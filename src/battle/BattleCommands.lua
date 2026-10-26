-- Native command dispatch shared by BattleState input and mod.battle intents.
-- Keep gameplay mutations here, after the mod facade's admission checks.
local Strings = require("src.core.Strings")
local Targeting = require("src.battle.Targeting")
local Commands, Methods = {}, {}
Commands.methods = Methods

function Methods.chooseMenu(self, choice)
  -- BattleMenu_Pack `.contest` (core.asm:4990): `ld a, PARK_BALL /
  -- ld [wCurItem], a / call DoItemEffect`.  No pack, no submenu -- the
  -- third slot IS the ball, so the item action becomes the throw.
  if choice == "item" and self.bugContest then
    self:bugContestBall()
    return true
  end
  if choice == "fight" and self.ghost then
    self:say(Strings("%s is too\nscared to move!", self.player.name))
    self.phase = "messages"
    self.afterQueue = "menu"
    self:act(function()
      self:executeAction(self.enemy, self.player, self:enemyAction())
    end)
    self:act(function()
      self:endOfTurn()
    end)
  elseif choice == "fight" then
    -- After the menu: own trapping/Bide or foe Wrap skips the move
    -- list and forces the locked action (core.asm:320-329)
    local fightLock = self:fightLockedAction(self.player)
    if fightLock then
      self:resolveTurn(fightLock)
      return true
    end
    local who = self:menuBattler()
    if not self:playerHasPP(who) then
      -- _NoMovesLeftText, then Struggle engages
      self:say(Strings("%s has no\nmoves left!", who.name))
      self:chooseAction({ id = "STRUGGLE", pp = 1, struggle = true })
      return true
    end
    self.phase = "moveSelect"
    self.moveIndex = math.min(self.moveIndex, #who.curMoves)
    self.moveSwapIndex = nil
  elseif choice == "run" then
    self:tryRun()
  elseif choice == "item" then
    self:openItems()
  else
    self:openParty()
  end
  return true
end

function Methods.chooseMove(self, index)
  local chooser = self:menuBattler()
  local moves = chooser.curMoves
  self.moveIndex = index
  local mv = moves[self.moveIndex]
  local mvDef = mv and self.data.moves[mv.id]
  local nativeReason = require("src.battle.Gen3MoveSelection").manualReason(self, chooser, mv, self.moveIndex)
  if require("src.core.GameVersion").isGen3() and not nativeReason then
    if Targeting.needsChoice(self, self:choosingBattler(), mvDef) then
      self.pendingMove = mv
      self.targetChoices = Targeting.choices(self, self:menuBattler())
      self.targetIndex, self.phase = 1, "targetSelect"
    else
      self:chooseAction(mv)
    end
    return true
  elseif nativeReason then
    local message
    if nativeReason == "choice" then
      local locked
      for _, def in pairs(self.data.moves) do
        if require("src.battle.Gen3ChoiceBand").identity(self, def) == chooser.choicedMove then locked = def; break end
      end
      local item = require("src.battle.HoldItems").defOf(chooser)
      message = Strings("%s allows use of\nonly %s!", item and item.name or "CHOICE BAND",
        locked and locked.name or tostring(chooser.choicedMove))
    elseif nativeReason == "pp" then
      message = self:romText("_MoveNoPPText", "No PP left for\nthis move!")
    elseif nativeReason == "disabled" then
      message = self:romText("_MoveDisabledText", "The move is\ndisabled!")
    elseif nativeReason == "taunt" then
      message = Strings("%s can't use\n%s after the\ntaunt!", chooser.name, mvDef and mvDef.name or mv.id)
    elseif nativeReason == "torment" then
      message = Strings("%s can't use the\nsame move twice in\na row due to the\nTORMENT!", chooser.name)
    elseif nativeReason == "imprison" then
      message = Strings("%s can't use the\nsealed %s!", chooser.name, mvDef and mvDef.name or mv.id)
    else
      message = Strings("That move can't\nbe selected!")
    end
    self:say(message)
    self.phase, self.afterQueue = "messages", "moveSelect"
    return true
  end
  if require("src.battle.Gen3Disable").blocked(chooser, mv, self.moveIndex) then
    self:say(self:romText("_MoveDisabledText", "The move is\ndisabled!"))
    self.phase = "messages"
    self.afterQueue = "menu"
  -- TAUNT and TORMENT refuse the move at SELECTION rather than after the
  -- fact, the way DISABLE already does, so the player is never told to
  -- pick again for something the game was never going to allow.
  elseif self.bw and require("src.battle.Gen5MoveRules").moveBlocked(self, chooser, mvDef, true) then
    -- BLACK AND WHITE: the Choice lock, Imprison, Gravity, Heal Block
    self:say(require("src.battle.Gen5MoveRules").moveBlocked(self, chooser, mvDef, true))
    self.phase = "messages"
    self.afterQueue = "menu"
  elseif self:tauntBlocks(chooser, mvDef) then
    self:say(Strings("%s can't use\n%s after the\ntaunt!", chooser.name, mvDef and mvDef.name or mv.id))
    self.phase = "messages"
    self.afterQueue = "menu"
  elseif self:tormentBlocks(chooser, mvDef) then
    self:say(Strings("%s can't use the\nsame move twice in\na row due to the\nTORMENT!", chooser.name))
    self.phase = "messages"
    self.afterQueue = "menu"
  elseif mv.pp <= 0 then
    self:say(self:romText("_MoveNoPPText", "No PP left for\nthis move!"))
    self.phase = "messages"
    self.afterQueue = "menu"
  elseif Targeting.needsChoice(self, self:choosingBattler(), mvDef) then
    -- WHICH OF THE TWO, when the move takes one and there are two.
    --
    -- Emerald's selector cycles over the legal slots and names the
    -- candidate; nothing else in the menu changes.  A single battle
    -- never gets here, because needsChoice answers false whenever there
    -- is only one thing to aim at -- and on the Game Boy cartridges the
    -- moves carry no target byte at all, so it answers false for every
    -- move in the game.
    self.pendingMove = mv
    self.targetChoices = Targeting.choices(self, self:menuBattler())
    self.targetIndex = 1
    self.phase = "targetSelect"
  else
    self:chooseAction(mv)
  end
  return true
end

function Methods.chooseTarget(self, index)
  local list = self.targetChoices or {}
  self.targetIndex = index
  local mv = self.pendingMove
  local pick = list[self.targetIndex]
  self.pendingMove, self.targetChoices = nil, nil
  self.chosenTargets = self.chosenTargets or {}
  local who = self:menuBattler()
  if who and who.position then
    self.chosenTargets[who.position] = pick
  end
  self:chooseAction(mv)
  return true
end

function Methods.chooseMimic(self, index)
  local moves = self.mimicMoves
  self.mimicIndex = index
  local pick = moves[self.mimicIndex]
  local ctx = self.mimicCtx
  self.mimicMoves, self.mimicCtx = nil, nil
  self.phase = "messages"
  self.nextInsert = 0 -- the copy's anim + text go to the queue head
  self:applyMimic(ctx.user, ctx.target, ctx.moveInst, pick.slot)
  return true
end

local SAFARI_INDEX = { ball = 1, bait = 2, rock = 3, run = 4 }
function Methods.chooseSafari(self, action)
  self.menuIndex = SAFARI_INDEX[action]
  self:safariAction(action)
  return true
end

local function backToFirst(self)
  if not self:isDouble() or self:choosingSlotNow() ~= 2 then
    return nil
  end
  local left = self:battlerAt(0)
  local pending = self.pendingActions and self.pendingActions[0]
  if
    left
    and not left.ally
    and (left.mon and left.mon.hp or 0) > 0
    and pending
    and not self:menuLockedAction(left)
  then
    return left
  end
end
function Methods.cancelMove(self)
  if self.phase == "moveSelect" then
    self.moveSwapIndex, self.phase = nil, "menu"
  elseif self.phase == "targetSelect" then
    self.pendingMove, self.targetChoices = nil, nil
    self.phase = "moveSelect"
  elseif self.phase == "menu" and backToFirst(self) then
    self.pendingActions[0] = nil
    if self.chosenTargets then
      self.chosenTargets[0] = nil
    end
    self.choosingSlot, self.menuIndex, self.moveIndex = 0, 1, 1
    pcall(function()
      require("src.core.Sound").play(self.game.data, "SEQ_SE_DP_DECIDE")
    end)
  else
    return nil, "nothing to cancel"
  end
  return true
end

local function moveReason(b, actor, slot, move)
  if not move or not b.data.moves[move.id] then
    return "invalid move slot"
  end
  if require("src.core.GameVersion").isGen3() then
    local why = require("src.battle.Gen3MoveSelection").manualReason(b, actor, move, slot)
    if why == "disabled" then return "move is disabled" end
    if why == "pp" then return "move has no PP" end
    if why == "taunt" then return "move is blocked by Taunt" end
    if why == "torment" then return "move is blocked by Torment" end
    return why and ("move is blocked by native GBA rules: " .. why) or nil
  end
  if require("src.battle.Gen3Disable").blocked(actor, move, slot) then
    return "move is disabled"
  end
  if (move.pp or 0) <= 0 then
    return "move has no PP"
  end
  local def = b.data.moves[move.id]
  if b.bw and require("src.battle.Gen5MoveRules").moveBlocked(b, actor, def, true) then
    return "move is blocked by native BW rules"
  end
  if b:tauntBlocks(actor, def) then
    return "move is blocked by Taunt"
  end
  if b:tormentBlocks(actor, def) then
    return "move is blocked by Torment"
  end
end

-- Admission checks are read-only. Native refusal messages still belong to
-- chooseMove when driven by ordinary input; invalid API requests do not act.
function Commands.reason(b, intent)
  if b.kind == "link" or b.spectating or b.demo or b.dudeDemo or b.pokedudeDemo or b.palace or b.arena then
    return "battle controller owns input"
  end
  if b.result or b.dead or b.waitingUI then
    return "battle is not ready"
  end
  if intent.kind == "safari" then
    if b.phase ~= "menu" or not b.safari then
      return "safari menu is not active"
    end
    if (b.safari.balls or 0) <= 0 then
      return "no safari balls remain"
    end
    return
  end
  if b.safari then
    return "safari controller owns input"
  end
  local actor = intent.kind == "mimic" and b.mimicCtx and b.mimicCtx.user or b:menuBattler()
  if not (actor and actor.mon) or actor.ally or (actor.mon.hp or 0) <= 0 then
    return "player battler is not ready"
  end
  if
    intent.kind ~= "mimic"
    and (
      b:menuLockedAction(actor)
      or actor.mustRecharge
      or actor.charging
      or actor.rageMove
      or (actor.thrashTurns and actor.thrashTurns > 0)
    )
  then
    return "player battler is locked"
  end
  if intent.kind == "menu" then
    if b.phase ~= "menu" then
      return "battle menu is not active"
    end
    local acting = b.player or b:activeOn(1)
    if not acting or (acting.mon.hp or 0) <= 0 or b:menuLockedAction(acting) then
      return "battle menu is not ready"
    end
  elseif intent.kind == "move" then
    if b.phase ~= "moveSelect" then
      return "move menu is not active"
    end
    if b.moveSwapIndex then
      return "move reorder is active"
    end
    return moveReason(b, actor, intent.slot, (actor.curMoves or {})[intent.slot])
  elseif intent.kind == "target" then
    if b.phase ~= "targetSelect" then
      return "target menu is not active"
    end
    local move, slot = b.pendingMove, nil
    for index, mv in ipairs(actor.curMoves or {}) do
      if mv == move then
        slot = index
        break
      end
    end
    if not slot then
      return "pending move is no longer current"
    end
    local reason = moveReason(b, actor, slot, move)
    if reason then
      return reason
    end
    if not Targeting.needsChoice(b, actor, b.data.moves[move.id]) then
      return "target choice is no longer needed"
    end
    local pick = b:battlerAt(intent.target)
    if not (pick and pick.mon and (pick.mon.hp or 0) > 0) then
      return "target is not on the field"
    end
    local offered = false
    for _, target in ipairs(b.targetChoices or {}) do
      if target == pick then
        offered = true
        break
      end
    end
    if not offered then
      return "target is not in the current selector"
    end
    for _, target in ipairs(Targeting.choices(b, actor)) do
      if target == pick then
        return
      end
    end
    return "target is no longer eligible"
  elseif intent.kind == "back" then
    if b.phase == "moveSelect" or b.phase == "targetSelect" or (b.phase == "menu" and backToFirst(b)) then
      return
    end
    return "nothing to cancel"
  elseif intent.kind == "mimic" then
    if b.phase ~= "mimicSelect" then
      return "mimic menu is not active"
    end
    local ctx, pick = b.mimicCtx, (b.mimicMoves or {})[intent.index]
    if not ctx or not pick or ctx.user ~= actor or not ctx.target or not ctx.moveInst then
      return "invalid mimic context"
    end
    local targetPresent = false
    for pos = 0, 3 do
      if b:battlerAt(pos) == ctx.target then
        targetPresent = true
      end
    end
    if not targetPresent or #(actor.curMoves or {}) == 0 then
      return "invalid mimic context"
    end
    local onField = false
    for _, pos in ipairs({ 0, 2 }) do
      if b:battlerAt(pos) == actor then
        onField = true
      end
    end
    if not onField then
      return "mimic user is no longer on the field"
    end
    local source = (ctx.target.curMoves or {})[pick.slot]
    if not source or source.id ~= pick.id then
      return "mimic option is no longer current"
    end
  else
    return "unknown battle intent"
  end
end

local DISPATCH = {
  menu = "chooseMenu",
  move = "chooseMove",
  target = "chooseTarget",
  back = "cancelMove",
  safari = "chooseSafari",
  mimic = "chooseMimic",
}
function Commands.dispatch(b, intent)
  -- Ordinary input already performs this at its menu boundary.
  if b.phase == "menu" and not b.safari then
    b:clearTurnFlinches()
  end
  if intent.kind == "target" then
    local pick = b:battlerAt(intent.target)
    for index, target in ipairs(b.targetChoices or {}) do
      if target == pick then
        return b:chooseTarget(index)
      end
    end
    return nil, "target is not in the current selector"
  end
  local value = intent.choice or intent.slot or intent.action or intent.index
  return b[DISPATCH[intent.kind]](b, value)
end
return Commands
