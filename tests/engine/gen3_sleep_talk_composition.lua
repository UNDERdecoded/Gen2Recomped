package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({
    "delegate",
    "primary_delegate",
    "override",
    "status_override",
    "fallback",
    "awake",
    "empty",
  }) do
    local entry
    if mode ~= "fallback" then
      entry = [[return function(mod)
    local base=assert(mod.content.move_effects:get("SLEEP_TALK_EFFECT"))
    local pick,run=base.callsMove,base.run
    mod.exports.calls=0
    ]] .. (mode == "primary_delegate" and [[
    base={kind="primary",run=function(ctx)mod.exports.calls=mod.exports.calls+1;return run(ctx)end}
    ]] or [[
    base.callsMove=function(ctx)
     mod.exports.calls=mod.exports.calls+1
     ]] .. (mode == "override" and "return ctx.user.curMoves[3].id" or "return pick(ctx)") .. [[
    end
    ]]) .. [[
    assert(mod.content.move_effects:override("SLEEP_TALK_EFFECT",base))
    ]] .. (mode == "status_override" and [[
    local status=mod.content.statuses:get("SLP")
    status.beforeMove=function()return false,{}end
    assert(mod.content.statuses:override("SLP",status))
    ]] or "") .. [[
    mod.exports.api=mod
   end]]
    end
    local f = require("tests.enemy_actions.sleep_talk").fixture(".", "gen2", version, entry)
    local c = f.fresh("TACKLE", { enemy = true })
    local b = c.battle
    b:syncSides()
    c.user.mon.status, c.user.sleepTurns = "SLP", 4
    c.user.mon.moves =
      { { id = f.ids.SLEEP_TALK, pp = 10 }, { id = f.ids.TACKLE, pp = 0 }, { id = f.ids.SCRATCH, pp = 10 } }
    c.user.curMoves = c.user.mon.moves
    if mode == "awake" then
      c.user.mon.status, c.user.sleepTurns = nil, nil
    end
    if mode == "empty" then
      c.user.curMoves[2].id, c.user.curMoves[3].id = f.ids.METRONOME, f.ids.MIRROR_MOVE
    end
    c.user.lastMove = f.ids.SCRATCH
    local originalEffects, originalStatuses = b.data.move_effects, b.data.statuses
    if mode == "fallback" then
      b.data.move_effects, b.data.statuses = nil, nil
    end
    local reads = {}
    local offReads = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
      reads[#reads + 1] = { trigger = ctx.trigger, parameter = ctx.parameter, item = ctx.item }
      return nextRead(ctx)
    end)
    local used = {}
    local off = f.e.api.events:on("battle.move_used", function(e)
      used[#used + 1] = { move = e.move.id, target = e.target.mon.nickname, called = e.isCalled or false }
    end)
    b.rng = function(lo, hi)
      if lo == 1 then
        return 1
      end
      return hi
    end
    b:executeAction(c.user, c.user, c.user.curMoves[1])
    if mode == "awake" or mode == "empty" then
      T.eq(#used, 1, "failed Sleep Talk emits only its caller event")
      T.eq(c.user.curMoves[1].pp, 9, "failed executed caller still spends its PP")
      T.eq(c.user.lastMove, f.ids.SCRATCH, "failed caller preserves previous move bookkeeping")
      T.eq(#reads, 2, "failed caller performs only the separate after-action item reads")
      for _, read in ipairs(reads) do
        T.eq(read.trigger, "residual", "no failed-call move-end sweep is inserted")
      end
    elseif mode == "status_override" then
      T.eq(#used, 0, "authored sleep interruption owns cancellation")
      T.eq(f.e.calls, 0, "cancelled caller never selects a nested move")
      T.eq(c.user.curMoves[1].pp, 10, "authored cancellation spends no PP")
    else
      T.eq(#used, 2, "default or delegated caller reaches one nested move")
      T.eq(
        used[2].move,
        mode == "override" and "SCRATCH" or "TACKLE",
        "authored choice or native zero-PP eligibility is respected"
      )
      T.eq(used[2].called, true, "nested public event retains called provenance")
      T.eq(c.user.curMoves[1].pp, 9, "caller alone spends PP")
      T.eq(c.user.curMoves[2].pp, 0, "called learned slot retains zero PP")
      T.eq(c.user.sleepTurns, 3, "native sleep ticks once")
      T.eq(c.user.mon.sleepTurns, 3, "the party record retains the actual remaining sleep count")
      T.check(
        c.target.mon.hp < 400 and c.user.mon.hp == 400,
        "nested attack targets the foe rather than the caller"
      )
      if mode ~= "primary_delegate" then
        local asleep, announced
        for i, row in ipairs(b.queue) do
          if row.text and row.text:find("is fast asleep", 1, true) then
            asleep = asleep or i
          end
          if row.text and row.text:find("used", 1, true) then
            announced = announced or i
          end
        end
        T.check(
          asleep and announced and asleep < announced,
          "native sleep text precedes the move announcement"
        )
      end
      T.eq(c.user.lastMove, f.ids.SLEEP_TALK, "native bookkeeping retains selected caller identity")
      if mode ~= "fallback" then
        T.eq(f.e.calls, 1, "captured builtin delegation is invoked once")
      end
    end
    T.eq(b._gbaMoveFrame, nil, "nested dispatcher restores its frame")
    T.eq(
      require("src.battle.MoveEffects").RECORDS.SLEEP_TALK_EFFECT.callsMove,
      nil,
      "shared legacy effect remains unchanged"
    )
    T.same(f.result.loader.errors, {}, "record callbacks complete without swallowed runtime errors")
    off()
    offReads()
    b.data.move_effects, b.data.statuses = originalEffects, originalStatuses
    f.close()
  end
end
local V = require("src.core.GameVersion")
local before = V.get()
for _, version in ipairs({ "red", "gold" }) do
  V.set(version)
  local base = require("src.battle.Status").RECORDS.SLP
  T.eq(
    require("src.battle.Gen3SleepTalk").status("SLP", base),
    base,
    "older-generation status records are not adapted"
  )
  local user = { name = "OLD", mon = { status = "SLP" }, sleepTurns = 1 }
  local canMove = require("src.battle.Status").beforeMove(user, function(lo)
    return lo
  end, nil, { id = "SLEEP_TALK" })
  T.eq(canMove, false, "older-generation waking still forfeits the turn")
  T.eq(user.mon.status, nil, "older-generation waking clears sleep")
end
V.set(before)
T.finish("native Sleep Talk effect and sleep status composition")
