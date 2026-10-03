-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE KEYS INSIDE `constants`, AND WHETHER THE RUNNING GAME HAS THEM.
--
-- `tools/gen4_cache_wiring_check.lua` compares the MODULE names the extractor
-- writes against the list `Data` loads, in both directions. That caught four
-- modules written and never loaded -- the move animations and the particles
-- among them, which cost every Platinum move its animation.
--
-- IT CANNOT SEE ONE LEVEL DOWN. A feature whose data rides as a KEY inside
-- `constants` rather than as a module of its own is invisible to it, and four
-- finished features were sitting in exactly that blind spot:
--
--     gen4BerryGrowth, gen4BerryPositions, gen4BerryInitial
--                                     -> src/world/Gen4BerryPatches.lua
--     gen4PoketchRoutes, gen4PoketchCoin, gen4PoketchMapCells
--                                     -> src/pokemon/Gen4PoketchState.lua
--     gen4HoneyEncounters             -> src/world/Gen4HoneyTrees.lua
--     martSpecialties                 -> src/import/Gen4Mart.lua
--
-- The extractor writes all eight. The engine reads all eight. The installed
-- cache carried NONE of them, because it was built before the stages that
-- write them -- and `Gen4BerryPatches` opens with
--
--     if not c.gen4BerryGrowth or not c.gen4BerryInitial then return nil end
--
-- so the whole berry system returns nil and nothing says why. Written, read,
-- and absent: a feature that is finished in the repository and does not exist
-- in the game, which is the most expensive kind of gap because it looks done.
--
-- THREE DIRECTIONS, and the third is the one that found it:
--
--   WRITTEN BUT UNREAD -- data produced on every import that nothing consumes.
--     The `gen4_species_sprites` class, one level down. Reported, not failed:
--     a key may legitimately be written ahead of its consumer.
--
--   READ BUT UNWRITTEN -- the engine names a key the extractor never produces.
--     Always a fault: the consumer silently takes its nil branch forever.
--
--   WRITTEN BUT ABSENT FROM A GIVEN CACHE -- the data exists in the code and
--     not in the install. Needs a cache to test against, which is why that
--     section is skipped without one, and it names the CONSUMER for each
--     missing key so the output says which feature is off rather than which
--     identifier is missing.
--
-- Run:  texlua tools/gen4_constants_wiring_check.lua [cache dir]

package.path = "./?.lua;" .. package.path

local CACHE = arg and arg[1]

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local t = f:read("*a")
  f:close()
  return t
end

-- ---------------------------------------------------------------------------
section("1. the keys the extractor writes, read off the extractor")
-- ---------------------------------------------------------------------------
-- DERIVED, because a list of keys kept here would be the hardcoded twin of the
-- table it describes -- the fault repaired twice already in this tree.
local source = read("src/import/RomExtractorGen4.lua")
ok(source ~= nil, "src/import/RomExtractorGen4.lua could not be read")
if not source then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local written = {}
do
  local at = source:find('self:write("constants", {', 1, true)
  ok(at ~= nil, "the extractor no longer writes a `constants` table literal")
  if at then
    -- Walk to the matching close brace, counting depth, and take the keys that
    -- sit at depth 1 -- the top level of the table and nothing nested in it.
    local i = source:find("{", at, true)
    local depth, j = 0, i
    local body
    while j <= #source do
      local ch = source:sub(j, j)
      if ch == "{" then depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then body = source:sub(i + 1, j - 1) break end
      end
      j = j + 1
    end
    ok(body ~= nil, "the `constants` table literal is not balanced")
    if body then
      local depth2 = 0
      for line in body:gmatch("[^\n]+") do
        local trimmed = line:gsub("^%s+", "")
        if depth2 == 0 then
          local key = trimmed:match("^([%a_][%w_]*)%s*=")
          if key then written[#written + 1] = key end
        end
        local _, opens = line:gsub("{", "")
        local _, closes = line:gsub("}", "")
        depth2 = depth2 + opens - closes
        if depth2 < 0 then depth2 = 0 end
      end
    end
  end
end
table.sort(written)
io.write(("   %d keys written into constants\n"):format(#written))
ok(#written >= 20, "only %d constants keys found (was 20+); the parse probably "
   .. "missed the table", #written)
-- A SPOT CHECK that the parse found real keys rather than whatever it liked:
-- `gen` is the field seventy-one places read, so if it is absent the parse is
-- wrong, not the extractor.
local haveGen = false
for _, k in ipairs(written) do if k == "gen" then haveGen = true end end
ok(haveGen, "the parse did not find `gen`, so it is not reading the right table")

-- ---------------------------------------------------------------------------
section("2. every written key, and whether anything reads it")
-- ---------------------------------------------------------------------------
-- The engine's own files, excluding the importer: a key the extractor both
-- writes and reads proves nothing about whether the GAME uses it.
local consumers = {}
do
  local dirs = { "src/world", "src/pokemon", "src/battle", "src/ui", "src/script",
                 "src/core", "src/render", "src/mods" }
  local files = {}
  for _, dir in ipairs(dirs) do
    local pipe = io.popen('ls "' .. dir .. '"/*.lua 2>/dev/null')
    if pipe then
      for line in pipe:lines() do files[#files + 1] = line end
      pipe:close()
    end
  end
  ok(#files > 50, "only %d engine files were scanned; the read side is not "
     .. "being measured", #files)
  local text = {}
  for _, path in ipairs(files) do
    local body = read(path)
    if body then text[path] = body end
  end
  for _, key in ipairs(written) do
    for path, body in pairs(text) do
      if body:find("%f[%w_]" .. key .. "%f[^%w_]") then
        consumers[key] = consumers[key] or {}
        consumers[key][#consumers[key] + 1] = path
      end
    end
  end
end
local unread = {}
for _, key in ipairs(written) do
  if not consumers[key] then unread[#unread + 1] = key end
end
io.write(("   %d of %d written keys have a consumer in the engine\n")
         :format(#written - #unread, #written))
-- REPORTED, NOT FAILED. A key written ahead of its consumer is a half-built
-- feature, which is a thing worth seeing and not a thing worth stopping on.
if #unread > 0 then
  io.write("   written and read by nothing yet:\n")
  for _, key in ipairs(unread) do io.write(("     %s\n"):format(key)) end
end
ok(#unread <= 12, "%d written keys have no consumer at all (was 12 or fewer); "
   .. "that is a lot of data produced for nobody", #unread)

-- ---------------------------------------------------------------------------
section("3. nothing reads a key the extractor does not write")
-- ---------------------------------------------------------------------------
-- The other direction, and always a fault: the consumer takes its nil branch
-- for ever and says nothing. Only `gen4`-prefixed names are checked, because
-- those are unambiguous -- a bare word like `badges` appears in a hundred
-- places that have nothing to do with this table.
local writtenSet = {}
for _, k in ipairs(written) do writtenSet[k] = true end
-- THE ACCESS HAS TO NAME A CONSTANTS TABLE, which is the whole difficulty.
-- A first version matched every `.gen4Something` in the engine and reported
-- THIRTY-SEVEN phantoms -- `gen4Anim`, `gen4Vars`, `gen4Camera` and the rest --
-- every one of them an ordinary field on a battle, a save or the overworld
-- that has nothing to do with this table. A check that cries wolf
-- thirty-seven times is worse than no check, so it matches only accesses
-- written against a constants table by name: `constants.gen4X`,
-- `constants(game).gen4X`, `something.constants.gen4X`.
--
-- That is narrower than the truth -- a file that binds `local c =
-- constants(game)` and then reads `c.gen4X` is not seen -- and narrow is the
-- right direction to be wrong in here. Section 4 catches the same fault from
-- the other side for any key that HAS a consumer, so the two overlap where it
-- matters.
local phantom, seenRead = {}, 0
do
  local pipe = io.popen('grep -rhoE "constants[a-zA-Z()a-z]*\\.gen4[A-Za-z0-9_]+'
                        .. '|\\.constants\\.gen4[A-Za-z0-9_]+" '
                        .. 'src/world src/pokemon src/battle src/ui src/script '
                        .. 'src/core 2>/dev/null')
  if pipe then
    local seen = {}
    for line in pipe:lines() do
      local key = line:match("(gen4[%w_]+)$")
      if key and not seen[key] then
        seen[key] = true
        seenRead = seenRead + 1
        if not writtenSet[key] then phantom[#phantom + 1] = key end
      end
    end
    pipe:close()
  end
end
-- ...and the scan found something, or section 3 is asserting that an empty set
-- contains no faults.
ok(seenRead >= 4, "only %d constants key(s) were found being read this way; "
   .. "the pattern has stopped matching", seenRead)
-- ONE IS READ ON PURPOSE AND NOT WRITTEN YET, and it is not a fault: a hook
-- left for a stage that has not been built, with a stated fallback beside it.
-- `Gen4Battle.actionLabels` says so outright -- "a later extractor stage can
-- publish Platinum's own four words as `constants.gen4BattleMenu` and they
-- will be used without this file changing; the literals are the floor" -- and
-- it prints the English the cartridge prints until then. That is a deliberate
-- seam, so it is NAMED here rather than allowed by loosening the rule, and a
-- SECOND one still fails.
--
-- (It is a real gap all the same, just a declared one: the battle menu's four
-- words are the engine's English, not the cartridge's, so a non-English
-- Platinum would print them wrong.)
local HOOKS = { gen4BattleMenu = true }
local unexpected, hooks = {}, 0
for _, key in ipairs(phantom) do
  if HOOKS[key] then hooks = hooks + 1 else unexpected[#unexpected + 1] = key end
end
ok(#unexpected == 0,
   "%d gen4 constants key(s) are read by the engine and written by nothing: %s",
   #unexpected, table.concat(unexpected, ", "))
-- ...and the named hook is still unwritten. If a stage starts writing it, this
-- fails and the exception above should go rather than linger as folklore.
ok(hooks == 1,
   "%d of the declared hooks are still unwritten, not 1 -- if gen4BattleMenu "
   .. "is published now, drop it from HOOKS", hooks)

-- ---------------------------------------------------------------------------
section("4. ...and whether the installed cache actually has them")
-- ---------------------------------------------------------------------------
if not CACHE then
  io.write("   (no cache dir given -- skipped; pass one to check an install)\n")
else
  local chunk, why = loadfile(CACHE .. "/constants.lua")
  ok(chunk ~= nil, "%s/constants.lua did not load: %s", CACHE, tostring(why))
  if chunk then
    local constants = chunk()
    ok(type(constants) == "table", "constants.lua did not return a table")
    if type(constants) == "table" then
      ok(tonumber(constants.gen) == 4,
         "this cache is not a Gen 4 one (constants.gen = %s)",
         tostring(constants.gen))
      local missing = {}
      for _, key in ipairs(written) do
        -- A key the extractor may legitimately leave nil on some cartridges is
        -- still expected to be PRESENT once written, so absence is the test.
        if constants[key] == nil and consumers[key] then
          missing[#missing + 1] = key
        end
      end
      if #missing > 0 then
        io.write("   written, read by the engine, and NOT IN THIS CACHE:\n")
        for _, key in ipairs(missing) do
          local who = consumers[key] and consumers[key][1] or "?"
          io.write(("     %-24s read by %s\n"):format(key, who))
        end
      end
      ok(#missing == 0,
         "%d constants key(s) are written by the extractor and read by the "
         .. "engine but absent from this cache -- those features are inert "
         .. "until it is re-extracted", #missing)
    end
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
