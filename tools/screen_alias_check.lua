-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- AN UNNAMED OPTION ON A SCREEN PUSH IS NOT A DOWNGRADE, IT IS A CRASH.
--
-- Reported from play: "Getting an error on the pokemon summary menu in gen4 --
-- src/ui/SummaryMenu.lua:550: attempt to index local 'def' (a nil value)".
--
-- `Gen4PartyMenu` pushes `SummaryMenu` with `{ mon = mon, readOnlyMoves = ...}`
-- and `Gen4SummaryMenu.new` reads that key -- but the alias in Screens.lua
-- listed only `{ onCancel, mon }`.  `servedBy` declines a push carrying a key
-- the alias does not name, so the Gen 4 screen was refused; on a Gen 4 cache
-- the Gen 3 table is never consulted (`resolveId` asks `if isGen3(game)`), so
-- the push landed on the Game Boy `SummaryMenu`.
--
-- AND THE TWO GENERATIONS' SCREENS HAVE DIFFERENT SIGNATURES.  Gen 3 and Gen 4
-- screens take `(game, opts)`; the Game Boy ones take `(game, mon, opts)`.  So
-- the options table arrived where the Pokemon goes, `mon.species` was nil,
-- `data.pokemon[nil]` was nil, and the draw died several frames later on a
-- line that had nothing to do with it.
--
-- Nothing logged either: the "which option declined it" warning existed on the
-- Gen 3 path only.
--
-- Run:  texlua tools/screen_alias_check.lua

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local fails, checks, reports = 0, 0, 0
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
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function listDir(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
  if not p then return out end
  for line in p:lines() do
    if line:match("%.lua$") then out[#out + 1] = line end
  end
  p:close()
  return out
end

love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
}

local GameVersion = require("src.core.GameVersion")
local Screens = require("src.ui.Screens")

-- ---------------------------------------------------------------------------
section("1. the reported push resolves to the Gen 4 screen")
-- ---------------------------------------------------------------------------
GameVersion.set("platinum")
ok(GameVersion.isGen4() == true, "the probe is not running as a Gen 4 game")
local game = { data = {}, save = {} }
local mon = { species = 387, level = 5, moves = {}, stats = { hp = 20 } }

-- EXACTLY what Gen4PartyMenu pushes, both arms of its `readOnlyMoves`.
for _, ro in ipairs({ false, true }) do
  local id = Screens.resolveId(game, "SummaryMenu", { mon = mon, readOnlyMoves = ro })
  ok(id == "Gen4SummaryMenu",
     "the party menu's SUMMARY push (readOnlyMoves = %s) resolved to %s, not "
     .. "Gen4SummaryMenu -- that screen takes (game, mon, opts) positionally, "
     .. "so the options table lands where the Pokemon goes", tostring(ro), id)
end
-- ...and the shapes that already worked still do
ok(Screens.resolveId(game, "SummaryMenu", mon) == "Gen4SummaryMenu",
   "a bare Pokemon no longer resolves to the Gen 4 summary")
ok(Screens.resolveId(game, "SummaryMenu",
     { mon = mon, onCancel = function() end }) == "Gen4SummaryMenu",
   "mon + onCancel no longer resolves to the Gen 4 summary")

-- `choose` STILL falls through, deliberately: Gen4SummaryMenu assigns
-- self.choose and never reads it, so serving it there would be a screen with
-- no way to pick a move.  Asserted so the fallthrough stays a decision.
ok(Screens.resolveId(game, "SummaryMenu", { mon = mon, choose = true })
     == "SummaryMenu",
   "`choose` is now served by the Gen 4 summary, which assigns self.choose "
   .. "and never reads it -- the player would have no way to pick")

-- ---------------------------------------------------------------------------
section("2. the fallback can read what a declined push hands it")
-- ---------------------------------------------------------------------------
-- The `choose` push above ends up at the Game Boy screen with an OPTIONS TABLE
-- in the argument the Game Boy screen reads as the Pokemon.  That is the crash,
-- and it is separate from the routing: a fallback that cannot read its argument
-- is not a fallback.
do
  local Summary = require("src.ui.SummaryMenu")
  local g = { data = { pokemon = { [387] = { name = "TURTWIG" } },
                       field = {} }, save = {} }
  local okNew, screen = pcall(Summary.new, g, { mon = mon, choose = true })
  ok(okNew, "SummaryMenu.new raised on a declined push's options table: %s",
     tostring(screen))
  if okNew then
    ok(screen.mon == mon,
       "SummaryMenu read the options table as the Pokemon, so mon.species is "
       .. "nil and the draw dies on data.pokemon[nil]")
  end
  -- ...and the ordinary positional call is untouched
  local okOld, plain = pcall(Summary.new, g, mon)
  ok(okOld and plain.mon == mon,
     "the ordinary SummaryMenu.new(game, mon) call changed shape")
end

-- ---------------------------------------------------------------------------
section("3. a key the screen READS must be named by its alias")
-- ---------------------------------------------------------------------------
-- THE SWEEP THAT WOULD HAVE CAUGHT IT, and the subjects derive themselves: a
-- new screen or a new push site is covered the day it is written.
--
-- THE RULE IS NOT "every pushed key must be named".  Run that way, this found
-- 32 offenders and every one of them was correct: `picked`, `giveTo`,
-- `shiftSwitchMon`, `member`, `done`, `old`, `item`, `who`, `save` and `name`
-- are read by NO Gen 3 or Gen 4 screen, so those pushes genuinely cannot be
-- served by one and falling back is the right answer.  A check that reports
-- thirty-two correct things as faults gets switched off.
--
-- The rule that is both true and decidable:
--
--     a key the generation's own screen READS must be named by its alias,
--
-- because that is a screen declining a push it could have served.  Reading is
-- "mentioned more than once": every one of these is assigned (`self.k = arg
-- and arg.k`) and the supported ones are then USED somewhere.  That is what
-- separates `readOnlyMoves` in Gen4SummaryMenu -- assigned at line 105 and
-- consulted at 391 -- from `choose`, which is assigned and never read, so
-- serving it would be a screen with no way to pick a move.
--
-- Only table-literal pushes are read: those are the ones whose keys can be
-- checked statically, and they are the shape that crashes.
local aliases = Screens.ALIASES_FOR_CHECKS
if type(aliases) ~= "table" then
  report("Screens does not publish its alias tables, so section 3 could not "
         .. "run; add Screens.ALIASES_FOR_CHECKS = { gen3 = ..., gen4 = ... }")
else
  -- how many times a module mentions a key, so "assigned once" is separable
  -- from "assigned and then used"
  local mentionCache = {}
  local function mentions(moduleId, key)
    mentionCache[moduleId] = mentionCache[moduleId] or slurp("src/ui/" .. moduleId .. ".lua")
    local src = mentionCache[moduleId]
    if not src then return nil end
    local n = 0
    for _ in src:gmatch("[%w_%.]*%." .. key .. "%f[%W]") do n = n + 1 end
    return n
  end

  local sites, offenders, declines = 0, {}, 0
  for _, dir in ipairs({ "src/ui", "src/world", "src/script", "src/battle" }) do
    for _, name in ipairs(listDir(dir)) do
      local src = slurp(dir .. "/" .. name)
      if src then
        for id, body in src:gmatch('push%s*%([^,]+,%s*["\']([%w_]+)["\']%s*,%s*(%b{})') do
          sites = sites + 1
          local keys = {}
          local depth, i = 0, 1
          while i <= #body do
            local c = body:sub(i, i)
            if c == "{" then depth = depth + 1
            elseif c == "}" then depth = depth - 1
            elseif c == "(" then
              local chunk = body:match("^%b()", i)
              if chunk then i = i + #chunk - 1 end
            elseif depth == 1 then
              local k = body:match("^([%a_][%w_]*)%s*=", i)
              if k and (i == 1 or body:sub(i - 1, i - 1):match("[{,%s]")) then
                keys[k] = true
                i = i + #k
              end
            end
            i = i + 1
          end
          -- WHICH GENERATIONS THIS CALL SITE CAN REACH, from its filename.
          -- `Gen3Commands.lua` only ever runs on a Gen 3 cache, where
          -- `resolveId` never consults the Gen 4 table.  A shared file reaches
          -- both.  Derived rather than listed.
          local gens = { "gen3", "gen4" }
          if name:match("^Gen3") then gens = { "gen3" }
          elseif name:match("^Gen4") then gens = { "gen4" } end
          for _, gen in ipairs(gens) do
            local alias = aliases[gen] and aliases[gen][id]
            if alias and not alias.positional then
              for k in pairs(keys) do
                if not alias.opts[k] then
                  declines = declines + 1
                  local n = mentions(alias.id, k)
                  if n and n > 1 then
                    offenders[#offenders + 1] = ("%s/%s pushes %s with `%s`; "
                      .. "%s mentions it %d times (assigned AND read) but the "
                      .. "%s alias does not name it, so the screen declines a "
                      .. "push it could have served")
                      :format(dir, name, id, k, alias.id, n, gen)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  -- TWO FLOORS, because this section's result is an ABSENCE and a regex that
  -- stopped matching would report a clean sweep over nothing at all.
  ok(sites >= 30, "only %d table-literal push site(s) were found; the sweep is "
     .. "not reaching the call sites and its clean result means nothing", sites)
  ok(declines >= 10,
     "only %d declining key(s) were seen across the whole port; the rule below "
     .. "is only interesting because declines are COMMON and correct, and a "
     .. "count this low means the alias lookup is not working", declines)
  io.write(("   %d table-literal push sites, %d declining key(s), %d of them "
            .. "on a screen that reads the key\n"):format(sites, declines,
                                                          #offenders))
  for _, o in ipairs(offenders) do io.write("   ", o, "\n") end
  ok(#offenders == 0,
     "%d push(es) carry a key the generation's own screen READS and its alias "
     .. "does not name; each one declines a screen that could have served it "
     .. "and falls through to one whose arguments are positional (listed above)",
     #offenders)
end

-- ---------------------------------------------------------------------------
section("4. a decline says so, on BOTH generations")
-- ---------------------------------------------------------------------------
-- The silence is why this reached play.  The warning existed on the Gen 3 path
-- only, so a Gen 4 push that declined said nothing at all.
do
  local src = slurp("src/ui/Screens.lua") or ""
  ok(#src > 0, "src/ui/Screens.lua did not open")
  local code = src:gsub("%-%-[^\r\n]*", "")
  ok(code:find("local function warnDeclined", 1, true) ~= nil,
     "the decline warning is not a shared function, so it is about to be "
     .. "written twice again")
  local calls = 0
  for _ in code:gmatch("warnDeclined%(") do calls = calls + 1 end
  ok(calls >= 3,
     "warnDeclined is declared and called %d time(s); both the Gen 3 and the "
     .. "Gen 4 decline paths have to reach it", calls - 1)
  -- and behaviourally: a declining Gen 4 push logs
  local Logger = require("src.core.Logger")
  local realWarn, said = Logger.warn, {}
  Logger.warn = function(fmt, ...) said[#said + 1] = tostring(fmt) end
  Screens.resolveId(game, "SummaryMenu", { mon = mon, aKeyNobodyServes = 1 })
  Logger.warn = realWarn
  local found = false
  for _, line in ipairs(said) do
    if line:find("does not serve", 1, true) then found = true end
  end
  ok(found,
     "a Gen 4 push carrying an unserved key declined silently; that silence "
     .. "is how the summary crash reached play")
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
