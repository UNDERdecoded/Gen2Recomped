package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
love=require('tests.love_stub')
local sources={};local Source={};Source.__index=Source
function Source:play()self.playing=true end
function Source:stop()self.playing=false end
function Source:pause()self.playing=false end
function Source:isPlaying()return self.playing end
function Source:setLooping(v)self.looping=v end
function Source:setVolume(v)self.volume=v end
function Source:setFilter()end
love.audio={newSource=function(file)local s=setmetatable({file=file},Source);sources[file]=s;return s end}
local Sound=require('src.core.Sound');local Music=require('src.core.Music')
local data={constants={gen3Cry={scale=256,volume=90,duckBgm=85}},audio={songs={TEST={file='song.ogg'}},cries={A='a.ogg',B='b.ogg'}}}
local function near(a,b)T.check(type(a)=='number'and math.abs(a-b)<1e-10,tostring(a)..' matches '..b)end
Music.play(data,'TEST');local song=assert(sources['song.ogg']);near(song.volume,0.7)
local a=assert(Sound.playCry(data,'A'));near(a.volume,0.8*90/256);near(song.volume,0.7*85/256)
local b=assert(Sound.playCry(data,'B',{noDuck=true,volume=125}));near(b.volume,0.8*125/256)
near(song.volume,0.7*85/256) -- another active cry retains its attenuation
T.eq(Sound.playCry(data,'A',{noDuck=true,volume=125}),a);near(song.volume,0.7);near(a.volume,0.8*125/256)
T.eq(Sound.playCry(data,'A'),a);near(a.volume,0.8*90/256);near(song.volume,0.7*85/256)
a:stop();Music.update(data);near(song.volume,0.7)
Sound.playCry(data,'B',{volume=0,noDuck=true});near(b.volume,0);near(song.volume,0.7)
Sound.playCry(data,'B',{volume=0/0,noDuck=true});near(b.volume,0.8*90/256)
Sound.playCry(data,'B',{volume=257,noDuck=true});near(b.volume,0.8*90/256)
Sound.invalidate();Music.stop()
T.finish('field-move cry options preserve native cached audio and music ownership')
