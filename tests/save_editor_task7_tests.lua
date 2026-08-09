-- Headless tests for the save editor's Events + Dex behaviour.
-- Run from repo root: luajit tests/save_editor_task7_tests.lua
-- (also chained from tests/run_save_editor_tests.lua so CI covers it)
--
-- Driven through tools/save-editor/Ops.lua rather than by clicking pixel
-- coordinates: the rules worth protecting here are the save-shape ones
-- (flags write true/nil, object toggles write true/false, owning implies
-- seen, un-seeing clears owned, wholesale clears arm before they commit),
-- and those all live in Ops.

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love_stub

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

print("== save editor task 7 tests (Events + Dex) ==")

local Ops = require("Ops")
local State = require("State")

local function newState()
  local S = State.new()
  S.events = { "EVENT_ALPHA", "EVENT_BEAT_BROCK", "EVENT_ZETA" }
  S.cat = { species = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIKACHU" },
            items = {}, moves = {} }
  S.save = {
    flags = {}, defeatedTrainers = {}, itemsTaken = {}, objectToggles = {},
    party = {}, boxes = {},
  }
  return S
end

-- Events --------------------------------------------------------------

do
  local S = newState()

  Ops.setFlag(S, "EVENT_ALPHA", true)
  eq(S.save.flags.EVENT_ALPHA, true, "setFlag on writes true")
  check(S.dirty, "setFlag dirties the save")
  check(S.status:match("EVENT_ALPHA") ~= nil, "setFlag names the flag it changed")

  Ops.setFlag(S, "EVENT_ALPHA", false)
  eq(S.save.flags.EVENT_ALPHA, nil,
     "setFlag off writes nil, not false (a false flag would still serialize)")
end

do
  local S = newState()

  Ops.setKey(S, "defeatedTrainers", "PEWTER_GYM_obj_1", true)
  eq(S.save.defeatedTrainers.PEWTER_GYM_obj_1, true, "setKey marks a trainer beaten")
  Ops.setKey(S, "defeatedTrainers", "PEWTER_GYM_obj_1", false)
  eq(S.save.defeatedTrainers.PEWTER_GYM_obj_1, nil, "setKey off clears the entry")

  Ops.setKey(S, "itemsTaken", "VIRIDIAN_FOREST_obj_3", true)
  eq(S.save.itemsTaken.VIRIDIAN_FOREST_obj_3, true, "setKey works for itemsTaken too")

  -- setKey creates the table when a save predates it
  S.save.newTable = nil
  Ops.setKey(S, "newTable", "k", true)
  eq(S.save.newTable.k, true, "setKey creates a missing table")
end

do
  -- object toggles are an explicit true/false override, NOT presence/absence:
  -- false means "this object is hidden", which is different from "no override"
  local S = newState()
  Ops.setToggle(S, "CELADON_CITY", "gym_guide", true)
  eq(S.save.objectToggles.CELADON_CITY.gym_guide, true, "setToggle on writes true")
  Ops.setToggle(S, "CELADON_CITY", "gym_guide", false)
  eq(S.save.objectToggles.CELADON_CITY.gym_guide, false,
     "setToggle off writes false, not nil")
end

do
  -- clearing a whole key table is destructive: arm, then commit
  local S = newState()
  S.save.defeatedTrainers = { a = true, b = true, c = true }
  S.dirty = false

  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == false,
        "clearTable arms on the first call")
  eq(count(S.save.defeatedTrainers), 3, "an armed clear has not cleared anything")
  check(S.status:match("Clear all 3") ~= nil, "the arming message counts the entries")
  eq(Ops.armLabel(S, "clear-defeatedTrainers", "Clear all trainers"), "Confirm?",
     "an armed clear relabels its button")

  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == true,
        "clearTable commits on the second call")
  eq(count(S.save.defeatedTrainers), 0, "the committed clear empties the table")
  check(S.dirty, "the committed clear dirties the save")

  S.dirty = false
  check(Ops.clearTable(S, "defeatedTrainers", "trainers") == false,
        "clearing an already-empty table is a no-op")
  check(S.dirty == false, "a no-op clear does not dirty the save")
  check(S.status:match("already empty") ~= nil, "a no-op clear explains itself")
end

-- Dex -----------------------------------------------------------------

do
  local S = newState()
  local dex = Ops.dex(S)
  check(type(dex.seen) == "table" and type(dex.owned) == "table",
        "Ops.dex creates the seen/owned tables")

  Ops.dexSeen(S, "BULBASAUR", true)
  eq(dex.seen.BULBASAUR, true, "dexSeen marks seen")
  eq(dex.owned.BULBASAUR, nil, "seeing alone does not own")

  Ops.dexOwned(S, "CHARMANDER", true)
  eq(dex.owned.CHARMANDER, true, "dexOwned marks owned")
  eq(dex.seen.CHARMANDER, true, "owning implies having seen")

  Ops.dexSeen(S, "CHARMANDER", false)
  eq(dex.seen.CHARMANDER, nil, "un-seeing clears seen")
  eq(dex.owned.CHARMANDER, nil, "un-seeing also clears owned (can't own the unseen)")
end

do
  local S = newState()
  local seen, owned, total = Ops.dexCounts(S)
  eq(seen, 0, "a fresh dex has seen nothing")
  eq(owned, 0, "a fresh dex owns nothing")
  eq(total, #S.cat.species, "dexCounts reports the catalog size")

  Ops.dexSeeAll(S)
  seen, owned = Ops.dexCounts(S)
  eq(seen, #S.cat.species, "dexSeeAll marks every species seen")
  eq(owned, 0, "dexSeeAll does not own anything")

  Ops.dexOwnAll(S)
  seen, owned = Ops.dexCounts(S)
  eq(owned, #S.cat.species, "dexOwnAll marks every species owned")
  eq(seen, #S.cat.species, "dexOwnAll leaves everything seen too")
end

do
  -- stamping from the save's own mons, party and boxes both
  local S = newState()
  S.save.party = { { species = "PIKACHU" } }
  S.save.boxes = { { { species = "SQUIRTLE" } } }

  Ops.dexStamp(S)
  local dex = Ops.dex(S)
  eq(dex.owned.PIKACHU, true, "dexStamp owns party mons")
  eq(dex.owned.SQUIRTLE, true, "dexStamp owns box mons")
  eq(dex.seen.PIKACHU, true, "dexStamp marks stamped mons seen")
  check(S.status:match("2 more") ~= nil, "dexStamp reports how many it added")

  S.dirty = false
  check(Ops.dexStamp(S) == false, "a second dexStamp with nothing new is a no-op")
  check(S.dirty == false, "a no-op dexStamp does not dirty the save")
end

do
  -- wiping the dex is destructive: arm, then commit
  local S = newState()
  Ops.dexOwnAll(S)
  S.dirty = false

  check(Ops.dexClear(S) == false, "dexClear arms on the first call")
  local _, owned = Ops.dexCounts(S)
  eq(owned, #S.cat.species, "an armed dexClear has not wiped anything")
  eq(Ops.armLabel(S, "dex-clear", "Wipe dex"), "Confirm?",
     "an armed dexClear relabels its button")

  check(Ops.dexClear(S) == true, "dexClear commits on the second call")
  local seen2, owned2 = Ops.dexCounts(S)
  eq(seen2, 0, "the committed dexClear clears seen")
  eq(owned2, 0, "the committed dexClear clears owned")
  check(S.dirty, "the committed dexClear dirties the save")
end

do
  -- doing anything else disarms a pending confirmation: an unrelated click
  -- must never become the second half of a destructive one
  local S = newState()
  Ops.dexOwnAll(S)
  Ops.dexClear(S)
  eq(S.armed, "dex-clear", "dexClear left the button armed")
  Ops.dexSeen(S, "PIKACHU", true)
  eq(S.armed, nil, "an unrelated mutation disarms the pending confirmation")
  local _, owned = Ops.dexCounts(S)
  check(owned > 0, "the dex was not wiped by the unrelated click")
end

print(string.format("save editor task 7 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
