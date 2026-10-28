-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local G=require('src.render.ShaderSamplerGuard')
local source=[[
#pragma language glsl3
vec4 position(mat4 m,vec4 v){return m*v;}
uniform Image lateTexture;
#ifdef PIXEL
uniform Image pixelOnly;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return Texel(pixelOnly,uv);}
#endif
]]
local out=G.rewrite(source,source,function()return true end)
T.check(out:sub(1,23)=='#pragma language glsl3\n','language pragma keeps its original position')
T.check(out:find('vec4 pokeportBranchVertexSample();',1,true)<out:find('vec4 position',1,true),'the vertex helper is declared before its first call')
T.check(out:find('vec4 pokeportBranchVertexSample(){',1,true)>out:find('uniform Image lateTexture;',1,true),'the vertex helper body follows late sampler declarations')
T.check(out:find('vec4 pokeportBranchPixelSample(){',1,true)>out:find('uniform Image pixelOnly;',1,true),'the pixel helper follows its own stage declarations')
T.check(out:find('return m*v;',1,true),'authored vertex body remains exact')
T.check(out:find('return Texel(pixelOnly,uv);',1,true),'authored fragment body remains exact')
local vertex=assert(out:match('vec4 pokeportBranchVertexSample%(%){(.-)}'))
local pixel=assert(out:match('vec4 pokeportBranchPixelSample%(%){(.-)}'))
T.check(vertex:find('Texel(lateTexture,',1,true)~=nil);T.check(vertex:find('pixelOnly',1,true)==nil,'pixel-only bindings never leak into the vertex helper')
T.check(pixel:find('Texel(lateTexture,',1,true)~=nil);T.check(pixel:find('Texel(pixelOnly,',1,true)~=nil)
out=G.rewrite(source,source,function()return false end)
T.check(out:find('vec4 pokeportBranchVertexSample(){return vec4(0.0);}',1,true)~=nil,'inactive native samplers do not create new resource bindings')
T.check(out:find('vec4 pokeportBranchPixelSample(){return vec4(0.0);}',1,true)~=nil)
local multi='uniform Image live; void effect(){love_Canvases[2]=Texel(live,vec2(0.));}'
out=G.rewrite(multi,multi,function()return true end)
T.check(out:find('love_Canvases[2]=pokeportBranchSample;return;',1,true)~=nil,'the existing multiple-output guard remains intact')
for _,name in ipairs{G.uniform,'pokeportBranchVertexSample','pokeportBranchPixelSample'}do
 T.check(not pcall(G.rewrite,source..'\nfloat '..name..';',source..'\nfloat '..name..';',function()return true end),'reserved helper collisions fall back to the native source')
end
T.finish('stage-scoped sampler retention after valid late declarations')
