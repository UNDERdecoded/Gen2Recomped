local base=dofile('mods/DRAMATIC_SHAPE/data/voxel_heights.lua')
local P=dofile('mods/DRAMATIC_SHAPE/lib/PolishedProfile.lua')
local indices=dofile('mods/DRAMATIC_SHAPE/data/polishedcrystal/voxel_indices.lua')
local result=P.apply(base,indices)
assert(result.tilesets.TilesetJohto1 and not result.tilesets.TilesetJohto)
assert(base.tilesets.TilesetJohto and not base.tilesets.TilesetJohto1)
assert(result.collision==base.collision and result.heights==base.heights)
local n=0
for id,e in pairs(result.tilesets)do n=n+1 end
assert(n>=45)
print('PASS isolated Polished roster and unchanged GSC profiles')
local furniture=dofile('mods/DRAMATIC_SHAPE/data/polishedcrystal/furniture.lua')
local complete=P.apply(base,indices,furniture)
for id,expected in pairs(furniture)do
  local seen={}
  for class,tiles in pairs(complete.tilesets[id])do
    if type(tiles)=='table' and #tiles>0 and type(tiles[1])=='number'then
      for _,tile in ipairs(tiles)do assert(not seen[tile],id..' conflicting class for '..tile);seen[tile]=class end
    end
  end
  for class,tiles in pairs(expected)do
    if type(tiles)=='table' and #tiles>0 and type(tiles[1])=='number'then
      for _,tile in ipairs(tiles)do assert(seen[tile]==class,id..' incomplete '..class)end
    end
  end
end
assert(#complete.tilesets.TilesetHouse1.console==6)
assert(#complete.tilesets.TilesetHouse1.billboard==6)
assert(complete.tilesets.TilesetHouse1.heights.table==6)
assert(indices.tilesets.TilesetHouse1~=complete.tilesets.TilesetHouse1)
print('PASS complete furniture groups, low tables, floor pins and nonmutation')
local landmarks={}
for id,templates in pairs(indices.buildings)do
  for _,t in ipairs(templates)do
    landmarks[t.id]=true
    for _,role in ipairs(t.roles or {})do landmarks[role]=true end
    if t.id:find('ecruteak_pagoda')then
      for r=1,t.roofRows/8 do for _,tile in ipairs(t.tiles[r])do
        assert(tile~=30 and tile~=31 and tile~=62 and tile~=63,'forest row included in pagoda roof')
      end end
    end
  end
end
for _,id in ipairs({'polished_sprout_tower','polished_radio_west','polished_lighthouse',
                   'polished_goldenrod_dept_store','polished_goldenrod_game_corner',
                   'polished_celadon_dept_store','polished_harbor_tent_0'})do
  assert(landmarks[id],'missing complete landmark '..id)
end
print('PASS landmark models and pagoda roof boundaries')
local function classFor(entry,tile)
  for class,tiles in pairs(entry)do
    if type(tiles)=='table' and type(tiles[1])=='number'then
      for _,id in ipairs(tiles)do if id==tile then return class end end
    end
  end
end
for _,id in ipairs({'TilesetJohto1','TilesetJohto2','TilesetJohto3','TilesetJohto4','TilesetJohto5'})do
  for _,tile in ipairs({70,71,86,87})do
    assert(classFor(complete.tilesets[id],tile)=='signpost',id..' sign must use thin billboard art')
  end
end
for _,tile in ipairs({8,24})do
  assert(classFor(complete.tilesets.TilesetJohto2,tile)=='fence','trackside fence row misclassified')
end
assert(complete.tilesets.TilesetJohto2.heights.fence==8,'rail fence must stay low')
for _,tile in ipairs({198,199,200,201,214,215,216,217,202,203,204,205,218,219,220,221})do
  assert(classFor(complete.tilesets.TilesetJohto1,tile)==(tile==198 and 'canopy' or 'cylinder'),'pink tree canopy group split')
end
for _,tile in ipairs({73,74,75,78,79,94,95})do
  assert(classFor(complete.tilesets.TilesetJohto3,tile)=='wall','Alph masonry becomes a tree')
end
for _,tile in ipairs({128,129,144,145,224,225,240,241})do
  assert(classFor(complete.tilesets.TilesetAlph,tile)=='wall','Unown glyph must stay upright')
end
print('PASS signs, trackside fences, pink crowns and Alph masonry/glyphs')
