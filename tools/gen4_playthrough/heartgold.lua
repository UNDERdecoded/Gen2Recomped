-- HEARTGOLD / SOULSILVER'S STORY, AS BEATS (tools/gen4_playthrough/runner.lua).
--
-- The vars and flags are pokeheartgold's (include/constants/vars.h, flags.h):
--   0x4106 VAR_SCENE_PLAYERS_HOUSE_1F   0x4108 VAR_SCENE_ELMS_LAB
--   0x4072 VAR_SCENE_NEW_BARK_TOWN_OW   0x408C VAR_SCENE_ROUTE_30_OW
--   0x4073 VAR_SCENE_CHERRYGROVE_CITY_OW
--   flags 0x9C GOT_POKEGEAR, 0x6A GOT_STARTER, 0x6B GOT_POKEDEX
-- Run:
--
--   INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold MAP=T20R0202 X=6 Y=6 \
--     FACING=down PLAYTHROUGH=heartgold TICKS=200000 love tools/gen4_hgss_overworld_harness

local B = {}

-- downstairs: Mom's frame-table scene (scr_seq_0845_T20R0201 000, run while
-- VAR_SCENE_PLAYERS_HOUSE_1F is 0): the Bag, Trainer Card, Save and Options
B[#B + 1] = { name = "mom downstairs",
  steps = { { "do", function(r) print("[hg] before: 0x4106=" .. tostring(r:var(0x4106))) end },
            { "warpto", "T20R0201" },
            { "do", function(r) print("[hg] arrived: 0x4106=" .. tostring(r:var(0x4106))) end },
            { "until", function(r) return r:var(0x4106) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4106) >= 1 end, why = "0x4106 >= 1 (Mom's scene)" }

-- Elm's lab (scr_seq_0843_T20R0101): his scene, the starter (VAR_SCENE_ELMS_LAB 1)
B[#B + 1] = { name = "elm's lab and the starter",
  -- New Bark's frame script (0x4106 == 1) has the neighbour lead the way
  -- (0x4106 -> 2); inside, the starter machine (bg 10 at (8,4), script 012:
  -- ChooseStarter) -- talking to Elm first only repeats "If a wild Pokémon
  -- appears", and row 10's trigger is "Where are you going?"
  steps = { { "warpto", "T20" },
            { "until", function(r) return r:var(0x4106) >= 2 end, 20000 },
            { "warpto", "T20R0101" }, { "walkto", 8, 5 }, { "face", "up" }, { "press", "a" },
            { "until", function(r) return r:flag(0x6A) end, 40000 } },
  expect = function(r) return r:flag(0x6A) and #r:party() >= 1 and r:var(0x4108) >= 1 end,
  why = "flag 0x6A, a starter, 0x4108 >= 1" }

-- leaving: the aide's Potions at the door (VAR_SCENE_ELMS_LAB 2)
B[#B + 1] = { name = "the aide's potions",
  steps = { { "activecoord" },
            { "until", function(r) return r:var(0x4108) >= 2 end, 20000 } },
  expect = function(r) return r:var(0x4108) >= 2 end, why = "0x4108 >= 2" }

-- Cherrygrove's guide (scr_seq_0850_T21 001, coord 1 at (54,13) while
-- VAR_SCENE_CHERRYGROVE_CITY_OW 0x4073 == 0): the tour, the Running Shoes
B[#B + 1] = { name = "cherrygrove guide",
  steps = { { "teleport", "T21", 57, 14, "left" }, { "activecoord" },
            { "until", function(r) return r:var(0x4073) >= 1 end, 40000 } },
  expect = function(r) return r:var(0x4073) >= 1 end, why = "0x4073 >= 1 (the tour)" }

-- Mr. Pokémon's house on Route 30 (scr_seq_0229_R30R0201): the Mystery Egg,
-- Oak and the Pokédex (VAR_SCENE_ELMS_LAB 3)
B[#B + 1] = { name = "mr. pokemon",
  steps = { { "teleport", "R30", 24, 7, "up" }, { "warpto", "R30R0201" },
            { "until", function(r) return r:var(0x4108) >= 3 end, 40000 } },
  expect = function(r) return r:var(0x4108) >= 3 and r:flag(0x6B) end, why = "0x4108 >= 3, flag 0x6B (Pokédex)" }

-- the rival on the way back (T21 003, coord 2 at (63,14) while 0x4073 == 3):
-- the battle, then 0x4073 = 4
B[#B + 1] = { name = "rival at cherrygrove",
  steps = { { "teleport", "T21", 60, 15, "right" }, { "activecoord" },
            { "until", function(r) return r:var(0x4073) >= 4 end, 60000 } },
  expect = function(r) return r:var(0x4073) >= 4 end, why = "0x4073 >= 4 (rival battle)" }

-- back at the lab (stage 3 -> 4): the stolen Pokémon, the officer, Elm's thanks
B[#B + 1] = { name = "back to elm",
  steps = { { "teleport", "T20", 12, 10, "up" }, { "warpto", "T20R0101" },
            { "until", function(r) return r:var(0x4108) >= 4 end, 40000 } },
  expect = function(r) return r:var(0x4108) >= 4 end, why = "0x4108 >= 4" }

-- A CHEAT, said as one: the lead is rebuilt at level 75 (healed) with Psychic so the runner's
-- A-mashing (the first move, every turn) wins the gym battles below. The
-- story is under test here, not the battles.
local trainMove, trainLevel, trainSpecies = 94, 75, nil
local function trainUp(r)
  local party = r:party()
  local lead = party[1]
  if not lead then return end
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(r.game.data, trainSpecies or lead.species, trainLevel)
  mon.nickname, mon.otName, mon.otId = lead.nickname, lead.otName, lead.otId
  -- ...and Psychic (94) first, with PP to spare: the runner always takes the
  -- first move, a status move first loops on "No PP left", and Body Slam
  -- loops on "It doesn't affect" against the rival's Gastly
  mon.moves = mon.moves or {}
  table.insert(mon.moves, 1, { id = trainMove, pp = 64 })
  while #mon.moves > 4 do table.remove(mon.moves) end
  party[1] = mon
end

-- ...with another first move: Steel resists Psychic (Jasmine's team)
local function trainUpWith(move, level, species)
  return function(r)
    trainMove, trainLevel, trainSpecies = move, level or 75, species
    trainUp(r)
    trainMove, trainLevel, trainSpecies = 94, 75, nil
  end
end

-- Sprout Tower 3F (scr_seq_0018_D15R0103): Elder Li (person 3), TM70 Flash
-- (flag 0x76)
B[#B + 1] = { name = "sprout tower elder li",
  steps = { { "do", trainUp }, { "teleport", "D15R0103", 15, 26, "up" }, { "talk", 3 },
            { "until", function(r) return r:flag(0x76) end, 60000 } },
  expect = function(r) return r:flag(0x76) end, why = "flag 0x76 (beat Li, TM70)" }

-- Violet Gym (scr_seq_0859_T22GYM0101): Falkner (person 0), the Zephyr Badge,
-- VAR_SCENE_VIOLET_CITY_OW 0x4074 -> 1, VAR_SCENE_ELMS_LAB -> 6
B[#B + 1] = { name = "falkner",
  -- the walkway is 464 units over the floor: the lift (coord trigger at
  -- (15,20), VioletGymElevator) is the only way up (src/world/Gen4HeightRule.lua)
  steps = { { "teleport", "T22GYM0101", 15, 26, "up" }, { "walkto", 15, 20 },
            { "until", function(r)
                local g = r.game.save and r.game.save.hgssGymmick
                local def = r.ow and r.ow.map and r.ow.map.def
                local up = def and def.gen4HeightEdits and def.gen4HeightEdits["15,20"]
                return g and g.kind == "violet" and g.violetLift == 1 and up == 496 and not r:busy()
              end, 3000 },
            { "talk", 0 },
            { "until", function(r) return r:var(0x4074) >= 1 end, 60000 },
            { "do", function(r) print(("[hg] falkner: 0x4074=%s 0x4108=%s"):format(r:var(0x4074), r:var(0x4108))) end } },
  expect = function(r) return r:var(0x4074) >= 1 and r:var(0x4108) >= 6 end,
  why = "0x4074 >= 1 (Zephyr Badge), 0x4108 >= 6",
  -- the badge speech and TM51 run long after the vars are set
  expectBudget = 12000 }

-- Violet's mart (scr_seq_0858_T22FS0101): Elm's aide (person 4) hands over
-- the Mystery Egg -- VAR_SCENE_ELMS_LAB 7, VAR_SCENE_VIOLET_CITY_OW 3
B[#B + 1] = { name = "the aide's egg",
  -- Violet City's frame script (0x4074 == 1, scr_seq_0857_T22 000) is Elm's
  -- call: 0x4074 -> 2 and the aide is shown
  steps = { { "teleport", "T22", 31, 35, "up" },
            { "until", function(r) return r:var(0x4074) >= 2 end, 20000 },
            { "warpto", "T22FS0101" }, { "talk", 4 },
            { "until", function(r) return r:var(0x4108) >= 7 end, 30000 } },
  expect = function(r) return r:var(0x4108) >= 7 and r:var(0x4074) >= 3 end, why = "0x4108 >= 7, 0x4074 >= 3",
  expectBudget = 8000 }

-- Kurt's house (T23R0501, person 0): he storms off to the Slowpoke Well
-- (flag 0x77)
B[#B + 1] = { name = "kurt",
  steps = { { "teleport", "T23R0501", 4, 8, "up" }, { "talk", 0 },
            { "until", function(r) return r:flag(0x77) end, 30000 } },
  expect = function(r) return r:flag(0x77) end, why = "flag 0x77 (Kurt went to the well)", expectBudget = 8000 }

-- the Slowpoke Well B1F (scr_seq_0060_D26R0102): Proton (person 4) --
-- FLAG_BEAT_AZALEA_ROCKETS 0x7B
B[#B + 1] = { name = "proton in the slowpoke well",
  steps = { { "do", trainUp }, { "teleport", "D26R0102", 42, 26, "up" }, { "talk", 4 },
            { "until", function(r) return r:flag(0x7B) end, 90000 } },
  expect = function(r) return r:flag(0x7B) end, why = "flag 0x7B (beat the Azalea Rockets)", expectBudget = 12000 }

-- Azalea Gym (scr_seq_0869_T23GYM0102): Bugsy (person 5), the Hive Badge,
-- TM89 (flag 0x7F)
B[#B + 1] = { name = "bugsy",
  -- past the Spinarak carts (src/world/HgssAzaleaGym, checked on its own):
  -- the runner walks, it does not ride
  steps = { { "do", trainUp }, { "teleport", "T23GYM0102", 9, 8, "up" }, { "talk", 5 },
            { "until", function(r) return r:flag(0x7F) end, 90000 } },
  expect = function(r) return r:flag(0x7F) end, why = "flag 0x7F (Hive Badge, TM89)", expectBudget = 12000 }

-- Azalea, after the badge (scr_seq_0866_T23 coord 1 at (11,14) while
-- VAR_UNK_4075 == 1): the rival -- 0x4075 -> 2
B[#B + 1] = { name = "rival in azalea",
  steps = { { "do", trainUp }, { "teleport", "T23", 13, 14, "left" }, { "activecoord" },
            { "until", function(r) return r:var(0x4075) >= 2 end, 60000 } },
  expect = function(r) return r:var(0x4075) >= 2 end, why = "0x4075 >= 2 (rival battle)", expectBudget = 8000 }

-- Ilex Forest (scr_seq_0092_D36R0101): the apprentice's two Farfetch'd, then
-- HM01 Cut (flag 0x80).
--   The first (person 0) at (25,62): the sticks at (25,66) (farfetchd1_sticks1)
--   set its blind spot, then walked up to from (25,61) facing SOUTH it is
--   caught (_farfetchd1_bottom_left_caught) and the player is put back at
--   (15,65).
--   The second (person 2) starts at (41,54): walked up to facing NORTH it runs
--   right to (49,54) and arms the sticks; the sticks at (52,53)
--   (farfetchd2_sticks2) set its blind spot and turn it to the right; then
--   walked up to facing EAST it is caught (_farfetchd2_top_right_caught).
local chase = { { "teleport", "D36R0101", 15, 66, "up" } }
for _, s in ipairs({ { "walkto", 25, 66 }, { "walkto", 25, 61 }, { "face", "down" }, { "press", "a" },
                     { "until", function(r) return r:map() == "D36R0101" and select(2, r:pos()) == 65 end, 8000 },
                     { "do", function(r) r:say("  ff2 %s", r:personAt(2)) end },
                     { "walkto", 41, 55 }, { "face", "up" }, { "press", "a" },
                     { "do", function(r) r:say("  ff2 %s", r:personAt(2)) end },
                     { "walkto", 52, 53 },
                     { "until", function(r) return r:var(0x4003) == 1 end, 600 },
                     { "do", function(r) r:say("  ff2 %s blind %s", r:personAt(2), tostring(r:var(0x4003))) end },

                     -- round the sticks it just armed (sticks1 at (50,49), sticks4
                     -- at (45,53)): stepping on either turns it and clears the
                     -- blind spot
                     { "walkto", 52, 48 }, { "walkto", 48, 48 }, { "walkto", 48, 50 },
                     { "walkto", 47, 50 }, { "walkto", 47, 53 },
                     { "walkto", 47, 54 }, { "walkto", 48, 54 }, { "face", "right" },
                     { "do", function(r) r:say("  ff2 %s blind %s (at 48,54)", r:personAt(2), tostring(r:var(0x4003))) end },
                     { "press", "a" },
                     { "do", function(r) r:say("  ff2 %s flags %s %s", r:personAt(2), tostring(r:flag(0x80)), tostring(r:var(0x4003))) end } }) do
  chase[#chase + 1] = s
end
chase[#chase + 1] = { "until", function(r) return r:flag(0x80) end, 30000 }
B[#B + 1] = { name = "ilex forest farfetch'd",
  steps = chase,
  expect = function(r) return r:flag(0x80) end, why = "flag 0x80 (HM01 Cut)", expectBudget = 8000,
  budget = 80000 }

-- Goldenrod Gym (T25GYM0101): Whitney (person 0) cries after the battle; the
-- lass (person 1, moved to (13,15)) says to give her a minute (FLAG_UNK_0B7),
-- then Whitney hands over the Plain Badge and TM45 (flag 0x85)
B[#B + 1] = { name = "whitney",
  steps = { { "do", trainUp }, { "teleport", "T25GYM0101", 13, 6, "up" }, { "talk", 0 },
            { "until", function(r) return r:var(0x410A) >= 1 end, 60000 },
            -- the lass's line is the coord trigger at (13,11) (scr_seq_T25GYM0101_001,
            -- FLAG_UNK_0B7): Whitney's corner reaches the pit only under the
            -- walkway, through that trigger (the walkways are 52 units up)
            { "walkto", 13, 10 },
            -- down onto the trigger (held until its scene has set the flag:
            -- the scene puts the player back on (13,10), so a cell count
            -- never sees the step)
            { "until", function(r) if r:flag(0xB7) then return true end r.held = "down" end, 6000 },
            { "talk", 0 },
            { "until", function(r) return r:flag(0x85) end, 30000 } },
  expect = function(r) return r:flag(0x85) end, why = "flag 0x85 (Plain Badge, TM45)", expectBudget = 12000,
  budget = 80000 }

-- The Burned Tower 1F (scr_seq D18R0101): Morty and Eusine at the door
-- (coord 1 at (19,23), script 000: 0x40A2 -> 1), then the rival (coord 2 at
-- (22,19), script 003: the battle, 0x40A6 -> 1)
B[#B + 1] = { name = "burned tower rival",
  steps = { { "do", trainUp }, { "teleport", "D18R0101", 15, 25, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A2) >= 1 end, 30000 },
            { "coord", 2 },
            { "until", function(r) return r:var(0x40A6) >= 1 end, 60000 } },
  expect = function(r) return r:var(0x40A6) >= 1 end, why = "0x40A6 >= 1 (rival battle)", expectBudget = 8000 }

-- B1F (D18R0102): the three beasts wake and flee (coord 1 at (20,16) while
-- 0x40A1 == 0): 0x40A1 = 1, 0x4076 = 1, 0x4079 = 2 (Morty's gym opens)
B[#B + 1] = { name = "the legendary beasts",
  steps = { { "teleport", "D18R0102", 22, 16, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A1) >= 1 end, 60000 } },
  expect = function(r) return r:var(0x40A1) >= 1 and r:var(0x4079) >= 2 end, why = "0x40A1 >= 1, 0x4079 >= 2",
  expectBudget = 12000 }

-- Ecruteak Gym (T27GYM0101): Morty (person 1), past the invisible floor;
-- the Fog Badge and TM30 (FLAG_GOT_TM30_FROM_MORTY)
B[#B + 1] = { name = "morty",
  steps = { { "do", trainUp }, { "teleport", "T27GYM0101", 10, 10, "up" }, { "talk", 1 },
            { "until", function(r) return r:flag(0xA6) end, 60000 } },
  expect = function(r) return r:flag(0xA6) end, why = "flag 0xA6 (Fog Badge, TM30)", expectBudget = 12000 }

-- Olivine Lighthouse's top (D27R0107): Jasmine (person 1) and the sick
-- Ampharos -- VAR_SCENE_LIGHTHOUSE_JASMINE 0x40A5 -> 1
B[#B + 1] = { name = "jasmine at the lighthouse",
  steps = { { "teleport", "D27R0107", 9, 9, "up" }, { "talk", 1 },
            { "until", function(r) return r:var(0x40A5) >= 1 end, 30000 } },
  expect = function(r) return r:var(0x40A5) >= 1 end, why = "0x40A5 >= 1", expectBudget = 8000 }

-- Cianwood Gym (T24GYM0101): Chuck (person 0) trains under the waterfall and
-- does not notice you until the winch (sign 1 at (10,2), CianwoodGymTurnWinch
-- into VAR_TEMP_x4000) stops it; then the Storm Badge and TM01 (0xBA)
B[#B + 1] = { name = "chuck",
  steps = { { "do", trainUp }, { "teleport", "T24GYM0101", 13, 12, "up" }, { "sign", 1 },
            { "until", function(r) return r:var(0x4000) == 1 end, 8000 }, { "talk", 0 },
            { "until", function(r) return r:flag(0xBA) end, 60000 } },
  expect = function(r) return r:flag(0xBA) end, why = "flag 0xBA (Storm Badge, TM01)", expectBudget = 12000 }

-- Cianwood's pharmacy (T24R0501): the SecretPotion (flag 0xB9)
B[#B + 1] = { name = "the secretpotion",
  -- across the counter: the pharmacist stands behind it at (5,5)
  steps = { { "teleport", "T24R0501", 5, 8, "up" }, { "walkto", 5, 7 }, { "face", "up" }, { "press", "a" },
            { "until", function(r) return r:flag(0xB9) end, 30000 } },
  expect = function(r) return r:flag(0xB9) end, why = "flag 0xB9 (SecretPotion)", expectBudget = 8000 }

-- back up the Lighthouse: the medicine for Amphy (0x40A5 -> 2)
B[#B + 1] = { name = "amphy healed",
  steps = { { "teleport", "D27R0107", 9, 9, "up" }, { "talk", 1 },
            { "until", function(r) return r:var(0x40A5) >= 2 end, 30000 } },
  expect = function(r) return r:var(0x40A5) >= 2 end, why = "0x40A5 >= 2", expectBudget = 12000 }

-- Olivine Gym (T26GYM0101): Jasmine (person 0), the Mineral Badge, TM23 (0xC2)
B[#B + 1] = { name = "jasmine",
  steps = { { "do", trainUpWith(53) }, { "teleport", "T26GYM0101", 6, 8, "up" }, { "talk", 0 },
            { "until", function(r) return r:flag(0xC2) end, 60000 } },
  expect = function(r) return r:flag(0xC2) end, why = "flag 0xC2 (Mineral Badge, TM23)", expectBudget = 12000 }

-- A CHEAT, said as one: put the player on the water as a surfer (the runner
-- walks; it does not answer the Surf prompt). After a "teleport" onto water.
local function surfing(r)
  local p = r.ow and r.ow.player
  if p then p.surfing = true end
end

-- The Lake of Rage (scr_seq_0938_T29): the red Gyarados (person 3 at (45,39),
-- a WildBattle at level 30) and the Red Scale (FLAG_GOT_RED_SCALE)
B[#B + 1] = { name = "the red gyarados",
  steps = { { "do", trainUp }, { "teleport", "T29", 45, 41, "up" }, { "do", surfing }, { "talk", 3 },
            { "until", function(r) return r:flag(0xC9) end, 60000 } },
  expect = function(r) return r:flag(0xC9) end, why = "flag 0xC9 (Red Scale)", expectBudget = 12000 }

-- Lance by the lake (person 8): VAR_UNK_40A8 -> 1
B[#B + 1] = { name = "lance at the lake",
  steps = { { "teleport", "T29", 48, 53, "up" }, { "talk", 8 },
            { "until", function(r) return r:var(0x40A8) >= 1 end, 30000 } },
  expect = function(r) return r:var(0x40A8) >= 1 end, why = "0x40A8 >= 1", expectBudget = 8000 }

-- Mahogany's souvenir shop (D35R0101): Lance's frame scene (0x40A8 == 1)
-- opens the stairs down -- 0x40A8 -> 2
B[#B + 1] = { name = "the mahogany shop",
  steps = { { "teleport", "D35R0101", 5, 8, "up" },
            { "until", function(r) return r:var(0x40A8) >= 2 end, 30000 } },
  expect = function(r) return r:var(0x40A8) >= 2 end, why = "0x40A8 >= 2", expectBudget = 8000 }

-- THE ROCKET HIDEOUT (D35R0102 B1F, D35R0103 B2F, D35R0104 B3F). Its story
-- is VAR_UNK_40AC (0x40AC) 0 -> 10, each step a coord trigger gated on the
-- value before it, across the floors (scr_seq_0089..0091):
--   B2F frame (0x40A9 == 0) -> 0x40A9 1; B3F frame (0x40AC == 0) -> 1, its
--   OnTransition -> 2 once its two grunts are beaten; B3F (20,17) the rival -> 3; B3F (23,12) Petrel -> 4;
--   B2F (11,4) -> 5; B3F (50,4) -> 6; B2F (50,29) -> 7; B2F (29,27) -> 8
--   (0x40A9 3); B2F (30,19) Ariana and Lance -> 9 (0x40A9 4); the three
--   Electrodes (persons 9-11) -> 10.
local function at(v) return function(r) return r:var(0x40AC) >= v end end
B[#B + 1] = { name = "rocket hideout: b3f",
  -- B1F's (16,28) warps back to the start for good (VAR_UNK_40C2 is never
  -- set): down the east side and west along row 30 instead
  steps = { { "do", trainUp }, { "teleport", "D35R0101", 6, 4, "up" }, { "warpto", "D35R0102" },
            { "walkto", 50, 12 }, { "walkto", 50, 30 }, { "walkto", 12, 30 },
            { "warpto", "D35R0103" }, { "until", function(r) return r:var(0x40A9) >= 1 end, 20000 },
            { "warpto", "D35R0104" }, { "until", at(1), 20000 },
            -- B3F's OnTransition sets 2 only once its two grunts are beaten
            -- (persons 3 and 4), on coming back in
            { "talk", 3 }, { "talk", 4 },
            -- B3F is walled into sections: the rival and Petrel are only
            -- reached by B2F's stairs at (10,4), so those stairs, by cell
            -- B2F's top row is walled off from its south too: up at B3F's
            -- (51,29), across B3F's east side, up at (51,4), west along
            -- B2F's top row and down at (10,4)
            { "warpto", "D35R0103" }, { "walkto", 49, 29 }, { "warpto", "D35R0104" },
            { "walkto", 50, 4 }, { "step", "right", 2 },
            { "walkto", 11, 4 }, { "step", "left", 2 },
            { "until", at(2), 20000 },
            { "activecoord" }, { "until", at(3), 40000 },
            -- the door to Petrel (persons 10/11 at (23,15)/(24,15), script
            -- 004) slides open when spoken to, both grunts beaten
            { "talk", 10 },
            { "activecoord" }, { "until", at(4), 60000 } },
  expect = at(4), why = "0x40AC >= 4 (the rival, Petrel)", expectBudget = 12000, budget = 160000 }

B[#B + 1] = { name = "rocket hideout: the murkrow",
  -- the stairs by cell again (walked into, held: a stair fires on a press
  -- into it): B3F (10,4) up to B2F's top row and (11,4);
  -- B2F (51,4) down to B3F's east side and (50,4); B3F (51,29) up to B2F's
  -- south-east corner and (50,29)
  steps = { { "do", trainUp }, { "walkto", 11, 4 }, { "step", "left", 2 },
            { "activecoord" }, { "until", at(5), 30000 },
            { "walkto", 50, 4 }, { "step", "right", 2 }, { "activecoord" }, { "until", at(6), 30000 },
            { "walkto", 50, 29 }, { "step", "right", 2 }, { "activecoord" }, { "until", at(7), 30000 },
            { "activecoord" }, { "until", at(8), 30000 } },
  expect = at(8), why = "0x40AC >= 8", expectBudget = 12000, budget = 160000 }

B[#B + 1] = { name = "rocket hideout: ariana and the electrodes",
  -- the three Electrodes are wild battles one after another, with no heal
  -- between: an Electrode that Self-Destructs first takes a lone lead with
  -- it, and the next battle starts with no healthy party (a blackout to
  -- Mahogany's Center, the beat lost). A TEST-BOT CHOICE, said as one: a
  -- Ghost lead (Gengar, Shadow Ball first) for them, which Explosion and
  -- Self-Destruct cannot touch
  steps = { { "do", trainUp }, { "activecoord" }, { "until", at(9), 60000 },
            { "do", trainUpWith(247, 75, 94) },
            { "talk", 9 }, { "talk", 10 }, { "talk", 11 }, { "until", at(10), 60000 } },
  expect = at(10), why = "0x40AC >= 10 (the generator stopped)", expectBudget = 12000, budget = 160000 }

-- Mahogany Gym (T28GYM0101): Pryce (person 0), past the ice; the Glacier
-- Badge and TM07 (0xD2). Fire beats his Ice types; at 100, as the default
-- level lost to his Piloswine on close HP more than once.
B[#B + 1] = { name = "pryce",
  steps = { { "do", trainUpWith(53, 100) }, { "teleport", "T28GYM0101", 7, 6, "up" }, { "talk", 0 },
            { "until", function(r) return r:flag(0xD2) end, 60000 } },
  expect = function(r) return r:flag(0xD2) end, why = "flag 0xD2 (Glacier Badge, TM07)", expectBudget = 12000 }

-- THE RADIO TOWER TAKEOVER, VAR_SCENE_ROCKET_TAKEOVER 0x4077:
--   Mahogany's frame table (VAR_MIDGAME_BADGES 0x4134 == 4) starts it -> 2;
--   the Goldenrod Underground's coord (15,7..13) puts the player in a Rocket
--   costume -> 3; the rival at the tower's 1F stairs (23,5) -> 4; Petrel as
--   the fake director on 5F (D23R0105 person 0, revealed as person 2) gives the Basement Key
--   (0x40E7 -> 2); the real director in the warehouse (D37R0105 person 3)
--   the Card Key (flag 0x1C1); Archer (D23R0106 person 0) -> 5.
--   The warehouse's switch gates and the 3F shutter are teleported past.
local function takeover(v) return function(r) return r:var(0x4077) >= v end end
B[#B + 1] = { name = "the takeover begins",
  steps = { { "teleport", "T28", 16, 16, "down" }, { "until", takeover(2), 20000 } },
  expect = takeover(2), why = "0x4077 >= 2", expectBudget = 8000 }

B[#B + 1] = { name = "the rocket costume",
  steps = { { "do", trainUp }, { "teleport", "D37R0102", 16, 10, "left" }, { "activecoord" },
            { "until", takeover(3), 40000 } },
  expect = takeover(3), why = "0x4077 >= 3", expectBudget = 12000 }

B[#B + 1] = { name = "radio tower rival",
  -- the grunt on the stairs (person 6, standing on the trigger) steps aside
  -- for a player in the costume (0x4077 == 3)
  steps = { { "do", trainUp }, { "teleport", "D23R0101", 23, 7, "up" }, { "talk", 6 },
            { "activecoord" }, { "until", takeover(4), 40000 } },
  expect = takeover(4), why = "0x4077 >= 4", expectBudget = 12000 }

B[#B + 1] = { name = "petrel the fake director",
  steps = { { "do", trainUp }, { "teleport", "D23R0105", 5, 15, "up" }, { "talk", 0 },
            { "until", function(r) return r:var(0x40E7) >= 2 end, 40000 } },
  expect = function(r) return r:var(0x40E7) >= 2 end, why = "0x40E7 >= 2 (Basement Key)", expectBudget = 12000 }

B[#B + 1] = { name = "the real director",
  steps = { { "do", trainUp }, { "teleport", "D37R0105", 20, 15, "up" }, { "talk", 3 },
            { "until", function(r) return r:flag(0x1C1) end, 40000 } },
  expect = function(r) return r:flag(0x1C1) end, why = "flag 0x1C1 (Card Key)", expectBudget = 12000 }

B[#B + 1] = { name = "archer",
  -- Surf: his Houndour and Houndoom are Dark, which Psychic cannot touch
  steps = { { "do", trainUpWith(57) }, { "teleport", "D23R0106", 8, 5, "up" }, { "talk", 0 },
            { "until", takeover(5), 60000 } },
  expect = takeover(5), why = "0x4077 >= 5 (the tower freed)", expectBudget = 12000 }

-- Blackthorn Gym (T30GYM0101): Clair (person 0) is beaten and refuses the
-- badge (FLAG_UNK_0D1; the Dragon's Den guard steps aside). Ice Beam for
-- her dragons, at 100: Kingdra takes Ice Beam neutrally and won once at 75.
B[#B + 1] = { name = "clair",
  steps = { { "do", trainUpWith(58, 100) }, { "teleport", "T30GYM0101", 12, 5, "up" }, { "talk", 0 },
            { "until", function(r) return r:flag(0xD1) end, 60000 } },
  expect = function(r) return r:flag(0xD1) end, why = "flag 0xD1 (Clair beaten)", expectBudget = 12000 }

-- The Dragon's Den shrine (D44R0103): its frame script (0x40C3 == 0) is the
-- elder's five questions; a wrong answer asks the same question again. The
-- right rows (the items whose value is 0): 1, 1, 2, 1, 2. Then the Rising
-- Badge, 0x40C3 -> 1, VAR_SCENE_ELMS_LAB -> 8.
B[#B + 1] = { name = "the elder's test",
  steps = { { "answers", { 1, 1, 2, 1, 2 } }, { "teleport", "D44R0103", 5, 12, "up" },
            { "until", function(r) return r:var(0x40C3) >= 1 end, 60000 } },
  expect = function(r) return r:var(0x40C3) >= 1 and r:var(0x4108) >= 8 end,
  why = "0x40C3 >= 1, 0x4108 >= 8 (Rising Badge)", expectBudget = 12000 }

-- THE POKEMON LEAGUE (T10R0201..0601): each room walks the player in, the
-- Elite Four member is person 0 (FLAG_DEFEATED_WILL 0xE4, KOGA 0xE5, BRUNO
-- 0xE6, KAREN 0xE7); Lance's room (frame script on 0x40C8 == 0), then the
-- Hall of Fame (T10R0701: HallOfFameAnim, the credits). The cheat's move is
-- chosen per room: Ice Beam (58) for Will's Xatu and Lance's dragons, Psychic
-- for Koga and Bruno, Surf (57) for Karen's dark types -- on a Mewtwo, as
-- Chikorita at 100 still lost to her (Houndoom, Vileplume) once.
-- THE SAME CHEAT, SIX DEEP: the Elite Four and Red outlast one Pokemon of any
-- level (Will's Jynx resists Ice Beam; Karen beat a lone Chikorita at 100), so
-- the party becomes six Mewtwo at 100, each leading with `move`.
local function fullTeam(move)
  return function(r)
    local party = r:party()
    local lead = party[1]
    local Pokemon = require("src.pokemon.Pokemon")
    for i = 1, 6 do
      local mon = Pokemon.new(r.game.data, 150, 100)
      if lead then mon.otName, mon.otId = lead.otName, lead.otId end
      mon.moves = mon.moves or {}
      table.insert(mon.moves, 1, { id = move, pp = 64 })
      while #mon.moves > 4 do table.remove(mon.moves) end
      party[i] = mon
    end
  end
end
local E4 = { { "will", "T10R0201", 0xE4, 58 }, { "koga", "T10R0301", 0xE5, 94 },
             { "bruno", "T10R0401", 0xE6, 94 }, { "karen", "T10R0501", 0xE7, 57, 150 } }
for _, e in ipairs(E4) do
  local flag = e[3]
  B[#B + 1] = { name = "elite four " .. e[1],
    steps = { { "do", fullTeam(e[4]) }, { "teleport", e[2], 6, 19, "up" }, { "talk", 0 },
              { "until", function(r) return r:flag(flag) end, 60000 } },
    expect = function(r) return r:flag(flag) end, why = ("flag 0x%X"):format(flag), expectBudget = 12000 }
end

local function famed(r)
  local hof = r.game.save and r.game.save.hallOfFame
  return type(hof) == "table" and #hof > 0
end
B[#B + 1] = { name = "champion lance",
  -- one Pokemon, one move, six of Lance's: the cheat's lead is a Mewtwo here
  steps = { { "do", trainUpWith(58, 100, 150) }, { "teleport", "T10R0601", 6, 26, "up" },
            { "until", function(r) return r:var(0x40C8) >= 1 end, 20000 },
            -- the scene can run to the Hall of Fame (and the bedroom) inside the
            -- wait above; then there is nobody left to talk to
            { "talk", 0, unless = famed },
            { "until", famed, 120000 } },
  expect = famed, why = "a Hall of Fame record", expectBudget = 12000, budget = 160000, passBusy = true }

-- KANTO. After the Hall of Fame (FLAG_GAME_CLEAR) Elm hands over the S.S.
-- Ticket (scr_seq_0843_T20R0101 _0526: FLAG_GOT_SS_TICKET_FROM_ELM 0xF2).
B[#B + 1] = { name = "the s.s. ticket",
  steps = { { "teleport", "T20", 12, 10, "up" }, { "warpto", "T20R0101" },
            -- Elm (person 0) at (4,5), from the tile below him: the walking
            -- Pokemon, back beside the player after the Hall of Fame walk-in,
            -- left the generic talk on the aide's side of the lab
            { "walkto", 4, 6 }, { "face", "up" }, { "press", "a" },
            { "until", function(r) return r:flag(0xF2) end, 20000 } },
  expect = function(r) return r:flag(0xF2) end, why = "flag 0xF2 (S.S. Ticket)" }

-- Olivine port (P01R0101), from beside its door (the long walk down from the
-- town met wandering sailors in a full run): the seaman (person 0) takes the ticket and walks
-- the player out to the boat (VAR_BOAT_DIRECTION 0x40E1 = 1).
B[#B + 1] = { name = "boarding the s.s. aqua",
  steps = { { "teleport", "T26", 23, 50, "down" }, { "warpto", "P01R0101" }, { "talk", 0 },
            { "until", function(r) return r:var(0x40E1) == 1 end, 20000 } },
  expect = function(r) return r:var(0x40E1) == 1 end, why = "0x40E1 = 1 (boat leaves Olivine)" }

-- The dock (P01R0102): the seaman (person 0) leads the player up the gangway
-- and ScrCmd_723 carries them aboard -- S.S. Aqua 1F (P01R0301).
B[#B + 1] = { name = "aboard the s.s. aqua",
  steps = { { "warpto", "P01R0102" }, { "talk", 0 },
            { "until", function(r) return r:map() == "P01R0301" end, 20000 } },
  expect = function(r) return r:map() == "P01R0301" end, why = "on S.S. Aqua 1F" }

-- On board (scr_seq_0156_P01R0301): the frame script walks the player in
-- (0x40DC -> 1), then the gentleman runs into them looking for his
-- granddaughter -- a coordinate trigger -- and 0x40CB goes to 2.
local function coords(r)
  local def = r.ow and r.ow.map and r.ow.map.def or {}
  for i, c in ipairs(def.coordEvents or {}) do
    r:say("  coord %d at (%s,%s) w%s var 0x%X = %s", i, tostring(c.x), tostring(c.y), tostring(c.width),
          tonumber(c.var) or 0, tostring(c.value))
  end
end
B[#B + 1] = { name = "the lost granddaughter",
  steps = { { "until", function(r) return r:var(0x40DC) == 1 end, 6000 }, { "do", coords },
            { "activecoord" }, { "until", function(r) return r:var(0x40CB) >= 2 end, 20000 } },
  expect = function(r) return r:var(0x40CB) >= 2 end, why = "0x40CB >= 2 (the gentleman's search)" }

-- B1F (P01R0307): a sailor stops the player (FLAG_UNK_0ED); in the southeast
-- cabins (P01R0303) Sailor Stanly (person 0) then fights, 0x40CB -> 3.
B[#B + 1] = { name = "sailor stanly",
  steps = { { "do", trainUpWith(94, 75) }, { "warpto", "P01R0307" }, { "talk", 1 },
            { "until", function(r) return r:flag(0xED) end, 6000 },
            { "warpto", "P01R0301" }, { "warpto", "P01R0303" }, { "talk", 0 },
            { "until", function(r) return r:var(0x40CB) >= 3 end, 30000 } },
  expect = function(r) return r:var(0x40CB) >= 3 end, why = "0x40CB >= 3 (Stanly beaten)" }

-- The captain's room (P01R0302): the granddaughter (person 1) runs off, 4.
B[#B + 1] = { name = "the captain's room",
  -- 1F is two halves walled apart at x 39-40: the captain's door (49,15) is
  -- reached down the west stairs (24,3) and up B1F's other flight
  steps = { { "warpto", "P01R0301" }, { "warpto", "P01R0307", 24, 3 },
            { "warpto", "P01R0301", 42, 9 }, { "warpto", "P01R0302" }, { "talk", 1 },
            { "until", function(r) return r:var(0x40CB) >= 4 end, 20000 } },
  expect = function(r) return r:var(0x40CB) >= 4 end, why = "0x40CB >= 4" }

B[#B + 1] = { name = "the granddaughter found",
  steps = { { "warpto", "P01R0301" }, { "warpto", "P01R0307", 42, 9 }, { "talk", 0 },
            { "until", function(r) return r:flag(0xEB) end, 30000 } },
  expect = function(r) return r:var(0x40CB) >= 6 and r:flag(0xEB) end, why = "0x40CB >= 6, boat arrived" }

-- Docked: the sailor at the gangway (scr_seq_0156_P01R0301 _0101) steps aside
-- (0x40CB 7) and the way off leads to Vermilion's dock (P01R0104), whose frame
-- scene ends the voyage (VAR_BOAT_DIRECTION 0) -- KANTO.
B[#B + 1] = { name = "vermilion port",
  steps = { { "warpto", "P01R0301" }, { "talkany", { 1, 0, 2 } },
            { "until", function(r) return r:var(0x40CB) >= 7 end, 20000 },
            { "warpto", "P01R0104" },
            { "until", function(r) return r:map() == "P01R0104" and r:var(0x40E1) == 0 end, 20000 } },
  expect = function(r) return r:map() == "P01R0104" and r:var(0x40E1) == 0 end,
  why = "on Vermilion's dock, 0x40E1 = 0" }

-- KANTO'S GYMS. Their puzzles (Vermilion's trash cans, Saffron's warp
-- panels, Janine's doubles) are teleported past, as Azalea's carts were: the
-- player is put on the gym's first warp, then on the open side of the leader.
local SIDES = { { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }
local function besideLeader(map, id)
  return function(r)
    local def = r.game.data.maps[map]
    local w = def and def.warps and def.warps[1]
    r.ow:setMap(map, w and w.x or 1, w and w.y or 1, "up")
    for _, n in ipairs(r.ow.npcs or {}) do
      local lid = n.localId or (n.def and n.def.localId)
      if lid == id and not n.hidden then
        for _, d in ipairs(SIDES) do
          local cx, cy = n.cellX + d[1], n.cellY + d[2]
          if r.ow.map:isWalkableCell(cx, cy) then
            r.ow:setMap(map, cx, cy, d[3])
            r:say("  beside %s person %d at (%d,%d)", map, id, cx, cy)
            return
          end
        end
      end
    end
    r:say("  person %d not found on %s", id, map)
  end
end
local function onMap(map)
  return function(r)
    local def = r.game.data.maps[map]
    local w = def and def.warps and def.warps[1]
    r.ow:setMap(map, w and w.x or 1, w and w.y or 1, "down")
  end
end
local function kantoGym(name, map, id, flag, move, level, species)
  B[#B + 1] = { name = name,
    steps = { { "do", trainUpWith(move, level or 100, species) }, { "do", besideLeader(map, id) }, { "talk", id },
              { "until", function(r) return r:flag(flag) end, 60000 } },
    expect = function(r) return r:flag(flag) end, why = ("flag 0x%X (the TM)"):format(flag), expectBudget = 12000,
    -- the talk-started battle is inside the beat's own budget; a long one
    -- (two fainted, forced switches) ran past the 30000 default on resumes
    budget = 70000 }
end
-- Ground for Surge, Dark (Crunch 242) for Sabrina, Fire (Flamethrower 53) for
-- Erika, Psychic (94) for Janine
kantoGym("lt. surge", "T06GYM0101", 9, 0x181, 89, 100, 150)
kantoGym("sabrina", "T11GYM0101", 5, 0x182, 242, 100, 150)
kantoGym("erika", "T07GYM0101", 8, 0x124, 53, 100, 150)
kantoGym("janine", "T08GYM0101", 2, 0x12D, 94, 100, 150)
-- Water (Surf 57) for Brock and Blaine,
-- Ice Beam (58) for Blue's mixed team
-- The Power Plant (R10R0202, scr_seq_0196): the manager (person 6, script
-- 006) tells his story (0x411B 1), the officer's scene follows (007, a
-- coordinate scene: 0x411C 1); in Cerulean Gym the Rocket bolts (T04GYM0101
-- 004: 0x4088 1, Misty to Route 25); on the cape her date is broken up (R25
-- 000: 0x4088 2) and she is back in her gym.
B[#B + 1] = { name = "the power plant",
  steps = { { "do", onMap("R10R0202") }, { "talk", 6 },
            { "until", function(r) return r:var(0x411B) == 1 end, 20000 },
            { "do", coords }, { "activecoord" },
            { "until", function(r) return r:var(0x411C) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x411C) >= 1 end, why = "0x411C >= 1 (the officer's report)" }
B[#B + 1] = { name = "the rocket in cerulean gym",
  steps = { { "do", onMap("T04GYM0101") },
            { "until", function(r) return r:var(0x4088) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4088) >= 1 end, why = "0x4088 >= 1" }
B[#B + 1] = { name = "misty's date",
  steps = { { "do", onMap("R25") }, { "do", coords }, { "activecoord" },
            { "until", function(r) return r:var(0x4088) >= 2 end, 30000 } },
  expect = function(r) return r:var(0x4088) >= 2 end, why = "0x4088 >= 2 (Misty back at the gym)" }
kantoGym("misty", "T04GYM0101", 6, 0x180, 412, 100, 150) -- Energy Ball: Quagsire is immune to Thunderbolt and 4x weak to Grass; Psychic dragged the battle out
kantoGym("brock", "T03GYM0101", 1, 0x17F, 57, 100, 150)
kantoGym("blaine", "D11R0106", 0, 0x17D, 57, 100, 150)
kantoGym("blue", "T02GYM0101", 5, 0x17E, 58, 100, 150)

-- Sixteen badges: Oak (T01R0301, person 0) opens Mt. Silver
-- (FLAG_UNLOCKED_MT_SILVER 0x12B); at its summit (D41R0108) Red (person 0)
-- is beaten -- 0x40FD 1 -- and the credits roll (HOFCredits 1).
-- Out of Viridian Gym the frame script (scr_seq_0741_T02 011) has Oak call:
-- 0x4096 1 -> 2, which is what his Mt. Silver line checks.
B[#B + 1] = { name = "oak's call",
  steps = { { "warpto", "T02" }, { "until", function(r) return r:var(0x4096) == 2 end, 20000 } },
  expect = function(r) return r:var(0x4096) == 2 end, why = "0x4096 = 2 (Oak's call)" }
B[#B + 1] = { name = "oak's permission",
  steps = { { "do", onMap("T01R0301") }, { "talk", 0 },
            { "until", function(r) return r:flag(0x12B) end, 20000 } },
  expect = function(r) return r:flag(0x12B) end, why = "flag 0x12B (Mt. Silver unlocked)" }
B[#B + 1] = { name = "red",
  steps = { { "do", fullTeam(94) }, { "do", besideLeader("D41R0108", 0) }, { "talk", 0 },
            { "until", function(r) return r:var(0x40FD) >= 1 end, 120000 } },
  expect = function(r) return r:var(0x40FD) >= 1 end, why = "0x40FD >= 1 (Red beaten)",
  expectBudget = 12000, budget = 160000, passBusy = true }

return B
