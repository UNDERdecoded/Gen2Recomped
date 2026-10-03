-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHERE EVERY SHEET'S WIDTH COMES FROM, AND WHETHER ANYTHING STILL GUESSES.
--
-- A sheet is a set of pieces with no tilemap. Laying it out needs a width, and
-- a wrong width is not a wrong size -- it is a DIFFERENT PICTURE, the same
-- tiles re-flowed into the wrong rectangle. `RomExtractorGen4:composeJob` has
-- four places a width can come from and returns which one it used:
--
--   byCell     a cell bank says where every piece goes; no width needed
--   stated     a width written down for the group in `Gen4Screens.ARCHIVES`
--   declared   the member's own NCGR header, where the archive invited it
--   fallback   the bare 8, which nobody stated -- a guess
--
-- WHY THIS CHECK EXISTS, and it is not the happy reason. The comment above
-- that block used to carry a census, and the census went stale: it said
-- twenty-six sheets were drawn at a width the file contradicts. Twenty-five of
-- those had since been resolved by cell-bank work, and reading the old number
-- as current turned ONE wrong picture into an imagined twenty-six -- a whole
-- pass spent on a backlog that no longer existed. A stale pin measures
-- nothing; a stale comment is worse, because it reads like a measurement.
--
-- So the census lives here, where it runs.
--
-- THE ONE THING THAT WAS ACTUALLY WRONG was the Pokedex's weight scale:
-- `weight_scale` (zukan member 36) declares 16x2 and was laid out 8 wide, so a
-- 128x16 bar extracted as 64x32. Three sources agree on 128x16 -- the header,
-- the fact that 16*2 is exactly its 32 tiles, and pokeplatinum centring it as
-- `xPos = 128 - (128 / 2)`, `yPos = 96 - (16 / 2)` in ov21_021E7F40. It is a
-- SoftwareSprite, so it has no cell bank and no bank work would have found it.
--
-- IT IS NOT A VISIBLE FAULT, and this file should not be read as claiming one:
-- `Gen4Pokedex` takes its art from `gen4_dex` and nothing reads this sheet. It
-- was fixed so that section 1 can pin an exact zero instead of carrying a known
-- exception in prose, which is how the last figure here went stale.
--
-- WHAT IS PINNED, and why these shapes:
--   * the four provenances, as FLOORS for the three legitimate ones (an
--     archive added tomorrow raises them) and EXACTLY ZERO for `fallback`,
--     because growth there is never legitimate -- it means a new archive
--     arrived with no bank, no stated width and a silent header;
--   * no sheet drawn at a width its own header contradicts. Exactly zero.
--     This is the general form of the weight_scale fault;
--   * where a stated width and a declared one BOTH exist they must agree.
--     They do, 36 times out of 36, which is what licenses the hand-measured
--     table in `ARCHIVES` as cartridge-derived rather than merely plausible;
--   * `preferDeclaredSize` is read off `ARCHIVES` rather than listed here,
--     with the count pinned -- the hardcoded twin of that flag is exactly what
--     went stale in `gen4_mining_art_check` and had to be repaired in pass 157;
--   * every archive carrying the flag must have a member that NEEDS it, so the
--     flag cannot be cargo-culted onto an archive where it does nothing.
--
-- It needs the ROM: a NARC member's declared tilesX cannot be read anywhere
-- else, and the whole question is what the cartridge says.
--
-- Usage: texlua tools/gen4_sheet_layout_check.lua <platinum .nds> [cache dir]
--    or: python tools/run_lua_check.py tools/gen4_sheet_layout_check.lua <rom>
--
-- The optional cache dir is a staleness probe, not part of the census: a
-- `gen4_graphics` written before this provenance existed carries no
-- `layoutFrom` at all, and such a cache needs a re-extract before any of the
-- above is visible in the game.

package.path = "./?.lua;" .. package.path

-- LuaJIT has `bit`; texlua has not. Preloading unconditionally would shadow
-- the real one under run_lua_check.py.
if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local function tou32(v) return math.floor(v) % 4294967296 end
    local function op(a, b, f)
      a, b = tou32(a), tou32(b)
      local r, m = 0, 1
      for _ = 1, 32 do
        r = r + f(a % 2, b % 2) * m
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end
    local M = {}
    function M.band(a, b) return op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
    function M.bor(a, b) return op(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end
    function M.bxor(a, b) return op(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end
    function M.bnot(a) return 4294967295 - tou32(a) end
    function M.lshift(a, n) return tou32(tou32(a) * 2 ^ n) end
    function M.rshift(a, n) return math.floor(tou32(a) / 2 ^ n) end
    function M.arshift(a, n) return M.rshift(a, n) end
    function M.tobit(a) local v = tou32(a) return v >= 2147483648 and v - 4294967296 or v end
    function M.tohex(a) return ("%08x"):format(tou32(a)) end
    return M
  end
end

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 240 end, getHeight = function() return 160 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local ROM = arg and arg[1]
local CACHE = arg and arg[2]
if not ROM then
  io.write("Pass the Platinum .nds as the first argument.\n")
  os.exit(2)
end

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local okN, Nds = pcall(require, "src.import.NdsRom")
local okA, Narc = pcall(require, "src.import.NarcArchive")
local okG, Graphics = pcall(require, "src.import.Gen4Graphics")
local okS, Screens = pcall(require, "src.import.Gen4Screens")
local okE, Extractor = pcall(require, "src.import.RomExtractorGen4")
ok(okN and okA and okG and okS and okE,
   "a loader did not load: %s %s %s %s %s", tostring(Nds), tostring(Narc),
   tostring(Graphics), tostring(Screens), tostring(Extractor))
if not (okN and okA and okG and okS and okE) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local rom, why = Nds.open(ROM)
ok(rom ~= nil, "%s did not open as an NDS ROM: %s", ROM, tostring(why))
if not rom then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

-- THE WALK.
--
-- `composeJob` is called for real, so the provenance is the engine's own
-- answer rather than this file's copy of its rules -- the copy is exactly what
-- would drift. Only `Gen4Graphics.compose` is stood down, and only to skip
-- allocating 364 pictures: the width block under test runs as shipped and its
-- second return value is what gets counted.
local realCompose = Graphics.compose
local composeCalls = 0
Graphics.compose = function(map, sheet, palette, firstTile)
  composeCalls = composeCalls + 1
  return { width = map.width, height = map.height, stub = true }
end

local function declaredWidth(arc, job)
  local data = job.tiles and arc:get(job.tiles)
  if not data then return nil end
  if Graphics.isCompressed(data) then data = Graphics.decompress(data) end
  local sheet = Graphics.tiles(data)
  if not sheet then return nil end
  local x = sheet.tilesX
  if x and x > 0 and x ~= 0xFFFF then return x, sheet.tilesY, sheet.count end
  return nil, nil, sheet.count
end

local census = { byCell = 0, stated = 0, declared = 0, fallback = 0, other = 0 }
local guessed = {}
local contradicted, disagreed, agreed, headerSilent = {}, {}, 0, 0
local flagged, flaggedUsed, sheets = {}, {}, 0
local widthUsed = {}

for _, a in ipairs(Screens.ARCHIVES) do
  if a.preferDeclaredSize then flagged[a.path] = true end
end

for _, a in ipairs(Screens.ARCHIVES) do
  local raw = rom:read(a.path)
  if raw then
    local arc = Narc.parse(raw)
    for _, job in ipairs(Screens.plan(a.path, a) or {}) do
      if job.kind == Screens.SHEET and not job.tilemap then
        sheets = sheets + 1
        if job.cell then
          census.byCell = census.byCell + 1
        else
          local img, layout = Extractor.composeJob({}, arc, job)
          local decl, declY, count = declaredWidth(arc, job)
          if census[layout] then census[layout] = census[layout] + 1
          else census.other = census.other + 1 end
          if layout == "fallback" then
            guessed[#guessed + 1] = ("%s %s (header says %s)")
              :format(a.path, tostring(job.name), decl and tostring(decl) or "nothing")
          end

          -- WHAT WIDTH DID THE PICTURE ACTUALLY COME OUT AT. Taken from the
          -- composed width in pixels, not from re-running the choice: this is
          -- the number a player would see.
          local used = img and img.width and (img.width / 8) or nil
          widthUsed[#widthUsed + 1] = { path = a.path, name = job.name, used = used }

          if decl and used and used ~= decl then
            contradicted[#contradicted + 1] = ("%s %s: drawn %d wide, header says %d")
              :format(a.path, tostring(job.name), used, decl)
          end

          if job.tilesWideStated then
            if decl then
              if decl == job.tilesWide then agreed = agreed + 1
              else
                disagreed[#disagreed + 1] = ("%s %s: stated %s, header %d")
                  :format(a.path, tostring(job.name), tostring(job.tilesWide), decl)
              end
            else
              headerSilent = headerSilent + 1
            end
          end

          -- An archive carrying the flag has to have a member that NEEDS it:
          -- not stated, and declaring a size. Otherwise the flag is decoration.
          if flagged[a.path] and not job.tilesWideStated and decl then
            flaggedUsed[a.path] = (flaggedUsed[a.path] or 0) + 1
          end
        end
      end
    end
  end
end

section("1. the census, which is the thing that went stale")
-- FLOORS for the three legitimate provenances. A new archive raises them and
-- that is not a regression; the check is that none of them COLLAPSES, which
-- would mean a path stopped being exercised at all.
ok(census.byCell >= 179, "only %d sheet(s) come from a cell bank (was 179)", census.byCell)
ok(census.stated >= 109, "only %d sheet(s) take a stated width (was 109)", census.stated)
ok(census.declared >= 76, "only %d sheet(s) take their header's width (was 76)", census.declared)
-- EXACT, and the only exact one. `fallback` is the bare 8 that nobody stated.
-- If this ever moves, an archive was added without a cell bank, without a
-- width in ARCHIVES, and with members whose header says 0xFFFF -- and its
-- pictures are guesses. Give it one of the three, do not raise this number.
ok(census.fallback == 0,
   "%d sheet(s) are laid out at a width NOBODY states:\n    %s",
   census.fallback, table.concat(guessed, "\n    "))
ok(census.other == 0, "%d sheet(s) returned a provenance that is none of the four", census.other)
-- The totals have to add up to the sheets walked, or something was skipped
-- silently and every number above is measuring a subset.
ok(census.byCell + census.stated + census.declared + census.fallback + census.other == sheets,
   "the four provenances total %d but %d sheets were walked",
   census.byCell + census.stated + census.declared + census.fallback + census.other, sheets)
ok(sheets >= 364, "only %d sheets walked (was 364)", sheets)
-- composeJob really ran, rather than every sheet taking an early return and
-- leaving the census a count of nils.
ok(composeCalls >= 185, "composeJob composed only %d time(s); the census is not measuring the engine",
   composeCalls)

section("2. no sheet drawn at a width its own header contradicts")
ok(#contradicted == 0, "%d contradicted sheet(s):\n    %s",
   #contradicted, table.concat(contradicted, "\n    "))

section("3. stated and declared agree wherever both exist")
ok(#disagreed == 0, "%d disagreement(s):\n    %s", #disagreed, table.concat(disagreed, "\n    "))
ok(agreed >= 36, "only %d stated width(s) are confirmed by a header (was 36)", agreed)
-- The other side of the same coin: if this went to zero, the stated table
-- would be redundant and the agreement above would be the whole story.
ok(headerSilent >= 73, "only %d stated width(s) sit on a silent header (was 73)", headerSilent)

section("4. preferDeclaredSize, derived from ARCHIVES and not listed here")
local flaggedCount = 0
for _ in pairs(flagged) do flaggedCount = flaggedCount + 1 end
ok(flaggedCount == 8,
   "%d archive(s) carry preferDeclaredSize, not 8; if one was added, say so here and re-measure section 1",
   flaggedCount)

-- THREE OF THE EIGHT ARE INERT, AND THAT IS ON PURPOSE. The five Underground
-- rows carry the flag uniformly by an explicit decision recorded in
-- `Gen4Screens`: "kept on all three for that one sheet and for the screens".
-- The one sheet is `smoke_tiles` in ug_trap; ug_fossil, ug_anim and
-- underg_radar have nothing that declares a size, so the flag does nothing
-- there and removing it would change no picture.
--
-- Asserting every flag is load-bearing would therefore fail on a correct file
-- -- the same over-strictness that once rejected six legitimately prefix-matched
-- boulder banks. So the inert ones are NAMED and COUNTED instead: a fourth
-- inert flag is a new fact and fails, and one of the five below going inert
-- fails too.
local INERT_BY_DESIGN = {
  ["/data/ug_fossil.narc"] = true,
  ["/data/ug_anim.narc"] = true,
  ["/data/underg_radar.narc"] = true,
}
local inert = 0
for path in pairs(flagged) do
  if INERT_BY_DESIGN[path] then
    inert = inert + 1
    ok((flaggedUsed[path] or 0) == 0,
       "%s now has a member that needs preferDeclaredSize; it was inert by design -- "
       .. "re-measure section 1 and move it out of INERT_BY_DESIGN", path)
  else
    ok((flaggedUsed[path] or 0) > 0,
       "%s carries preferDeclaredSize but no member there needs it -- the flag does "
       .. "nothing, so either it is decoration or a member stopped declaring", path)
  end
end
ok(inert == 3, "%d of the flagged archives are inert by design, not 3", inert)

section("5. the Pokedex weight scale, the one that was actually wrong")
local ZK = "/resource/eng/zukan/zukan.narc"
local zrow
for _, a in ipairs(Screens.ARCHIVES) do if a.path == ZK then zrow = a end end
ok(zrow ~= nil, "the zukan archive is no longer in ARCHIVES")
if zrow then
  ok(zrow.preferDeclaredSize == true,
     "zukan no longer invites its headers; weight_scale goes back to 64x32")
  local arc = Narc.parse(rom:read(ZK))
  local job
  for _, j in ipairs(Screens.plan(ZK, zrow) or {}) do
    if j.kind == Screens.SHEET and j.tiles == 36 and not j.tilemap then job = j end
  end
  ok(job ~= nil, "zukan member 36 is no longer planned as a sheet")
  if job then
    ok(job.name == "weight_scale", "zukan member 36 is now %s, not weight_scale", tostring(job.name))
    local decl, declY, count = declaredWidth(arc, job)
    ok(decl == 16, "weight_scale declares %s tiles wide, not 16", tostring(decl))
    ok(declY == 2, "weight_scale declares %s tiles tall, not 2", tostring(declY))
    -- The cartridge's shape accounts for the whole member. 8x4 would too, which
    -- is why this is recorded as agreement and not as the discriminator.
    ok(decl and declY and count and decl * declY == count,
       "weight_scale's declared %sx%s does not account for its %s tiles",
       tostring(decl), tostring(declY), tostring(count))
    -- THE DISCRIMINATOR, from pokeplatinum: ov21_021E7F40 centres the sprite as
    -- xPos = 128 - (128 / 2) and yPos = 96 - (16 / 2). The arithmetic states the
    -- size, 128 by 16 pixels, and 8 wide cannot produce it.
    local img, layout = Extractor.composeJob({}, arc, job)
    ok(layout == "declared", "weight_scale's width came from %s, not the header", tostring(layout))
    ok(img and img.width == 128, "weight_scale composed %s px wide, not pokeplatinum's 128",
       tostring(img and img.width))
    ok(img and img.height == 16, "weight_scale composed %s px tall, not pokeplatinum's 16",
       tostring(img and img.height))
  end
end

section("6. the fix re-flows the tiles rather than changing them")
-- Restore the real compose: this section is about pixels, so a stub would make
-- it a measurement that cannot fail.
Graphics.compose = realCompose
do
  local arc = Narc.parse(rom:read(ZK))
  local function jobAt(spec)
    for _, j in ipairs(Screens.plan(ZK, spec) or {}) do
      if j.kind == Screens.SHEET and j.tiles == 36 and not j.tilemap then return j end
    end
  end
  local asIs = jobAt(zrow)
  local without = {}
  for k, v in pairs(zrow) do without[k] = v end
  without.preferDeclaredSize = nil
  local old = jobAt(without)
  local a = asIs and select(1, Extractor.composeJob({}, arc, asIs))
  local b = old and select(1, Extractor.composeJob({}, arc, old))
  ok(a and b and a.rgba and b.rgba, "the weight scale did not compose both ways")
  if a and b and a.rgba and b.rgba then
    ok(#a.rgba == #b.rgba, "the two layouts hold %d and %d bytes", #a.rgba, #b.rgba)
    -- DIFFERENT PICTURE: if these matched, the flag would not be doing anything
    -- and section 5 would be passing on a coincidence.
    ok(a.rgba ~= b.rgba, "both widths composed byte-identical output; the flag changed nothing")
    -- SAME PIXELS: a width fix re-flows tiles. If the multiset moved, something
    -- is being dropped or invented rather than rearranged.
    local function multiset(s)
      local h = {}
      for i = 1, #s - 3, 4 do local k = s:sub(i, i + 3) h[k] = (h[k] or 0) + 1 end
      return h
    end
    local ha, hb = multiset(a.rgba), multiset(b.rgba)
    local same = true
    for k, v in pairs(ha) do if hb[k] ~= v then same = false break end end
    for k, v in pairs(hb) do if ha[k] ~= v then same = false break end end
    ok(same, "the 128x16 layout is not a permutation of the 64x32 one -- pixels changed, not just their places")
  end
end

section("7. is the installed cache old enough to be hiding all of this")
if not CACHE then
  io.write("   (no cache dir given -- skipped; pass one to probe it)\n")
else
  local path = CACHE .. "/gen4_graphics.lua"
  local f = io.open(path, "rb")
  ok(f ~= nil, "%s does not exist", path)
  if f then
    local text = f:read("*a")
    f:close()
    local provisional = select(2, text:gsub("provisionalLayout%s*=%s*true", ""))
    local from = select(2, text:gsub('layoutFrom%s*=%s*"', ""))
    -- `layoutFrom` is written for every non-tilemap sheet. A cache with none at
    -- all predates the provenance entirely, whatever else it contains, and the
    -- numbers in section 1 cannot be seen in the game until it is re-extracted.
    ok(from > 0,
       "%s carries %d provisionalLayout flag(s) and NO layoutFrom: it predates the "
       .. "provenance and needs a re-extract before any of the above is visible",
       path, provisional)
    if from > 0 then
      ok(provisional == 0,
         "%s still flags %d sheet(s) provisional; section 1 says none should be",
         path, provisional)
    end
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
