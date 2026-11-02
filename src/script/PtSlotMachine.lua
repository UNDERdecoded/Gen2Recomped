-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SLOT MACHINE SESSION: ScrCmd_267 (`267 <machineVar>`) ->
-- sub_0203E414 / sub_0203E35C (pokeplatinum src/unk_0203D1B8.c).
--
-- The field side of a session, READ from the decomp:
--   * the machine's setting (sub_0203E484): the twelve machines' settings
--     {0,5,1,1,4,4,2,2,2,3,3,3} shuffled with the LCRNG seeded from the
--     player's record-mixed random (RecordMixedRNG_GetRand -- the same
--     entry the swarm daily is drawn from; the port keeps it as
--     save.gen4Swarm.rand), and the machine's own entry read out;
--   * the coin count handed to the app and written back afterwards;
--   * records 4 (sub_0206DD38): kept when the player leaves with at least
--     1000 coins more than they sat down with, with the minutes played;
--   * the consecutive bonus-round wins (SystemVars_SetConsecutiveBonusRound
--     Wins), raised to the session's count when it beats the saved one --
--     what `checkbonusroundstreak` reads (save.gen4BonusRoundStreak).
--
-- THE APP ITSELF (overlay 101: reels, lottery, bonus rounds) is
-- src/ui/PtSlotMachineApp.lua over src/script/PtSlotLogic.lua, on the
-- data/slot.narc art (Gen4PtSlotArt). `M.app` is the hook: a function(ctx,
-- args) that plays and returns { coins = n, bonusWins = n } (yielding the
-- script while the app is up). A cache without the art (an import from
-- before platinum-slot-app-v1) gets no app: the session opens and closes on
-- the same coin count, which is what the bookkeeping then sees.

local Logger = require("src.core.Logger")

local M = {}

M.SETTINGS = { [0] = 0, 5, 1, 1, 4, 4, 2, 2, 2, 3, 3, 3 }
M.COUNT = 12
M.app = function(ctx, args)
  return require("src.ui.PtSlotMachineApp").run(ctx, args)
end

local TWO32 = 4294967296

-- seed * 0x41C64E6D + 0x6073 mod 2^32, exact in doubles (16-bit halves)
local function lcrngStep(seed)
  local lo, hi = seed % 65536, math.floor(seed / 65536)
  local mlo, mhi = 0x4E6D, 0x41C6
  local v = lo * mlo + ((lo * mhi + hi * mlo) % 65536) * 65536 + 0x6073
  return v % TWO32
end
M.lcrngStep = lcrngStep

-- sub_0203E484
function M.setting(seed, machine)
  local s = (tonumber(seed) or 0) % TWO32
  local v = {}
  for i = 0, M.COUNT - 1 do v[i] = M.SETTINGS[i] end
  for i = 0, M.COUNT - 1 do
    for _ = i + 1, M.COUNT - 1 do
      s = lcrngStep(s)
      local slot = math.floor(s / 65536) % M.COUNT
      v[i], v[slot] = v[slot], v[i]
    end
  end
  return v[math.floor(tonumber(machine) or 0) % 256] or 0
end

local function mixedRand(save)
  local s = type(save) == "table" and save.gen4Swarm
  return type(s) == "table" and tonumber(s.rand) or 0
end

-- sub_0203E35C state 1, once the app has closed
function M.finish(save, startCoins, endCoins, minutes, bonusWins)
  local GC = require("src.import.Gen4GameCorner")
  local recorded = false
  pcall(function()
    recorded = require("src.script.PtTvRecords").slotsRecord(save, startCoins, endCoins, minutes)
  end)
  save.coins = math.max(0, math.min(GC.MAX_COINS, math.floor(tonumber(endCoins) or 0)))
  local wins = math.floor(tonumber(bonusWins) or 0)
  if wins > (tonumber(save.gen4BonusRoundStreak) or 0) then save.gen4BonusRoundStreak = wins end
  return recorded
end

local function valueOf(ctx, n)
  return math.floor(tonumber(require("src.script.Gen4Commands").valueOf(ctx, n)) or 0)
end

function M.install(L)
  local Commands = require("src.script.Commands")
  -- the machine id is a var (ScriptContext_GetVar)
  L["267"] = function(ins, s)
    s.out[#s.out + 1] = { "pt_slot_machine", ins.args and ins.args[1] }
  end
  function Commands.pt_slot_machine(ctx, machineVar)
    local save = ctx.save
    local machine = valueOf(ctx, machineVar)
    local GC = require("src.import.Gen4GameCorner")
    local args = { machine = machine, setting = M.setting(mixedRand(save), machine),
                   coins = GC.coins(save), bonusWins = 0 }
    M.lastSession = args
    local started = os.time()
    local result
    if M.app then
      result = M.app(ctx, args)
    else
      Logger.info("gen4 script: slot machine %d (setting %d) -- the slot app (overlay 101) is not ported",
                  machine, args.setting)
    end
    result = result or args
    local minutes = math.floor((os.time() - started) / 60)
    args.recorded = M.finish(save, args.coins, result.coins or args.coins, minutes, result.bonusWins)
  end
  Commands.meta.pt_slot_machine = { foreground = true, blocking = true }
end

return M
