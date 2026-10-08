local root=love.filesystem.getWorkingDirectory():gsub('\\','/')..'/'
package.path=root..'?.lua;'..root..'?/init.lua;'..package.path
function love.load()
 local ok,why=xpcall(function()
  local function read(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
  local C=require('src.import.CacheFs');C.mkdirReal(root..'tmp');C.mkdirReal(root..'tmp/polished-voxel-probe')
  C.root=function()return root..'tmp/polished-voxel-probe/output' end
  local E=require('src.import.RomExtractorGen2')
  local e=E.new(read(root..'polishedcrystal-3.2.3 (1).gbc'),'polishedcrystal',require('src.link.Json').decode(read(root..'tools/rom_manifest_polishedcrystal.json')))
  e.readSourceTable=function(self,n)
    local f=loadfile(C.root()..'/data/generated/'..n..'.lua')
      or loadfile('G:/Gen2Recomped/polishedcrystal/data/generated/'..n..'.lua')
      or assert(loadfile(root..self.sourceDir..'/'..n..'.lua'))
    return f()
  end
  if os.getenv('POLISHED_FRESH')=='1' then e:extractMapsFromRom() end
  if os.getenv('POLISHED_EVENTS')=='1' then
    e:extractScaffoldCore();e:extractMapsFromRom();e:extractMapScripts()
    local items=dofile(C.root()..'/data/generated/items.lua')
    local found=false
    for _,item in pairs(items)do if item.key=='COIN_CASE' and item.keyItem then found=true end end
    assert(found,'Polished key-item space must include Coin Case')
    local scripts=dofile(C.root()..'/data/generated/map_scripts.lua')
    assert(scripts.maps.GOLDENROD_GAME_CORNER.objects[1],'inline coin-vendor standard script linked')
    for _,contact in pairs(scripts.phone or {})do
      if contact.name then assert(not contact.name:find('{',1,true),'phone name decoded as raw ngrams')end
    end
    print('PASS Coin Case registry, coin vendor linkage and phone names')
  end
  e:extractIcons()
  e:extractRuntimeScaffolds()
  assert(e:gen2TownMapImage('JohtoMap','ui/town_map_johto.png'))
  assert(e:gen2TownMapImage('KantoMap','ui/town_map_kanto.png'))
  local townMap=assert(e:gen2TownMap())
  assert(townMap.playerIcon,'compressed player icon extracted for town map')
  local gear=assert(e:gen2Pokegear())
  assert(gear.playerIcon,'compressed player icon extracted for Pokegear')
  assert(gear.cardIconOffset==16 and gear.blankTile==247,'Polished Pokegear VRAM layout')
  local gearSheet=love.image.newImageData(love.filesystem.newFileData(read(C.root()..'/'..gear.tiles),gear.tiles))
  assert(gearSheet:getWidth()==128 and gearSheet:getHeight()==64,'full Polished Pokegear sheet')
  local gearImage=love.graphics.newImage(gearSheet);gearImage:setFilter('nearest','nearest')
  for _,page in ipairs({'clock','phone','radio'})do
    assert(#gear.cards[page]==360 and gear.cards[page][360]==247,'ROM page clear/padding '..page)
    local canvas=love.graphics.newCanvas(160,144,{dpiscale=1})
    love.graphics.push('all');love.graphics.origin();love.graphics.setShader();love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,1)
    for i,tile in ipairs(gear.cards[page])do
      local x,y=(i-1)%20*8,math.floor((i-1)/20)*8
      if tile==127 then
        love.graphics.setColor(230/255,1,164/255,1);love.graphics.rectangle('fill',x,y,8,8)
      elseif tile<128 and tile~=247 then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(gearImage,love.graphics.newQuad(tile%16*8,math.floor(tile/16)*8,8,8,128,64),x,y)
      end
    end
    love.graphics.setCanvas();love.graphics.pop()
    local f=assert(io.open(root..'tmp/polished-voxel-probe/pokegear-'..page..'-shell.png','wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
  end
  local marker=love.image.newImageData(love.filesystem.newFileData(read(C.root()..'/'..townMap.playerIcon),townMap.playerIcon))
  local gearMarker=love.image.newImageData(love.filesystem.newFileData(read(C.root()..'/'..gear.playerIcon),gear.playerIcon))
  assert(marker:getString()==gearMarker:getString(),'Pokegear must not overwrite the valid TownMap icon with compressed bytes')
  print('PASS Pokegear and TownMap player markers match pixel for pixel')
  print('PASS extracted Polished Crystal tilesets')
  if os.getenv("POLISHED_UNOWN")=="1" then
    e:extractPokemon()
    local pokemon=dofile(C.root().."/data/generated/pokemon.lua")
    local u=pokemon.SPECIES_201
    assert(u and #u.forms==28,"Polished must extract 28 Unown forms")
    local paths={}
    for i,f in ipairs(u.forms)do assert(f.spriteFront and not paths[f.spriteFront],"duplicate Unown front "..i); paths[f.spriteFront]=true end
    print("PASS 28 distinct ROM-extracted Unown front sprites")
  end
  require('src.core.GameVersion').set('polishedcrystal')
  local ts=assert(loadfile(C.root()..'/data/generated/tilesets.lua'))()
  local cache=os.getenv('POLISHED_CACHE') or 'G:/Gen2Recomped/polishedcrystal/data/generated'
  local maps=assert(loadfile((os.getenv('POLISHED_FRESH')=='1' and C.root()..'/data/generated' or cache)..'/maps.lua'))()
  require('src.core.Game').data={maps=maps,tilesets=ts,field={gen2Roofs=e:gen2Roofs()}}
  local A=require('src.render.Assets')
  A.imageData=function(path)return love.image.newImageData(love.filesystem.newFileData(read(C.root()..'/'..path),path))end
  A.image=function(path)return love.graphics.newImage(A.imageData(path))end
  local sprites=dofile(C.root()..'/data/generated/sprites.lua')
  local bird=assert(sprites.SPRITE_MON_016)
  assert(bird.monIcon and bird.image~=sprites.SPRITE_RED.image,'overworld Pidgey must not use player art')
  local chart=love.graphics.newCanvas(160,48,{dpiscale=1});love.graphics.setCanvas(chart);love.graphics.clear(.25,.25,.25,1)
  love.graphics.draw(A.image(bird.image),0,0)
  local objects=A.image(sprites.SPRITE_BALL_CUT_FRUIT.image)
  for frame=0,2 do love.graphics.draw(objects,love.graphics.newQuad(0,frame*16,16,16,objects:getDimensions()),40+frame*32,0)end
  love.graphics.setCanvas();local f=assert(io.open(root..'tmp/polished-voxel-probe/objects.png','wb'));f:write(chart:newImageData():encode('png'):getString());f:close()
  local V,mods={},{}
  V.require=function(n)if not mods[n]then mods[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V)end;return mods[n]end
  V.data=function(n)
    local base=assert(loadfile(root..'mods/DRAMATIC_SHAPE/data/'..n..'.lua'))()
    if n=='voxel_heights'then return V.require('PolishedProfile').apply(base,dofile(root..'mods/DRAMATIC_SHAPE/data/polishedcrystal/voxel_indices.lua'),dofile(root..'mods/DRAMATIC_SHAPE/data/polishedcrystal/furniture.lua'))end
    return base
  end
  local Shapes=V.require('TileShape');local Map=require('src.world.Map')
  local Scene=V.require('VoxelScene')
  local alph=maps.RUINS_OF_ALPH_OUTSIDE
  local masks=Scene.masksFor({id="VIOLET_CITY"})
  local clipped=false
  for _,r in ipairs(masks or {})do
    if r[1]==-256 and r[2]==192 and r[3]==-256+alph.width*32 and r[4]==192+alph.height*32 then clipped=true end
  end
  assert(clipped,"live Violet border mask must include Alph body")
  print("PASS live voxel mask resolver clips incoming border trees over Alph")
  local sceneMap=Map.new(maps.ROUTE30,ts[maps.ROUTE30.tileset])
  assert(Scene.statedFrame(sceneMap,{fixedFrame=2})==2,'Gen2 fruit row reaches the voxel cast')
  assert(Scene.statedFrame(sceneMap,{fixedFrame=0})==0,'Gen2 ball row reaches the voxel cast')
  V.require('ChunkMesher').setCacheRulesTag('polished-incoming-border-masks-v14')
  if os.getenv('POLISHED_RENDER_ONLY') then
    local B=V.require('Buildings');local build=B.build
    B.build=function(S,map,pixels,perRow)
      if map.id==os.getenv('POLISHED_RENDER_ONLY') then
        print('MODEL ATLAS '..map.id..' perRow='..perRow..' width='..pixels:getWidth()..' height='..pixels:getHeight())
        local f=assert(io.open(root..'tmp/polished-voxel-probe/model-atlas.png','wb'));f:write(pixels:encode('png'):getString());f:close()
      end
      return build(S,map,pixels,perRow)
    end
  end
  local checked=0
  local atlases={}
  for id,def in pairs(maps)do if ts[def.tileset]then
    local tileset=ts[def.tileset]
    if not atlases[def.tileset] then
      local p=A.imageData(tileset.image);local w,h=p:getDimensions()
      assert(w==tileset.imageWidth and h==tileset.imageHeight,'atlas geometry mismatch '..def.tileset)
      for _,block in ipairs(tileset.blocks)do for _,tile in ipairs(block)do
        assert(tile>=0 and tile<w*h/64,'tile outside atlas '..def.tileset)
      end end
      atlases[def.tileset]=true
    end
    for _,block in ipairs(def.blocks)do assert(block<#tileset.blocks,'invalid map block '..id)end
    local map=Map.new(def,tileset);local shapes=Shapes.forMap(map)
    for y=0,def.height*4-1 do for x=0,def.width*4-1 do
      local s=Shapes.at(map,shapes,map:tileAt(x,y),x,y);assert(s and s.h>=-32 and s.h<=128)
    end end
    checked=checked+1
  end end
  print('PASS shape resolution for '..checked..' Polished maps')
  if os.getenv('POLISHED_AUDIT')=='1' then
    local Game=require('src.core.Game');Game.save=require('src.core.SaveData').newGame()
    local suffix=os.getenv('POLISHED_AUDIT_TILESETS') and '-subset' or ''
    local report=assert(io.open(root..'tmp/polished-voxel-probe/audit'..suffix..'.csv','w'))
    report:write('map,tileset,vertices,object_quads\n')
    local filter=os.getenv('POLISHED_AUDIT_TILESETS')
    local ids={};for id,def in pairs(maps)do if ts[def.tileset] and (not filter or filter:find('|'..def.tileset..'|',1,true)) then ids[#ids+1]=id end end;table.sort(ids)
    local shown={};local failures={}
    for i,id in ipairs(ids)do
      local ok,why=xpcall(function()
        local map=Map.new(maps[id],ts[maps[id].tileset])
        local S=V.require('Structures').forMap(map)
        local mesh=V.require('ChunkMesher').build(map,true)
        local count=mesh and mesh:getVertexCount() or 0
        if map.def.width>1 and map.def.height>1 then assert(count>0,'missing complete terrain mesh')end
        report:write(id..','..map.tileset.id..','..count..','..#S.objectQuads..'\n');report:flush()
        if mesh and not shown[map.tileset.id]then
          local p=V.require('PolishedAtlas').forMap(map) or A.imageData(map.tileset.image)
          local texture=love.graphics.newImage(p);texture:setFilter('nearest','nearest')
          V.require('VoxelState').angle=math.rad(35)
          local g=V.require('Voxel3D');local vw=math.max(map.def.width*32,map.def.height*32*800/650)*1.2
          assert(g.beginScene(800,650,map.def.width*16,map.def.height*16,vw,vw*650/800))
          g.draw(mesh,texture);g.endScene()
          local f=assert(io.open(root..'tmp/polished-voxel-probe/audit-'..map.tileset.id..'.png','wb'));f:write(g.canvas():newImageData():encode('png'):getString());f:close()
          texture:release();shown[map.tileset.id]=id
        end
        if mesh then mesh:release()end
      end,debug.traceback)
      if not ok then failures[#failures+1]=id..': '..why;print('FAIL '..failures[#failures])end
      V.require('Structures').invalidate(id);collectgarbage('collect')
      if i%10==0 then print('AUDIT '..i..'/'..#ids);io.stdout:flush()end
    end
    report:close();assert(#failures==0,table.concat(failures,'\n'))
    print('PASS complete mesh audit '..#ids..' maps')
  end
  for _,id in ipairs({'RADIO_TOWER1_F','CHERRYGROVE_POKE_CENTER1_F','RUINS_OF_ALPH_AERODACTYL_CHAMBER','CHERRYGROVE_CITY','RUINS_OF_ALPH_HO_OH_WORD_ROOM','ROUTE30','NEW_BARK_TOWN','GOLDENROD_CITY','CELADON_CITY','VIOLET_CITY','OLIVINE_CITY','ECRUTEAK_CITY','AZALEA_TOWN','RUINS_OF_ALPH_OUTSIDE','GOLDENROD_HARBOR','ROUTE34_COAST','PALLET_TOWN','ELMS_LAB','ILEX_FOREST','DARK_CAVE_VIOLET_ENTRANCE','PLAYERS_HOUSE1_F','PLAYERS_HOUSE2_F'})do
    if maps[id] and (not os.getenv('POLISHED_RENDER_ONLY') or os.getenv('POLISHED_RENDER_ONLY')==id) then
      local map=Map.new(maps[id],ts[maps[id].tileset]);local S=V.require('Structures').forMap(map)
      print('MESH '..id..' quads='..#S.objectQuads)
      if id=='CHERRYGROVE_CITY' then
        local count=0
        for y=0,map.def.height*4-4 do for x=0,map.def.width*4-4 do
          local tile=map:tileAt(x,y)
          local variant=map.tileset.tileVariants and map.tileset.tileVariants[tile]
          if (variant and variant.base or tile)==198 then
            local found=false
            for _,stamp in ipairs(S.roundStamps)do
              if stamp.mx==x*8+16 and stamp.mz==y*8+16 and stamp.r==16
                 and #stamp.quads>0 then found=true break end
            end
            assert(found,'pink tree lacks full round canopy at '..x..','..y)
            count=count+1
          end
        end end
        assert(count>10,'southern pink grove must be included')
        print('PASS '..count..' complete Cherrygrove pink canopies')
      end
      if id=='ECRUTEAK_CITY' and os.getenv('POLISHED_RENDER_ONLY') then
        local hist={}
        for _,q in ipairs(S.objectQuads)do
          if q.own and q.uv and q[1][1]>=64 and q[1][1]<128 and q[1][3]>=240 and q[1][3]<288 then
            local uv=q.uv[1];local tile=math.floor(uv[2]*map.tileset.imageHeight/8)*map.tileset.tilesPerRow+math.floor(uv[1]*map.tileset.imageWidth/8)
            hist[tile]=(hist[tile]or 0)+1
          end
        end
        print('HOUSE UV '..require('src.link.Json').encode(hist))
        for _,st in ipairs(S.roundStamps)do
          if st.mx>=56 and st.mx<=136 and st.mz>=224 and st.mz<=296 then
            print('NEAR HOUSE STAMP '..st.mx..','..st.mz..' r='..tostring(st.r)..' y='..tostring(st.my))
          end
        end
      end
      local mesh,waterMesh=V.require('ChunkMesher').build(map,true,nil,true)
      assert(mesh,'complete terrain mesh must build')
      print('FULL '..id..' vertices='..mesh:getVertexCount())
      do
        local raw=V.require('PolishedAtlas').forMap(map) or A.imageData(map.tileset.image)
        local texture=(os.getenv('POLISHED_COLOR')=='1' and require('src.render.TileRenderer').gen2AtlasFor(map.tileset))
          or love.graphics.newImage(raw);texture:setFilter('nearest','nearest')
        V.require('VoxelState').angle=math.rad(35)
        local g=V.require('Voxel3D');local vw=math.max(map.def.width*32,map.def.height*32*800/650)*1.25
        assert(g.beginScene(800,650,map.def.width*16,map.def.height*16,vw,vw*650/800))
        g.draw(mesh,texture);if waterMesh then g.draw(waterMesh,texture)end;g.endScene()
        local f=assert(io.open(root..'tmp/polished-voxel-probe/revised-'..id..'.png','wb'))
        f:write(g.canvas():newImageData():encode('png'):getString());f:close()
      end
      if id=='ROUTE30' then
        local def=map.def.objects[10]
        local npc=require('src.world.NPC').new({sprites=sprites},id,def)
        local proxy=V.require('PolishedFruitSprite').sprite(map,npc,npc.sprite)
        assert(proxy~=npc.sprite and proxy.def.billboardTexture,'berry terrain and fruit form one billboard')
        for dy=0,1 do for dx=0,1 do
          local key=(def.y*2+dy+64)*4096+def.x*2+dx+64
          assert(S.skip[key] and S.shapeAt[key].class=='ground','berry base must not remain a prism')
        end end
        local img=proxy:resolveImage();local c=love.graphics.newCanvas(16,16,{dpiscale=1})
        love.graphics.push('all');love.graphics.setCanvas(c);love.graphics.origin();love.graphics.setShader();love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1);love.graphics.draw(img);love.graphics.setCanvas();love.graphics.pop()
        local f=assert(io.open(root..'tmp/polished-voxel-probe/berry-billboard.png','wb'));f:write(c:newImageData():encode('png'):getString());f:close()
        print('PASS combined berry billboard and flat soil footprint')
        local baked,why=V.require('ChunkMesher').bake(map,'body');assert(baked or why=='cached',why)
        local hit,cached=V.require('VoxelDiskCache').load(map,'body')
        assert(hit and cached)
        for _,i in ipairs({1,100,65536,65537,math.floor(mesh:getVertexCount()/2),mesh:getVertexCount()})do
          local expected={mesh:getVertex(i)};local actual={cached:getVertex(i)}
          for n=1,6 do assert(math.abs(expected[n]-actual[n])<.001,'cached vertex mismatch '..i..' component '..n..' '..expected[n]..'/'..actual[n])end
        end
        print('PASS full Route30 cache roundtrip')
        local Game=require('src.core.Game');Game.save=require('src.core.SaveData').newGame()
        local raw=V.require('PolishedAtlas').forMap(map) or A.imageData(map.tileset.image)
        local texture=love.graphics.newImage(raw)
        map.renderer={image=texture,trueColor=true}
        map.tileset.animatedTiles={{tile=20,kind='hshift',offsets={1,0},period=20}}
        V.require('TerrainAtlas').invalidate()
        V.require('VoxelState').angle=math.rad(35)
        local g=V.require('Voxel3D');assert(g.beginScene(800,650,8*16,34*16,240,195))
        local shader=love.graphics.getShader();local depth,write=love.graphics.getDepthMode()
        local atlas=V.require('TerrainAtlas').forMap(map,nil)
        assert(atlas~=texture,'test exercises animated readback')
        assert(love.graphics.getShader()==shader,'readback restores scene shader')
        local afterDepth,afterWrite=love.graphics.getDepthMode();assert(afterDepth==depth and afterWrite==write)
        g.draw(cached,atlas);g.endScene()
        local f=assert(io.open(root..'tmp/polished-voxel-probe/live-route30.png','wb'));f:write(g.canvas():newImageData():encode('png'):getString());f:close()
        love.graphics.push('all');love.graphics.setShader();love.graphics.origin();love.graphics.setDepthMode()
        local w,h=atlas:getDimensions();local ac=love.graphics.newCanvas(w,h,{dpiscale=1});love.graphics.setCanvas(ac);love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1);love.graphics.draw(atlas);love.graphics.setCanvas();local ap=ac:newImageData();love.graphics.pop()
        local _,_,_,alpha=ap:getPixel(16,16);assert(alpha>.99,'live terrain atlas must remain opaque')
        print('PASS active scene animation readback and visible Route30')
      end
      if id=='GOLDENROD_CITY' or id=='PLAYERS_HOUSE2_F' or id=='PLAYERS_HOUSE1_F' then
        local Game=require('src.core.Game');Game.save=require('src.core.SaveData').newGame()
        local p=V.require('PolishedAtlas').forMap(map) or A.imageData(map.tileset.image)
        local texture=love.graphics.newImage(p)
        V.require('VoxelState').angle=math.rad(35)
        local g=V.require('Voxel3D');assert(g.beginScene(800,650,map.def.width*16,map.def.height*16,240,195))
        g.draw(mesh,texture);g.endScene()
        local f=assert(io.open(root..'tmp/polished-voxel-probe/full-'..id..'.png','wb'));f:write(g.canvas():newImageData():encode('png'):getString());f:close()
      end
      -- Alphabet chambers contain ordinary terrain walls and floor tiles,
      -- with no freestanding props. Their terrain mesh was checked above.
      if id~='DARK_CAVE_VIOLET_ENTRANCE' and id~='ROUTE34_COAST'
         and id~='RUINS_OF_ALPH_HO_OH_WORD_ROOM'then assert(#S.objectQuads>0)end
      if id=='NEW_BARK_TOWN'then
        local pixels=assert(V.require('PolishedAtlas').forMap(map));local texture=love.graphics.newImage(pixels)
        -- Animation's private atlas must preserve the map's roof artwork.
        local water=require('src.render.TileRenderer').defaultAnimatedTiles(map.tileset)
        map.renderer={image=texture,trueColor=true,animatedTiles=water}
        local animated=V.require('TerrainAtlas').forMap(map,nil)
        assert(animated,'terrain texture remains available')
        local aw,ah=animated:getDimensions();local ac=love.graphics.newCanvas(aw,ah,{dpiscale=1})
        love.graphics.setCanvas(ac);love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1);love.graphics.draw(animated);love.graphics.setCanvas()
        local ap=ac:newImageData()
        for tile=10,18 do for y=0,7 do for x=0,7 do
          local sx,sy=tile%16*8+x,math.floor(tile/16)*8+y
          local r,g,b=pixels:getPixel(sx,sy);local r2,g2,b2=ap:getPixel(sx,sy)
          assert(math.abs(r-r2)<.005 and math.abs(g-g2)<.005 and math.abs(b-b2)<.005,'animation preserves roof texels')
        end end end
        -- Other cartridges never receive the Polished-only roof replacement.
        for _,version in ipairs({'gold','silver','crystal'})do
          require('src.core.GameVersion').set(version)
          assert(V.require('PolishedAtlas').forMap(map)==nil)
        end
        require('src.core.GameVersion').set('polishedcrystal')
        texture:setFilter('nearest','nearest')
        local quads={};for _,q in ipairs(S.objectQuads)do
          if q[1][1]>=0 and q[1][3]>=0 and q[1][1]<=map.def.width*32 and q[1][3]<=map.def.height*32 then quads[#quads+1]=q end
        end
        table.sort(quads,function(a,b)
          local function depth(q)local n=0;for i=1,4 do n=n+q[i][3]+q[i][1]*0.25 end;return n end
          return depth(a)<depth(b)
        end)
        local vertices={}
        for _,q in ipairs(quads)do for _,i in ipairs({1,2,3,1,3,4})do
          local p=q[i];local uv=q.uv and q.uv[i] or {q.u or 0,q.v or 0};local shade=q.shade or 1
          vertices[#vertices+1]={80+p[1]*1.7+p[3]*0.45,120+p[3]*1.35-p[2]*1.4,uv[1],uv[2],shade,shade,shade,1}
        end end
        local mesh=love.graphics.newMesh(vertices,'triangles','static');mesh:setTexture(texture)
        local canvas=love.graphics.newCanvas(800,650,{dpiscale=1});love.graphics.setCanvas(canvas);love.graphics.clear(.12,.14,.17,1);love.graphics.draw(mesh);love.graphics.setCanvas()
        local f=assert(io.open(root..'tmp/polished-voxel-probe/preview.png','wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
        local stats=V.require('Buildings').stats();local n=0;for _ in pairs(stats)do n=n+1 end;assert(n>=3,'New Bark uses real facade models')
        print('PASS New Bark buildings='..n..', native mesh preview')
      end
    end
  end
 end,debug.traceback)
 if not ok then print(why)end;love.event.quit(ok and 0 or 1)
end
function love.errorhandler(m)print(debug.traceback(tostring(m)));return function()return 1 end end
