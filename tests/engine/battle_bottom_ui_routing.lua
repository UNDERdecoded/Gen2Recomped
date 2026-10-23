package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/battle_bottom_ui/fixture.lua")
local Cases = dofile("tests/battle_bottom_ui/cases.lua")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Loader = require("src.mods.Loader")
local Battle = require("src.battle.BattleState")
local TextBox = require("src.render.TextBox")
local Font = require("src.render.Font")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e, b, g, stack = f.exports, f.battle, f.game, f.stack
    T.eq(b.isBattleState, true, "real Gen2 prototype supplies battle classification")
    T.eq(rawget(b, "isBattle"), nil, "inheritance does not rely on a fabricated isBattle marker")
    local anchors = 0
    g.renderer = {
      setUIAnchor = function()
        anchors = anchors + 1
      end,
    }
    local text, choice = f.textBox(), f.choiceBox()
    stack.states = { b, text, choice }
    e.hide(true)
    f.counters.ink = 0
    text:draw()
    choice:draw()
    T.eq(f.counters.ink, 0, "hidden battle suppresses actual text/choice backings and glyphs")
    T.eq(anchors, 0, "hidden overlays do not leave a render anchor")
    T.eq(e.seen.state, b, "inherited overlay decision queries native enclosing battle")
    e.hide(false)
    text:draw()
    choice:draw()
    T.check(f.counters.ink > 0, "unhidden actual text/choice draws again")
    T.check(anchors > 0, "unhidden text resumes native anchoring")
    -- A field choice has no battle owner and must never become a hook state.
    stack.states = { text, choice }
    local polls = e.seen.calls
    f.counters.ink = 0
    e.hide(true)
    choice:draw()
    T.check(f.counters.ink > 0, "field choice remains visible under an active bottom predicate")
    T.eq(e.seen.calls, polls, "field choice does not query battle hook")
    text:draw()
    T.eq(e.seen.state, text, "field text retains its individual predicate contract")
    -- A battle above a text state is not its owner.
    stack.states = { text, b, choice }
    e.hide(false)
    local off = f.public.hooks:wrap("battle.bottom_ui_visible", function(next, state)
      if state == b then
        return false
      end
      return next(state)
    end, 100)
    T.eq(
      require("src.battle.UIVisibility").bottomVisible(text, true),
      true,
      "battle above a text state is not inherited"
    )
    off()
    -- Native hidden YES/NO input still completes its own delayed callback.
    local answer
    choice = f.choiceBox(function(value)
      answer = value
    end)
    stack.states = { b, text, choice }
    e.hide(true)
    f.input:keypressed("z")
    f.input:step()
    polls = e.seen.calls
    stack:update(1 / 60)
    f.input:keyreleased("z")
    f.input:step()
    for _ = 1, 40 do
      if stack:top() == choice then
        stack:update(1 / 60)
      end
    end
    T.eq(answer, true, "hidden native YES/NO confirms through real input and hold frames")
    T.eq(stack:top(), text, "hidden choice pops exactly itself")
    T.eq(e.seen.calls, polls, "native choice update never queries rendering predicate")
    -- Hidden typewriter text remains a live native foreground state.
    text = f.textBox()
    stack.states = { b, text }
    local chars = text.charIndex or 0
    polls = e.seen.calls
    for _ = 1, 60 do
      stack:update(1 / 60)
    end
    T.check((text.charIndex or 0) > chars or text.done, "hidden native text continues typing")
    T.eq(e.seen.calls, polls, "native typewriter update never queries draw predicate")
    -- No menu-row scissor may remain after the corresponding UI is hidden.
    local clips = 0
    f.patch(love.graphics, "getScissor", function()
      return nil
    end)
    f.patch(love.graphics, "intersectScissor", function()
      clips = clips + 1
    end)
    for _, phase in ipairs({ "moveSelect", "mimicSelect" }) do
      b.phase = phase
      local before = clips
      e.hide(false)
      b:drawPicsLayer(0, 0, 0)
      T.eq(clips, before + 1, "visible native move menu clips its rows")
      before = clips
      e.hide(true)
      b:drawPicsLayer(0, 0, 0)
      T.eq(clips, before, "hidden native move menu removes its own clip")
      e.hide(false)
      b:drawPicsLayer(0, 0, 0, nil, true)
      T.eq(clips, before, "explicit skipMenuClip retains native behavior")
    end
    b.phase = "contract"
    e.hide(false)
    Cases.run(f)
    f.close()
  end
end
local bare = Fixture.new(".", "gen2", "red", 3, "unified", true)
local originalCall, calls = Runtime.call, 0
Runtime.call = function(name, ...)
  if name == "battle.bottom_ui_visible" then
    calls = calls + 1
  end
  return originalCall(name, ...)
end
T.eq(Runtime.wantsHook("battle.bottom_ui_visible"), false, "no-mod runtime")
T.eq(bare.visible(), true, "no-mod default")
T.eq(bare.draw(), true, "no-mod actual bottom draw")
T.eq(calls, 0, "unsubscribed path never dispatches Runtime.call")
Runtime.call = originalCall
bare.close()
-- Preserve the pre-existing private claim API while adding the public hook.
local legacy = Fixture.new(".", "gen2", "red", 3, "unified")
local Visibility = require("src.battle.UIVisibility")
Visibility.reset()
T.eq(Visibility.claimBottom(nil, function() end), false, "nil legacy owner rejected")
T.eq(Visibility.claimBottom("bad", false), false, "non-callable legacy claim rejected")
local queried, queryKind
T.eq(
  Visibility.claimBottom("legacy_owner", function(state, isTextBox)
    queried, queryKind = state, isTextBox
    return false
  end),
  true,
  "legacy claim accepted"
)
local polls = legacy.exports.seen.calls
T.eq(legacy.visible(), false, "legacy denial wins over public default true")
T.eq(legacy.exports.seen.calls, polls, "legacy denial bypasses hook")
T.eq(queried, legacy.battle, "legacy claim receives original state")
T.eq(queryKind, true, "legacy predicate receives original kind flag")
T.same(Visibility.bottomClaimants(), { "legacy_owner" }, "claimant introspection preserved")
local owners = Visibility.bottomClaimants()
owners[1] = "changed"
T.same(Visibility.bottomClaimants(), { "legacy_owner" }, "claimant result is detached")
T.eq(
  Visibility.claimBottom("legacy_owner", function()
    return true
  end),
  true,
  "legacy owner replacement"
)
legacy.exports.hide(true)
T.eq(legacy.visible(), false, "public hook may still hide after legacy approval")
legacy.exports.hide(false)
T.eq(legacy.visible(), true, "both layers must allow drawing")
T.eq(Visibility.releaseBottom("legacy_owner"), true, "legacy release reports removed owner")
T.eq(Visibility.releaseBottom("legacy_owner"), false, "legacy release is idempotent")
Visibility.claimBottom("throwing", function()
  error("intentional legacy claim failure")
end)
T.eq(legacy.visible(), true, "throwing legacy claim fails open")
T.same(Visibility.bottomClaimants(), {}, "throwing legacy claim is retired")
Visibility.claimBottom("reset_me", function()
  return false
end)
Visibility.reset()
T.eq(legacy.visible(), true, "legacy reset restores ordinary visibility")
legacy.close()
local files = {
  ["mods/broken_bottom/manifest.json"] = [[{"id":"broken_bottom","name":"Broken Bottom",
    "version":"1.0.0","api":3,"entry":"main.lua"}]],
  ["mods/broken_bottom/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("battle.bottom_ui_visible", function() return false end)
    error("intentional bottom entry failure")
  ]],
}
local failed = T.sdk.loadMods(
  { "mods/broken_bottom" },
  { fs = T.sdk.memfs(files), data = T.fixtures.fresh() }
)
T.check(#failed.errors > 0, "failed entry is reported")
T.eq(Runtime.wantsHook("battle.bottom_ui_visible"), false, "entry rollback removes predicate")
Loader.teardown()
T.eq(Runtime.wantsHook("battle.bottom_ui_visible"), false, "teardown removes predicate")
failed.release()
Version.set(originalVersion)
T.finish("battle.bottom_ui_visible native routing")
