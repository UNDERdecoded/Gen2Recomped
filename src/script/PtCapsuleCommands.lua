-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- `opensealcapsuleeditor` (ScrCmd_156, CapsuleMenu_StartFieldTask) opens
-- Platinum's Ball Capsule app (src/ui/PtCapsuleMenu.lua) when the cache
-- carries its art (gen4_pt_capsule_art, platinum-capsule-app-v1); otherwise
-- the row it lowers onto keeps saying what is missing, as before.

local M = {}

function M.install(L)
  local Commands = require("src.script.Commands")
  if M.installed then return end
  M.installed = true
  local before = Commands.g4_open_seal_capsule_editor
  Commands.g4_open_seal_capsule_editor = function(ctx, ...)
    local App = require("src.ui.PtCapsuleMenu")
    if ctx and ctx.game and App.available(ctx.game) then return App.run(ctx) end
    if before then return before(ctx, ...) end
  end
  Commands.meta = Commands.meta or {}
  Commands.meta.g4_open_seal_capsule_editor = { foreground = true, blocking = true }
end

return M
