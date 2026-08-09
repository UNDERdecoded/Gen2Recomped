-- Driver: OG BLUE (GBC boot-ROM) palette correctness for Pokemon Blue (#155).
--
-- Pokemon Blue, like Red, ships no CGB code, so a Game Boy Color colorizes it
-- from the boot ROM's per-game auto-palette table.  Blue's entry is NOT a
-- mirror of Red's and does NOT share Red's green characters: per Bulbapedia's
-- Generation-I GBC boot-ROM palette table (and the Gambatte hardware capture
-- attached to #155) Blue is a light-blue/blue BACKGROUND
-- with a PINK object (OBP0) palette -- the same red/pink ramp Red uses for its
-- BACKGROUND.  The port had baked a fabricated "channel-swapped Red" BG and
-- kept Red's green sprites for both versions, so a Blue playthrough in COLORS =
-- OG rendered periwinkle terrain and a green player instead of blue terrain and
-- a pink player.
--
-- These checks are pure-data (version-forced via GameVersion.set) so they run
-- even on a Red-only cache; the two screenshots force the Blue OG palette over
-- the overworld for visual before/after evidence.  Ground-truth RGB below is
-- Bulbapedia BG 0xFFFFFF/0x63A5FF/0x0000FF/0x000000, OBP0
-- 0xFFFFFF/0xFF8484/0x943A3A/0x000000.
--
-- Run:  SHOT_DIR=/tmp/ogblue POKEPORT_IDENTITY=bug155 POKEPORT_TOUCH=0 \
--         POKEPORT_DRIVER=tests/drivers/ogblue_palette_bug155_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  -- deep-equal for a 4-color {r,g,b} palette table
  local function palEq(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
      local ca, cb = a[i], b[i]
      if type(ca) ~= "table" or type(cb) ~= "table" then return false end
      if ca[1] ~= cb[1] or ca[2] ~= cb[2] or ca[3] ~= cb[3] then return false end
    end
    return true
  end

  local TRUE_BG  = { {255,255,255}, {99,165,255}, {0,0,255},   {0,0,0} }
  local TRUE_OBJ = { {255,255,255}, {255,132,132}, {148,58,58}, {0,0,0} }

  -- (1) the background constant is the real GBC Blue BG, not the periwinkle
  -- 0x8484FF/0x3A3A94 mirror of Red
  expect(palEq(PaletteFX.GBC_BG_BLUE, TRUE_BG),
         "GBC_BG_BLUE == real GBC Blue BG 0x63A5FF/0x0000FF, got",
         PaletteFX.GBC_BG_BLUE and PaletteFX.GBC_BG_BLUE[2]
           and table.concat(PaletteFX.GBC_BG_BLUE[2], ","))

  -- (2) a dedicated Blue OBJ (OBP0) constant exists and is the pink ramp
  expect(PaletteFX.GBC_OBJ_BLUE ~= nil and palEq(PaletteFX.GBC_OBJ_BLUE, TRUE_OBJ),
         "GBC_OBJ_BLUE == real GBC Blue OBP0 pink 0xFF8484/0x943A3A")
  -- (3) ... and it is NOT the green Red OBJ palette
  expect(PaletteFX.GBC_OBJ_BLUE ~= nil
           and not palEq(PaletteFX.GBC_OBJ_BLUE, PaletteFX.GBC_OBJ),
         "Blue OBJ is NOT the green Red GBC_OBJ")

  -- (4) version routing: as Blue, the OG helpers resolve Blue's palettes
  local savedVer = GameVersion.get()
  GameVersion.set("blue")
  expect(palEq(PaletteFX.ogBg(), TRUE_BG), "ogBg() -> Blue BG when isBlue()")
  expect(type(PaletteFX.ogObj) == "function", "PaletteFX.ogObj() helper exists")
  if type(PaletteFX.ogObj) == "function" then
    local c = PaletteFX.ogObj()
    expect(palEq(c, TRUE_OBJ), "ogObj() -> Blue pink OBJ when isBlue()")
  end

  -- (5) version routing: as Red, the OG helpers still resolve Red's palettes
  -- (green player over the red field is correct and must not regress)
  GameVersion.set("red")
  expect(palEq(PaletteFX.ogBg(), PaletteFX.GBC_BG), "ogBg() -> Red BG when Red")
  if type(PaletteFX.ogObj) == "function" then
    expect(palEq(PaletteFX.ogObj(), PaletteFX.GBC_OBJ),
           "ogObj() -> green Red OBJ when Red")
  end

  -- Visual proof: force Blue's OG palette over the (Red-cache) overworld.  The
  -- terrain colors come from ogBg() and the player sprite from ogObj(), so the
  -- shot exercises the exact code the fix touches.  Before: periwinkle terrain
  -- + green player; after: light-blue/blue terrain + pink player, matching
  -- the Gambatte capture attached to #155.
  GameVersion.set("blue")
  game.save.options = game.save.options or {}
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")

  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "SQUIRTLE", 5) }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(60)
  U.shot(game, DIR .. "/ogblue_01_route1.png")

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(60)
  U.shot(game, DIR .. "/ogblue_02_pallet.png")

  GameVersion.set(savedVer)

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed")
end
