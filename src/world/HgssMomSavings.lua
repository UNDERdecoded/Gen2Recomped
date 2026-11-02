-- HEARTGOLD / SOULSILVER: MOM'S SAVINGS AND SHOPPING -- the money cut per
-- battle and the things she buys with it.
--
-- pokeheartgold, read off:
--
--   * THE SWITCH. FLAG_SYS_MOMS_SAVINGS (0x986, sys_flags.c
--     Save_VarsFlags_MomsSavingsFlagAction / Check). Her house script
--     (scr_seq_0845 T20R0201) and her phone call (phone_scripts_mother.c
--     GearPhoneCall_Mother, src/ui/HgssPhoneCall.lua) set and clear it.
--   * THE BALANCE. PhoneCallPersistentState.bankBalance (save_pokegear.c
--     PhoneCallPersistentState_MomSavings_BalanceAction: SET / ADD capped at
--     999,999 / SUB floored at 0) -- `save.hgssMomSavings` here, which the
--     field's CheckBankBalance / BankOrWalletIsFull already read.
--   * THE CUT. battle_setup.c sub_0205230C, from sub_0205239C as every
--     battle hands its profile back to the field: with the switch on, a
--     quarter of what the wallet GAINED over the battle -- (after - before)
--     / 4, a signed int division -- moves to the bank, trimmed so the bank
--     stops at 999,999. A battle that lost money banks nothing. Either way
--     MomGift_TryEnqueueGiftOnBalanceChange runs, and when it buys something
--     the ring manager's trigger 12 (CALL_TRIGGER_MOM_BOUGHT_SOMETHING) is
--     set with the clock bumped (sub_02092E14(..., 12, TRUE)).
--   * THE BATTLE LINE. BattleSetup.momsSavingsActive is the switch while the
--     bank is under 999,999 (battle_setup.c 242); BtlCmd_PayPrizeMoney hands
--     it to subscript_0004_BattleWin, which prints msg_0197_01275 ("...for
--     winning! Sent some to Mom!") instead of msg_0197_00033.
--   * THE SHOPPING (mom_gift.c). Nine one-off buys, in order, each once the
--     balance reaches its threshold (the bought bits are unk_144), every buy
--     queued and its cost taken off the balance it is compared at next; the
--     loop stops at the first threshold not reached or a full queue. Only
--     when none of them was bought: crossing a 3,000 boundary (new / 3000 >
--     old / 3000, on the balances before any cost) buys one of seventeen
--     berry packs at random -- 5 berries for 100.
--   * THE QUEUE. momGiftQueue[5] {item, quantity}: Put fills the first empty
--     slot, Get drops slot 0 and shifts, full when slot 4 holds anything --
--     `save.hgssMomGifts` (a list, front first). The Poke Mart deliveryman
--     (scr_seq_0144: MomGiftCheck, ScrCmd_811 / 812, UnsetPhoneCallTrigger
--     12; src/script/HgssMiscCommands.lua) hands them over.
--   * HER CALL. Trigger 12 is { Mom, PHONE_SCRIPT_027 } (ov02_02253C84), an
--     incoming call the handler answers with its predefined script, 664 29.

local M = {}

M.FLAG_SAVING = 0x986
M.MAX = 999999
M.QUEUE = 5
M.TRIGGER = 12
M.BERRY_THRESHOLD = 3000

-- sGiftNormalTable: item, threshold, cost (constants/items.h ids)
M.NORMAL = {
  { 26, 900, 600 },     -- Super Potion
  { 79, 4000, 270 },    -- Repel
  { 26, 7000, 600 },    -- Super Potion
  { 251, 10000, 100 },  -- Silk Scarf
  { 81, 15000, 3000 },  -- Moon Stone
  { 25, 19000, 900 },   -- Hyper Potion
  { 287, 30000, 200 },  -- Choice Scarf
  { 266, 40000, 200 },  -- Muscle Band
  { 275, 50000, 200 },  -- Focus Sash
}
-- sGiftBerryTable: Occa .. Chilan (items 184 .. 200), 5 each for 100
M.BERRIES = {}
for i = 0, 16 do M.BERRIES[i + 1] = { 184 + i, 5, 100 } end

local function flagKey(id) return ("FLAG_G4_%04X"):format(id) end

function M.isHgss()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.family and GV.family() == "hgss" or false
end

function M.saving(save)
  return ((save or {}).flags or {})[flagKey(M.FLAG_SAVING)] == true
end

function M.balance(save) return math.floor(tonumber(save and save.hgssMomSavings) or 0) end

-- PhoneCallPersistentState_MomSavings_BalanceAction: 0 get, 1 set, 2 add, 3 sub
function M.balanceAction(save, action, n)
  local b = M.balance(save)
  n = math.floor(tonumber(n) or 0)
  if action == 1 then b = n
  elseif action == 2 then b = math.min(M.MAX, b + n)
  elseif action == 3 then b = (b < n) and 0 or (b - n) end
  if action ~= 0 then save.hgssMomSavings = b end
  return b
end

function M.queue(save)
  if type(save.hgssMomGifts) ~= "table" then save.hgssMomGifts = {} end
  return save.hgssMomGifts
end
function M.queueFull(save) return #M.queue(save) >= M.QUEUE end
-- PhoneCallPersistentState_MomGiftQueue_Put: the first empty slot, if any
function M.put(save, item, qty)
  local q = M.queue(save)
  if #q < M.QUEUE then q[#q + 1] = { item = item, quantity = qty } end
end

-- unk_144: the nine normal buys already made (sub_0202F198 / sub_0202F1B4)
local function bought(save, i)
  local b = math.floor(tonumber(save.hgssMomGiftsBought) or 0)
  return math.floor(b / 2 ^ i) % 2 == 1
end
local function markBought(save, i)
  if i < 9 and not bought(save, i) then
    save.hgssMomGiftsBought = math.floor(tonumber(save.hgssMomGiftsBought) or 0) + 2 ^ i
  end
end

-- MomSavings_ProcessNormalGifts
local function processNormal(save, balance)
  local count = 0
  for i, e in ipairs(M.NORMAL) do
    if not bought(save, i - 1) then
      if balance < e[2] then break end
      markBought(save, i - 1)
      M.put(save, e[1], 1)
      balance = M.balanceAction(save, 3, e[3])
      count = count + 1
      if M.queueFull(save) then break end
    end
  end
  return count ~= 0
end

-- MomGift_TryEnqueueGiftOnBalanceChange; `rand(n)` answers 0 .. n-1 (LCRandom % n)
function M.tryEnqueue(save, newBalance, oldBalance, rand)
  if M.queueFull(save) then return false end
  if processNormal(save, newBalance) then return true end
  if math.floor(newBalance / M.BERRY_THRESHOLD) <= math.floor(oldBalance / M.BERRY_THRESHOLD) then
    return false
  end
  local idx = (rand or function(n) return math.random(0, n - 1) end)(#M.BERRIES)
  local berry = M.BERRIES[idx + 1]
  M.put(save, berry[1], berry[2])
  M.balanceAction(save, 3, berry[3])
  return true
end

-- sub_0205230C: the wallet before and after the battle; answers whether she
-- bought something (and has rung the trigger)
function M.settle(game, before, after)
  local save = game and game.save
  if not (save and M.saving(save)) then return false end
  local delta = after - before
  -- (int)(money2 - money1) / 4: C division truncates toward zero
  delta = delta >= 0 and math.floor(delta / 4) or -math.floor(-delta / 4)
  local old = M.balance(save)
  local result = old
  if delta > 0 then
    if old + delta >= M.MAX then delta = M.MAX - old end
    save.money = after - delta
    result = M.balanceAction(save, 2, delta)
  end
  if M.tryEnqueue(save, result, old) then
    local ok, Ring = pcall(require, "src.world.HgssPhoneRing")
    if ok then Ring.setTrigger(game, M.TRIGGER, true) end
    return true
  end
  return false
end

-- BattleState:enter -- BattleSetup's copy of the profile and momsSavingsActive
function M.battleEntered(battle)
  if not (battle and battle.game and battle.game.save and M.isHgss()) then return end
  if battle.hgssMoneyBefore ~= nil then return end
  local save = battle.game.save
  battle.hgssMoneyBefore = math.floor(tonumber(save.money) or 0)
  battle.hgssMomActive = M.saving(save) and M.balance(save) < M.MAX
end

-- BattleState:finish -- sub_0205239C handing the profile back
function M.battleFinished(battle)
  if not (battle and battle.hgssMoneyBefore ~= nil) or battle.hgssMomSettled then return end
  battle.hgssMomSettled = true
  local game = battle.game
  if battle.demo or battle.pokedudeDemo then return end
  M.settle(game, battle.hgssMoneyBefore, math.floor(tonumber(game.save.money) or 0))
end

-- the prize line: msg_0197_01275 while momsSavingsActive, else nil (the
-- battle's own msg_0197_00033 line)
function M.prizeLine(battle, prize)
  if not (battle and battle.hgssMomActive) then return nil end
  local game = battle.game
  local T = require("src.import.Gen4Text")
  local saved = game.stringBuffers
  game.stringBuffers = {}
  for k, v in pairs(saved or {}) do game.stringBuffers[k] = v end
  game.stringBuffers[1] = tostring(game.save.player and game.save.player.name or "")
  game.stringBuffers[2] = tostring(prize)
  local ok, text = pcall(T.resolve, game.data, 197, 1275, game)
  game.stringBuffers = saved
  if ok and type(text) == "string" and text ~= "" then return text end
  return ("%s got %s%d for winning!\nSent some to Mom!"):format(
    tostring(game.save.player and game.save.player.name or ""),
    require("src.core.GameVersion").moneySign(), prize)
end

-- GetMaxBankTransactionAmount: 0 deposit (the wallet, up to the bank's
-- room), 1 withdraw (the bank, up to the wallet's room)
function M.maxTransaction(save, mode)
  local wallet = math.floor(tonumber(save.money) or 0)
  local bank = M.balance(save)
  if mode == 0 then return math.min(wallet, M.MAX - bank) end
  return math.min(bank, M.MAX - wallet)
end

-- ScrCmd_BankTransaction / sub_020479D4: the amount picked (0 or B answers 1,
-- cancelled), then PlayerProfile_Sub/AddMoney and the bank ADD / SUB, and 0.
-- The cartridge's picker is the touch screen's keypad (ov01_021F6A9C mode 5,
-- not ported); the amount is entered on the six-digit dial (src/ui/MoneyEntry).
function M.transaction(ctx, mode, destVar, setResult)
  local game, save, runner = ctx.game, ctx.save, ctx.runner
  local max = math.max(0, M.maxTransaction(save, mode))
  local picked, done = nil, false
  local function apply()
    if not picked or picked <= 0 then setResult(1) return end
    picked = math.min(picked, max)
    if mode == 0 then
      save.money = math.max(0, math.floor(tonumber(save.money) or 0) - picked)
      M.balanceAction(save, 2, picked)
    else
      save.money = math.min(M.MAX, math.floor(tonumber(save.money) or 0) + picked)
      M.balanceAction(save, 3, picked)
    end
    setResult(0)
  end
  -- a test or a mod can answer the dial without a screen
  if type(M.autoAmount) == "function" then
    picked = M.autoAmount(mode, max)
    return apply()
  end
  require("src.ui.Screens").push(game, "MoneyEntry", {
    max = max,
    onDone = function(v)
      picked, done = v, true
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
  apply()
end

return M
