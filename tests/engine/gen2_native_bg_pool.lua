-- GSC register/picture traces against the native BgEffects API. No graphics,
-- game state, ROM, synthetic animation runner or replacement clock is used.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Bg=require('src.battle.gen2.BgEffects')
local Ids=require('src.battle.Gen2BgEffectIds')
local Math=require('src.battle.Gen2AnimMath')
T.eq(Math.sine(16,32),32,'Q8.8 quarter-wave reaches its exact positive amplitude')
T.eq(Math.sine(48,32),224,'negative amplitude wraps as a hardware byte')
T.eq(Math.cosine(0,32),32,'cosine follows the cartridge quarter-wave shift')
T.eq(Math.sra(0x80),0xc0,'arithmetic right shift preserves a negative byte sign')
T.eq(Math.sra(0xff),0xff,'minus one remains minus one after arithmetic shift')
T.eq(Math.sra(0x7f),0x3f,'positive arithmetic shift does not invent sign bits')
T.eq(Math.swap(0xab),0xba,'nibble swap preserves byte ordering')
for value=0,255 do T.eq(Math.swap(Math.swap(value)),value,'two nibble swaps recover the hardware byte')end

for _,edition in ipairs({'gold','silver','crystal'})do
  local order=Ids.forVersion(edition)
  T.eq(#order,edition=='crystal'and 54 or 53,'edition owns its cartridge BG jump table')
  T.eq(order[38],edition=='crystal'and'BATTLE_BG_EFFECT_BODY_SLAM'or'BATTLE_BG_EFFECT_WOBBLE_MON',
    'Crystal insertion does not misinterpret the Gold/Silver effect id')
  T.eq(order[#order],'BATTLE_BG_EFFECT_WOBBLE_SCREEN','edition table terminates at the proper final effect')
  local altered=Ids.forVersion(edition);altered[1]='changed'
  T.eq(Ids.forVersion(edition)[1],'BATTLE_BG_EFFECT_END','one consumer cannot mutate another edition registry')
  for index,name in ipairs(order)do
    T.eq(type(Bg.EFFECTS[name]),'function','every cartridge BG id has an actual native state machine')
    local pool=Bg.new({battleBgEffectOrder=order},{battleTurn=0})
    local entry=pool:queue(index-1,0,0,0)
    T.eq(entry and entry.func,name,'raw cartridge id selects its actual edition state machine')
    local before=#Bg.DROPPED
    T.check(pcall(function()for _=1,8 do pool:playFrame()end end),
      'known native effect executes its initial state transitions')
    T.eq(#Bg.DROPPED,before,'known cartridge effects never take the unknown-id fallback')
  end
end

-- BattleBGEffect_EnterMon's three four-frame squares. Player uses 2x2,
-- 4x4,6x6; enemy uses 3x3,5x5,7x7 (pic-size selectors2/1/0 and5/4/3).
for _,turn in ipairs({0,1})do
  for _,side in ipairs({'player','enemy'})do
    local sideFlag=side=='player'and(1-turn)or turn
    local pool=Bg.new({}, {battleTurn=turn})
    pool:queue('BATTLE_BG_EFFECT_ENTER_MON',0,sideFlag,0)
    for frame=1,13 do
      pool:playFrame()
      local stage=math.floor((frame-1)/4)
      local expected=stage<3 and((side=='player'and 2 or 5)-stage)or nil
      T.eq(pool.picSize[side],expected,'native entry follows its own picture-size trace')
      T.eq(pool.hidden[side],false,'entry reveals the side selected by battle-turn XOR')
    end
    T.eq(pool:activeCount(),0,'entry terminates after its native final picture state')
  end
end

-- BODY_SLAM is Crystal's inserted $25 entry. The trace retains the exact
-- LCD window and byte displacement cited by Gen1Recomp bug2102.
local slam=Bg.new({battleBgEffectOrder=Ids.forVersion('crystal')},{battleTurn=0})
slam:queue(0x25,0,1,0);slam:playFrame()
T.eq(slam.lcdc,'SCX','BODY_SLAM displaces the selected band horizontally')
T.eq(slam.lyStart,0x2d,'player band begins at the cartridge LCD boundary')
T.eq(slam.lyEnd,0x5f,'player band ends one row beyond the picture')
slam:playFrame();slam:playFrame()
T.eq(slam.lyBackup[0x30],0xfe,'native lunge writes the signed two-pixel displacement')

local pool=Bg.new({}, {battleTurn=0})
for _=1,5 do T.check(pool:queue('BATTLE_BG_EFFECT_FLASH_WHITE',0,0,0)~=nil,'native pool admits five hardware effect structs')end
T.eq(pool:queue('BATTLE_BG_EFFECT_FLASH_WHITE',0,0,0),nil,'full native pool refuses a sixth struct')
pool:reset();T.eq(pool:activeCount(),0,'native reset retires all effect owners')
T.eq(pool.bgp,0xe4,'native reset restores identity BG palette register')
T.eq(pool.scx,0,'native reset restores horizontal register')
T.eq(pool.scy,0,'native reset restores vertical register')
T.finish('native GSC BG registry, byte arithmetic and register/picture state machines')
