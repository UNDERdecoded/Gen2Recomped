-- tools/gen5_move_effects_check/main.lua
--
-- EVERY BLACK / WHITE MOVE, THROUGH THE REAL BATTLE ENGINE, BOTH WAYS ROUND.
--
-- The bug this exists for: a BW move record keeps its battle effect as the
-- cartridge's number and the engine dispatches on a name, so every BW status
-- move answered "But, it failed!" and every damaging move ran as a bare hit
-- (src/battle/Gen5MoveEffects.lua). This builds a wild 1v1 for each of the
-- 559 moves, once with the player's Pokemon using it and once with the
-- foe's, runs `BattleState:performMove` exactly as a turn does, and asserts
-- the OUTCOME CLASS the cartridge's own move record says it has:
--
--   damage      the target lost HP              status      the condition landed
--   stat        the stages moved as listed      confuse     the target is confused
--   flinch      the target will flinch           recoil      the user paid
--   drain/heal  the user got HP back             multi-hit   "Hit n time(s)!"
--   ...and a check of its own for every effect the fields cannot describe.
--
-- The battle's RNG answers its lowest value, so every chance lands (a 10% burn
-- burns) and nothing misses. Abilities are off except where a check is about
-- one. Then:
--   * the join to Platinum: BW's effect numbers are Gen 4's (needs a
--     Platinum cache, PT_DATA, default G:/Gen2Recomped/platinum/...);
--   * the ability and held-item hooks (Clear Body, Shield Dust, Serene Grace,
--     Inner Focus, Rock Head, Liquid Ooze, Sturdy, Own Tempo, Limber,
--     Contrary, Simple, Defiant, Pluck on a Sitrus Berry...);
--   * the text: no move effect may print the engine's English ("Enemy X",
--     "But, it failed!") -- the lines are the cartridge's banks;
--   * a coverage summary: moves whose effect is fully / partly / not done.
--
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/black/data/generated VERSION=black \
--     lovec tools/gen5_move_effects_check
--
-- Env: MOVES=1,45 (only these), VERBOSE=1 (every line printed), PT_DATA=<dir>.

local function env(k, d) local v = os.getenv(k) if v == nil or v == "" then return d end return v end

local results = { pass = 0, fail = 0, fails = {}, leaks = {} }
local function check(cond, what, detail)
  if cond then
    results.pass = results.pass + 1
  else
    results.fail = results.fail + 1
    results.fails[#results.fails + 1] = what .. (detail and (" -- " .. detail) or "")
  end
  return cond
end

local function main()
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(env("VERSION", "black"))
  local Data = require("src.core.Data")
  Data:load()
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local BattleState = require("src.battle.BattleState")
  local Game = require("src.core.Game")
  local G5 = require("src.battle.Gen5MoveEffects")
  local T = require("src.battle.Gen5BattleText")
  local TypeChart = require("src.battle.TypeChart")
  Game.data = Data
  Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
  Game.input = { wasPressed = function() return false end, isDown = function() return false end,
                 wasReleased = function() return false end }

  assert(G5.isBW(Data), "this cache is not Black / White's (no BW move records)")

  -- -------------------------------------------------------------------------
  -- 1. THE NUMBERING: BW's effect ids are Platinum's for every shared move
  -- -------------------------------------------------------------------------
  local ptDir = env("PT_DATA", "G:/Gen2Recomped/platinum/data/generated")
  local okPt, pt = pcall(dofile, ptDir .. "/moves.lua")
  if okPt and type(pt) == "table" then
    local byName = {}
    for _, m in pairs(pt) do
      if type(m) == "table" and m.name then byName[m.name:lower():gsub("[^a-z0-9]", "")] = m end
    end
    local joined, same, differ = 0, 0, {}
    for id = 1, 559 do
      local m = Data.moves[id]
      local p = m and byName[m.name:lower():gsub("[^a-z0-9]", "")]
      if p and p.gen4Effect then
        joined = joined + 1
        local bwEffect = m.bwEffect or m.effect
        if bwEffect == p.gen4Effect then same = same + 1 else differ[#differ + 1] = m.name .. " " .. p.gen4Effect .. "->" .. tostring(bwEffect) end
      end
    end
    print(("[join] %d BW moves join Platinum's by name; %d keep Platinum's effect number; differ: %s")
      :format(joined, same, table.concat(differ, ", ")))
    check(joined >= 460, "the join to Platinum reaches every Gen 4 move", tostring(joined))
    check(#differ == 2, "only Growth and Tail Glow changed their effect number", table.concat(differ, ", "))
  else
    print("[join] no Platinum cache at " .. ptDir .. " -- numbering check skipped")
  end

  G5.prepare(Data)
  TypeChart.load(Data)

  -- -------------------------------------------------------------------------
  -- 2. EVERY MOVE
  -- -------------------------------------------------------------------------
  local POOL = { 506, 519, 524, 535, 546, 532, 562, 554, 595, 559, 527 }
  local STATUS_IMMUNE = { BRN = { FIRE = true }, FRZ = { ICE = true }, PSN = { POISON = true, STEEL = true } }
  local function typesOf(sp) local d = Data.pokemon[sp] return d and d.types or {} end
  local function pickDefender(m)
    for _, sp in ipairs(POOL) do
      local types = typesOf(sp)
      local ok = TypeChart.effectiveness(m.type, types) > 0
      local st = G5.CONDITION[m.condition or 0]
      for _, t in ipairs(types) do
        if st and STATUS_IMMUNE[st] and STATUS_IMMUNE[st][t] then ok = false end
        if m.bwEffect == 84 and t == "GRASS" then ok = false end
        if (m.bwEffect == 67 or m.bwEffect == 6) and t == "GROUND" then ok = false end
      end
      if ok then return sp end
    end
    return POOL[1]
  end

  local function bigHP(b)
    b.mon.stats.hp = 999
    b.mon.hp = 999
  end
  local function fresh(playerSp, foeSp)
    Game.save.party = { Pokemon.new(Data, playerSp, 50), Pokemon.new(Data, 498, 50) }
    local b = BattleState.newWild(Game, foeSp, 50)
    b.rng = function(a) return a end
    b.bwAutoSwitch = true
    for _, x in ipairs({ b.player, b.enemy }) do
      x.abilityOverride = false
      x.mon.item = nil
      x.mon.status = nil
      bigHP(x)
    end
    b.turnCount = 1
    return b
  end

  local function snap(x)
    local s = { hp = x.mon.hp, status = x.mon.status, stages = {} }
    for k, v in pairs(x.stages or {}) do s.stages[k] = v end
    return s
  end

  local function linesOf(b)
    local out = {}
    for _, item in ipairs(b.queue) do
      if type(item.text) == "string" and item.text ~= "" then out[#out + 1] = T.translate(b, item.text) end
    end
    return out
  end

  -- per effect: setup(env) before, check(env) -> ok, why after
  local S = {}
  local function lastMoveSetup(e)
    e.t.lastMove = 33
    e.t.curMoves = { { id = 33, pp = 30 }, { id = 45, pp = 30 } }
    e.b.bw.lastMoveUsed = 33
  end
  local function flag(get) return function(e) return get(e) ~= nil and get(e) ~= false end end
  local function failsLine(e) return e.lines[#e.lines] == T.std(e.b, "failed") end

  S[8] = { setup = function(e) e.t.mon.status = "SLP" end }                          -- Dream Eater
  S[92] = { setup = function(e) e.u.mon.status = "SLP" end }                         -- Snore
  S[97] = { setup = function(e) e.u.mon.status = "SLP"; e.u.curMoves = { { id = e.m.id, pp = 10 }, { id = 33, pp = 10 } } end,
            check = function(e) return #e.lines > 0 and not failsLine(e) end }
  S[161] = { setup = function(e) e.u.stockpile = 1 end }                             -- Spit Up
  S[162] = { setup = function(e) e.u.stockpile = 1; e.u.mon.hp = 300 end,
             check = function(e) return e.u.mon.hp > 300 end }
  S[89] = { setup = function(e) e.u.bwHit = { by = e.t, damage = 20, turn = 1, physical = true } end }
  S[144] = { setup = function(e) e.u.bwHit = { by = e.t, damage = 20, turn = 1, physical = false } end }
  S[227] = { setup = function(e) e.u.bwHit = { by = e.t, damage = 20, turn = 1, physical = true } end }
  S[189] = { setup = function(e) e.u.mon.hp = 10 end }                                -- Endeavor
  S[320] = { check = function(e) return e.u.mon.hp == 0 and e.t.mon.hp < 999 end }    -- Final Gambit
  S[7] = { check = function(e) return e.u.mon.hp == 0 end }                           -- Explosion
  S[100] = { setup = lastMoveSetup, check = function(e) return e.t.curMoves[1].pp < 30 end }
  S[86] = { setup = lastMoveSetup, check = flag(function(e) return e.t.disabledSlot end) }
  S[90] = { setup = lastMoveSetup, check = flag(function(e) return e.t.encoreTurns end) }
  S[9] = { setup = lastMoveSetup, check = function(e) return e.t.mon.hp < 999 end }  -- Mirror Move -> Tackle
  S[242] = { setup = lastMoveSetup, check = function(e) return e.t.mon.hp < 999 end } -- Copycat -> Tackle
  S[93] = { setup = lastMoveSetup, check = function(e) return e.u.curTypes and e.u.curTypes[1] ~= "GRASS" end }
  S[107] = { setup = function(e) e.t.mon.status = "SLP" end, check = flag(function(e) return e.t.nightmare end) }
  S[234] = { setup = function(e) e.u.mon.status = "BRN" end, check = function(e) return e.t.mon.status == "BRN" and not e.u.mon.status end }
  S[193] = { setup = function(e) e.u.mon.status = "PSN" end, check = function(e) return not e.u.mon.status end }
  S[102] = { setup = function(e) e.u.mon.status = "PAR" end, check = function(e) return not e.u.mon.status end }
  S[184] = { setup = function(e) e.u.lastConsumedItem = 155 end, check = function(e) return e.u.mon.item == 155 end }
  S[222] = { setup = function(e) e.u.mon.item = 149 end, check = function(e) return e.t.mon.hp < 999 and not e.u.mon.item end }
  S[233] = { setup = function(e) e.u.mon.item = 55 end, check = function(e) return e.t.mon.hp < 999 and not e.u.mon.item end }
  S[177] = { setup = function(e) e.u.mon.item = 155 end, check = function(e) return e.t.mon.item == 155 end }
  S[323] = { setup = function(e) e.u.mon.item = 155 end, check = function(e) return e.t.mon.item == 155 and not e.u.mon.item end }
  S[224] = { setup = function(e) e.t.mon.item = 158; e.u.mon.hp = 300 end,       -- Pluck: a Sitrus Berry
             check = function(e) return not e.t.mon.item and e.u.mon.hp > 300 end }
  S[314] = { setup = function(e) e.t.mon.item = 158 end, check = function(e) return not e.t.mon.item end }
  S[105] = { setup = function(e) e.t.mon.item = 155 end, check = function(e) return e.u.mon.item == 155 end }
  S[188] = { setup = function(e) e.t.mon.item = 155 end, check = function(e) return not e.t.mon.item end }
  S[317] = {}                                                                           -- Acrobatics
  local function genders(e) e.u.mon.gender, e.t.mon.gender = "male", "female" end
  S[120] = { setup = genders, check = flag(function(e) return e.t.infatuated end) }
  S[265] = { setup = genders }
  S[292] = { setup = function(e) e.t.curTypes = { e.u.curTypes[1] } end }              -- Synchronoise
  -- Sucker Punch: the target has chosen Tackle this turn
  S[248] = { setup = function(e) e.t.bwChoice = { action = { id = 33, pp = 35 }, turn = 1 } end }
  S[246] = { setup = function(e)                                                        -- Last Resort
    e.u.curMoves = { { id = e.m.id, pp = 5 }, { id = 33, pp = 5 } }
    e.u.bwUsedMoves = { [33] = true }
  end }
  S[26] = { check = flag(function(e) return e.u.bideTurns end) }
  -- (the damage is worked out when it lands: Gen5MoveRules keeps the pending hit)
  S[148] = { check = function(e)
    local fut = e.b.bw.future
    return fut ~= nil and fut[e.t.isPlayer and 1 or 2] ~= nil
  end }
  S[27] = { check = function(e) return e.t.mon.hp < 999 and (e.u.thrashTurns or 0) > 0 end }
  S[25] = { setup = function(e) e.u.stages.attack = 2 e.t.stages.defense = -1 end,
            check = function(e) return next(e.u.stages) == nil and next(e.t.stages) == nil end }
  S[143] = { setup = function(e) e.t.stages.attack = 2 end, check = function(e) return e.u.stages.attack == 2 end }
  S[243] = { setup = function(e) e.t.stages.attack = 2 end, check = function(e) return e.u.stages.attack == 2 end }
  S[244] = { setup = function(e) e.t.stages.defense = 2 end, check = function(e) return e.u.stages.defense == 2 end }
  S[250] = { setup = function(e) e.t.stages.speed = 2 end, check = function(e) return e.u.stages.speed == 2 end }
  S[279] = { check = function(e) return e.u.curStats.defense == e.t.curStats.defense end }
  S[280] = { check = function(e) return e.u.curStats.attack == e.t.curStats.attack end }
  S[238] = { setup = function(e) e.before.atk, e.before.def = e.u.curStats.attack, e.u.curStats.defense end,
             check = function(e) return e.u.curStats.attack == e.before.def and e.u.curStats.defense == e.before.atk end }
  S[294] = { check = function(e) return e.t.curTypes[1] == "WATER" and #e.t.curTypes == 1 end }
  S[318] = { check = function(e) return e.u.curTypes[1] == e.t.curTypes[1] end }
  S[30] = { setup = function(e) e.u.curMoves = { { id = e.m.id, pp = 5 }, { id = 33, pp = 5 } } end,
            check = function(e) return e.u.curTypes[1] == "NORMAL" end }
  S[213] = { check = function(e) return e.u.curTypes[1] == "NORMAL" end }
  local function abilities(e) e.u.abilityOverride, e.t.abilityOverride = "OVERGROW", "BLAZE" end
  S[191] = { setup = abilities, check = function(e) return e.u.abilityOverride == "BLAZE" end }
  S[178] = { setup = abilities, check = function(e) return e.u.abilityOverride == "BLAZE" end }
  S[239] = { setup = abilities, check = function(e) return e.t.abilityOverride == false end }
  S[247] = { setup = abilities, check = function(e) return e.t.abilityOverride == "INSOMNIA" end }
  S[298] = { setup = abilities, check = function(e) return e.t.abilityOverride == "SIMPLE" end }
  S[299] = { setup = abilities, check = function(e) return e.t.abilityOverride == "OVERGROW" end }
  S[57] = { check = flag(function(e) return e.u.bwTransformed end) }
  S[95] = { setup = function(e) lastMoveSetup(e); e.u.curMoves = { { id = e.m.id, pp = 1 } } end,
            check = function(e) return e.u.curMoves[1].id == 33 end }
  S[82] = { check = function() return true end }                       -- Mimic: the engine's own flow
  S[83] = { check = function(e) return #e.lines > 0 end }                -- Metronome
  S[180] = { check = function(e) return #e.lines > 0 end }               -- Assist
  S[173] = { check = function(e) return e.t.mon.hp < 999 end }           -- Nature Power -> Earthquake
  -- Me First: the target has chosen Tackle; the user uses it first
  S[241] = { setup = function(e) e.t.bwChoice = { action = { id = 33, pp = 35 }, turn = 1 } end,
             check = function(e) return e.t.mon.hp < 999 end }
  -- Mimic (Gen V): the target's last move, at its own full PP
  S[82] = { setup = function(e)
              e.t.lastMove = 33
              e.u.curMoves = { { id = e.m.id, pp = 10 } }
            end,
            check = function(e) return e.u.curMoves[1].id == 33 and e.u.curMoves[1].pp == 35 end }
  S[307] = { check = failsLine }                                        -- Ally Switch (single)
  S[85] = { check = function(e) return e.lines[#e.lines] == T.std(e.b, "nothingHappened") end }
  S[28] = { check = function(e) return e.b.result == "run" end }         -- Roar in a wild battle
  S[313] = { check = function(e) return e.t.mon.hp < 999 and e.b.result == "run" end }
  S[153] = { check = function(e) return e.b.result == "run" end }        -- Teleport
  local function switched(e) return e.b.player ~= e.u end
  S[127] = { check = function(e) if e.u.isPlayer then return switched(e) end return failsLine(e) end }
  S[228] = { check = function(e) if e.u.isPlayer then return switched(e) end return e.t.mon.hp < 999 end }
  S[220] = { check = function(e) if e.u.isPlayer then return e.u.mon.hp == 0 end return failsLine(e) end }
  S[270] = S[220]
  S[168] = { check = function(e) return e.u.mon.hp == 0 and (e.t.stages.attack or 0) == -2 end }
  S[172] = { check = failsLine }; S[176] = { check = failsLine }; S[307] = { check = failsLine }
  S[300] = { check = function(e) return not failsLine(e) end }
  S[315] = S[300]
  S[37] = { setup = function(e) e.u.mon.hp = 300 end, check = function(e) return e.u.mon.status == "SLP" and e.u.mon.hp == 999 end }
  S[32] = { setup = function(e) e.u.mon.hp = 300 end, check = function(e) return e.u.mon.hp > 300 end }
  S[214] = S[32]
  S[132] = S[32]
  S[309] = { setup = function(e) e.t.mon.hp = 300 end, check = function(e) return e.t.mon.hp > 300 end }
  S[142] = { check = function(e) return e.u.stages.attack == 6 end }
  S[109] = { check = function(e) return e.u.stages.attack == 1 and e.u.stages.speed == -1 end }
  S[79] = { check = flag(function(e) return e.u.substituteHP end) }
  S[47] = { check = flag(function(e) return e.u.focusEnergy end) }
  S[111] = { check = flag(function(e) return e.u.protecting end) }
  S[116] = { check = flag(function(e) return e.u.enduring end) }
  local function side(e, who, key) return e.b.bw.sides[(who and who.isPlayer) and 1 or 2][key] end
  S[306] = { check = function(e) return side(e, e.u, "quickGuard") ~= nil end }
  S[278] = { check = function(e) return side(e, e.u, "wideGuard") ~= nil end }
  S[35] = { check = function(e) return side(e, e.u, "lightScreen") ~= nil and e.u.lightScreen end }
  S[65] = { check = function(e) return side(e, e.u, "reflect") ~= nil and e.u.reflect end }
  S[46] = { check = function(e) return side(e, e.u, "mist") ~= nil end }
  S[225] = { check = function(e) return side(e, e.u, "tailwind") ~= nil and e.u.bwSpeedMultiplier == 2 end }
  S[240] = { check = function(e) return side(e, e.u, "luckyChant") ~= nil end }
  S[124] = { check = flag(function(e) return e.u.safeguardTurns end) }
  S[112] = { check = function(e) return side(e, e.t, "spikes") == 1 end }
  S[249] = { check = function(e) return side(e, e.t, "toxicSpikes") == 1 end }
  S[266] = { check = function(e) return side(e, e.t, "stealthRock") == true end }
  S[258] = { check = function(e) return e.t.stages.evasion == -1 end }
  S[215] = { check = function(e) return (e.b.bw.field.gravity or 0) > 0 end }
  S[281] = { check = function(e) return (e.b.bw.field.wonderRoom or 0) > 0 end }
  S[286] = { check = function(e) return (e.b.bw.field.magicRoom or 0) > 0 end }
  S[259] = { check = function(e) return (e.b.field.trickRoom or 0) > 0 end }
  local Weather = require("src.battle.Weather")
  S[115] = { check = function(e) return Weather.current(e.b) == Weather.SANDSTORM end }
  S[136] = { check = function(e) return Weather.current(e.b) == Weather.RAIN end }
  S[137] = { check = function(e) return Weather.current(e.b) == Weather.SUN end }
  S[164] = { check = function(e) return Weather.current(e.b) == Weather.HAIL end }
  S[201] = { check = function(e) return e.b.field.mudSport ~= nil end }
  S[210] = { check = function(e) return e.b.field.waterSport ~= nil end }
  S[251] = { check = flag(function(e) return e.u.bwAquaRing end) }
  S[252] = { check = flag(function(e) return e.u.bwMagnetRise end) }
  S[181] = { check = flag(function(e) return e.u.ingrained end) }
  S[179] = { check = flag(function(e) return e.u.wishTurns end) }
  S[98] = { check = flag(function(e) return e.u.destinyBond end) }
  S[194] = { check = flag(function(e) return e.u.grudge end) }
  S[160] = { check = function(e) return e.u.stockpile == 1 and e.u.stages.defense == 1 end }
  S[226] = { check = function(e) for _, v in pairs(e.u.stages) do if v == 2 then return true end end return false end }
  S[308] = { check = function(e) return e.u.stages.attack == 2 and e.u.stages.defense == -1 end }
  S[183] = { check = flag(function(e) return e.u.bwMagicCoat end) }
  S[195] = { check = flag(function(e) return e.u.bwSnatch end) }
  S[192] = { check = flag(function(e) return e.u.bwImprison end) }
  S[175] = { check = flag(function(e) return e.t.tauntTurns end) }
  S[165] = { check = flag(function(e) return e.t.tormented end) }
  S[187] = { check = flag(function(e) return e.t.drowsyTurns end) }
  S[113] = { check = flag(function(e) return e.t.identified end) }
  S[216] = S[113]
  S[94] = { check = function(e) return e.u.lockedOn == e.t end }
  S[106] = { check = flag(function(e) return e.t.trapped end) }
  S[114] = { check = flag(function(e) return e.t.perishTurns end) }
  S[232] = { check = flag(function(e) return e.t.bwEmbargo end) }
  S[236] = { check = flag(function(e) return e.t.bwHealBlock end) }
  S[285] = { check = flag(function(e) return e.t.bwTelekinesis end) }
  S[84] = { check = flag(function(e) return e.t.leechSeeded end) }
  S[91] = { setup = function(e) e.u.mon.hp = 100 end, check = function(e) return e.u.mon.hp > 100 end }
  S[42] = { check = function(e) return e.t.bwBound ~= nil end }
  S[261] = S[42]
  S[287] = { check = function(e) return e.t.bwGrounded == true end }
  S[304] = { setup = function(e) e.t.stages.attack = 2 end, check = function(e) return next(e.t.stages) == nil end }
  S[155] = { charge = true }; S[255] = S[155]; S[256] = S[155]; S[263] = S[155]; S[272] = S[155]
  S[311] = S[155]; S[39] = S[155]; S[75] = S[155]; S[145] = S[155]; S[151] = S[155]; S[331] = S[155]
  S[332] = S[155]
  S[29] = { multi = true }; S[44] = S[29]; S[77] = S[29]; S[104] = S[29]; S[154] = S[29]
  -- Beat Up hits once per able party member: the wild foe has a party of one
  S[154] = { check = function(e)
    if not e.u.isPlayer then return e.t.mon.hp < 999 end
    for _, l in ipairs(e.lines) do if l:find("time", 1, true) then return true end end
    return false
  end }
  -- Hidden Power's type is the IVs' (all 31: Dark, 70)
  S[135] = { setup = function(e)
    e.u.mon.ivs = { hp = 31, attack = 31, defense = 31, speed = 31, spatk = 31, spdef = 31 }
  end, check = function(e) return e.t.mon.hp < 999 end }
  S[80] = { check = function(e) return e.t.mon.hp < 999 and e.u.mustRecharge end }
  S[158] = {}
  S[34] = { check = function(e) return (e.b.payDay or 0) > 0 end }
  S[81] = { check = flag(function(e) return e.u.bwRage end) }
  S[159] = { check = function(e) return e.t.mon.hp < 999 and e.u.uproarTurns end }
  S[38] = { check = function(e) return e.t.mon.hp == 0 end }               -- OHKO (same level)
  S[40] = { check = function(e) return e.t.mon.hp == 500 end }             -- Super Fang: half of 999
  S[41] = { check = function(e) return e.t.mon.hp == 959 end }             -- Dragon Rage: 40
  S[130] = { check = function(e) return e.t.mon.hp == 979 end }            -- SonicBoom: 20
  S[87] = { check = function(e) return e.t.mon.hp == 949 end }             -- Seismic Toss: level 50
  S[254] = { check = function(e) return e.t.mon.hp < 999 and e.u.mon.hp < 999 end }

  local tested, perEffect = 0, {}
  local only = {}
  for id in tostring(env("MOVES", "")):gmatch("%d+") do only[tonumber(id)] = true end
  local verbose = env("VERBOSE") ~= nil

  local function runOne(m, playerSide)
    local defSp = pickDefender(m)
    local atkSp = 495
    local b = playerSide and fresh(atkSp, defSp) or fresh(defSp, atkSp)
    local u, t = (playerSide and b.player or b.enemy), (playerSide and b.enemy or b.player)
    local e = { b = b, u = u, t = t, m = m, before = {} }
    local spec = S[m.bwEffect] or {}
    -- the self-healers and drainers start hurt, so the gain is visible
    if (m.recoil or 0) > 0 or m.effectClass == 3 then u.mon.hp = 300 end
    if spec.setup then spec.setup(e) end
    e.before.u, e.before.t = snap(u), snap(t)
    b.queue, b.nextInsert = {}, 0
    local inst = { id = m.id, pp = 10 }
    local ok, err = pcall(b.performMove, b, u, t, inst)
    if ok and spec.charge and u.charging then
      b.turnCount = 2
      b.nextInsert = #b.queue
      ok, err = pcall(b.performMove, b, u, t, u.charging)
    end
    e.lines = linesOf(b)
    local what = ("%3d %-13s %s"):format(m.id, m.name, playerSide and "player" or "foe   ")
    if not ok then
      check(false, what, "raised: " .. tostring(err):sub(1, 200))
      return false
    end
    local fails = {}
    local function need(cond, why) if not cond then fails[#fails + 1] = why end end
    local cls = m.effectClass
    if spec.check then
      need(spec.check(e), "effect check")
    elseif (m.power or 0) > 0 then
      need(t.mon.hp < e.before.t.hp, "target took no damage")
      local cond = m.condition or 0
      if cls == 4 and cond >= 1 and cond <= 5 and (m.conditionChance or 0) > 0 and m.bwEffect ~= 267 then
        need(t.mon.status == G5.CONDITION[cond], "no " .. tostring(G5.CONDITION[cond]))
        if m.bwEffect == 202 then need(t.toxicCounter ~= nil, "not badly poisoned") end
      elseif cls == 4 and cond == 6 and (m.conditionChance or 0) > 0 then
        need(t.confusedTurns ~= nil, "not confused")
      end
      if cls == 6 then
        for _, row in ipairs(G5.statList(m)) do
          need((t.stages[row[1]] or 0) == row[2], "target " .. row[1] .. " not " .. row[2])
        end
      elseif cls == 7 then
        for _, row in ipairs(G5.statList(m)) do
          need((u.stages[row[1]] or 0) == row[2], "user " .. row[1] .. " not " .. row[2])
        end
      end
      if (m.flinch or 0) > 0 and m.bwEffect ~= 158 then need(t.flinched == true, "no flinch") end
      if (m.recoil or 0) < 0 then need(u.mon.hp < e.before.u.hp, "no recoil") end
      if (m.recoil or 0) > 0 then need(u.mon.hp > e.before.u.hp, "no drain") end
      if spec.multi or (m.hitsMax or 0) > 1 then
        local hit = false
        for _, l in ipairs(e.lines) do if l:find("time", 1, true) then hit = true end end
        need(hit, "no hit count line")
      end
    elseif cls == 2 then
      local tg = tonumber(m.target)
      local subject = (tg == 7 or tg == 1 or tg == 12) and u or t
      for _, row in ipairs(G5.statList(m)) do
        need((subject.stages[row[1]] or 0) == row[2], row[1] .. " not " .. row[2])
      end
    elseif cls == 1 then
      local st = G5.CONDITION[m.condition or 0]
      if st then
        need(t.mon.status == st, "no " .. st)
        if m.bwEffect == 33 then need(t.toxicCounter ~= nil, "not badly poisoned") end
      elseif m.condition == 6 then
        need(t.confusedTurns ~= nil, "not confused")
      else
        need(not failsLine(e), "failed")
      end
    elseif cls == 5 then
      need(t.confusedTurns ~= nil, "not confused")
      for _, row in ipairs(G5.statList(m)) do
        need((t.stages[row[1]] or 0) == row[2], row[1] .. " not " .. row[2])
      end
    elseif cls == 3 then
      need(u.mon.hp > e.before.u.hp, "no heal")
    else
      need(#e.lines > 0 and not failsLine(e), "no effect (failed)")
    end
    -- THE TEXT: nothing the engine wrote for Kanto
    for _, l in ipairs(e.lines) do
      if l:find("Enemy ", 1, true) or l:find("But, it failed", 1, true) then
        results.leaks[#results.leaks + 1] = what .. ": " .. l:gsub("\n", " ")
      end
    end
    if verbose then
      print(what .. "  " .. table.concat(e.lines, " | "):gsub("\n", " "))
    end
    return check(#fails == 0, what, table.concat(fails, "; ") .. " :: " .. table.concat(e.lines, " | "):gsub("\n", " "))
  end

  for id = 1, 559 do
    local m = Data.moves[id]
    if m and (next(only) == nil or only[id]) then
      tested = tested + 1
      local a = runOne(m, true)
      local c = runOne(m, false)
      local row = perEffect[m.bwEffect] or { moves = {}, ok = true }
      row.moves[#row.moves + 1] = m.name
      row.ok = row.ok and a and c
      perEffect[m.bwEffect] = row
    end
  end

  -- -------------------------------------------------------------------------
  -- 3. THE ABILITY AND HELD-ITEM HOOKS
  -- -------------------------------------------------------------------------
  local function scenario(name, moveId, setup, verify, rngFn)
    local m = Data.moves[moveId]
    local b = fresh(495, pickDefender(m))
    if rngFn then b.rng = rngFn end
    local e = { b = b, u = b.player, t = b.enemy, m = m, before = {} }
    if setup then setup(e) end
    e.before.u, e.before.t = snap(e.u), snap(e.t)
    b.queue, b.nextInsert = {}, 0
    local ok, err = pcall(b.performMove, b, e.u, e.t, { id = moveId, pp = 10 })
    e.lines = linesOf(b)
    if verbose then print("[hook] " .. name .. "  " .. table.concat(e.lines, " | "):gsub("\n", " ")) end
    check(ok and verify(e), "[hook] " .. name, (not ok) and tostring(err) or table.concat(e.lines, " | "):gsub("\n", " "))
  end
  local function ab(who, name) return function(e) e[who].abilityOverride = name end end
  scenario("Clear Body refuses Growl", 45, ab("t", "CLEAR_BODY"), function(e) return (e.t.stages.attack or 0) == 0 end)
  scenario("Hyper Cutter refuses Growl", 45, ab("t", "HYPER_CUTTER"), function(e) return (e.t.stages.attack or 0) == 0 end)
  scenario("Contrary turns Growl around", 45, ab("t", "CONTRARY"), function(e) return e.t.stages.attack == 1 end)
  scenario("Simple doubles Swords Dance", 14, ab("u", "SIMPLE"), function(e) return e.u.stages.attack == 4 end)
  scenario("Defiant answers Leer with Attack", 43, ab("t", "DEFIANT"), function(e) return e.t.stages.attack == 2 end)
  scenario("Shield Dust refuses Ember's burn", 52, ab("t", "SHIELD_DUST"), function(e) return e.t.mon.status == nil end)
  scenario("Inner Focus refuses Bite's flinch", 44, ab("t", "INNER_FOCUS"), function(e) return not e.t.flinched end)
  scenario("Rock Head pays no recoil", 36, ab("u", "ROCK_HEAD"), function(e) return e.u.mon.hp == e.before.u.hp end)
  scenario("Liquid Ooze hurts the drainer", 71, function(e) e.t.abilityOverride = "LIQUID_OOZE" end,
           function(e) return e.u.mon.hp < e.before.u.hp end)
  scenario("Sturdy refuses Fissure", 90, ab("t", "STURDY"), function(e) return e.t.mon.hp == 999 end)
  scenario("Own Tempo refuses Supersonic", 48, ab("t", "OWN_TEMPO"), function(e) return not e.t.confusedTurns end)
  scenario("Limber refuses Thunder Wave", 86, ab("t", "LIMBER"), function(e) return e.t.mon.status == nil end)
  scenario("Insomnia refuses Hypnosis", 95, ab("t", "INSOMNIA"), function(e) return e.t.mon.status == nil end)
  scenario("Serene Grace doubles Ember's 10%", 52, ab("u", "SERENE_GRACE"),
           function(e) return e.t.mon.status == "BRN" end,
           function(a, b2) if a == 0 and b2 == 99 then return 15 end return a end)
  scenario("...and without it a 15 misses the 10%", 52, nil,
           function(e) return e.t.mon.status == nil end,
           function(a, b2) if a == 0 and b2 == 99 then return 15 end return a end)
  scenario("Safeguard refuses Toxic", 92, function(e) e.t.safeguardTurns = 5 end, function(e) return e.t.mon.status == nil end)
  scenario("a Substitute stops Growl", 45, function(e) e.t.substituteHP = 50 end, function(e) return (e.t.stages.attack or 0) == 0 end)
  scenario("Mist stops Growl", 45, function(e) e.t.mist = true; e.b.bw.sides[2].mist = 5 end, function(e) return (e.t.stages.attack or 0) == 0 end)
  scenario("Protect stops Growl", 45, function(e) e.t.protecting = true end, function(e) return (e.t.stages.attack or 0) == 0 end)
  scenario("Magic Coat bounces Growl", 45, function(e) e.t.bwMagicCoat = 1 end, function(e) return e.u.stages.attack == -1 end)
  scenario("Pluck eats an Oran Berry", 365, function(e) e.t.mon.item = 155; e.u.mon.hp = 500 end,
           function(e) return e.u.mon.hp == 510 end)
  scenario("Acrobatics doubles with no item", 512, nil, function(e) return e.t.mon.hp < 999 end)
  scenario("Thunder Wave misses a Ground type", 86, function(e) e.t.curTypes = { "GROUND" } end,
           function(e) return e.t.mon.status == nil end)
  scenario("Poison Powder on a Steel type", 77, function(e) e.t.curTypes = { "STEEL" } end,
           function(e) return e.t.mon.status == nil end)

  -- -------------------------------------------------------------------------
  -- 3b. THE TURN-LEVEL RULES (src/battle/Gen5MoveRules.lua): locks, Pursuit,
  --     Future Sight, Beat Up, doubles, Nature Power, Imprison, Gravity,
  --     Sucker Punch, the rooms, Telekinesis, Sky Drop, Me First, the thaw
  -- -------------------------------------------------------------------------
  local R = require("src.battle.Gen5MoveRules")
  local function rule(name, fn)
    local ok, good, why = pcall(fn)
    if not ok then return check(false, "[rule] " .. name, tostring(good)) end
    if verbose then print("[rule] " .. name .. " -> " .. tostring(good) .. " " .. tostring(why or "")) end
    return check(good, "[rule] " .. name, why)
  end
  local function drain(b)
    local guard = 0
    while #b.queue > 0 and guard < 400 do
      local item = table.remove(b.queue, 1)
      b.nextInsert = 0
      if item.fn then item.fn() end
      guard = guard + 1
    end
  end
  local function said(b, want)
    for _, l in ipairs(linesOf(b)) do if l == want then return true end end
    return false
  end
  local function use(b, u, t, id, inst)
    inst = inst or { id = id, pp = 10 }
    b:performMove(u, t, inst)
    return inst
  end
  local function freshDouble()
    Game.save.party = { Pokemon.new(Data, 495, 50), Pokemon.new(Data, 498, 50), Pokemon.new(Data, 501, 50) }
    local b = BattleState.newWild(Game, 506, 50)
    b:makeWildDouble(Pokemon.new(Data, 504, 50))
    b.rng = function(a) return a end
    b.bwAutoSwitch = true
    for pos = 0, 3 do
      local x = b:battlerAt(pos)
      if x then
        x.abilityOverride = false
        x.mon.item, x.mon.status = nil, nil
        bigHP(x)
      end
    end
    b.turnCount = 1
    b.queue, b.nextInsert = {}, 0
    return b
  end

  rule("Rollout locks its user in and doubles each turn", function()
    local b = fresh(495, 506)
    local inst = { id = 205, pp = 20 }
    b.queue, b.nextInsert = {}, 0
    use(b, b.player, b.enemy, 205, inst)
    local d1 = 999 - b.enemy.mon.hp
    local locked = b:menuLockedAction(b.player) == inst
    b.turnCount = 2
    local hp = b.enemy.mon.hp
    use(b, b.player, b.enemy, 205, inst)
    local d2 = hp - b.enemy.mon.hp
    return locked and d2 > d1 * 1.6 and inst.pp == 19, ("d1=%d d2=%d pp=%d"):format(d1, d2, inst.pp)
  end)
  rule("Rollout's run ends after five hits (lock released, power back to base)", function()
    local b = fresh(495, 506)
    local inst = { id = 205, pp = 20 }
    for t = 1, 5 do b.turnCount = t; b.enemy.mon.hp = 999; use(b, b.player, b.enemy, 205, inst) end
    return b:menuLockedAction(b.player) == nil and b.player.bwRoll == nil
  end)
  rule("Rollout stops when a turn passes without it (the end-of-turn rule)", function()
    local b = fresh(495, 506)
    local inst = { id = 205, pp = 20 }
    use(b, b.player, b.enemy, 205, inst)
    b.turnCount = 2
    R.upkeep(b)
    return b:menuLockedAction(b.player) == nil
  end)
  rule("Uproar: three turns, locked in, the sleeper wakes (bank 14 #706)", function()
    local b = fresh(495, 506)
    b.enemy.mon.status = "SLP"
    local inst = { id = 253, pp = 10 }
    use(b, b.player, b.enemy, 253, inst)
    local woke = b.enemy.mon.status == nil and said(b, T.set(b, 706, b.enemy))
    b:gen3CountersTick(); R.upkeep(b)
    local lockedAfter1 = b:menuLockedAction(b.player) == inst
    b.turnCount = 2; use(b, b.player, b.enemy, 253, inst); b:gen3CountersTick(); R.upkeep(b)
    b.turnCount = 3; use(b, b.player, b.enemy, 253, inst); b:gen3CountersTick(); R.upkeep(b)
    local free = b:menuLockedAction(b.player) == nil and not b.player.uproarTurns
    return woke and lockedAfter1 and free and inst.pp == 9, ("woke=%s l1=%s free=%s pp=%d"):format(
      tostring(woke), tostring(lockedAfter1), tostring(free), inst.pp)
  end)
  rule("Pursuit lands on a switching player Pokemon first, at double power", function()
    local b = fresh(495, 506)
    b.enemy.curMoves = { { id = 228, pp = 20 } }
    b.enemyAction = function() return b.enemy.curMoves[1] end
    local leaving = b.player
    local base = select(1, b:computeDamage(b.enemy, leaving, Data.moves[228], { rng = b.rng }))
    b.queue, b.nextInsert = {}, 0
    b:resolveSwitch(Game.save.party[2])
    drain(b)
    local took = 999 - leaving.mon.hp
    -- double POWER is not double damage: base = floor((X + 2) * k), the
    -- doubled hit floor((2X + 2) * k) with k = 2 * 85/100 here (crit, low
    -- roll), so it can sit up to 4 under twice the single hit; -2 flaked on
    -- the random IVs Pokemon.new rolls (battle parity pass, 2026-11-02)
    return b.player ~= leaving and took >= base * 2 - 4, ("took %d, single hit %d"):format(took, base or -1)
  end)
  rule("Pursuit goes before a trainer's switch (the turn order)", function()
    local b = fresh(495, 506)
    local sw = { special = "aiSwitch", index = 2 }
    local order = { { b.enemy, b.player, sw }, { b.player, b.enemy, { id = 228, pp = 20 } } }
    order = R.arrange(b, order)
    return order[1][1] == b.player and b.enemy.switchingOut == true
  end)
  rule("Future Sight's damage is worked out when it lands, two turns later", function()
    local b = fresh(495, 506)
    use(b, b.player, b.enemy, 248)
    local hp0 = b.enemy.mon.hp
    b.player.curStats.spatk = b.player.curStats.spatk * 4
    b.turnCount = 2; R.upkeep(b)
    local early = b.enemy.mon.hp == hp0
    b.turnCount = 3; R.upkeep(b)
    local mid = b.enemy.mon.hp == hp0
    b.turnCount = 4; R.upkeep(b)
    local landed = b.enemy.mon.hp < hp0 and said(b, T.set(b, "tookAttack", b.enemy, { nil, Data.moves[248].name }))
    return early and mid and landed, ("hp %d -> %d"):format(hp0, b.enemy.mon.hp)
  end)
  rule("Beat Up strikes once per able party member at 5 + base Attack / 10", function()
    local b = fresh(495, 506)
    Game.save.party[3] = Pokemon.new(Data, 501, 50)
    use(b, b.player, b.enemy, 251)
    return said(b, T.std(b, "hitTimes", { count = 3 })), table.concat(linesOf(b), " | ")
  end)
  rule("Beat Up skips a statused party member", function()
    local b = fresh(495, 506)
    Game.save.party[2].status = "PSN"
    use(b, b.player, b.enemy, 251)
    return said(b, T.std(b, "hitTimes", { count = 1 })), table.concat(linesOf(b), " | ")
  end)
  rule("[doubles] Surf hits both foes and the partner, Growl both foes", function()
    local b = freshDouble()
    local T5 = require("src.battle.Targeting")
    local surf = T5.resolve(b, b:battlerAt(0), Data.moves[57], nil)
    local growl = T5.resolve(b, b:battlerAt(0), Data.moves[45], nil)
    return #surf == 3 and #growl == 2, ("surf %d growl %d"):format(#surf, #growl)
  end)
  rule("[doubles] Follow Me draws the player's single-target move", function()
    local b = freshDouble()
    local left, right = b:battlerAt(1), b:battlerAt(3)
    b:executeAction(right, b:battlerAt(0), { id = 266, pp = 20 })
    b.chosenTargets = { [0] = left }
    b:executeAction(b:battlerAt(0), left, { id = 33, pp = 35 })
    return left.mon.hp == 999 and right.mon.hp < 999 and said(b, T.set(b, "centerOfAttention", right)),
      ("left %d right %d"):format(left.mon.hp, right.mon.hp)
  end)
  rule("[doubles] Rage Powder does the same", function()
    local b = freshDouble()
    local left, right = b:battlerAt(1), b:battlerAt(3)
    b:executeAction(right, b:battlerAt(0), { id = 476, pp = 20 })
    b.chosenTargets = { [0] = left }
    b:executeAction(b:battlerAt(0), left, { id = 33, pp = 35 })
    return left.mon.hp == 999 and right.mon.hp < 999
  end)
  rule("[doubles] Follow Me does not draw a move from its own side", function()
    local b = freshDouble()
    b:executeAction(b:battlerAt(2), b:battlerAt(1), { id = 266, pp = 20 })
    return R.centerOfAttention(b, b:battlerAt(0), Data.moves[33]) == nil
  end)
  rule("[doubles] Ally Switch swaps the two places (bank 14 #1137)", function()
    local b = freshDouble()
    local a, c = b:battlerAt(0), b:battlerAt(2)
    b:executeAction(a, b:battlerAt(1), { id = 502, pp = 15 })
    return b:battlerAt(0) == c and b:battlerAt(2) == a and b.player == c
           and said(b, T.set(b, 1137, a, { nil, c.name }))
  end)
  rule("[doubles] Helping Hand powers the partner", function()
    local b = freshDouble()
    b:executeAction(b:battlerAt(2), b:battlerAt(1), { id = 270, pp = 20 })
    return b:battlerAt(0).bwHelped == b.turnCount
  end)
  rule("Nature Power by the terrain: grass -> Seed Bomb, water -> Hydro Pump, indoors -> Tri Attack", function()
    local out = {}
    for terrain, want in pairs({ grass = 402, water = 56, building = 161, plain = 89, cave = 157 }) do
      local b = fresh(495, 506)
      b.gen5Terrain = terrain
      use(b, b.player, b.enemy, 267)
      local got = said(b, T.used(b, b.player, want))
      if not got then out[#out + 1] = terrain end
    end
    return #out == 0, table.concat(out, ",")
  end)
  rule("Imprison seals the move for the foe (menu #589, and its action)", function()
    local b = fresh(495, 506)
    b.player.curMoves = { { id = 33, pp = 35 }, { id = 286, pp = 10 } }
    use(b, b.player, b.enemy, 286)
    local line = R.moveBlocked(b, b.enemy, Data.moves[33], true)
    b.queue, b.nextInsert = {}, 0
    local hp = b.player.mon.hp
    b:executeAction(b.enemy, b.player, { id = 33, pp = 35 })
    return line == T.set(b, 589, b.enemy, { nil, Data.moves[33].name }) and b.player.mon.hp == hp
  end)
  rule("Gravity: Earthquake hits a Flying type, accuracy x5/3, Fly refused (#1086)", function()
    local b = fresh(495, 506)
    use(b, b.player, b.enemy, 356)
    b.enemy.curTypes = { "FLYING" }
    local hp = b.enemy.mon.hp
    use(b, b.player, b.enemy, 89)
    local quake = b.enemy.mon.hp < hp
    -- a 50% move rolls 70 of 0..255: 127 needed, 212 under Gravity
    b.rng = function(a, z) if z == 255 then return 180 end return a end
    local hit = b:accuracyRoll(Data.moves[95], b.player, b.enemy)
    local fly = R.moveBlocked(b, b.player, Data.moves[19], true)
    return quake and hit and fly == T.set(b, 1086, b.player, { nil, Data.moves[19].name }),
      ("quake=%s hit=%s fly=%s"):format(tostring(quake), tostring(hit), tostring(fly))
  end)
  rule("Gravity brings a Pokemon down out of the air (#1083)", function()
    local b = fresh(495, 506)
    b.enemy.curTypes = { "FLYING" }
    b.enemy.bwMagnetRise = 3
    use(b, b.player, b.enemy, 356)
    return b.enemy.bwMagnetRise == nil and b.enemy.bwGrounded and said(b, T.set(b, 1083, b.enemy))
  end)
  rule("Sucker Punch fails against a status move", function()
    local b = fresh(495, 506)
    b.enemy.bwChoice = { action = { id = 45, pp = 40 }, turn = 1 }
    use(b, b.player, b.enemy, 389)
    return b.enemy.mon.hp == 999
  end)
  rule("Wonder Room swaps Defense and Sp. Def (a special hit on a high-Def foe hurts less)", function()
    local b = fresh(495, 506)
    b.enemy.curStats.defense, b.enemy.curStats.spdef = 300, 30
    local before = select(1, require("src.battle.Gen5MoveEffects").damage(
      { battle = b, user = b.player, target = b.enemy, move = Data.moves[94] }, {}))
    b.bw.field.wonderRoom = 5
    local after = select(1, require("src.battle.Gen5MoveEffects").damage(
      { battle = b, user = b.player, target = b.enemy, move = Data.moves[94] }, {}))
    return after < before, ("%d -> %d"):format(before, after)
  end)
  rule("Magic Room: Leftovers do nothing, Fling fails", function()
    local b = fresh(495, 506)
    b.bw.field.magicRoom = 5
    b.player.mon.item = 234
    b.player.mon.hp = 500
    b:holdItemTrigger(b.player, "turn")
    local hp = b.player.mon.hp
    use(b, b.player, b.enemy, 374)
    return hp == 500 and b.enemy.mon.hp == 999 and b.player.mon.item == 234
  end)
  rule("Telekinesis: every move hits the lifted target", function()
    local b = fresh(495, 506)
    use(b, b.enemy, b.player, 477)
    b.rng = function(a, z) if z == 255 then return 255 end return a end
    return b.player.bwTelekinesis ~= nil and b:accuracyRoll(Data.moves[95], b.enemy, b.player) == true
  end)
  rule("Sky Drop lifts the target, which cannot move, then drops it", function()
    local b = fresh(495, 506)
    local inst = { id = 507, pp = 10 }
    use(b, b.player, b.enemy, 507, inst)
    local up = b.enemy.bwSkyDropped == b.player and b.enemy.invulnerable and b.player.invulnerable
                and said(b, T.pair(b, "skyDrop", b.player, b.enemy))
    local held = b:menuLockedAction(b.enemy)
    local hp = b.player.mon.hp
    b:executeAction(b.enemy, b.player, { id = 33, pp = 35 })
    local stayed = b.player.mon.hp == hp
    b.turnCount = 2
    b:performMove(b.player, b.enemy, b:menuLockedAction(b.player))
    local dropped = b.enemy.mon.hp < 999 and not b.enemy.bwSkyDropped and not b.enemy.invulnerable
    return up and held and held.special == "bwHeld" and stayed and dropped,
      ("up=%s stayed=%s dropped=%s"):format(tostring(up), tostring(stayed), tostring(dropped))
  end)
  rule("Sky Drop fails on a 200 kg target", function()
    local b = fresh(495, 506)
    b.enemy.def = setmetatable({ weight = 2100 }, { __index = b.enemy.def })
    use(b, b.player, b.enemy, 507)
    return b.enemy.bwSkyDropped == nil and not b.player.charging
  end)
  rule("Me First uses the target's chosen move first, at x1.5", function()
    local b = fresh(495, 506)
    local plain = select(1, require("src.battle.Gen5MoveEffects").damage(
      { battle = b, user = b.player, target = b.enemy, move = Data.moves[33] }, {}))
    b.enemy.bwChoice = { action = { id = 33, pp = 35 }, turn = 1 }
    use(b, b.player, b.enemy, 382)
    local took = 999 - b.enemy.mon.hp
    return said(b, T.used(b, b.player, 33)) and took >= math.floor(plain * 1.4), ("plain %d took %d"):format(plain, took)
  end)
  rule("Me First fails once the target has moved", function()
    local b = fresh(495, 506)
    b.enemy.bwChoice = { action = { id = 33, pp = 35 }, turn = 1 }
    b.enemy.bwMovedTurn = 1
    use(b, b.player, b.enemy, 382)
    return b.enemy.mon.hp == 999
  end)
  for _, id in ipairs({ 172, 221, 394, 503, 558 }) do
    rule(("the thaw flag: a frozen user's %s melts the ice (#303)"):format(Data.moves[id].name), function()
      local b = fresh(495, 506)
      b.player.mon.status = "FRZ"
      b.rng = function(a, z) if z == 4 or z == 5 then return z end return a end
      b:executeAction(b.player, b.enemy, { id = id, pp = 10 })
      return b.player.mon.status == nil and said(b, T.set(b, 303, b.player, { nil, Data.moves[id].name }))
             and b.enemy.mon.hp < 999, table.concat(linesOf(b), " | ")
    end)
  end
  rule("...and a move without the flag stays frozen", function()
    local b = fresh(495, 506)
    b.player.mon.status = "FRZ"
    b.rng = function(a, z) if z == 4 or z == 5 then return z end return a end
    b:executeAction(b.player, b.enemy, { id = 33, pp = 35 })
    return b.player.mon.status == "FRZ" and b.enemy.mon.hp == 999
  end)
  rule("Mimic leaves with its user: the slot is Mimic again, its PP back", function()
    local b = fresh(495, 506)
    local slot = { id = 102, pp = 10 }
    b.player.curMoves = { slot }
    b.enemy.lastMove = 33
    use(b, b.player, b.enemy, 102, slot)
    local copied = slot.id == 33 and slot.pp == 35
    b:restoreMimicked(b.player)
    return copied and slot.id == 102 and slot.pp == 9
  end)

  -- -------------------------------------------------------------------------
  -- 4. THE TEXT, against the banks themselves
  -- -------------------------------------------------------------------------
  do
    local m = Data.moves[45]
    local b = fresh(495, 506)
    b.queue, b.nextInsert = {}, 0
    b:performMove(b.player, b.enemy, { id = 45, pp = 10 })
    local lines = linesOf(b)
    local want = Data.text["TEXT_G5S_0014_00091"]:gsub("{VAR1}", b.enemy.name)
    local got = false
    for _, l in ipairs(lines) do if l == want then got = true end end
    check(got, "[text] Growl on a wild Pokemon prints btl_set 91", table.concat(lines, " | "))
    local usedWant = Data.text["TEXT_G5S_0013_00135"]:gsub("{VAR1}", b.player.name)
    local usedGot = false
    for _, l in ipairs(lines) do if l == usedWant then usedGot = true end end
    check(usedGot, "[text] \"used Growl!\" is bank 13 line 135", table.concat(lines, " | "))
  end

  -- -------------------------------------------------------------------------
  -- 5. COVERAGE
  -- -------------------------------------------------------------------------
  local counts, partial, missing = { full = 0, partial = 0, missing = 0 }, {}, {}
  local ids = {}
  for e in pairs(perEffect) do ids[#ids + 1] = e end
  table.sort(ids)
  local movesFull, movesPartial, movesMissing = 0, 0, 0
  for _, e in ipairs(ids) do
    local row = perEffect[e]
    local status, note = G5.coverage(e)
    if status == "generic" then status = "full" end
    if not row.ok and status == "full" then status = "partial"; note = "a check failed" end
    counts[status] = (counts[status] or 0) + 1
    if status == "full" then movesFull = movesFull + #row.moves
    elseif status == "partial" then movesPartial = movesPartial + #row.moves
      partial[#partial + 1] = ("  effect %3d %s: %s"):format(e, table.concat(row.moves, ", "), note or "")
    else movesMissing = movesMissing + #row.moves
      missing[#missing + 1] = ("  effect %3d %s: %s"):format(e, table.concat(row.moves, ", "), note or "")
    end
  end
  print(("[coverage] %d moves, %d effect ids: %d full (%d moves), %d partial (%d moves), %d missing (%d moves)")
    :format(tested, #ids, counts.full, movesFull, counts.partial, movesPartial, counts.missing or 0, movesMissing))
  if #partial > 0 then print("[coverage] partial:") for _, l in ipairs(partial) do print(l) end end
  if #missing > 0 then print("[coverage] missing:") for _, l in ipairs(missing) do print(l) end end
  if #results.leaks > 0 then
    print(("[text] %d lines still in the engine's English:"):format(#results.leaks))
    for i = 1, math.min(40, #results.leaks) do print("  " .. results.leaks[i]) end
  end
  for _, f in ipairs(results.fails) do print("FAIL " .. f) end
  print(("[result] %d passed, %d failed"):format(results.pass, results.fail))
  return results.fail == 0
end

function love.load()
  local ok, res = xpcall(main, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(res)) end
  love.event.quit((ok and res) and 0 or 1)
end

function love.draw() end
