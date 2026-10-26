-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Detached tile rectangles and the native menu's actual label/cursor spacing.
local W={CURSOR_WIDTH=require('src.ui.Gen3StartMenu').CURSOR_WIDTH}
function W.template(left,top,width,height,opts)
 return{left=left,top=top,width=width,height=height,tilemapLeft=left,tilemapTop=top,
  w=width,h=height,paletteNum=opts and opts.paletteNum or 15}
end
function W.stdFrame(tpl)
 return require('src.render.Font').drawBox((tpl.left or tpl.tilemapLeft)-1,(tpl.top or tpl.tilemapTop)-1,
  (tpl.width or tpl.w)+2,(tpl.height or tpl.h)+2)
end
return W
