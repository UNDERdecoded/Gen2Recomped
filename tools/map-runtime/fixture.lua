local F={}
function F.new(edition)
 local f=require('tools.map-views.fixture').new(edition)
 local names=require('src.compat.gen1.PairNames')[edition];local a,b
 for _,row in ipairs(names)do
  if not a then a=row elseif row[1]==a[1]and row[2]~=a[2]then b=row;break end
 end
 assert(a and b,'two bank identities required')
 local banks=f.game.data.map_tilesets
 banks.P.address,banks.P.secondary=a[1],false
 banks.S.address,banks.S.secondary=a[2],true
 banks.T.address,banks.T.secondary=b[2],true
 f.pair,f.neighborPair=a[3],b[3]
 return f
end
return F
