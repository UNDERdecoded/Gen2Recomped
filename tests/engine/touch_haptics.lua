-- Native haptic preferences and input edges. No physical vibrator claim.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Touch=require('src.core.TouchControls')
local Skin=require('src.core.TouchSkin')
local Input=require('src.core.Input')
local Save=require('src.core.SaveData')
local Version=require('src.core.GameVersion')
T.eq(Touch.normalizeHaptics(nil),'light')
T.eq(Touch.normalizeHaptics('physical'),'light')
T.eq(Touch.normalizeHaptics('medium'),'normal')
T.eq(Touch.normalizeHaptics('heavy'),'strong')
T.eq(Touch.normalizeHaptics('bad'),'light')
T.eq(Touch.cycleHaptics('strong',1),'off')
T.eq(Touch.cycleHaptics('off',-1),'strong')
for _,level in ipairs{'off','light','normal','strong'}do
  T.eq(Touch.hapticLabel(level),level:upper(),'native haptic label')
end
love.system=love.system or {}
local oldOS,oldVibrate=love.system.getOS,love.system.vibrate
love.system.getOS=oldOS or function() return "Linux" end
local pulses={}
love.system.vibrate=function(seconds)pulses[#pulses+1]=seconds end
T.eq(Touch.buzz('off'),false,'OFF never pulses')
for _,row in ipairs{{'light',.012},{'normal',.025},{'strong',.045}}do
  T.check(Touch.buzz(row[1]),'supported level requests a pulse')
  T.eq(pulses[#pulses],row[2],'duration follows reference preset')
end
love.system.vibrate=nil
T.eq(Touch.buzz('light'),false,'runtime without vibrator remains usable')
love.system.vibrate=function(seconds)pulses[#pulses+1]=seconds end
Version.set('crystal');Input:init();Touch:init();Touch.active=true
Touch:applyOptions({haptics='normal'})
local skin=Skin.newSkin('haptic-memory')
skin.pages[1].controls={Skin.newControl('a',.8,.8,.2,.2,'rect'),
  Skin.newControl('key:f5',.2,.8,.2,.2,'rect')}
Skin.setActive(skin)
local w,h=love.graphics.getDimensions()
local ax,ay=Skin.controlGeometry(Skin.page(),Skin.page().controls[1],w,h)
local kx,ky=Skin.controlGeometry(Skin.page(),Skin.page().controls[2],w,h)
local n=#pulses
T.check(Touch:touchpressed('one',ax,ay))
T.eq(#pulses,n+1,'first native button owner pulses')
Touch:touchpressed('two',ax,ay)
T.eq(#pulses,n+1,'second owner of held button does not pulse')
Touch:touchmoved('one',ax,ay)
T.eq(#pulses,n+1,'stationary held contact does not pulse')
Touch:touchreleased('one',ax,ay)
T.check(Input:isDown('a'),'first release retains other owner')
Touch:touchreleased('two',ax,ay)
T.eq(#pulses,n+1,'release does not pulse')
T.check(not Input:isDown('a'))
Touch:touchpressed('key-one',kx,ky)
T.eq(#pulses,n+2,'key-only control pulses on its first owner')
Touch:touchpressed('key-two',kx,ky)
T.eq(#pulses,n+2,'shared key owner does not retrigger vibration')
Touch:reset()
T.eq(#pulses,n+2,'focus reset releases holds without a new pulse')
Touch.haptics='off';Skin.setActive(skin)
Touch:touchpressed('off',ax,ay);Touch:touchreleased('off',ax,ay)
T.eq(#pulses,n+2,'OFF preference applies to actual skin input')
Skin.setActive(nil)
T.eq(Touch:config().haptics,nil,'layout snapshots do not relocate the global preference')
T.eq(Save.defaultOptions().haptics,'light','new native options retain the reference default')

-- Normal OPTIONS input, not direct calls to the row implementation.
love.system.getOS=function()return 'Android'end
local Stack=require('src.core.StateStack')
local game={data=T.fixtures.fresh(),save=Save.newGame(),writes=0,input={pressed={}}}
game.stack=setmetatable({},{__index=Stack});game.stack:init()
game.input.wasPressed=function(self,key)return self.pressed[key]end
game.writeOptions=function(self)self.writes=self.writes+1;self.persisted=Save.encode(self.save)end
local menu=require('src.ui.OptionsMenu').new(game);game.stack:push(menu)
local page
for index,row in ipairs(menu.rows) do
  if row.id=='haptics' then menu.index=index;page=menu;break end
end
T.check(page~=nil,'mobile native options offer haptic intensity')
if page then
  game.input.pressed={right=true};page:update(1/60);game.input.pressed={}
  T.eq(game.save.options.haptics,'normal','normal RIGHT changes haptic preference')
  T.eq(Touch.haptics,'normal','native controller applies the chosen intensity')
  T.eq(game.writes,1,'normal input persists exactly one change')
  local saved=assert(Save.decode(game.persisted))
  T.eq(saved.options.haptics,'normal','native save codec retains haptics')
end
love.system.getOS, love.system.vibrate=oldOS,oldVibrate
Touch:reset();Skin.setActive(nil)
T.finish('native haptics preferences, ownership edges and normal options input')
