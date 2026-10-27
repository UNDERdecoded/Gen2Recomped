return function(layout,kind,environment,connections,warps)
 local a,b,n=1,17,0
 local function value(v)
  local s=tostring(v)..';'
  for i=1,#s do local c=s:byte(i);a=(a*131+c)%2147483647;b=(b*257+c)%2147483629 end
 end
 for _,v in ipairs({layout.width,layout.height,layout.trueWidth,layout.trueHeight,layout.borderWidth,layout.borderHeight,kind,environment})do value(v)end
 for _,mid in ipairs(layout.borderMids)do value(mid)end
 for _,row in ipairs(layout.cells)do n=n+1;value(row.mid);value(row.coll);value(row.elev)end
 for _,row in ipairs(connections or{})do value(row.dir);value(row.map);value(row.offset)end
 for _,row in ipairs(warps or{})do value(row.x);value(row.y);value(row.destMap);value(row.destWarp);value(row.mapGroup);value(row.mapNum)end
 return {hashA=a,hashB=b,cells=n,width=layout.width,height=layout.height,trueWidth=layout.trueWidth,trueHeight=layout.trueHeight}
end
