local maps=dofile("G:/Gen2Recomped/polishedcrystal/data/generated/maps.lua")
local O=require("src.world.OverworldController")
local Graph=dofile("mods/DRAMATIC_SHAPE/lib/BorderMaskGraph.lua")
local drawing=Graph.build(maps,O.computeNeighbors)
local root="RUINS_OF_ALPH_OUTSIDE"
local checked=0
for _,n in ipairs(O.computeNeighbors(maps,root,2,96,96))do
 local found=false
 for _,r in ipairs(drawing[n.id])do
  if r[1]==-n.ox and r[2]==-n.oy and r[3]==-n.ox+maps[root].width*32
    and r[4]==-n.oy+maps[root].height*32 then found=true end
 end
 assert(found,"neighbour ring can cover Alph: "..n.id)
 checked=checked+1
end
assert(checked==4)
local original=false
for _,r in ipairs(O.computeNeighbors(maps,"VIOLET_CITY",2,96,96))do
 if r.id==root then original=true end
end
assert(not original,"test no longer reproduces missing reverse mask")
local fixture={a={width=2,height=3,blockPx=32,connections={east={map="b",offset=1}}},
 b={width=4,height=6,blockPx=16,connections={}}}
local f=Graph.build(fixture,O.computeNeighbors)
assert(f.b[1][1]==-64 and f.b[1][2]==-32)
assert(next(fixture.b.connections)==nil,"gameplay connection mutated")
print("PASS all four neighbouring border rings mask Alph at its actual position")
print("PASS one-way connection regression, mixed block sizes and original map nonmutation")
