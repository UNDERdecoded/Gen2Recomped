-- The Pokemon Rowan releases in the opening comes out of overlay 73 (Buneary on
-- retail Platinum, Eevee on Renegade Platinum), not out of a constant.
--
--   python tools/run_lua_check.py tools/gen4_intro_species_check.lua
--   python tools/run_lua_check.py tools/gen4_intro_species_check.lua <rom.nds> <expected species>
--
-- The first form runs on a synthetic Thumb sequence; with a cartridge it also
-- reads the real overlay and compares.
package.path = "./?.lua;./?/init.lua;" .. package.path

local Intro = require("src.import.Gen4IntroScene")
local fails = 0
local function check(cond, label)
  if not cond then fails = fails + 1; print("FAIL: " .. label) end
end

local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536)) end

-- ldr r1, [pc, #8] ; str r2, [sp, #8] ; add r0, sp, #0x10 ; movs r3, #2 ; pad
-- from offset 0 the literal is at floor(4 / 4) * 4 + 8 = 12
local function overlay(species)
  return u16(0x4902) .. u16(0x9202) .. u16(0xA804) .. u16(0x2302)
      .. u16(0) .. u16(0) .. u32(species)
end
check(Intro.monSpecies(overlay(427)) == 427, "reads Buneary's literal")
check(Intro.monSpecies(overlay(133)) == 133, "reads Eevee's literal")
check(Intro.monSpecies(overlay(0)) == nil, "species 0 is not a species")
check(Intro.monSpecies(overlay(9999)) == nil, "a value past the species count is refused")
check(Intro.monSpecies(u16(0x4902) .. u16(0x9203) .. u16(0xA804) .. u16(0x2302)
        .. u16(0) .. u16(0) .. u32(133)) == nil, "a different sequence is not matched")
check(Intro.monSpecies(nil) == nil and Intro.monSpecies("") == nil, "no overlay, no species")

local rom, expected = arg and arg[1], tonumber(arg and arg[2])
if rom and expected then
  local NdsRom = require("src.import.NdsRom")
  local cart = assert(NdsRom.open(rom))
  local got = Intro.monSpecies((cart:overlay(Intro.OVERLAY)))
  check(got == expected, ("overlay %d names species %s, expected %d"):format(
    Intro.OVERLAY, tostring(got), expected))
end

print(("gen4 intro species: %s"):format(fails == 0 and "ok" or (fails .. " failed")))
if fails > 0 then os.exit(1) end
