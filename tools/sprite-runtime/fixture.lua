local F={}
function F.new(edition)
  local V=require('src.core.GameVersion');V.set(edition)
  local Sheets=require('src.import.Gen3ObjectSheets')
  local records={}
  local function record(id,n)
    local parts={}
    for frame=0,n-1 do for y=0,15 do
      local row={};for x=0,15 do row[x+1]=string.char((frame*3+x+y*5+id)%16)end;parts[#parts+1]=table.concat(row)
    end end
    local palette,mapped={},{}
    for i=0,15 do palette[i]=i+i*32+i*1024;mapped[i]=i*1024 end
    return {graphicsId=id,width=16,height=16,frameCount=n,indexed=table.concat(parts),inanimate=false,
      drawOffX=-2,drawOffY=3,palette=palette,paletteTag=4,paletteSlot=2,
      reflectionPaletteTag=5,reflectionPaletteMappedTag=5,mappedReflectionPalette=mapped}
  end
  records[0]=record(0,18);records[1]=record(1,9);records[2]=record(2,3);records[3]=record(3,12)
  local native={}
  local r=records[0]
  r.native={key='SPRITE_G3_000',width=16,height=16,defaultWidth=16,defaultHeight=16,
    image='assets/generated/overworld/g3_000.png',frames=9,walker=true,
    order={0,1,2,3,5,7,4,6,8},runKey='SPRITE_G3_000_RUN',runImage='assets/generated/overworld/g3_000_run.png',
    runWidth=16,runHeight=16,runFrames=9,runOrder={9,12,15,10,13,16,11,14,17}}
  for _,suffix in ipairs({'','_RUN'})do
    local key='SPRITE_G3_000'..suffix
    native[key]={id=key,image='assets/generated/overworld/g3_000'..(suffix==''and''or'_run')..'.png',frames=9,frameWidth=16,frameHeight=16,walker=true}
  end
  local avatars
  if edition~='firered'and edition~='leafgreen'then avatars={player={
    {state='NORMAL',male=0,female=89},{state='MACH_BIKE',male=1,female=90},
    {state='ACRO_BIKE',male=63,female=91},{state='SURFING',male=2,female=92},
    {state='UNDERWATER',male=111,female=112},{state='FIELD_MOVE',male=3,female=93},
    {state='FISHING',male=137,female=138},{state='WATERING',male=191,female=192}}}end
  local meta={schema=Sheets.SCHEMA,edition=edition,romSha1=V.info(edition).sha1,objects=records,avatars=avatars,count=4}
  local map={id='SPRITE_TEST',def={mapType='ROUTE'}}
  local player={cellX=4,cellY=4,px=64,py=64,elevation=3,facing='down'}
  local world={isOverworld=true,map=map,player=player,entities={player}}
  local game={data={gen3_object_sheets=meta,sprites=native,maps={SPRITE_TEST=map.def}},save={player={gender=0},onBike=false},stack={states={world}}}
  package.loaded['src.core.Game']=game
  return {game=game,world=world,player=player,meta=meta,records=records}
end
return F
