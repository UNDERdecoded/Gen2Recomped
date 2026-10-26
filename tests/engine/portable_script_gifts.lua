package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_gifts")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
local function tick(f, key)
  f.game.input.wasPressed = function(_, button)
    return button == key
  end
  f.loader.hooks:call("input.step", function() end, f.game, 1 / 60)
  f.game.stack:update(1 / 60)
  f.game.input.wasPressed = function()
    return false
  end
end
local function close(f)
  for _ = 1, 2000 do
    if f.exports.result().done > 0 then
      return
    end
    tick(f, "a")
  end
  error("gift UI did not close")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared gift contract: " .. tostring(why))
end
for _, rows in ipairs({
  { { "give_item", "POTION", 1, false }, { "give_pokemon", "UNKNOWN", 5, true, false } },
  { { "give_item", "POTION", 0 } },
  { { "give_item", "POTION", 1000 } },
  { { "give_item", "POTION", 1, true } },
  { { "give_item", "POTION", 1, "\255" } },
  { { "give_pokemon", "MEW", 0 } },
  { { "give_pokemon", "MEW", 101 } },
  { { "give_pokemon", "MEW", 5, "yes" } },
  { { "give_pokemon", "MEW", 5, true, "text" } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid gift list refused")
  T.eq(f.quantity(), 3, "gift prefix does not write inventory")
  T.eq(#f.game.save.party, 1, "gift prefix does not create party mon")
  T.eq(f.exports.result().done, 0, "refusal has no completion")
end
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  T.check(
    f.exports.queue({ { "give_item", "POTION", 1, "RECEIVED POTION!" }, { "set_flag", "mod:after" } }),
    "native receipt admitted"
  )
  T.eq(f.quantity(), 4, "native bag already contains received item")
  T.eq(f.exports.result().done, 0, "script waits for native receipt")
  close(f)
  T.eq(f.exports.result().success, true, "receipt completes native script")
  T.eq(f.exports.get("mod:after"), true, "next command runs after receipt only")
  T.eq(f.game.stack:top(), f.ow, "owned receipt removed")
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "give_pokemon", "MEW", 5, true, true }, { "set_flag", "mod:after" } }),
    "native mon receipt admitted"
  )
  T.eq(#f.game.save.party, 2, "native mon gift created once")
  T.eq(f.exports.result().done, 0, "native mon receipt waits")
  close(f)
  T.eq(f.exports.result().success, true, "native mon receipt complete")
  T.eq(f.exports.get("mod:after"), true, "mon gift resumes script")
end
do
  local f = fixture()
  f.game.save.inventory.POTION = 99
  T.check(
    f.exports.queue({ { "give_item", "POTION", 1, false, "BAG IS FULL!" }, { "set_flag", "mod:burned" } }),
    "full bag admitted for native refusal UI"
  )
  T.eq(f.quantity(), 99, "full bag adds nothing")
  T.eq(f.exports.result().done, 0, "bag full message awaited")
  close(f)
  T.eq(f.exports.result().success, true, "native full bag halts cleanly")
  T.eq(f.exports.get("mod:burned"), false, "full bag cannot burn later gift flag")
end
for _, action in ipairs({ "rollback", "teardown", "save" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(
    f.exports.queue({ { "give_item", "POTION", 1, "RECEIVED!" }, { "set_flag", "mod:after" } }),
    "receipt before " .. action
  )
  local box = f.game.stack:top()
  local overlay = { update = function() end }
  f.game.stack:push(overlay)
  if action == "rollback" then
    f.loader:_rollback("script_gifts")
  elseif action == "teardown" then
    Loader.teardown()
  else
    f.game.save = {}
    tick(f)
  end
  T.eq(f.game.stack:top(), overlay, "foreign overlay retained")
  T.eq(#f.game.stack.states, 2, "only owned receipt removed")
  T.eq(f.ow.runner, original, "native original runner restored")
  T.eq(f.exports.result().done, 1, "cancelled receipt completes once")
  T.eq(f.exports.result().success, false, "cancelled receipt reports failure")
  box.onDone()
  T.eq(f.exports.result().done, 1, "retained native callback cannot replay cancellation")
  T.eq(f.game.stack:top(), overlay, "retained native callback preserves foreign overlay")
end
for _, field in ipairs({ "player", "party", "pokedex", "boxes", "boxNames", "currentBox" }) do
  local f = fixture()
  f.game.save[field] = false
  T.eq(
    f.exports.queue({ { "give_item", "POTION", 1, false }, { "give_pokemon", "MEW", 5, true, false } }),
    nil,
    "malformed " .. field .. " preflight"
  )
  T.eq(f.quantity(), 3, "malformed gift destination prevents prefix")
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "give_pokemon", "MEW", 5, false, false }, { "wait", 5 }, { "set_flag", "mod:after" } }),
    "native nickname flow admitted"
  )
  local question = f.game.stack:top()
  local Choice = require("src.ui.ChoiceBox")
  for _ = 1, 2000 do
    if getmetatable(f.game.stack:top()) == Choice then
      break
    end
    tick(f, "a")
  end
  T.eq(getmetatable(f.game.stack:top()), Choice, "native question opens native choice")
  tick(f, "a")
  for _ = 1, 40 do
    tick(f)
  end
  local naming = f.game.stack:top()
  T.check(
    naming ~= f.ow and naming ~= question and getmetatable(naming) ~= Choice,
    "native naming screen opened"
  )
  T.eq(type(naming.onDone), "function", "native naming completion exists")
  question.onDone()
  question.choice(false)
  T.eq(f.game.stack:top(), naming, "old question callbacks cannot bypass naming")
  T.eq(f.exports.result().done, 0, "old question cannot complete gift")
  f.game.stack:pop()
  naming.onDone("SCOUT")
  naming.onDone("REPLAY")
  T.eq(f.game.save.party[2].nickname, "SCOUT", "native naming callback commits once")
  T.eq(f.exports.result().done, 0, "stale callback cannot skip later wait")
  for _ = 1, 5 do
    tick(f)
  end
  T.eq(f.exports.get("mod:after"), true, "native nickname flow resumes normally")
end
do
  local f = fixture()
  for i = 2, 6 do
    f.game.save.party[i] = require("src.mods.Merge").deepCopy(f.game.save.party[1])
  end
  T.check(
    f.exports.queue({ { "give_pokemon", "MEW", 5, true, false }, { "set_flag", "mod:boxed" } }),
    "native box gift admitted"
  )
  T.eq(#f.game.save.party, 6, "full party retained")
  T.check(f.game.save.boxes[1][1], "actual native box receives gift")
  T.eq(f.exports.result().done, 0, "native sent-to-box message awaited")
  close(f)
  T.eq(f.exports.get("mod:boxed"), true, "box message resumes script")
end
do
  local f = fixture()
  local party = f.game.save.party
  f.game.mods = { events = f.loader.events }
  f.loader.events:on("pokemon.before_give", function()
    f.loader:_rollback("script_gifts")
  end, 0, "probe")
  T.check(
    f.exports.queue({ { "give_pokemon", "MEW", 5, true, false } }),
    "gift admission reaches native hook"
  )
  T.eq(#party, 1, "owner retired in before_give cannot construct a gift")
  T.eq(f.exports.result().done, 1, "mid-construction cancellation completes once")
  T.eq(f.exports.result().success, false, "mid-construction cancellation reported")
  T.eq(f.game.stack:top(), f.ow, "cancelled native gift opens no late UI")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script gifts")
