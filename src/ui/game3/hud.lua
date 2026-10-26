-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local H={}
function H.isBusy()return require('src.core.game3.runtime').uiBusy()end
H.busy=H.isBusy
return H
