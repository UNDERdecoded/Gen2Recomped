-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DOES EVERY OVERWORLD GRAPHICS ID REACH A SPRITE.
--
-- A Gen 4 map object carries a `graphicsId`, which is NOT an archive index. It
-- is a key into the cartridge's own lookup table, and turning one into a
-- picture takes two hops:
--
--     graphicsId --Gen4ObjectGfx.name--> a NAME
--     NAME --gen4_overworld.sprites[name].member--> an mmodel.narc member
--
-- and the two names come from different places. `Gen4ObjectGfx` is transcribed
-- from pokeplatinum's `OBJ_EVENT_GFX_*` constants; the key is the NARC's own
-- member name. THE JOIN IS BY STRING, so a sprite whose two names differ by
-- one character is simply not found.
--
-- TWO OF THEM DIFFER:
--
--     id 176  player_m_holding_poke_ball  ->  member 155  player_m_holding_pokeball
--     id 177  player_f_holding_poke_ball  ->  member 156  player_f_holding_pokeball
--
-- `poke_ball` against `pokeball`, and NEITHER IS WRONG. pokeplatinum writes
-- both in a single line of object_event_gfx_data.c -- the constant one way and
-- the file the other -- and spells the CONSTANT `POKEBALL` for the
-- distortion-world pair, so the cartridge disagrees with itself.
--
-- WHAT IT COST. Those two ids are the player's counterpart holding a Poke Ball
-- -- Dawn when you play as Lucas -- and their one use is the catching
-- demonstration on Route 201. Everything else was right: the entry script ran,
-- the gender branch picked 177, the member existed, the PNG was on disk. The
-- lookup missed on an underscore, the object kept its placeholder and drew
-- nothing, and what reaches the player is PROFESSOR ROWAN standing alone on
-- the tile where Dawn should be beside him -- which reads as a wrong sprite
-- rather than a missing one. Reported as "Dawn is missing from the pokeball
-- catching intro it's showing the old man placeholder".
--
-- This is the port's recurring fault once more: ONE THING SPELLED TWO WAYS IN
-- TWO FILES THAT NEVER MEET. It has cost a feature at least eight times now --
-- the type chart, the abilities, the move effects, the ball pocket, the item
-- key, the party icons, the move targeting, and this.
--
-- WHAT IS PINNED, and why these shapes:
--   * the exact joins as a FLOOR -- an archive revision may add sprites;
--   * the normalise-only joins EXACTLY, and named. Two is not a budget. A
--     third means a new spelling nobody has looked at, and the right response
--     is to look at it rather than to raise a number;
--   * that the loose match did not become promiscuous: the ids that must NOT
--     resolve -- the var slots, the signposts -- still do not;
--   * and the whole hop run through the REAL `resolveGraphicsVar`, because
--     every claim above is about two tables and the thing that actually has
--     to work is the function that joins them.
--
-- Run:  texlua tools/gen4_object_sprite_check.lua <cache dir>

package.path = "./?.lua;" .. package.path

if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local M = {}
    local function t(v) return math.floor(v) % 4294967296 end
    local function op(a, b, f)
      local r, m = 0, 1
      a, b = t(a), t(b)
      for _ = 1, 32 do
        r = r + f(a % 2, b % 2) * m
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end
    function M.band(a, b) return op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
    function M.bor(a, b) return op(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end
    function M.bxor(a, b) return op(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end
    function M.bnot(a) return 4294967295 - t(a) end
    function M.lshift(a, n) return t(t(a) * 2 ^ n) end
    function M.rshift(a, n) return math.floor(t(a) / 2 ^ n) end
    function M.arshift(a, n) return M.rshift(a, n) end
    function M.tobit(a) local v = t(a) return v >= 2147483648 and v - 4294967296 or v end
    function M.tohex(a) return ("%08x"):format(t(a)) end
    return M
  end
end

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end,
                 getDirectoryItems = function() return {} end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end,
               setColor = function() end, draw = function() end, rectangle = function() end,
               newQuad = function() return {} end, print = function() end,
               push = function() end, pop = function() end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
  window = { getMode = function() return 256, 384 end },
}

local CACHE = arg and arg[1]
if not CACHE then
  io.write("usage: texlua tools/gen4_object_sprite_check.lua <cache dir>\n")
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

local okG, Gfx = pcall(require, "src.import.Gen4ObjectGfx")
ok(okG, "src.import.Gen4ObjectGfx did not load: %s", tostring(Gfx))
local chunk, why = loadfile(CACHE .. "/gen4_overworld.lua")
ok(chunk ~= nil, "%s/gen4_overworld.lua did not load: %s", CACHE, tostring(why))
if not (okG and chunk) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end
local overworld = chunk()
local sprites = overworld and overworld.sprites
ok(type(sprites) == "table", "gen4_overworld carries no `sprites` table")
if type(sprites) ~= "table" then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local function normalise(name)
  return (name:gsub("%.%w+$", ""):gsub("[_%s]", ""):lower())
end

section("1. how the two name lists join")
local byNorm = {}
for key, value in pairs(sprites) do byNorm[normalise(key)] = value end

local total = 0
while Gfx.name(total) do total = total + 1 end
ok(total >= 276, "Gen4ObjectGfx knows only %d names (was 276)", total)

local exact, loose, unresolved = 0, {}, 0
for id = 0, total - 1 do
  local name = Gfx.name(id)
  if name then
    if sprites[name] then
      exact = exact + 1
    elseif byNorm[normalise(name)] then
      local record = byNorm[normalise(name)]
      loose[#loose + 1] = { id = id, name = name, member = tonumber(record.member) }
    else
      unresolved = unresolved + 1
    end
  end
end
io.write(("   %d join exactly, %d only once normalised, %d reach no member\n")
         :format(exact, #loose, unresolved))
ok(exact >= 209, "only %d names join exactly (was 209)", exact)

section("2. the normalise-only joins, which are the fault this file is for")
-- EXACTLY TWO, AND THESE TWO. Not a floor: a third is a spelling nobody has
-- looked at, and raising this number would hide it rather than record it.
ok(#loose == 2, "%d name(s) join only when normalised, not 2:%s", #loose,
   (function()
     local t = {}
     for _, row in ipairs(loose) do
       t[#t + 1] = ("\n    id %d %s -> member %s"):format(row.id, row.name, tostring(row.member))
     end
     return table.concat(t)
   end)())
local WANT = {
  [176] = { name = "player_m_holding_poke_ball", member = 155 },
  [177] = { name = "player_f_holding_poke_ball", member = 156 },
}
for _, row in ipairs(loose) do
  local want = WANT[row.id]
  ok(want ~= nil, "id %d (%s) needs normalising and was not one of the two known",
     row.id, row.name)
  if want then
    ok(row.name == want.name, "id %d is named %s, not %s", row.id, row.name, want.name)
    ok(row.member == want.member, "id %d resolves to member %s, not %d",
       row.id, tostring(row.member), want.member)
  end
end
-- ...and the picture is really there, which is what makes this fixable without
-- a re-extract: the cache already holds the member under the ARCHIVE's name.
for _, key in ipairs({ "player_m_holding_pokeball", "player_f_holding_pokeball" }) do
  local record = sprites[key]
  ok(record ~= nil, "the cache has no `%s` sprite at all", key)
  ok(record and record.path, "`%s` carries no picture path", key)
end

section("3. the loose match did not become promiscuous")
-- NORMALISATION MUST STAY INJECTIVE, and this is the assertion that makes
-- trying the exact name first mean anything. With no two archive names
-- collapsing to the same key, the loose map cannot re-point a sprite that
-- already joins -- which is why removing the exact lookup changes nothing
-- today, and why that is a property rather than a coincidence worth leaving
-- untested. The day two names do collide, the loose map has to pick one of
-- them arbitrarily and this fails instead of quietly drawing the wrong NPC.
do
  local seen, collisions = {}, {}
  for key in pairs(sprites) do
    local n = normalise(key)
    if seen[n] then
      collisions[#collisions + 1] = ("%s vs %s"):format(seen[n], key)
    else
      seen[n] = key
    end
  end
  ok(#collisions == 0,
     "%d archive name(s) collapse to the same normalised key, so a loose match "
     .. "is ambiguous: %s", #collisions, table.concat(collisions, ", "))
end
-- A normalised join that matched anything would resolve the var slots and the
-- signposts too, and every one of those would then draw SOMETHING wrong rather
-- than nothing. They must still miss.
local MUST_NOT_RESOLVE = { 101, 102, 116, 95, 96, 100 }
for _, id in ipairs(MUST_NOT_RESOLVE) do
  local name = Gfx.name(id)
  ok(name ~= nil, "Gen4ObjectGfx no longer names id %d", id)
  if name then
    ok(sprites[name] == nil and byNorm[normalise(name)] == nil,
       "id %d (%s) now resolves to a sprite; it is a var slot or a signpost and "
       .. "must not", id, name)
  end
end

section("4. the real hop, through resolveGraphicsVar")
local okO, Overworld = pcall(require, "src.world.OverworldController")
ok(okO, "src.world.OverworldController did not load: %s", tostring(Overworld))
ok(okO and type(Overworld.gen4SpriteFor) == "function",
   "OverworldController does not export gen4SpriteFor, so the join cannot be tested")
if okO and type(Overworld.gen4SpriteFor) == "function" then
  -- The join takes its data as an argument, which is what makes it testable:
  -- `resolveGraphicsVar` reads a module local that only a running overworld
  -- sets. What a map object's var holds is a graphics id, and this is the hop
  -- that turns one into a sheet.
  local data = { gen4_overworld = overworld }
  local function resolve(heldId)
    return (Overworld.gen4SpriteFor(data, heldId))
  end
  -- DAWN, which is the reported fault.
  local dawn = resolve(177)
  ok(dawn == "SPRITE_G4_156",
     "var_0 holding 177 (Dawn with a Poke Ball) resolved to %s, not SPRITE_G4_156",
     tostring(dawn))
  local lucas = resolve(176)
  ok(lucas == "SPRITE_G4_155",
     "var_0 holding 176 (Lucas with a Poke Ball) resolved to %s, not SPRITE_G4_155",
     tostring(lucas))
  -- A CONTROL ON THE SAME PATH: an id that already joined exactly must still
  -- join, and to the same member -- otherwise the normalised map could be
  -- answering everything.
  local plain = resolve(97)
  ok(plain == "SPRITE_G4_091",
     "var_0 holding 97 (plain player_f) resolved to %s, not SPRITE_G4_091",
     tostring(plain))
  -- AND AN UNFILLED SLOT STILL KEEPS ITS PLACEHOLDER. The object comes back
  -- unchanged rather than guessing, which is what stops a wrong character
  -- standing in for Dawn.
  -- AND AN ID WITH NO MEMBER STILL ANSWERS NOTHING, so the caller keeps its
  -- placeholder rather than a wrong character standing in for Dawn.
  ok(resolve(101) == nil,
     "var_0 (a var slot, not a picture) resolved to %s instead of nothing",
     tostring(resolve(101)))
  ok(resolve(57) == nil,
     "dummy_057 resolved to %s instead of nothing", tostring(resolve(57)))
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
