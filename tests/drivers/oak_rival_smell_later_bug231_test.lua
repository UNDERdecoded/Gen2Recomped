-- Driver: regression coverage for #231 "Missing Blue Dialogue (first rival
-- battle exit line)".
--
-- The first lab rival battle is a coordinate trigger in
-- data/scripts/oaks_lab.lua onStep (OaksLabRivalChallengesPlayerScript,
-- wYCoord == 6).  In pret/pokered scripts/OaksLab.asm the post-battle
-- OaksLabRivalEndBattleScript heals + flags, then on WIN prints the
-- "I picked the wrong POKéMON!" gloat, and on BOTH win and loss prints the
-- shared exit line _OaksLabRivalSmellYouLaterText ("OK! I'll make my POKéMON
-- fight to toughen it up!\012<PLAYER>! Gramps! Smell you later!") before Blue
-- walks out.  The buggy onStep sequence omitted that exit line entirely, so
-- Blue left the lab silently.
--
-- Scenario WIN: after the battle Blue must gloat ("picked the wrong POKéMON")
--   AND say the exit line ("Smell you later").
-- Scenario LOSS: Blue skips the gloat (that taunt was shown in-battle via
--   Rival1WinText) but must STILL say the exit line ("Smell you later").
--
-- Both scenarios FAIL before the fix (the exit line never appears) and PASS
-- after it.
--
-- Mechanics: TextBox.new is hooked to APPEND every raw `text` arg (before
-- {PLAYER}/{RIVAL} substitution, so the token-free search substrings survive)
-- into `seen`; the whole SmellYouLater string, incl. the \012 page break,
-- arrives in one TextBox.new call.  start_battle is stubbed to record the
-- result and RETURN NIL (not "end"): ScriptRunner then continues
-- synchronously into heal_party/set_flag/jump_if_false/show_text with NO
-- BattleState push and NO yield, so the run needs no party and cannot hang.
-- heal_party is a safe no-op on an empty party.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- accumulate every raw text a TextBox is built with
  local TextBox = require("src.render.TextBox")
  local origNew = TextBox.new
  local seen = {}
  TextBox.new = function(g, text, ...)
    if type(text) == "string" then seen[#seen + 1] = text end
    return origNew(g, text, ...)
  end

  -- Stub start_battle: set the win/loss result the post-battle rows branch on
  -- and return nil so ScriptRunner falls through to heal_party/set_flag/
  -- jump_if_false/show_text with no BattleState and no yield.  ScriptRunner
  -- resolves the live Commands.start_battle when no mod overrides it, so this
  -- monkeypatch intercepts the onStep challenge (Commands.resolve).
  local Commands = require("src.script.Commands")
  local origStartBattle = Commands.start_battle
  local winResult = true
  Commands.start_battle = function(ctx, _kind, _a, _b)
    ctx.lastBattleResult = winResult and "win" or "lose"
    ctx.lastCheck = winResult -- Rival1: check = (result == "win")
    return nil
  end

  local function restore()
    TextBox.new = origNew
    Commands.start_battle = origStartBattle
  end

  -- Set the pre-battle flag state AND clear the rival's object toggle.  The
  -- WIN sequence ends with hide_object OAKSLAB_RIVAL, which persists as
  -- save.objectToggles.OAKS_LAB.OAKSLAB_RIVAL = false; without clearing it the
  -- LOSS re-teleport spawns with the rival hidden and onStep (which returns
  -- false when npcByIndex(1) is nil) never fires the challenge.  Must run
  -- BEFORE U.teleport, since the map spawns its objects on push.
  local function resetSave()
    local flags = game.save.flags or {}
    game.save.flags = flags
    flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
    flags.EVENT_GOT_STARTER = true
    flags.EVENT_CHOSE_SQUIRTLE = true
    flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
    if game.save.objectToggles and game.save.objectToggles.OAKS_LAB then
      game.save.objectToggles.OAKS_LAB.OAKSLAB_RIVAL = nil
    end
  end

  local function seenHas(sub)
    for _, t in ipairs(seen) do
      if t:find(sub, 1, true) then return true end
    end
    return false
  end

  -- Walk down onto the y>=6 trigger, then page through the post-battle boxes
  -- and the walk-out.  Bounded so the window always quits.  Captures the exit
  -- line box the first time "Smell you later" appears, and a final overworld
  -- shot once Blue has despawned (hide_object at the end of the sequence).
  local function drive(smellShot, endShot)
    local grabbedSmell = false
    for _ = 1, 500 do
      if (not grabbedSmell) and seenHas("Smell you later") then
        U.wait(18) -- let the typewriter reveal the line before the shot
        U.shot(game, smellShot)
        grabbedSmell = true
      end
      local rival = game.overworld:npcByIndex(1)
      if rival == nil then break end -- rival walked out + hid: sequence done
      -- before the trigger fires the player must step down onto y>=6; after,
      -- A pages every text box (IllTakeYouOn, IPicked, SmellYouLater)
      local p = game.overworld.player
      if p and (p.cellY or 0) < 6 then
        U.hold(game, "down", 8)
      end
      U.tap(game, "a")
      U.wait(3)
    end
    U.wait(6)
    U.shot(game, endShot)
    return grabbedSmell
  end

  -- ---- Scenario WIN
  resetSave()
  U.teleport(game, "OAKS_LAB", 4, 5, "down")
  U.wait(6)
  winResult = true
  seen = {}
  do
    local p = game.overworld.player
    U.log("WIN start cell:", tostring(p.cellX), tostring(p.cellY),
          "rival:", tostring(game.overworld:npcByIndex(1) ~= nil))
  end
  U.shot(game, DIR .. "/win_before.png")
  drive(DIR .. "/win_smell.png", DIR .. "/win_end.png")
  local winGloat = seenHas("picked the")
  local winSmell = seenHas("Smell you later")
  local winPass = winGloat and winSmell
  U.log("WIN gloat(picked the):", tostring(winGloat),
        "exit(Smell you later):", tostring(winSmell))
  U.log("WIN", winPass and "PASS" or "FAIL")

  -- ---- Scenario LOSS
  resetSave()
  U.teleport(game, "OAKS_LAB", 4, 5, "down")
  U.wait(6)
  winResult = false
  seen = {}
  do
    local p = game.overworld.player
    U.log("LOSS start cell:", tostring(p.cellX), tostring(p.cellY),
          "rival:", tostring(game.overworld:npcByIndex(1) ~= nil))
  end
  U.shot(game, DIR .. "/loss_before.png")
  drive(DIR .. "/loss_smell.png", DIR .. "/loss_end.png")
  local lossGloat = seenHas("picked the")
  local lossSmell = seenHas("Smell you later")
  -- loss must skip the win gloat but still print the shared exit line
  local lossPass = lossSmell and (not lossGloat)
  U.log("LOSS gloat(picked the):", tostring(lossGloat),
        "exit(Smell you later):", tostring(lossSmell))
  U.log("LOSS", lossPass and "PASS" or "FAIL")

  -- restore hooks before any assert so a failure can't leave them installed
  restore()

  U.log("RESULT bug231", (winPass and lossPass) and "PASS" or "FAIL")
  assert(winPass,
    "WIN: after the first lab rival battle Blue must gloat "
    .. "('I picked the wrong POKéMON!') AND say the exit line "
    .. "('Smell you later'); got gloat=" .. tostring(winGloat)
    .. " exit=" .. tostring(winSmell))
  assert(lossPass,
    "LOSS: after losing the first lab rival battle Blue must skip the gloat "
    .. "but STILL say the exit line ('Smell you later'); got gloat="
    .. tostring(lossGloat) .. " exit=" .. tostring(lossSmell))
end
