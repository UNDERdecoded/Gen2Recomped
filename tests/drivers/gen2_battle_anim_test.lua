-- Gen 2 battle animations.  BattleState drives the ball toss and the send-out
-- with Gen 1's animation ids (TossBallAnimation's TOSS/POOF/HIDEPIC/SHAKE
-- chain), but Gen 2 keeps the whole toss in one script -- ANIM_THROW_POKE_BALL
-- -- so none of those ids resolved and no ball was ever thrown on screen.
-- `anim_loop` also lost its jump target in the extractor, so looping scripts
-- (thunder, the multi-hit bursts) ran their body once.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  U.wait(10)
  local anims = game.data.battle_anims
  ok(anims and anims.gen2, "the Gen 2 animation set loaded")
  if not (anims and anims.gen2) then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail))
    return false
  end

  local Player = require("src.battle.Gen2AnimPlayer")
  local p = Player.new(game.data)

  ok(p:scriptFor("TOSS_ANIM") ~= nil, "TOSS_ANIM resolves to ANIM_THROW_POKE_BALL")
  ok(p:scriptFor("ULTRATOSS_ANIM") ~= nil, "ULTRATOSS_ANIM resolves too")
  ok(p:scriptFor("BLOCKBALL_ANIM") ~= nil, "BLOCKBALL_ANIM resolves too")
  ok(p:scriptFor("POOF_ANIM") ~= nil, "POOF_ANIM resolves to ANIM_SEND_OUT_MON")
  ok(p:scriptFor("SHAKE_ANIM") == nil,
     "SHAKE_ANIM has no script of its own in Gen 2")

  -- the toss has to actually put the ball on screen, not just start
  local function run(name, opts)
    local started = p:start(name, true, opts)
    local frames, seen, fx, moved = 0, 0, 0, false
    while not p:isDone() and frames < 400 do
      frames = frames + 1
      p:update()
      if #p.objects > seen then seen = #p.objects end
      fx = fx + #p:pollEffects()
      for _, o in ipairs(p.objects) do
        if o.xOffset ~= 0 or o.yOffset ~= 0 then moved = true end
      end
    end
    return started, frames, seen, fx, moved
  end

  local started, frames, seen = run("TOSS_ANIM", { shakes = 3, ball = "POKE_BALL" })
  ok(started ~= false and frames > 4 and seen > 0,
     "the ball toss plays (" .. frames .. " frames, " .. seen .. " objects)")

  -- BattleAnim_ThrowPokeBall's first row is `anim_if_param_equal NO_ITEM,
  -- .TheTrainerBlockedTheBall`, so wBattleAnimParam has to be the ball's
  -- ITEM index.  Left at 0 every toss took the blocked branch: a stray
  -- BATTLE_ANIM_GFX_HIT flash over the throw and none of the capture --
  -- no mon drawn in, no wobble, no click.
  local function runBall(opts)
    p:start("TOSS_ANIM", true, opts)
    local frames, effects, framesets = 0, {}, {}
    while not p:isDone() and frames < 600 do
      frames = frames + 1
      p:update()
      for _, e in ipairs(p:pollEffects()) do effects[e.effect] = true end
      for _, o in ipairs(p.objects) do
        if o.index == 1 then framesets[o.frameset] = true end
      end
    end
    local rocked = 0
    for _ in pairs(framesets) do rocked = rocked + 1 end
    return effects, frames, rocked
  end

  local effects, ballFrames, rocked = runBall({ shakes = 3, caught = true, ball = "POKE_BALL" })
  ok(p.vars.param ~= 0, "the toss carries the ball's item index as its param")
  ok(effects["SE_HIDE_MON_PIC"],
     "a real toss draws the mon into the ball (RETURN_MON)")
  ok(p.wobbles == 4,
     "anim_checkpokeball is read once per wobble plus the verdict ("
     .. tostring(p.wobbles) .. ")")
  ok(ballFrames > 150,
     "the wobble loop runs its full 48 frames per shake (" .. ballFrames .. ")")
  ok(rocked > 1,
     "anim_incobj rocks the ball through more than one frameset (" .. rocked .. ")")
  ok(p.keepSprites == true,
     "a capture ends on anim_keepsprites, so the closed ball stays up")
  ok(p:finalSprites() ~= nil, "and BattleState gets the resting ball")

  effects = runBall({ shakes = 2, caught = false, ball = "POKE_BALL" })
  ok(effects["SE_SHOW_MON_PIC"],
     "a break-out puts the mon back on screen (ENTER_MON)")
  ok(p.keepSprites == false, "and leaves no resting ball behind")

  p:start("BLOCKBALL_ANIM", true)
  ok(p.vars.param == 0, "a trainer's block is the NO_ITEM branch")

  started, frames, seen = run("POOF_ANIM")
  ok(started ~= false and frames > 4 and seen > 0,
     "the send-out poof plays (" .. frames .. " frames, " .. seen .. " objects)")
  ok(p:start("SHAKE_ANIM", true) == false,
     "the Gen 1 shake row reports no data instead of hanging")

  -- objects must travel, and the screen effects must reach BattleState
  local moves, blank, still = 0, 0, 0
  local firstBlank
  -- ...and none may spin until the runaway bound: anim_jumpuntil is a
  -- countdown on wBattleAnimParam, not a wait on the object list, and
  -- treating it as a wait left Fury Cutter (and every other user) looping
  -- until the safety cut-off -- the "glitchy and far too long" animations.
  local runaway, firstRunaway = 0, nil
  for id in pairs(game.data.moves or {}) do
    if p:scriptFor(id) then
      moves = moves + 1
      local _, _, objs, _, moved = run(id, nil)
      if objs == 0 then blank = blank + 1; firstBlank = firstBlank or id end
      if objs > 0 and not moved then still = still + 1 end
      if (p.ranFrames or 0) > 180 then
        runaway = runaway + 1
        firstRunaway = firstRunaway or id
      end
    end
  end
  ok(moves > 200, "every move animation ran (" .. moves .. ")")
  ok(runaway == 0, runaway .. "/" .. moves
     .. " move animations ran away (first " .. tostring(firstRunaway) .. ")")
  ok(blank <= moves * 0.2,
     blank .. "/" .. moves .. " moves draw no object at all (first "
     .. tostring(firstBlank) .. ")")
  ok(still <= moves * 0.5,
     still .. "/" .. moves .. " moves never move an object")

  -- every anim_bgeffect the scripts use has to be either routed to a screen
  -- effect or listed as deliberately dropped
  local unmapped = {}
  for _, script in pairs(anims.scripts or {}) do
    for _, inst in ipairs(script.code or {}) do
      if inst.op == "bgeffect" then
        local id = inst.args[1]
        if not Player.BG_EFFECTS_DROPPED[id] then
          p.effects = {}
          p:step(inst)
          if #p.effects == 0 then unmapped[id] = (unmapped[id] or 0) + 1 end
        end
      end
    end
  end
  p.effects = {}
  local kinds = 0
  for id, n in pairs(unmapped) do
    kinds = kinds + 1
    U.log(("unrouted bg effect $%02X x%d"):format(id, n))
  end
  ok(kinds == 0, "every bg effect is routed or explicitly dropped")

  -- the PLAYERHEAD/ENEMYFEET sheets are placeholders for a VRAM copy the
  -- port cannot do; drawing them put a stray foot in unrelated moves
  local strays = 0
  for id in pairs(game.data.moves or {}) do
    local script = p:scriptFor(id)
    for _, inst in ipairs(script and script.code or {}) do
      if inst.op == "obj" then
        local def = anims.objects[inst.args[1]]
        if def and (def.gfx == 0x28 or def.gfx == 0x29) then
          p.objects = {}
          p:spawn(inst.args[1], inst.args[2], inst.args[3], inst.args[4])
          strays = strays + #p.objects
        end
      end
    end
  end
  p.objects = {}
  ok(strays == 0, "no move draws a raw battler-pic sheet (" .. strays .. ")")

  -- anim_loop rows must resolve their target, or a looping script runs once
  local loops, resolved = 0, 0
  for _, script in pairs(anims.scripts or {}) do
    for _, inst in ipairs(script.code or {}) do
      if inst.op == "loop" then
        loops = loops + 1
        if inst.to then resolved = resolved + 1 end
      end
    end
  end
  ok(loops > 0 and resolved == loops,
     "every anim_loop knows where to jump (" .. resolved .. "/" .. loops .. ")")

  -- and every move should have a script to play
  local moves, missing, firstMissing = 0, 0, nil
  for id in pairs(game.data.moves or {}) do
    moves = moves + 1
    if not p:scriptFor(id) then
      missing = missing + 1
      firstMissing = firstMissing or id
    end
  end
  ok(missing == 0, "every move has an animation (" .. missing .. "/" .. moves
     .. " missing, first " .. tostring(firstMissing) .. ")")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
