package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = dofile("tests/battle_auxiliary/fixture.lua")
local Version, Auxiliary = require("src.core.GameVersion"), require("src.battle.MenuAuxiliary")
local oldVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = F.new(".", version, mode[1], mode[2])
    local b, game, e = f.battle, f.game, f.exports
    T.eq(e.api:supports("hooks", "battle.menu_auxiliary"), true, version .. " capability")
    T.eq(Auxiliary.ready(b), true, "native command menu ready")
    -- Reach the boundary through actual native queue/drain execution. Merely
    -- constructing an idle menu misses stale insertion and closing markers.
    local during
    b:act(function() during = Auxiliary.ready(b) end)
    b:updateQueue()
    T.eq(during, false, "callback insertion cursor blocks reentrant START")
    T.eq(Auxiliary.ready(b), true, "native callback releases menu boundary")
    b.enemy.mon.hp = b.enemy.mon.hp - 2
    local frames = 0
    while b:stepHPDrain() and frames < 1000 do
      frames = frames + 1
      T.eq(Auxiliary.ready(b), false, "native drain and closing hold block START")
    end
    T.check(frames < 1000, "native HP drain finishes")
    T.eq(Auxiliary.ready(b), true, "completed native drain releases menu boundary")
    f.press(false, true)
    T.eq(e.seen.calls, 0, "no START leaves hook idle")
    T.eq(b.menuIndex, 2, "ordinary native navigation")
    b.menuIndex = 1
    f.press(true, true)
    T.eq(e.seen.calls, 1, "START invokes native hook once")
    T.eq(b.menuIndex, 2, "unclaimed START preserves native navigation")
    T.eq(e.seen.game, game, "opaque native Game")
    T.same(e.seen.context, { kind = "wild" }, "data-only native context")
    e.claim(true)
    b.menuIndex = 1
    f.press(true, true)
    T.eq(b.menuIndex, 1, "claimed input skips native menu navigation")
    for _, row in ipairs({ {}, { value = false }, { value = 0 }, { value = "" }, { value = {} } }) do
      local off = e.api.hooks:wrap("battle.menu_auxiliary", function()
        return row.value
      end, 100)
      b.menuIndex = 1
      f.press(true, true)
      T.eq(b.menuIndex, 2, "only literal true claims START")
      off()
    end
    for _, after in ipairs({ false, true }) do
      local off = e.api.hooks:wrap("battle.menu_auxiliary", function(next)
        if after then
          next()
        end
        error("intentional auxiliary failure")
      end, 100)
      b.menuIndex = 1
      local calls = e.seen.calls
      f.press(true, true)
      T.eq(b.menuIndex, 1, "wrapper failure preserves downstream claim")
      T.eq(e.seen.calls, calls + 1, "failure does not repeat downstream")
      off()
    end
    -- Presentation is caught up during native update; an unsettled frame must
    -- not turn into an eligible START action halfway through that same update.
    local calls = e.seen.calls
    b.player.shownHP = b.player.mon.hp - 1
    b.menuIndex = 1
    f.press(true, true)
    T.eq(e.seen.calls, calls, "unsettled HP rejected before catch-up")
    T.eq(b.menuIndex, 2, "native catch-up/navigation still runs")
    b.menuIndex = 1
    f.press(true, true)
    T.eq(e.seen.calls, calls + 1, "fresh START after settling works")
    local bad = {
      { owner = b, key = "kind", value = "link" },
      { owner = b, key = "safari", value = {} },
      { owner = b, key = "pokedudeDemo", value = true },
      { owner = b, key = "palace", value = true },
      { owner = b, key = "phase", value = "moveSelect" },
      { owner = b, key = "queue", value = { {} } },
      { owner = b, key = "pendingActions", value = { [0] = { kind = "move" } } },
      { owner = b, key = "animPlaying", value = true },
      { owner = b, key = "waitFrames", value = 1 },
      { owner = b, key = "introSlide", value = 1 },
      { owner = b, key = "waitingUI", value = true },
      { owner = b.player, key = "mustRecharge", value = true },
      { owner = b.player, key = "shownStatus", value = "PSN" },
      { owner = b.player, key = "drainFloor", value = 0 },
      { owner = game.stack, key = "states", value = { b, {} } },
    }
    for _, change in ipairs(bad) do
      local old = change.owner[change.key]
      change.owner[change.key] = change.value
      T.eq(Auxiliary.ready(b), false, "unsafe " .. change.key)
      game.input.pressed = { start = true }
      T.eq(Auxiliary.request(b), nil, "unsafe START does not allocate request")
      change.owner[change.key] = old
    end
    game.input.pressed = { start = true }
    local token = assert(Auxiliary.request(b))
    calls = e.seen.calls
    game.sessionStartedAt = 2
    T.eq(Auxiliary.dispatch(b, token), true, "retired session input consumed")
    T.eq(e.seen.calls, calls, "retired session never dispatches hook")
    game.sessionStartedAt = 1
    -- Even a faulty wrapper that opens an overlay and returns false cannot
    -- feed that same input through the old native menu.
    local overlay = {}
    local off = e.api.hooks:wrap("battle.menu_auxiliary", function()
      game.stack.states = { b, overlay }
      return false
    end, 100)
    b.menuIndex = 1
    f.press(true, true)
    T.eq(game.stack:top(), overlay, "custom overlay stays on stack")
    T.eq(b.menuIndex, 1, "overlay invalidation prevents stale native fallthrough")
    off()
    game.stack.states = { b }
    e.stop()
    e.stop()
    calls = e.seen.calls
    b.menuIndex = 1
    f.press(true, true)
    T.eq(e.seen.calls, calls, "unsubscribe is idempotent")
    T.eq(b.menuIndex, 2, "unsubscribe restores native menu")
    local player, enemy = b.player, b.enemy
    b.double = true
    b:placeBattler(2, player)
    b:placeBattler(0, nil)
    b.choosingSlot = 2
    T.eq(Auxiliary.ready(b), true, "double partner can own an otherwise empty player side")
    b:placeBattler(1, nil)
    T.eq(Auxiliary.ready(b), false, "no live opponent cannot open an auxiliary menu")
    b:placeBattler(1, enemy)
    T.eq(Auxiliary.ready(b), true, "restored opponent returns to a live decision")
    f.close()
    local unreadable = setmetatable({}, {
      __index = function()
        error("no-hook path touched battle")
      end,
    })
    T.eq(Auxiliary.request(unreadable), nil, "no-mod hot path skips native traversal")
  end
end
Version.set(oldVersion)
T.finish("portable battle.menu_auxiliary native dispatch")
