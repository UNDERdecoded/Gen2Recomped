package.path = './?.lua;./?/init.lua;' .. package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Data=require('src.core.Data')
local Hud=require('src.render.HudTiles')
local Palette=require('src.render.PaletteFX')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local previous,oldFont=Version.get(),Data.font
local function fixture(version)
  Version.set(version)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation(version)
  require('src.render.Font').load(data)
  local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
  local b=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  b.queue,b.current={},nil
  b.introSlide,b.introBalls,b.enemySendingOut,b.showEnemyTrainer=0,nil,nil,nil
  b.showPlayerBack,b.sendingOut=nil,nil
  return b
end
local function tiles(screen)
  local actual=Hud.tile;local rows={}
  -- Capture only the final native tile output. HP, palette selection and
  -- queue stepping are real; no battle or HP implementation is mocked.
  Hud.tile=function(code,x,y,_,paint) rows[#rows+1]={code=code,x=x,y=y,paint=paint}end
  local ok,why=pcall(screen.drawHUDs,screen,0)
  Hud.tile=actual;assert(ok,why)
  return rows
end
local function fill(rows,side)
  local x,y=side=='enemy' and 32 or 96,side=='enemy' and 16 or 72
  local pixels=0
  for _,row in ipairs(rows)do
    if row.y==y and row.x>=x and row.x<x+48 and row.code>=0x63 and row.code<=0x6b then
      pixels=pixels+row.code-0x63
    end
  end
  return pixels
end
for _,edition in ipairs({'gold','silver','crystal'})do
  local b=fixture(edition)
  local mon=b.enemy.mon
  mon.stats.hp,mon.hp,b.enemy.shownHP=19,16,19
  b:drainNext(b.enemy);b:updateQueue()
  T.eq(b:hudHp(mon,'enemy'),19,'public HUD reads real pre-drain displayed HP')
  for i,expected in ipairs({47,47,46,46,45,45})do
    b:updateQueuePresentation()
    T.eq(b:hudHpPixels(mon,'enemy'),expected,edition..' public pixel view follows real animation')
    T.eq(fill(tiles(b),'enemy'),expected,edition..' native HUD writes every short-loop pixel')
    if i==1 then T.eq(b:hudHp(mon,'enemy'),19,'number repeats while actual fill moves')end
  end
  local frames=0
  while b:updateQueuePresentation()and frames<2000 do frames=frames+1 end
  T.eq(b:hudHp(mon,'enemy'),16,'retired HUD keeps displayed native target')
  T.eq(fill(tiles(b),'enemy'),40,'retired bar uses exact GSC pixel ratio')
  mon.stats.hp,mon.hp,b.enemy.shownHP=383,190,190
  T.eq(b:hudHpPixels(mon,'enemy'),24,'public view retains high-HP byte-divisor rounding')
  T.eq(fill(tiles(b),'enemy'),24,'native HUD retains high-HP byte-divisor rounding')
  T.eq(Palette.barPalName(190,383),'GREENBAR','party/summary and battle agree on GSC half-HP green')
  T.eq(Palette.barPalName(9,48),'REDBAR','GSC red ends below ten pixels')
  T.eq(Palette.barPalName(10,48),'YELLOWBAR','GSC yellow begins at ten pixels')
  T.eq(Palette.barPalName(23,48),'YELLOWBAR','GSC yellow ends below half HP')
  T.eq(Palette.barPalName(24,48),'GREENBAR','GSC green begins at half HP')
  T.eq(Palette.barPalName(19,19,23),'YELLOWBAR','zone color uses animated pixels while the number repeats')
  -- Reading/drawing cannot run damage, spend PP, or advance the HP timeline.
  local hp,anim=b.enemy.shownHP,b.hpAnim
  tiles(b);tiles(b)
  T.eq(b.enemy.shownHP,hp,'draws leave the displayed HP clock alone')
  T.eq(b.hpAnim,anim,'draws preserve native animation identity')
end
do
  local b=fixture('crystal');local mon=b.enemy.mon
  mon.stats.hp,mon.hp,b.enemy.shownHP=19,3,19
  b:drainNext(b.enemy);b:updateQueue();b:updateQueuePresentation()
  T.eq(b:hudHpPixels(mon,'enemy'),47,'native short loop starts its actual pixel cursor')
  local native=b.stepHpAnim
  b.stepHpAnim=function(self)
    self.shownHp.enemy=self.shownHp.enemy-2
    return true
  end
  b:updateQueuePresentation()
  T.eq(b:hudHp(mon,'enemy'),17,'wide decorator owns its displayed increment')
  T.eq(b.hpAnim.bar,nil,'wide increment retires the stale cartridge pixel cursor')
  T.eq(fill(tiles(b),'enemy'),42,'fallback HUD follows the wider displayed value')
  b.stepHpAnim=native;b:updateQueuePresentation()
  T.check(b:hudHp(mon,'enemy')<=17,'returning to native stepping never reverses damage display')
  T.eq(fill(tiles(b),'enemy'),41,'native cursor resumes from the actual wider displayed value')
  local frames=0
  while b:updateQueuePresentation()and frames<2000 do frames=frames+1 end
  T.check(frames<2000,'display owner handoff still completes its actual queue beat')
  T.eq(mon.hp,3,'handoff never changes resolved damage')
end
do
  Version.set('crystal')
  -- Keep imported hack geometry, including its explicit palette thresholds.
  Data.font={hud={hpBarTiles=7,hpBarGreenPixels=28,hpBarYellowPixels=12}}
  T.eq(Hud.hpPixels(383,383),56,'wider imported HUD retains all seven full segments')
  T.eq(Hud.hpPixels(1,999),1,'wider living bar retains one pixel')
  T.eq(Palette.barPalName(190,383),'GREENBAR','explicit hack threshold uses its scaled fill')
  T.eq(Hud.geometry().hpBarYellowPixels,12,'explicit imported yellow threshold retained')
  -- Changing editions with the SAME font object must not keep GSC defaults.
  Data.font={hud={}}
  T.eq(Hud.geometry().hpBarGreenPixels,24,'GSC defaults apply without imported override')
  Version.set('red')
  T.eq(Hud.geometry().hpBarGreenPixels,27,'Gen1 cache switches back to its own defaults')
  T.eq(Palette.barPalName(24,48),'YELLOWBAR','Gen1 existing threshold retained')
  Version.set('crystal')
  T.eq(Hud.geometry().hpBarGreenPixels,24,'returning to GSC restores native defaults')
end
for _,edition in ipairs({'red','firered','emerald'})do
  Version.set(edition);Data.font=nil
  T.eq(Hud.hpPixels(190,383),23,edition..' existing ratio remains unchanged')
  T.eq(Palette.barPalName(24,48),'YELLOWBAR',edition..' existing threshold remains unchanged')
end
Data.font=oldFont;Hud.invalidate();Version.set(previous)
T.finish('native GSC HUD pixel output, palette boundaries and live HP view')
