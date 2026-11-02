-- src/script/HgssPhoneCallCommands.lua -- HEARTGOLD / SOULSILVER'S SCRIPTED
-- POKEGEAR CALLS.
--
-- Nine overworld scripts reach `PhoneCall who, b, c` (asm/macros/script.inc):
-- Elm on Route 30 / in Violet, Cianwood, Olivine, Mahogany, Blackthorn, Mom on
-- Route 30, Oak in Viridian, Baoba in Olivine. The macro puts its operands in
-- VAR_SPECIAL_x8004..6 and calls std_phone_call (scr_seq_0003):
--
--   SetPhoneCall x8004, x8005, x8006   GearPhoneRingManager_SetCallerParams
--                                      (callerId, 0xFF, 0, isScriptedCall = b,
--                                      callScriptID = c); starts the ring
--   PlaySE / WaitSE SEQ_SE_GS_PHONE0 x2, FadeScreen to black
--   RunPhoneCall                       PokegearPhone_LaunchApp, and the script
--                                      waits for the application to close
--   RestoreOverworld, FadeScreen back
--
-- The call itself is src/ui/HgssPhoneCall.lua. UnsetPhoneCallTrigger <id>
-- (PhoneCallPersistentState_ClearCallTriggerFlag) is kept beside them: the
-- trigger flags are the ring manager's, and it is the one phone command left
-- unlowered (GetPhoneBookRematch and LoadPhoneDat are aliased to their
-- no-phone answers in Gen4HgssScriptAliases).
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

local function valueOf(ctx, n) return require("src.script.Gen4Commands").valueOf(ctx, n) end

-- ScrCmd_SetPhoneCall: three ScriptGetVar operands, kept as u8 by the ring
-- manager; a caller past NUM_PHONE_CONTACTS (75) is 0xFF (GF_ASSERT)
function Commands.g4_hgss_set_phone_call(ctx, who, kind, id)
  local game = ctx.game
  if not game then return end
  local caller = math.floor(valueOf(ctx, who) or 0) % 256
  game.hgssPhoneCall = {
    caller = caller < 75 and caller or 0xFF,
    kind = math.floor(valueOf(ctx, kind) or 0) % 256,
    id = math.floor(valueOf(ctx, id) or 0) % 256,
  }
end

-- ScrCmd_RunPhoneCall: the Pokegear's phone with the call connected; the
-- script resumes when the player has closed the Pokegear
function Commands.g4_hgss_run_phone_call(ctx)
  local game = ctx.game
  local call = game and game.hgssPhoneCall
  local UI = require("src.ui.HgssPhoneCall")
  if not (call and call.caller ~= 0xFF and game.stack and UI.available(game)) then
    Logger.warn("hgss phone: no call to run (%s) or the phone data is not in this cache "
                .. "(re-import HeartGold / SoulSilver: gen4_hgss_phone_call)", call and tostring(call.caller) or "none set")
    return
  end
  local runner = ctx.runner
  game.stack:push(UI.new(game, call, function() if runner then runner:resume() end end, ctx))
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_run_phone_call = { foreground = true, blocking = true }

-- UnsetPhoneCallTrigger <byte>: clears one of the persistent call-trigger
-- flags (Mom's "bought something" call is the script that does it)
function Commands.g4_hgss_unset_phone_trigger(ctx, id)
  local save = ctx.save
  if not save then return end
  save.hgssPhoneCallTriggers = save.hgssPhoneCallTriggers or {}
  save.hgssPhoneCallTriggers[math.floor(tonumber(id) or 0)] = nil
end

-- ScrCmd_148 <trigger, bump> (sub_02092E14): sets one of the ring manager's
-- call triggers (src/world/HgssPhoneRing.lua); Elm's Pokerus call
function Commands.g4_hgss_set_phone_trigger(ctx, id, bump)
  local game = ctx.game
  if not game then return end
  require("src.world.HgssPhoneRing").setTrigger(game, math.floor(tonumber(id) or 0), (tonumber(bump) or 0) ~= 0)
end

function M.install(L)
  L.scrcmd_148 = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_set_phone_trigger", ins.args[1], ins.args[2] }
  end
  L.setphonecall = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_set_phone_call", ins.args[1], ins.args[2], ins.args[3] }
  end
  L.runphonecall = function(_, s) s.out[#s.out + 1] = { "g4_hgss_run_phone_call" } end
  L.unsetphonecalltrigger = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_unset_phone_trigger", ins.args[1] }
  end
end

return M
