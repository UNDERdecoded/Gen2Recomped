-- Native battle-effect controllers. Presentation never changes battle HP,
-- status, PP or RNG; the battle queue owns its lifetime and native frame clock.
local M = {}
local V = require("src.core.GameVersion")

function M.queue(battle, user, name)
  if not V.isGen3() or type(battle.queue) ~= "table" then
    return
  end
  battle.nextInsert = (battle.nextInsert or 0) + 1
  table.insert(battle.queue, battle.nextInsert, {
    anim = name,
    gbaNativeEffect = true,
    attackerIsPlayer = user.isPlayer,
    attackerPosition = user.position,
    targetPosition = user.position,
  })
end

local function startFade(from, target, delay, color)
  -- The initialization callback performs the first background half-step.
  return {
    y = from,
    target = target,
    toggle = 1,
    delay = 0,
    active = true,
    interval = delay or 2,
    color = color or { 30 / 31, 0, 1 },
  }
end

local function fade(state)
  local f = state.fade
  if not f.active then
    return
  end
  if f.finishing ~= nil then
    if f.finishing == 4 then
      f.active = false
    else
      f.finishing = f.finishing + 1
    end
    return
  end
  if f.toggle == 0 then
    if f.delay < f.interval then
      f.delay = f.delay + 1
      return
    end
    f.delay = 0
    f.toggle = 1
    return
  end
  state.coeff = f.y / 16
  local k = state.coeff
  state.color = k > 0 and { (f.color[1] * k) / k, (f.color[2] * k) / k, (f.color[3] * k) / k } or { 0, 0, 0 }
  f.toggle = 0
  if f.y == f.target then
    f.finishing = 0
  else
    f.y = f.target > f.y and math.min(f.target, f.y + 2) or math.max(f.target, f.y - 2)
  end
end

function M.start(battle, row)
  if
    not V.isGen3() or row.anim ~= "POISON" and row.anim ~= "FOCUS_BAND" and row.anim ~= "SUBSTITUTE_FADE"
  then
    return false
  end
  local user = row.attackerPosition ~= nil and battle:battlerAt(row.attackerPosition)
    or (row.attackerIsPlayer and battle.player or battle.enemy)
  if not user then
    return false
  end
  if row.anim == "SUBSTITUTE_FADE" then
    local Sub = require("src.battle.Gen3SubstitutePresentation")
    local hidden = battle.picFx and battle.picFx[user] and battle.picFx[user].hidden
    if battle:substituteVisible(user) and hidden then
      local swap = Sub.beginSwap(battle, user, false)
      swap.state.substitute = false
      return false
    end
    battle._gbaEffectPresentation = {
      user = user,
      kind = row.anim,
      frame = 0,
      x = 0,
      y = 0,
      alpha = 1,
      monbg = false,
      coeff = 0,
      color = { 0, 0, 0 },
    }
    return true
  end
  local focus = row.anim == "FOCUS_BAND"
  local pause = focus and not battle:animationsOn()
  local protected = focus and battle:substituteVisible(user) or not focus and (user.substituteHP or 0) > 0
  if not pause and (not battle:animationsOn() or user.invulnerable or protected) then
    return false
  end
  battle._gbaEffectPresentation = {
    user = user,
    kind = row.anim,
    pause = pause and 32 or nil,
    frame = 0,
    x = 0,
    y = 0,
    coeff = 0,
    color = { 0, 0, 0 },
    sound = focus and (V.get() == "firered" and 164 or 171) or (V.get() == "firered" and 141 or 148),
    soundLeft = focus and 1 or 6,
    soundWait = 0,
  }
  return true
end

local function focusStep(state)
  if state.frame == 1 then
    state.fade = startFade(0, 9, 7, { 1, 0, 0 })
    state.phase, state.remaining = "ramp", 30
    state.jitterWait, state.jitterPeriod, state.jitter, state.amplitude = 0, 1, 0, 2
    state.distance = 0
  elseif state.phase == "ramp" or state.phase == "hold" then
    fade(state)
    state.jitterWait = state.jitterWait - 1
    if state.jitterWait < 0 then
      if state.jitter == 0 then
        state.jitter, state.amplitude = state.amplitude, -state.amplitude
      else
        state.jitter = 0
      end
      state.jitterWait = state.jitterPeriod
    end
    if state.phase == "ramp" then
      state.distance = state.distance + 128
    end
    state.x = state.jitter + (state.user.isPlayer and -1 or 1) * math.floor(state.distance / 256)
    state.remaining = state.remaining - 1
    if state.remaining == 0 then
      if state.phase == "ramp" then
        state.phase, state.remaining, state.jitterPeriod = "hold", 30, 0
      else
        state.phase = "second-fade"
        state.fade = startFade(9, 0, 4, { 1, 0, 0 })
      end
    end
  elseif state.phase == "second-fade" then
    -- Sprite callbacks observe fade completion before that tick's tasks.
    if not state.fade.active then
      state.phase, state.delay = "delay", 6
    else
      fade(state)
    end
  elseif state.phase == "delay" then
    if state.delay > 0 then
      state.delay = state.delay - 1
    elseif not state.waitReleased then
      state.waitReleased = true
    else
      state.phase, state.remaining, state.origin = "return", 15, state.x
      local velocity = -state.x * 256 / 15
      state.velocity = velocity < 0 and math.ceil(velocity) or math.floor(velocity)
      state.distance = 0
    end
  else
    if state.remaining == 0 then
      state.x = 0
      return false
    end
    state.remaining, state.distance = state.remaining - 1, state.distance + state.velocity
    state.x = state.origin + math.floor(state.distance / 256)
  end
  return true
end

function M.update(battle)
  local state = battle._gbaEffectPresentation
  if not state then
    return false
  end
  state.frame = state.frame + 1
  if state.kind == "SUBSTITUTE_FADE" then
    local frame = state.frame
    -- Sixteen alpha decrements every third callback finish at tick 49;
    -- task release, waitforvisualfinish and script delays clear monbg at 55.
    -- The palette reset and ordinary native swap begin together at tick 57.
    if frame <= 56 then
      state.monbg = frame < 55
      state.alpha = 1 - math.min(16, math.floor((frame - 1) / 3)) / 16
      state.coeff = math.min(16, frame - 1) / 16
      state.color = state.coeff > 0 and { 1, 1, 1 } or { 0, 0, 0 }
      return true
    end
    local Sub = require("src.battle.Gen3SubstitutePresentation")
    if not state.swap then
      state.coeff, state.color = 0, { 0, 0, 0 }
      state.swap = Sub.beginSwap(battle, state.user, false)
    end
    local busy = Sub.stepSwap(state.swap)
    if state.swap.phase == "in" then
      state.alpha = 1
    end
    if busy then
      return true
    end
    if battle.picFx and battle.picFx[state.user] then
      battle.picFx[state.user].hidden = nil
    end
    battle._gbaEffectReconcile = battle._gbaEffectReconcile or {}
    battle._gbaEffectReconcile[state.user] = true
    battle._gbaEffectPresentation = nil
    return false
  end
  if state.pause ~= nil then
    if state.pause > 0 then
      state.pause = state.pause - 1
      return true
    end
    battle._gbaEffectPresentation = nil
    return false
  end
  -- The native sound task precedes shake and palette callbacks. Its
  -- thirteen-frame counter plays again on the following callback.
  if state.soundWait > 0 then
    state.soundWait = state.soundWait - 1
  elseif state.soundLeft > 0 then
    local options = battle.game and battle.game.save and battle.game.save.options or {}
    require("src.core.Sound").playId(
      battle.data,
      state.sound,
      { pan = state.user.isPlayer and -64 or 63, mono = options.stereo == false }
    )
    state.soundLeft, state.soundWait = state.soundLeft - 1, 13
  end
  if state.kind == "FOCUS_BAND" then
    if focusStep(state) then
      return true
    end
    battle._gbaEffectPresentation = nil
    return false
  elseif state.frame == 1 then
    state.x, state.shakes, state.shakeWait = 1, 18, 1
    state.fade, state.cycles = startFade(0, 12), 1
  else
    if state.shakes > 0 then
      if state.shakeWait > 0 then
        state.shakeWait = state.shakeWait - 1
      else
        state.shakes, state.shakeWait = state.shakes - 1, 2
        state.x = state.shakes == 0 and 0 or -state.x
      end
    end
    if not state.fade.active and state.cycles > 0 then
      state.fade, state.cycles = startFade(12, 0), state.cycles - 1
    end
    fade(state)
  end
  if state.soundLeft == 0 and state.shakes == 0 and not state.fade.active and state.cycles == 0 then
    battle._gbaEffectPresentation = nil
    return false
  end
  return true
end

function M.view(battle, user)
  local state = battle._gbaEffectPresentation
  return state and state.user == user and state or nil
end

function M.monBg(battle, user)
  local state = battle._gbaEffectPresentation
  local hidden = battle.picFx and battle.picFx[user] and battle.picFx[user].hidden
  return state ~= nil and state.monbg == true and user.isPlayer == state.user.isPlayer and not hidden
end

function M.reconcile(battle)
  for user in pairs(battle._gbaEffectReconcile or {}) do
    if user.invulnerable and battle:animationsOn() and user.mon and user.mon.hp > 0 then
      battle.picFx = battle.picFx or {}
      battle.picFx[user] = battle.picFx[user] or {}
      battle.picFx[user].hidden = true
    end
  end
  battle._gbaEffectReconcile = nil
end
return M
