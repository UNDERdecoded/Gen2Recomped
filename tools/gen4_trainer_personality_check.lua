-- Pure-Lua check of src/battle/Gen4TrainerPersonality.lua against
-- pret/pokeplatinum TrainerData_BuildParty (src/trainer_data.c).
--   python tools/run_lua_check.py tools/gen4_trainer_personality_check.lua \
--       <usa cache> <renegade cache>
-- (caches: ...LOVE/v_usa/platinum and ...LOVE/v_rp/renegadeplatinum)
--
-- The expected personalities below come from an INDEPENDENT integer
-- implementation of the decomp's algorithm (python, masked 32-bit math):
--     seed = ivScale + level + (species & 0x3FF) + trainerId
--     run the LCRNG (x*0x41C64E6D+0x6073) `class` times, keep x >> 16
--     pid = (that << 8) + (female class ? 120 : 136)
-- The end-to-end half (buildTrainerParty through the real Data) is
-- tools/gen4_trainer_personality_check/ (lovec).
package.path = "./?.lua;" .. package.path
local P = require("src.battle.Gen4TrainerPersonality")
local n = 0
local function check(v, why) n = n + 1; if not v then error("FAIL: " .. why, 2) end end

-- { cache, trainer id, class, ivScale, level, species, personality, nature }
local CASES = {
  { "usa",   1,  2,   0,  5, 396,  9229448, 23 },  -- Youngster Tristan's Starly
  { "usa",   3,  3,   0,  5, 399, 10115192, 17 },  -- Lass Natalie's Bidoof (female class: low byte 0x78)
  { "usa", 408, 88, 200, 40, 454, 11684728,  3 },  -- Commander Saturn's Toxicroak (class 88 is female in the ROM table)
  { "usa", 445, 14,  30, 38, 454,  1153416, 16 },  -- Black Belt Kendal's Toxicroak
  { "rp",  408, 88, 255, 53, 454,  4054136, 11 },
  { "rp",  959, 88, 255, 34, 454,  5544312, 12 },
  { "rp",  317, 76, 248, 38, 454,  5523576,  1 },
  { "rp",  148, 14, 250, 51, 454, 13765256,  6 },
}
for _, c in ipairs(CASES) do
  local slot = { ivScale = c[4], level = c[5], species = c[6] }
  local pid = P.personality(c[2], c[3], slot)
  check(pid == c[7], ("%s trainer %d: personality %d (0x%x), want %d"):format(c[1], c[2], pid, pid, c[7]))
  check(pid % 25 == c[8], "nature of " .. c[7])
  check(P.personality(c[2], c[3], slot) == pid, "determinism")
  check(pid % 2 == 0 and (pid % 256 == 120 or pid % 256 == 136) and pid < 2 ^ 24, "shape")
  check((pid % 256 == 120) == (c[3] == 3 or c[3] == 88 or c[3] == 76), "gender byte follows the class")
end
check(P.iv({ ivScale = 255 }) == 31 and P.iv({ ivScale = 0 }) == 0
      and P.iv({ ivScale = 200 }) == 24 and P.iv({ ivScale = 100 }) == 12, "ivScale*31/255")
-- the LCRNG itself: seed 0 -> 0x6073; seed 1 -> 0x41C64E6D + 0x6073
check(P.step(0) == 0x6073 and P.step(1) == 0x41C64E6D + 0x6073, "LCRNG step")
check(P.step(0xFFFFFFFF) == (0x100000000 - 0x41C64E6D + 0x6073) % 0x100000000, "LCRNG wraps like u32")

-- sweep every party slot of both caches
for _, root in ipairs({ arg[1], arg[2] }) do
  local tr = assert(loadfile(root .. "/data/generated/trainers.lua"))()
  local pk = assert(loadfile(root .. "/data/generated/pokemon.lua"))()
  local slots, tox = 0, 0
  for id = 0, 4000 do
    local rec = tr[id]
    if rec and rec.party and rec.class then
      for _, s in ipairs(rec.party) do
        local pid = P.personality(id, rec.class, s)
        check(pid % 2 == 0 and pid < 2 ^ 24 and (pid % 256 == 120 or pid % 256 == 136), "slot shape")
        slots = slots + 1
        local def = pk[s.species]
        if root == arg[2] and s.species == 454 and def then
          tox = tox + 1
          check(def.abilities[(pid % 2) + 1] == "DRY_SKIN", "Renegade Toxicroak slot -> Dry Skin")
        end
      end
    end
  end
  print(root, "slots", slots, "renegade toxicroak", tox)
end
print("gen4_trainer_personality_check: " .. n .. " checks ok")
