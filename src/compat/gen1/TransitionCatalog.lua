-- Cartridge enum facts; visual execution remains on native registered styles.
local M={}
local base={'BLUR','SWIRL','SHUFFLE','BIG_POKEBALL','POKEBALLS_TRAIL','CLOCKWISE_WIPE','RIPPLE','WAVE',
  'SLICE','WHITE_BARS_FADE','GRID_SQUARES','ANGLED_WIPES'}
local tails={frlg={'LORELEI','BRUNO','AGATHA','LANCE','BLUE','SPIRAL'},
  rse={'SIDNEY','PHOEBE','GLACIA','DRAKE','CHAMPION','AQUA','MAGMA','REGICE','REGISTEEL','REGIROCK',
    'KYOGRE','GROUDON','RAYQUAZA','SHRED_SPLIT','BLACKHOLE','BLACKHOLE_PULSATE','RECTANGULAR_SPIRAL',
    'FRONTIER_LOGO_WIGGLE','FRONTIER_LOGO_WAVE','FRONTIER_SQUARES','FRONTIER_SQUARES_SCROLL',
    'FRONTIER_SQUARES_SPIRAL','FRONTIER_CIRCLES_MEET','FRONTIER_CIRCLES_CROSS','FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL',
    'FRONTIER_CIRCLES_SYMMETRIC_SPIRAL','FRONTIER_CIRCLES_MEET_IN_SEQ','FRONTIER_CIRCLES_CROSS_IN_SEQ',
    'FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL_IN_SEQ','FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ'}}
local commonStyles={'g3_blur','g3_swirl','g3_shuffle','g3_bigPokeball','g3_pokeballsTrail','g3_clockwiseBlackfade',
  'g3_ripple','g3_wave','g3_slice','g3_whitefade','g3_grid','g3_angled'}
function M.family(edition)
  if edition=='firered'or edition=='leafgreen'then return 'frlg'end
  if edition=='emerald'or edition=='ruby'or edition=='sapphire'then return 'rse'end
end
function M.new(edition)
  local family=assert(M.family(edition),'no native GBA transition catalogue')
  local rs=edition=='ruby'or edition=='sapphire'
  local c={ID={},names={},styles={},MUGSHOT_BY_ID={},TERRAIN={NORMAL=0,CAVE=1,FLASH=2,WATER=3},family=family}
  for i,name in ipairs(base)do c.ID[name]=i-1;c.names[i-1]=name;c.styles[i-1]=commonStyles[i]end
  for i,name in ipairs(tails[family])do
    if not rs or i<=5 then c.ID[name]=11+i;c.names[11+i]=name end
  end
  if family=='frlg'then
    c.styles[1],c.styles[4],c.styles[5],c.styles[8],c.styles[9]='frlg_swirl','frlg_balltrail','frlg_clockwise','frlg_slice','frlg_whitebars'
  end
  local names=family=='frlg'and{'lorelei','bruno','agatha','lance','blue'}or{'sidney','phoebe','glacia','drake','champion'}
  for i,name in ipairs(names)do c.MUGSHOT_BY_ID[11+i]=name;c.styles[11+i]='g3_mugshot'end
  if family=='rse'and not rs then
    for i,name in ipairs({'aqua','magma','regice','registeel','regirock','kyogre','groudon','rayquaza'})do c.styles[16+i]='g3_'..name end
  end
  if rs then
    for alias,name in pairs({CLOCKWISE_BLACKFADE='CLOCKWISE_WIPE',WHITEFADE='WHITE_BARS_FADE',SHARDS='ANGLED_WIPES',SYDNEY='SIDNEY',STEVEN='CHAMPION'})do c.ID[alias]=c.ID[name]end
  end
  c.TUNE={introFades=family=='frlg'and 2 or 3,blurDelay=family=='frlg'and 2 or 4,
    wipeStepX=family=='frlg'and 32 or 16,wipeStepY=family=='frlg'and 16 or 8,
    rippleFadeAt=family=='frlg'and 41 or 81,rippleFadeDelay=family=='frlg'and -8 or -2}
  return c
end
function M.terrain(edition,opts)
  opts=opts or{}
  if opts.flash or(tonumber(opts.flashLevel)or 0)>0 then return 2 end
  if M.family(edition)=='frlg'then
    if opts.surfing or opts.isWater or opts.mapKind=='water'or opts.mapType==4 or opts.mapType==5 then return 3 end
    if opts.isCave or opts.mapKind=='cave'or opts.mapKind=='dungeon'or opts.mapType==3 then return 1 end
  else
    if opts._surfable then return 3 end
    if tonumber(opts.mapType)==4 then return 1 end
    if tonumber(opts.mapType)==5 then return 3 end
  end
  return 0
end
local wild={{8,9},{5,10},{0,10},{7,6}}
local trainer={{4,11},{2,3},{0,10},{1,6}}
function M.pick(edition,opts,isTrainer)
  opts=opts or{}
  local frlg=M.family(edition)=='frlg';local cls=tonumber(opts.trainerClass);local id=tonumber(opts.trainerId)
  if isTrainer then
    if frlg then
      if opts.trainerTower or opts.eReader then cls=nil end
      if cls==87 then
        for i,name in ipairs({'Lorelei','Bruno','Agatha','Lance'})do if opts['is'..name]then return 11+i end end
        return ({[410]=12,[411]=13,[412]=14,[413]=15,[735]=12,[736]=13,[737]=14,[738]=15})[id]or 16
      end
      if cls==90 or opts.isRival or opts.isChampion then return 16 end
      for i,name in ipairs({'Lorelei','Bruno','Agatha','Lance','Blue'})do if opts['is'..name]then return 11+i end end
    else
      local rs=edition=='ruby'or edition=='sapphire'
      if id==1024 or cls==(rs and 32 or 38)then return 16 end
      if cls==(rs and 24 or 31)then return ({[261]=12,[262]=13,[263]=14,[264]=15})[id]or 16 end
      if edition=='emerald'then
        if cls==9 or cls==53 or cls==49 then return 18 end
        if cls==3 or cls==13 or cls==11 then return 17 end
      end
    end
  elseif opts.pyramid and not frlg then
    return (tonumber(opts.enemyLevel)or 3)<(tonumber(opts.playerLevel)or 5)and 0 or 10
  end
  local terrain=opts.terrain or M.terrain(edition,opts)
  local row=(isTrainer and trainer or wild)[terrain+1]or(isTrainer and trainer or wild)[1]
  return row[(tonumber(opts.enemyLevel)or 3)<(tonumber(opts.playerLevel)or 5)and 1 or 2]
end
function M.special(edition,group,opts)
  opts=opts or{}
  if group=='trainer_hill'or group=='secret_base'or group=='e_reader'or group=='battle_tower'then
    return(tonumber(opts.enemyLevel)or 3)<(tonumber(opts.playerLevel)or 5)and 4 or 3
  end
  assert(edition=='emerald','transition group is unavailable for this edition')
  local list=group=='pyramid'and{31,32,33}or group=='dome'and{29,31,32,33}or{29,30,31,32,34,35,36,37,38,39,40,41}
  local random=opts.random or math.random
  return list[(random(#list*65536)%#list)+1]
end
return M
