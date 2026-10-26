-- Real public Loader facade and native keyboard controller; no admission or
-- dispatch helper is replaced by the test.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/choice_band.lua").fixture(".", "gen2", version)
  local api = f.e.api.battle
  local function fresh()
    local b = f.field(false)
    f.game.stack.states = { b }
    b.introSlide, b.moveIndex = 0, 2
    f.hold(b.player, 186)
    b.player.choicedMove = 33
    return b
  end
  local function submit(id, slot)
    local snapshot = assert(api:snapshot())
    return api:submit({ id = id, revision = snapshot.revision, kind = "move", slot = slot })
  end
  for _, kind in ipairs({ "physical", "metadata_cleared", "effect_only", "empty_override", "suppressed" }) do
    local b, reads, draws = fresh(), 0, 0
    if kind == "effect_only" then
      f.hold(b.player, 529)
    end
    if kind == "empty_override" then
      f.hold(b.player, nil)
    end
    f.data.items.ITEM_186.holdEffect = kind == "metadata_cleared" and "NONE" or "CHOICE_BAND"
    local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
      reads = reads + 1
      if kind == "suppressed" then
        return nil, 0
      end
      if kind == "empty_override" then
        return "HELD_CHOICE_BAND", 0
      end
      return nextRead(ctx)
    end)
    b.rng = function(lo)
      draws = draws + 1
      return lo
    end
    local snapshot = assert(api:snapshot())
    local blocked = kind == "physical" or kind == "metadata_cleared" or kind == "suppressed"
    T.eq(snapshot.moves[1].disabled, false, "locked learned slot stays selectable")
    T.eq(snapshot.moves[2].disabled, blocked, "snapshot follows physical native Choice Band")
    if blocked then
      local ok, reason = submit(1, 2)
      T.eq(ok, nil, "public action refuses other move")
      T.check(reason and reason:find("choice", 1, true) ~= nil, "public refusal identifies native choice")
      T.eq(b.phase, "moveSelect", "public refusal preserves current prompt")
      T.eq(#b.queue, 0, "public refusal adds no native messages")
    end
    T.eq(reads, 0, "public snapshot/admission never asks the held-effect hook")
    T.eq(draws, 0, "public snapshot/admission consumes no RNG")
    T.eq(b.player.curMoves[1].pp, 10, "query/refusal preserves locked slot PP")
    T.eq(b.player.curMoves[2].pp, 10, "query/refusal preserves other slot PP")
    off()
  end
  f.data.items.ITEM_186.holdEffect = "CHOICE_BAND"
  for _, change in ipairs({ "choice", "item", "imprison", "same_restriction_choice" }) do
    local b = fresh()
    if change == "same_restriction_choice" then
      f.hold(b.player, nil)
    end
    local snapshot = assert(api:snapshot())
    local old = { id = 1, revision = snapshot.revision, kind = "move", slot = 2 }
    if change == "item" then
      f.hold(b.player, nil)
    elseif change == "imprison" then
      b.enemy.imprison = true
    else
      b.player.choicedMove = 10
    end
    local ok, reason = api:submit(old)
    T.eq(ok, nil, "changed native admission invalidates offered intent")
    T.eq(reason, "stale battle context", "staleness is reported before native dispatch")
    T.eq(b.phase, "moveSelect", "stale intent preserves prompt")
    T.eq(b.player.curMoves[2].pp, 10, "stale intent spends no PP")
  end
  do
    local b, reads, draws = fresh(), 0, 0
    local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
      reads = reads + 1
      return nextRead(ctx)
    end)
    b.rng = function(lo)
      draws = draws + 1
      return lo
    end
    f.game.input.wasPressed = function(_, key)
      return key == "a"
    end
    b:update(1 / 60)
    T.eq(b.phase, "messages", "actual A input presents native refusal")
    T.eq(b.afterQueue, "moveSelect", "native refusal returns to attack selection")
    for _ = 1, 240 do
      if b.phase ~= "messages" then
        break
      end
      b:update(1 / 60)
    end
    T.eq(b.phase, "moveSelect", "actual message queue returns to the move selector")
    T.eq(b.moveIndex, 2, "native refusal keeps the selected cursor")
    T.eq(reads, 0, "manual refusal never calls held-effect consumers")
    T.eq(draws, 0, "manual refusal never advances RNG")
    T.eq(b.player.curMoves[2].pp, 10, "manual refusal spends no PP")
    off()
    f.game.input.wasPressed = function()
      return false
    end
    local ok, err = submit(1, 1)
    T.eq(ok, true, "fresh public intent admits the locked learned move: " .. tostring(err))
  end
  T.eq(#f.result.errors, 0, "public and native callbacks remain error-free")
  f.close()
end
T.finish("native GBA Choice Band public admission and native refusal return")
