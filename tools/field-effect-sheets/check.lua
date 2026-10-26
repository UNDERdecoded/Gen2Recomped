package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local F=require('src.core.game3.field_effects')
T.eq(package.loaded['src.core.Game'],nil,'resource require cannot bootstrap a game')
T.eq(F.loadSheet('tall_grass'),nil,'no dataset cannot invent an image')
love=require('tests.love_stub')
local read,imageFile,created=require('tools.sprite-runtime.cpu-gpu').install(love)
local Runtime=require('src.compat.gen1.FieldEffectRuntime')
local Host=require('src.mods.Runtime')
local Assets=require('src.render.Assets')
local Version=require('src.core.GameVersion')
local decode=require('src.compat.gen1.FieldEffectCache')
local function pixel(seed,w,h)
  local out={};for y=0,h-1 do for x=0,w-1 do out[#out+1]=string.char((x*31+seed)%256,(y*17+seed)%256,(x+y*7)%256,255)end end
  return table.concat(out)
end
local manifests={}
local function cache(text,rgba)
  local out={reads={}}
  function out:read(path)
    self.reads[#self.reads+1]=path
    T.check(path:find('data/generated/gba/field_effects/',1,true)==1,'only the explicit effect cache root is read')
    if path:sub(-11)=='objects.lua'then return text end
    if path:sub(-10)=='grass.rgba'then return rgba end
  end
  return out
end
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  F.release();local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
  local c=game.data.constants;game.data.sprites={}
  local expected={}
  for i,key in ipairs({'tall_grass','surf_blob','fly_bird','ripple','sparkle','emote_heart'})do
    local path='assets/generated/field-test/'..key..'.png';local bytes=pixel(i,16,32)
    imageFile(path,16,32,bytes);expected[key]=bytes
    local row={image=path,frameWidth=16,frameHeight=16,frames=2,trueColor=true}
    if key=='tall_grass'then c.gen3TallGrass=row
    elseif key=='surf_blob'then c.gen3SurfBlob=row
    elseif key=='fly_bird'then c.gen3FRLGFlyBird={path=path,frameWidth=16,frameHeight=16,frames=2}
    elseif key=='emote_heart'then c.gen3Emotes={heart={image=path,width=16,height=16,frames=2}}
    else c[key=='ripple'and'gen3Ripple'or'gen3Sparkle']={key=key};game.data.sprites[key]=row end
  end
  local original=game.data.constants.gen3TallGrass
  for name,bytes in pairs(expected)do
    Host.currentMod='effects-a';local sheet=assert(F.loadSheet(name,128,128,256));Host.currentMod=nil
    T.eq(sheet.fw,16);T.eq(sheet.fh,16);T.eq(sheet.frames,2,'supplied geometry cannot reinterpret native images')
    T.eq(read(sheet.image),bytes,'native source pixels remain in their original order')
    local x,y,w,h=sheet.quadsFront[1]:getViewport();T.eq(x,0);T.eq(y,24);T.eq(w,16);T.eq(h,8)
  end
  local view=F.manifest();view._byName.tall_grass.fw=88
  T.eq(F.manifestObject('tall_grass').fw,16,'metadata readers receive detached records')
  T.eq(F.loadSheet('emoticons'),nil,'separate native bubbles cannot masquerade as a combined source strip')
  T.eq(F.loadSheet('../tall_grass'),nil)
  local native=assert(F.loadSheet('tall_grass'));local nativeImage=native.image
  local borrowed=love.graphics.newImage(love.image.newImageData(original.image))
  Host.currentMod='effects-b';T.eq(F.loadSheet('tall_grass'),native);Host.currentMod=nil
  F.cancelOwner('effects-a');T.eq(native._retired,nil,'a peer lease keeps the shared owned sheet alive')
  F.cancelOwner('effects-b');T.eq(native._retired,nil,'an engine request still owns this sheet')
  native.image=borrowed
  native.quads={external={release=function()error('borrowed quad must never be released')end}}
  F.invalidate();T.eq(native._retired,true);T.eq(read(borrowed),expected.tall_grass,'public table mutation cannot transfer ownership of a borrowed image')
  T.eq(game.data.constants.gen3TallGrass,original);T.check(not pcall(nativeImage.getWidth,nativeImage))
  borrowed:release()
  local family=Version.isFRLG(edition)and'frlg'or'rse'
  local bytes=pixel(93,8,16)
  local text="return {family='"..family.."',objects={[0]={name='tall_grass',fw=8,fh=8,frames=2,rgba='grass.rgba',anims={{{'frame',0,3},{'frame',1,4}}}}},extras={}}"
  local source=cache(text,bytes)
  Host.currentMod='provider-owner';T.check(F.install(source)~=nil)
  local sheet=assert(F.loadSheet('tall_grass',16,16,5));Host.currentMod=nil
  T.eq(sheet.fw,8);T.eq(sheet.fh,8);T.eq(sheet.frames,2);T.eq(read(sheet.image),bytes,'explicit source RGBA remains exact')
  T.eq(F.loadSheet('surf_blob'),nil,'an explicit authored manifest remains authoritative')
  local copy=F.manifestObject('tall_grass');copy.anims[1][1][2]=99
  T.eq(F.manifestObject('tall_grass').anims[1][1][2],0)
  F.cancelOwner('provider-owner');T.eq(sheet._retired,true);T.eq(F._cache,nil)
  T.eq(assert(F.loadSheet('tall_grass')).fw,16,'native resources resume after provider retirement')
  Host.currentMod='provider-owner';assert(F.install(source));local previous=assert(F.loadSheet('tall_grass'));Host.currentMod=nil
  game.save={};T.eq(assert(F.loadSheet('tall_grass')).fw,16,'a save cohort switch cannot replay an old cache lease')
  T.eq(previous._retired,true);T.eq(F._cache,nil)
  local runtime=Runtime.new();runtime.maxBytes=1
  local missing,why=runtime:get('tall_grass');T.eq(missing,nil);T.check(why:find('budget',1,true)~=nil)
  runtime.maxBytes=1024*1024
  local before=#created;local quad=love.graphics.newQuad
  love.graphics.newQuad=function(...)if#created>=before+1 then error('injected second quad failure')end;return quad(...)end
  T.eq(runtime:get('tall_grass'),nil);love.graphics.newQuad=quad
  T.eq(runtime.bytes,0);T.eq(next(runtime.loaded),nil)
  for i=before+1,#created do T.eq(created[i].dead,true,'failed preparation releases every partial allocation')end
  T.check(runtime:get('tall_grass')~=nil,'a failed upload is retryable');runtime:release()
  local wrong=cache(text:gsub(family,family=='frlg'and'rse'or'frlg'),bytes)
  local m,err=decode.manifest(wrong,'data/generated/gba/field_effects',family)
  T.eq(m,nil);T.check(err:find('family',1,true)~=nil)
  for _,bad in ipairs({text:gsub('grass.rgba','../grass.rgba'),text:gsub('frames=2','frames=999'),
      text:gsub('extras={}',"extras={{name='tall_grass',fw=8,fh=8,frames=2,rgba='grass.rgba'}}"),
      'return {objects=function()end}','while true do end',string.char(27)..'bytecode'})do
    T.eq(decode.manifest(cache(bad,bytes),'data/generated/gba/field_effects',family),nil,'malformed source metadata is rejected')
  end
  local sentinel=function()end;debug.sethook(sentinel,'',1000000)
  T.eq(decode.manifest(cache('error()'), 'data/generated/gba/field_effects',family),nil)
  local restored=debug.gethook();debug.sethook();T.eq(restored,sentinel,'manifest execution restores the host debug hook')
  local changing=cache(text,bytes);local reader=changing.read
  function changing:read(path)
    if path:sub(-10)=='grass.rgba'then F.release()end
    return reader(self,path)
  end
  Host.currentMod='stale-owner';assert(F.install(changing));local stale=F.loadSheet('tall_grass');Host.currentMod=nil
  T.eq(stale,nil,'a reentrant cache reader cannot publish retired resources')
  T.eq(assert(F.loadSheet('tall_grass')).fw,16)
  F.release();T.eq(F._cache,nil)
end
F.release();package.loaded['src.core.Game']=nil
T.eq(F.manifest(),nil)
T.finish('owned field-effect artwork and cache leases')
