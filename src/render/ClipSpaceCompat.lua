-- Only for shaders emitting custom, already canvas-oriented clip coordinates.
-- Standard 2D shaders using transform_projection already follow LÖVE's backend.
local C={}
--
-- These shaders were written for 11.x canvases, where clip y -1 is the TOP row.
-- LOVE 12 wants its own convention, y +1 at the top, and flips afterwards where
-- the backend needs it. Reading love_ClipSpaceParams.x as "the flip to cancel"
-- is only right where that flip exists: OpenGL ES and desktop canvases get -1 and
-- so do Vulkan's, but METAL NEVER FLIPS (only Z_NEG1_1_TO_0_1 in
-- metal/Graphics.mm, x is always 1), because a Metal texture's row 0 is already
-- at clip +1. So on iOS, where Metal is the first renderer tried, this left every
-- one of these shaders upside down: the DS fields and BW's battle backdrop under
-- an upright UI and upright sprites, and the voxel mods. A canvas needs the
-- negation on every backend, so Metal says it outright.
local function flipExpression()
 local ok,name=pcall(function() return love.graphics.getRendererInfo() end)
 if ok and type(name)=="string" and name:lower():find("metal",1,true) then return "-1.0" end
 return "love_ClipSpaceParams.x"
end
function C.shader(source)
 local major=love and love.getVersion and love.getVersion() or 11
 if major<12 then return source end
 local count
 source,count=source:gsub("vec4%s+position%s*%(","vec4 legacyPosition(")
 if count==0 then return source end
 return source..[[
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
 vec4 clip=legacyPosition(transform_projection,vertex_position);
 clip.y*=]]..flipExpression()..[[;
 return clip;
}
#endif
]]
end
return C
