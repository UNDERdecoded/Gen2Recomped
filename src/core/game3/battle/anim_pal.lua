-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Decode source artwork with LOVE; palette indices must be explicit imported
-- data. RGBA colours cannot recover duplicate cartridge palette entries.
local P={}
local blend
function P.shader()
 if not blend then
  blend=love.graphics.newShader([[
   extern vec3 blendColor;
   extern number blendCoeff;
   vec4 effect(vec4 colour, Image image, vec2 uv, vec2 screen) {
    vec4 pixel=Texel(image,uv);
    return vec4(mix(pixel.rgb,blendColor,blendCoeff),pixel.a)*colour;
   }
  ]])
  blend:send('blendColor',{0,0,0});blend:send('blendCoeff',0)
 end
 return blend
end
function P.loadImageData(bytes,name)
 if type(bytes)~='string'then return nil,'animation image bytes unavailable'end
 local file=love.filesystem.newFileData(bytes,name or'animation.png')
 local ok,data=pcall(love.image.newImageData,file);file:release()
 if not ok then return nil,data end
 return data
end
function P.hydrateIndex(info,tag,image,reader)
 assert(type(info)=='table'and type(reader)=='function','animation artwork and reader required')
 if info.idxImage then return true end
 local path=info.indexFile or info.idxFile
 if not path then return false,'animation artwork has no explicit palette indices'end
 local data,why=P.loadImageData(reader(path),path)
 if not data then return false,why end
 local w,h=image:getDimensions();local iw,ih=data:getDimensions()
 if iw~=w or ih~=h then data:release();return false,'animation palette index dimensions differ'end
 local ok,texture=pcall(love.graphics.newImage,data)
 if not ok then data:release();return false,texture end
 texture:setFilter('nearest','nearest');info.idxImage,info.idxData=texture,data
 return true
end
P._service={release=function()
 if blend then blend:release();blend=nil end
end}
require('src.core.game3.asset_stream').register(P._service)
return P
