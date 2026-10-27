-- Only for shaders emitting custom, already canvas-oriented clip coordinates.
-- Standard 2D shaders using transform_projection already follow LÖVE's backend.
local C={}
function C.shader(source)
 local major=love and love.getVersion and love.getVersion() or 11
 if major<12 then return source end
 local count
 source,count=source:gsub("vec4%s+position%s*%(","vec4 legacyPosition(")
 if count==0 then return source end
 return "#define POKEPORT_NATIVE_CLIP_SPACE 1\n"..source..[[
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
 vec4 clip=legacyPosition(transform_projection,vertex_position);
 clip.y*=love_ClipSpaceParams.x;
 return clip;
}
#endif
]]
end
return C
