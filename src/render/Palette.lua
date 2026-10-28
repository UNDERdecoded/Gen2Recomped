-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Palette IDs and category vocabulary follow Gen1Recomp's public protocol.
-- An optional authored data.gb_palettes library supplies named ramps; this
-- module contains no cartridge palette catalogue or private renderer data.
local P = {}
P.MONO_COLOURS = {
  {"GREEN",155,188,15}, {"LIME",168,216,56}, {"OLIVE",166,172,132},
  {"AMBER",255,176,0}, {"ORANGE",255,128,48}, {"RED",255,80,80},
  {"ROSE",255,144,176}, {"MAGENTA",240,96,208}, {"PURPLE",176,112,240},
  {"INDIGO",128,128,240}, {"BLUE",80,160,255}, {"CYAN",64,224,224},
  {"TEAL",64,192,160}, {"MINT",144,224,176}, {"SAND",224,200,144},
  {"BROWN",192,144,80}, {"WHITE",255,255,255}, {"SILVER",208,216,224},
}
P.GREY_CHROMA, P.HUE_ARC = 12, 50
P.CATEGORIES = {{key="full",label="FULL COLOUR"},{key="single",label="SINGLE COLOUR"},{key="grey",label="GREYSCALE"}}
local library, index, buckets, lastId, lastRamp
function P.packs()
  if library == nil then
    local ok, value = pcall(require, "data.gb_palettes")
    library = ok and type(value) == "table" and value or false
  end
  return library or {}
end
function P.packId(group, name) return "p:" .. group .. "/" .. name end
function P.monoId(r,g,b) return ("m:%02x%02x%02x"):format(r,g,b) end
function P.monoRamp(r,g,b)
  local out = {}
  for i, scale in ipairs({1,0.72,0.38,0.12}) do
    out[i] = {math.floor(r*scale+0.5),math.floor(g*scale+0.5),math.floor(b*scale+0.5)}
  end
  return out
end
function P.unhex(text)
  if type(text) ~= "string" or #text ~= 24 or text:find("[^%x]") then return nil end
  local out = {}
  for i=1,4 do
    out[i] = {}
    for c=1,3 do local at=(i-1)*6+(c-1)*2+1;out[i][c]=tonumber(text:sub(at,at+1),16) end
  end
  return out
end
function P.hueChroma(color)
  local r,g,b=color[1] or 0,color[2] or 0,color[3] or 0
  local hi,lo=math.max(r,g,b),math.min(r,g,b)
  local c=hi-lo
  if c<=0 then return 0,0 end
  local h
  if hi==r then h=((g-b)/c)%6 elseif hi==g then h=(b-r)/c+2 else h=(r-g)/c+4 end
  return h*60,c
end
function P.hueArc(hues)
  local span=360
  for _,start in ipairs(hues) do
    local width=0
    for _,hue in ipairs(hues) do width=math.max(width,(hue-start)%360) end
    span=math.min(span,width)
  end
  return span
end
function P.categoryOf(ramp)
  if type(ramp)~="table" or not ramp[4] then return nil end
  local hues={}
  for i=1,4 do
    local h,c=P.hueChroma(ramp[i])
    if c>P.GREY_CHROMA then hues[#hues+1]=h end
  end
  if #hues==0 then return "grey" end
  return P.hueArc(hues)<=P.HUE_ARC and "single" or "full"
end
local function ensureIndex()
  if index then return end
  index,buckets={},{full={},single={},grey={}}
  for _,pack in ipairs(P.packs()) do
    for _,entry in ipairs(pack.palettes or {}) do
      if type(entry[1])=="string" then
        local id=P.packId(pack.name,entry[1]);index[id]=entry
        local ramp=P.unhex(entry[2]);local category=ramp and P.categoryOf(ramp)
        if category then
          local bucket=buckets[category]
          bucket[#bucket+1]={name=entry[1],pack=pack.name,id=id}
        end
      end
    end
  end
end
function P.findPack(group,name) ensureIndex();return index[P.packId(group,name)] end
function P.category(key)
  ensureIndex()
  for _,category in ipairs(P.CATEGORIES) do
    if category.key==key then return {key=key,name=category.label,palettes=buckets[key]} end
  end
end
function P.categories()
  local out={}
  for _,category in ipairs(P.CATEGORIES) do out[#out+1]=P.category(category.key) end
  return out
end
function P.locate(id)
  if type(id)~="string" or id=="" then return nil end
  ensureIndex()
  for _,category in ipairs(P.CATEGORIES) do
    for i,palette in ipairs(buckets[category.key]) do if palette.id==id then return category.key,i end end
  end
end
function P.label(id)
  if type(id)~="string" or id=="" then return nil end
  local hex=id:match("^m:(%x+)$")
  if hex then
    local r,g,b=tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16)
    for _,color in ipairs(P.MONO_COLOURS) do if r==color[2] and g==color[3] and b==color[4] then return color[1] end end
    return "MONO"
  end
  return id:match("^p:.*/([^/]+)$") or id
end
function P.ramp(id)
  if type(id)~="string" or id=="" then return nil end
  if id==lastId then return lastRamp end
  local ramp
  local hex=id:match("^m:(%x%x%x%x%x%x)$")
  if hex then ramp=P.monoRamp(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
  else
    local group,name=id:match("^p:(.*)/([^/]+)$")
    local entry=group and P.findPack(group,name)
    local raw=entry and P.unhex(entry[2])
    if raw then ramp={raw[4],raw[3],raw[2],raw[1]} end
  end
  lastId,lastRamp=id,ramp
  return ramp
end
function P.swatch(id)
  local ramp=P.ramp(id)
  if ramp then return {ramp[4],ramp[3],ramp[2],ramp[1]} end
end
function P.invalidate() index,buckets,lastId,lastRamp=nil,nil,nil,nil end
return P
