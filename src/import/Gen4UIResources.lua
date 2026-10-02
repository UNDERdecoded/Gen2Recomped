-- Resources whose runtime indices are shared across species or wallpapers.
local G=require('src.import.Gen4Graphics')
local N=require('src.import.NarcArchive')
local C=require('src.import.Gen4Cells')
local Anim=require('src.import.Gen4CellAnim')
local R={}
function R.images(rom)
 local out={}
 local function archive(path) local b=rom:read(path);return b and N.parse(b) end
 local function member(a,i)
  local b=a and a:get(i);if b and G.isCompressed(b) then b=G.decompress(b) end;return b
 end
 local function picture(a,tiles,map,pal)
  local sheet=G.tiles(member(a,tiles));local tilemap=G.tilemap(member(a,map));local palette=G.palette(member(a,pal))
  if not (sheet and tilemap and palette) then return nil end
  local slot=tilemap.cells[1] and tilemap.cells[1].palette or 0
  if #palette<=16 and slot>0 then palette=G.paletteAtSlot(palette,slot) end
  return G.compose(tilemap,sheet,palette)
 end
 local opening=archive('/demo/title/op_demo.narc')
 if opening then
  out['opening/first_top']=picture(opening,16,17,15)
  out['opening/first_bottom']=picture(opening,16,18,15)
  out['opening/first_overlay']=picture(opening,114,113,115)
 end
 for key,pic in pairs(require('src.import.Gen4OpeningAssets').images(rom)) do out[key]=pic end
 for key,pic in pairs(require('src.import.Gen4Dex').images(rom)) do out[key]=pic end
 local box=archive('/graphic/box.narc')
 local shop=archive('/graphic/shop_gra.narc')
 if shop then
  local palette=G.palette(member(shop,10))
  for _,resource in ipairs({{name='cursor',tiles=7,cells=8,anim=9},{name='scroll',tiles=4,cells=5,anim=6}}) do
   local sheet=G.tiles(member(shop,resource.tiles));local bank=C.parse(member(shop,resource.cells),G)
   local anim=Anim.parse(member(shop,resource.anim),G)
   if palette and sheet and bank and anim then
    for sequence=0,#anim.sequences-1 do
     local frames=Anim.frames(anim,sequence);local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
     if cell then
      local pic=C.assemble(cell,sheet,palette,bank,G)
      if pic then pic.originX,pic.originY=C.extent(cell);out[('shop/%s_%02d'):format(resource.name,sequence)]=pic end
     end
    end
   end
  end
 end
 if box then
  out['storage/main']=picture(box,1,0,5)
  -- ov19_021D8B54: cursor NCGR/NCER/NANR 12/13/14, shared OBJ palette 26.
  local sheet=G.tiles(member(box,12));local bank=C.parse(member(box,13),G)
  local palette=G.palette(member(box,26));local animation=Anim.parse(member(box,14),G)
  if sheet and bank and palette and animation then
   for sequence=0,9 do
    local frames=Anim.frames(animation,sequence)
    local cellId=frames and frames[1] and frames[1].cell
    local cell=cellId and bank.cells[cellId+1]
    if cell then
     local pic=C.assemble(cell,sheet,palette,bank,G)
     if pic then pic.originX,pic.originY=C.extent(cell);out[('storage/cursor_%02d'):format(sequence)]=pic end
    end
   end
  end
  for i=0,31 do out[('storage/wallpaper_%02d'):format(i)]=picture(box,29+i*3,30+i*3,28+i*3) end
 end
 local summaryPath='/graphic/pl_pst_gra.narc'
 local summary=archive(summaryPath)
 if summary then
  local A=require('src.import.Gen4Archives')
  local ballBank=C.parse(member(summary,A.find(summaryPath,'condition_flash_cell.NCER')),G)
  local ballAnim=Anim.parse(member(summary,A.find(summaryPath,'condition_flash_anim.NANR')),G)
  local ballNames={'master','ultra','great','poke','safari','net','dive','nest','repeat','timer','luxury','premier','dusk','heal','quick','cherish'}
  local ballPalettes={0,2,2,0,1,1,1,1,2,2,2,2,3,3,2,0}
  local ballFrames=ballAnim and Anim.frames(ballAnim,0)
  local ballCell=ballBank and ballFrames and ballFrames[1] and ballBank.cells[ballFrames[1].cell+1]
  if ballCell then
   for id,name in ipairs(ballNames) do
    local sheet=G.tiles(member(summary,A.find(summaryPath,name..'_ball.NCGR')))
    local colours=G.palette(member(summary,A.find(summaryPath,('balls_%d.NCLR'):format(ballPalettes[id]))))
    if sheet and colours then
     local pic=C.assemble(ballCell,sheet,Anim.paletteFor(colours,ballCell.oam[1].palette),ballBank,G)
     if pic then out[('summary/ball_%02d'):format(id)]=pic end
    end
   end
  end
  local statusPalette=G.palette(member(summary,A.find(summaryPath,'status_icons.NCLR')))
  local statusSheet=G.tiles(member(summary,A.find(summaryPath,'status_icons.NCGR')))
  local statusBank=C.parse(member(summary,A.find(summaryPath,'status_icons_cell.NCER')),G)
  local statusAnim=Anim.parse(member(summary,A.find(summaryPath,'status_icons_anim.NANR')),G)
  if statusPalette and statusSheet and statusBank and statusAnim then
   local padded=Anim.paletteFor(statusPalette,Anim.bankOf(statusBank) or 0)
   for sequence=0,#statusAnim.sequences-1 do
    local frames=Anim.frames(statusAnim,sequence)
    local cell=frames and frames[1] and statusBank.cells[frames[1].cell+1]
    if cell then out[('summary/status_%02d'):format(sequence)]=C.assemble(cell,statusSheet,padded,statusBank,G) end
   end
  end
  -- The sheen sprites select palette 2 in sprites.NCLR, not the BG palette.
  local sheenPalette=G.palette(member(summary,A.find(summaryPath,'sprites.NCLR')))
  local sheenSheet=G.tiles(member(summary,A.find(summaryPath,'sheen.NCGR')))
  local sheenBank=C.parse(member(summary,A.find(summaryPath,'sheen_cell.NCER')),G)
  local sheenAnim=Anim.parse(member(summary,A.find(summaryPath,'sheen_anim.NANR')),G)
  if sheenPalette and sheenSheet and sheenBank and sheenAnim then
   local colours={}
   for i=1,16 do colours[i]=sheenPalette[32+i] end
   if colours[16] then
    local padded=Anim.paletteFor(colours,Anim.bankOf(sheenBank) or 0)
    for sequence=0,#sheenAnim.sequences-1 do
     local frames=Anim.frames(sheenAnim,sequence)
     local cell=frames and frames[1] and sheenBank.cells[frames[1].cell+1]
     if cell then out[('summary/sheen_%02d'):format(sequence)]=C.assemble(cell,sheenSheet,padded,sheenBank,G) end
    end
    local sheet=G.tiles(member(summary,A.find(summaryPath,'shiny_and_pokerus_cured_icon.NCGR')))
    local bank=C.parse(member(summary,A.find(summaryPath,'markings_cell.NCER')),G)
    local animation=Anim.parse(member(summary,A.find(summaryPath,'markings_anim.NANR')),G)
    if sheet and bank and animation then
     for sequence=0,1 do
      local frames=Anim.frames(animation,sequence)
      local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
      if cell then out[('summary/special_%02d'):format(sequence)]=C.assemble(cell,sheet,Anim.paletteFor(colours,cell.oam[1].palette),bank,G) end
     end
    end
   end
  end
  if sheenPalette then
   local tabSheet=G.tiles(member(summary,A.find(summaryPath,'tabs.NCGR')))
   local tabBank=C.parse(member(summary,A.find(summaryPath,'tabs_cell.NCER')),G)
   local tabAnim=Anim.parse(member(summary,A.find(summaryPath,'tabs_anim.NANR')),G)
   if tabSheet and tabBank and tabAnim then
    for sequence=0,15 do
     local base=sequence%8
     local paletteIndex=(base==0 or base==1 or base==2 or base==4) and 1 or 2
     local colours={};for i=1,16 do colours[i]=sheenPalette[paletteIndex*16+i] end
     local frames=Anim.frames(tabAnim,sequence)
     local cell=frames and frames[1] and tabBank.cells[frames[1].cell+1]
     if cell and colours[16] then
      local pic=C.assemble(cell,tabSheet,Anim.paletteFor(colours,cell.oam[1].palette),tabBank,G)
      if pic then pic.originX,pic.originY=C.extent(cell);out[('summary/tab_%02d'):format(sequence)]=pic end
     end
    end
   end
   local sheet=G.tiles(member(summary,A.find(summaryPath,'pokerus_icon.NCGR')))
   local bank=C.parse(member(summary,A.find(summaryPath,'pokerus_icon_cell.NCER')),G)
   local animation=Anim.parse(member(summary,A.find(summaryPath,'pokerus_icon_anim.NANR')),G)
   local colours={};for i=1,16 do colours[i]=sheenPalette[16+i] end
   if sheet and bank and animation and colours[16] then
    local frames=Anim.frames(animation,0)
    local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
    if cell then out['summary/pokerus_active']=C.assemble(cell,sheet,Anim.paletteFor(colours,Anim.bankOf(bank) or 0),bank,G) end
   end
  end
  local palette=G.palette(member(summary,A.find(summaryPath,'ribbons.NCLR')))
  local bank=C.parse(member(summary,A.find(summaryPath,'ribbons_cell.NCER')),G)
  if palette and bank then
   for id,ribbon in pairs(require('src.ui.Gen4RibbonData')) do
    local name=ribbon.art:match('/([^/]+)$')
    local sheet=G.tiles(member(summary,A.find(summaryPath,name..'.NCGR')))
    local colours={}
    for i=1,16 do colours[i]=palette[ribbon.palette*16+i] end
    if sheet and colours[16] then
     local pic=C.assemble(bank.cells[1],sheet,Anim.paletteFor(colours,Anim.bankOf(bank) or 0),bank,G)
     if pic then out[('summary/ribbon_%02d'):format(id)]=pic end
    end
   end
  end
 end
 local egg=archive('/demo/egg/data/egg_data.narc')
 if egg then out['evolution/background']=picture(egg,0,1,8) end
 local dexPath=require('src.import.Gen4Dex').PATH
 local dex=archive(dexPath)
 if dex then
  local A=require('src.import.Gen4Archives')
  local function named(tiles,map,pal) return picture(dex,A.find(dexPath,tiles..'.NCGR.lz'),A.find(dexPath,map..'.NSCR.lz'),A.find(dexPath,pal..'.NCLR')) end
  out['pokedex/area_map']=named('entry_main','area_map','banner_sinnoh')
  out['pokedex/cry_button']=named('entry_main','cry_button','banner_sinnoh')
  out['pokedex/height_check_main']=named('entry_main','height_check_main','banner_sinnoh')
  out['pokedex/weight_check_main']=named('entry_main','weight_check_main','banner_sinnoh')
  out['pokedex/cry_sub']=named('entry_sub','cry_sub','cry_sub')
  out['pokedex/forms_sub']=named('entry_sub','forms_sub','background_sub_2')
 end
 local foot=archive('/poketool/pokefoot/pokefoot.narc')
 if foot then
  local palette=G.palette(member(foot,0));local bank=C.parse(member(foot,2),G)
  if palette and bank then
   palette=Anim.paletteFor(palette,Anim.bankOf(bank) or 0)
   for species=1,493 do
    local sheet=G.tiles(member(foot,3+species))
    if sheet then out[('dex/footprint_%03d'):format(species)]=C.assemble(bank.cells[1],sheet,palette,bank,G) end
   end
  end
 end
 return out
end
return R
