-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A TM THAT CANNOT BE TAUGHT, AND A LINE WITH A HOLE IN IT.
--
-- Reported from play, with a screenshot of HM01 selected in the bag's TM/HM
-- pocket: *"This isn't the time to use that!"*.
--
-- TWO FAULTS, ONE AFTER THE OTHER.
--
-- The first was an absent field.  `BagMenu.useItem` gates the entire machine
-- flow -- the boot-up lines, the party picker's TM/HM mode, the ABLE!/UNABLE!
-- word -- on `def.machine`, and `ItemEffects.needsTarget` will not answer true
-- without one.  Of the 446 items in a Platinum cache, ZERO carried it: Gen 1,
-- 2 and 3 extractors write `machine = { move, kind }` and the Gen 4 one never
-- did, because the cartridge does not store it that way.  Every piece of work
-- the earlier TM passes did was correct and unreachable.
--
-- The second was underneath it.  With the record stamped, the bag reached its
-- own wording and printed *"It contained ."* -- `{STRVAR_1 6 0 0}` is string
-- buffer slot 0 and nothing had filled it, which `gen4Markup` said out loud
-- (*"string slot 0 was never buffered"*) to a log nobody was reading.
--
-- WHAT THIS PINS
--   1. the cartridge's two sources, as pret states them;
--   2. the derivation, against the cache;
--   3. that every refusal lands -- the derivation declining is the whole
--      reason to trust the one case where it does not;
--   4. the wording, end to end, including how the box pages it;
--   5. that a Gen 4 bank line is read ONE way in this tree.
--
-- Run:  texlua tools/gen4_machine_check.lua <data/generated> [pokeplatinum]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg[1]
local PRET  = arg[2]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function listDir(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
  if not p then return out end
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end
-- Comments do not grade the code they describe.  A prose paragraph naming
-- every word a source assertion looks for will satisfy it; that happened once
-- in this tree already and the fault it was meant to catch walked past.
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end

love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
}

local ItemEffects = require("src.inventory.ItemEffects")
local Gen4Text    = require("src.import.Gen4Text")
local Logger      = require("src.core.Logger")

-- Every warn the derivation emits, so a refusal can be asserted to SAY so.
local said
do
  local realWarn = Logger.warn
  Logger.warn = function(fmt, ...)
    if said then
      local okF, line = pcall(string.format, tostring(fmt), ...)
      said[#said + 1] = okF and line or tostring(fmt)
    end
    return realWarn(fmt, ...)
  end
end
local function capture(fn)
  said = {}
  local value = fn()
  local lines = said
  said = nil
  return value, table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
section("1. the cartridge's two sources, as pret states them")
-- ---------------------------------------------------------------------------
if not PRET then
  skip("no pokeplatinum checkout, so the use-function number and "
       .. "Item_MoveForTMHM's shape are unverified against pret")
else
  local itemsH = slurp(PRET .. "/include/constants/items.h")
  ok(itemsH ~= nil, "include/constants/items.h is not readable")
  if itemsH then
    local n = itemsH:match("#define%s+ITEM_USE_FUNC_TM_HM%s+(%d+)")
    ok(tonumber(n) == ItemEffects.ITEM_USE_FUNC_TM_HM,
       "pret says ITEM_USE_FUNC_TM_HM is %s; ItemEffects says %s -- the whole "
       .. "derivation keys off this number",
       tostring(n), tostring(ItemEffects.ITEM_USE_FUNC_TM_HM))
  end

  local itemC = code(slurp(PRET .. "/src/item.c"))
  ok(itemC ~= "", "src/item.c is not readable")
  if itemC ~= "" then
    -- THE ID IS THE INDEX.  Three lines, and they are why this check can
    -- derive a machine record from an id at all.
    local body = itemC:match("u16%s+Item_MoveForTMHM%s*%b()%s*{(.-)\n}")
    ok(body ~= nil, "Item_MoveForTMHM is not defined in src/item.c")
    if body then
      ok(body:find("item%s*%-=%s*ITEM_TM01") ~= nil,
         "Item_MoveForTMHM no longer subtracts ITEM_TM01, so an item id is no "
         .. "longer an index into sTMHMMoves: %s", (body:gsub("%s+", " ")))
      ok(body:find("sTMHMMoves%s*%[%s*item%s*%]") ~= nil,
         "Item_MoveForTMHM no longer indexes sTMHMMoves by the offset item")
    end
    -- ...and the TM/HM half is a scan of the array's tail, which is the
    -- question `kind` answers.
    local hm = itemC:match("Item_IsHMMove%s*%b()%s*{(.-)\n}")
    ok(hm ~= nil, "Item_IsHMMove is not defined in src/item.c")
    if hm then
      ok(hm:find("NUM_TMS") ~= nil,
         "Item_IsHMMove no longer scans from NUM_TMS, so the TM/HM split is "
         .. "not where this check believes it is")
    end
    report("pret: ITEM_USE_FUNC_TM_HM = %s, Item_MoveForTMHM indexes "
           .. "sTMHMMoves by (item - ITEM_TM01)",
           tostring(ItemEffects.ITEM_USE_FUNC_TM_HM))
  end
end

-- ---------------------------------------------------------------------------
section("2. the derivation, against the cache")
-- ---------------------------------------------------------------------------
local items  = CACHE and loadTable(CACHE, "items")
local moves  = CACHE and loadTable(CACHE, "moves")
local consts = CACHE and loadTable(CACHE, "constants")
local texts  = CACHE and loadTable(CACHE, "text")
local tmhm   = consts and consts.tmhmMoves

if not (items and moves and tmhm) then
  skip("no Platinum cache with items/moves/constants.tmhmMoves, so the "
       .. "derivation is unverified")
else
  -- `Data` publishes every Gen 4 item under BOTH its numeric id and
  -- `ITEM_nnn`, pointing at one table.  The fixture is built that way on
  -- purpose: the dedup is part of what is under test.
  local function fixture()
    local t = {}
    for k, v in pairs(items) do
      if type(v) == "table" then
        local copy = {}
        for ck, cv in pairs(v) do copy[ck] = cv end
        local id = tonumber(k)
        if id then
          t[id] = copy
          t[("ITEM_%03d"):format(id)] = copy
        else
          t[k] = t[k] or copy
        end
      end
    end
    -- A COPY OF THE ARRAY, because section 3 plants faults in it.  The first
    -- draft shared it, `table.remove` took an entry off the real one, and
    -- every later fixture in the run was built on 99 entries -- which the
    -- floor caught as five refusals that refused for the wrong reason.
    local list = {}
    for i = 1, #tmhm do list[i] = tmhm[i] end
    return { items = t, constants = { tmhmMoves = list }, moves = moves,
             text = texts }
  end
  local function byName(data, name)
    for k, def in pairs(data.items) do
      if tonumber(k) and type(def) == "table" and def.name == name then
        return def, tonumber(k)
      end
    end
  end

  local data = fixture()
  local stamped = ItemEffects.markGen4Machines(data)
  ok(stamped == #tmhm,
     "markGen4Machines stamped %d record(s) against %d entries in tmhmMoves "
     .. "-- a Platinum cache has one machine per entry", stamped, #tmhm)
  report("tmhmMoves has %d entries; %d machine record(s) stamped",
         #tmhm, stamped)

  -- EVERY ONE OF THEM, not four spot checks: the move each item teaches is
  -- `tmhmMoves[id - firstId + 1]`, and the half it falls in is what the
  -- cartridge's Item_IsHMMove answers for its move.
  local lo
  for k, def in pairs(data.items) do
    local id = tonumber(k)
    if id and type(def) == "table" and def.machine
       and (not lo or id < lo) then lo = id end
  end
  ok(lo ~= nil, "no stamped item has a numeric id")
  if lo then
    local tmCount = 0
    for k, def in pairs(data.items) do
      if tonumber(k) and type(def) == "table" and def.machine
         and tostring(def.name or ""):match("^TM%d+$") then
        tmCount = tmCount + 1
      end
    end
    -- the cartridge's own question, asked the cartridge's own way
    local isHMMove = {}
    for i = tmCount + 1, #tmhm do isHMMove[tmhm[i]] = true end

    local wrongMove, wrongKind, disagree = 0, 0, 0
    for k, def in pairs(data.items) do
      local id = tonumber(k)
      if id and type(def) == "table" and def.machine then
        local want = tmhm[id - lo + 1]
        if def.machine.move ~= want then wrongMove = wrongMove + 1 end
        local wantKind = (id - lo + 1) > tmCount and "HM" or "TM"
        if def.machine.kind ~= wantKind then wrongKind = wrongKind + 1 end
        if (def.machine.kind == "HM") ~= (isHMMove[def.machine.move] or false)
          then disagree = disagree + 1 end
      end
    end
    ok(wrongMove == 0,
       "%d stamped item(s) teach a move that is not tmhmMoves[id - %d + 1] -- "
       .. "a wrong index does not fail, it teaches Rock Climb where it should "
       .. "teach Focus Punch", wrongMove, lo)
    ok(wrongKind == 0,
       "%d stamped item(s) carry a kind that disagrees with the half of the "
       .. "machine run their id falls in", wrongKind)
    ok(disagree == 0,
       "%d stamped item(s) have a kind that disagrees with the cartridge's "
       .. "Item_IsHMMove(move) -- the two answers are only the same while no "
       .. "move sits in both halves of the array, and one now does",
       disagree)
    report("the machine run is ids %d..%d, %d TM then %d HM",
           lo, lo + #tmhm - 1, tmCount, #tmhm - tmCount)
  end

  -- the four the play report and the array's ends name
  for _, want in ipairs({ { "TM01", 1 }, { "TM92", 92 },
                          { "HM01", 93 }, { "HM08", 100 } }) do
    local def = byName(data, want[1])
    if def and tmhm[want[2]] then
      ok(def.machine and def.machine.move == tmhm[want[2]],
         "%s teaches %s; tmhmMoves[%d] is %s", want[1],
         tostring(def.machine and def.machine.move), want[2],
         tostring(tmhm[want[2]]))
      ok(def.machine and def.machine.kind
           == (want[1]:sub(1, 2) == "HM" and "HM" or "TM"),
         "%s is stamped as a %s", want[1],
         tostring(def.machine and def.machine.kind))
    else
      skip("%s is not in this cache", want[1])
    end
  end

  -- THE STAMP IS ONLY WORTH THE DOOR IT OPENS.
  do
    local before = fixture()
    local hm01b = byName(before, "HM01")
    ok(hm01b ~= nil, "HM01 is not in this cache")
    if hm01b then
      ok(not ItemEffects.needsTarget("HM01", hm01b),
         "HM01 asks for a target BEFORE the record is stamped, so this check "
         .. "cannot tell whether the record is what opens the party picker")
      ItemEffects.markGen4Machines(before)
      ok(ItemEffects.needsTarget("HM01", hm01b) and true or false,
         "HM01 still answers no target needed after the record is stamped -- "
         .. "which is the bag saying \"This isn't the time to use that!\"")
    end
  end

  -- ...AND ONLY nil IS FILLED, so a mod keeps its own record.
  do
    local mine = fixture()
    local tm01 = byName(mine, "TM01")
    local own = { move = 1, kind = "TM" }
    tm01.machine = own
    ItemEffects.markGen4Machines(mine)
    ok(tm01.machine == own,
       "markGen4Machines overwrote a machine record it did not place, so a "
       .. "mod that supplies its own loses it")
  end

  -- ---------------------------------------------------------------------
  section("3. every refusal lands")
  -- ---------------------------------------------------------------------
  -- A derivation that cannot refuse is a derivation that cannot be trusted
  -- when it does not.  Each of these is a fault planted in the data; each
  -- must stamp nothing AND say why.
  local function plant(name, mutate, expect)
    local data2 = fixture()
    mutate(data2)
    local n, log = capture(function()
      return ItemEffects.markGen4Machines(data2)
    end)
    ok(n == 0, "the planted fault %q stamped %d record(s) instead of refusing",
       name, n)
    ok(log:find(expect, 1, true) ~= nil,
       "the planted fault %q refused without saying %q; it said %q",
       name, expect, log)
  end

  plant("tmhmMoves one entry short",
        function(d) table.remove(d.constants.tmhmMoves) end,
        "cannot be placed")
  -- THE COUNT STAYS AT 100 AND THE RUN BREAKS.  The first version of this
  -- plant simply ADDED an item, so there were 101 against 100 entries and the
  -- count test refused first -- the fault landed, but not on the assertion it
  -- was aimed at, which is the same thing as not landing.
  plant("a machine item moved out of the run, which is no longer unbroken",
        function(d)
          local def, id = byName(d, "TM50")
          d.items[id] = nil
          d.items[("ITEM_%03d"):format(id)] = nil
          d.items[9000] = def
          d.items.ITEM_9000 = def
        end,
        "unbroken run")
  -- ...AND THE SAME TRAP THE OTHER WAY ROUND.  Renaming a TM takes one off
  -- the TM run's length, which moves the split, which trips the half test
  -- before the name test ever runs.  An HM's name is the one that can be
  -- spoiled without moving anything.
  plant("a machine item with a name that is not TMnn/HMnn",
        function(d)
          local def = byName(d, "HM04")
          def.name = "BICYCLE"
        end,
        "is named")
  plant("TM40 renamed TM41, so a name disagrees with its id",
        function(d)
          local def = byName(d, "TM40")
          def.name = "TM41"
        end,
        "but its name puts it at")
  plant("HM03 renamed TM93, which moves the split",
        function(d)
          local def = byName(d, "HM03")
          def.name = "TM93"
        end,
        "but its name puts it at")
  plant("no item carries the use function at all",
        function(d)
          for _, def in pairs(d.items) do
            if type(def) == "table"
               and def.fieldUseFunc == ItemEffects.ITEM_USE_FUNC_TM_HM then
              def.fieldUseFunc = nil
            end
          end
        end,
        "has nothing to trigger it")

  -- THE DEDUP, asserted as a number rather than assumed.  Walking the values
  -- of that table sees each machine twice; walking the ids cannot.
  do
    local d = fixture()
    local values, ids = 0, {}
    for k, def in pairs(d.items) do
      if type(def) == "table"
         and def.fieldUseFunc == ItemEffects.ITEM_USE_FUNC_TM_HM then
        values = values + 1
        local id = tonumber(k) or tonumber(tostring(k):match("^ITEM_(%d+)$"))
        if id then ids[id] = true end
      end
    end
    local n = 0
    for _ in pairs(ids) do n = n + 1 end
    ok(values > n,
       "the fixture does not publish items twice, so it is not the table "
       .. "`Data` builds and the dedup is not under test (%d values, %d ids)",
       values, n)
    ok(n == #tmhm,
       "the id-keyed walk found %d machines against %d array entries",
       n, #tmhm)
  end

  -- ---------------------------------------------------------------------
  section("4. the wording, end to end")
  -- ---------------------------------------------------------------------
  local BANK, BOOTED_TM, BOOTED_HM, CONTAINED = 7, 58, 59, 60
  -- the bag's own three lines, read out of the file it reads them from
  do
    local src = code(slurp("src/ui/BagMenu.lua"))
    for name, want in pairs({ BAG_TEXT_BANK = BANK,
                              BAG_TEXT_BOOTED_TM = BOOTED_TM,
                              BAG_TEXT_BOOTED_HM = BOOTED_HM,
                              BAG_TEXT_CONTAINED = CONTAINED }) do
      local got = tonumber(src:match("local%s+" .. name .. "%s*=%s*(%d+)"))
      ok(got == want,
         "BagMenu's %s is %s; this check is pinning %d", name,
         tostring(got), want)
    end
  end

  -- AND THE BAG HAS TO BE THE ONE THAT BUFFERS IT.  This section fills slot 0
  -- itself a few lines down, which is how `resolve` gets exercised -- but that
  -- made BagMenu's own buffer call a cold arm: deleting it from BagMenu.lua
  -- left all 67 checks passing while the line on screen read "It contained .".
  do
    local src = code(slurp("src/ui/BagMenu.lua"))
    local arm = src:match("isGen4%(%)%s+then(.-)\n      end")
    ok(arm ~= nil,
       "BagMenu has no Gen 4 arm in useItem, so the bag reads Hoenn's wording")
    if arm then
      local at = arm:find("Gen4Text%.buffer%s*%(")
      local resolves = arm:find("Gen4Text%.resolve%s*%(")
      ok(at ~= nil,
         "BagMenu's Gen 4 arm never buffers the move name, so both halves of "
         .. "\"It contained {move}.\" print with a gap where it should be")
      ok(at and resolves and at < resolves,
         "BagMenu buffers the move name AFTER it resolves the line, which is "
         .. "too late: the token is already gone")
    end
  end

  if not texts then
    skip("no text.lua in this cache, so the machine wording is unverified")
  else
    local raw = texts[Gen4Text.label(BANK, CONTAINED)]
    ok(type(raw) == "string",
       "bank %d entry %d is absent, so the bag has no \"It contained\" line",
       BANK, CONTAINED)
    if type(raw) == "string" then
      -- BOTH HALVES READ ONE SLOT.  That is why one buffer fills both.
      local slots = {}
      for low, slot in raw:gmatch("{STRVAR_1%s+(%d+)%s+(%d+)%s*%d*}") do
        slots[#slots + 1] = slot
      end
      ok(#slots == 2,
         "bank %d entry %d carries %d string-variable token(s); the "
         .. "cartridge's line has two, one per half", BANK, CONTAINED, #slots)
      ok(slots[1] == "0" and slots[2] == slots[1],
         "entry %d reads slots %s and %s; TMHMUseTask fills slot 0 only "
         .. "(StringTemplate_SetMoveName(template, 0, move))", CONTAINED,
         tostring(slots[1]), tostring(slots[2]))
      ok(raw:find("\v", 1, true) ~= nil,
         "entry %d has no wait between its halves, so \"It contained CUT.\" "
         .. "and the question would type into one box with no button press",
         CONTAINED)
    end

    -- and now exactly what the bag does, with the move the play report named
    local hm01 = byName(data, "HM01")
    local moveName = hm01 and hm01.machine
                     and moves[hm01.machine.move]
                     and moves[hm01.machine.move].name
    ok(moveName ~= nil, "HM01's move has no name in this cache")
    if moveName then
      local game = { data = data }
      Gen4Text.buffer(game, moveName)
      local line, log = capture(function()
        return Gen4Text.resolve(data, BANK, CONTAINED, game)
      end)
      ok(type(line) == "string", "the bag's \"It contained\" line resolved to "
         .. "%s", tostring(line))
      if type(line) == "string" then
        local n = select(2, line:gsub(moveName, ""))
        ok(n == 2,
           "the resolved line names %s %d time(s); the cartridge's line names "
           .. "it twice -- %q", moveName, n, line)
        ok(not line:find("{", 1, true),
           "the resolved line still carries markup: %q", line)
        ok(log:find("never buffered", 1, true) == nil,
           "resolving the line still logged an unbuffered slot: %s", log)
        -- THE SHAPE ON SCREEN.  One box: two lines, the button, then the
        -- question scrolled up into it.
        local TextBox = require("src.render.TextBox")
        local pages = TextBox.paginate(line, 18)
        ok(#pages == 1,
           "the line paged into %d boxes; the cartridge's wait is a scroll, "
           .. "not a clear", #pages)
        local conts = 0
        for p = 1, #pages do
          for i = 1, #pages[p] do
            if pages.contBefore[p] and pages.contBefore[p][i] then
              conts = conts + 1
            end
          end
        end
        ok(conts == 1,
           "%d line(s) of the resolved line wait-and-scroll; the cartridge's "
           .. "entry has exactly one", conts)
        local blank = 0
        for p = 1, #pages do
          for i = 1, #pages[p] do
            if pages[p][i] == "" then blank = blank + 1 end
          end
        end
        ok(blank == 0,
           "the line pages with %d blank line(s), each of which still wants "
           .. "its button press", blank)
      end

      -- the TM and HM halves say different words
      local tmLine = Gen4Text.resolve(data, BANK, BOOTED_TM, game)
      local hmLine = Gen4Text.resolve(data, BANK, BOOTED_HM, game)
      ok(type(tmLine) == "string" and type(hmLine) == "string"
           and tmLine ~= hmLine,
         "the TM and HM boot-up lines are %q and %q", tostring(tmLine),
         tostring(hmLine))
    end

    -- THE TRAILING WAIT COMES OFF, and the field-poison line is the one that
    -- taught this: it had stripped the marker under the decoder's OLD name
    -- for years, which is to say it had stripped nothing.
    do
      local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
      local bank = okB and Bands and Bands.TEXT_BANK
                    and Bands.TEXT_BANK.common_scripts
      if not bank then
        skip("Gen4ScriptBands names no common_scripts text bank")
      else
        local rawP = texts[Gen4Text.label(bank, 66)]
        if type(rawP) ~= "string" then
          skip("bank %d entry 66 is absent, so the poison line is unverified",
               bank)
        else
          ok(rawP:find("[\v\f]$") ~= nil,
             "bank %d entry 66 does not end in a wait, so this check cannot "
             .. "tell whether the trailing wait is stripped", bank)
          local game2 = { data = data }
          Gen4Text.buffer(game2, "CHIMCHAR")
          local line = Gen4Text.resolve(data, bank, 66, game2)
          ok(type(line) == "string" and line:find("[\v\f]$") == nil,
             "the resolved poison line still ends in a wait: %q",
             tostring(line))
          ok(type(line) == "string" and line:find("CHIMCHAR", 1, true) ~= nil,
             "the resolved poison line does not name the Pokemon: %q",
             tostring(line))
          ok(select(2, tostring(texts[Gen4Text.label(bank, 66)])
                        :gsub("\r", "")) == 0,
             "entry 66 contains a carriage return after all; the strip this "
             .. "replaced was spelled \\r and the decoder spells it \\v")
        end
      end
    end

    -- A CARRIAGE RETURN IS NOT A MARKER IN THIS TREE AT ALL, measured over
    -- the whole bank rather than argued from one entry.
    do
      local n, with = 0, 0
      for _, v in pairs(texts) do
        if type(v) == "string" then
          n = n + 1
          if v:find("\r", 1, true) then with = with + 1 end
        end
      end
      ok(with == 0,
         "%d of %d cartridge strings contain a carriage return; a `\\r` strip "
         .. "would not have been dead code after all", with, n)
      report("%d cartridge strings, %d with a carriage return", n, with)
    end
  end
end

-- ---------------------------------------------------------------------------
section("5. a Gen 4 bank line is read ONE way in this tree")
-- ---------------------------------------------------------------------------
-- THE INVARIANT, NOT A LIST.  `resolve` does three things a raw `data.text`
-- subscript does not: it checks the value is a string, it runs `gen4Markup`
-- so `{WAIT 3}` is not printed literally, and it takes the trailing wait off.
-- A screen that reads the table directly gets none of them, and the symptom
-- is a stray token on screen rather than an error -- which is how the bag's
-- "It contained ." and the Underground's row labels both got there.
--
-- The subject derives itself: a key built by `Gen4Text.label` is by
-- construction a Gen 4 bank key, so any site that builds one and then
-- subscripts the text table is an offender the day it is written.
--
-- TWO LAYERS, TWO RULES, because the first draft had one and found seven sites
-- in `Gen4Commands.lua` that were not faults.  A SCREEN has no markup step of
-- its own and must go through `resolve`.  The SCRIPT layer does -- it holds
-- `gen4Markup` and `show_text` -- so what it owes is that the function doing
-- the read also does the markup, which is the part that was actually missing:
-- three of those seven read a message bank straight into a string buffer with
-- the tokens still on it.
local function bankReadSites(src)
  local out = {}
  for stmt in src:gmatch("[^\r\n]+") do
    if stmt:find("text%s*%[") and (stmt:find("Gen4Text%.label")
        or stmt:find("%[label%]") or stmt:find("%[key%]")
        or stmt:find("%[textLabel%]")) then
      out[#out + 1] = (stmt:gsub("^%s+", ""))
    end
  end
  return out
end
-- Split on the function boundaries, so "does this function mark up" is asked
-- of the function the read is IN rather than of the file.
local function bodies(src)
  local out, at = {}, 1
  while true do
    local s2 = src:find("\n%s*%-?%-?%s*function ", at)
      or src:find("\nlocal function ", at)
    if not s2 then out[#out + 1] = src:sub(at) break end
    out[#out + 1] = src:sub(at, s2)
    at = s2 + 1
  end
  return out
end
do
  local OWNS = {           -- the two files the mechanism itself lives in
    ["src/import/Gen4Text.lua"] = true,
    ["src/import/RomExtractorGen4.lua"] = true,   -- WRITES the table
  }
  local screens, unmarked, scanned = {}, {}, 0
  local function sweep(dir)
    for _, name in ipairs(listDir(dir)) do
      local path = dir .. "/" .. name
      if name:match("%.lua$") then
        local rel = path:gsub("^%./", "")
        if not OWNS[rel] and not rel:find("Gen4Commands%-1") then
          local src = code(slurp(path))
          scanned = scanned + 1
          if src:find("Gen4Text%.label%s*%(") then
            if rel:find("^src/script/") then
              for _, body in ipairs(bodies(src)) do
                local sites = bankReadSites(body)
                if #sites > 0 and not body:find("gen4Markup")
                   and not body:find("%.resolve%s*%(") then
                  for _, site in ipairs(sites) do
                    unmarked[#unmarked + 1] = rel .. ": " .. site
                  end
                end
              end
            else
              for _, site in ipairs(bankReadSites(src)) do
                screens[#screens + 1] = rel .. ": " .. site
              end
            end
          end
        end
      elseif not name:find("%.") then
        sweep(path)
      end
    end
  end
  sweep("src")
  ok(scanned > 100, "the sweep read %d Lua file(s) under src/, which is too "
     .. "few to have run", scanned)
  ok(#screens == 0,
     "%d site(s) outside the script layer read a Gen 4 bank line straight out "
     .. "of data.text instead of through Gen4Text.resolve, so the line keeps "
     .. "its markup and its trailing wait:\n    %s", #screens,
     table.concat(screens, "\n    "))
  ok(#unmarked == 0,
     "%d bank read(s) in the script layer sit in a function that never runs "
     .. "gen4Markup, so the line reaches the player with its control tokens "
     .. "on it:\n    %s", #unmarked, table.concat(unmarked, "\n    "))
  report("%d Lua file(s) swept for raw Gen 4 bank reads", scanned)
end

-- AND NOBODY EXPANDS A STRING BUFFER BY HAND.  A gsub whose SLOT number is a
-- wildcard is someone re-implementing `gen4Markup`; a fully literal token
-- (`{STRVAR_1 51 2 0}`) is a NUMBER variable, which is a different mechanism
-- and not this one.
do
  local ARGUED = {
    -- Rowan's intro fills the player's and the rival's names from answers the
    -- player is typing INSIDE the screen, before there is a game to buffer
    -- them on, and it draws its own pages rather than handing text to a box.
    ["src/ui/Gen4RowanIntro.lua"] = 1,
  }
  local found, scanned = {}, 0
  local function sweep(dir)
    for _, name in ipairs(listDir(dir)) do
      local path = dir .. "/" .. name
      if name:match("%.lua$") then
        local rel = path:gsub("^%./", "")
        if rel ~= "src/script/Commands.lua"
           and rel ~= "src/import/Gen4Text.lua"
           and not rel:find("Gen4Commands%-1") then
          scanned = scanned + 1
          local src = code(slurp(path))
          local n = 0
          for pat in src:gmatch('gsub%s*%(%s*[\'"]({STRVAR_1[^\'"]*)') do
            if pat:find("%%") then n = n + 1 end
          end
          if n > 0 then found[rel] = n end
        end
      elseif not name:find("%.") then
        sweep(path)
      end
    end
  end
  sweep("src")
  local extra = {}
  for rel, n in pairs(found) do
    if ARGUED[rel] ~= n then
      extra[#extra + 1] = ("%s (%d, argued %s)")
        :format(rel, n, tostring(ARGUED[rel]))
    end
  end
  for rel, n in pairs(ARGUED) do
    if found[rel] == nil then
      extra[#extra + 1] = ("%s (argued %d, now none -- retire the exception)")
        :format(rel, n)
    end
  end
  ok(#extra == 0,
     "%d file(s) expand a Gen 4 string buffer by hand rather than buffering "
     .. "the value and letting gen4Markup do it:\n    %s", #extra,
     table.concat(extra, "\n    "))
end

-- AND THE DERIVATION RUNS AT LOAD.  A function nothing calls stamps nothing.
do
  local src = code(slurp("src/core/Data.lua"))
  -- A CALL, not a substring.  The first spelling of this was
  -- `src:find("markGen4Machines")`, and renaming the function to
  -- `markGen4MachinesXX` to prove the assertion bites left it passing --
  -- because the old name is a prefix of the new one.
  ok(src:find("markGen4Machines%s*%(") ~= nil,
     "src/core/Data.lua never CALLS markGen4Machines, so no cache is ever "
     .. "stamped and every TM is back to \"This isn't the time to use that!\"")
  ok(ItemEffects.markGen4Machines ~= nil,
     "ItemEffects.markGen4Machines is gone, so the name Data calls resolves "
     .. "to nil and the pcall around it swallows the failure")
  -- ...on the Gen 4 branch, beside the other load-time stamp
  local branch = src:match("markFormsTrueColor.-\n  end\n")
  ok(src:find("markFormsTrueColor") ~= nil,
     "src/core/Data.lua no longer marks the Gen 4 forms, so the call this "
     .. "one sits beside has moved and its placement is unverified")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
