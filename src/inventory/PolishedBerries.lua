-- Polished uses modern berry names and a different held-effect enum from
-- GSC. Keep this translation local to its cartridge.
local B={}
local cures={CHERI_BERRY='PAR',CHESTO_BERRY='SLP',PECHA_BERRY='PSN',
             RAWST_BERRY='BRN',ASPEAR_BERRY='FRZ'}
function B.enabled()
  return require('src.core.GameVersion').get()=='polishedcrystal'
end
function B.record(def)
  if not B.enabled() or not def then return nil end
  local key=def.key
  if cures[key]then return {cures={cures[key]}} end
  if key=='LUM_BERRY'then return {cureAll=true}end
  if key=='PERSIM_BERRY'then return {confusion=true}end
  if key=='LEPPA_BERRY'then return {pp=true,single=true,amount=10}end
  if key=='ORAN_BERRY'then return {heal=true,amount=10}end
  if key=='SITRUS_BERRY'then return {heal=true,hpDivisor=4}end
  if key=='FIGY_BERRY'then return {heal=true,hpDivisor=3}end
  local ev={POMEG_BERRY='hp',KELPSY_BERRY='attack',QUALOT_BERRY='defense',
    HONDEW_BERRY='spatk',GREPA_BERRY='spdef',TAMATO_BERRY='speed'}
  if ev[key]then return {ev=ev[key],amount=-10,friendship={10,5,2},friendshipOnly=true}end
end
function B.held(def,mon)
  if not B.enabled() or not def then return nil end
  local key=def.key
  local names={PAR='CURE_PAR',SLP='CURE_SLP',PSN='CURE_PSN',BRN='CURE_BRN',FRZ='CURE_FRZ'}
  if cures[key]then return names[cures[key]],0 end
  if key=='LUM_BERRY'then return 'CURE_STATUS',0 end
  if key=='PERSIM_BERRY'then return 'CURE_CONFUSION',0 end
  if key=='LEPPA_BERRY'then return 'RESTORE_PP',10 end
  if key=='ORAN_BERRY'then return 'RESTORE_HP',10 end
  if key=='SITRUS_BERRY'then return 'RESTORE_HP',math.max(1,math.floor(mon.stats.hp/4))end
  if key=='FIGY_BERRY'then return 'CONFUSE_SPICY',3 end
  local pinch={LIECHI_BERRY='ATTACK_UP',GANLON_BERRY='DEFENSE_UP',SALAC_BERRY='SPEED_UP',
    PETAYA_BERRY='SP_ATTACK_UP',APICOT_BERRY='SP_DEFENSE_UP',STARF_BERRY='RANDOM_STAT_UP',
    LANSAT_BERRY='CRITICAL_UP'}
  if pinch[key]then return pinch[key],4 end
end
return B
