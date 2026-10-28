-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local P=require('src.core.Performance')
local savedLove,savedJit,savedEnv,savedFlag=love,jit,os.getenv,P.shaderBranchSpecialization
local savedLegacy=package.loaded['src.render.LegacyShaderCompat']
local function inert()error('passthrough policy must not call graphics')end
local function case(policy,enabled,version,osName,arch,renderer,missing,oldLegacy)
 local g={newShader=inert,getShader=inert,setShader=inert,draw=inert,getStackDepth=inert,getRendererInfo=function()return renderer end}
 love={graphics=g,getVersion=function()return version end,system={getOS=function()return osName end},thread={newChannel=inert},timer={getTime=inert}}
 if missing then love[missing]=nil end
 jit={arch=arch};P.shaderBranchSpecialization=enabled
 package.loaded['src.render.LegacyShaderCompat']=oldLegacy and{}or nil
 os.getenv=function(name)if name=='POKEPORT_SHADER_BRANCHES'then return policy end;return savedEnv(name)end
 local S=assert(loadfile('src/render/ShaderSpecialization.lua'))()
 T.eq(S.install(),false,'unqualified policy remains inactive')
 T.eq(g.newShader,inert,'original Shader constructor remains exact')
 T.eq(g.draw,inert,'native drawing entry remains exact')
 T.eq(S.status().installed,false)
end
case('0',true,12,'OS X','arm64','Metal')
case(nil,false,12,'OS X','arm64','Metal')
case('1',true,11,'OS X','arm64','Metal')
case('1',true,12,'Windows','arm64','Metal')
case('1',true,12,'OS X','x64','Metal')
case('1',true,12,'OS X','arm64','OpenGL')
case('1',true,12,'OS X','arm64','Metal','thread')
case('1',true,12,'OS X','arm64','Metal','system')
case('1',true,12,'OS X','arm64','Metal','timer')
case('1',true,12,'OS X','arm64','Metal',nil,true)
love,jit,os.getenv,P.shaderBranchSpecialization=savedLove,savedJit,savedEnv,savedFlag
package.loaded['src.render.LegacyShaderCompat']=savedLegacy
T.finish('native shader adapter platform and explicit passthrough policies')
