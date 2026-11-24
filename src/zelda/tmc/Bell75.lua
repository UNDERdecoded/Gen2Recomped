-- Round 75: the festival's bell scene report ("when the man rings the bell Link just walks into walls and freezes")
-- and four script / menu gaps against the decomp.
--
-- CARTRIDGE BEHAVIOUR
--   * script.c WaitForPlayerNormal ($0807F9A4) and WaitForPlayerNormalOrTalkEzlo ($0807FA40) wait only while
--     gPlayerState.framestate is THROW, SWIM, PARACHUTE, FALL, JUMP, C, D, USEPORTAL, F, TRAPPED, 11, DIE,
--     (TALKEZLO: the first one only), CAPE, ITEMGET, DROWN, HOLE, CLIMB, SINKING or STAIRS.  Everything else goes
--     through -- idle / walk, the sword, the Gust Jar, carrying (HOLD), rolling, pushing / pulling -- and neither
--     looks at the message window.
--   * player.c CheckInitPauseMenu: START opens the pause menu only when no fade runs, gPauseMenuOptions.disabled is
--     0 (DisablePauseMenu sets $FF, EnablePauseMenu 0, GameMain_ChangeRoom 0 at every room change), no message is
--     up, health > 0, gSave.inventory[0] holds a sword (none in the festival intro: START does nothing there),
--     gPlayerState.controlMode == CONTROL_ENABLED (SetPlayerIdle / DisablePlayerControl -> CONTROL_DISABLED) and the
--     framestate is not DIE / TALKEZLO / ITEMGET / DROWN / STAIRS.
--   * HandleEntity0x82Actions: an NPC whose script set field_0x82 bit 1 (DoPostScriptAction $0A; $0B clears it)
--     calls sub_0806ED78 every frame -> sub_0800445C: Link is pushed out of its hitbox (when PlayerCanBeMoved).
--     The festival's Pina, Zelda, kids, Percy, Beedle, the guard, the Wind Tribe and the Cloud Tops people do so.
--   * subtaskMapHint.c Subtask_MapHint_1: 60 frames (SFX_103 at 30), then A, B or START closes the map.
-- PORT GAPS FIXED
--   (a) the port's WaitForPlayerNormal waited for state "normal" and no message: Link put into a cutscene while
--       carrying (SetPlayerIdle locks his input, so he never throws) waited for ever; the OrTalkEzlo copy listed
--       state names the port never uses (swimming, falling ... are player fields), so it never waited.
--   (b) menuDisabled was set and cleared but never read; START opened the pause menu inside cutscenes (Link idle,
--       no sword yet) -- now CheckInitPauseMenu's gates.  Cleared on every room change (GameMain_ChangeRoom).
--   (c) field82 bit 2 was kept but never acted on: scripted NPCs that the cartridge makes solid could be walked
--       through.  Now pushed out like the unscripted solid NPCs (Hitboxes.pushOut, its own busy states).
--   (d) the map hint closed only with START (as the pause menu); now A / B / START after its 60 frames.
local bit = require("bit")
local band = bit.band

local M = {}

-- framestates WaitForPlayerNormal waits on, as the port keeps them
local BUSY_STATE = { itemget = true, dead = true, portal = true, throw = true, ext = true }

-- the cartridge's busy framestates (true = wait); ezlo = count Ezlo's talk (PL_STATE_TALKEZLO)
function M.busy(f, ezlo)
  local p = f.player
  if not p then return false end
  local st = p.state or "normal"
  if BUSY_STATE[st] then return true end
  if p.swimming or p.falling or p.jumping or p.climbing or p.para or p.inHole42 then return true end
  if (p.z or 0) > 0 and st ~= "hurt" then return true end -- in the air (PL_STATE_JUMP)
  local ok, pending = pcall(function() return require("src.zelda.tmc.ItemGet").pending(f) end)
  if ok and pending then return true end -- PL_STATE_ITEMGET lasts through the item's message
  if ezlo and f.textbox and f.textKind == "ezlo" then return true end
  return false
end

local Native = require("src.zelda.tmc.Native")
local N = Native.N
N[0x0807F9A4] = function(f, e, ctx, a)                   -- WaitForPlayerNormal
  if M.busy(f, true) then a.commandSize = 0 else a.flags = bit.bor(a.flags, 1) end
end
N[0x0807FA40] = function(f, e, ctx, a)                   -- WaitForPlayerNormalOrTalkEzlo
  if M.busy(f, false) then a.commandSize = 0 else a.flags = bit.bor(a.flags, 1) end
end

-- items 1 .. 6: the swords (gSave.inventory[0]'s Smith's / White swords; the later ones keep it set)
function M.hasSword(f)
  for id = 1, 6 do if f:inventory(id) ~= 0 then return true end end
  return false
end

-- CheckInitPauseMenu's gates besides START and the framestate (Field:update already wants "normal" and no message)
function M.pauseBlocked(f)
  if f.menuDisabled then return true end
  if f.player and f.player.control == false then return true end
  if f.playerScript or f.playerMacro then return true end
  if (f.fadeLevel or 0) ~= (f.fadeTarget or 0) then return true end
  local st = f.save and f.save.stats
  if st and (st.health or 1) <= 0 then return true end
  if not M.hasSword(f) then return true end
  return false
end

-- GameMain_ChangeRoom: gPauseMenuOptions.disabled = 0
function M.roomChange(f) f.menuDisabled = nil end

-- HandleEntity0x82Actions bit 1 for NPCs the solid list leaves out (scripted ones)
function M.push82(f, HB)
  for _, e in ipairs(f.entities) do
    if e.kind == 7 and e.script and band(e.field82 or 0, 2) ~= 0 and not e.hidden and not e.deleted
       and not e.unplaced and e.def and not e.noHitbox and not (HB.SOLID_NPC[e.id] and HB.SCRIPTED_PUSH[e.id]) then
      HB.pushOut(f, e, HB.npc(f, e))
    end
  end
end

-- Subtask_MapHint_1 on the port's world-map page: true while the hint owns the menu
M.HINT_FRAMES = 60
function M.mapHintFrame(menu, input)
  if not menu.mapHint then return false end
  if menu.mapHint > 0 then menu.mapHint = menu.mapHint - 1; return true end
  if input.pressed("a") or input.pressed("b") or input.pressed("start") then
    menu.mapHint = nil
    menu:toggle()
  end
  return true
end

return M
