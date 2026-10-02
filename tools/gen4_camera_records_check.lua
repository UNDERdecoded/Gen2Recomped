package.path='./?.lua;'..package.path
local Camera=require('src.render.Camera')
local camera=Camera.new()
for _, size in ipairs({{128,84},{256,192},{512,384}}) do
  for _, sin in ipairs({1,.8576,.5}) do
    for _, rise in ipairs({0,8,24}) do
      camera.groundScale=sin
      camera.spriteCenterX,camera.spriteCenterY=8,-4-rise
      camera:follow(320,640,size[1],size[2])
      assert(math.abs(320-camera.x+8-size[1]/2)<1e-8)
      assert(math.abs((640-camera.y)*sin-4-rise-size[2]/2)<1e-8)
    end
  end
end
camera.spriteCenterX,camera.spriteCenterY,camera.groundScale=nil,nil,nil
camera:follow(320,640,160,144)
assert(camera.x==256 and camera.y==576,'older generation framing changed')
require('src.script.Gen4Commands')
local C=require('src.script.Commands')
local VM=require('src.script.Gen4ScriptVM')
local ctx={save={gen4Vars={[0x4001]=12}},g4Compare=2,lastCheck=false}
C.g4_add_game_record(ctx,4,0x4001,false)
assert(ctx.save.gen4GameRecords[4]==12)
C.g4_add_game_record(ctx,4,0x4001,true)
assert(ctx.save.gen4GameRecords[4]==12+16385,'big amounts must remain literals')
for _, row in ipairs({{0,999999999},{9,999999},{71,65535},{73,9999}}) do
  C.g4_add_game_record(ctx,row[1],1000000000,true)
  assert(ctx.save.gen4GameRecords[row[1]]==row[2])
end
assert(ctx.g4Compare==2 and ctx.lastCheck==false)
local rows=VM.lower({{name='incrementgamerecord',args={4}},{name='addtogamerecord',args={4,0x4001}},{name='addtogamerecordbigvalue',args={4,16385}}})
assert(rows[1][1]=='g4_add_game_record' and rows[1][3]==1 and rows[1][4]==true)
assert(rows[2][4]==false and rows[3][4]==true)
assert(loadfile('src/world/OverworldController.lua'))
print('Native field centering at three view sizes, three pitches and three terrain heights; legacy framing; game-record variables, literals, limits and lowering passed')
