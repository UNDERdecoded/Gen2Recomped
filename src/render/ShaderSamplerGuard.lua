-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Keep original live 2D samplers visible to the Metal stage linker when a
-- branch is folded. The private control uniform is always zero. Unsupported
-- stage/resource syntax is allowed to fail compilation and use the original.
local G={uniform='pokeportBranchSamplerGuard'}
function G.rewrite(source,clean,hasUniform)
 assert(not clean:find(G.uniform,1,true),'sampler guard name already present')
 assert(not clean:find('pokeportBranchVertexSample',1,true)and not clean:find('pokeportBranchPixelSample',1,true),'sampler helper name already present')
 assert(not clean:find('%f[%w_]buffer%f[^%w_]'),'storage buffers stay native')
 assert(not clean:find('uniform%s+Image%s+[%w_]+%s*%['),'sampler arrays stay native')
 for kind in clean:gmatch('uniform%s+([%w_]+)%s+')do
  assert(not kind:find('Image')or kind=='Image','other sampler types stay native')
 end
 local names={vertex={},pixel={}};local seen={vertex={},pixel={}}
 local function both(a,b)if a==false or b==false then return false end;if a and b then return true end end
 local function either(a,b)if a or b then return true end;if a==false and b==false then return false end end
 local function invert(a)if a~=nil then return not a end end
 local function symbol(name,stage)
  if name=='VERTEX'then return stage=='vertex'end
  if name=='PIXEL'then return stage=='pixel'end
 end
 for _,stage in ipairs{'vertex','pixel'}do
  local allowed=true;local stack={}
  for line in(clean..'\n'):gmatch('(.-)\n')do
   local directive,arg=line:match('^%s*#%s*(%w+)%s*(.-)%s*$')
   if directive=='ifdef'or directive=='ifndef'or directive=='if'then
    local condition
    if directive=='if'then
     local text=arg:gsub('%s+','')
     local name=text:match('^defined%(([%w_]+)%)$')or text:match('^defined([%w_]+)$')
     if name then condition=symbol(name,stage)
     elseif text=='0'then condition=false elseif text=='1'then condition=true end
    else condition=symbol(arg:match('^(%w+)'),stage);if directive=='ifndef'then condition=invert(condition)end end
    stack[#stack+1]={parent=allowed,taken=condition};allowed=both(allowed,condition)
   elseif directive=='else'then
    local top=assert(stack[#stack]);allowed=both(top.parent,invert(top.taken));top.taken=true
   elseif directive=='elif'then
    local top=assert(stack[#stack]);allowed=both(top.parent,invert(top.taken));top.taken=either(top.taken,nil)
   elseif directive=='endif'then
    local top=assert(stack[#stack]);stack[#stack]=nil;allowed=top.parent
   elseif allowed~=false then
    for name in line:gmatch('uniform%s+Image%s+([%w_]+)%s*;')do
     if not seen[stage][name]and hasUniform(name)then seen[stage][name]=true;names[stage][#names[stage]+1]=name end
    end
   end
  end
  assert(#stack==0,'unbalanced shader stage directives')
  assert(#names[stage]<=16,'sampler guard stage cap')
 end
 local function sum(stage)
  local samples={};for _,name in ipairs(names[stage])do samples[#samples+1]='Texel('..name..',vec2(0.0))'end
  return #samples>0 and table.concat(samples,'+')or'vec4(0.0)'
 end
 -- A valid source may declare a stage sampler after position(). Prototypes
 -- keep the injected call legal there; definitions follow all declarations.
 local prefix='uniform float '..G.uniform..';\n#ifdef VERTEX\nvec4 pokeportBranchVertexSample();\n#endif\n#ifdef PIXEL\nvec4 pokeportBranchPixelSample();\n#endif\n'
 local pragma,rest=source:match('^(#pragma[^\n]*\n)(.*)$')
 source=pragma and(pragma..prefix..rest)or(prefix..source)
 local outputs,maxOutput={},0
 for slot in clean:gmatch('love_Canvases%[(%d+)%]')do maxOutput=math.max(maxOutput,tonumber(slot))end
 assert(maxOutput<8,'sampler guard output cap')
 for slot=0,maxOutput do outputs[#outputs+1]='love_Canvases['..slot..']=pokeportBranchSample;'end
 local n
 source,n=source:gsub('(void%s+effect%s*%(%s*%)%s*{)',function(entry)
  return entry..'\n#ifdef PIXEL\nif('..G.uniform..'>.5){vec4 pokeportBranchSample=pokeportBranchPixelSample();'..table.concat(outputs)..'return;}\n#endif\n'
 end,1)
 if n==0 then
  source=source:gsub('(vec4%s+effect%s*%([^)]*%)%s*{)',function(entry)
   return entry..'\n#ifdef PIXEL\nif('..G.uniform..'>.5)return pokeportBranchPixelSample();\n#endif\n'
  end,1)
 end
 source=source:gsub('(vec4%s+position%s*%([^)]*%)%s*{)',function(entry)
  return entry..'\n#ifdef VERTEX\nif('..G.uniform..'>.5)return pokeportBranchVertexSample();\n#endif\n'
 end,1)
 return source..'\n#ifdef VERTEX\nvec4 pokeportBranchVertexSample(){return '..sum('vertex')..';}\n#endif\n#ifdef PIXEL\nvec4 pokeportBranchPixelSample(){return '..sum('pixel')..';}\n#endif\n'
end
return G
