package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Gen4 keyboard/controller bindings')
local V=require('src.core.GameVersion');V.set('platinum')
local Input=require('src.core.Input')
local Pads=require('src.core.GamepadMap')
local Menu=require('src.ui.BindingsMenu')
local function edge(action,alias)
 Input:step();T.check(Input:wasPressed(action),action..' native edge');T.check(Input:wasPressed(alias),action..' gameplay alias')
end
for _,nx in ipairs({false,true}) do
 Pads._setForceNXForTests(nx);Input:init()
 Input:keypressed('/');edge('x','start');Input:keyreleased('/');T.check(not Input:isDown('x'),'slash release')
 Input:keypressed("'");edge('y','select');Input:keyreleased("'");T.check(not Input:isDown('y'),'quote release')
 Input:keypressed('x');Input:step();T.check(Input:wasPressed('b'),'keyboard X still cancels');Input:keyreleased('x')
 for _,case in ipairs({{'y','x','start'},{'x','y','select'}}) do
  Input:gamepadpressed(nil,case[1]);edge(case[2],case[3]);Input:gamepadreleased(nil,case[1]);T.check(not Input:isDown(case[2]),'controller face release')
 end
 for _,case in ipairs({{3,'y','select'},{4,'x','start'}}) do
  Input:joystickpressed(nil,case[1]);edge(case[2],case[3]);Input:joystickreleased(nil,case[1]);T.check(not Input:isDown(case[2]),'raw face release')
 end
 local game={input=Input,save={options={}},stack={push=function() end,pop=function() end},writeOptions=function() end}
 local menu=Menu.new(game)
 local rows={};for _,item in ipairs(menu.items) do rows[item.button.id]=item end
 T.check(rows.x and rows.y,'Gen4 controls has both rows')
 T.eq(rows.x.right,nx and 'SLASH/X' or 'SLASH/Y','X row uses physical controller label')
 T.eq(rows.y.right,nx and 'QUOTE/Y' or 'QUOTE/X','Y row uses physical controller label')
 T.eq(rows.a.button.id,'a','A row retained');T.eq(rows.b.right,'X/B','keyboard X label never gets Nintendo pad translation')
 -- Capture only commits on release and swaps the previous owner's mapping.
 menu:beginCapture(rows.x);menu:captureKey("'")
 T.eq(game.save.options.bindings,nil,'key press waits for release')
 menu:captureKeyRelease("'")
 T.eq(game.save.options.bindings.x.key,"'",'X key saved');T.eq(game.save.options.bindings.y.key,'/','Y key swapped')
 menu:commitBindings();Input:reset();Input:keypressed("'");edge('x','start');Input:keyreleased("'")
 Input:keypressed('/');edge('y','select');Input:keyreleased('/')
 menu:beginCapture(rows.x);menu:capturePad('x');menu:capturePadRelease('x')
 T.eq(game.save.options.bindings.x.pad,'x','X controller saved');T.eq(game.save.options.bindings.y.pad,'y','Y controller swapped')
 menu:commitBindings();Input:reset();Input:gamepadpressed(nil,'x');edge('x','start');Input:gamepadreleased(nil,'x')
 menu:clearBinding(rows.x);menu:clearBinding(rows.y);menu:commitBindings();Input:reset()
 Input:keypressed('/');edge('x','start');Input:keyreleased('/')
 Input:gamepadpressed(nil,'y');edge('x','start');Input:gamepadreleased(nil,'y')
 menu:beginCapture(rows.y);menu:captureJoy(11);menu:captureJoyRelease(11);menu:commitBindings();Input:reset()
 Input:joystickpressed(nil,11);edge('y','select');Input:joystickreleased(nil,11);T.check(not Input:isDown('y'),'custom raw controller releases')
 local confirmation
 game.stack.push=function(_,s) confirmation=s end
 menu:confirmReset();confirmation.onChoose(true);menu:commitBindings();Input:reset()
 T.eq(game.save.options.bindings,nil,'reset all clears X/Y overlays')
 T.eq(rows.x.right,nx and 'SLASH/X' or 'SLASH/Y','reset restores X row label')
 T.eq(rows.y.right,nx and 'QUOTE/Y' or 'QUOTE/X','reset restores Y row label')
 Input:keypressed("'");edge('y','select');Input:keyreleased("'")
end
Pads._setForceNXForTests(false)
for _,version in ipairs({'red','gold','crystal','emerald','firered'}) do
 V.set(version);Input:init()
 local menu=Menu.new({input=Input,save={options={}}})
 for _,item in ipairs(menu.items) do T.check(item.button.id~='x' and item.button.id~='y',version..' has no DS-only rows') end
 Input:keypressed('/');Input:step();T.check(not Input:wasPressed('start'),version..' no X-to-menu alias');Input:keyreleased('/')
 Input:keypressed("'");Input:step();T.check(not Input:wasPressed('select'),version..' no Y-to-item alias');Input:keyreleased("'")
end
T.finish()
