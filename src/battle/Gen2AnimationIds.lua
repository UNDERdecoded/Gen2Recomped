-- GSC constants/move_constants.asm, also documented by Gen1Recomp's
-- RomExtractorGen2 BATTLE_ANIM_IDS. These name existing native ROM programs;
-- they neither synthesize scripts nor replace cartridge data.
local Ids = {
  ANIM_SWEET_SCENT_2=0xff, ANIM_THROW_POKE_BALL=0x100,
  ANIM_SEND_OUT_MON=0x101, ANIM_RETURN_MON=0x102,
  ANIM_CONFUSED=0x103, ANIM_SLP=0x104, ANIM_BRN=0x105,
  ANIM_PSN=0x106, ANIM_SAP=0x107, ANIM_FRZ=0x108,
  ANIM_PAR=0x109, ANIM_IN_LOVE=0x10a, ANIM_IN_SANDSTORM=0x10b,
  ANIM_IN_NIGHTMARE=0x10c, ANIM_IN_WHIRLPOOL=0x10d,
  ANIM_MISS=0x10e, ANIM_ENEMY_DAMAGE=0x10f,
  ANIM_ENEMY_STAT_DOWN=0x110, ANIM_PLAYER_STAT_DOWN=0x111,
  ANIM_PLAYER_DAMAGE=0x112, ANIM_WOBBLE=0x113,
  ANIM_SHAKE=0x114, ANIM_HIT_CONFUSION=0x115,
}
local M={}
function M.install(anims)
  if not (anims and anims.gen2) then return anims end
  local ids=anims.ids or {};anims.ids=ids
  for name,index in pairs(Ids) do
    if ids[name]==nil and anims.scripts and anims.scripts[index] then
      ids[name]=index
    end
  end
  return anims
end
return M
