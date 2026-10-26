-- The same constructor/mutator consumer executes on both actual engines.
return function(T,L)
 local data={width=3,height=2,trueWidth=2,trueHeight=2,borderWidth=2,borderHeight=2,borderMids={11,12,13,14},cells={
  {mid=1,coll=0,elev=3},{mid=2,coll=1,elev=4},{mid=3,coll=2,elev=0},
  {mid=4,coll=3,elev=15},{mid=5,coll=0,elev=0},{mid=6,coll=1,elev=1}}}
 local l=L.fromDecoded(data,'MAP_TEST','PAIR_TEST');local out={}
 T.eq(l.cells,data.cells,'actual decoded base-cell owner identity')
 T.eq(l.mapId,'MAP_TEST','native map identity');T.eq(l.pair,'PAIR_TEST','native graphics pair')
 T.eq(l.width,3,'source row stride');T.eq(l.trueWidth,2,'cropped width')
 T.eq(l:cellAt(1,0),data.cells[2],'unpatched decoded cell retains original identity')
 T.eq(l:workerPacked(),nil,'mutable authored source has no packed fast path')
 T.same(l:cellAt(1,0),{mid=2,coll=1,elev=4},'source native cell triple')
 T.eq(l:midAt(1,0),2,'artwork query');T.eq(l:collAt(0,1),3,'blocking query');T.eq(l:elevAt(0,1),15,'bridge query')
 T.same(l:cellAt(2,0),{mid=11,coll=255,elev=0},'padded column reads tiled border')
 T.same(l:cellAt(-1,-1),{mid=14,coll=255,elev=0},'negative coordinates tile border')
 T.same(l:collArray(),{0,1,255,3,0,255},'native collision binding crops padded column')
 l:applyOverride(0,0,20,0,0)
 T.same(l:cellAt(0,0),{mid=20,coll=0,elev=0},'native explicit zero override');T.eq(l._revision,1,'one native override revision')
 T.eq(l.overrides[0].mid,20,'native override projection is current')
 l:applyOverride(-1,-1,21)
 T.same(l:cellAt(-1,-1),{mid=21,coll=255,elev=0},'actual authored border override')
 T.eq(l._revision,2,'border override has one native revision')
 T.eq(l:setMetatiles{{x=1,y=0,mid=22},{x=1,y=0,coll=0,elev=0},{x=2,y=0,mid=23,coll=1,elev=2}},3,'native batched row count')
 T.same(l:cellAt(1,0),{mid=22,coll=0,elev=0},'repeated native rows preserve prior fields')
 T.same(l:cellAt(2,0),{mid=23,coll=1,elev=2},'override precedes padded border sampling')
 T.same(l:collArray(),{0,0,255,3,0,255},'padded collision stays outside true map')
 T.eq(l._revision,3,'one native revision for complete batch')
 T.eq(l:setMetatiles({}),0,'empty batch');T.eq(l._revision,3,'empty batch cannot advance native revision')
 local src={width=2,height=1,cells={{mid=30,coll=0,elev=15},{mid=31,coll=1,elev=0}}}
 T.eq(l:stamp(src,0,1),2,'native stamp counts actual source cells')
 T.same(l:cellAt(0,1),src.cells[1],'stamp writes actual bridge cell');T.same(l:cellAt(1,1),src.cells[2],'stamp writes actual blocked cell')
 T.eq(l._revision,4,'one native revision for complete stamp')
 T.eq(l:stamp({},0,0),0,'missing source does not stamp')
 out.beforeClear={l:cellAt(0,0),l:cellAt(1,0),l:cellAt(0,1),l:cellAt(-1,-1)}
 l:clearOverrides();T.eq(l._revision,5,'clear advances changed native state once')
 T.same(l:cellAt(0,0),data.cells[1],'clear restores actual base cell')
 T.same(l:cellAt(-1,-1),{mid=14,coll=255,elev=0},'clear restores tiled border')
 T.eq(next(l.overrides),nil,'clear retires all native overrides')
 l:clearOverrides();T.eq(l._revision,5,'empty clear does not change revision')
 local old=l.cellAt;l.cellAt=function(self,x,y)local c=old(self,x,y);return {mid=c.mid+100,coll=c.coll,elev=c.elev}end
 T.eq(l:midAt(0,0),101,'custom cell reader controls scalar artwork')
 T.eq(l:collAt(0,0),0,'custom reader retains native collision')
 T.eq(l:elevAt(0,0),3,'custom reader retains native height');T.eq(l:workerPacked(),nil,'custom cell readers do not claim immutable packed input')
 local collReader=l.cellAt;l.cellAt=function(self,x,y)local c=collReader(self,x,y);c.coll=99;return c end
 T.same(l:collArray(),{0,1,255,3,0,255},'collision binding uses actual grid rather than a custom rendering reader')
 l.cellAt=nil
 local function u16(n)return string.char(n%256,math.floor(n/256))end
 local bytes={'SVML',string.char(1,0),u16(3),u16(2),u16(2),u16(2),string.char(2,2)}
 for _,n in ipairs(data.borderMids)do bytes[#bytes+1]=u16(n)end
 for _,c in ipairs(data.cells)do bytes[#bytes+1]=u16(c.mid)..string.char(c.coll,c.elev)end
 local blob=table.concat(bytes)
 local p=L.fromDecoded(data,'PACKED','PAIR_TEST',blob)
 p:setMetatiles{{x=0,y=0,mid=32,coll=0,elev=15},{x=-1,y=0,mid=33}}
 local packed=p:workerPacked();T.check(packed~=nil,'actual supplied immutable packed source is available')
 if packed then
  T.eq(packed.blob,blob,'worker receives exact original immutable source bytes')
  T.eq(packed.off,25,'worker offset includes actual packed border dimensions')
  T.eq(packed.width,3,'worker source stride');T.eq(packed.trueWidth,2,'worker cropped width');T.eq(packed.trueHeight,2,'worker cropped height')
  T.same(packed.borderMids,{11,12,13,14},'worker border values')
  T.same(packed.overrides[0],{mid=32},'worker artwork patch excludes live movement metadata')
  T.same(packed.overrides[-1],{mid=33},'worker preserves authored border patch')
  packed.overrides[0].mid=999;packed.borderMids[1]=999
  T.eq(p:midAt(0,0),32,'worker receives detached COW artwork')
  T.eq(p.borderMids[1],11,'worker receives detached border values')
 end
 local previousAssets=package.loaded['src.render.Assets']
 package.loaded['src.render.Assets']={loader={overrideOrder=function()return {'active_asset'}end}}
 T.eq(p:workerPacked(),nil,'live asset overrides decline immutable worker path')
 package.loaded['src.render.Assets']=previousAssets
 p.trueWidth=1;T.eq(p:workerPacked(),nil,'changed crop declines immutable worker path');p.trueWidth=2
 p.cells={};T.eq(p:workerPacked(),nil,'replaced base source declines immutable worker path');p.cells=data.cells
 p.midAt=function()return 900 end;T.eq(p:workerPacked(),nil,'custom metatile reader declines immutable worker path');p.midAt=nil
 out.packed={blob=blob,mid=p:midAt(0,0),border=p:midAt(-1,0),stride=p.width}
 out.afterClear={l:cellAt(0,0),l:cellAt(-1,-1),l:collArray()};out.revision=l._revision
 return out
end
