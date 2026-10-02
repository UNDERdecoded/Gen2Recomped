package.path='./?.lua;'..package.path
local View=require('src.render.Gen4View')
for _,mode in ipairs({'third','field3d'}) do
 View.look={zoom=1,orbiting=true,yaw=0,rise=0}
 local view=View.new(mode);view.config={distance=512};view.fieldPitch=59
 view:follow(0,0,0,0);local far=math.sqrt(view.x^2+view.z^2);local fov=view.fovY
 for i=1,40 do view:zoomBy(-1) end
 view:follow(0,0,0,0);local close=math.sqrt(view.x^2+view.z^2)
 assert(close<far*.1,'camera must move toward player at close stop')
 assert(view.fovY==fov,'zoom must not change lens FOV')
end
-- Orthographic headers are common indoors. Eye distance has no effect on
-- their projected size; terrain and sprite projection must share zoom scale.
for _,pitch in ipairs({30,59,80}) do
 View.look={zoom=1,orbiting=false,yaw=0,rise=0}
 local view=View.new('field3d')
 view.config={distance=512,projection='orthographic'};view.fieldPitch=pitch
 view:follow(0,0,0,0)
 local x,y,scale=view:project(16,0,0,256,192)
 assert(x and scale==1)
 view:zoomBy(-4);view:follow(0,0,0,0)
 local zx,zy,zscale=view:project(16,0,0,256,192)
 local cx,cy=view:project(0,0,0,256,192)
 assert(math.abs(cx-128)<1e-5 and math.abs(cy-96)<1e-5,'tilted zoom lost its target')
 assert(zscale>scale and math.abs((zx-128)/(x-128)-zscale)<1e-5,'terrain/sprite zoom disagree')
 view:zoomBy(8);view:follow(0,0,0,0)
 local ox,oy,oscale=view:project(16,0,0,256,192)
 assert(oscale<1 and math.abs(ox-128)<math.abs(x-128),'zoom out does not widen tilted view')
end
local root='G:/Gen2Recomped/platinum/data/generated/'
local data={maps=assert(loadfile(root..'maps.lua'))(),map_scripts=assert(loadfile(root..'map_scripts.lua'))()}
local VM=require('src.script.Gen4ScriptVM')
local rows=assert(VM.resolveTalk(data,'D01R0102',1,nil),'Roark fallback did not resolve')
local messages,flags={},{}
for _,row in ipairs(rows) do
 assert(row[1]~='g4_unimplemented','Roark still has an unimplemented command')
 if row[1]=='g4_message' then messages[row[2]]=true end
 if row[1]=='set_flag' then flags[row[2]]=true end
end
assert(messages[0] and messages[1],'both mine dialogue lines must be present')
assert(flags.FLAG_G4_007A and flags.FLAG_G4_017C,'Roark departure story flags missing')
local text=assert(loadfile(root..'text.lua'))()
for id in pairs(messages) do
 local key=require('src.import.Gen4Text').label(data.maps.D01R0102.messages,id)
 assert(type(text[key])=='string' and #text[key]>0,'Roark dialogue cannot resolve')
end
print('Native camera dolly and constant lens checks; Roark missing-registration recovery, both ROM messages and departure flags passed')

local notches
package.loaded['src.core.Game']={zoomView=function() return {zoomBy=function(_,n) notches=n end} end}
local dependencies={VoxelState={active=function() return true end},Voxel3D={available=function() return true end},FirstPerson={onTop=function() return true end},ThirdPerson={},BattleCam={},NativeGen4={battleLive=function() return false end},OverworldBattle={shot=function() return nil end}}
local control=assert(loadfile('mods/DRAMATIC_SHAPE/lib/CamControl.lua'))({require=function(name) return assert(dependencies[name],name) end})
assert(control.zoomTarget()=='native')
control.zoomBy(-1);assert(notches==-1,'mod did not dolly native Platinum camera')
assert(loadfile('src/core/Game.lua'));assert(loadfile('src/world/OverworldController.lua'))
print('Dramatic Shapes native zoom routing passed')
