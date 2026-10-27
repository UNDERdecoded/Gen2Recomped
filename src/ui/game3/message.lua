-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Dialogue observations and commands over the native printer/stack owner.
local Native=require('src.compat.gen1.NativeSession')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local active,drawBox
local frame='normal'
local function current()
 local g=Native.game();if not(g and g.stack)then return end
 local TextBox=package.loaded['src.render.TextBox'];if not TextBox then return end
 for i=#g.stack.states,1,-1 do
  local state=g.stack.states[i]
  if getmetatable(state)==TextBox then return state end
  if state.isOpaque then return end
 end
end
function M.isOpen()return current()~=nil end
function M.isWaiting()local b=current();return b~=nil and(b.waiting or b.done)end
function M.isTyping()local b=current();return b~=nil and not(b.waiting or b.done)end
function M.isHeld()local b=current();return b~=nil and b.sourceHeld==true end
function M.currentPage()local b=current();return b and table.concat(b.pages[b.pageIndex],'\n')end
function M.setFrame(kind)frame=kind or'normal'end
function M.frameKind()return frame end
function M.show(text,opts)
 opts=opts or{}
 if active and active:valid()then active:retire()end
 local flow,why=require('src.compat.gen1.UiFlow').new(opts.done)
 if not flow then return false,why end
 local b=require('src.render.TextBox').new(flow.game,text,function()flow:finish()end,
  {stay=(opts.stay or opts.hold)and{}or nil,signpost=opts.sign or opts.frame=='sign',
   style=opts.colors,box=opts.box,maxPixels=opts.maxWidth})
 b.sourceHeld=opts.hold==true;b.sourceMessage=true
 active=flow;flow:push(b)
 if tonumber(opts.speed)==0 then b:revealPage()end
 return true
end
function M.showStay(text,opts)
 local copy={};for k,v in pairs(opts or{})do copy[k]=v end;copy.stay=true;return M.show(text,copy)
end
function M.close()
 local b=current();if not(b and b.sourceMessage and b.nativeUiFlow)then return false end
 return b.nativeUiFlow:finish()
end
function M.closeStay()local b=current();if b and b.stay then return M.close()end;return false end
function M.skipReveal()local b=current();if b then b:revealPage();return true end;return false end
function M.advance()
 local b=current();if not b or b.sourceHeld then return false end
 if not(b.waiting or b.done)then b:revealPage()else b:advance()end
 return true
end
M.pressAB=M.advance
function M.reset()if active then active:retire();active=nil end end
function M.tick()return Boundary.invoke('message.update')end
function M.draw()return Boundary.invoke('message.draw')end
M.drawText=M.draw
function M._draw(box,body)
 local previous=drawBox;drawBox=box
 local ok,result=require('src.render.GraphicsScope').call(function()
  return Boundary.dispatch('message.draw',body,function()return Call.call(M,'draw')end)
 end)
 drawBox=previous;if not ok then error(result,0)end;return result
end
function M._update(box,body)
 return Boundary.dispatch('message.update',body,function()return Call.call(M,'tick')end)
end
return M
