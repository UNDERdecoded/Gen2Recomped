package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local V = require('src.core.GameVersion')
local Battle = require('src.battle.BattleState')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Serializer = require('src.core.SaveSerializer')
local before = V.get()
local male, female = '\226\153\130', '\226\153\128'
local function fixture(version)
  V.set(version)
  local data = T.fixtures.fresh(); data.constants.gen = V.generation(version)
  local save = Save.newGame()
  save.party = {Pokemon.new(data, 'FIXMON_A', 12)}
  local game = {data=data,save=save,stack={top=function()end}}
  return Battle.newWild(game,'FIXMON_B',8),data
end

for _, version in ipairs({'gold','silver','crystal','prism','polishedcrystal'}) do
  local b,data = fixture(version)
  T.eq(type(b.genderSymbol),'function',version .. ' publishes the actual native screen method')
  if type(b.genderSymbol)=='function' then
    local mon = b.player.mon
    local oldRandom = love.math.random; local draws=0
    love.math.random=function(...) draws=draws+1;return oldRandom(...) end
    -- Cartridge ratio classes: every Attack DV on each side of every
    -- threshold, with both Speed-DV extremes. No second gender record.
    for _, row in ipairs({{0,0},{31,2},{63,4},{127,8},{191,12},{254,16},{255,-1}}) do
      data.pokemon[mon.species].genderRatio=row[1]
      for attack=0,15 do for _,speed in ipairs({0,15}) do
        mon.dvs.attack=attack;mon.dvs.speed=speed;mon.gender=nil
        local bytes=Serializer.encode(mon)
        local want
        if row[2]>=0 then want=attack<row[2] and female or male end
        T.eq(b:genderSymbol(mon),want,'native DV ratio '..row[1]..'/'..attack..'/'..speed)
        T.eq(Serializer.encode(mon),bytes,'HUD read preserves actual saved Pokemon bytes')
      end end
    end
    for _,row in ipairs({{'MALE',male},{'female',female},{'NONE',false},{'genderless',false}})do
      mon.gender=row[1];T.eq(b:genderSymbol(mon),row[2]or nil,'native explicit gender authority')
    end
    T.eq(b:genderSymbol(nil),nil,'missing presentation mon has no symbol')
    T.eq(b:genderSymbol({species='UNKNOWN_NATIVE_SPECIES',dvs={attack=15}}),nil,'unknown catalog row has no invented gender')
    T.eq(draws,0,'painting gender never draws native Pokemon randomness')
    love.math.random=oldRandom
  end
end

-- The shared screen class must not make Gen3 clients fall back to DVs.
do
  local b,data=fixture('firered');local mon=b.player.mon
  T.eq(type(b.genderSymbol),'function','shared native screen has the same method')
  if type(b.genderSymbol)=='function' then
    data.pokemon[mon.species].genderRatio=127;mon.gender=nil
    mon.personality=0;T.eq(b:genderSymbol(mon),female,'native PID female')
    mon.personality=255;T.eq(b:genderSymbol(mon),male,'native PID male')
    mon.gender='F';T.eq(b:genderSymbol(mon),nil,'unknown native override is not guessed')
  end
end
V.set(before)
T.finish('native battle HUD gender authority')
