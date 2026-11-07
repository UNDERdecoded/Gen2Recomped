local V=...
local Native={}
local Camera=require('src.render.Gen4Camera')
local Voxel=V.require('VoxelState')
local lastLevel,lastChosen,manualCamera
local battleTime=0
local battleCamera,battleEnabled
function Native.battleLive()
 local game=require('src.core.Game')
 local top=game.stack and game.stack:top()
 return battleEnabled and battleEnabled() and Native.supports(game.overworld)
  and top and top.gen4Layout and top:gen4Layout() or false
end
function Native.tick(dt)
 battleTime=battleTime+(dt or 0)
 if battleCamera and Native.battleLive() then
  battleCamera.steerable=true
  V.require('CamControl').tick(dt)
  battleCamera.update(dt)
 end
end
function Native.supports(state)
 local map=state and state.map
 return map and map.def and map.def.generation==4 or false
end
function Native.update(state,level)
 if not Native.supports(state) then Camera.setExternalTilt(nil);return false end
 level=tonumber(level) or 0
 if level~=lastLevel then manualCamera=false
 elseif lastChosen and Camera.chosen~=lastChosen then manualCamera=true end
 lastLevel,lastChosen=level,Camera.chosen
 local choice
 if level==Voxel.FP_LEVEL then choice='first'
 elseif level==Voxel.TP_LEVEL then choice='third'
 elseif level==Voxel.FULL_LEVEL then choice='cartridge'
 elseif level>0 then choice=Voxel.ANGLES_DEG[level+1] end
 if manualCamera then choice=nil end
 Camera.setExternalTilt(choice)
 local ground=state.map.renderer and state.map.renderer.gen4Ground
 if ground and ground.tiltGeneration~=Camera.generation then
  ground:dropBakes();ground:applyCamera()
 end
 return true
end
-- Decline the voxel override so OverworldController draws native terrain,
-- props, characters and field effects together, with its shared depth pass.
function Native.drawWorld(state) return Native.supports(state) end
-- Native battles keep Platinum's healthboxes, menus and animation handlers.
-- The terrain uses a native camera; actors retain Platinum's battle layout.
function Native.installBattles(enabled,controls)
 battleEnabled,battleCamera=enabled,controls
 -- the surface these battles draw on takes the window's shape (NativeWide)
 V.require('NativeWide').install(enabled,Native.supports)
 local Battle=require('src.battle.Gen4Battle')
 local View=require('src.render.Gen4View')
 local Ground=require('src.render.Gen4Ground')
 local fullDraw=Battle.draw
 local rawSetScissor,rawInterScissor,rawGetScissor=love.graphics.setScissor,love.graphics.intersectScissor,love.graphics.getScissor
 function Battle.draw(battle)
  local scale=Ground.syncRenderScale(battle.game)
  if not enabled() or not Native.supports(battle.game and battle.game.overworld) or scale<=1 then return fullDraw(battle) end
  local w=Battle.width(battle);local h=select(2,battle:uiSize())
  local canvas=battle.dramaticNativeSurface
  if not canvas or canvas:getWidth()~=w*scale or canvas:getHeight()~=h*scale then
   canvas=love.graphics.newCanvas(w*scale,h*scale);canvas:setFilter('nearest','nearest');battle.dramaticNativeSurface=canvas
  end
  local g=love.graphics
  -- pop('all') puts the caller's canvas back WITH its depth attachment; a
  -- setCanvas(getCanvas()) after it would drop the depth and is not needed
  g.push('all');g.setCanvas(canvas);g.clear(0,0,0,0);g.origin();g.scale(scale)
  -- the scissor is in this canvas's pixels and the transform does not reach it
  -- (the panel's backdrop and the battlers' clips were cut to a third of themselves)
  local setS,interS,getS=g.setScissor,g.intersectScissor,g.getScissor
  g.setScissor=function(x,y,sw,sh)
   if x then return rawSetScissor(x*scale,y*scale,sw*scale,sh*scale) end
   return rawSetScissor()
  end
  g.intersectScissor=function(x,y,sw,sh) return rawInterScissor(x*scale,y*scale,sw*scale,sh*scale) end
  g.getScissor=function()
   local x,y,sw,sh=rawGetScissor()
   if not x then return nil end
   return x/scale,y/scale,sw/scale,sh/scale
  end
  rawSetScissor()
  local ok,err=pcall(fullDraw,battle)
  g.setScissor,g.intersectScissor,g.getScissor=setS,interS,getS
  g.pop()
  if not ok then error(err,0) end
  g.setColor(1,1,1,1);g.draw(canvas,0,0,0,1/scale,1/scale)
  local renderer=battle.game.renderer
  -- only while nothing is over it: the big canvas holds the battle alone, and
  -- a prompt drawn after it went to the ordinary one, unseen
  local stack=battle.game.stack
  if renderer and (not stack or stack:top()==battle) then renderer.uiOverride=canvas end
 end
 local field,position=Battle.drawField,Battle.battlerPos
 local actors,trainer=Battle.drawBattlers,Battle.drawTrainerBack
 local enemyTrainer=Battle.drawEnemyTrainer
 local Stage=V.require('NativeStage')
 -- WHERE THIS BATTLE STANDS (NativeStage): chosen once per battle on the
 -- ground round the player, then shot by a camera solved to it.
 local DIRS={up={0,-1},down={0,1},left={-1,0},right={1,0}}
 local function stageFor(battle,state,ground)
  local st=battle.dramaticNativeStage
  if st then return st end
  local map,p=state.map,state.player
  local cx,cy=p.cellX or 0,p.cellY or 0
  local surfing=p.surfing and true or false
  -- FISHING: a wild fight with water dead ahead of a player standing on
  -- land -- the foe came out of that water, so it may stand on it
  local fishing=false
  local d=DIRS[p.facing]
  if not surfing and battle.kind=='wild' and d and map.isWaterCell then
   local okW,water=pcall(map.isWaterCell,map,cx+d[1],cy+d[2])
   if okW and water then
    local intro=tostring(battle.introText or ''):lower()
    local okE,enc=pcall(function() return map.isEncounterCell and map:isEncounterCell(cx,cy) end)
    fishing=intro:find('hook',1,true)~=nil or not (okE and enc)
   end
  end
  local okD,double=pcall(function() return battle.isDouble and battle:isDouble() end)
  st=Stage.plan(map,cx,cy,p.facing,{surfing=surfing,fishing=fishing,double=okD and double or false,
   groundY=function(x,y) return ground:groundY(x*16+8,y*16+8) end})
  st.fishing=fishing
  battle.dramaticNativeStage=st
  return st
 end
 local function slotOf(self,mon)
  if Battle.doubleSlots and Battle.doubleSlots(self) then
   for p=0,3 do
    local okB,b=pcall(self.battlerAt,self,p)
    if okB and b==mon then return p+2 end
   end
  end
  if mon==self.player then return 0 end
  return 1
 end
 local function context(battle)
  local game=battle and battle.game
  local state=game and game.overworld
  if not enabled() or not Native.supports(state) then return nil end
  return state,state.map.renderer and state.map.renderer.gen4Ground
 end
 function Battle.drawField(battle)
  battle.dramaticNativePositions=nil
  battle.dramaticNativeActors=false
  local state,ground=context(battle)
  if not ground or ground.noDepth or battle.blankForAskName then return field(battle) end
  Ground.syncRenderScale(battle.game)
  local W=Battle.width(battle)
  local ox,oz=ground.offsetX or 0,ground.offsetY or 0
  local st=stageFor(battle,state,ground)
  battle.dramaticNativeView=battle.dramaticNativeView or View.new('third')
  local view=battle.dramaticNativeView
  view.fovY=Stage.FOV_Y
  -- Keep this rig separate from the player's saved overworld orbit.
  local look=View.look
  -- the shot at rest, solved once per battle (and per surface width)
  local sol=battle.dramaticNativeSolve
  if not sol or battle.dramaticNativeSolveWidth~=W then
   local okS,s=pcall(Stage.solve,st,view,View,ground,W,192)
   View.look=look
   sol=okS and s or {x=(st.cx*16+8)+ox,z=(st.cy*16+8)+oz,zoom=1.5,yaw=0.25,rise=0,baseY=ground:groundY(st.cx*16+8,st.cy*16+8)}
   battle.dramaticNativeSolve,battle.dramaticNativeSolveWidth=sol,W
  end
  -- ...then the player's steer and a slow drift on top of it
  View.look={orbiting=true,yaw=sol.yaw+(controls and controls.orbit or 0)+math.sin(battleTime*0.15)*0.04,
   rise=sol.rise+(controls and controls.pitch or 0)*30,zoom=sol.zoom*(controls and controls.zoom or 1)}
  view:follow(sol.x,sol.z,0,sol.baseY)
  View.look=look
  local previous=ground.view3d
  local publish=ground.suppressWorldOverride
  ground.suppressWorldOverride=true
  ground.view3d=view
  local ok,err=pcall(function()
   if not ground:drawFree(W,192) then return end
   local marks={}
   local depths={}
   local feet={}
   local ppus={}
   for slot=0,5 do
    -- Native slots include the extra width on the opponent's side. Trainer
    -- backs, send-outs and move effects all read these same positions.
    local target=position(battle,slot)
    if target then
     local wx,wz=Stage.point(st,slot)
     local x,y,ppu,depth
     local gy=wx and ground:groundY(wx,wz)
     if wx then x,y,ppu,depth=view:project(wx+ox,gy,wz+oz,W,192) end
     if x then
      -- the depth it is tested at is taken a little toward the eye, so the
      -- grass on its own cell does not swallow it (NativeStage.DEPTH_PULL)
      local vx,vy,vz=(view.x or 0)-(wx+ox),(view.y or 0)-gy,(view.z or 0)-(wz+oz)
      local len=math.sqrt(vx*vx+vy*vy+vz*vz)
      if len>Stage.DEPTH_PULL*2 then
       local t=Stage.DEPTH_PULL/len
       local _,_,_,pulled=view:project(wx+ox+vx*t,gy+vy*t,wz+oz+vz*t,W,192)
       if pulled then depth=pulled end
      end
      ppu=ppu or 1
      feet[slot]={x=x,y=y};ppus[slot]=ppu
      -- the middle of a typical 80px frame drawn at this stage's size, which
      -- is where a move's effect aims (the native pos is the frame's centre)
      local k=ppu*16*Stage.MON_FRAME_TILES/80
      marks[slot]={x=x,y=y-40*k}
      depths[slot]=depth and depth-0.00002
     else
      marks[slot]=target
     end
    end
   end
   battle.dramaticNativeScales=ppus
   battle.dramaticNativeFeet=feet
   battle.dramaticNativePositions=marks
   local own=rawget(battle,'drawBattlerPic')
   local draw=battle.drawBattlerPic
   battle.drawBattlerPic=function(self,mon,...)
    local args={...};local slot=slotOf(self,mon)
    if not (depths[slot] and feet[slot]) then return end
    return ground:withFreeDepth(depths[slot],function()
     local g=love.graphics;local mark=marks[slot];local ft=feet[slot]
     local picture=self.battlerPic and self:battlerPic(mon)
     local ph=(picture and picture:getHeight()) or 80
     -- every frame the same height in the WORLD (NativeStage.MON_FRAME_TILES),
     -- scaled about the feet so the mon stays standing on its cell
     local k=ppus[slot]*16*Stage.MON_FRAME_TILES/math.max(1,ph)
     g.push();g.origin();g.scale(Ground.renderScale())
     g.translate(ft.x,ft.y);g.scale(k,k);g.translate(-ft.x,-ft.y)
     -- drawBattlers centres the frame on `mark` and lowers it by the
     -- species' own empty rows, which puts the visible feet at mark + h/2:
     -- move that onto the stage point
     g.translate(0,ft.y-mark.y-ph/2)
     local ok,err=pcall(draw,self,mon,unpack(args));g.pop()
     if not ok then error(err,0) end
    end)
   end
   -- BLACK AND WHITE stand slots 0/1 on their own 3D field's platforms
   -- (Gen5BattleSceneView) rather than on battlerPos; for this pass the
   -- stage is the field, so they are drawn where the stage put them
   local okV,G5V=pcall(require,'src.render.Gen5BattleSceneView')
   local available=okV and G5V and G5V.available
   if available then G5V.available=function() return false end end
   local okActors,actorError=pcall(actors,battle)
   if available then G5V.available=available end
   battle.drawBattlerPic=own
   if not okActors then error(actorError,0) end
   if depths[0] and feet[0] and battle.playerBackPic and (battle.showPlayerBack or battle.dsBackLeave) then
    ground:withFreeDepth(depths[0],function()
     local image=battle.picImage and battle:picImage(battle.playerBackPic) or battle.playerBackPic
     if image and image.getDimensions then
      local iw,ih=image:getDimensions();local ft=feet[0]
      local k=ppus[0]*16*Stage.TRAINER_FRAME_TILES/math.max(1,ih)
      love.graphics.setColor(1,1,1,1)
      love.graphics.push();love.graphics.origin();love.graphics.scale(Ground.renderScale())
      -- THE DS BACK IS AN ANIMATED STRIP (Gen4Battle.dsBackFrame): the still is
      -- only its measure. Black and White's still is cell 0 and has no throwing
      -- arm at all, so drawing it left the figure armless through the throw.
      -- The strip's dx, dy run from the still's centre to the strip's corner, so
      -- the still's foot (where the stage stands it) is at (-dx, ih/2 - dy).
      local sheet,quad,rec,off
      if Battle.dsBackFrame then sheet,quad,rec,off=Battle.dsBackFrame(battle) end
      if sheet then
       love.graphics.draw(sheet,quad,ft.x+off,ft.y,0,k,k,-rec.dx,ih/2-rec.dy)
      elseif battle.showPlayerBack then
       love.graphics.draw(image,ft.x,ft.y,0,k,k,iw/2,ih)
      end
      love.graphics.pop()
     end
    end)
   end
   battle.dramaticNativeActors=true
   ground:endFree()
  end)
  ground:endFree();ground.view3d=previous;ground.suppressWorldOverride=publish
  if not ok then error(err,0) end
  if not battle.dramaticNativePositions then return field(battle) end
 end
 function Battle.battlerPos(battle,slot)
  return battle.dramaticNativePositions and battle.dramaticNativePositions[slot] or position(battle,slot)
 end
 function Battle.drawBattlers(battle)
  if not battle.dramaticNativeActors then return actors(battle) end
 end
 function Battle.drawTrainerBack(battle)
  if not battle.dramaticNativeActors then return trainer(battle) end
 end
 -- THE OPPOSING TRAINER, at the stage's size: drawn by the native layout at
 -- the foe's battlerPos (the stage point, through the override above) but at
 -- its own 80px, which beside a tile-high Pokemon read as a giant. Scaled
 -- about the foe's feet so it stands on the same cell.
 if enemyTrainer then
  function Battle.drawEnemyTrainer(battle)
   local feet=battle.dramaticNativeActors and battle.dramaticNativeFeet
   local ft=feet and feet[1]
   local mark=battle.dramaticNativePositions and battle.dramaticNativePositions[1]
   local ppu=battle.dramaticNativeScales and battle.dramaticNativeScales[1]
   if not (ft and mark and ppu and battle.trainerPic) then return enemyTrainer(battle) end
   local img=battle.picImage and battle:picImage(battle.trainerPic) or battle.trainerPic
   local ih=(img and img.getHeight and img:getHeight()) or 80
   local k=ppu*16*Stage.TRAINER_FRAME_TILES/math.max(1,ih)
   local g=love.graphics
   g.push();g.translate(ft.x,ft.y);g.scale(k,k);g.translate(-ft.x,-ft.y)
   -- the native draw centres the pic on `mark`; put its bottom on the feet
   g.translate(0,ft.y-mark.y-ih/2)
   local ok,r=pcall(enemyTrainer,battle);g.pop()
   if not ok then error(r,0) end
   return r
  end
 end
end
return Native
