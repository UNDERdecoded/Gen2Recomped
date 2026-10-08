package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Polished Unown wall glyphs')
local Version=require('src.core.GameVersion')
local chosen
package.loaded['src.render.Assets']={register=function()end,image=function(path)
  chosen=path
  return {getWidth=function()return 128 end,getHeight=function()return 128 end,
          getDimensions=function()return 128,128 end}
end}
local Wall=require('src.ui.UnownWall')
local game={data={field={gen2UnownWalls={words={{8,68,4,0,46,8},{96}}}},
  tilesets={TilesetRuins={image='ruins'},TilesetAlph={image='alph'}}},
  overworld={map={def={tileset='TilesetRuins'}}}}
Version.set('polishedcrystal')
local wall=Wall.new(game,{word=0})
T.eq(chosen,'alph','word screen loads the Polished alphabet atlas')
local tiles={}
wall.drawTile=function(_,id)tiles[#tiles+1]=id end
wall:draw()
T.eq(tiles[1],136,'E starts at bank-one tile eight plus 128')
T.eq(tiles[5],196,'S uses the lower alphabet band')
T.eq(tiles[13],128,'A renders from first alphabet tile')
wall=Wall.new(game,{word=1});tiles={}
wall.drawTile=function(_,id)tiles[#tiles+1]=id end
wall:draw()
T.eq(tiles[1],224,'Polished Y uses ordinary conversion')
Version.set('crystal')
wall=Wall.new(game,{word=1});tiles={}
wall.drawTile=function(_,id)tiles[#tiles+1]=id end
wall:draw()
T.eq(chosen,'ruins','Crystal still loads its chamber atlas')
T.eq(tiles[1],91,'Crystal keeps its literal Y conversion')
T.finish()
