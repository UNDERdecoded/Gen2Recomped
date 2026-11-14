-- End-to-end check: BattleState.buildTrainerParty builds every Gen 4 trainer
-- party with the cartridge's personality (TrainerData_BuildParty).
--   CACHE=<cache> POKEPORT_VERSION=renegadeplatinum \
--   POKEPORT_DATA_DIR=<cache>/data/generated POKEPORT_ASSET_ROOT=<cache> \
--     "C:/Program Files/LOVE/lovec.exe" tools/gen4_trainer_personality_check
-- (version defaults to platinum).  Verifies for every party slot of every
-- trainer: personality == Gen4TrainerPersonality, nature = pid % 25, ability
-- slot first, gender from the low byte, never shiny, IVs = ivScale*31/255,
-- stats recomputed from those IVs and that nature, and two builds agree.
local function out(fmt, ...) io.stdout:write(fmt:format(...), "\n"); io.stdout:flush() end

function love.load()
  local ok, err = xpcall(function()
    local version = os.getenv("POKEPORT_VERSION") or "platinum"
    require("src.core.GameVersion").set(version)
    local Data = require("src.core.Data")
    Data:load()
    assert(Data.isGen4Cache, "not a Gen 4 cache")
    local Game = require("src.core.Game")
    Game.data = Data
    local BattleState = require("src.battle.BattleState")
    local P = require("src.battle.Gen4TrainerPersonality")
    local Pokemon = require("src.pokemon.Pokemon")
    local Stats = require("src.pokemon.Stats")
    local Forms = require("src.pokemon.Gen4Forms")
    local order = Data.constants.natureOrder
    local fails, mons, tox = {}, 0, 0
    local function fail(m) if #fails < 20 then fails[#fails + 1] = m end end
    for id = 1, 4000 do
      local rec = Data.trainers[id]
      if rec and rec.parties and rec.parties[1] and rec.class then
        local a = BattleState.buildTrainerParty(Game, id, 1, rec.parties[1])
        local b = BattleState.buildTrainerParty(Game, id, 1, rec.parties[1])
        for i, slot in ipairs(rec.parties[1]) do
          local m, m2 = a[i], b[i]
          mons = mons + 1
          local tag = ("trainer %d slot %d"):format(id, i)
          local pid = P.personality(id, rec.class, slot)
          if m.personality ~= pid then fail(tag .. " personality") end
          if m2.personality ~= pid then fail(tag .. " not deterministic") end
          if m.nature ~= order[(pid % 25) + 1] then fail(tag .. " nature") end
          if m.abilitySlot ~= 1 then fail(tag .. " ability slot " .. tostring(m.abilitySlot)) end
          if Pokemon.isShiny(m) or m.shiny then fail(tag .. " shiny") end
          local def = Forms.definition(Data, m)
          local iv = P.iv(slot)
          if m.ivs.hp ~= iv or m.ivs.spdef ~= iv then fail(tag .. " ivs") end
          local want = Stats.calc(def, m.level, m.ivs, nil, m.evs, m.nature)
          for k, v in pairs(want) do if m.stats[k] ~= v then fail(tag .. " stat " .. k) end end
          if m.hp ~= m.stats.hp then fail(tag .. " hp") end
          local g = Pokemon.genderOf(Data, m)
          local ratio = def.genderRatio
          local exp = (ratio == 255 and "none") or (ratio == 0 and "male") or (ratio == 254 and "female")
            or ((ratio > pid % 256) and "female" or "male")
          if g ~= exp then fail(tag .. " gender " .. tostring(g) .. " want " .. exp) end
          if version == "renegadeplatinum" and slot.species == 454 then
            tox = tox + 1
            local AbilityOf = require("src.pokemon.AbilityOf")
            if AbilityOf.pick(m, def.abilities) ~= "DRY_SKIN" then fail(tag .. " Toxicroak not Dry Skin") end
          end
        end
      end
    end
    out("%s: %d trainer mons, %d renegade toxicroak, %d failures", version, mons, tox, #fails)
    for _, m in ipairs(fails) do out("  FAIL %s", m) end
    love.event.quit(#fails > 0 and 1 or 0)
  end, debug.traceback)
  if not ok then out("CHECK FAILED:\n%s", tostring(err)); love.event.quit(2) end
end
function love.draw() end
