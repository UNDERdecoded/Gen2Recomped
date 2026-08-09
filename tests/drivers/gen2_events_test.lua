-- Event/flag extraction audit, driven by the Slowpoke Well report: after the
-- Rockets were beaten nothing happened, because (a) trainer group 66 (GRUNTF)
-- never extracted so the fourth Rocket had no party, and (b) the ROM's
-- after-battle script -- the one that clears the well and walks Kurt in --
-- was extracted but never run.
local U = dofile("tests/drivers/util.lua")

return function(game)
  U.newGame(game)
  U.wait(20)
  local data = game.data
  local pass, fail = 0, 0
  local function check(cond, label)
    if cond then pass = pass + 1 else fail = fail + 1 end
    U.log((cond and "PASS " or "FAIL ") .. label)
  end

  -- ---------------------------------------------------- trainer classes
  local romGroups = {}
  for _, def in pairs(data.trainers or {}) do
    if def.source == "ROM:TrainerGroups" and def.index then
      romGroups[def.index] = def
    end
  end
  local missing = {}
  for group = 1, 66 do
    if not romGroups[group] then missing[#missing + 1] = group end
  end
  check(#missing == 0,
    "every TrainerGroups class extracted (missing: "
    .. (#missing > 0 and table.concat(missing, ",") or "none") .. ")")
  local gruntF = romGroups[66]
  check(gruntF and #gruntF.parties == 5,
    "GRUNTF has its 5 parties (" .. tostring(gruntF and #gruntF.parties) .. ")")

  -- Every trainer object must either resolve to a real party or -- like the
  -- rival, whose team is picked from your starter at runtime -- fall back to
  -- its own talk script.  An object that has neither is a dead NPC.
  local pool = data.map_scripts
  local orphans, trainers = 0, 0
  local seen, dead = {}, {}
  for mapId, mapDef in pairs(data.maps or {}) do
    -- data.maps is aliased under several spellings; the script pool only
    -- carries the canonical id
    local entry = pool and pool.maps and pool.maps[mapDef.id or mapId]
    for _, obj in ipairs(mapDef.objects or {}) do
      if obj.trainerObject and not seen[obj.id] then
        local def = obj.trainerClass and data.trainers[obj.trainerClass]
        local party = def and def.parties and def.parties[obj.trainerParty]
        local script = entry and entry.objects and entry.objects[obj.index]
        if party or script then
          seen[obj.id] = true
          trainers = trainers + 1
          dead[obj.id] = nil
        elseif dead[obj.id] == nil then
          dead[obj.id] = mapId
        end
      end
    end
  end
  for id, mapId in pairs(dead) do
    orphans = orphans + 1
    trainers = trainers + 1
    U.log("  dead trainer " .. mapId .. " " .. id)
  end
  check(trainers > 300, "the maps carry their trainer objects (" .. trainers .. ")")
  check(orphans == 0, "no trainer object is left dead (" .. orphans .. ")")

  -- ------------------------------------------------------ Slowpoke Well
  local well = data.maps.SLOWPOKE_WELL_B1_F
  check(well ~= nil, "SLOWPOKE_WELL_B1_F exists")
  local rockets = 0
  for _, obj in ipairs(well and well.objects or {}) do
    if obj.trainerObject then rockets = rockets + 1 end
  end
  check(rockets == 4, "the well holds four Rockets (" .. rockets .. ")")
  for i = 1, 4 do
    local header = data:trainerHeader("SLOWPOKE_WELL_B1_F", i)
    check(header ~= nil and header.event ~= nil,
      "Rocket " .. i .. " has a header with its beat event")
  end

  -- ------------------------------------------- the after-battle scripts
  local VM = require("src.script.Gen2ScriptVM")
  local boss = VM.afterBattleRows(data, "SLOWPOKE_WELL_B1_F", 2)
  check(boss ~= nil, "the well boss has an after-battle script")
  local ops = {}
  for _, row in ipairs(boss or {}) do ops[row[1]] = (ops[row[1]] or 0) + 1 end
  check((ops.g2_object or 0) >= 4, "it clears the four Rockets off the map")
  check(ops.g2_warp ~= nil, "it warps the player out of the well")
  check(ops.set_flag ~= nil and ops.clear_flag ~= nil,
    "it moves the story event flags")
  check(ops.g2_endifjustbattled == nil,
    "the boss script runs straight after the battle")

  local grunt = VM.afterBattleRows(data, "SLOWPOKE_WELL_B1_F", 1)
  check(grunt ~= nil, "a plain Rocket has an after-battle script")
  local guard = false
  for _, row in ipairs(grunt or {}) do
    if row[1] == "g2_endifjustbattled" then guard = true break end
    if row[1] == "show_text" then break end
  end
  check(guard, "a plain Rocket's script is guarded by endifjustbattled")

  -- the guard has to actually stop the script
  local Commands = require("src.script.Commands")
  check(Commands.g2_endifjustbattled({ justBattled = true }) == "end",
    "endifjustbattled ends a run that came from a battle")
  check(Commands.g2_endifjustbattled({}) == nil,
    "endifjustbattled falls through when the player talked")

  -- ------------------------------------ after-battle scripts game-wide
  local withAfter, compiled = 0, 0
  for mapId, entry in pairs(pool and pool.maps or {}) do
    for objIndex in pairs(entry.objectAfter or {}) do
      withAfter = withAfter + 1
      if VM.afterBattleRows(data, mapId, objIndex) then compiled = compiled + 1 end
    end
  end
  check(withAfter > 200,
    "the extractor kept every trainer's after-battle script (" .. withAfter .. ")")
  check(compiled == withAfter,
    "all of them compile (" .. compiled .. "/" .. withAfter .. ")")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
