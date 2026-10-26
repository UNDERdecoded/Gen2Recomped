-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Detach the native row command at its battle yield. The original coroutine,
-- service objects and completion closures never become checkpoint data.
local S = {}
local OMIT =
  { game = true, save = true, overworld = true, runner = true, npc = true, onDone = true, script = true, pc = true }
function S.capture(game, descriptor, clone)
  local ctx = assert(descriptor.ctx)
  local runner = assert(ctx.runner)
  assert(
    runner == game.overworld.runner and runner.ctx == ctx and runner:isRunning(),
    "story runner is not the active native owner"
  )
  assert(
    type(ctx.script) == "table"
      and type(ctx.pc) == "number"
      and ctx.pc % 1 == 0
      and ctx.script[ctx.pc]
      and ctx.script[ctx.pc][1] == "start_battle",
    "current script command cannot be detached"
  )
  assert(not ctx.afterScript or next(ctx.afterScript) == nil, "story has opaque deferred callbacks")
  local values = {}
  for key, v in pairs(ctx) do
    if not OMIT[key] then
      values[key] = v
    end
  end
  local record = clone({
    kind = "script",
    rows = ctx.script,
    pc = ctx.pc + 1,
    values = values,
    npc = ctx.npc and ctx.npc.id,
    battleKind = descriptor.battleKind,
    before = descriptor.before,
  })
  record.onDone = require("src.core.CheckpointCallbacks").capture(ctx.onDone, clone)
  assert(S.validate(game, record), "native script cannot be reconstructed")
  return record
end
function S.validate(game, c)
  if
    type(c) ~= "table"
    or c.kind ~= "script"
    or type(c.rows) ~= "table"
    or type(c.values) ~= "table"
    or type(c.pc) ~= "number"
    or c.pc % 1 ~= 0
    or c.pc < 2
    or c.pc > #c.rows + 1
    or not c.rows[c.pc - 1]
    or c.rows[c.pc - 1][1] ~= "start_battle"
    or (c.battleKind ~= "wild" and c.battleKind ~= "trainer")
  then
    return false
  end
  for key in pairs(c.values) do
    if OMIT[key] or key == "onDone" then
      return false
    end
  end
  if not require("src.core.CheckpointCallbacks").valid(c.onDone) then
    return false
  end
  if c.npc and type(c.npc) ~= "string" then
    return false
  end
  return #require("src.script.ScriptRunner").validate(c.rows, function(name)
    return require("src.script.Commands").resolve(game.data, name) ~= nil
  end) == 0
end
function S.apply(game, battle, c)
  assert(S.validate(game, c), "invalid native script continuation")
  local ctx = {}
  for key, v in pairs(c.values) do
    ctx[key] = v
  end
  if c.npc then
    for _, npc in ipairs(game.overworld.npcs or {}) do
      if npc.id == c.npc then
        ctx.npc = npc
        break
      end
    end
    assert(ctx.npc, "native story actor is absent")
  end
  ctx.onDone = require("src.core.CheckpointCallbacks").build(game.overworld, c.onDone)
  local runner = game.overworld.runner
  runner:_checkpointRun(c.rows, ctx, c.pc)
  ctx = runner.ctx
  ctx.script, ctx.pc = c.rows, c.pc - 1
  battle.onFinish = function(result)
    require("src.script.Commands")._checkpointBattleFinished(ctx, battle, c.battleKind, c.before, result)
  end
  require("src.core.CheckpointBattle").bind(
    battle,
    { kind = "script", ctx = ctx, battleKind = c.battleKind, before = c.before },
    battle.onFinish
  )
end
return S
