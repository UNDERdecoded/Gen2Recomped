-- Parity test: the low-health alarm is a LATCH, not a per-frame function of the
-- model's HP (#293).  pokered keeps it in wLowHealthAlarm bit 7, set by
-- DrawPlayerHUDAndHPBar (engine/battle/core.asm:1858-1875) and cleared by
-- RemoveFaintedPlayerMon (core.asm:1011-1016).  That redraw does not run until
-- UpdateHPBar2 finishes (core.asm:4727-4729), so a siren already sounding rides
-- through the next hit.  This walks that timeline frame by frame.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local BattleState = require("src.battle.BattleState")
local Sound = require("src.core.Sound")
local S = require("tests.harness").suite("parity low health alarm")
local check, eq = S.check, S.eq

-- A stand-in carrying only what updateFx/stepHPDrain/lowHealthAlarmActive read.
-- The point is the frame-by-frame decision, not the damage roll behind it.
local function battler(maxHP, hp)
  return { mon = { hp = hp, stats = { hp = maxHP } }, shownHP = hp }
end

-- BattleState.__index = BattleState (BattleState.lua:32), so the stand-in
-- gets the real methods without newWild's Data/RNG/queue setup
local function battleAt(maxHP, hp)
  return setmetatable({
    data = {},        -- only ever handed to the stubbed Sound.startLoop
    introSlide = 0,   -- HUD already drawn (post send-out)
    showPlayerBack = false,
    player = battler(maxHP, hp),
    enemy = battler(40, 40),
  }, BattleState)
end

-- Record what the siren did instead of making noise.  updateFx re-requires
-- src.core.Sound each frame, so it picks these up off the same module table.
local siren = false
local realStart, realStop = Sound.startLoop, Sound.stopLoop
Sound.startLoop = function(_, name)
  if name == "Low_Health_Alarm" then siren = true end
end
Sound.stopLoop = function(name)
  if name == "Low_Health_Alarm" then siren = false end
end

-- One battle frame in BattleState:update's order: updateFx first
-- (BattleState.lua:1281), then the queue, whose {drain=true} row steps the bar
-- (BattleState.lua:798).  Returns one siren sample per frame, oldest first.
local function frames(b, n, draining)
  local log = {}
  for _ = 1, n do
    BattleState.updateFx(b)
    if draining then BattleState.stepHPDrain(b) end
    log[#log + 1] = siren
  end
  return log
end

local function allOn(log)
  for _, on in ipairs(log) do
    if not on then return false end
  end
  return #log > 0
end

local function allOff(log)
  for _, on in ipairs(log) do
    if on then return false end
  end
  return #log > 0
end

-- drain the bar to the model one frame at a time, sampling as we go; capped so
-- a broken stepHPDrain cannot spin forever
local function drainToModel(b, cap)
  local log = {}
  for _ = 1, cap or 200 do
    if b.player.shownHP == b.player.mon.hp then break end
    local f = frames(b, 1, true)
    log[#log + 1] = f[1]
  end
  return log
end

-- ---------------------------------------------------------------------
-- the regression: a hit lands while the siren is already sounding
-- ---------------------------------------------------------------------
do
  -- 9/48 = 9 px of a 48-px bar, one under HP_BAR_RED's threshold
  local b = battleAt(48, 9)
  check(allOn(frames(b, 10)), "a red bar starts the siren")
  check(b.lowHealthAlarmOn == true, "and latches wLowHealthAlarm's bit 7")

  -- applyDamage: the model loses the HP while the turn is still being queued,
  -- and the bar will not move until the {drain} row runs.
  b.player.mon.hp = 4
  eq(b.player.shownHP, 9, "the drawn bar has not moved yet")

  -- "FOE RATTATA used TACKLE!" plus the move animation: dozens of frames with
  -- no drain running at all, which is where #293 went silent
  check(allOn(frames(b, 60)),
        "the siren holds through the announcement and the move animation (#293)")

  -- ...and then the bar drains, maxHP/96 per frame (BattleState:stepHPDrain,
  -- porting engine/gfx/hp_bar.asm UpdateHPBar)
  local drain = drainToModel(b)
  check(#drain > 1, "the drain really took multiple frames")
  check(allOn(drain), "the siren holds for every frame of the drain (#293)")
  check(allOn(frames(b, 5)), "and is still sounding once the bar settles")
end

-- ---------------------------------------------------------------------
-- a lethal hit: the siren must last until the bar is visibly empty
-- (RemoveFaintedPlayerMon, core.asm:1011-1016, runs after the drain)
-- ---------------------------------------------------------------------
do
  local b = battleAt(48, 4)
  check(allOn(frames(b, 5)), "siren sounding before the killing blow")

  b.player.mon.hp = 0 -- applyDamage zeroes the model at queue-build time
  check(allOn(frames(b, 45)),
        "a lethal hit keeps the siren through \"used X!\" and the animation (#293)")

  local drain = drainToModel(b)
  check(allOn(drain), "and through the bar draining to empty (#293)")
  eq(b.player.shownHP, 0, "the bar reached empty")

  -- updateFx samples before the drain step, so the frame that lands on
  -- empty is decided from the previous value; the siren stops on the next
  local after = frames(b, 3)
  check(after[#after] == false, "the empty bar silences it")
end

-- ---------------------------------------------------------------------
-- the over-correction guard: a STOPPED alarm must not start during a drain.
-- DrawPlayerHUDAndHPBar sets the bit and does not run until UpdateHPBar2 has
-- finished, so the siren begins when the BAR lands in the red, not the model.
-- ---------------------------------------------------------------------
do
  local b = battleAt(48, 48)
  check(allOff(frames(b, 5)), "a full bar is silent")

  b.player.mon.hp = 9 -- big hit: model in the red, bar still at the top
  local drain = drainToModel(b)
  check(#drain > 1, "the long drain really took multiple frames")
  check(allOff(drain), "the siren does not start until the bar lands (#293)")
  check(allOn(frames(b, 3)), "and starts the moment it does")
end

-- ---------------------------------------------------------------------
-- healing out of the red silences it AT ONCE, not after the bar animates:
-- engine/items/item_effects.asm:991-994 clears the alarm before the heal
-- draws.  This is the one place the latch must not hold.
-- ---------------------------------------------------------------------
do
  local b = battleAt(48, 9)
  check(allOn(frames(b, 5)), "siren sounding on a red bar")
  b.player.mon.hp = 30 -- SUPER POTION: model jumps, the bar climbs after
  local after = frames(b, 1)
  check(after[1] == false, "a heal out of the red silences it on the spot")
  check(b.player.shownHP < b.player.mon.hp,
        "and it was silenced while the bar was still climbing")
end

-- ---------------------------------------------------------------------
-- the pre-existing gates still win over the latch: a decided battle
-- (EndLowHealthAlarm) and a fainted battler both stop it dead
-- ---------------------------------------------------------------------
do
  local b = battleAt(48, 9)
  check(allOn(frames(b, 3)), "siren sounding")
  b.result = "win"
  check(allOff(frames(b, 3)), "a decided battle stops it (EndLowHealthAlarm)")

  local c = battleAt(48, 9)
  check(allOn(frames(c, 3)), "siren sounding")
  c.player.fainted = true
  check(allOff(frames(c, 3)), "a fainted battler stops it")

  local d = battleAt(48, 9)
  check(allOn(frames(d, 3)), "siren sounding")
  d.lowHealthAlarmDisabled = true
  check(allOff(frames(d, 3)), "wLowHealthAlarmDisabled stops it")

  -- safari/old-man battles draw no player HUD, so they have no alarm to latch
  local e = battleAt(48, 9)
  e.safari = true
  check(allOff(frames(e, 3)), "the safari battle never starts one")
end

Sound.startLoop, Sound.stopLoop = realStart, realStop

S.finish()
