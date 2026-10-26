-- Portable wild/static battle requests; native battle cleanup owns its lifetime.
local Ids = require("src.mods.UnifiedIds")
local Version = require("src.core.GameVersion")
local B = { ARITY = { start_battle = 4, static_battle = 4, check_battle_result = 5 } }
local outcomes = { win = true, lose = true, run = true, caught = true }
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
    if #row ~= 4 or row[2] ~= "wild" then
      return nil, "portable start_battle currently requires wild"
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
      local species = verb == "start_battle" and row[3] or row[2]
      local group, why = ids:resolve("pokemon", species)
      if not group or not (game.data.pokemon and game.data.pokemon[group.key]) then
        return nil, "row " .. i .. ": " .. (why or "unknown species")
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
