-- Control codes and substitutions are literal segments, never model input.
local P={}
function P.build(strings,terms)
 local texts,index,entries={},{},{}
 local function plain(text)
  local prefix,body,suffix=text:match("^(%s*)(.-)(%s*)$")
  if not body or body=="" then return {literal=text} end
  local n=index[body]
  if not n then n=#texts+1;index[body]=n;texts[n]=body end
  return {index=n,prefix=prefix,suffix=suffix}
 end
 local byFirst={}
 for term,localized in pairs(terms or {})do
  local key=term:upper()
  if #key>=3 then
   local first=key:sub(1,1)
   byFirst[first]=byFirst[first] or {}
   byFirst[first][#byFirst[first]+1]={key=key,value=localized}
  end
 end
 for _,list in pairs(byFirst)do table.sort(list,function(a,b)return #a.key>#b.key end)end
 local function addSegment(parts,segment)
  local upper=segment:upper()
  local start,at=1,1
  local fragments,replacements={},{}
  while at<=#segment do
   local hit
   if at==1 or not upper:sub(at-1,at-1):match("[%w]")then
    for _,entry in ipairs(byFirst[upper:sub(at,at)] or {})do
     local finish=at+#entry.key-1
     if upper:sub(at,finish)==entry.key and (finish==#upper or not upper:sub(finish+1,finish+1):match("[%w]"))then hit=entry;break end
    end
   end
   if hit then
    fragments[#fragments+1]=segment:sub(start,at-1)
    local marker="[ZX"..string.format("%04d",#replacements+1).."]"
    fragments[#fragments+1]=marker
    replacements[#replacements+1]={marker=marker,value=hit.value}
    at=at+#hit.key;start=at
   else at=at+1 end
  end
  fragments[#fragments+1]=segment:sub(start)
  local part=plain(table.concat(fragments))
  part.replacements=replacements;part.original=segment
  if #replacements>0 then
   local preferred=table.concat(fragments)
   for _,replacement in ipairs(replacements)do
    local first,last=preferred:find(replacement.marker,1,true)
    preferred=preferred:sub(1,first-1)..replacement.value..preferred:sub(last+1)
   end
   part.preferred=plain(preferred)
  end
  parts[#parts+1]=part
 end
 for _,source in ipairs(strings)do
  local parts={}
  local i=1
  while i<=#source do
   local a,b=source:find("{[^}]*}",i)
   local na,nb=source:find("[\n\r\f\v]",i)
   local fa,fb=source:find("%%[-+ #0]*%d*%.?%d*[cdeEfgGiouXxsq%%]",i)
   if na and (not a or na<a)then a,b=na,nb end
   if fa and (not a or fa<a)then a,b=fa,fb end
   local segment=source:sub(i,a and a-1 or #source)
   -- Established localized names are protected from machine translation.
   if terms and terms[segment] then parts[#parts+1]={literal=terms[segment]}
   elseif #segment>0 then addSegment(parts,segment) end
   if a then parts[#parts+1]={literal=source:sub(a,b)};i=b+1 else break end
  end
  entries[#entries+1]={source=source,parts=parts}
 end
 return {texts=texts,entries=entries}
end
function P.finish(plan,translations,allowFallback)
 assert(#translations==#plan.texts,"Translation response is incomplete")
 local catalog={}
 local fallback=0
 for _,entry in ipairs(plan.entries)do
  local function assemble()
  local out={}
  for _,part in ipairs(entry.parts)do
   if part.literal then out[#out+1]=part.literal
   else
    local text=assert(translations[part.index],"Missing translated segment")
    assert(type(text)=="string" and not text:find("[{}\f\v]"),"Model introduced a control token")
    local native=part.preferred and translations[part.preferred.index]
    local useNative=type(native)=="string" and not native:find("[{}\f\v]")
    for _,replacement in ipairs(part.replacements or {})do
      if not native or not native:find(replacement.value,1,true)then useNative=false end
    end
    if useNative then text=native end
    for _,replacement in ipairs(useNative and {} or part.replacements or {})do
      local first,last=text:find(replacement.marker,1,true)
      assert(first and not text:find(replacement.marker,last+1,true),"Model changed a protected term")
      text=text:sub(1,first-1)..replacement.value..text:sub(last+1)
    end
    out[#out+1]=part.prefix..text..part.suffix
   end
  end
  return table.concat(out)
  end
  local ok,result=pcall(assemble)
  if ok then catalog[entry.source]=result
  elseif allowFallback then catalog[entry.source]=entry.source;fallback=fallback+1
  else error(result) end
 end
 return catalog,fallback
end
return P
