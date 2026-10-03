-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE UNDERGROUND'S ART, AND WHETHER ANY OF IT IS DRAWN AT A GUESSED WIDTH.
--
-- Five NARCs hold the Underground's graphics. Two were extracted in pass 132
-- and three were not, and the three are a DIFFERENT SHAPE from the two:
--
--   ug_parts    71 plain sheets, every one DECLARING its own tilesX/tilesY
--   ug_fossil   the mining interface, a composed screen
--   ug_anim     2 sheets, both CELL ACTORS, neither declaring a size
--   ug_trap     14 sheets, 13 cell actors, 1 declaring 32x32
--   underg_radar 1 sheet, a cell actor, plus a screen
--
-- WHY THAT MATTERS. `Gen4Screens` exists largely to write down sheet widths,
-- and its own comment is blunt about why: a wrong width is not a wrong size,
-- it is a DIFFERENT PICTURE. A plain sheet needs a width from somewhere. A
-- cell actor does not -- its bank says how many pieces there are, how big each
-- is and where it sits -- and a cell actor's NCGR usually declares nothing at
-- all, so a chosen width would be pure guess.
--
-- So the question this check asks is not "did the archives extract". It is:
-- IS EVERY SHEET'S LAYOUT SOMETHING THE CARTRIDGE STATED? Each one has to be
-- covered by a cell bank or by its own declared size. Zero may be left to a
-- default width.
--
-- It needs the ROM because a NARC's member count cannot be read from anywhere
-- else, and the member count against the name count is the only test there is
-- that the name tables line up: a NARC HAS NO DIRECTORY, so a name list that
-- is off by one is off for every member after it and nothing else would say so.
--
-- Usage: texlua tools/gen4_underground_art_check.lua <platinum .nds>
--    or: python tools/run_lua_check.py tools/gen4_underground_art_check.lua <rom>

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
local okR, Arch = pcall(require, "src.import.Gen4Archives")
local okG, Graphics = pcall(require, "src.import.Gen4Graphics")
local okS, Screens = pcall(require, "src.import.Gen4Screens")
ok(okN and okA and okR and okG and okS,
   "a loader did not load: %s %s %s %s %s", tostring(Nds), tostring(Narc),
   tostring(Arch), tostring(Graphics), tostring(Screens))
if not (okN and okA and okR and okG and okS) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local rom, why = Nds.open(ROM)
ok(rom ~= nil, "%s did not open as an NDS ROM: %s", ROM, tostring(why))
if not rom then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

-- THE FIVE ARCHIVES AND WHAT EACH ONE SHOULD COME TO.
--
-- `members` is the cartridge's own count, which is also the name count -- the
-- two being equal is the test, so writing one number and comparing both to it
-- is the point rather than a shortcut.
--
-- `byCell` and `bySize` are how many of that archive's SHEETS get their layout
-- from a cell bank and from their own NCGR header. They must add to the sheet
-- count: any remainder is a sheet being drawn at a default width.
local ARCHIVES = {
  { path = "/data/ug_parts.narc",    members = 116, jobs = 71, sheets = 71,
    byCell = 0,  bySize = 71 },
  { path = "/data/ug_fossil.narc",   members = 3,   jobs = 1,  sheets = 0,
    byCell = 0,  bySize = 0 },
  { path = "/data/ug_anim.narc",     members = 8,   jobs = 2,  sheets = 2,
    byCell = 2,  bySize = 0 },
  -- the six damaged boulders match by prefix onto `boulder_cell`; see the
  -- note in section 3
  { path = "/data/ug_trap.narc",     members = 53,  jobs = 19, sheets = 14,
    byCell = 13, bySize = 1, excusedPrefix = 6 },
  { path = "/data/underg_radar.narc", members = 7,  jobs = 2,  sheets = 1,
    byCell = 1,  bySize = 0 },
}

-- ---------------------------------------------------------------------------
section("1. all five are declared, and declared for the Underground")
-- ---------------------------------------------------------------------------
local declared = {}
for _, entry in ipairs(Screens.ARCHIVES or {}) do
  declared[entry.path] = entry
end
for _, want in ipairs(ARCHIVES) do
  local entry = declared[want.path]
  ok(entry ~= nil,
     "%s is not in Gen4Screens.ARCHIVES, so the graphics stage never opens it",
     want.path)
  if entry then
    ok(entry.out == "underground",
       "%s is extracted to %q rather than `underground`", want.path,
       tostring(entry.out))
    ok(entry.preferDeclaredSize == true,
       "%s does not prefer the sheet's declared size", want.path)
  end
end
io.write(("  %d of 5 declared\n")
         :format((function()
           local n = 0
           for _, w in ipairs(ARCHIVES) do if declared[w.path] then n = n + 1 end end
           return n
         end)()))

-- ---------------------------------------------------------------------------
section("2. the name tables line up with the cartridge")
-- ---------------------------------------------------------------------------
-- A NARC has no directory. If a name list is off by one it is off for every
-- member after it, the extractor writes the right pixels under the wrong
-- names, and nothing else in the port would ever say so.
local archives = {}
for _, want in ipairs(ARCHIVES) do
  local bytes = rom:read(want.path)
  ok(bytes ~= nil, "%s is not in this ROM", want.path)
  if bytes then
    local a, aerr = Narc.parse(bytes)
    ok(a ~= nil, "%s did not parse as a NARC: %s", want.path, tostring(aerr))
    archives[want.path] = a
    local names = Arch.names(want.path) or {}
    if a then
      ok(a.count == want.members,
         "%s holds %d members and %d were recorded", want.path, a.count,
         want.members)
      ok(#names == want.members,
         "%s has %d names and %d members were recorded", want.path, #names,
         want.members)
      ok(#names == a.count,
         "%s: %d names against %d members -- the name table does not fit",
         want.path, #names, a.count)
    end
  end
end

-- ---------------------------------------------------------------------------
section("3. every sheet's layout is something the cartridge stated")
-- ---------------------------------------------------------------------------
-- The job names its NCGR by MEMBER INDEX (`tiles`), not by name: the group
-- base strips `_tiles`, so job `dirt` is member `dirt_tiles.NCGR` and a lookup
-- by name finds nothing at all.
local function declaredSize(a, job)
  if not (a and job.tiles) then return nil end
  local bytes = a:get(job.tiles)
  if not bytes then return nil end
  local t = Graphics.tiles(bytes)
  if t and t.tilesX and t.tilesY and t.tilesX ~= 0xFFFF and t.tilesY ~= 0xFFFF
     and t.tilesX > 0 and t.tilesY > 0 then
    return t.tilesX, t.tilesY
  end
  return nil
end

local totalSheets, totalCell, totalSize, totalGuessed = 0, 0, 0, 0
for _, want in ipairs(ARCHIVES) do
  local entry = declared[want.path]
  local a = archives[want.path]
  if entry and a then
    local jobs = Screens.plan(want.path, entry)
    ok(type(jobs) == "table", "%s produced no plan", want.path)
    if type(jobs) == "table" then
      ok(#jobs == want.jobs, "%s plans %d jobs and %d were recorded",
         want.path, #jobs, want.jobs)
      local sheets, byCell, bySize, guessed = 0, 0, 0, {}
      local notNamed, excusedPrefix = 0, 0
      for _, job in ipairs(jobs) do
        if job.kind == Screens.SHEET then
          sheets = sheets + 1
          if job.cell then
            byCell = byCell + 1
            -- `named` is the cartridge saying so; `prefix` and `sole` are the
            -- resolver's own judgement.
            --
            -- SIX SHEETS HERE MATCH BY PREFIX AND THAT IS CORRECT, for a
            -- reason the cartridge states in its own member names: the damaged
            -- boulders carry `boulder_damaged_N_cell_unused.NCER` -- UNUSED,
            -- in the name -- and the prefix rule lands all six on
            -- `boulder_cell`, the undamaged boulder's real bank, which is the
            -- layout the damage states share.
            --
            -- So a prefix match is accepted ONLY where the sheet's own bank is
            -- the one the cartridge marked unused. Accepting prefix matches
            -- generally would wave through a sheet that landed on an unrelated
            -- bank because their names happen to share a stem; requiring
            -- `named` everywhere would fail six sheets that are right.
            if job.cellMatch ~= "named" then
              local own = (job.sheetName or job.raw or job.name)
              local excused = job.cellMatch == "prefix"
                              and Arch.find(want.path, own .. "_cell_unused")
                                  ~= nil
              if excused then
                excusedPrefix = excusedPrefix + 1
              else
                notNamed = notNamed + 1
                io.write(("  %s/%s found its bank by %q and the cartridge does "
                            .. "not mark its own bank unused\n")
                         :format(want.path, tostring(job.name),
                                 tostring(job.cellMatch)))
              end
            end
          elseif declaredSize(a, job) then
            bySize = bySize + 1
          else
            guessed[#guessed + 1] = tostring(job.name)
          end
        end
      end
      ok(sheets == want.sheets, "%s has %d sheets and %d were recorded",
         want.path, sheets, want.sheets)
      ok(byCell == want.byCell,
         "%s: %d sheet(s) take their layout from a cell bank, %d recorded",
         want.path, byCell, want.byCell)
      ok(bySize == want.bySize,
         "%s: %d sheet(s) declare their own size, %d recorded",
         want.path, bySize, want.bySize)
      -- THE ONE THAT MATTERS: nothing left over.
      ok(#guessed == 0,
         "%s: %d sheet(s) would be drawn at a default width -- %s",
         want.path, #guessed, table.concat(guessed, ", "))
      ok(notNamed == 0,
         "%s: %d cell bank(s) were matched by guess with nothing to justify it",
         want.path, notNamed)
      -- ...AND THE EXEMPTION MUST STAY REAL. If the six stopped being prefix
      -- matches -- because the resolver changed, or the names did -- this
      -- fails rather than silently covering nothing, which is how an exemption
      -- goes dead and starts hiding a bug.
      ok(excusedPrefix == (want.excusedPrefix or 0),
         "%s: %d prefix match(es) excused by an `_unused` bank, %d recorded",
         want.path, excusedPrefix, want.excusedPrefix or 0)
      ok(byCell + bySize == sheets,
         "%s: %d by bank plus %d by header is not %d sheets",
         want.path, byCell, bySize, sheets)
      totalSheets = totalSheets + sheets
      totalCell = totalCell + byCell
      totalSize = totalSize + bySize
      totalGuessed = totalGuessed + #guessed
    end
  end
end
io.write(("  %d sheets across five archives: %d by a cell bank, %d by their own "
            .. "header, %d guessed\n")
         :format(totalSheets, totalCell, totalSize, totalGuessed))
ok(totalSheets == 88, "%d sheets in all, and 88 were recorded", totalSheets)
ok(totalGuessed == 0, "%d sheet(s) in the Underground are drawn at a guess",
   totalGuessed)

-- ---------------------------------------------------------------------------
section("4. the two mechanisms are both real")
-- ---------------------------------------------------------------------------
-- A measurement that cannot fail says nothing, and "0 guessed" would be
-- satisfied by an archive with no sheets at all. These two say the file is
-- actually exercising both paths, so section 3 is a result rather than an
-- absence.
ok(totalCell >= 16, "only %d sheet(s) resolve through a cell bank", totalCell)
ok(totalSize >= 70, "only %d sheet(s) resolve through their own header",
   totalSize)
-- Asserting the recorded figures here as well would be circular: section 3
-- already pins the MEASURED count of each against the recorded one, so a
-- second read of the same constants could not fail and would only look like
-- another check. The two totals above are measurements; this is the line that
-- would have been the third, and it is deliberately not here.

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
