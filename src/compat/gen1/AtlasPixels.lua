-- A source-format pixel projection over the native bank decoder. No ROM/cache
-- conversion, simulation, graphics allocation or independent clock lives here.
local Tiles=require('src.render.Gen3Tiles')
local M={COLS=16}
local floor,concat=math.floor,table.concat
local component5={}
for n=0,31 do
  local value=floor(n*255/31)
  component5[value]=n
end
local function integer(v,hi)return type(v)=='number'and v>=0 and v<=hi and v%1==0 end
local function bytes(values)
  local out={};for i=1,#values do out[i]=string.char(values[i])end;return concat(out)
end
local function le16(n)return string.char(n%256,floor(n/256)%256)end
local function word(data,index)
  if type(data)~='string'then return nil end
  local lo,hi=data:byte(index*2+1,index*2+2)
  if hi then return lo+hi*256 end
end
local function matches(value,rgb)
  return value~=nil and rgb and floor((value%32)*255/31)==rgb[1]
    and floor((floor(value/32)%32)*255/31)==rgb[2]
    and floor((floor(value/1024)%32)*255/31)==rgb[3]
end
function M.colors(words)
  local out={}
  for i=1,16 do
    local word=words[i]or 0;assert(integer(word,65535),'invalid palette word')
    out[i]={floor((word%32)*255/31+.5),floor((floor(word/32)%32)*255/31+.5),floor((floor(word/1024)%32)*255/31+.5)}
  end
  return out
end
function M.new(pair,layout,checkpoint)
  for _,bank in ipairs({pair.primary,pair.secondary})do
    assert(type(bank)=='table'and integer(bank.metatileCount,1024)
      and type(bank.metatiles)=='string'and#bank.metatiles>=bank.metatileCount*16
      and type(bank.attributes)=='string'and#bank.attributes>=bank.metatileCount*2
      and type(bank.tiles)=='string','native atlas bank data unavailable')
    for slot=1,16 do
      local palette=bank.palettes and bank.palettes[slot]
      assert(type(palette)=='table','native atlas palette data unavailable')
      for color=1,16 do
        local rgb=palette[color];assert(type(rgb)=='table','native atlas palette data unavailable')
        for channel=1,3 do assert(integer(rgb[channel],255),'invalid native atlas colour')end
      end
    end
  end
  local decoder=Tiles.new(pair,layout)
  local self={decoder=decoder,mids={},midToSlot={},indexed={},under={},over={},paletteOverrides={},revision=0,checkpoint=checkpoint,
    background='\0\0\0\255',paletteUsers={},slotPalettes={},indexRevision=0}
  local usedTiles={}
  local function add(mid)
    local slot=#self.mids;self.mids[slot+1]=mid;self.midToSlot[mid]=slot
    for _,entry in ipairs(decoder:entries(mid))do
      local set=usedTiles[entry.tile]or{};usedTiles[entry.tile]=set;set[slot]=true
    end
    if checkpoint and slot%16==15 then checkpoint('index')end
  end
  local primaryCount=math.min(pair.primary.metatileCount or 0,decoder.metatilesInPrimary)
  for mid=0,primaryCount-1 do add(mid)end
  for mid=0,(pair.secondary and pair.secondary.metatileCount or 0)-1 do add(decoder.metatilesInPrimary+mid)end
  assert(#self.mids>0 and #self.mids<=1024,'invalid atlas metatile count')
  self.cols,self.rows=M.COLS,math.max(1,math.ceil(#self.mids/M.COLS))
  self.width,self.height=self.cols*16,self.rows*16
  local function activeCycle(slot,color)
    local bank=decoder:paletteBank(slot)
    local selected=decoder.paletteState and decoder.paletteState[slot<decoder.palettesInPrimary and'primaryFrames'or'secondaryFrames']
    local found,frame
    for i,cycle in ipairs(bank and bank.paletteCycles or{})do
      local at=slot*16+color
      if selected and at>=cycle.first and at<cycle.first+cycle.count then found,frame=cycle,selected[i]end
    end
    return found,frame,bank
  end
  local function sourceColor(slot,color)
    local cycle,frame,record=activeCycle(slot,color)
    local reservedBase=false
    if slot>=(layout.palettesTotal or 13)and not cycle then
      slot=0;record=decoder:paletteBank(0);cycle,frame=nil,nil;reservedBase=true
    end
    local palette=reservedBase and record.palettes[1]or decoder:palette(slot)or{}
    local rgb=palette[color+1]or{0,0,0}
    local original=record and word(record.sourcePaletteBytes,slot*16+color)
    if cycle then
      local at=slot*16+color
      if cycle.kind=='frames'then original=cycle.sourceFrames and word(cycle.sourceFrames[frame+1],at-cycle.first)
      else
        local from=cycle.first+(at-cycle.first-cycle.direction*frame)%cycle.count
        rgb=record.palettes[floor(from/16)+1][from%16+1]
        original=word(record.sourcePaletteBytes,from)
        if from%16==0 and floor(from/16)<decoder.palettesInPrimary then rgb={0,0,0};original=0 end
      end
    elseif slot<decoder.palettesInPrimary and color==0 then
      -- LoadTilesetPalette clears primary colour zero; reserved BG banks
      -- inherit palette zero until an explicit palette operation owns them.
      rgb={0,0,0};original=0
    end
    if not matches(original,rgb)then original=nil end
    return rgb,original
  end
  local function paletteLut()
    local lut,bgr,stamp,rows,changed={},{},{},{},{}
    for slot=0,15 do
      local colors=self.paletteOverrides[slot]
      bgr[slot]={};local row={}
      for color=0,15 do
        local rgb,original=sourceColor(slot,color)
        local r,g,b=rgb[1]or 0,rgb[2]or 0,rgb[3]or 0
        -- Prove the current RGB still equals the imported word before doing
        -- source-style rounding. Changed/custom/legacy RGB remains exact.
        bgr[slot][color]=original or((component5[r]or floor(r*31/255+.5))
          +(component5[g]or floor(g*31/255+.5))*32+(component5[b]or floor(b*31/255+.5))*1024)
        local chosen=colors and colors[color+1]
        if chosen then r,g,b=chosen[1],chosen[2],chosen[3]
        elseif original then
          r,g,b=floor((original%32)*255/31+.5),floor((floor(original/32)%32)*255/31+.5),floor((floor(original/1024)%32)*255/31+.5)
        end
        local value=string.char(r,g,b,255);lut[slot*16+color]=value;stamp[#stamp+1]=value;row[#row+1]=value
      end
      rows[slot]=concat(row)
      if not self.paletteRows or self.paletteRows[slot]~=rows[slot]then changed[slot]=true end
    end
    self.paletteRows=rows
    return lut,bgr,concat(stamp),changed
  end
  local function indexed(mid)
    local under,over={},{}
    for i=1,256 do under[i],over[i]=0,0 end
    local above=decoder:topIsAbovePlayer(mid)
    for n,entry in ipairs(decoder:entries(mid))do
      local layer=floor((n-1)/4)
      local dest=layer==0 and under or(above and over or under)
      local quad=(n-1)%4;local pixels=decoder:tilePixels(entry.tile)
      for y=0,7 do for x=0,7 do
        local sx,sy=entry.flipX and 7-x or x,entry.flipY and 7-y or y
        local color=pixels[sy*8+sx+1]or 0
        if color~=0 or layer==0 then
          local offset=(floor(quad/2)*8+y)*16+(quad%2)*8+x+1
          dest[offset]=color==0 and 0 or(entry.palette*16+color)
        end
      end end
    end
    return bytes(under),bytes(over)
  end
  local function rgba(indices,lut,over)
    local out={}
    for i=1,256 do
      local index=indices:byte(i)
      out[i]=over and index==0 and'\0\0\0\0'or lut[index]
    end
    return concat(out)
  end
  function self:update(ticks)
    local changed=decoder:setAnimationTicks(ticks)
    decoder:setPaletteTicks(ticks)
    local lut,bgr,key,palettes=paletteLut()
    local dirty,indexDirty={},{}
    if self.paletteKey==nil then for slot=0,#self.mids-1 do dirty[slot]=true;indexDirty[slot]=true end
    else
      for tile in pairs(changed)do for slot in pairs(usedTiles[tile]or{})do dirty[slot]=true;indexDirty[slot]=true end end
      for palette in pairs(palettes)do for slot in pairs(self.paletteUsers[palette]or{})do dirty[slot]=true end end
    end
    local underDirty,overDirty={},{}
    for slot in pairs(dirty)do
      local prior=self.indexed[slot];local u,o
      if indexDirty[slot]then u,o=indexed(self.mids[slot+1])else u,o=prior[1],prior[2]end
      if not prior or prior[1]~=u or prior[2]~=o then
        self.indexed[slot]={u,o};self.indexRevision=self.indexRevision+1
        for palette in pairs(self.slotPalettes[slot]or{})do self.paletteUsers[palette][slot]=nil end
        local used={}
        for plane,indices in ipairs({u,o})do for i=1,256 do
          local index=indices:byte(i)
          if plane==1 or index~=0 then used[floor(index/16)]=true end
        end end
        self.slotPalettes[slot]=used
        for palette in pairs(used)do self.paletteUsers[palette]=self.paletteUsers[palette]or{};self.paletteUsers[palette][slot]=true end
      end
      local under,over=rgba(u,lut,false),rgba(o,lut,true)
      if self.under[slot]~=under then self.under[slot]=under;underDirty[slot]=true end
      if self.over[slot]~=over then self.over[slot]=over;overDirty[slot]=true end
      if self.checkpoint and slot%16==15 then self.checkpoint('pixels')end
    end
    -- Sparse-atlas padding is not an indexed metatile. Palette operations
    -- paint real cells only, retaining the original black padding texels.
    self.backgroundChanged=false
    self.bgr=bgr;self.paletteKey=key;self.ticks=ticks
    if next(underDirty)or next(overDirty)or self.backgroundChanged then self.revision=self.revision+1 end
    return underDirty,overDirty
  end
  function self:setPalette(slot,words)
    assert(integer(slot,15),'invalid palette slot')
    self.paletteOverrides[slot]=words and M.colors(words)or nil
    return self:update(self.ticks or 0)
  end
  function self:rgba(over)
    local slots=over and self.over or self.under
    local blank=string.rep(over and'\0\0\0\0'or self.background,16)
    local lines={}
    for y=0,self.height-1 do
      local line={};local row=floor(y/16);local py=y%16
      for x=0,self.cols-1 do
        local data=slots[row*self.cols+x]
        line[x+1]=data and data:sub(py*64+1,py*64+64)or blank
      end
      lines[y+1]=concat(line)
    end
    return concat(lines)
  end
  function self:blob(over)
    local out={'SVMI',string.char(1,2),le16(#self.mids),le16(self.cols),le16(self.rows)}
    for _,mid in ipairs(self.mids)do out[#out+1]=le16(mid)end
    for slot=0,#self.mids-1 do out[#out+1]=self.indexed[slot][over and 2 or 1]end
    return concat(out)
  end
  function self:palettePixels(slot,over)
    local out={cells={}}
    for atlasSlot=0,#self.mids-1 do
      local data=self.indexed[atlasSlot][over and 2 or 1]
      for i=1,256 do
        local value=data:byte(i)
        if floor(value/16)==slot and not(over and value==0)then
          local p=i-1
          out[#out+1]={(atlasSlot%self.cols)*16+p%16,floor(atlasSlot/self.cols)*16+floor(p/16),value%16}
          out.cells[atlasSlot]=true
        end
      end
    end
    return out
  end
  self:update(0)
  self.checkpoint=nil
  return self
end
return M
