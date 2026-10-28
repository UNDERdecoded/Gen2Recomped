-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('src.core.ModCompat').install()
local G=require('src.render.GbcPalette')
local P=require('src.render.PaletteFX')
local V=require('src.core.GameVersion')
local A={{251,241,239},{211,37,53},{17,181,89},{29,31,157}}
local B={{233,227,223},{13,67,197},{163,41,131},{3,7,11}}
local R={{229,199,167},{179,127,79},{109,61,23},{47,19,5}}
local active,fail
local function compiler(code)
 return {code=code,values={},send=function(self,name,...)
  if fail==name then fail=nil;error('driver rejected uniform')end
  local args={...};local out={}
  for i,v in ipairs(args)do out[i]=type(v)=='table'and{unpack(v)}or v end
  self.values[name]=out
 end}
end
love.graphics={newShader=compiler,setShader=function(s)active=s end,getShader=function()return active end}
T.eq(G.BGP_IDENTITY,0xe4,'public identity byte')
T.same(G.bgpShades(),{0,1,2,3},'omitted byte is identity')
for _,edition in ipairs({'red','gold','silver','crystal'})do
 V.set(edition);P.setMode('gbc');P.setShadeMap(nil)
 for byte=0,255 do
  local fields,expected={},{}
  for i=0,3 do fields[i+1]=math.floor(byte/4^i)%4;expected[i+1]=A[fields[i+1]+1]end
  local label=edition..' byte '..byte
  T.same(G.bgpShades(byte),fields,label..' reads all two-bit fields')
  T.same(G.remap(A,byte),expected,label..' explicit palette permutation')
  local before=G.bgp
  T.eq(G.setBgp(byte),before,label..' returns actual previous register')
  T.eq(G.bgp,byte~=0xe4 and byte or nil,label..' public byte reflects native state')
  T.same(P.effectiveColors(A),expected,label..' native renderer receives permutation')
  T.eq(G.resolve(A),A,label..' inspecting colours does not consume BGP')
  T.same(G.color(A,2),expected[2],label..' solid colours consume it exactly once')
  G.use(A)
  for i=1,4 do T.same(active.values['pal'..i-1][1],{expected[i][1]/255,expected[i][2]/255,expected[i][3]/255},label..' indexed draw row '..i)end
  local native=compiler('native');P.sendColors(native,A)
  for i=1,4 do T.same(native.values['c'..i-1][1],{expected[i][1]/255,expected[i][2]/255,expected[i][3]/255},label..' native uniform row '..i)end
 end
 P.setShadeMap({[0]=2,3,0,1});T.eq(G.bgp,0x4e,edition..' native register write visible publicly')
 G.bgp=0xf9;T.eq(P.bgp(),0xf9,edition..' legacy property writes native register')
 G.bgp=nil;T.eq(P.shadeMap(),nil,edition..' legacy nil clears native state')
 G.setBgp(0);P.setShadeMap(nil);T.eq(G.bgp,nil,edition..' native frame reset clears public register')
end
T.eq(G.remap(A,nil),A,'nil remap retains identity')
T.eq(G.remap(A,0xe4),A,'identity remap retains table identity')
T.eq(G.remap(nil,0xf9),nil,'missing palette stays missing')
V.set('crystal');P.setShadeMap(nil)
local src,dst,count,ambiguous=G.remapTable({A},0xf9,{B})
T.eq(count,8,'BG and OBJ rows both recognized')
T.eq(ambiguous,0,'disjoint palette mapping exact')
for i=1,4 do T.same(src[i],A[i],'BG source row');T.same(dst[i],A[({2,3,4,4})[i]],'BG byte applies own palette');T.same(dst[i+4],B[i],'OBJ row stays unchanged')end
T.eq(#src,64,'source bounded and padded');T.eq(#dst,64,'destination bounded and padded')
T.neq(src[9],src[1],'padding owns its row');T.same(src[9],src[1],'padding repeats first colour')
local _,collisionDst,_,collisions=G.remapTable({A},0xff,{A})
T.eq(collisions,3,'overlapping BG/OBJ collision count is explicit')
T.same(collisionDst[1],A[4],'first BG interpretation wins')
local rampSrc,rampDst,rampCount,rampAmbiguous=G.remapTable({A},0xf9,{B},R,{true})
T.eq(rampCount,12,'forced ramp included as already drawn source')
T.eq(rampAmbiguous,0,'disjoint forced ramp exact')
T.same(rampDst[1],R[2],'forced BG takes explicit byte')
T.same(rampDst[9],R[1],'ramped OBJ uses unpermuted forced ramp')
local _,unramped=G.remapTable({A},0xf9,{B},R)
T.same(unramped[9],B[1],'unramped OBJ retains original colour')
G.setBgp(0xff)
local u=G.remapUniforms({A},0xf9,{B})
T.same(u.src[1],{A[1][1]/255,A[1][2]/255,A[1][3]/255},'explicit backward byte ignores standing forward register')
T.same(u.dst[1],{A[2][1]/255,A[2][2]/255,A[2][3]/255},'backward byte consumed once')
G.setBgp(nil)
local ok,n=G.useRemapUniforms(u);T.check(ok,'remap shader applies');T.eq(n,0,'successful apply reports ambiguity')
local sh=active;T.eq(sh,G.remapShader(),'actual remap shader active')
T.check(sh.code:find('vec4(rgb, pixel.a) * tint',1,true)~=nil,'backward shader retains alpha and draw tint')
T.same(sh.values.remapSrc,u.src,'all normalized source entries uploaded')
T.same(sh.values.remapDst,u.dst,'all normalized destination entries uploaded')
T.same(sh.values.remapCount,{8},'bounded live count uploaded')
local first=u.src[1][1];u.src[1][1]=0
G.withRaw(A,function()G.useRemap({B},0xff)end)
T.eq(active,sh,'nested draw restores remap shader')
T.eq(sh.values.remapSrc[1][1],first,'nested draw restores detached original remap uniforms')
local did,why=pcall(function()G.withRaw(A,function()G.useRemap({B},0xff);error('draw failure',0)end)end)
T.check(not did and why=='draw failure','callback failure propagates')
T.eq(active,sh,'error restores remap shader');T.eq(sh.values.remapSrc[1][1],first,'error restores remap uniforms')
T.eq(G.useRemap({}),false,'empty palette leaves shader alone');T.eq(active,sh,'empty palette keeps prior shader')
local rows={};for p=1,20 do rows[p]={{p,1,1},{p,2,2},{p,3,3},{p,4,4}}end
local hugeSrc,hugeDst,hugeCount=G.remapTable(rows,0xff)
T.eq(hugeCount,64,'overfull palette tables bounded');T.eq(#hugeSrc,64,'source cannot overflow shader');T.eq(#hugeDst,64,'destination cannot overflow shader')
T.eq(G.remapUniforms({false,{},{{1,2,3}}},0xf9),nil,'malformed palette rows decline safely')
T.eq(G.useRemapUniforms({count=65,src={},dst={}}),false,'oversized borrowed uniforms rejected')
fail='remapDst';T.eq(G.useRemap({B},0xff),false,'driver upload failure declines effect')
T.eq(active,sh,'driver failure keeps previous shader');T.eq(sh.values.remapSrc[1][1],first,'partial driver failure restores previous uniforms')
T.eq(G.remapShader(),nil,'failed remap shader disabled for current compiler')
love.graphics.newShader=function(code)return compiler(code)end
T.check(G.useRemap({A},0xf9),'new compiler recovers from failed upload')
love.graphics={};T.eq(G.useRemap({A},0xf9),false,'headless remap declines effect')
T.finish('native palette byte register and composited BG/OBJ remapping')
