package.path='./?.lua;'..package.path
local checks=0;local function check(v,label) assert(v,label);checks=checks+1 end
package.loaded['src.core.Logger']={debug=function() end,warn=function() end,info=function() end}
package.loaded['src.render.Assets']={resolve=function(path) return path end}
package.loaded['src.core.Music']={duckForCry=function() end}
local made=0;local cached
local function source()
 return {playing=false,setVolume=function() end,stop=function(s) s.playing=false end,
 play=function(s) s.playing=true end,isPlaying=function(s) return s.playing end,
 clone=function() return source() end}
end
love={audio={newSource=function() made=made+1;cached=source();return cached end}}
local Sound=require('src.core.Sound')
local data={pokemon={[387]={name='TURTWIG'}},audio={cries={[387]='cry.wav'}}}
local first=Sound.playCry(data,387)
check(first==cached and first.playing and made==1,'ordinary cry uses cached source')
local copy=Sound.playCry(data,387,{isolated=true})
check(copy~=first and copy.playing and first.playing and made==1,'Dex plays clone without restarting cached cry')
copy:stop();check(first.playing,'stopping Dex clone leaves ordinary playback alive')
local second=Sound.playCry(data,387,{isolated=true})
check(second~=copy and second~=first,'repeat gets independent source')
check(Sound.playCry(data,387)==first,'ordinary callers retain existing cache identity')
first.clone=function() error('unsupported backend') end
check(Sound.playCry(data,387,{isolated=true})==first,'unsupported cloning retains safe playback fallback')
love.audio=nil;check(Sound.playCry(data,387,{isolated=true})==nil,'headless playback remains safe')
print(checks..' cry isolation/cache/back-end fallback checks passed')
