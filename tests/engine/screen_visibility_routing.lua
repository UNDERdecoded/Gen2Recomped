package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/screen_visibility/fixture.lua")
local Cases = dofile("tests/screen_visibility/cases.lua")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Loader = require("src.mods.Loader")
local Game = require("src.core.Game")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e, stack, base, menu, overlay = f.exports, f.stack, f.base, f.menu, f.overlay
    e.hide("BagMenu", true)
    local baseAnimations, menuAnimations = 0, 0
    base.animate = function()
      baseAnimations = baseAnimations + 1
    end
    menu.animate = function()
      menuAnimations = menuAnimations + 1
    end
    stack.states = { base, menu, overlay }
    local polls = e.seen.calls
    stack:update(1 / 60)
    T.eq(baseAnimations, 0, "hidden opaque menu still covers lower simulation animation")
    T.eq(menuAnimations, 1, "hidden covered menu retains native animation")
    T.eq(overlay.updates, 1, "visible overlay retains update ownership")
    T.eq(e.seen.calls, polls, "animation does not invoke render predicate")
    base.animate, menu.animate = nil, nil
    stack.states = { base, menu }
    local key
    menu.onKeyPressed = function(_, value)
      key = value
    end
    f.game:keypressed("screen-contract-key")
    T.eq(key, "screen-contract-key", "hidden menu retains native keyboard dispatch")
    T.eq(e.seen.calls, polls, "keyboard does not invoke render predicate")
    menu.onKeyPressed = nil
    local worldPalettes = 0
    base.sgbWorldZones = function()
      worldPalettes = worldPalettes + 1
      return "world zones"
    end
    local trace, zones, worldZones, clearWorld = f.frame({ base, menu })
    T.same(trace, { "Base" }, "world below hidden opaque menu is drawn")
    T.eq(zones, "Base zones", "hidden menu cannot claim UI palettes")
    T.eq(worldZones, "world zones", "visible world retains separate palettes")
    T.eq(clearWorld, true, "visible world retains transparent UI clear")
    e.hide("Base", true)
    trace, zones, worldZones, clearWorld = f.frame({ base, menu })
    T.same(trace, {}, "all hidden states draw nothing")
    T.eq(zones, nil, "all hidden states claim no UI palette")
    T.eq(worldZones, nil, "hidden world cannot claim world palette")
    T.eq(worldPalettes, 1, "hidden world palette provider is never invoked")
    T.eq(clearWorld, false, "hidden world cannot claim clear ownership")
    e.hide("Base", false)
    -- World-backed battles can extend drawing below the opaque base. Their
    -- fallback search must not select a hidden opaque state as that base.
    local middle = f.state("BagMenu", true)
    local battle = f.state("Battle", false)
    battle.bgMode = function()
      return "world"
    end
    overlay.isOpaque = true
    stack.states = { base, middle, battle, overlay }
    T.eq(Game.drawBaseInStack(stack, 4), 1, "backdrop search skips hidden opaque states")
    e.hide("Battle", true)
    T.eq(Game.drawBaseInStack(stack, 4), 4, "hidden battle does not extend native backdrop")
    e.hide("Battle", false)
    overlay.isOpaque = false
    base.sgbWorldZones = nil
    e.hide("BagMenu", false)
    base.updates, menu.updates, menu.presses, overlay.updates = 0, 0, 0, 0
    Cases.run(f)
    f.close()
  end
end
local bare = Fixture.new(".", "gen2", "red", 3, "unified", true)
local originalCall, calls = Runtime.call, 0
Runtime.call = function(name, ...)
  if name == "screen.render_visible" then
    calls = calls + 1
  end
  return originalCall(name, ...)
end
T.eq(Runtime.wantsHook("screen.render_visible"), false, "no-mod runtime")
T.eq(bare.stack:renderVisible(nil), false, "nil remains hidden without mods")
T.eq(bare.stack:renderVisible(bare.menu), true, "no-mod default true")
T.same(bare.frame({ bare.base, bare.menu }), { "BagMenu" }, "no-mod native main render")
bare.stack:draw()
T.eq(calls, 0, "unsubscribed predicate never dispatches Runtime.call")
Runtime.call = originalCall
bare.close()
local files = {
  ["mods/broken_screen/manifest.json"] = [[{"id":"broken_screen","name":"Broken Screen",
    "version":"1.0.0","api":3,"entry":"main.lua"}]],
  ["mods/broken_screen/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("screen.render_visible", function() return false end)
    error("intentional visibility entry failure")
  ]],
}
local failed = T.sdk.loadMods(
  { "mods/broken_screen" },
  { fs = T.sdk.memfs(files), data = T.fixtures.fresh() }
)
T.check(#failed.errors > 0, "failed entry reported")
T.eq(Runtime.wantsHook("screen.render_visible"), false, "rollback removes hidden-state predicate")
Loader.teardown()
T.eq(Runtime.wantsHook("screen.render_visible"), false, "teardown removes hidden-state predicate")
failed.release()
Version.set(originalVersion)
T.finish("screen.render_visible native routing")
