-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local B=require('src.render.ShaderBranches')
local qualified=assert(B.plan('uniform LOVE_HIGHP_OR_MEDIUMP float gate;void f(){if(gate>.5){}}'))
T.eq(qualified.order[1],'gate','standard precision macro is a qualifier')
local source=[[
uniform float enabled;
uniform highp float amount;
uniform bool lit;
uniform int count;
uniform float unused;
uniform float array[4];
// if(enabled) amount
vec4 effect(){
 if(enabled > .5 && lit){float enabledExtra=amount*2.0;}
 if(!lit){if(enabled < .5){return vec4(amount);}}
 if(count>0 && array[0]>.5){return vec4(1.0);}
 return vec4(amount);
}
]]
local plan=assert(B.plan(source))
T.eq(table.concat(plan.order,','),'enabled,lit','only branch-only float/bool reads qualify')
local constants,key,count=B.key(plan,{enabled=0,lit=true,amount=1,count=0})
T.eq(key,'enabled=0.0;lit=true');T.eq(count,2)
local result=B.rewrite(plan,constants)
T.check(result:find('uniform float enabled;',1,true),'original declaration is retained')
T.check(result:find('// if(enabled) amount',1,true),'comments remain byte-identical')
T.check(result:find('if(0.0 > .5 && true)',1,true),'actual branch reads specialize')
T.check(result:find('if(!true){if(0.0 < .5)',1,true),'nested branch reads specialize')
T.check(result:find('enabledExtra=amount*2.0',1,true),'identifier prefixes and arithmetic remain unchanged')
T.check(result:find('count>0 && array[0]',1,true),'integer and array paths stay dynamic')
T.eq(B.rewrite(plan,{}),source,'no qualified value is exact passthrough')
for _,value in ipairs{.5,2,-1,math.huge,-math.huge,0/0}do T.eq(B.literal('float',value),nil,'arbitrary/nonfinite values stay dynamic')end
T.eq(B.literal('float',-1/math.huge),nil,'negative zero stays dynamic')
T.eq(B.literal('float',0),'0.0');T.eq(B.literal('float',1),'1.0')
T.eq(B.literal('bool',false),'false');T.eq(B.literal('bool',true),'true')
T.eq(B.literal('bool',0),nil);T.eq(B.literal('int',0),nil)
for _,suffix in ipairs{
 'float other(float gate){if(gate>0.0)return 1.0;return 0.0;}',
 'void other(){float a=1.0,gate=0.0;if(gate>.5){}}',
 '#define ALIAS gate\nvoid other(){if(gate>.5){}}',
 'void other(){if(bool gate=true){}}',
 '#if (gate)\n#endif\nvoid other(){if(gate>.5){}}',
 '#define DEFINE uniform float gate;\nvoid other(){if(gate>.5){}}',
}do
 local p=assert(B.plan('uniform float gate;\n'..suffix))
 T.eq(#p.order,0,'shadowed or macro candidate is rejected')
end
local arithmetic=assert(B.plan('uniform float gate; void f(){float b=gate*2.0;if(gate>.5){}}'))
T.eq(#arithmetic.order,1,'a branch read can specialize while arithmetic stays dynamic')
T.check(B.rewrite(arithmetic,{gate='0.0'}):find('float b=gate*2.0;if(0.0>.5)',1,true),'uniform arithmetic is preserved byte-for-byte')
local commented=assert(B.plan('uniform float gate; void f(){if(/* gate */ gate>.5){}}'))
local c=B.key(commented,{gate=1})
T.check(B.rewrite(commented,c):find('if(/* gate */ 1.0>.5)',1,true),'inline comment is preserved while actual token changes')
T.eq(B.plan('uniform float gate; /* unfinished'),nil)
T.eq(B.plan('uniform float gate; void f(){if(gate'),nil)
T.eq(B.plan('uniform float gate; uniform bool gate;'),nil)
T.eq(B.plan({}),nil)
for _,body in ipairs{
 'float x=0.0,gate=1.0;if(gate>.5){}',
 'for(float x=0.0,gate=0.0;x<1.0;x++){if(gate>.5){}}',
 'float named(float x,float gate){if(gate>.5){}return gate;}',
 '#define DECL(a,b) float a,b;\nvoid f(){DECL(other,gate);if(gate>.5){}}',
 '#define DECL(a,b) float a,b;\nvoid f(){DECL(gate,other);if(gate>.5){}}',
 '#define DECL(a,b) float a,b;\nvoid f(){DECL(other,nested(gate));if(gate>.5){}}',
}do
 local p=assert(B.plan('uniform float gate;\n'..body))
 T.eq(#p.order,0,'declarations, loop headers and macro expansion retain the original branch')
end
T.eq(B.plan('#define LOCAL(a,b) float a##b;\nuniform float gate;void f(){LOCAL(ga,te);if(gate>.5){}}'),nil,'token-pasted shadow names cannot be proven')
T.check(not pcall(B.rewrite,plan,{enabled='malicious code'}),'only qualified literal bytes can enter output')
local large,expected={},{}
for i=1,64 do
 local line=('uniform float gate%d;\n'):format(i);large[#large+1]=line;expected[#expected+1]=line
end
-- Large generated programs must retain comments, arithmetic, nested branches
-- and complete identifier boundaries while specializing every selected read.
local values={};for i=1,64 do values['gate'..i]=i%2==0 and'0.0'or'1.0'end
for i=1,1024 do
 local name='gate'..((i-1)%64+1)
 local line=('void f%d(){if(/* %s */%s>.5){if(%s<.5){float v=%s*2.;}}}\n'):format(i,name,name,name,name)
 large[#large+1]=line
 expected[#expected+1]=('void f%d(){if(/* %s */%s>.5){if(%s<.5){float v=%s*2.;}}}\n'):format(i,name,values[name],values[name],name)
end
large=table.concat(large);expected=table.concat(expected)
local big=assert(B.plan(large));T.eq(#big.order,64)
T.eq(B.rewrite(big,values),expected,'large nested shader output is exact, without rebuilding the program per branch')
T.eq(B.rewrite(big,{}),large,'large dynamic program is byte-identical')
for _,prefix in ipairs{'word ','word\n','word\t',',',' ,\n','.',' .\t'}do
 local p=assert(B.plan('uniform float gate;void f(){'..prefix..'gate;if(gate>.5){}}'))
 T.eq(#p.order,0,'token predecessor retains shadow/member rejection: '..prefix)
end
T.finish('shader branch planning, unchanged arithmetic and conservative source guards')
