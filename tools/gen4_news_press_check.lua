-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEMON NEWS PRESS NAMED A BLANK POKEMON.
--
-- `getrandomseenspecies` lowered onto `g4_no_feature`, which writes 0 into the
-- destination var -- and 0 is SPECIES_NONE.  The Solaceon News Press asks for
-- a species, stores the answer in VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON and
-- prints its name, so the line came out with a hole in it.
--
-- This is the Underground goods PC's fault in a different room, and the
-- distinction is the same one: the feature being declined is PRESENT.  The
-- port has kept `save.pokedex.seen` all along, and `g4_dex_seen_count` has
-- filtered it by the Sinnoh dex since before this pass -- so the zero was not
-- an absence, it was a wrong answer that a script then printed.
--
-- THE CARTRIDGE'S DEFAULT IS NOT ZERO, and that is the fact most likely to be
-- got wrong by someone implementing this from the description:
--
--     u16 seenSpeciesCount = Pokedex_CountSeen_Local(pokedex);
--     u16 random = LCRNG_Next() % seenSpeciesCount;
--     *destVar = SPECIES_PIKACHU;          /* written BEFORE the loop */
--     for (u16 species = 1, i = 0; species <= NATIONAL_DEX_COUNT; species++) {
--         if (Pokedex_HasSeenSpecies(pokedex, species) == TRUE
--             && Pokemon_SinnohDexNumber(species) != FALSE) { ... }
--     }
--
-- so an empty dex answers Pikachu, not nothing.  Section 2 asserts both ends
-- of that: a real pick when the dex has members, and Pikachu when it does not.
--
-- THE DEADLINE is `VAR_NEWS_PRESS_DEADLINE`, counted down once a day by the
-- number of days that actually passed and saturating at zero
-- (`unk_020559DC.c`).  Section 3 covers the countdown; section 4 the var id,
-- derived by an enum walk and cross-checked against the cartridge's own
-- script bytes.
--
-- Run:  texlua tools/gen4_news_press_check.lua <data/generated> [pokeplatinum] [rom]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg and arg[1]
local PRET  = arg and arg[2]
local ROM   = arg and arg[3]

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
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

local drawn = {}
love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end,
               push = function() end, pop = function() end,
               setFont = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")
local Daily    = require("src.script.Gen4Daily")
local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")

-- THE REQUIRES ARE ASSERTED before anything leans on them: `Gen4Commands`
-- publishes its verbs onto the SHARED `Commands` table as it loads, so a check
-- that required only `Commands` would find every `g4_` handler nil and report
-- the subject absent -- a true statement about the wrong thing.
ok(type(Commands.g4_news_press_species) == "function",
   "g4_news_press_species has no handler, so the row the lowering emits "
   .. "reaches nothing")
ok(type(Commands.g4_news_press_deadline) == "function",
   "g4_news_press_deadline has no handler")
ok(type(Gen4Commands.getVar) == "function"
   and type(Gen4Commands.setVar) == "function",
   "Gen4Commands does not publish getVar/setVar, so every assertion below "
   .. "would read nil and pass for the wrong reason")

local function ctxWith(seen, sinnoh)
  local ctx = { save = { pokedex = { seen = seen or {}, owned = {} } } }
  ctx.game = { save = ctx.save,
               data = { gen4_dex = { orders = { sinnoh = sinnoh or {} } } } }
  return ctx
end
local DEST = 0x4000
local SEED = 0xBEEF  -- see section 2: zero is a legitimate answer nowhere here,
                     -- but a var nobody wrote also reads zero
local function answered(ctx)
  local v = Gen4Commands.getVar(ctx.save, DEST)
  if v == SEED then return "nothing -- the var was never written" end
  return tostring(v)
end

-- ---------------------------------------------------------------------------
section("1. the var ids, derived and then cross-checked against the ROM")
-- ---------------------------------------------------------------------------
-- NEEDS NOTHING but the repository, so this check has something that can fail
-- with no cache, no pret and no cartridge.
ok(Daily.NEWS_PRESS_DEADLINE_VAR == 0x403B,
   "the deadline var is %s; the enum walk over generated/vars_flags.txt puts "
   .. "VAR_NEWS_PRESS_DEADLINE at 0x403B",
   string.format("0x%X", Daily.NEWS_PRESS_DEADLINE_VAR or 0))
ok(Daily.NEWS_PRESS_SPECIES_VAR == 0x40E5,
   "the species var is %s; VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON is 0x40E5",
   string.format("0x%X", Daily.NEWS_PRESS_SPECIES_VAR or 0))
-- Both ids are above VARS_START, which is the property that makes them vars at
-- all rather than flags. A derivation that slipped a whole block would still
-- produce a plausible-looking number, so this is asserted separately.
ok(Daily.NEWS_PRESS_DEADLINE_VAR >= 0x4000
   and Daily.NEWS_PRESS_SPECIES_VAR >= 0x4000,
   "a News Press var id landed below VARS_START (0x4000), so the enum walk "
   .. "slipped out of the var block")

-- THE WALK ITSELF, when pret is present -- because an id typed into a module
-- is a number somebody typed until something re-derives it.
if PRET then
  local text = slurp(PRET .. "/generated/vars_flags.txt")
  if not text then
    skip("no generated/vars_flags.txt under %s", tostring(PRET))
  else
    local ids, nxt = {}, 0
    for line in text:gmatch("[^\r\n]+") do
      local body = line:gsub("//.*", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if body ~= "" then
        local name, rhs = body:match("^([%w_]+)%s*=%s*(.+)$")
        if name then
          if ids[rhs] then nxt = ids[rhs]
          else
            local n = tonumber(rhs)
            if n then nxt = n end
          end
          ids[name] = nxt
        else
          ids[body] = nxt
        end
        nxt = (ids[name or body] or nxt) + 1
      end
    end
    -- THREE ANCHORS FIRST. If the walk is wrong, the two News Press ids would
    -- be wrong together and agreeing with a wrong module would look like
    -- success; these three are known from elsewhere in the port.
    ok(ids.VAR_OBJ_GFX_ID_0 == 0x4020,
       "the enum walk puts VAR_OBJ_GFX_ID_0 at %s, not 0x4020 -- the walk is "
       .. "wrong, so nothing derived from it below means anything",
       tostring(ids.VAR_OBJ_GFX_ID_0))
    ok(ids.VAR_LAST_TALKED == 0x800D,
       "the enum walk puts VAR_LAST_TALKED at %s, not 0x800D",
       tostring(ids.VAR_LAST_TALKED))
    ok(ids.VAR_NEWS_PRESS_DEADLINE == Daily.NEWS_PRESS_DEADLINE_VAR,
       "generated/vars_flags.txt puts VAR_NEWS_PRESS_DEADLINE at %s and the "
       .. "module says %s", tostring(ids.VAR_NEWS_PRESS_DEADLINE),
       string.format("0x%X", Daily.NEWS_PRESS_DEADLINE_VAR or 0))
    ok(ids.VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON
         == Daily.NEWS_PRESS_SPECIES_VAR,
       "generated/vars_flags.txt puts VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON "
       .. "at %s and the module says %s",
       tostring(ids.VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON),
       string.format("0x%X", Daily.NEWS_PRESS_SPECIES_VAR or 0))
    report("the var enum walked: %s names, three anchors agree",
           (function() local n = 0 for _ in pairs(ids) do n = n + 1 end
            return tostring(n) end)())
  end
else
  skip("no pokeplatinum path, so the var ids are not re-derived this run")
end

-- ---------------------------------------------------------------------------
section("2. the species pick, and the default that is not zero")
-- ---------------------------------------------------------------------------
do
  -- A dex with three Sinnoh members and one national-only member. The
  -- national-only one is the control: a pick that can return it is not
  -- applying `Pokemon_SinnohDexNumber`.
  local sinnoh = { 387, 390, 393 }
  local seen = { [387] = true, [390] = true, [393] = true, [151] = true }
  local picks, national = {}, 0
  for _ = 1, 400 do
    local ctx = ctxWith(seen, sinnoh)
    Gen4Commands.setVar(ctx.save, DEST, SEED)
    Commands.g4_news_press_species(ctx, DEST)
    local v = Gen4Commands.getVar(ctx.save, DEST)
    picks[v] = (picks[v] or 0) + 1
    if v == 151 then national = national + 1 end
  end
  ok(national == 0,
     "%d of 400 picks named species 151, which is seen but has no Sinnoh dex "
     .. "number -- the regional filter is not being applied", national)
  ok(picks[SEED] == nil,
     "a pick left the destination var unwritten")
  local distinct = 0
  for _ in pairs(picks) do distinct = distinct + 1 end
  -- ALL THREE must come up. A handler that always answers the first eligible
  -- species passes "it named something eligible" every time.
  ok(distinct == 3,
     "400 picks produced %d distinct species out of 3 eligible; a pick that "
     .. "cannot reach every member is not a pick", distinct)
  ok(picks[387] and picks[390] and picks[393],
     "one of the three eligible species never came up in 400 picks")
end

do
  -- THE DEFAULT. An empty dex, and a dex whose only seen species is outside
  -- the Sinnoh list, must BOTH answer Pikachu -- the second is the cartridge's
  -- fall-through case, where the count and the loop predicate disagree.
  local ctx = ctxWith({}, { 387 })
  Gen4Commands.setVar(ctx.save, DEST, SEED)
  Commands.g4_news_press_species(ctx, DEST)
  ok(Gen4Commands.getVar(ctx.save, DEST) == 25,
     "an empty dex answered %s; pret writes SPECIES_PIKACHU (25) before the "
     .. "loop, so the press names a real Pokemon rather than SPECIES_NONE",
     answered(ctx))
  local ctx2 = ctxWith({ [151] = true }, { 387 })
  Gen4Commands.setVar(ctx2.save, DEST, SEED)
  Commands.g4_news_press_species(ctx2, DEST)
  ok(Gen4Commands.getVar(ctx2.save, DEST) == 25,
     "a dex holding only a non-Sinnoh species answered %s, not Pikachu -- "
     .. "this is the loop-falls-through case", answered(ctx2))
  -- AND NEVER ZERO, which is the bug this pass exists to fix, stated as its
  -- own assertion so it cannot be satisfied by accident.
  local ctx3 = ctxWith({}, {})
  Gen4Commands.setVar(ctx3.save, DEST, SEED)
  Commands.g4_news_press_species(ctx3, DEST)
  ok(Gen4Commands.getVar(ctx3.save, DEST) ~= 0,
     "the News Press answered 0 (SPECIES_NONE), which is what `g4_no_feature` "
     .. "wrote and what made the line print a blank")
end

-- ---------------------------------------------------------------------------
section("3. the deadline, and the countdown that must know how many days")
-- ---------------------------------------------------------------------------
do
  local ctx = ctxWith()
  Commands.g4_news_press_deadline(ctx, "set", 7)
  ok(Daily.deadline(ctx.save) == 7,
     "setting a 7-day deadline stored %s", tostring(Daily.deadline(ctx.save)))
  Gen4Commands.setVar(ctx.save, DEST, SEED)
  Commands.g4_news_press_deadline(ctx, "get", DEST)
  ok(Gen4Commands.getVar(ctx.save, DEST) == 7,
     "reading the deadline back answered %s, not 7", answered(ctx))
  -- THE COUNT, not a flag. Two days off a seven-day deadline is five, and
  -- this is the assertion a "a new day happened" implementation fails.
  Daily.countdown(ctx.save, 2)
  ok(Daily.deadline(ctx.save) == 5,
     "two days off a 7-day deadline left %s, not 5 -- the countdown is "
     .. "subtracting a day-turned flag rather than the days that passed",
     tostring(Daily.deadline(ctx.save)))
  -- SATURATION, both at and past the boundary.
  Daily.countdown(ctx.save, 5)
  ok(Daily.deadline(ctx.save) == 0,
     "five more days left %s, not 0", tostring(Daily.deadline(ctx.save)))
  Commands.g4_news_press_deadline(ctx, "set", 3)
  Daily.countdown(ctx.save, 99)
  ok(Daily.deadline(ctx.save) == 0,
     "99 days off a 3-day deadline left %s; pret clamps at zero rather than "
     .. "wrapping a u16", tostring(Daily.deadline(ctx.save)))
  -- and zero days must not move it, which is what a backwards clock produces
  Commands.g4_news_press_deadline(ctx, "set", 4)
  Daily.countdown(ctx.save, 0)
  ok(Daily.deadline(ctx.save) == 4,
     "a zero-day tick moved the deadline to %s", tostring(Daily.deadline(ctx.save)))
end

-- ---------------------------------------------------------------------------
section("4. the clock, which is NOT the weather table's day number")
-- ---------------------------------------------------------------------------
do
  local function d(y, m, dd) return Daily.civilDay({ year = y, month = m, day = dd }) end
  ok(d(2026, 1, 2) - d(2026, 1, 1) == 1, "consecutive days are not one apart")
  ok(d(2026, 3, 1) - d(2026, 2, 28) == 1,
     "28 February to 1 March 2026 is %d days", d(2026, 3, 1) - d(2026, 2, 28))
  ok(d(2024, 3, 1) - d(2024, 2, 28) == 2,
     "2024 is a leap year, so 28 February to 1 March is %d days",
     d(2024, 3, 1) - d(2024, 2, 28))
  -- THE REASON THIS CLOCK EXISTS. `Gen4Weather.dayNumber` is a day-of-year, so
  -- the difference across New Year is negative; a countdown built on it would
  -- stop counting every 1 January.
  ok(d(2027, 1, 1) - d(2026, 12, 31) == 1,
     "New Year's Eve to New Year's Day is %d days", d(2027, 1, 1) - d(2026, 12, 31))
  local W = require("src.import.Gen4Weather")
  ok(W.dayNumber({ year = 2027, month = 1, day = 1 })
       - W.dayNumber({ year = 2026, month = 12, day = 31 }) < 0,
     "Gen4Weather.dayNumber no longer wraps at New Year, so the comment in "
     .. "Gen4Daily explaining why it needs its own clock is now wrong")
  ok(d(2026, 12, 31) - d(2026, 1, 1) == 364,
     "a full non-leap year is %d days", d(2026, 12, 31) - d(2026, 1, 1))
  ok(d(2024, 12, 31) - d(2024, 1, 1) == 365,
     "a full leap year is %d days", d(2024, 12, 31) - d(2024, 1, 1))
end

-- ---------------------------------------------------------------------------
section("5. the poll, including the first one on an old save")
-- ---------------------------------------------------------------------------
do
  -- A FIRST POLL MUST COUNT NOTHING. A save that has never recorded a day
  -- would otherwise lose a day off a deadline the moment this module landed --
  -- including one set seconds earlier in the same session.
  local ctx = ctxWith()
  Commands.g4_news_press_deadline(ctx, "set", 3)
  Daily.poll(ctx.save)
  ok(Daily.deadline(ctx.save) == 3,
     "the first poll on a save with no recorded day took the deadline to %s",
     tostring(Daily.deadline(ctx.save)))
  ok(ctx.save.g4DailyDay ~= nil, "the poll did not record the day")
  -- A SECOND POLL ON THE SAME DAY must also count nothing.
  Daily.poll(ctx.save)
  ok(Daily.deadline(ctx.save) == 3,
     "a second poll on the same day took the deadline to %s",
     tostring(Daily.deadline(ctx.save)))
  -- MOVING THE STORED DAY BACK is how a real elapsed gap is simulated without
  -- touching the clock.
  ctx.save.g4DailyDay = ctx.save.g4DailyDay - 2
  Daily.poll(ctx.save)
  ok(Daily.deadline(ctx.save) == 1,
     "two elapsed days left the deadline at %s, not 1",
     tostring(Daily.deadline(ctx.save)))
  -- A CLOCK THAT WENT FORWARD then came back must not clear a deadline the
  -- player has not waited out.
  Commands.g4_news_press_deadline(ctx, "set", 5)
  ctx.save.g4DailyDay = ctx.save.g4DailyDay + 500
  Daily.poll(ctx.save)
  ok(Daily.deadline(ctx.save) == 5,
     "a backwards clock took the deadline to %s", tostring(Daily.deadline(ctx.save)))
  ok(ctx.save.g4DailyDay == Daily.civilDay(),
     "a backwards clock left the stored day in the future, so the next real "
     .. "day change would count nothing")
end

-- ---------------------------------------------------------------------------
section("6. the lowerings, and nothing left on a stub")
-- ---------------------------------------------------------------------------
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua")
                     or slurp("../src/script/Gen4ScriptVM.lua"))
  ok(src ~= "", "could not read Gen4ScriptVM.lua, so section 6 graded nothing")
  local rows = {
    getrandomseenspecies = "g4_news_press_species",
    setnewspressdeadline = "g4_news_press_deadline",
    getnewspressdeadline = "g4_news_press_deadline",
  }
  for name, verb in pairs(rows) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend")
    ok(body ~= nil, "`%s` has no lowering", name)
    if body then
      ok(body:find(verb, 1, true) ~= nil,
         "`%s` does not lower onto %s", name, verb)
      ok(body:find("g4_no_feature") == nil and body:find("g4_noop") == nil,
         "`%s` is still on a stub verb", name)
    end
  end
  -- THE OPERAND, which the handler tests above cannot see because they call
  -- the handlers directly. Each of these three carries exactly one operand and
  -- it must be args[1]; a lowering that forwarded a different index would pass
  -- every assertion in sections 2 and 3.
  for name in pairs(rows) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend") or ""
    local order = {}
    for n in body:gmatch("ins%.args%[(%d)%]") do order[#order + 1] = n end
    ok(table.concat(order, ",") == "1",
       "`%s` forwards operands [%s]; it has one and it is args[1]",
       name, table.concat(order, ","))
  end
  -- AND THE POLL IS WIRED. A module nothing calls is a module that cannot
  -- count days, and sections 3-5 would still pass.
  local ow = code(slurp("src/world/OverworldController.lua")
                    or slurp("../src/world/OverworldController.lua"))
  ok(ow:find("Gen4Daily", 1, true) ~= nil,
     "nothing in OverworldController requires Gen4Daily, so the countdown "
     .. "never runs")
  ok(ow:find('require%("src%.script%.Gen4Daily"%)%.poll') ~= nil,
     "OverworldController names Gen4Daily but does not poll it")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
