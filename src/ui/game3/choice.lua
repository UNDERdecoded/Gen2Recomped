-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local C={}
local active
function C.isOpen()return active~=nil and active:valid()end
function C.multi(options,defaultIdx,callback,layout)
 if C.isOpen()then return false end
 local flow,why=require('src.compat.gen1.UiFlow').new(callback)
 if not flow then return false,why end
 local state=require('src.ui.MultiChoice').new(flow.game,options,defaultIdx,function(index)flow:finish(index)end,layout)
 active=flow;flow:push(state);return true
end
return C
