-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the Underground's mining art extracts at the size the
-- cartridge states, that those sizes agree with a completely separate source,
-- and -- the part that matters most -- that inviting the extractor to believe a
-- sheet's own header changes NOTHING for any archive that did not ask for it.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: `preferDeclaredSize` looks like a
-- harmless improvement that should simply be the default, and section 3 asserts
-- the opposite of the usual thing -- that the change is inert for every archive
-- that did not ask for it.
--
-- WHAT THIS FILE USED TO SAY HERE, AND WHY IT WAS WRONG. It claimed twenty-six
-- sheets were drawn at a width the file contradicts, pl_winframe's message boxes
-- among them, and that turning the flag on globally would redraw twenty-six
-- pictures. That figure came from section 4 comparing each sheet's header against
-- `job.tilesWide` WITHOUT ASKING WHETHER THE SHEET IS LAID OUT AT THAT WIDTH AT
-- ALL. Twenty-five of the twenty-six are assembled through a cell bank, which
-- decides their shape outright and makes the nominal width irrelevant --
-- pl_winframe's are exactly those. So the count was 25 phantoms and ONE real
-- fault: zukan's `weight_scale`, declared 16x2 and drawn 8 wide, which is fixed.
-- The phantoms never needed fixing.
--
-- The number was wrong the day it was written, not merely stale, and it was
-- quoted twice afterwards as a live backlog. Section 4 now compares the header
-- against the width the picture ACTUALLY came out at, and counts the
-- bank-assembled sheets separately instead of silently among the faults.
--
-- It calls the extractor's real `composeJob` rather than restating its three-line
-- precedence: the function touches no `self` (checked -- zero references in its
-- 75 lines), so a dummy receiver exercises the shipped decision itself.
--
-- Usage: texlua tools/gen4_mining_art_check.lua <rom>

local romPath = arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_mining_art_check.lua <rom>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom   = require("src.import.NdsRom")
local Narc     = require("src.import.NarcArchive")
local Graphics = require("src.import.Gen4Graphics")
local Screens  = require("src.import.Gen4Screens")
local Archives = require("src.import.Gen4Archives")
local Mining   = require("src.import.Gen4Mining")
local Extractor = require("src.import.RomExtractorGen4")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local rom = NdsRom.open(romPath)
if not rom then
  io.stderr:write("could not open " .. romPath .. "\n")
  os.exit(2)
end

-- WHICH ARCHIVES MAY TAKE THE DECLARED-SIZE BRANCH: the ones that ask for it,
-- READ OFF THE TABLE rather than listed again here.
--
-- It was a literal list of two, and that is this port's recurring bug in
-- miniature: one fact spelled in two files that never meet. Pass 154 declared
-- three more Underground archives with `preferDeclaredSize`, this list did not
-- know, and the result was THREE failures that were all one staleness.
--
-- SO IT WAS DERIVED -- from `preferDeclaredSize`, which was the WRONG PROPERTY
-- and broke the moment the flag was wanted for something other than the
-- Underground. Three non-Underground archives now carry it (zukan, the bag and
-- the Poketch, for members whose own header states a size), and this set quietly
-- swallowed all three: `flagged` read 8, and section 4 stopped measuring those
-- archives at all because they had become "the Underground".
--
-- The property actually meant is the one in the table: `out == "underground"`.
-- It names the same five archives, it does not move when the flag is used
-- elsewhere, and it restores section 4's 65 exactly. Deriving from a proxy that
-- merely coincides is the same bug as hardcoding; it just takes longer to bite.
local UG, flagged, flaggedOutside = {}, 0, 0
for _, a in ipairs(Screens.ARCHIVES) do
	if a.out == "underground" then
		UG[a.path] = true
		flagged = flagged + 1
	elseif a.preferDeclaredSize then
		flaggedOutside = flaggedOutside + 1
	end
end

-- ---------------------------------------------------------------------------
section("1. the archives are in the plan, and the ROM has them")
-- ---------------------------------------------------------------------------
local entries = {}
for _, a in ipairs(Screens.ARCHIVES) do
  if UG[a.path] then entries[a.path] = a end
end
-- DERIVING THE SET MUST NOT MEAN IT CAN GROW UNNOTICED. Five archives are the
-- Underground's today; a sixth has to be acknowledged here, because section 4's
-- figures are measured over everything outside this set and would shift the
-- moment it changed.
ok(flagged == 5,
   "%d archive(s) have out=\"underground\" and 5 were recorded -- if one was added, say so here and re-measure section 4", flagged)
-- And the flag OUTSIDE the Underground is pinned too, because that coupling is
-- what broke this file. A fourth such archive is a new fact, not a detail.
ok(flaggedOutside == 3,
   "%d non-Underground archive(s) set preferDeclaredSize, not 3 -- tools/gen4_sheet_layout_check.lua owns that census", flaggedOutside)
for path in pairs(UG) do
  ok(entries[path] ~= nil, "%s is not in Gen4Screens.ARCHIVES", path)
  local raw = rom:read(path)
  ok(raw ~= nil, "%s is not in this ROM", path)
  if raw and entries[path] then
    local narc = Narc.parse(raw)
    local names = Archives.names(path)
    io.write(("  %-24s %3d members, %3d names, out=%s, preferDeclaredSize=%s\n")
             :format(path, narc.count, names and #names or -1,
                     tostring(entries[path].out),
                     tostring(entries[path].preferDeclaredSize)))
    -- A NARC has no directory, so the only thing tying a name to an index is
    -- the count agreeing. If it does not, every name is off by something.
    ok(names ~= nil and #names == narc.count,
       "%s: %d members but %s names -- the name table does not fit this archive",
       path, narc.count, names and #names or "no")
    ok(entries[path].preferDeclaredSize == true,
       "%s must set preferDeclaredSize; its sheets state their own sizes", path)
  end
end

-- ---------------------------------------------------------------------------
section("2. every ug_parts sheet states its own size, and the sizes are right")
-- ---------------------------------------------------------------------------
-- The other source: Gen4Mining.OBJECTS, whose sizes come from sMiningObjects,
-- compiled into an ARM9 overlay -- nothing to do with the NCGR headers. Two tiles
-- per mining cell, because Mining_DrawBuriedObject indexes the tilemap in tiles
-- and strides by the record's stored width, which is cells * 2.
local want = {}
for _, o in ipairs(Mining.OBJECTS) do
  local n = o.sprite:gsub("_NCGR$", ".NCGR")
  want[n] = want[n] or {}
  want[n][(o.w * 2) .. "x" .. (o.h * 2)] = true
end
local narc = Narc.parse(rom:read("/data/ug_parts.narc"))
local names = Archives.names("/data/ug_parts.narc")
local sheets, declared, agreed, notInTable = 0, 0, 0, {}
for i, n in ipairs(names or {}) do
  if n:match("%.NCGR$") then
    sheets = sheets + 1
    local data = narc:get(i - 1)
    if data and Graphics.isCompressed(data) then data = Graphics.decompress(data) end
    local sheet = data and Graphics.tiles(data)
    ok(sheet ~= nil, "%s did not decode as a tile sheet", n)
    if sheet then
      if sheet.tilesX and sheet.tilesY then declared = declared + 1 end
      ok(sheet.tilesX ~= nil and sheet.tilesY ~= nil,
         "%s declares no tilesX/tilesY, so preferDeclaredSize cannot help it "
         .. "and it needs a width written down", n)
      local w = want[n]
      if not w then notInTable[#notInTable + 1] = n
      elseif sheet.tilesX then
        local hit = false
        for s in pairs(w) do
          local ww, hh = s:match("(%d+)x(%d+)")
          if tonumber(ww) == sheet.tilesX and tonumber(hh) == sheet.tilesY then hit = true end
        end
        if hit then agreed = agreed + 1 end
        local list = {}
        for s in pairs(w) do list[#list + 1] = s end
        table.sort(list)
        ok(hit, "%s declares %dx%d but the mining table says %s",
           n, sheet.tilesX, sheet.tilesY, table.concat(list, " or "))
      end
    end
  end
end
io.write(("  %d NCGR members, %d declare a size, %d agree with the mining table\n")
         :format(sheets, declared, agreed))
io.write(("  not in the mining table: %s\n"):format(
  #notInTable > 0 and table.concat(notInTable, ", ") or "none"))
ok(sheets == 71, "expected 71 NCGR members in ug_parts, found %d", sheets)
ok(declared == sheets, "%d of %d sheets declare a size", declared, sheets)
ok(agreed == 70, "expected 70 of 71 to match the mining table, got %d", agreed)
-- dirt_tiles is the seven layers of earth, not a buried object, so it is right
-- that the mining table has no size for it.
ok(#notInTable == 1 and notInTable[1] == "dirt_tiles.NCGR",
   "expected only dirt_tiles.NCGR to be absent from the mining table, got %s",
   table.concat(notInTable, ", "))

-- ---------------------------------------------------------------------------
section("3. the change is inert for every archive that did not ask")
-- ---------------------------------------------------------------------------
-- composeJob returns the layout's provenance, so the question is simply which
-- archives reach the `declared` branch. The property is PER ARCHIVE: an archive
-- that did not set the flag must never reach it.
--
-- This used to test `not UG[a.path]` -- not-the-Underground -- which was the
-- same mistake as deriving UG from the flag: it only read as inertness while
-- the Underground and the flag were the same set. They no longer are, so the
-- test is now the flag itself, and the archives that DID ask are counted
-- separately and pinned.
local touched, invited, sheetsSeen, byProvenance = {}, {}, 0, {}
for _, a in ipairs(Screens.ARCHIVES) do
  local raw = rom:read(a.path)
  if raw then
    local arc = Narc.parse(raw)
    for _, job in ipairs(Screens.plan(a.path, a) or {}) do
      if not job.tilemap then
        sheetsSeen = sheetsSeen + 1
        local _, layout = Extractor.composeJob({}, arc, job)
        if layout then
          byProvenance[layout] = (byProvenance[layout] or 0) + 1
          if layout == "declared" then
            if not a.preferDeclaredSize then
              touched[#touched + 1] = a.path .. " / " .. tostring(job.name)
            elseif not UG[a.path] then
              invited[#invited + 1] = ("%s / %s%s"):format(
                a.path, tostring(job.name), job.cell and " (cell job)" or "")
            end
          end
        end
      end
    end
  end
end
local parts = {}
for k, v in pairs(byProvenance) do parts[#parts + 1] = ("%s=%d"):format(k, v) end
table.sort(parts)
io.write(("  %d sheets: %s\n"):format(sheetsSeen, table.concat(parts, " ")))
ok(#touched == 0,
   "%d sheet(s) in archives that never set preferDeclaredSize took the "
   .. "declared-size branch, so the flag is not doing what it says: %s", #touched,
   table.concat(touched, "; ", 1, math.min(#touched, 4)))
-- THE ARCHIVES THAT DID ASK, OUTSIDE THE UNDERGROUND. Five jobs, and the shape
-- of the five is the point: four are plain sheets whose header states a size
-- (bag/item_entry_icons, poketch/unused_apps, poketch/watch -- all three
-- declaring the 8 they already had -- and zukan/weight_scale, the one this
-- changed, 64x32 to 128x16). The fifth, poketch/map, is a CELL job: the real
-- extractor assembles it through its bank and never uses a composed width at
-- all, so it appears here only because this walk does not skip cell jobs.
ok(#invited == 5,
   "%d sheet(s) outside the Underground take their header's width, not 5: %s",
   #invited, table.concat(invited, "; "))
ok((byProvenance.declared or 0) > 0,
   "no sheet anywhere took the declared-size branch, so section 3 is asserting "
   .. "that an unreachable branch was not reached, which says nothing")
-- Both other branches still reachable. NOTE on `fallback`: this walk includes
-- CELL jobs, whose composed width the extractor discards, and every remaining
-- fallback is one of those. For plain sheets the count is zero -- which is
-- `tools/gen4_sheet_layout_check.lua` section 1, and it owns that number.
ok((byProvenance.stated or 0) > 0 and (byProvenance.fallback or 0) > 0,
   "the stated and fallback branches are not both exercised (stated=%d fallback=%d)",
   byProvenance.stated or 0, byProvenance.fallback or 0)

-- ---------------------------------------------------------------------------
section("4. sheets whose header differs from the width they are drawn at")
-- ---------------------------------------------------------------------------
-- THE COMPARISON THAT HAS TO BE RIGHT: a sheet's header against the width its
-- picture ACTUALLY came out at, which is not the same as `job.tilesWide`.
--
-- A cell-assembled sheet never uses a width at all -- its bank places every
-- piece -- so comparing its header to the nominal width asks a question that
-- has no meaning and answers it with a fault. That is precisely how this
-- section produced twenty-six: twenty-five bank-assembled sheets plus one real
-- one. They are now counted apart, and the real count is pinned at zero.
local declaresElsewhere, contradicted, byBank, examples = 0, 0, 0, {}
for _, a in ipairs(Screens.ARCHIVES) do
  if not UG[a.path] then
    local raw = rom:read(a.path)
    if raw then
      local arc = Narc.parse(raw)
      for _, job in ipairs(Screens.plan(a.path, a) or {}) do
        if not job.tilemap then
          local data = job.tiles and arc:get(job.tiles)
          if data and Graphics.isCompressed(data) then data = Graphics.decompress(data) end
          local sheet = data and Graphics.tiles(data)
          if sheet and sheet.tilesX then
            declaresElsewhere = declaresElsewhere + 1
            -- The width the picture came out at. For a cell sheet there is no
            -- such width, and `byBank` is where it goes instead.
            local drawn
            if job.cell then
              byBank = byBank + 1
            else
              local img = Extractor.composeJob({}, arc, job)
              drawn = img and img.width and (img.width / 8) or (job.tilesWide or 8)
            end
            if drawn and sheet.tilesX ~= drawn then
              contradicted = contradicted + 1
              if #examples < 4 then
                examples[#examples + 1] = ("%s/%s drawn %d wide, declares %dx%d")
                  :format(a.path:match("([^/]+)%.narc$") or a.path,
                          tostring(job.name), drawn,
                          sheet.tilesX, sheet.tilesY)
              end
            end
          end
        end
      end
    end
  end
end
io.write(("  outside the Underground: %d sheets declare a size; %d of them are "
          .. "placed by a cell bank and use no width at all; %d are drawn at a "
          .. "width their header contradicts\n")
         :format(declaresElsewhere, byBank, contradicted))
for _, e in ipairs(examples) do io.write("    " .. e .. "\n") end
ok(declaresElsewhere == 65, "expected 65 declaring sheets elsewhere, found %d",
   declaresElsewhere)
-- EXACTLY ZERO, and this is the assertion the old 26 should always have been.
-- A sheet here is drawn at a width its own file contradicts: that is a wrong
-- picture, not a backlog item. Raising this number is never the fix -- give the
-- archive `preferDeclaredSize`, or a width in `tilesWideFor`, or a cell bank.
ok(contradicted == 0,
   "%d sheet(s) outside the Underground are drawn at a width their header "
   .. "contradicts; this is a wrong picture each: %s",
   contradicted, table.concat(examples, "; "))
-- The bank-assembled ones are pinned as a count, not as faults. If this fell to
-- zero the split above would be untested and the 0 could be hiding behind an
-- empty set.
ok(byBank >= 25,
   "only %d declaring sheet(s) outside the Underground are placed by a cell "
   .. "bank (was 25); the cell/width split may no longer be exercised", byBank)

-- ---------------------------------------------------------------------------
section("5. tilesWideStated marks exactly the written-down widths")
-- ---------------------------------------------------------------------------
-- The whole precedence rests on telling a measured 8 from the archive default 8.
for _, a in ipairs(Screens.ARCHIVES) do
  for _, job in ipairs(Screens.plan(a.path, a) or {}) do
    local named = (a.tilesWideFor and a.tilesWideFor[job.name]) ~= nil
    ok((job.tilesWideStated == true) == named,
       "%s/%s: tilesWideStated=%s but tilesWideFor %s it",
       a.path, tostring(job.name), tostring(job.tilesWideStated),
       named and "names" or "does not name")
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)