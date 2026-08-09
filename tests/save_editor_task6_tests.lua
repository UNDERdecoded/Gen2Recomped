-- Headless tests for the save editor's Boxes + Items behaviour.
-- Run from repo root: luajit tests/save_editor_task6_tests.lua
-- (also chained from tests/run_save_editor_tests.lua so CI covers it)
--
-- These drive tools/save-editor/Ops.lua rather than clicking pixel
-- coordinates.  The panels are pure layout now: every rule the old click
-- tests were really asserting (party/box capacity, the money clamp, the bag
-- slot cap, arm-then-confirm on destructive verbs) lives in Ops, so asserting
-- it there means a panel redesign cannot silently invalidate the suite.

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

print("== save editor task 6 tests (Boxes + Items) ==")

local Data = require("src.core.Data")
Data:load()

local Catalog = require("Catalog")
local MonOps = require("MonOps")
local Ops = require("Ops")
local State = require("State")
local SaveData = require("src.core.SaveData")
local BoxesMod = require("src.pokemon.Boxes")
local PartyMod = require("src.pokemon.Party")
local Bag = require("src.inventory.Bag")

local function newState()
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  BoxesMod.ensure(S.save)
  return S
end

-- Boxes ---------------------------------------------------------------

do
  local S = newState()
  local boxes = Ops.boxes(S)

  Ops.boxAdd(S)
  eq(#boxes[1], 1, "boxAdd puts a mon in the current box")
  check(S.dirty, "boxAdd marks the save dirty")
  check(S.status:match("box 1 slot 1") ~= nil, "boxAdd says where the mon landed")
  check(S.editingMon == boxes[1][1], "boxAdd selects the new mon for the inspector")

  Ops.selectBoxSlot(S, 1)
  eq(S.selectedBoxSlot, 1, "selectBoxSlot selects the slot")
  check(S.editingMon == boxes[1][1], "selectBoxSlot points the inspector at the mon")

  -- withdraw moves box -> party
  Ops.withdraw(S)
  eq(#boxes[1], 0, "withdraw empties the box slot")
  eq(#S.save.party, 1, "withdraw appends to the party")
  eq(S.selectedParty, 1, "withdraw selects the withdrawn mon's party slot")

  -- deposit moves party -> box (Boxes.deposit picks the box)
  Ops.deposit(S)
  eq(#S.save.party, 0, "deposit removes the mon from the party")
  eq(#boxes[1], 1, "deposit fills the current box first")
  check(S.status:match("into box 1") ~= nil, "deposit reports the destination box")
end

do
  -- withdraw refuses (and says so) when the party is already full
  local S = newState()
  for _ = 1, PartyMod.MAX do
    table.insert(S.save.party, MonOps.create(Data, S.cat.species[1], 5))
  end
  Ops.boxAdd(S)
  S.dirty = false
  Ops.selectBoxSlot(S, 1)
  local ok = Ops.withdraw(S)
  check(ok == false, "withdraw returns false when the party is full")
  eq(#S.save.party, PartyMod.MAX, "withdraw with a full party leaves the party alone")
  eq(#Ops.boxes(S)[1], 1, "withdraw with a full party leaves the box alone")
  check(S.dirty == false, "a refused withdraw does not dirty the save")
  check(S.status:match("Party is full") ~= nil, "a refused withdraw explains itself")
end

do
  -- release is destructive: first click arms, second commits
  local S = newState()
  Ops.boxAdd(S)
  Ops.selectBoxSlot(S, 1)
  S.dirty = false

  check(Ops.release(S) == false, "release arms on the first call")
  eq(#Ops.boxes(S)[1], 1, "an armed release has not released anything yet")
  eq(Ops.armLabel(S, "box-release", "Release"), "Confirm?",
     "an armed release relabels its button")
  check(Ops.release(S) == true, "release commits on the second call")
  eq(#Ops.boxes(S)[1], 0, "the committed release empties the slot")
  check(S.dirty, "the committed release dirties the save")
  eq(Ops.armLabel(S, "box-release", "Release"), "Release",
     "committing disarms the button label")
end

do
  -- a full box refuses another mon
  local S = newState()
  local box = Ops.boxes(S)[1]
  for _ = 1, BoxesMod.CAPACITY do
    table.insert(box, MonOps.create(Data, S.cat.species[1], 5))
  end
  S.dirty = false
  check(Ops.boxAdd(S) == false, "boxAdd refuses a full box")
  eq(#box, BoxesMod.CAPACITY, "a refused boxAdd adds nothing")
  check(S.status:match("full") ~= nil, "a refused boxAdd explains itself")
end

do
  -- box navigation wraps in both directions and follows the save's currentBox
  local S = newState()
  Ops.stepBox(S, -1)
  eq(S.selectedBox, BoxesMod.COUNT, "stepping back from box 1 wraps to the last box")
  eq(S.save.currentBox, BoxesMod.COUNT, "the save's currentBox follows the selection")
  Ops.stepBox(S, 1)
  eq(S.selectedBox, 1, "stepping forward from the last box wraps to box 1")
end

-- Items ---------------------------------------------------------------

do
  local S = newState()
  S.save.money = 100

  Ops.addMoney(S, 1000)
  eq(S.save.money, 1100, "addMoney adds")
  Ops.addMoney(S, -100000)
  eq(S.save.money, 0, "addMoney clamps at zero")
  Ops.maxMoney(S)
  eq(S.save.money, Ops.MONEY_MAX, "maxMoney tops the wallet out")
  S.dirty = false
  check(Ops.addMoney(S, 1000) == false, "addMoney at the cap is a no-op")
  check(S.dirty == false, "a no-op addMoney does not dirty the save")
end

do
  local S = newState()
  local id = S.cat.items[1]

  Ops.addToBag(S, id)
  eq(S.save.inventory[id], 1, "addToBag adds one")
  Ops.bagAdjust(S, id, 1)
  eq(S.save.inventory[id], 2, "bagAdjust +1 increments")
  Ops.bagAdjust(S, id, -1)
  eq(S.save.inventory[id], 1, "bagAdjust -1 decrements")
  Ops.bagAdjust(S, id, -1)
  eq(S.save.inventory[id], nil, "bagAdjust to zero clears the slot")
  check(S.status:match("Removed the last") ~= nil,
        "emptying a bag slot says so rather than printing x0")

  Ops.addToBag(S, id)
  Ops.bagAdjust(S, id, 1)
  Ops.bagDrop(S, id)
  eq(S.save.inventory[id], nil, "bagDrop removes the whole stack")
  eq(#Bag.order(S.save), 0, "bagDrop removes the bag order entry too")
end

do
  -- the bag has a hard slot cap; the picker must refuse past it
  local S = newState()
  local capacity = Bag.capacity(S.data)
  local added = 0
  for _, id in ipairs(S.cat.items) do
    if not Ops.isBadgeId(id) and Ops.addToBag(S, id) then added = added + 1 end
    if added >= capacity then break end
  end
  eq(Bag.slots(S.save), capacity, "the bag filled to its cap")
  S.dirty = false
  local spare
  for _, id in ipairs(S.cat.items) do
    if not Ops.isBadgeId(id) and not S.save.inventory[id] then spare = id break end
  end
  check(spare ~= nil, "there is an item left over to try to add")
  check(Ops.addToBag(S, spare) == false, "addToBag refuses once the bag is full")
  check(S.dirty == false, "a refused addToBag does not dirty the save")
  check(S.status:match("Bag is full") ~= nil, "a refused addToBag explains itself")
end

do
  -- PC storage is a plain dict with a per-stack cap and no slot limit.
  -- A new game already seeds one item there, so the assertions below track
  -- the delta rather than assuming an empty dict.
  local S = newState()
  local seeded = #Ops.pcOrder(S)
  local id
  for _, candidate in ipairs(S.cat.items) do
    if not Ops.pcItems(S)[candidate] then id = candidate break end
  end
  check(id ~= nil, "found an item not already in PC storage")

  Ops.addToPc(S, id)
  eq(#Ops.pcOrder(S), seeded + 1, "addToPc grows the PC order by one")
  eq(Ops.pcItems(S)[id], 1, "addToPc creates the entry")
  Ops.pcAdjust(S, id, 1)
  eq(Ops.pcItems(S)[id], 2, "pcAdjust +1 increments")
  Ops.pcAdjust(S, id, -2)
  eq(Ops.pcItems(S)[id], nil, "pcAdjust down to zero removes the entry")

  Ops.addToPc(S, id)
  Ops.pcItems(S)[id] = Ops.STACK_MAX
  S.dirty = false
  check(Ops.pcAdjust(S, id, 1) == false, "pcAdjust refuses past the 99 stack cap")
  eq(Ops.pcItems(S)[id], Ops.STACK_MAX, "a refused pcAdjust changes nothing")

  Ops.pcDrop(S, id)
  eq(Ops.pcItems(S)[id], nil, "pcDrop removes the entry")
  eq(#Ops.pcOrder(S), seeded, "pcDrop shrinks the PC order back")
end

do
  -- badges are truthy flags on inventory, toggled not stacked; the engine
  -- writes them as 1 (#515), so the editor must too
  local S = newState()
  local ids = Ops.badgeIds(S)
  check(#ids > 0, "the catalog exposes badge ids")
  local id = ids[1]
  Ops.toggleBadge(S, id)
  eq(S.save.inventory[id], 1, "toggleBadge earns the badge")
  Ops.toggleBadge(S, id)
  eq(S.save.inventory[id], nil, "toggleBadge removes the badge (nil, not false)")
end

print(string.format("save editor task 6 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
