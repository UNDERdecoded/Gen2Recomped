-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Streaks=require('src.battle.Gen3LevelUpStreaks')
local Art=require('src.import.Gen3LevelUpArt')
local bit=require('bit')
local ffi=require('ffi')
local seed=ffi.new('uint32_t[1]')
local function speed(index)
 -- Independent integer C-width oracle; never consume the game's RNG.
 seed[0]=ffi.new('uint64_t',index)*1103515245+24691
 return bit.band(tonumber(seed[0]),63)+32
end
local previous,seen={},{}
for frame=0,100 do
 local rows={};local active,count=Streaks.sample(frame,function(x,y,index,velocity)
  T.eq(velocity,speed(index),'native LCG low-bit arithmetic')
  T.eq(x,bit.band(index*219,63)-32)
  T.eq(y,32+bit.arshift(-velocity*(frame-2*(index-1)),4),'signed subpixel truncation')
  T.check(y>=-32 and y<=32,'sprite retires beyond its actual boundary')
  if previous[index]then T.check(y<=previous[index],'streak moves upward')end
  rows[index]=y;seen[index]=true
 end)
 local expected=0
 for index=1,18 do
  local age=frame-2*(index-1)
  local y=bit.arshift(-speed(index)*age,4)
  if age>=0 and y>=-64 then expected=expected+1 end
 end
 T.eq(count,expected);T.eq(active,expected>0 or frame<34)
 T.eq(Streaks.busy(frame),active,'queue completion uses the same native frames as drawing')
 previous=rows
end
local n=0;for _ in pairs(seen)do n=n+1 end;T.eq(n,18,'all sprites are sampled without an admission cap')
T.raises(function()Streaks.sample(-1,function()end)end,'invalid native streak frame')
T.raises(function()Streaks.sample(0)end,'native streak visitor must be callable')
for _,edition in ipairs{'firered','leafgreen'}do T.eq(Art.supports(edition),true)end
for _,edition in ipairs{'emerald','ruby','sapphire','gold','unknown'}do
 T.eq(Art.supports(edition),false,'a foreign cartridge is not assigned FRLG artwork')
 T.eq(Art.read({version=edition}),nil)
end
local V=require('src.core.GameVersion');local previousVersion=V.get()
local Sound=require('src.core.Sound');local play=Sound.playSe;local sounds=0
Sound.playSe=function(data,name)T.eq(name,'SE_RS_SHOP');sounds=sounds+1 end
for _,edition in ipairs{'firered','leafgreen'}do
 V.set(edition)
 local actor={mon={hp=10},isPlayer=true,position=0}
 local battle={frame=0,player=actor,data={constants={gen3LevelUpStreaks={image='owned native resource'}}},queue={}}
 function battle:battlerAt(index)T.eq(index,0);return actor end
 Streaks.queue(battle,actor)
 T.eq(#battle.queue,1);T.eq(battle.queue[1].gbaLevelUpStreaks,true)
 T.eq(Streaks.start(battle,battle.queue[1]),true)
 local steps=0
 while Streaks.update(battle)do battle.frame=battle.frame+1;steps=steps+1;T.check(steps<100,'native effect finishes without a timeout extension')end
 T.eq(battle._levelUpStreaks,nil);T.check(steps>34,'native queue holds through the final sprites')
 actor.mon.hp=0;T.eq(Streaks.start(battle,battle.queue[1]),false,'fainted actors do not gain a visible streak effect')
 actor.mon.hp=10;battle.picFx={[actor]={hidden=true}}
 T.eq(Streaks.start(battle,battle.queue[1]),false,'hidden native sprites remain hidden')
 battle.picFx=nil;battle.data.constants.gen3LevelUpStreaks=nil
 T.eq(Streaks.start(battle,battle.queue[1]),false,'an absent native resource is never replaced with generic artwork')
 local released=0;battle._levelUpBlend={release=function()released=released+1 end}
 Streaks.release(battle);Streaks.release(battle);T.eq(released,1,'owned render buffers retire once')
end
T.eq(sounds,2,'native sound is triggered once per accepted effect')
Sound.playSe=play;V.set(previousVersion)
T.finish('native vertical streak timing, integer sampling and edition ownership')
