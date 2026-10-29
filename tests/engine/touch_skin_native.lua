-- Native host integration, using owned memory-only skins. No ROM/profile IO.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Skin = require('src.core.TouchSkin')
local Touch = require('src.core.TouchControls')
local Input = require('src.core.Input')
local V = require('src.render.GameViewport')
local Runtime = require('src.mods.Runtime')
local Save = require('src.core.SaveData')
local Game = require('src.core.Game')
local sdk=T.sdk.loadMods({'mods/skin_consumer'},{data=T.fixtures.fresh(),fs=T.sdk.memfs({
  ['mods/skin_consumer/manifest.json']=require('src.link.Json').encode({
    id='skin_consumer',name='Unmodified skin API consumer fixture',version='1.0.0',api=2,entry='main.lua'}),
  ['mods/skin_consumer/main.lua']=[[
    local mod=...
    local S=require('src.core.TouchSkin')
    mod.exports.hasGeometry=type(S.page)=='function' and type(S.controlGeometry)=='function'
    mod.exports.hasLibrary=type(S.installArchive)=='function' and type(S.exportDelta)=='function'
  ]],
})})
T.eq(#sdk.errors,0,'actual mod loader resolves native skin API')
T.eq(sdk.loader.apis.skin_consumer.exports.hasGeometry,true,'optional mod geometry consumer receives real API')
T.eq(sdk.loader.apis.skin_consumer.exports.hasLibrary,true,'optional mod library consumer receives real API')
sdk.release()
local W, H = 640, 480
love.graphics.getDimensions = function() return W, H end
love.graphics.getPixelDimensions = function() return W * 2, H * 2 end
local files, dirs = {}, {skins=true, ['assets/skins']=true}
local fs = {}
function fs.read(path) return files[path] end
function fs.write(path, bytes) files[path] = bytes; return true end
function fs.getInfo(path)
  if dirs[path] then return {type='directory'} end
  if files[path] then return {type='file', size=#files[path]} end
end
function fs.createDirectory(path) dirs[path]=true; return true end
function fs.remove(path) files[path], dirs[path]=nil,nil; return true end
function fs.getDirectoryItems(path)
  local found, out = {}, {}
  for _, table_ in ipairs{dirs,files} do
    for key in pairs(table_) do
      local tail = key:sub(1,#path+1)==path..'/' and key:sub(#path+2)
      local name = tail and tail:match('^([^/]+)')
      if name and not found[name] then found[name]=true; out[#out+1]=name end
    end
  end
  table.sort(out); return out
end
love.filesystem = fs
-- Same persistence seam as portable/account saves, with an explicit memory fs.
Save.persistenceFs = function() return fs end
local skin = Skin.newSkin('native_owned')
skin.pages[1].aspectFromCfg = false
skin.pages[1].viewport = {x=.1,y=.1,w=.8,h=.5}
skin.pages[1].controls = {
  Skin.newControl('a|key:f5', .8,.8,.2,.2,'rect'),
  Skin.newControl('hold_fast_forward', .2,.8,.2,.2,'rect'),
}
skin.pages[1].imagePath = 'img/bezel.png'
skin.pages[1].controls[1].imagePath = 'img/a.png'
dirs[skin.root], dirs[skin.root..'/img'] = true,true
files[skin.root..'/img/bezel.png'] = 'owned-bezel-image'
files[skin.root..'/img/a.png'] = 'owned-control-image'
local drawn = {}
love.graphics.newImage = function(path)
  return {getWidth=function() return W end, getHeight=function() return H end,
    getDimensions=function() return W,H end, setFilter=function() end, path=path}
end
love.graphics.draw = function(image,x,y,...) drawn[#drawn+1]={image=image,x=x,y=y} end
T.eq(Skin.saveTo(skin), 'skins/native_owned', 'native skin saves through persistence owner')
local restored = assert(Skin.load('skins/native_owned','native_owned'))
T.eq(#restored.pages[1].controls, 2, 'saved skin reloads both controls')
T.eq(restored.pages[1].controls[1].spec, 'a|key:f5', 'combined binding survives disk shape')
T.eq(#Skin.list(), 1, 'library discovers the saved native skin')
local export, missing = Skin.export(restored)
T.eq(#missing, 0, 'export finds every owned asset')
T.check(files[export]:find('owned-bezel-image',1,true) ~= nil, 'export contains original bezel bytes')
T.check(files[export]:find('owned-control-image',1,true) ~= nil, 'export contains original control bytes')
local ra = assert(Skin.exportRetroArch(restored))
T.check(files[ra]:find('overlay0_desc0',1,true) ~= nil, 'RetroArch export contains actual bindings')
local delta = assert(Skin.exportDelta(restored, {system='gbc'}))
T.check(files[delta]:find('info.json',1,true) ~= nil, 'Delta export contains metadata')

-- The actual option row accepts normal input and retains other layout options.
local Version=require('src.core.GameVersion')
Version.set('crystal')
local Menu=require('src.ui.OptionsMenu')
local Stack=require('src.core.StateStack')
local g={data=T.fixtures.fresh(),save=Save.newGame(),writes=0,input={pressed={}}}
g.stack=setmetatable({},{__index=Stack});g.stack:init()
g.input.wasPressed=function(self,key) return self.pressed[key]==true end
g.writeOptions=function(self) self.writes=self.writes+1;self.persisted=Save.encode(self.save) end
g.save.options.touchControls={layouts={portrait={scale=1.2}}}
local menu=Menu.new(g);g.stack:push(menu)
-- This offered base retains upstream's actual flat OPTIONS page.
local page
for index,row in ipairs(menu.rows) do
  if row.id=='touchSkin' then menu.index=index;page=menu;break end
end
T.check(page ~= nil,'installed skin exposes a native Options row')
if page then
  g.input.pressed={right=true};page:update(1/60);g.input.pressed={}
  T.eq(g.save.options.touchControls.skin,'native_owned','normal RIGHT selects installed skin')
  T.eq(Skin.active and Skin.active.id,'native_owned','normal Options input applies real skin')
  T.eq(g.writes,1,'normal Options input writes through native owner')
  local roundTrip=assert(Save.decode(g.persisted))
  T.eq(roundTrip.options.touchControls.skin,'native_owned','save codec round-trips selected skin')
  T.eq(roundTrip.options.touchControls.layouts.portrait.scale,1.2,'skin choice retains layout preferences')
  g.input.pressed={right=true};page:update(1/60);g.input.pressed={}
  T.eq(g.save.options.touchControls.skin,nil,'normal RIGHT wraps to default pad')
  T.eq(Skin.active,nil,'default choice releases custom viewport')
end

Touch:init(); Input:init()
Touch.active = true
Touch:applyOptions({touchControls={skin='native_owned'}})
T.eq(Touch.skinId, 'native_owned', 'options select the real saved skin')
T.eq(Touch:config().skin, 'native_owned', 'editor config retains selection')
local keyEdges, speedEdges = {}, {}
love.keypressed = function(key) keyEdges[#keyEdges+1]='+'..key end
love.keyreleased = function(key) keyEdges[#keyEdges+1]='-'..key end
Touch:setHotkeyHandler(function(key, down) speedEdges[#speedEdges+1]=key..':'..tostring(down) end)
local cx,cy=Skin.controlGeometry(Skin.page(),Skin.page().controls[1],W,H)
T.check(Touch:touchpressed('one',cx,cy), 'custom A contact captured')
T.check(Touch:touchpressed('two',cx,cy), 'overlapping second contact captured')
T.check(Input:isDown('a'), 'custom A reaches real native input')
T.eq(#keyEdges,1, 'shared keyboard bind has one press edge')
Touch:touchreleased('one',cx,cy)
T.check(Input:isDown('a'), 'one release retains other A owner')
T.eq(#keyEdges,1, 'one release retains other key owner')
Touch:touchreleased('two',cx,cy)
T.check(not Input:isDown('a'), 'last release drops real native A')
T.eq(keyEdges[2],'-f5', 'last release drops native key')
local sx,sy=Skin.controlGeometry(Skin.page(),Skin.page().controls[2],W,H)
Touch:touchpressed('fast',sx,sy)
T.eq(speedEdges[1],'fast_forward_hold:true','skin speed action reaches host')
Touch:touchpressed('again',cx,cy)
Touch:reset()
T.eq(speedEdges[2],'fast_forward_hold:false','focus reset releases held speed action')
T.eq(keyEdges[#keyEdges],'-f5','focus reset releases keyboard binding')
T.check(not Input:isDown('a'), 'focus reset releases real native input')
Touch:touchpressed('reused',cx,cy)
Touch:touchpressed('reused',sx,sy)
T.check(not Input:isDown('a'), 'reused native pointer id releases previous owner')
Touch:reset()

-- Decorative desktop skins draw after composition without stealing input.
Touch.active=false; Touch.controllerHidden=true
T.check(Touch:visible(), 'desktop/controller retains bezel artwork')
T.eq(Touch:touchpressed('desktop',cx,cy),nil,'desktop bezel does not capture touch input')
Touch:draw()
T.eq(#drawn,2,'draws bezel and control once each in window space')
Touch:applyOptions({touchControls={enabled=false,skin='native_owned'}})
T.eq(Skin.active,nil,'disabling controls also clears skin viewport')
T.eq(Touch:visible(),false,'disabled skin is invisible')
Touch:applyOptions({touchControls={skin='missing'}})
T.eq(Skin.active,nil,'missing skin cannot leave stale art selected')
T.check(Touch.skinError ~= nil,'missing skin reports its load error')

-- Skin cutouts share the actual viewport owner; mod hooks keep final say.
local Hooks=require('src.mods.Hooks')
local hooks=Hooks.new()
Runtime.install(require('src.mods.Events').new(),hooks,{})
Touch:applyOptions({touchControls={skin='native_owned'}})
local x,y,w,h=Skin.viewport(W,H)
local r=V.begin(2)
T.eq(r.x,math.floor(x),'skin reserves native viewport x')
T.eq(r.y,math.floor(y),'skin reserves native viewport y')
T.eq(r.width,math.floor(w),'skin reserves native viewport width')
T.eq(r.height,math.floor(h),'skin reserves native viewport height')
local lx,ly,inside=V.toLocal(r.x+10,r.y+20)
T.eq(lx,10,'pointer maps into real cutout x')
T.eq(ly,20,'pointer maps into real cutout y')
T.check(inside,'pointer inside cutout is accepted')
V.finish({}); V.reset()
local undo=hooks:wrap('render.viewport',function(next,ctx)
  local base=next(ctx)
  T.eq(base.width,math.floor(w),'mod receives selected skin as default viewport')
  return {x=20,y=30,width=100,height=90}
end,0,'owned-fixture')
r=V.begin(2)
T.eq(r.x,20,'layout mod can override selected skin viewport')
T.eq(r.width,100,'layout mod retains final cutout authority')
V.finish({}); V.reset(); undo()
V.begin(4,false)
T.eq(V.active(),false,'existing native dual-screen layout keeps its owner')
V.finish({}); V.reset()
Skin.setActive(nil)
V.begin(2)
T.eq(V.active(),false,'no selected skin allocates no extra viewport')
V.finish({}); V.reset()

-- Real engine hotkeys must release an explicit speed override and obey locks.
local host=setmetatable({speedOverride=2,save={options={speed=1}},writes=0}, {__index=Game})
host.speedLocked=function() return false end
host.writeOptions=function(self) self.writes=self.writes+1 end
host:touchSkinHotkey('fast_forward_hold',true)
T.eq(host.speedOverride,4,'native held fast-forward engages')
host:touchSkinHotkey('fast_forward_hold',false)
T.eq(host.speedOverride,2,'native held fast-forward restores explicit override')
host:touchSkinHotkey('fast_forward_toggle',true)
T.eq(host.save.options.speed,2,'native toggle cycles persisted speed')
T.eq(host.writes,1,'native toggle persists through engine owner')
host.speedLocked=function() return true end
host:touchSkinHotkey('fast_forward_toggle',true)
T.eq(host.writes,1,'locked state blocks speed preference changes')
-- The offered native host must supply the actual lock owner; a test-only
-- speedLocked double cannot prove that a runtime skin action works.
host.speedLocked=nil
host.stack=setmetatable({},{__index=Stack});host.stack:init()
host.stack:push({isFixedSpeed=true});host.stack:push({name='options'})
T.eq(host:speedLocked(),true,'real native lock sees fixed-speed state under menu')
host.speedOverride=4
T.eq(host:logicSpeed(),1,'real lock overrides held acceleration in logic clock')
host:touchSkinHotkey('fast_forward_toggle',true)
T.eq(host.writes,1,'real lock blocks skin toggle persistence')
host.stack.states={};host.linkSession={}
T.eq(host:speedLocked(),true,'real native lock sees live link session')
host.linkSession=nil
T.eq(host:speedLocked(),false,'settled unlocked host can accelerate')
host:touchSkinHotkey('fast_forward_toggle',true)
T.eq(host.writes,2,'skin toggle reaches actual unlocked native owner')
T.finish('native custom-skin ownership, persistence, rendering and input')
