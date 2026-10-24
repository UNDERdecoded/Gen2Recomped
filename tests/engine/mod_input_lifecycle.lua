package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/mod_input/fixture.lua")
local Control = require("src.mods.InputControl")
local Input = require("src.core.Input")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Game = require("src.core.Game")
local Touch = require("src.core.TouchControls")
local savedVersion = Version.get()
Touch:init()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local label = version .. "/" .. mode[1] .. "/" .. mode[2] .. ": "
    f.ready()
    local own, peer, g = f.primary, f.peer, f.game
    setmetatable(g, { __index = Game })
    for _, recover in ipairs({
      function()
        g:focus(false)
      end,
      function()
        g:focus(true)
      end,
      function()
        g:visible(false)
      end,
      function()
        g:visible(true)
      end,
      function()
        g:joystickremoved(nil)
      end,
      function()
        Input:init()
      end,
    }) do
      local token = own.press("up")
      Input:step()
      recover()
      T.eq(Input:isDown("up"), false, label .. "native recovery clears hold")
      T.eq(own.release(token), false, label .. "native recovery retires token")
      local fresh = own.press("up")
      T.eq(own.release(token), false, label .. "old token cannot affect resumed input")
      T.eq(Input:isDown("up"), true, label .. "new input remains held")
      T.eq(own.release(fresh), true, label .. "API remains usable after recovery")
    end
    local api = f.result.loader.apis.portable_mod_input
    local seen = 0
    for _, name in ipairs({ "input.key", "input.gamepad", "input.wheel" }) do
      api.hooks:wrap(name, function(next, ...)
        seen = seen + 1
        return next(...)
      end)
    end
    own.tap("a")
    local token = own.press("b")
    own.release(token)
    T.eq(seen, 0, label .. "logical input bypasses raw hooks/hotkeys")
    g:keypressed("up")
    g:keyreleased("up")
    T.eq(seen, 2, label .. "physical input still dispatches raw hooks")
    -- Logical input can be used within a raw hook without recursion.
    local held
    local off = api.hooks:wrap("input.key", function(_, game, event)
      if event.phase == "pressed" then
        held = own.input:press(game, "a")
      end
    end, 100)
    g:keypressed("up")
    T.eq(Input:isDown("up"), false, label .. "raw hook can suppress original action")
    T.eq(Input:isDown("a"), true, label .. "raw hook can request logical action")
    T.eq(own.release(held), true, label .. "logical hold from hook releases")
    off()
    -- Replacing a mod's handle retires the old one without touching peers.
    token = own.press("select")
    local peerToken = peer.press("select")
    local fresh = f.result.loader.inputControl:api("portable_mod_input")
    T.eq(own.release(token), false, label .. "replaced API retires old token")
    T.eq(Input:isDown("select"), true, label .. "replacement preserves peer")
    T.raises(function()
      own.press("a")
    end, "no longer active", label .. "old API cannot press again")
    token = fresh:press(g, "select")
    peer.release(peerToken)
    T.eq(Input:isDown("select"), true, label .. "new handle owns independent source")
    T.eq(fresh:release(token), true, label .. "new handle releases normally")
    f.close()
    f.result.loader:_closeModInput()
  end
end
-- A reset retires tokens for that Input instance only.
Input:init()
local other = setmetatable({}, { __index = Input })
other:init()
local control = Control.new()
local api = control:api("isolation")
local a = api:press({ input = Input }, "a")
local b = api:press({ input = other }, "a")
Input:reset()
T.eq(api:release(a), false, "reset retires matching Input token")
T.eq(other:isDown("a"), true, "another Input instance remains held")
T.eq(api:release(b), true, "another Input instance's token remains valid")
control:close()
-- Two sessions with the same mod ID still own different sources.
local one, two = Control.new(), Control.new()
local x, y = one:api("same_id"), two:api("same_id")
a = x:press({ input = Input }, "b")
b = y:press({ input = Input }, "b")
one:close()
T.eq(x:release(a), false, "closed session token retired")
T.eq(Input:isDown("b"), true, "closing old session preserves replacement source")
T.eq(y:release(b), true, "replacement session releases normally")
two:close()
-- A failed entry is cleaned through the real loader's rollback path.
Input:init()
local capture = { game = { input = Input } }
_G.MOD_INPUT_ROLLBACK_FIXTURE = capture
local files = {}
local Json = require("src.link.Json")
for _, id in ipairs({ "aaa_input_peer", "broken_input" }) do
  files["mods/" .. id .. "/manifest.json"] = Json.encode({
    id = id,
    name = id,
    version = "1.0.0",
    api = 3,
    games = { "all" },
    generations = { 1, 2, 3, 4, 5 },
    entry = "main.lua",
  })
end
files["mods/aaa_input_peer/main.lua"] = [[
  local mod = ...
  local f = MOD_INPUT_ROLLBACK_FIXTURE
  f.peer, f.peerToken = mod.input, mod.input:press(f.game, "b")
]]
files["mods/broken_input/main.lua"] = [[
  local mod = ...
  local f = MOD_INPUT_ROLLBACK_FIXTURE
  f.broken, f.brokenToken = mod.input, mod.input:press(f.game, "b")
  f.brokenSelect = mod.input:press(f.game, "select")
  error("intentional mod.input rollback")
]]
local failed = T.sdk.loadMods({ "mods/aaa_input_peer", "mods/broken_input" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs(files),
  dev = false,
})
_G.MOD_INPUT_ROLLBACK_FIXTURE = nil
T.check(#failed.errors > 0, "failed input entry reported")
T.eq(Input:isDown("select"), false, "failed entry releases its exclusive hold")
T.eq(Input:isDown("b"), true, "failed entry preserves successful peer hold")
T.eq(capture.broken:release(capture.brokenToken), false, "rollback retires failed token")
T.eq(capture.peer:release(capture.peerToken), true, "peer still owns its token")
T.raises(function()
  capture.broken:press(capture.game, "a")
end, "no longer active", "rolled-back API retired")
failed.loader:_closeModInput()
failed.release()
-- Native hot reload closes the old service before building replacement mods.
local f = Fixture.new(".", "gen2", "red", 3, "unified")
f.ready()
a = f.primary.press("a")
f.game.data = T.fixtures.fresh()
rawset(f.game.data, "reloadGenerated", function() end)
local replacement = require("src.dev.HotReload").run(f.game, { fs = T.sdk.memfs({}), dev = false })
T.eq(#replacement.errors, 0, "ROM-free hot reload succeeds")
T.eq(Input:isDown("a"), false, "hot reload releases old holds")
T.eq(f.primary.release(a), false, "hot reload retires old token")
T.raises(function()
  f.primary.press("a")
end, "no longer active", "old service cannot press after reload")
f.close()
-- Native teardown retires all handles, including holds whose caller lost
-- its token/loader references. Outstanding sources must survive GC to cleanup.
Input:init()
Input:keypressed("z")
do
  local orphan = Control.new():api("orphan")
  orphan:press({ input = Input }, "b")
end
collectgarbage("collect")
Loader.teardown()
T.eq(Input:isDown("b"), false, "teardown releases orphaned mod hold after GC")
T.eq(Input:isDown("a"), true, "teardown preserves keyboard source")
Input:keyreleased("z")
Input:reset()
Version.set(savedVersion)
T.finish("mod.input lifecycle")
