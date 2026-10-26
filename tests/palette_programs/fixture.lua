-- Original synthetic GBA data and tiny Thumb leaf initializers. No cartridge
-- code, palette bytes, ROM images or player files are distributed by this test.
local F={}
local Json=require("src.link.Json")
local Rom=require("src.import.RomGba")
local function le(n,count)
  local s={};for i=1,count do s[i]=string.char(n%256);n=math.floor(n/256) end
  return table.concat(s)
end
function F.new(game)
  local file=assert(io.open("tools/rom_manifest_"..game..".json","rb"))
  local manifest=Json.decode(file:read("*a"));file:close()
  -- This synthetic cartridge contains palette programs, not the independent
  -- retail terrain-flag table. Its source-byte/hash contract is tested by
  -- gen3_source_flags and the real-cartridge integration host.
  manifest.metatileBehaviorFlags=nil
  local chunks={}
  local out={manifest=manifest,frames={},initializers={},sets={}}
  local function put(at,bytes) chunks[at]=bytes end
  local function init(at,target,readCounter)
    -- LDR literal / MOV immediate / counter halfword store; optional unknown
    -- RAM read mirrors initializers that inherit the primary counter.
    local h={0x4907,0x2000,0x8008,0x4907,0x2080,0x0080,0x8008,
      0x4906,0x4806,0x6008,0x4770}
    if readCounter then h[2]=0x8808 end
    local bytes={};for i,w in ipairs(h) do bytes[i]=le(w,2) end
    put(at,table.concat(bytes))
    -- Pools reflect each LDR's aligned PC, not its apparent instruction PC.
    put(at+32,le(0x03000010,4))
    put(at+36,le(0x03000012,4))
    put(at+40,le(0x03000020,4))
    put(at+44,le(target,4))
    out.initializers[#out.initializers+1]=at
    return 0x08000000+at+1
  end
  local profile=manifest.terrainPalettePrograms
  local keys={};for key in pairs(profile.programs) do keys[#keys+1]=key end
  table.sort(keys,function(a,b) return tonumber(a)<tonumber(b) end)
  for index,key in ipairs(keys) do
    local p=profile.programs[key]
    out.sets[p.id]={secondary=p.secondary,callback=init(0x1000+index*0x100,0x08000000+tonumber(key)+1,index%2==0)}
    if p.kind=="frames" then
      out.program=p
      for frame=0,p.frames-1 do
        local words,rgb={},{}
        for c=0,p.count-1 do
          local r,g,b=(c*3+frame*7)%32,(c*5+frame*11)%32,(c*9+frame*13)%32
          words[#words+1]=le(r+g*32+b*1024,2)
          rgb[#rgb+1]=string.char(math.floor(r*255/31),math.floor(g*255/31),math.floor(b*255/31))
        end
        local dest=0x6000+frame*32
        put(p.table+frame*4,le(0x08000000+dest,4));put(dest,table.concat(words))
        out.frames[frame+1]=table.concat(rgb)
      end
    end
  end
  out.sets.no_callback={secondary=true,callback=0}
  out.sets.null_callback={secondary=true,callback=init(0x3800,0)}
  out.sets.unknown={secondary=true,callback=init(0x3900,0x08100001)}
  local keys2={};for at in pairs(chunks) do keys2[#keys2+1]=at end;table.sort(keys2)
  local pieces,position={},0
  for _,at in ipairs(keys2) do
    assert(at>=position,"overlapping synthetic writes")
    pieces[#pieces+1]=string.rep("\0",at-position);pieces[#pieces+1]=chunks[at];position=at+#chunks[at]
  end
  pieces[#pieces+1]=string.rep("\0",0x530000-position)
  out.rom=Rom.new(table.concat(pieces))
  function out.change(at,bytes)
    out.rom=Rom.new(out.rom.data:sub(1,at)..bytes..out.rom.data:sub(at+#bytes+1))
  end
  out.init=init
  return out
end
F.le=le
return F
