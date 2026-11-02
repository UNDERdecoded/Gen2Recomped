-- HEARTGOLD / SOULSILVER: THE BIKE SHOP OWNER'S CALL after 1,024 steps on
-- the Bicycle.
--
-- pokeheartgold, read off:
--
--   * THE COUNT. sub_0205E048 (asm/unk_0205CB48.s), on every step the player
--     avatar takes: GameStats_Inc(GAME_STAT_STEPS_WALKED), and when
--     PlayerAvatar_GetState is PLAYER_STATE_CYCLING (1) also
--     GameStats_Inc(GAME_STAT_STEPS_BIKED = 1). HGSS's stat 1 is not
--     Platinum's record 1 (the trainer score), so it is kept apart, as
--     `save.hgssStepsBiked`, capped like GameStats_GetCapped's u32 row
--     (999,999,999).
--   * THE CHECK. field_control.c FieldSystem_UpdateBikeShop, from
--     FieldSystem_ProcessStep each step (after the repel): while
--     FLAG_SYS_GOT_BIKE_SHOP_CALL (0x984) is clear, CALL_TRIGGER_BIKE_SHOP_STEPS
--     (2) is not already set and the biked steps reach 1024, the trigger is set
--     with the clock bumped (sub_02092E14(..., 2, 1)).
--   * THE CALL. Trigger 2 is { Bike Shop (15), PHONE_SCRIPT_085, forcePickUp }
--     (ov02_02253C84): src/world/HgssPhoneRing.lua puts it straight through
--     at the next ring check (one RTC minute later -- the bump leaves the
--     counter one short), and script 085 (msg_0642_00003, PHONESCRIPTTYPE_FLAG)
--     sets FLAG_SYS_GOT_BIKE_SHOP_CALL so it never comes again.

local M = {}

M.FLAG_GOT_CALL = 0x984
M.TRIGGER = 2
M.STEPS = 1024
M.CAP = 999999999

local function flag(save, id) return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end

function M.isHgss()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.family and GV.family() == "hgss" or false
end

function M.steps(save) return math.floor(tonumber(save and save.hgssStepsBiked) or 0) end

-- FieldSystem_UpdateBikeShop
function M.check(game)
  local save = game and game.save
  if not save then return false end
  local triggers = save.hgssPhoneCallTriggers or {}
  if flag(save, M.FLAG_GOT_CALL) or triggers[M.TRIGGER] or M.steps(save) < M.STEPS then return false end
  require("src.world.HgssPhoneRing").setTrigger(game, M.TRIGGER, true)
  return true
end

-- one step taken (OverworldController's step end): sub_0205E048 then the check
function M.step(game)
  local save = game and game.save
  if not (save and M.isHgss()) then return end
  if save.onBike then save.hgssStepsBiked = math.min(M.CAP, M.steps(save) + 1) end
  M.check(game)
end

return M
