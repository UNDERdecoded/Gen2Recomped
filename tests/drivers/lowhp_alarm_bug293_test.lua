-- Driver: manual audio check for the low-health siren cutting out (#293).
-- pokered sets wLowHealthAlarm on a red bar (core.asm:1858-1875) and only
-- RemoveFaintedPlayerMon (core.asm:1011-1016) clears it, so a sounding siren
-- rides through the next hit.  No POKEPORT_SPEED: audio has its own clock.
--   POKEPORT_DRIVER=tests/drivers/lowhp_alarm_bug293_test.lua \
--     POKEPORT_IDENTITY=bug293 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Sound = require("src.core.Sound")

  local ALARM = "Low_Health_Alarm"
  local function siren() return Sound.isLooping(ALARM) end

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the ear cannot check --------------------------------
  -- A siren with no source and a siren stopped every frame sound the same.
  check("BattleState:lowHealthAlarmActive exists",
        type(BattleState.lowHealthAlarmActive) == "function")
  check("BattleState:updateFx exists (it is what latches the siren)",
        type(BattleState.updateFx) == "function")

  -- Sound.startLoop uses the registered sfx def when there is one and
  -- otherwise synthesizes the siren; a ROM import has no def, so the synth
  -- path is the normal one.
  local def = game.data.audio and game.data.audio.sfx
              and game.data.audio.sfx[ALARM]
  if def then
    check("data.audio.sfx." .. ALARM .. " resolves", true)
  else
    local ok, src = pcall(require("src.core.ChipAudio").newLowHealthAlarm)
    check("no " .. ALARM .. " def, so ChipAudio synthesizes the siren",
          ok and src ~= nil)
    if ok and src and src.stop then pcall(src.stop, src) end
  end

  local vol = game.save.options and game.save.options.sfxVol
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(vol))
  if not love.audio or vol == 0 then
    U.log("WARNING: sound output is off, so nothing below will be audible;",
          "raise SFX VOL in OPTION first -- a muted run and a dead siren",
          "are the same thing to an ear")
  end

  -- ---- a lead whose bar is red and who cannot end the fight --------------
  -- :L20 so a weak foe cannot one-shot it, and TAIL_WHIP only (power 0), so
  -- the wild mon survives every turn and keeps hitting back.
  local function freshLead()
    local mon = Pokemon.new(game.data, "RATTATA", 20)
    mon.moves = { { id = "TAIL_WHIP", pp = 30 } }
    game.save.party = { mon }
    return mon
  end

  -- put the drawn bar at 9 of 48 px: HP_BAR_RED is < 10 px
  -- (GetHealthBarColor, core.asm), the same threshold HudTiles.drawHPBar
  -- tints with
  local function intoTheRed(mon)
    mon.hp = math.max(1, math.floor(mon.stats.hp * 9 / 48))
    return math.max(1, math.floor(mon.hp * 48 / math.max(1, mon.stats.hp)))
  end

  local lead = freshLead()
  local px = intoTheRed(lead)
  U.log(("lead: RATTATA :L20  %d/%d HP  ->  %d of 48 px")
          :format(lead.hp, lead.stats.hp, px))
  check("the lead's bar is red (red is under 10 px)", px < 10)
  check("the lead has HP to spare for a non-lethal hit", lead.hp >= 6)

  U.teleport(game, "ROUTE_1", 5, 5, "down")

  local function sample(battle, pressA)
    if pressA then U.tap(game, "a") else U.wait(1) end
    return {
      on = siren(),
      hp = battle.player.mon.hp,
      shown = battle.player.shownHP,
      text = battle.current and battle.current.text or "",
    }
  end

  -- longest run of consecutive silent frames in [from, to], and where it
  -- started: this is the number a human hears as a gap
  local function longestGap(log, from, to)
    local best, bestAt, run, runAt = 0, nil, 0, nil
    for i = from, math.min(to, #log) do
      if log[i].on then
        run, runAt = 0, nil
      else
        if run == 0 then runAt = i end
        run = run + 1
        if run > best then best, bestAt = run, runAt end
      end
    end
    return best, bestAt
  end

  local function startBattle(species, level, enemyMoves)
    local battle = BattleState.newWild(game, species, level)
    battle.onFinish = function() end
    if enemyMoves then
      -- BOTH: the battler's curMoves aliases mon.moves at construction
      -- (BattleState.lua:345) and TrainerAI.chooseMove reads curMoves, so
      -- replacing only mon.moves leaves the AI on the original moveset
      battle.enemy.mon.moves = enemyMoves
      battle.enemy.curMoves = enemyMoves
    end
    game.overworld:pushBattle(battle)
    for _ = 1, 120 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(4)
    end
    return battle
  end

  -- The A presses are folded into the sampling loop rather than done with
  -- U.tap first: applyDamage takes the HP off the model at queue-build time,
  -- so a faster foe can land its hit within a couple of frames of the move
  -- being chosen and a U.tap would sample straight past it.
  local function playTurn(battle, maxFrames)
    local pre = battle.player.mon.hp
    local log, hitAt, emptyAt, settleAt = {}, nil, nil, nil
    for i = 1, maxFrames or 900 do
      local pressA = i == 1 or i == 6
        or (i > 6 and i % 6 == 0 and battle.phase ~= "menu")
      log[i] = sample(battle, pressA)
      if not hitAt and log[i].hp < pre then hitAt = i end
      if hitAt and not emptyAt and (log[i].shown or 0) <= 0 then emptyAt = i end
      if hitAt and not settleAt and log[i].shown == log[i].hp then
        settleAt = i
      end
      if settleAt and i > settleAt + 40 then break end
    end
    return log, pre, hitAt, settleAt, emptyAt
  end

  -- =====================================================================
  -- 1. the non-lethal hit: the siren must ride it out unbroken
  -- =====================================================================
  U.log("--- battle 1: a hit you survive -------------------------------")
  -- PIDGEY :L3 knows only GUST (SAND_ATTACK is not until :L5), accurate and
  -- worth a couple of HP against a :L20 lead, so it lands and never kills.
  local b1 = startBattle("PIDGEY", 3)
  check("reached the action menu", b1.phase == "menu")
  check("the siren is sounding before anything happens", siren())
  U.shot(game, DIR .. "/bug293_1_menu.png")

  local log, pre, hitAt, settleAt = playTurn(b1)
  U.log(("turn: %d frames sampled, HP %d -> %d, hit landed on frame %s, ")
          :format(#log, pre, b1.player.mon.hp, tostring(hitAt))
        .. ("bar settled on frame %s"):format(tostring(settleAt)))
  if check("the foe's attack connected", hitAt ~= nil) then
    local to = settleAt and (settleAt + 20) or #log
    local gap, gapAt = longestGap(log, hitAt, to)
    -- the reported symptom, in frames: 60 frames is one second
    U.log(("longest silence between the hit and the bar settling: %d frames%s")
            :format(gap, gapAt and (" (from frame " .. gapAt .. ")") or ""))
    check("the siren never dropped out across the hit (#293)", gap == 0)
    if gap > 0 then
      U.log("     it went quiet during:", log[gapAt].text ~= "" and
            log[gapAt].text:gsub("\n", " / ") or "(no text on screen)")
    end
    check("and it is still sounding once the bar has settled",
          siren() and b1.player.mon.hp > 0)
    U.shot(game, DIR .. "/bug293_2_after_hit.png")
  end

  -- =====================================================================
  -- 2. the killing blow: it must hold until the bar has drained empty
  -- =====================================================================
  U.log("--- battle 2: the hit that kills you --------------------------")
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local lead2 = freshLead()
  local px2 = intoTheRed(lead2)
  check("the lead's bar is red again", px2 < 10)
  -- One guaranteed-lethal move instead of the wild AI's random pick: only
  -- one of a :L40 PIDGEY's four real moves does any damage.
  local b2 = startBattle("PIDGEY", 40, { { id = "WING_ATTACK", pp = 35 } })
  check("reached the action menu", b2.phase == "menu")
  check("the siren is sounding before the killing blow", siren())

  local log2, pre2, hitAt2, settleAt2, emptyAt2 = playTurn(b2)
  U.log(("lethal turn: %d frames sampled, HP %d -> %d, hit on frame %s, ")
          :format(#log2, pre2, b2.player.mon.hp, tostring(hitAt2))
        .. ("bar empty on frame %s"):format(tostring(emptyAt2)))
  if check("the killing blow landed", hitAt2 ~= nil and b2.player.mon.hp <= 0) then
    local to = emptyAt2 or settleAt2 or #log2
    local gap, gapAt = longestGap(log2, hitAt2, to)
    U.log(("longest silence between the killing blow and the empty bar: " ..
           "%d frames%s"):format(gap, gapAt and (" (from frame " .. gapAt ..
           ")") or ""))
    check("the siren held all the way down to an empty bar (#293)", gap == 0)
    if gap > 0 then
      U.log("     it went quiet during:", log2[gapAt].text ~= "" and
            log2[gapAt].text:gsub("\n", " / ") or "(no text on screen)")
    end
    if emptyAt2 then
      -- and only then does it stop (RemoveFaintedPlayerMon)
      local stopped = false
      for i = emptyAt2, #log2 do
        if not log2[i].on then stopped = true break end
      end
      check("and went quiet once the bar was empty (RemoveFaintedPlayerMon)",
            stopped)
    end
    U.shot(game, DIR .. "/bug293_3_ko.png")
  end

  -- =====================================================================
  -- 3. hand off, already at the FIGHT menu with the siren going
  -- =====================================================================
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local lead3 = freshLead()
  intoTheRed(lead3)
  local b3 = startBattle("PIDGEY", 3)
  check("handing off at the action menu", b3.phase == "menu")
  check("handing off with the siren sounding", siren())
  U.shot(game, DIR .. "/bug293_4_handoff.png")

  U.log("FIGHT menu, wild PIDGEY, RATTATA in the red and the siren going.")
  U.log("A, A uses TAIL WHIP (power 0), so the PIDGEY keeps hitting back;")
  U.log("it takes several turns to die.")
  U.log("The siren must not break under the foe's move, the animation or the")
  U.log("bar drain, and on the lethal hit it holds to an empty bar (#293).")

  while true do
    coroutine.yield()
  end
end
