local P={}
function P.describe(service)
 local p=service.progress or {}
 local total=tonumber(p.total) or 0
 local done=math.max(0,tonumber(p.done) or 0)
 local fraction=total>0 and math.min(1,done/total) or nil
 local detail
 if p.unit=="bytes"then
  detail=string.format("%.1f MB",done/1048576)
  if total>0 then detail=detail..string.format(" / %.1f MB",total/1048576)end
 elseif total>0 and p.unit=="segments"then
  detail=string.format("%d / %d text segments",done,total)
 end
 if fraction then detail=string.format("%d%%",math.floor(fraction*100))..(detail and (" · "..detail) or "")end
 return fraction,detail,service.message or "Choose a language to begin translation"
end
return P
