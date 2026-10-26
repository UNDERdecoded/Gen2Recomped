package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Data=require('src.core.Data')
local Version=require('src.core.GameVersion')
local saved=Version.get()
for _,version in ipairs(Version.ORDER)do
 Version.set(version)
 local maps={}
 for env=1,7 do maps['ENV'..env]={id='ENV'..env,environment=env,tileset='NATIVE_TILESET'}end
 maps.AUTHORED={generation=2,outdoor=false,environment=1}
 maps.CUSTOM={generation=9,outdoor=true,environment=3}
 maps.UNKNOWN={environment=99}
 maps.ABSENT={}
 maps.NAMED={environment='ROUTE'}
 maps.FRACTION={environment=1.5}
 maps.BAD='bad record'
 local data={maps=maps}
 local accepted=Data.publishGen2MapMetadata(data)
 if Version.isGen2()then
  T.eq(accepted,true,version..' native Gen2 metadata')
  for env=1,7 do
   local def=maps['ENV'..env]
   T.eq(def.generation,2,version..' real host generation '..env)
   T.eq(def.outdoor,env==1 or env==2,version..' ROM environment '..env)
   T.eq(def.environment,env,'native environment byte retained')
   T.eq(def.id,'ENV'..env,'native identifier retained')
   T.eq(def.tileset,'NATIVE_TILESET','native tileset lookup retained')
  end
  T.eq(maps.AUTHORED.outdoor,false,'explicit interior override retained')
  T.eq(maps.CUSTOM.outdoor,true,'explicit exterior override retained')
  T.eq(maps.CUSTOM.generation,9,'authored generation retained')
  T.eq(maps.UNKNOWN.outdoor,nil,'unknown byte not guessed')
  T.eq(maps.ABSENT.outdoor,nil,'missing header not guessed')
  T.eq(maps.NAMED.outdoor,true,'authored named environment supported')
  T.eq(maps.FRACTION.outdoor,nil,'invalid byte not guessed')
  maps.AUTHORED.outdoor=true
  T.eq(Data.publishGen2MapMetadata(data),true,'republication after mods')
  T.eq(maps.AUTHORED.outdoor,true,'post-merge authored choice retained')
 else
  T.eq(accepted,false,version..' other generation untouched')
  T.eq(maps.ENV1.generation,nil,'no false Gen2 metadata')
  T.eq(maps.ENV1.outdoor,nil,'other native outdoor rules unchanged')
 end
end
Version.set('crystal');T.eq(Data.publishGen2MapMetadata({}),false,'missing maps safe')
Version.set(saved)
T.finish('native Gen2 map metadata')
