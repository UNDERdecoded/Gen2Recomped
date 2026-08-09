-- Shiny Pokemon, and the red Gyarados of the Lake of Rage.
--
-- On the Game Boy Color a shiny mon is nothing but a palette: every species
-- row in PokemonPalettes (02:$6D3D) is EIGHT bytes -- normal colour 1,
-- normal colour 2, shiny colour 1, shiny colour 2 -- and
-- GetMonNormalOrShinyPalettePointer (02:$5C66) adds 4 to the row when
-- CheckShininess (02:$5040) passes.  CheckShininess wants
--     Defense DV == 10, Speed DV == 10, Special DV == 10,
--     Attack DV with bit 1 set (2, 3, 6, 7, 10, 11, 14, 15)
-- which is 1 in 8192 of a random roll.
--
-- RedGyarados (49:$4F6F) is
--     cry GYARADOS / loadwildmon GYARADOS, 30 / loadvar 3, 7 / startbattle
-- where var 3 is wBattleType ($D119) and 7 is BATTLETYPE_SHINY.  LoadEnemyMon
-- .InitDVs sees that byte and writes ATKDEFDV_SHINY ($EA) / SPDSPCDV_SHINY
-- ($AA) instead of rolling -- Attack 14, Defense 10, Speed 10, Special 10.
-- The port dropped `loadvar` on the floor during lowering, so the Lake of
-- Rage Gyarados rolled ordinary DVs and came out blue.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local Stats = require("src.pokemon.Stats")
  local Pokemon = require("src.pokemon.Pokemon")
  local Commands = require("src.script.Commands")
  local PaletteFX = require("src.render.PaletteFX")
  local VM = require("src.script.Gen2ScriptVM")

  -- 1. CheckShininess, byte for byte -------------------------------------
  ok(Stats.isShiny({ attack = 14, defense = 10, speed = 10, special = 10 }),
     "ATKDEFDV_SHINY/SPDSPCDV_SHINY is shiny")
  for _, atk in ipairs({ 2, 3, 6, 7, 10, 11, 14, 15 }) do
    ok(Stats.isShiny({ attack = atk, defense = 10, speed = 10, special = 10 }),
       ("Attack DV %d is shiny"):format(atk))
  end
  for _, atk in ipairs({ 0, 1, 4, 5, 8, 9, 12, 13 }) do
    ok(not Stats.isShiny({ attack = atk, defense = 10, speed = 10, special = 10 }),
       ("Attack DV %d is not shiny"):format(atk))
  end
  ok(not Stats.isShiny({ attack = 14, defense = 9, speed = 10, special = 10 }),
     "Defense 9 is not shiny")
  ok(not Stats.isShiny({ attack = 14, defense = 10, speed = 11, special = 10 }),
     "Speed 11 is not shiny")
  ok(not Stats.isShiny({ attack = 14, defense = 10, speed = 10, special = 0 }),
     "Special 0 is not shiny")
  ok(not Stats.isShiny(nil), "no DVs is not shiny")

  -- 2. forceShiny writes the ROM's fixed pair, and recalculates ----------
  local mon = Pokemon.new(game.data, "SPECIES_130", 30)
  Pokemon.forceShiny(game.data, mon)
  ok(mon.dvs.attack == 14 and mon.dvs.defense == 10
     and mon.dvs.speed == 10 and mon.dvs.special == 10,
     "forceShiny writes $EA / $AA")
  ok(mon.dvs.hp == 0, "the derived HP DV of all-even DVs is 0")
  ok(Pokemon.isShiny(mon), "a forced mon reads back as shiny")
  local expect = Stats.calc(game.data.pokemon.SPECIES_130, 30, mon.dvs)
  ok(mon.stats.hp == expect.hp and mon.stats.attack == expect.attack,
     "stats were recalculated from the new DVs")
  ok(mon.hp == mon.stats.hp, "...and it comes in at full health")

  -- 3. the species really carries a distinct shiny palette ---------------
  local def = game.data.pokemon.SPECIES_130
  ok(def.shinyPalette == "MON_SPECIES_130_SHINY",
     "GYARADOS carries a shinyPalette name")
  local pals = game.data.palettes and game.data.palettes.palettes
  ok(pals and pals[def.palette], "the normal palette was extracted")
  ok(pals and pals[def.shinyPalette], "the shiny palette was extracted")
  local normal = PaletteFX.monPal(game.data, "SPECIES_130")
  local shiny = PaletteFX.monPal(game.data, "SPECIES_130", nil, true)
  ok(normal and shiny, "both resolve through monPal")
  local differs = false
  for i = 1, 4 do
    local a, b = normal[i], shiny[i]
    for c = 1, 3 do if a[c] ~= b[c] then differs = true end end
  end
  ok(differs, "the shiny palette is not the normal one")
  -- the ROM's shiny Gyarados pair is red; the normal one is blue.  Colour 2
  -- is the body shade in both, so red > blue shiny and blue > red normal.
  ok(shiny[3][1] > shiny[3][3], "the shiny GYARADOS body is red")
  ok(normal[3][3] > normal[3][1], "the normal GYARADOS body is blue")
  ok(PaletteFX.monPalName(game.data, "SPECIES_130", nil, true) == def.shinyPalette,
     "the cache key follows the shiny palette")
  ok(PaletteFX.monPalName(game.data, "SPECIES_130") ~= def.shinyPalette,
     "...and a normal mon keeps its own key")
  ok(PaletteFX.monPal(game.data, "SPECIES_130", true, true)
     ~= PaletteFX.monPal(game.data, "SPECIES_130", nil, true),
     "TRANSFORMED still beats shiny (DeterminePaletteID checks it first)")

  -- 4. loadvar 3, 7 survives lowering ------------------------------------
  local rows = VM.compile(game.data, "S49_4F6F")
  ok(type(rows) == "table" and #rows > 0, "RedGyarados compiles")
  local loadvar, wild, battle = nil, nil, false
  for i, row in ipairs(rows) do
    if row[1] == "g2_loadvar" then loadvar = { row[2], row[3], i } end
    if row[1] == "g2_load_wild" then wild = { row[2], row[3], i } end
    if row[1] == "g2_start_battle" then battle = i end
  end
  ok(loadvar and loadvar[1] == 3 and loadvar[2] == 7,
     "RedGyarados lowers `loadvar 3, 7` (wBattleType = BATTLETYPE_SHINY)")
  ok(wild and wild[1] == "SPECIES_130" and wild[2] == 30,
     "...beside `loadwildmon GYARADOS, 30`")
  ok(loadvar and battle and loadvar[3] < battle,
     "...and it lands before the startbattle")

  -- 5. the command sets the battle type, and startbattle consumes it -----
  local ctx = { game = game, save = game.save }
  Commands.g2_loadvar(ctx, 3, 7)
  ok(ctx.g2BattleType == 7, "g2_loadvar writes wBattleType")
  Commands.g2_loadvar(ctx, 9, 7)
  ok(ctx.g2BattleType == 7, "an unmodelled var writes nothing")

  local seen
  local realStart = Commands.start_battle
  Commands.start_battle = function(c, kind, a, b, opts)
    seen = { kind = kind, a = a, b = b, opts = opts }
    c.lastBattleResult = "win"
    c.lastCheck = true
  end
  ctx.g2Wild = { species = "SPECIES_130", level = 30 }
  ctx.g2BattleType = 7
  Commands.g2_start_battle(ctx)
  ok(seen and seen.opts and seen.opts.shiny == true,
     "startbattle after BATTLETYPE_SHINY forces a shiny wild mon")
  ok(ctx.g2BattleType == nil,
     "wBattleType is cleared with the rest of the battle variables")

  seen = nil
  ctx.g2Wild = { species = "SPECIES_130", level = 30 }
  Commands.g2_start_battle(ctx)
  ok(seen and seen.opts and seen.opts.shiny == false,
     "the NEXT battle is an ordinary one")
  Commands.start_battle = realStart

  -- 6. end to end: the battle the script builds is red -------------------
  local BattleState = require("src.battle.BattleState")
  local red = BattleState.newWild(game, "SPECIES_130", 30, { shiny = true })
  ok(Pokemon.isShiny(red.enemy.mon), "newWild{shiny} makes a shiny GYARADOS")
  ok(red.enemy.mon.level == 30, "...at level 30")
  local plain = BattleState.newWild(game, "SPECIES_130", 30)
  ok(not (plain.enemy.mon.dvs.defense == 10 and plain.enemy.mon.dvs.speed == 10
          and plain.enemy.mon.dvs.special == 10 and plain.enemy.mon.dvs.attack % 4 >= 2),
     "an ordinary GYARADOS is (almost certainly) not shiny")

  -- 7. a random roll still lands on the ROM's 1-in-8192 -------------------
  local hits, trials = 0, 200000
  local rng = love.math.random
  for _ = 1, trials do
    if Stats.isShiny(Stats.randomDVs(rng)) then hits = hits + 1 end
  end
  -- 200k rolls at 1/8192 averages ~24; anything in 5..60 is comfortably the
  -- right order of magnitude and nowhere near "never" or "always"
  ok(hits >= 5 and hits <= 60,
     ("random DVs are shiny about 1 in 8192 (%d hits in %d)"):format(hits, trials))

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
