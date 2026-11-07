-- LÖVE 11 shaders here already emit canvas-oriented clip coordinates.
-- LÖVE 12 applies another backend-specific Y transform after position().
-- Cancel only that additional Y transform; keep its Vulkan/Metal depth fix.
local C = {}
function C.shader(source)
 local major=love and love.getVersion and love.getVersion() or 11
 if major<12 then return source end
 -- the engine's answer knows the backend (Metal has no flip to cancel); the rest
 -- is for this file running where the engine's source is not on the path
 local okCore,core=pcall(require,"src.render.ClipSpaceCompat")
 if okCore and core and core.shader then return core.shader(source) end
 local count
 source,count=source:gsub("vec4%s+position%s*%(","vec4 legacyPosition(")
 if count==0 then return source end
 return source..[[
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
