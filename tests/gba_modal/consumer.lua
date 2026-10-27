-- One unchanged consumer runs against both actual native implementations.
return function(T,S)
 local out={};local clears=0;S.onClear(function()clears=clears+1 end)
 S.clear();T.eq(S.depth(),0,'empty modal depth');T.eq(S.top(),nil,'empty modal top');T.eq(S.busy(),false,'empty modal busy');T.eq(S.pop(),false,'empty pop');T.eq(clears,1,'empty clear dispatches callback')
 local first={isMenu=true};local second={};S.push('first',first,{hideBelow=false})
 T.eq(S.top().mod,first,'native widget identity');T.eq(S.top().isMenu,true,'native menu marker');T.eq(S.depth(),1,'first layer depth');T.eq(S.busy(),true,'native modal blocks field')
 S.push('second',second)
 T.eq(S.depth(),2,'nested native depth');T.eq(S.has('first'),true,'lower native layer exists');T.eq(S.top().mod,second,'top native widget');T.eq(S.top().isMenu,false,'nonmenu marker')
 T.eq(#S.drawOrder(),1,'hideBelow default');T.eq(S.drawOrder()[1].id,'second','visible top');T.eq(S.fullscreen(),false,'hideBelow does not imply fullscreen')
 local top=S.top();top.drawUnder=true;T.eq(#S.drawOrder(),2,'retained lower layer');top.fullscreen=function()return true end;T.eq(S.fullscreen(),true,'live fullscreen predicate');top.fullscreen=false
 local lease=S._layers;S._layers={};T.eq(S.depth(),0,'native preview suspension');T.eq(clears,1,'suspension does not clear native owners');T.eq(#lease,2,'original lease retained')
 S.push('preview',{}, {fullscreen=true,isMenu=true});T.eq(S.fullscreen(),true,'preview fullscreen');T.eq(S.pop('preview'),true,'preview closes');S._layers=lease
 T.eq(S.top(),top,'restored exact native layer');T.eq(S.top().mod,second,'restored native widget');T.eq(clears,1,'restoration does not clear native owners')
 S.push('first',first,{isMenu=false,hideBelow=false});T.eq(S.depth(),2,'reopen replaces same id');T.eq(S.top().isMenu,false,'explicit native menu override')
 T.eq(S.pop('second'),true,'targeted native pop');T.eq(S.top().id,'first','targeted pop preserves top');T.eq(S.pop('absent'),false,'missing named pop');T.eq(S.depth(),1,'missing pop leaves depth')
 S.clear();T.eq(clears,2,'native clear once');T.eq(S.busy(),false,'native clear retires modal state');T.eq(#S.drawOrder(),0,'clear releases visible list');T.eq(S.fullscreen(),false,'clear releases fullscreen state')
 for _,key in ipairs{'push','pop','clear','top','has','busy','fullscreen','drawOrder','depth','onClear'}do T.eq(type(S[key]),'function','native operation '..key)end
 out.callbacks=clears;out.finalDepth=S.depth();out.finalBusy=S.busy();out.operations=10
 return out
end
