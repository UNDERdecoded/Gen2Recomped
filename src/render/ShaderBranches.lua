-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Pure source planning for an optional compiler optimization. This module does
-- not change graphics state. Unknown syntax keeps its original runtime branch.
local B={}
local scalar={float=true,bool=true}
local qualifier={highp=true,mediump=true,lowp=true,LOVE_HIGHP_OR_MEDIUMP=true}
local function blank(text)return(text:gsub('[^\n]',' '))end
local function uncomment(source)
 local pieces,at={},1
 while at<=#source do
  local first=source:find('/',at,true)
  if not first then pieces[#pieces+1]=source:sub(at);break end
  pieces[#pieces+1]=source:sub(at,first-1)
  local pair=source:sub(first,first+1);local finish
  if pair=='//'then finish=source:find('\n',first+2,true)or(#source+1)
  elseif pair=='/*'then local last=source:find('*/',first+2,true);if not last then return end;finish=last+2 end
  if finish then pieces[#pieces+1]=blank(source:sub(first,finish-1));at=finish
  else pieces[#pieces+1]='/';at=first+1 end
 end
 return table.concat(pieces)
end
local function withoutDirectives(clean)
 local continued=false;local out={}
 for line in(clean..'\n'):gmatch('(.-)\n')do
  local directive=continued or line:match('^%s*#')~=nil
  continued=directive and line:match('\\%s*$')~=nil
  out[#out+1]=directive and blank(line)or line
 end
 return table.concat(out,'\n')
end
function B.plan(source)
 if type(source)~='string'then return nil,'source is not text'end
 local clean=uncomment(source);if not clean then return nil,'unfinished comment'end
 if clean:find('##',1,true)then return nil,'token-pasted names are not qualified'end
 local code=withoutDirectives(clean)
 local macros={}
 for name in clean:gmatch('#%s*define%s+([%a_][%w_]*)')do macros[name]=true end
 local declarations,names={},{}
 local at=1
 while true do
  local first,last,body=code:find('%f[%w_]uniform%s+([^;{}]+);',at)
  if not first then break end
  local q,kind,name=body:match('^([%w_]+)%s+([%w_]+)%s+([%a_][%w_]*)%s*$')
  if not(q and qualifier[q])then kind,name=body:match('^([%w_]+)%s+([%a_][%w_]*)%s*$')end
  if scalar[kind]and name and not name:match('^love_')and not name:match('^pokeport')then
   if names[name]and names[name]~=kind then return nil,'conflicting uniform kinds'end
   names[name]=kind;declarations[#declarations+1]={first,last}
  end
  at=last+1
 end
 local conditions={};at=1
 while true do
  local first,last=code:find('%f[%w_]if%f[^%w_]%s*%(',at)
  if not first then break end
  local depth,finish=1,last+1
  while finish<=#clean and depth>0 do
   local c=clean:sub(finish,finish)
   if c=='('then depth=depth+1 elseif c==')'then depth=depth-1 end
   finish=finish+1
  end
  if depth~=0 then return nil,'unfinished branch condition'end
  conditions[#conditions+1]={last,finish-1};at=finish
 end
 -- Uniform arithmetic remains dynamic. Reject possible shadow declarations,
 -- member names and macros before substituting any read in an if condition.
 -- Commas may introduce local declarators; retain the conservative guard.
 -- Macro arguments are also unknown: expansion may declare shadow names.
 local pieces,previous={},1
 for _,r in ipairs(declarations)do
  pieces[#pieces+1]=clean:sub(previous,r[1]-1)
  pieces[#pieces+1]=blank(clean:sub(r[1],r[2]));previous=r[2]+1
 end
 pieces[#pieces+1]=clean:sub(previous)
 local outside=table.concat(pieces)
 local used={}
 for _,r in ipairs(conditions)do
  for name in clean:sub(r[1],r[2]):gmatch('%f[%w_][%w_]+%f[^%w_]')do used[name]=true end
 end
 local rejected={};local pos,scanned=1,1
 local parents,macroDepth={},0
 while true do
  local a,b=outside:find('%f[%w_][%w_]+%f[^%w_]',pos);if not a then break end
  for i=scanned,a-1 do
   local char=code:sub(i,i)
   if char=='('then
    local last=i-1;while last>0 and code:sub(last,last):match('%s')do last=last-1 end
    local first=last;while first>0 and code:sub(first,first):match('[%w_]')do first=first-1 end
    local callee=code:sub(first+1,last)
    local row={macro=macros[callee]or false}
    parents[#parents+1]=row;if row.macro then macroDepth=macroDepth+1 end
   elseif char==')'and #parents>0 then
    if parents[#parents].macro then macroDepth=macroDepth-1 end
    parents[#parents]=nil
   end
  end
  scanned=b+1
  local name=outside:sub(a,b)
  if names[name]and not rejected[name]then
   -- Inspect the predecessor of this actual token. Searching an unanchored
   -- word+whitespace pattern rescans every suffix of long GLSL identifiers
   -- for every candidate, even when the candidate is absent there.
   local before=a-1
   while before>0 and outside:sub(before,before):match('%s')do before=before-1 end
   local predecessor=outside:sub(before,before)
   if predecessor:match('[,%.]')or macroDepth>0 or before<a-1 and predecessor:match('[%w_]')
    or code:sub(a,b)~=clean:sub(a,b)then rejected[name]=true end
  end
  pos=b+1
 end
 local order={}
 for name in pairs(names)do
  if rejected[name]then names[name]=nil
  else
   if used[name]then order[#order+1]=name else names[name]=nil end
  end
 end
 table.sort(order)
 return{source=source,clean=clean,kinds=names,order=order,conditions=conditions}
end
function B.literal(kind,value)
 if kind=='bool'and type(value)=='boolean'then return tostring(value)end
 if kind=='float'and type(value)=='number'then
  if value==1 then return'1.0'end
  if value==0 and 1/value==math.huge then return'0.0'end
 end
end
function B.key(plan,values)
 local constants,key={},{}
 for _,name in ipairs(plan.order)do
  local literal=B.literal(plan.kinds[name],values[name])
  if literal then constants[name]=literal;key[#key+1]=name..'='..literal end
 end
 return constants,table.concat(key,';'),#key
end
function B.rewrite(plan,constants)
 local source,pieces,previous=plan.source,{},1
 for _,range in ipairs(plan.conditions)do
  local first,last=range[1],range[2]
  local lexical=plan.clean:sub(first,last);local at=1
  while true do
   local a,b=lexical:find('%f[%w_][%w_]+%f[^%w_]',at);if not a then break end
   local name=lexical:sub(a,b);local value=plan.kinds[name]and constants[name]
   if value then
    assert(value=='0.0'or value=='1.0'or value=='true'or value=='false','unqualified literal')
    local start,finish=first+a-1,first+b-1
    pieces[#pieces+1]=source:sub(previous,start-1);pieces[#pieces+1]=value;previous=finish+1
   end
   at=b+1
  end
 end
 pieces[#pieces+1]=source:sub(previous)
 return table.concat(pieces)
end
return B
