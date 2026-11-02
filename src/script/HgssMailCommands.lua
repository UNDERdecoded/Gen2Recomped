-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S MAIL COMMANDS (src/pokemon/Gen4Mail.lua):
--
--   ScrCmd_376                  the PC's mailbox (scrcmd_c.c: sub_0203F074 ->
--     overlay 103, ScrNative_WaitApplication_DestroyTaskData) --
--     src/ui/HgssMailbox.lua, the script waiting until it closes
--   ScrCmd_377 <dest>           Mailbox_CountMessages into the var
--   KenyaCheckPartyOrMailbox <dest>  (scrcmd_party.c) TRUE when Kenya's
--     letter is on a party mon holding Mail or in the mailbox (Mail_Compare
--     against NPCTrade_MakeKenyaMail; here the letter's `kenya` mark, or the
--     old `kenyaMail` flag of a mon lent before letters were kept)
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table), after
-- HgssFieldQueries / Gen4ScriptVM's own stand-ins for these (377 -> 0,
-- 376 unlowered), which it replaces.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function setVar(ctx, id, v) G4().setVar(ctx.save, id, v) end

function Commands.g4_hgss_mailbox_count(ctx, destVar)
  local n = 0
  if ctx.game and ctx.save then n = require("src.pokemon.Gen4Mail").count(ctx.game) end
  setVar(ctx, destVar, n)
end

function Commands.g4_hgss_mailbox(ctx)
  local game = ctx.game
  if not (game and game.stack and ctx.save) then return end
  local UI = require("src.ui.HgssMailbox")
  game.stack:push(UI.new(game, function()
    if ctx.runner then ctx.runner:resume() end
  end))
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_mailbox = { foreground = true, blocking = true }

function Commands.g4_hgss_kenya_mail(ctx, destVar)
  local Mail = require("src.pokemon.Gen4Mail")
  local found = false
  for _, m in ipairs((ctx.save and ctx.save.party) or {}) do
    if Mail.isMailItem(m.item) and (m.kenyaMail or (type(m.mail) == "table" and m.mail.kenya)) then found = true end
  end
  if not found and ctx.game then
    for _, e in ipairs(Mail.list(ctx.game)) do
      if e.mail.kenya then found = true end
    end
  end
  setVar(ctx, destVar, found and 1 or 0)
end

function M.install(L)
  L.scrcmd_376 = function(_, st)
    st.out[#st.out + 1] = { "g4_hgss_mailbox" }
  end
  L.scrcmd_377 = function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_mailbox_count", ins.args[1] }
  end
  L.kenyacheckpartyormailbox = function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_kenya_mail", ins.args[1] }
  end
end

return M
