-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- 133 MAPS IN SINNOH CARRIED A WEATHER THAT CHANGED NOTHING YOU COULD LOOK AT.
--
-- `OverworldState:applyMapWeather` opened `if not GameVersion.isGen3() then
-- return end`. The extractor had been writing `maps[].weather` since the map
-- headers went in, one script command read it, and the renderer never did.
--
-- This is the second region with that exact hole -- the comment above
-- `fieldWeather` records Hoenn's ninety maps in the same words -- which is why
-- the fix is a table of the cartridge's own names feeding the look library
-- that already exists, not a second weather system.
--
-- AND SINNOH DOES IT DIFFERENTLY ENOUGH TO BE WORTH THE CHECK:
--
--   * DARKNESS IS A WEATHER. `OVERWORLD_WEATHER_DARK_FLASH` is 16, and Flash
--     lights a cave by making the map's weather CLEAR (`field_map_change.c`),
--     not by selecting a palette row. That is why
--     `PaletteFX.daytimeFor(mapDef, hour, flashUsed)` -- written for Gen 2's
--     DARKNESS row -- had no callers and was never going to get one: it is the
--     right answer to a different generation's question.
--   * FIVE MAPS HAVE A CALENDAR. Weathers 32..36 are columns of
--     `sYearlyWeather[366][5]`, read at the current day of the year.
--   * FLASH AND DEFOG ARE OFFERED BY THE WEATHER and by nothing else, so they
--     belong on the party menu under one condition each rather than behind a
--     badge.
--   * SIX IDS ARE UNNAMED IN pokeplatinum TOO, and 32 Mt. Coronet maps carry
--     one of them. Section 5 asserts that those are reported rather than
--     quietly treated as clear, because that silence is how 133 maps went
--     unnoticed in the first place.
--
-- Run:  texlua tools/gen4_weather_check.lua <data/generated> [pokeplatinum]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg and arg[1]
local PRET  = arg and arg[2]

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
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
-- Comments do not grade the code they describe.
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
-- A C definition, not its forward declaration: `scrcmd.c` declares 840
-- handlers before defining one, and this port has been burned by the bare-name
-- match twice.
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
local W   = require("src.import.Gen4Weather")
local G3  = require("src.world.Gen3Weather")
local FM  = require("src.world.Gen4FieldMoves")

-- ---------------------------------------------------------------------------
section("1. the enum, against pokeplatinum's own header")
-- ---------------------------------------------------------------------------
-- NEEDS NO CACHE AND NO CARTRIDGE past this file, so this check has something
-- that can fail with nothing supplied.
ok(W.YEARLY_START == 32 and W.YEARLY_COUNT == 5,
   "the calendar block is %s..%s; pokeplatinum has five tables from 32",
   tostring(W.YEARLY_START),
   tostring(W.YEARLY_START and W.YEARLY_START + (W.YEARLY_COUNT or 0) - 1))
ok(W.RENDERABLE_MAX == 30,
   "RENDERABLE_MAX is %s; the weather manager asserts `param1 < 31`",
   tostring(W.RENDERABLE_MAX))
ok(W.YEARLY_DAYS == 366,
   "the calendar has %s rows, not 366 -- a truncated transcription answers "
   .. "the last row it has for every day after the cut, which looks exactly "
   .. "like a map with no weather", tostring(W.YEARLY_DAYS))
ok(#W.YEARLY == 366 * 5,
   "the calendar holds %d entries, not %d", #W.YEARLY, 366 * 5)

if not PRET then
  skip("no pokeplatinum checkout, so the enum, the calendar and the three "
       .. "rules below are unverified against pret")
else
  local hdr = slurp(PRET .. "/include/constants/overworld_weather.h")
  ok(hdr ~= nil, "include/constants/overworld_weather.h is not readable")
  if hdr then
    -- EVERY ID pret DEFINES, not a spot check. An id this port names
    -- differently prints another weather's picture, and an id it does not name
    -- at all draws nothing -- so both directions matter.
    -- TWO KINDS OF ROW THAT ARE NOT AN ID'S NAME, and the first draft of this
    -- check tripped on both -- reporting seven disagreements against a port
    -- that was right, which is the same direction as pass 176's bank-634
    -- mislabel and worth the same note.
    --
    --   * `#define OVERWORLD_WEATHER_26 26` names nothing. The text after the
    --     prefix IS the number, so a naive capture reads pret's name for id 26
    --     as "26" and then complains that this port calls it WEATHER_26.
    --     A name that is all digits means pret has not identified it.
    --   * `OVERWORLD_WEATHER_YEARLY_START` is 32 as well, but it is the name
    --     of the BLOCK rather than of the first table in it -- the five
    --     ROUTE_212_SOUTH..SNOWPOINT_CITY aliases are arithmetic on it. It is
    --     not a competing name for id 32.
    local pret, pretCount, pretBlank = {}, 0, {}
    for name, value in hdr:gmatch("#define%s+OVERWORLD_WEATHER_([A-Z0-9_]+)%s+(%d+)") do
      local n = tonumber(value)
      if n and n <= 36 and not name:match("^YEARLY_") then
        if name:match("^%d+$") then
          pretBlank[n] = true
        else
          pret[n] = name
          pretCount = pretCount + 1
        end
      end
    end
    ok(next(pretBlank) ~= nil,
       "pokeplatinum names every weather id now, so the six placeholders in "
       .. "this port should be replaced with its names")
    ok(pretCount >= 17,
       "only %d weather id(s) were read out of the header, which is too few "
       .. "for this comparison to mean anything", pretCount)
    local wrong, missing = {}, {}
    for value, name in pairs(pret) do
      local mine = W.NAMES[value]
      if mine == nil then missing[#missing + 1] = ("%d (%s)"):format(value, name)
      elseif mine ~= name then
        wrong[#wrong + 1] = ("%d: %s vs pret's %s"):format(value, mine, name)
      end
    end
    ok(#wrong == 0,
       "%d id(s) are named differently from pret: %s", #wrong,
       table.concat(wrong, ", "))
    ok(#missing == 0,
       "%d id(s) pret names are absent from Gen4Weather.NAMES: %s",
       #missing, table.concat(missing, ", "))
    report("%d named weather ids agree with pret", pretCount - #wrong - #missing)

    -- THE FIVE CALENDAR IDS, whose names ARE the YEARLY_* aliases -- read as
    -- `YEARLY_START + n` rather than as a literal, so they are resolved here
    -- the way the header writes them.
    do
      local aliases, n = {}, 0
      for name, offset in hdr:gmatch("#define%s+OVERWORLD_WEATHER_([A-Z0-9_]+)%s+%(OVERWORLD_WEATHER_YEARLY_START %+ (%d+)%)") do
        if name ~= "YEARLY_END" then
          aliases[W.YEARLY_START + tonumber(offset)] = "YEARLY_" .. name
          n = n + 1
        end
      end
      ok(n == W.YEARLY_COUNT,
         "%d calendar alias(es) in the header, expected %d", n, W.YEARLY_COUNT)
      local bad = {}
      for id, name in pairs(aliases) do
        if W.NAMES[id] ~= name then
          bad[#bad + 1] = ("%d: %s vs %s"):format(id, tostring(W.NAMES[id]), name)
        end
      end
      ok(#bad == 0,
         "%d calendar id(s) are named differently from the header's aliases: "
         .. "%s", #bad, table.concat(bad, ", "))
    end

    -- ...AND THE SIX pret LEAVES UNNAMED ARE NAMED AFTER THEMSELVES HERE,
    -- which is the honest answer and has to stay one: a name invented for
    -- WEATHER_29 would be a claim about Mt. Coronet nobody has evidence for.
    local placeholders = 0
    for value, mine in pairs(W.NAMES) do
      if mine:match("^WEATHER_%d+$") then
        placeholders = placeholders + 1
        ok(tonumber(mine:match("(%d+)")) == value,
           "the placeholder for id %d is %q, which names a different id",
           value, mine)
        ok(pretBlank[value] == true,
           "id %d is a placeholder here but pret names it %s -- if pret has "
           .. "identified it, this port should use its name", value,
           tostring(pret[value]))
      end
    end
    ok(placeholders == 6,
       "%d placeholder name(s), expected 6 (ids 23, 26, 27, 28, 29, 30)",
       placeholders)
  end

  -- THE CALENDAR, RE-DERIVED. 1,830 entries, compared one at a time, because
  -- a transcription is exactly the kind of thing that is 99% right.
  local wx = slurp(PRET .. "/src/field_overworld_weather.c")
  ok(wx ~= nil, "src/field_overworld_weather.c is not readable")
  if wx and hdr then
    local ID = {}
    for name, value in hdr:gmatch("#define%s+(OVERWORLD_WEATHER_[A-Z0-9_]+)%s+(%d+)") do
      ID[name] = tonumber(value)
    end
    local body = wx:match("sYearlyWeather(.-)// clang%-format on")
    ok(body ~= nil, "could not find sYearlyWeather's body")
    if body then
      local rows = {}
      for mon, day, vals in body:gmatch("%[DAY_OF_YEAR_([A-Z]+)_(%d+) %- 1%]%s*=%s*{([^}]*)}") do
        local cols = {}
        for v in vals:gmatch("[A-Z0-9_]+") do
          if ID[v] then cols[#cols + 1] = ID[v] end
        end
        rows[#rows + 1] = { mon = mon, day = day, cols = cols }
      end
      ok(#rows == 366, "pret's calendar has %d rows, not 366", #rows)
      local bad, widths = 0, 0
      for i, row in ipairs(rows) do
        if #row.cols ~= 5 then widths = widths + 1 end
        for c = 1, math.min(5, #row.cols) do
          local mine = W.YEARLY[5 * (i - 1) + c]
          if mine ~= row.cols[c] then
            bad = bad + 1
            if bad <= 4 then
              report("calendar mismatch at %s %s column %d: %s vs pret's %d",
                     row.mon, row.day, c, tostring(mine), row.cols[c])
            end
          end
        end
      end
      ok(widths == 0, "%d of pret's rows did not read as five columns", widths)
      ok(bad == 0,
         "%d of %d calendar entries disagree with pret", bad, 366 * 5)
      report("%d calendar entries re-derived from pret and agree", 366 * 5 - bad)
    end

    -- THE LEAP-YEAR CORRECTION IS TWO HALVES THAT CANCEL, and each half is in
    -- a different file, so each is graded separately. Getting this wrong
    -- shifts every date after February by a day -- a wrong answer that is
    -- never an obviously wrong one.
    local getw = cdefn(wx, "FieldSystem_GetWeather")
    ok(getw ~= nil, "FieldSystem_GetWeather is not defined in that file")
    if getw then
      ok(getw:find("DayNumberForDate") ~= nil,
         "FieldSystem_GetWeather no longer calls DayNumberForDate")
      ok(getw:find("IsLeapYear") ~= nil and getw:find("MONTH_FEB") ~= nil,
         "FieldSystem_GetWeather no longer corrects for a non-leap year after "
         .. "February, which is one of the two halves Gen4Weather.resolve ports")
      ok(getw:find("DAY_OF_YEAR_JAN_02") ~= nil,
         "FieldSystem_GetWeather no longer pins a penalised clock to 2 January")
    end
    local rtc = slurp(PRET .. "/src/rtc.c")
    local dayn = rtc and cdefn(rtc, "DayNumberForDate")
    if not dayn then
      skip("DayNumberForDate is not readable, so the other half of the "
           .. "leap-year rule is unverified")
    else
      ok(dayn:find("MONTH_MAR") ~= nil,
         "DayNumberForDate no longer treats March as the boundary")
      -- its monthStart row for March is `- 2` and January's is `- 1`, which is
      -- where the 365-day layout comes from
      ok(dayn:find("MONTH_MAR %- 1%] = DAY_OF_YEAR_MAR_01 %- 2") ~= nil
         or dayn:find("DAY_OF_YEAR_MAR_01 %- 2") ~= nil,
         "DayNumberForDate's March offset is no longer DAY_OF_YEAR_MAR_01 - 2, "
         .. "so the two halves of the correction may no longer cancel")
    end
  end

  -- THE SUBSTITUTION RULE, from the line that performs it.
  local fmc = slurp(PRET .. "/src/field_map_change.c")
  if not fmc then
    skip("src/field_map_change.c is not readable, so the Flash/Defog "
         .. "substitution is unverified")
  else
    local c = code(fmc)
    ok(c:find("OVERWORLD_WEATHER_FOG") ~= nil
       and c:find("SystemFlag_CheckDefogActive") ~= nil,
       "field_map_change.c no longer substitutes for FOG + Defog")
    ok(c:find("OVERWORLD_WEATHER_DARK_FLASH") ~= nil
       and c:find("SystemFlag_CheckFlashActive") ~= nil,
       "field_map_change.c no longer substitutes for DARK_FLASH + Flash")
    -- AND DEEP_FOG IS NOT IN IT. Defog clears FOG (14) and not DEEP_FOG (15);
    -- adding the obvious second row would be a guess that reads as a fix.
    local line = c:match("[^\n]*SystemFlag_CheckDefogActive[^\n]*")
    ok(line == nil or line:find("OVERWORLD_WEATHER_DEEP_FOG") == nil,
       "field_map_change.c now mentions DEEP_FOG on the Defog line, so "
       .. "Gen4Weather.CLEARED_BY is missing a row: %s", tostring(line))
  end

  -- THE OFFER RULE, from the switch that sets the usable bits.
  local fmt = slurp(PRET .. "/src/field_move_tasks.c")
  if not fmt then
    skip("src/field_move_tasks.c is not readable, so the offer rule is "
         .. "unverified")
  else
    local c = code(fmt)
    for _, pair in ipairs({ { "OVERWORLD_WEATHER_FOG", "FIELD_MOVE_DEFOG" },
                            { "OVERWORLD_WEATHER_DARK_FLASH", "FIELD_MOVE_FLASH" } }) do
      local arm = c:match("case " .. pair[1] .. ":(.-)break;")
      ok(arm ~= nil and arm:find(pair[2]) ~= nil,
         "FieldMoves_CanUseMoves no longer offers %s under %s", pair[2], pair[1])
    end
    -- the band entries, from the ScriptEntry table's own order
    local entries = slurp(PRET .. "/res/field/scripts/scripts_field_moves.s")
    if not entries then
      skip("scripts_field_moves.s is not readable, so the band entry numbers "
           .. "are unverified")
    else
      local index, at = {}, 0
      for name in entries:gmatch("ScriptEntry%s+([A-Za-z0-9_]+)") do
        index[name] = at
        at = at + 1
      end
      ok(at >= 16, "only %d ScriptEntry row(s) found", at)
      ok(index.FieldMoves_UseDefogFromMenu == FM.WEATHER_MOVES.DEFOG.entry,
         "Defog's menu script is entry %s; this port runs %s",
         tostring(index.FieldMoves_UseDefogFromMenu),
         tostring(FM.WEATHER_MOVES.DEFOG.entry))
      ok(index.FieldMoves_UseFlashFromMenu == FM.WEATHER_MOVES.FLASH.entry,
         "Flash's menu script is entry %s; this port runs %s",
         tostring(index.FieldMoves_UseFlashFromMenu),
         tostring(FM.WEATHER_MOVES.FLASH.entry))
      -- ...and the C agrees about Flash, which is the one the task names
      local flashTask = cdefn(fmt, "FieldMoves_FlashTask")
      ok(flashTask ~= nil
         and flashTask:find("SCRIPT_ID%(FIELD_MOVES, "
                            .. FM.WEATHER_MOVES.FLASH.entry .. "%)") ~= nil,
         "FieldMoves_FlashTask does not start FIELD_MOVES entry %d",
         FM.WEATHER_MOVES.FLASH.entry)
      -- and the scripts really do set the flag and clear the weather, which
      -- is why running the entry is enough
      for _, want in ipairs({ { "FieldMoves_UseFlashFromMenu", "DoFlashFunc" },
                              { "FieldMoves_UseDefogFromMenu", "DoDefogFunc" } }) do
        local body = entries:match("\n" .. want[1] .. ":(.-)\n\n")
        ok(body ~= nil and body:find(want[2]) ~= nil
           and body:find("FIELD_MOVE_FUNC_SET_ACTIVE") ~= nil,
           "%s no longer sets its field-move flag, so running the entry would "
           .. "not make the effect persist", want[1])
        ok(body ~= nil and body:find("ScrCmd_0C") ~= nil,
           "%s no longer clears the weather in place, so the cave would stay "
           .. "dark until the next map load", want[1])
      end
    end
  end
end

-- ---------------------------------------------------------------------------
section("2. resolve, including the arms nothing in the cache reaches")
-- ---------------------------------------------------------------------------
-- a plain id passes straight through
for _, v in ipairs({ 0, 2, 14, 16, 29, 30 }) do
  ok(W.resolve(v, { year = 2026, month = 6, day = 15 }) == v,
     "resolve(%d) changed it to %s; only a calendar id is resolved", v,
     tostring(W.resolve(v, { year = 2026, month = 6, day = 15 })))
end
-- ...and a calendar id does not
do
  local date = { year = 2026, month = 1, day = 1 }
  for col = 0, W.YEARLY_COUNT - 1 do
    local id = W.YEARLY_START + col
    local got = W.resolve(id, date)
    ok(got == W.YEARLY[col + 1],
       "resolve(%d) on 1 January answered %s; the calendar's row 1 column %d "
       .. "is %s", id, tostring(got), col + 1, tostring(W.YEARLY[col + 1]))
    ok(got <= W.RENDERABLE_MAX,
       "resolve(%d) answered %s, which the renderer would assert on", id,
       tostring(got))
  end
end
-- THE LEAP-YEAR BOUNDARY, which is the one date this can be wrong on without
-- being obviously wrong. 1 March must read the same calendar row in both.
do
  local leap = W.resolve(32, { year = 2024, month = 3, day = 1 })
  local plain = W.resolve(32, { year = 2026, month = 3, day = 1 })
  ok(leap == plain,
     "1 March reads a different calendar row in a leap year (%s) than in an "
     .. "ordinary one (%s) -- the two halves of the correction no longer "
     .. "cancel and every date after February is off by one",
     tostring(leap), tostring(plain))
  -- ...and 29 February exists, which is the row the correction skips
  local feb29 = W.resolve(32, { year = 2024, month = 2, day = 29 })
  local feb28 = W.resolve(32, { year = 2024, month = 2, day = 28 })
  ok(feb29 ~= nil and feb28 ~= nil,
     "29 February resolved to nil, so the calendar is short a row")
  ok(W.dayNumber({ year = 2024, month = 3, day = 1 })
       - W.dayNumber({ year = 2024, month = 2, day = 29 }) == 1,
     "1 March is not the day after 29 February in a leap year")
  ok(W.dayNumber({ year = 2026, month = 3, day = 1 })
       - W.dayNumber({ year = 2026, month = 2, day = 28 }) == 1,
     "1 March is not the day after 28 February in an ordinary year")
end
-- the penalty arm, which no cache reaches and which would otherwise be cold
do
  local pinned = W.resolve(32, { year = 2026, month = 7, day = 4 }, true)
  ok(pinned == W.YEARLY[W.YEARLY_COUNT + 1],
     "a penalised clock answered %s; FieldSystem_GetWeather pins it to "
     .. "2 January, whose first column is %s", tostring(pinned),
     tostring(W.YEARLY[W.YEARLY_COUNT + 1]))
end
-- a column past the last table refuses rather than indexing off the end
ok(W.resolve(37, { year = 2026, month = 6, day = 15 }) == 0,
   "a weather past the last calendar column answered %s rather than clear",
   tostring(W.resolve(37, { year = 2026, month = 6, day = 15 })))

-- ---------------------------------------------------------------------------
section("3. the looks, and the three kinds of nothing")
-- ---------------------------------------------------------------------------
-- EVERY LOOK NAMES A ROW THAT EXISTS. A typo here draws nothing and reports
-- nothing, which is the failure this whole pass is about.
do
  local missing = {}
  for name, look in pairs(W.LOOK) do
    if look ~= false then
      if G3.LOOKS[look] == nil then
        missing[#missing + 1] = ("%s -> %s"):format(name, tostring(look))
      end
    end
  end
  ok(#missing == 0,
     "%d weather(s) name a look Gen3Weather does not have: %s", #missing,
     table.concat(missing, ", "))
  ok(G3.LOOKS.DARKNESS ~= nil,
     "Gen3Weather has no DARKNESS row, so Sinnoh's one dark cave draws nothing")
  ok(type(G3.LOOKS.DARKNESS) == "table" and type(G3.LOOKS.DARKNESS.veil) == "table",
     "DARKNESS has no veil, so it is a look that looks like nothing")
  -- ...and it is DARKER than the covered-not-dark case, which is the property
  -- that makes it a cave rather than a shadow
  local dark = G3.LOOKS.DARKNESS.veil[4]
  local shade = G3.LOOKS.SHADE and G3.LOOKS.SHADE.veil[4]
  ok(shade and dark > shade,
     "DARKNESS (alpha %s) is not darker than SHADE (%s)", tostring(dark),
     tostring(shade))
  ok(dark < 1,
     "DARKNESS is fully opaque, so an unlit cave cannot be navigated at all")
end
-- CLEAR BY NAME, NO LOOK AT ALL, AND NOT IN THE ENUM are three answers and
-- the module keeps them apart. A `false` for an unnamed id would launder it
-- into the 460 maps that really are clear.
do
  local look, name = W.lookFor(0)
  ok(look == false and name == "CLEAR", "lookFor(0) answered %s, %s",
     tostring(look), tostring(name))
  look, name = W.lookFor(29)
  ok(look == nil and name == "WEATHER_29",
     "lookFor(29) answered %s, %s -- an unnamed id must report its id and no "
     .. "look", tostring(look), tostring(name))
  look, name = W.lookFor(200)
  ok(look == nil and name == nil,
     "lookFor(200) answered %s, %s -- an id outside the enum has no name",
     tostring(look), tostring(name))
end

-- ---------------------------------------------------------------------------
section("4. the two field moves, from both ends of one table")
-- ---------------------------------------------------------------------------
ok(W.CLEARED_BY.FOG == "defog" and W.CLEARED_BY.DARK_FLASH == "flash",
   "CLEARED_BY no longer pairs FOG with defog and DARK_FLASH with flash")
ok(W.CLEARED_BY.DEEP_FOG == nil,
   "DEEP_FOG is listed as clearable; `field_map_change.c` clears FOG only")
-- ONE TABLE READ BOTH WAYS, asserted as a round trip rather than as two lists.
do
  local n = 0
  for name, move in pairs(W.CLEARED_BY) do
    n = n + 1
    ok(W.OFFERS[move] == name,
       "OFFERS[%q] is %s but CLEARED_BY[%q] is %q -- the pair has two "
       .. "spellings again", move, tostring(W.OFFERS[move]), name, move)
  end
  ok(n == 2, "%d weather(s) are cleared by a field move, expected 2", n)
end
-- the substitution
ok(W.afterFieldMoves(16, function(m) return m == "flash" end) == 0,
   "DARK_FLASH with Flash lit did not become clear")
ok(W.afterFieldMoves(16, function() return false end) == 16,
   "DARK_FLASH with Flash out stopped being dark")
ok(W.afterFieldMoves(14, function(m) return m == "flash" end) == 14,
   "Flash cleared the FOG, which is Defog's job")
ok(W.afterFieldMoves(15, function() return true end) == 15,
   "DEEP_FOG was cleared by a field move")
ok(W.afterFieldMoves(29, function() return true end) == 29,
   "an unnamed weather was cleared by a field move")
-- the offer gate, all three states
do
  ok(FM.weatherOffers({ gen4WeatherActive = 16 }, "FLASH") == true,
     "Flash is not offered in DARK_FLASH")
  ok(FM.weatherOffers({ gen4WeatherActive = 16 }, "DEFOG") == false,
     "Defog is offered in DARK_FLASH")
  ok(FM.weatherOffers({ gen4WeatherActive = 14 }, "DEFOG") == true,
     "Defog is not offered in FOG")
  ok(FM.weatherOffers({ gen4WeatherActive = 0 }, "FLASH") == false,
     "Flash is offered in clear weather, which would put a row on every party "
     .. "menu in Sinnoh")
  ok(FM.weatherOffers({}, "FLASH") == false,
     "Flash is offered on a save with no weather at all")
  ok(FM.weatherOffers({ gen4WeatherActive = 16 }, "CUT") == false,
     "a move with no weather row was offered by the weather")
end
-- AND THE PARTY MENU ASKS. The gate is worth nothing if the menu never
-- consults it; this reads the screen's own source because driving the whole
-- menu needs a game.
do
  local src = code(slurp("src/ui/Gen4PartyMenu.lua"))
  ok(src:find("WEATHER_MOVES") ~= nil,
     "Gen4PartyMenu never mentions WEATHER_MOVES, so Flash and Defog are "
     .. "still on no menu and a party carrying Flash in Wayward Cave has no "
     .. "way to use it")
  -- THE ROW IS NOT THE GATE.  This used to demand that `actions()` asked
  -- `weatherOffers` before listing Flash or Defog.  The cartridge does not:
  -- GetContextMenuEntriesForPartyMon (party_menu/main.c) lists every known
  -- field move through GetFieldMoveIndex and asks nothing else; the weather
  -- is FieldMoves_SetUsableMoves' usable bit, read by FieldMoves_CheckFlash /
  -- _CheckDefog when the row is CHOSEN, which answers "You can't use that
  -- here." in clear weather.  So the rows walk the field-move list, and the
  -- weather gate lives in `useFieldMove` (asserted just below).
  local actions = src:match("function Gen4PartyMenu:actions%(%)(.-)\nend")
  ok(actions ~= nil, "Gen4PartyMenu:actions is gone")
  ok(actions == nil or actions:find("F%.ORDER") ~= nil,
     "Gen4PartyMenu:actions does not walk the field-move list (F.ORDER), so "
     .. "Flash and Defog reach no menu row at all")
  ok(actions == nil or actions:find("weatherOffers%s*%(") == nil,
     "Gen4PartyMenu:actions hides Flash/Defog by the weather; the cartridge "
     .. "lists them and refuses at the press")
  -- ...and `useFieldMove` must ask as well, because a row can be reached by a
  -- stale menu or by a mod.
  local use = src:match("function Gen4PartyMenu:useFieldMove(.-)\nend")
  ok(use ~= nil and use:find("weatherOffers%s*%(") ~= nil,
     "Gen4PartyMenu:useFieldMove runs the weather moves without re-checking "
     .. "the weather")
  -- THE ROWS FOLLOW THE MON'S MOVE SLOTS (context_menu.c walks them), which
  -- is stable between openings without a sort.  This used to demand a
  -- `table.sort(rows`, which kept a `pairs` walk still but put the moves in
  -- an order the cartridge never shows.
  ok(actions ~= nil and actions:find("ipairs%s*%(%s*mon%.moves") ~= nil
     and actions:find("table%.sort") == nil,
     "the field-move rows are not built in move-slot order, so Flash and "
     .. "Defog can trade places between openings or sit out of the "
     .. "cartridge's order")
end

-- ---------------------------------------------------------------------------
section("5. the wiring, and what it is worth on a real cache")
-- ---------------------------------------------------------------------------
do
  local src = code(slurp("src/world/OverworldController.lua"))
  local body = src:match("function OverworldState:applyMapWeather%(%)(.-)\nend")
  ok(body ~= nil, "applyMapWeather is gone")
  if body then
    ok(body:find("isGen4") ~= nil,
       "applyMapWeather has no Gen 4 arm, so Sinnoh's weather byte is read "
       .. "nowhere again")
    -- THE THREE STEPS IN THE CARTRIDGE'S ORDER. Resolving the calendar after
    -- the substitution would be wrong in a way nothing would notice, because
    -- no calendar map carries fog or darkness -- so the order is asserted
    -- rather than left to luck.
    local atResolve = body:find("resolve%s*%(")
    local atAfter = body:find("afterFieldMoves%s*%(")
    ok(atResolve and atAfter and atResolve < atAfter,
       "applyMapWeather substitutes for a field move before it resolves the "
       .. "calendar; the cartridge does it the other way round")
    ok(body:find("gen4WeatherActive") ~= nil,
       "applyMapWeather does not store the active weather, so the renderer "
       .. "has nothing to read")
  end
  -- the getter and the renderer must read ONE value
  local g4 = code(slurp("src/script/Gen4Commands.lua"))
  local getter = g4:match("function Commands%.g4_overworld_weather(.-)\nend")
  ok(getter ~= nil, "g4_overworld_weather is gone")
  ok(getter == nil or getter:find("gen4WeatherActive") ~= nil,
     "`getoverworldweather` does not read the saved active weather, so the "
     .. "script and the picture answer the same question from two places -- "
     .. "and Route 213's header is 33, a calendar id, which is not a weather")
  -- ...and the in-place clear must move the drawn value too
  local clear = g4:match("function Commands%.g4_clear_overworld_weather(.-)\nend")
  ok(clear ~= nil, "g4_clear_overworld_weather is gone")
  ok(clear == nil or clear:find("gen4WeatherActive") ~= nil,
     "the in-place weather clear does not touch the drawn value, so Flash "
     .. "would report success, say its line, and leave the cave dark until "
     .. "the next map load")
end

-- HOENN IS UNTOUCHED, which is the standing constraint on every pass.
do
  GameVersion.set("emerald")
  local names = { [3] = "RAIN" }
  ok(GameVersion.isGen3() == true, "the probe is not running as a Gen 3 game")
  ok(not GameVersion.isGen4(),
   "GameVersion says a Gen 3 game is also Gen 4, so the arms added by this "
   .. "pass would run on Hoenn")
  GameVersion.set("platinum")
  ok(GameVersion.isGen4() == true, "the probe did not go back to Gen 4")
end

local maps = loadTable(CACHE, "maps")
if not maps then
  skip("no maps.lua in this cache, so the census below did not run")
else
  local total, byId = 0, {}
  for _, d in pairs(maps) do
    if type(d) == "table" then
      total = total + 1
      local v = tonumber(d.weather)
      if v then byId[v] = (byId[v] or 0) + 1 end
    end
  end
  ok(total >= 500,
     "only %d map(s) in this cache, so the census is not measuring Sinnoh",
     total)
  local date = { year = 2026, month = 6, day = 15 }
  local drawn, clear, unnamed, offEnum = 0, 0, 0, 0
  local ids = {}
  for v in pairs(byId) do ids[#ids + 1] = v end
  table.sort(ids)
  for _, v in ipairs(ids) do
    local look, name = W.lookFor(W.resolve(v, date))
    local raw = W.nameFor(v)
    if raw == nil then offEnum = offEnum + byId[v]
    elseif raw:match("^WEATHER_%d+$") then unnamed = unnamed + byId[v]
    elseif look then drawn = drawn + byId[v]
    else clear = clear + byId[v] end
  end
  ok(offEnum == 0,
     "%d map(s) carry a weather id this port's enum does not contain", offEnum)
  -- A FLOOR ON WHAT THIS PASS BOUGHT. 65 maps draw something that drew
  -- nothing before -- 51 of them fog -- and if that number ever goes DOWN,
  -- a look or a name has gone missing.
  ok(drawn >= 65,
     "only %d map(s) now draw a weather; the measured figure when this was "
     .. "written was 65 (51 fog, 5 calendar, 8 others, 1 dark cave)", drawn)
  report("%d maps: %d draw a weather, %d are clear by name, %d carry an id "
         .. "pokeplatinum has not named", total, drawn, clear, unnamed)
  -- ...AND THE UNNAMED ONES ARE A REPORTED NUMBER RATHER THAN A SILENCE.
  ok(unnamed > 0,
     "no map carries an unnamed weather id, so the honest-placeholder path is "
     .. "cold -- if a later pass identified them all, retire the placeholders")
  for _, v in ipairs(ids) do
    local raw = W.nameFor(v)
    if raw and raw:match("^WEATHER_%d+$") then
      report("  id %d is on %d map(s) and has no name in pokeplatinum",
             v, byId[v])
    end
  end
  -- the one dark cave, by name, because it is the subject
  ok((byId[16] or 0) >= 1,
     "no map in this cache carries DARK_FLASH, so the darkness has no subject")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
