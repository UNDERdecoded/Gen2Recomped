-- Typed binary cache input. A caller-supplied cache owns its I/O; this module
-- never reads profiles or imports a cartridge to satisfy a sprite request.
local M={}
local function u16(s,i)return s:byte(i)+s:byte(i+1)*256 end
local function signed(n)return n>=128 and n-256 or n end
function M.decode(bytes,gid)
  if type(bytes)~='string'or#bytes<16 or bytes:sub(1,4)~='SVOW'then return nil,'invalid sprite metadata'end
  local version=bytes:byte(5);if version<1 or version>4 then return nil,'unsupported sprite metadata version'end
  local r={formatVersion=version,inanimate=bytes:byte(6)==1,graphicsId=u16(bytes,7),
    width=u16(bytes,9),height=u16(bytes,11),frameCount=u16(bytes,13),paletteTag=u16(bytes,15),drawOffX=0,drawOffY=0}
  if r.graphicsId~=gid then return nil,'sprite metadata identity mismatch'end
  if r.width<8 or r.width>128 or r.height<8 or r.height>128 or r.frameCount<1 or r.frameCount>256
      or r.width*r.height*r.frameCount>2097152 then return nil,'sprite metadata geometry limit'end
  if version>=2 then
    if #bytes<118 then return nil,'truncated sprite palettes'end
    r.reflectionPaletteTag=u16(bytes,17);r.paletteSlot=bytes:byte(19);r.reflectionPaletteMappedTag=u16(bytes,20)
    local flags=bytes:byte(22)
    for index,key in ipairs({'palette','reflectionPalette','mappedReflectionPalette'})do
      local p={};for c=0,15 do p[c]=u16(bytes,23+(index-1)*32+c*2)end;r[key]=p
    end
    if flags%2==0 then r.reflectionPalette=nil end
    if math.floor(flags/2)%2==0 then r.mappedReflectionPalette=nil end
    if r.reflectionPaletteTag==65535 then r.reflectionPaletteTag=nil end
    if r.reflectionPaletteMappedTag==65535 then r.reflectionPaletteMappedTag=nil end
  end
  if version==4 then
    if #bytes<120 then return nil,'truncated sprite anchors'end
    r.drawOffX,r.drawOffY=signed(bytes:byte(119)),signed(bytes:byte(120))
  end
  return r
end
function M.read(cache,root,gid)
  local meta=cache:read(root..'/'..gid..'.meta');if not meta then return nil end
  local r,why=M.decode(meta,gid);if not r then return nil,why end
  local rgba=cache:read(root..'/'..gid..'.rgba')
  if type(rgba)~='string'or#rgba~=r.width*r.height*r.frameCount*4 then return nil,'invalid sprite RGBA payload'end
  return r,rgba
end
function M.manifest(cache,root)
  local bytes=cache:read(root..'/manifest.lua')
  if not bytes then return nil end
  if type(bytes)~='string'or#bytes>1048576 then return nil,'sprite manifest size limit'end
  local chunk,why
  if setfenv then chunk,why=loadstring(bytes,'@sprite-manifest')
  else chunk,why=load(bytes,'@sprite-manifest','t',{})end
  if not chunk then return nil,why end
  if setfenv then setfenv(chunk,{})end
  -- Count hooks do not interrupt an already compiled LuaJIT loop. The tiny
  -- generated manifest runs once; disable traces for it and its nested data
  -- constructors so the instruction guard remains effective.
  if jit and jit.off then jit.off(chunk,true)end
  local hook,mask,count=debug.gethook()
  debug.sethook(function()error('sprite manifest instruction limit')end,'',200000)
  local ok,result=pcall(chunk);debug.sethook(hook,mask,count)
  if not ok or type(result)~='table'then return nil,'invalid sprite manifest'end
  return result
end
return M
