-- Run:  python tools/run_lua_check.py tools/gen4_blackout_check.lua [<cache root>]
--
-- The DS whiteout (src/world/Gen4Blackout.lua) against installed caches:
-- where a blackout sends you, what it says, and which ROM script runs after.
-- <cache root> holds the version folders (default G:/Gen2Recomped); a version
-- whose folder is missing is skipped, not failed.
--
--   HeartGold   Violet's Center (T22PC0101) is a blackout spawn at (8,13), the
--               cell across the counter from the nurse at (8,11), facing up;
--               the house's ground floor (T20R0201 6,8) is the home spawn;
--               the whiteout scripts are std 2013 (M0003/S0EAA, the nurse)
--               and 2012 (M0003/S0E4B, Mom); the loss lines are bank 197
--   Platinum    the same from banks 213 / 368 / 373 (M0211/S103B, S0FCB)
--   Black       Accumula's Center (Z398) at (7,12) facing the nurse at (7,10);
--               the nurse's script is M0854/S0027; loss lines system bank 15

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local root = arg and arg[1] or "G:/Gen2Recomped"
local PASS, FAIL, SKIP = 0, 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. label) end
end

local GameVersion = require("src.core.GameVersion")
local B = require("src.world.Gen4Blackout")

local function load(version, names)
  local dir = root .. "/" .. version .. "/data/generated/"
  local data = {}
  for _, n in ipairs(names) do
    local ok, t = pcall(dofile, dir .. n .. ".lua")
    if not ok then return nil end
    data[n] = t
  end
  return data
end

-- -------------------------------------------------------------- HeartGold --
local hg = load("heartgold", { "field", "text", "map_scripts", "maps" })
if not hg then SKIP = SKIP + 1; print("skip: heartgold") else
  GameVersion.set("heartgold")
  local s = B.spawnFor(hg, "T22PC0101")
  check(s and s.x == 8 and s.y == 13 and s.facing == "up", "HG: Violet's Center is a spawn at (8,13) facing up")
  local nurse
  for _, o in ipairs(hg.maps.T22PC0101.objects or {}) do if o.x == 8 and o.y == 11 then nurse = o end end
  check(nurse ~= nil, "HG: the nurse stands two cells up, across the counter")
  local h = B.spawnFor(hg, "T20R0201")
  check(h and h.home and h.x == 6 and h.y == 8, "HG: the house's ground floor is the home spawn")
  check(B.spawnFor(hg, "T22") == nil, "HG: a town is not a spawn")
  check(B.spawnFor(hg, "T01") == nil, "HG: a fly-only row (blackout half outdoors) is not a spawn")
  check(B.whiteoutLabel(hg, false) == "M0003/S0EAA", "HG: the Center's whiteout script is std 2013")
  check(B.whiteoutLabel(hg, true) == "M0003/S0E4B", "HG: the house's whiteout script is std 2012")
  local lines = B.lossLines(hg, "LYRA", 48, false)
  check(lines and #lines == 4 and lines[1]:find("out of") and lines[2]:find("dropped %$48")
        and lines[4]:find("LYRA blacked out"), "HG: the loss lines are bank 197's, with the money")
  local t = B.lossLines(hg, "LYRA", 48, true)
  check(t and t[2]:find("paid out %$48"), "HG: a trainer loss pays the winner")
  check(B.scurryLine(hg, "LYRA", false):find("^LYRA scurried to"), "HG: the Center line")
  check(B.scurryLine(hg, "LYRA", true):find("^LYRA scurried back\nhome"), "HG: the home line")
  -- the record itself
  local game = { save = { lastHeal = { map = "T20R0201", x = 6, y = 8 } }, data = hg }
  B.noteEntry({ map = { id = "T22PC0101", def = hg.maps.T22PC0101 } }, game)
  check(game.save.lastHeal.map == "T22PC0101" and game.save.lastHeal.y == 13, "HG: entering the Center records it")
  B.noteEntry({ map = { id = "T22", def = hg.maps.T22 } }, game)
  check(game.save.lastHeal.map == "T22PC0101", "HG: walking out keeps it")
end

-- --------------------------------------------------------------- Platinum --
local pt = load("platinum", { "field", "text", "map_scripts" })
if not pt then SKIP = SKIP + 1; print("skip: platinum") else
  GameVersion.set("platinum")
  check(B.whiteoutLabel(pt, false) == "M0211/S103B", "Pt: the Center's whiteout script")
  check(B.whiteoutLabel(pt, true) == "M0211/S0FCB", "Pt: the house's whiteout script")
  local lines = B.lossLines(pt, "LUCAS", 40, false)
  -- the cartridge's language: the English words are asserted on an English
  -- cache; any other language asserts the structure (four lines, the money
  -- and the name in them)
  local english = (pt.text.TEXT_B0213_00043 or ""):find("^First") ~= nil
  if english then
    check(lines and #lines == 4 and lines[2]:find("dropped %$40"), "Pt: the loss lines are bank 368's")
    check(B.scurryLine(pt, "LUCAS", false):find("^LUCAS scurried to"), "Pt: the Center line")
  else
    check(lines and #lines == 4 and lines[2]:find("40") and lines[4]:find("LUCAS"), "Pt (non-English): the loss lines are bank 368's, with the money and the name")
    local sc = B.scurryLine(pt, "LUCAS", false)
    check(sc and sc:find("LUCAS", 1, true), "Pt (non-English): the Center line names the player")
  end
  local n = 0
  for _, row in ipairs(pt.field.healLocations or {}) do
    if row.blackOut and B.spawnFor(pt, row.blackOut.map) then n = n + 1 end
  end
  check(n >= 15, "Pt: the Centers are spawns (" .. n .. ")")
end

-- ------------------------------------------------------------------ Black --
local bw = load("black", { "field", "text", "map_scripts", "maps" })
if not bw then SKIP = SKIP + 1; print("skip: black") else
  GameVersion.set("black")
  local s = B.spawnFor(bw, "Z398")
  check(s and s.x == 7 and s.y == 12 and s.facing == "up", "BW: Accumula's Center is a spawn at (7,12) facing up")
  check(B.spawnFor(bw, "Z390") == nil, "BW: the house is not a Center")
  check(B.whiteoutLabel(bw, false) == "M0854/S0027", "BW: the Center's whiteout script")
  local lines = B.lossLines(bw, "HILBERT", 56, false)
  check(lines and #lines == 3 and lines[1]:find("HILBERT is out of") and lines[2]:find("dropped %$56")
        and lines[3]:find("HILBERT blacked out"), "BW: the loss lines are system bank 15's")
  check(B.scurryLine(bw, "HILBERT", false):find("^HILBERT scurried to"), "BW: the Center line")
  local centers = 0
  for id, def in pairs(bw.maps) do if type(def) == "table" and B.spawnFor(bw, id, def) then centers = centers + 1 end end
  check(centers >= 13, "BW: every Center is a spawn (" .. centers .. ")")
end

print(("%d passed, %d failed, %d skipped"):format(PASS, FAIL, SKIP))
if FAIL > 0 then error("gen4_blackout_check failed") end
