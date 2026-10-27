-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local C={}
function C.dialogueWindow()
  local b=require('src.ui.Theme').textBox
  return b.tx,b.ty,b.tw,b.th
end
return C
