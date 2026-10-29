-- Portable wild/static battle requests; native battle cleanup owns its lifetime.
local Ids = require("src.mods.UnifiedIds")
local Version = require("src.core.GameVersion")
local B = { ARITY = { start_battle = 4, static_battle = 4, check_battle_result = 5 } }
local outcomes = { win = true, lose = true, run = true, caught = true }
local function integer(n, lo, hi)
  return type(n) == "number" and n == n and n >= lo and n <= hi and n % 1 == 0
end
function B.trainer(game, reference, member)
  local gen = Version.generation()
  local rows = game.data.trainers or {}
  local key, found
  if type(reference) == "number" then
    if gen == 3 then
      key = game.data.constants
        and game.data.constants.trainerOrder
        and game.data.constants.trainerOrder[reference]
    else
      for id, row in pairs(rows) do
        if type(row) == "table" and row.index == reference then
          local candidateKey = row.id and rows[row.id] and row.id or id
          local candidate = rows[candidateKey]
          if candidate.index ~= reference then
            return nil, "inconsistent trainer alias"
          end
          if found and found ~= candidate then
            return nil, "ambiguous trainer class"
          end
          key, found = candidateKey, candidate
        end
      end
    end
  else
    key = reference
  end
  local row = key and rows[key]
  local party = member or 1
  if gen == 3 and party ~= 1 then
    return nil, "Gen3 trainer has one party"
  end
  local roster = row and row.parties and row.parties[party]
  if type(roster) ~= "table" or #roster == 0 or #roster > 6 then
    return nil, "trainer content unavailable: " .. tostring(reference)
  end
  for _, mon in ipairs(roster) do
    if
      type(mon) ~= "table"
      or not integer(mon.level, 1, 100)
      or not (game.data.pokemon and game.data.pokemon[mon.species])
    then
      return nil, "invalid native trainer party"
    end
  end
  local nativeIndex = row and row.index
  if gen == 3 then
    local order = game.data.constants and game.data.constants.trainerOrder or {}
    nativeIndex = nil
    for index, id in pairs(order) do
      if id == key then
        if nativeIndex and nativeIndex ~= index then
          return nil, "ambiguous native trainer id"
        end
        nativeIndex = index
      end
    end
    local base = game.data.constants and game.data.constants.gen3TrainerFlagBase
    if
      not integer(nativeIndex, 1, 65535)
      or not integer(base, 0, 65535 - nativeIndex)
      or game.save.flags ~= nil and type(game.save.flags) ~= "table"
    then
      return nil, "native trainer flags unavailable"
    end
  end
  return { key = key, member = party, index = nativeIndex }
end
B.nativeTrainer = {
  resolve = B.trainer,
  construct = function(game, plan)
    return require("src.battle.BattleState").newTrainer(game, plan.key, plan.member)
  end,
  cleanup = function(game, world, plan, outcome)
    if Version.generation() == 3 and outcome == "win" then
      local ctx = { game = game, save = game.save, overworld = world }
      local commands = require("src.script.Gen3Commands")
      commands.markTrainerBeaten(ctx, plan.index)
      commands.registerTrainerInMatchCall(ctx, plan.index)
    end
  end,
}
function B.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable battles unavailable for this generation"
  end
  if verb == "check_battle_result" then
    if #row < 2 or #row > 5 then
      return nil, "invalid battle result list"
    end
    local out = { verb }
    for i = 2, #row do
      if not outcomes[row[i]] then
        return nil, "invalid battle result"
      end
      out[i] = row[i]
    end
    return out
  end
  local species, level = row[2], row[3]
  if verb == "start_battle" then
    if row[2] == "trainer" then
      if
        #row < 3
        or #row > 4
        or not (type(row[3]) == "string" and #row[3] > 0 and #row[3] <= 256 and not row[3]:find("%c") or integer(
          row[3],
          0,
          65535
        ))
        or row[4] ~= nil and not integer(row[4], 1, 255)
      then
        return nil, "invalid script trainer"
      end
      return { row[1], row[2], row[3], row[4] }
    end
    if #row ~= 4 or row[2] ~= "wild" then
      return nil, "invalid script battle"
    end
    species, level = row[3], row[4]
  elseif #row < 3 or #row > 4 then
    return nil, "invalid command arity"
  end
  if type(species) ~= "string" or #species == 0 or #species > 256 or species:find("%c") then
    return nil, "invalid species id"
  end
  if type(level) ~= "number" or level ~= level or level < 1 or level > 100 or level % 1 ~= 0 then
    return nil, "invalid battle level"
  end
  return { row[1], row[2], row[3], row[4] }
end
function B.prepare(loader, game, world, rows, flag)
  local ids = Ids.new(loader)
  local talking = world.talkNpc or world.runner and world.runner.ctx and world.runner.ctx.npc
  for i, row in ipairs(rows) do
    local verb = row[1]
    if verb == "warp" then
      talking = nil
    end
    if verb == "start_battle" or verb == "static_battle" then
      if verb == "start_battle" and row[2] == "trainer" then
        local plan, why = B.trainer(game, row[3], row[4])
        if not plan then
          return nil, "row " .. i .. ": " .. why
        end
      else
        local species = verb == "start_battle" and row[3] or row[2]
        local group, why = ids:resolve("pokemon", species)
        if not group or not (game.data.pokemon and game.data.pokemon[group.key]) then
          return nil, "row " .. i .. ": " .. (why or "unknown species")
        end
      end
      if type(world.pushBattle) ~= "function" or type(world.afterBattle) ~= "function" then
        return nil, "battle runtime unavailable"
      end
      if verb == "static_battle" and talking then
        local def = talking.def
        local ref = def and (def.name or def.localId or def.index or def.id)
        if ref then
          local edit, reason = require("src.mods.ScriptWorldEdits").prepare(
            game,
            world,
            "",
            { { "hide_object", world.map.id, ref } }
          )
          if not edit then
            return nil, "row " .. i .. ": " .. reason
          end
        end
      end
      if verb == "static_battle" and row[4] ~= nil then
        local value, reason = flag(row[4])
        if value == nil then
          return nil, "row " .. i .. ": " .. reason
        end
      end
    end
  end
  return true
end
B.outcomes = outcomes
return B
