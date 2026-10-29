package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local P = require('src.render.PaletteFX')
local Font = require('src.render.Font')
local V = require('src.core.GameVersion')
local C = require('src.ui.Gen2Chrome')
local before = {mode=P.mode, shade=P.shadeMap(), version=V.get()}
require('src.core.ModCompat').install()
T.eq(require('src.ui.gen2.Chrome'),C,'public Gen2 name resolves actual native menu renderer')
Font.load(T.fixtures.fresh())
local ramp={{250,240,230},{180,170,160},{100,90,80},{20,10,0}}
local map={[0]=1,[1]=3,[2]=0,[3]=2}
P.setShadeMap(map)
for _,version in ipairs({'gold','silver','crystal','red','firered','emerald'})do
  V.set(version)
  for _,mode in ipairs({'gbc','gbc_inv','og','og_inv','classic'})do
    P.setMode(mode)
    T.same(C.throughPalette(ramp),P.effectiveColors(ramp),'menu uses actual native mode/register '..version..'/'..mode)
    -- Inversion belongs BEFORE the noncommuting shade map. Compare against
    -- the native resolved display ramp with the shade register disarmed.
    P.setShadeMap(nil);local settled=P.effectiveColors(ramp);P.setShadeMap(map)
    local reversed={settled[4],settled[3],settled[2],settled[1]}
    T.same(C.throughPalette(ramp,true),P.permute(reversed,map),'inverted text then hardware shade register '..version..'/'..mode)
    T.same(C.rawPalette(ramp,true),{ramp[4],ramp[3],ramp[2],ramp[1]},'raw palette skips native display substitutions')
  end
end
P.setShadeMap(nil);P.setMode('gbc');V.set('crystal')
local dpi=love.graphics.getDPIScale
for _,d in ipairs({1,1.5,2})do
  love.graphics.getDPIScale=function()return d end -- output metrics only
  local scale=C.fitScale(801,601)
  T.eq(scale*d,math.floor(scale*d),'native panel pixels land on framebuffer grid')
  local x,y=C.fitOrigin(801,601,scale)
  T.check(x>=0 and y>=0 and x+160*scale<=801 and y+144*scale<=601,'native panel fits its actual viewport')
end
love.graphics.getDPIScale=dpi
T.eq(C.number(23,4,false),'  23','native padded number')
T.eq(C.number(23,4,true),'0023','native zero-filled number')
T.eq(C.money(23),'    ¥23','native floating yen field')
T.same(C.wrap('ONE TWO\nTHREE',7),{'ONE TWO','THREE'},'cart hard line break retained')
local chosen,cancel,moved
local list=C.List.new({items={{label='ONE',value=1},{label='TWO',value=2,disabled=true},{label='THREE',value=3}},rows=2,onChoose=function(v)chosen=v end,onCancel=function()cancel=true end,onMove=function(v)moved=v end})
local input=require('src.core.Input');input:init()
local function tap(key)input:keypressed(key);input:step();local out=list:update(input);input:keyreleased(key);input:step();return out end
T.check(tap('down'),'real native down edge consumed')
T.eq(list.index,2,'list moves once per native edge');T.eq(moved,2,'movement callback follows actual item')
tap('z');T.eq(chosen,nil,'disabled entry cannot be selected')
tap('down');T.eq(list.scroll,1,'native list scrolls into actual item')
tap('z');T.eq(chosen,3,'real native A selects current item')
tap('down');T.eq(list.index,1,'native list wraps at end')
tap('x');T.eq(cancel,true,'real native B cancels list')

-- Real native box and font calls, with only the output APIs recorded.
local draw,rect=love.graphics.draw,love.graphics.rectangle
local drawn,filled=0,0
love.graphics.draw=function(...)drawn=drawn+1;return draw(...)end
love.graphics.rectangle=function(...)filled=filled+1;return rect(...)end
C.clear();C.textbox(0,12,18,4);C.print('ONE',1,13);C.cursor(1,1);list:draw()
T.check(drawn>0 and filled>0,'native chrome actually renders font, box and paper')
local shader={tag='caller'};love.graphics.setShader(shader)
T.raises(function()C.withPanel(800,600,1,1,1,function()love.graphics.setShader({});error('panel body probe')end)end,'panel body probe','panel propagates actual draw failure')
T.eq(love.graphics.getShader(),shader,'panel restores native graphics state on failure')
love.graphics.setShader();love.graphics.draw,love.graphics.rectangle=draw,rect
-- Exercise the shaded path too; only the GPU uniform sink is replaced.
local nativeShader=P.shader
local uniforms={}
local output={send=function(_,key,value)uniforms[key]=value end}
P.shader=function()return output end
P.setShadeMap(map)
local caller={tag='native caller'};love.graphics.setShader(caller)
local expected=P.effectiveColors(ramp,true)
C.printThrough('ONE',1,1,ramp,true)
T.same(uniforms.c0,{expected[1][1]/255,expected[1][2]/255,expected[1][3]/255},'glyph shader receives once-resolved native paper')
T.same(uniforms.c3,{expected[4][1]/255,expected[4][2]/255,expected[4][3]/255},'glyph shader receives once-resolved native ink')
T.eq(love.graphics.getShader(),caller,'palette text restores actual caller shader')
T.eq(P.shadeMap(),map,'chrome does not replace native shade register')
P.shader=nativeShader;love.graphics.setShader()
P.setMode(before.mode);P.setShadeMap(before.shade);V.set(before.version)
T.finish('native Gen2 shared menu chrome')
