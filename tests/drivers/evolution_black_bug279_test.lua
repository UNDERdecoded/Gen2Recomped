-- Driver: the evolution flash must put the WHOLE screen on PAL_BLACK (#279).
-- pokered engine/movie/evolution.asm EvolveMon flashes under PAL_BLACK; only the
-- settled form wears a mon palette, and PAL_BLACK keeps colour 0 as paper white
-- (sgb_palettes.asm:46), so the background behind the silhouettes stays put.
--   POKEPORT_DRIVER=tests/drivers/evolution_black_bug279_test.lua \
--     POKEPORT_IDENTITY=bug279 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local EvolutionState = require("src.ui.EvolutionState")
  local Pokemon = require("src.pokemon.Pokemon")
  local Evolution = require("src.pokemon.Evolution")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function rgb(c)
    return c and ("(%d,%d,%d)"):format(c[1], c[2], c[3]) or "nil"
  end
  local function ramp(p)
    if not p then return "nil" end
    local s = {}
    for i = 1, 4 do s[i] = rgb(p[i]) end
    return table.concat(s, " ")
  end
  local function samePal(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
      if not a[i] or not b[i] then return false end
      for k = 1, 3 do if a[i][k] ~= b[i][k] then return false end end
    end
    return true
  end

  -- Text speed 1 keeps the "Congratulations!" box brisk; FLASH_FRAMES is a
  -- frame count, so the flash itself is unaffected.
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  -- =====================================================================
  -- Part 1: the halves the eye cannot check.  A missing BLACK entry or a zone
  -- that does not cover the screen looks exactly like the bug.
  -- =====================================================================
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  local BLACK = PaletteFX.pal(game.data, "BLACK")
  check(BLACK ~= nil, "data.palettes carries a BLACK entry (PAL_BLACK)")
  U.log("BLACK ramp:", ramp(BLACK))
  -- sgb_palettes.asm RGB 31,29,31 / 07,07,07 / 02,03,03 / 03,02,02, scaled
  -- to 8 bits by the extractor
  check(BLACK and BLACK[1][1] == 255 and BLACK[1][2] == 239 and BLACK[1][3] == 255,
        "PAL_BLACK colour 0 is still paper white (the background does NOT black out)")
  check(BLACK and BLACK[2][1] == 58 and BLACK[3][1] == 16 and BLACK[4][1] == 25,
        "PAL_BLACK shades 1..3 are crushed (58,58,58 / 16,25,25 / 25,16,16)")

  -- sgbPalettes is a pure function of the state's own fields, so drive it
  -- directly for the cases the live run cannot hold still.  MAGIKARP is REDMON
  -- and GYARADOS BLUEMON: a CATERPIE line settles on GREENMON either way and
  -- would prove nothing.
  local function zonesFor(fields)
    local fake = setmetatable(fields, EvolutionState)
    return EvolutionState.sgbPalettes(fake, game)
  end
  local function colorsFor(fields)
    local z = zonesFor(fields)
    return z and z[1] and z[1].colors, z and z[1]
  end

  local flashCols, flashZone = colorsFor({
    done = false, canceled = false,
    mon = { species = "MAGIKARP" }, newSpecies = "GYARADOS",
  })
  check(samePal(flashCols, BLACK),
        "mid-flash the whole screen is PAL_BLACK, not a mon palette")
  U.log("mid-flash zone resolves to:", ramp(flashCols))
  check(flashZone ~= nil and flashZone.x == 0 and flashZone.y == 0
        and flashZone.w == 160 and flashZone.h == 144,
        "that zone covers the whole 160x144 screen (SetPal_PokemonWholeScreen)")

  local settled = colorsFor({
    done = true, canceled = false,
    mon = { species = "MAGIKARP" }, newSpecies = "GYARADOS",
  })
  check(samePal(settled, PaletteFX.monPal(game.data, "GYARADOS")),
        "once .done, the NEW form wears its own palette again (GYARADOS/BLUEMON)")
  local cancelled = colorsFor({
    done = true, canceled = true,
    mon = { species = "MAGIKARP" }, newSpecies = "GYARADOS",
  })
  check(samePal(cancelled, PaletteFX.monPal(game.data, "MAGIKARP")),
        "a B-cancelled evolution settles on the OLD form (MAGIKARP/REDMON)")

  -- Mode guards: routing the blackout through PaletteFX.pal is what keeps the
  -- other COLORS modes honest.  A hardcoded {0,0,0} passes everything above.
  PaletteFX.setMode("ogred")
  local ogFlash = colorsFor({
    done = false, canceled = false,
    mon = { species = "WEEDLE" }, newSpecies = "KAKUNA",
  })
  check(samePal(ogFlash, PaletteFX.ogBg()),
        "OG RED does NOT black out (a Game Boy Color never sees the SGB packet)")
  PaletteFX.setMode("redpp")
  check(PaletteFX.pal(game.data, "BLACK") ~= nil,
        "RED++ resolves BLACK from data/palettes_gbc.lua (no ROM fallback needed)")
  PaletteFX.setMode("og")
  check(samePal(PaletteFX.effectiveColors(BLACK), PaletteFX.GRAYS),
        "plain DMG replaces it wholesale, so the mono modes are unchanged")
  PaletteFX.setMode("gbc")
  game.save.options.colors = "gbc"

  -- The bytes the pixel probe hunts for, read out of the data and read while
  -- the mode is SGB (under OG RED, PaletteFX.pal short-circuits every name to
  -- the one palette).
  local YELLOW = PaletteFX.monPal(game.data, "WEEDLE")   -- YELLOWMON
  local REDMON = PaletteFX.monPal(game.data, "MAGIKARP") -- REDMON
  local BLUE = PaletteFX.monPal(game.data, "GYARADOS")   -- BLUEMON
  local OGBG = PaletteFX.GBC_BG
  check(YELLOW ~= nil and REDMON ~= nil and BLUE ~= nil,
        "WEEDLE/MAGIKARP/GYARADOS mon palettes resolve")
  U.log("WEEDLE:", ramp(YELLOW), " MAGIKARP:", ramp(REDMON),
        " GYARADOS:", ramp(BLUE))

  local function probe(label, wanted)
    local shot = Probe.grab()
    if not shot then
      U.log("WARN pixel probe unavailable (no screenshot capture); judge",
            label, "by eye only")
      return nil
    end
    local counts, total = Probe.count(shot, wanted)
    local parts = {}
    for name, n in pairs(counts) do
      parts[#parts + 1] = ("%s=%d"):format(name, n)
    end
    table.sort(parts)
    U.log(("probe[%s] %d px sampled: %s"):format(label, total,
          table.concat(parts, " ")))
    return counts
  end

  -- =====================================================================
  -- Part 2: reach the moment and photograph it.
  -- =====================================================================
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)

  local function evoTop()
    local t = game.stack:top()
    return (t and t.screenId == "EvolutionState") and t or nil
  end
  local function waitFor(cond, max)
    for _ = 1, max or 600 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  local function pagesText(st)
    if not st or not st.pages then return nil end
    local parts = {}
    for _, page in ipairs(st.pages) do
      if type(page) == "table" then
        for _, line in ipairs(page) do
          if type(line) == "string" then parts[#parts + 1] = line end
        end
      elseif type(page) == "string" then
        parts[#parts + 1] = page
      end
    end
    return table.concat(parts, " ")
  end
  local function findText(needle)
    for _, st in ipairs(game.stack.states or {}) do
      local blob = pagesText(st)
      if blob and blob:find(needle, 1, true) then return st end
    end
    return nil
  end
  local function mashUntil(cond, max)
    for _ = 1, max or 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return cond()
  end

  -- Jump the flash clock to just under FLASH_FRAMES (220) once the shot is
  -- taken.  EvolutionState:update only compares self.t against that constant,
  -- so this ends the animation early without touching the palette logic.
  local function skipToEnd()
    local st = evoTop()
    if st then st.t = 214 end
  end

  local function startEvo(species, into)
    local mon = Pokemon.new(game.data, species, 7)
    table.insert(game.save.party, 1, mon)
    Evolution.evolve(game, mon, into)
    if not waitFor(evoTop, 300) then
      check(false, "EvolutionState opened for " .. species .. " -> " .. into)
      return nil
    end
    return mon
  end

  -- ---- case 1: the reported case, SGB, mid-flash --------------------------
  local weedle = startEvo("WEEDLE", "KAKUNA")
  U.wait(24) -- into the flash, far short of FLASH_FRAMES = 220
  U.shot(game, DIR .. "/evo279_1_flash_sgb.png")
  local c1 = probe("flash/SGB", {
    monYellow1 = YELLOW[2], monYellow2 = YELLOW[3],
    black1 = BLACK[2], black2 = BLACK[3], paper = BLACK[1],
  })
  if c1 then
    check(c1.monYellow1 == 0 and c1.monYellow2 == 0,
          "no WEEDLE/KAKUNA yellow anywhere on screen during the flash")
    check(c1.black1 + c1.black2 > 0,
          "the crushed PAL_BLACK shades ARE on screen (the silhouette)")
    check(c1.paper > 0,
          "paper white still fills the background (PAL_BLACK keeps colour 0)")
  end

  -- ---- case 1b: it comes back once the flash is over ----------------------
  skipToEnd()
  if not waitFor(function() return findText("evolved into") ~= nil end, 240) then
    check(false, "the Congratulations text appears when the flash ends")
  end
  U.wait(50) -- let the box finish typing before the shot
  U.shot(game, DIR .. "/evo279_2_congrats_sgb.png")
  local c2 = probe("congrats/SGB", {
    monYellow1 = YELLOW[2], monYellow2 = YELLOW[3], black1 = BLACK[2],
  })
  if c2 then
    check(c2.monYellow1 + c2.monYellow2 > 0,
          "the settled KAKUNA is yellow again under the Congratulations box")
  end
  check(weedle == nil or weedle.species == "KAKUNA",
        "the mon actually evolved (control: the fix touched no game logic)")
  mashUntil(function() return not evoTop() and not findText("evolved into") end, 90)
  U.wait(10)

  -- ---- case 2: B-cancel settles on the OLD form's colours -----------------
  local karp = startEvo("MAGIKARP", "GYARADOS")
  U.wait(24)
  U.hold(game, "b", 20) -- evolution.asm Evolution_CheckForCancel
  if not waitFor(function() return findText("stopped evolving") ~= nil end, 240) then
    check(false, "holding B prints \"stopped evolving\"")
  end
  U.wait(50)
  U.shot(game, DIR .. "/evo279_3_cancelled_sgb.png")
  local c3 = probe("cancelled/SGB", {
    red1 = REDMON[2], red2 = REDMON[3], blue1 = BLUE[2], blue2 = BLUE[3],
  })
  if c3 then
    check(c3.red1 + c3.red2 > 0,
          "a cancelled MAGIKARP settles back into MAGIKARP's own red")
    check(c3.blue1 == 0 and c3.blue2 == 0,
          "no GYARADOS blue leaks in (wEvoOldSpecies, not the new species)")
  end
  check(karp == nil or karp.species == "MAGIKARP", "the cancelled mon kept its species")
  mashUntil(function() return not evoTop() and not findText("stopped evolving") end, 90)
  U.wait(10)

  -- ---- case 3: OG RED must NOT black out ---------------------------------
  -- A Game Boy Color never sees the SGB packet, so its one global BG palette
  -- applies all the way through.  Switch mode with only the overworld on the
  -- stack: setMode's cache drop / map reload must not land on a live evolution.
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  U.wait(20)
  startEvo("WEEDLE", "KAKUNA")
  U.wait(24)
  U.shot(game, DIR .. "/evo279_4_flash_ogred.png")
  local c4 = probe("flash/OG RED", {
    ogPink = OGBG[2], ogRed = OGBG[3], black1 = BLACK[2], black2 = BLACK[3],
  })
  if c4 then
    check(c4.ogPink + c4.ogRed > 0, "OG RED stays red/pink through the flash")
    check(c4.black1 == 0 and c4.black2 == 0,
          "PAL_BLACK's crushed shades never appear in OG RED")
  end
  skipToEnd()
  waitFor(function() return findText("evolved into") ~= nil end, 240)
  mashUntil(function() return not evoTop() and not findText("evolved into") end, 90)

  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  U.wait(20)

  U.log(fails == 0 and "all #279 preconditions passed"
                    or (fails .. " #279 precondition(s) FAILED -- read up"))

  -- =====================================================================
  -- Part 3: one more, live, for the human.
  -- =====================================================================
  startEvo("WEEDLE", "KAKUNA")

  U.log("A WEEDLE is evolving now in SGB colours, about four seconds.  While the")
  U.log("two forms trade places the whole screen is on PAL_BLACK: near-black")
  U.log("silhouettes on the unchanged off-white background, colour back only")
  U.log("under the Congratulations box.  #279 flashed both forms in full colour.")
  U.log("Hold B mid-flash to cancel; it settles on the OLD form's colours.")
  U.log("Screenshots: " .. DIR .. "/evo279_*.png")

  while true do
    coroutine.yield()
  end
end
