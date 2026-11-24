-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CONTROL MODES and START (input round, 2026-11-18).
--
-- Reported from play: "I have to click the right bumper to use what should be
-- set to A". The port reads the action (lift, talk, open, read, dash) from R
-- and the item from A, which is the GBA cartridge's control mode 0
-- (round 18, Items.lua). The cartridge has more than one mode: its button
-- builder 0x0806995C switches on the byte at +0x548 (RAM 0x03002778):
--
--   mode 0  item = A (+0x53E new / +0x538 held), action = R (+0x53F / +0x539)
--   mode 1  item = R,                          action = A
--   mode 2  item = A,                          action = A + B together
--
-- (mode 1 is what 0x08069D00 writes, called from the restart routine
-- 0x08068D60.) Mode 0 is what the cartridge's messages name ("press R to
-- lift", glyph 0x5B), so it stays the cartridge's own; mode 1 is the layout a
-- Pokemon / SNES player expects and is the default in the app: A talks,
-- lifts, opens and dashes, R uses the chosen item, B is the sword, L the map.
-- The system menu's CONTROLS row switches between the two
-- (Host:gameOption "controls" = "a" | "r"); in mode 1 the messages' A / R
-- glyphs swap so the hints name the button that does it.
--
-- Only the item / action bytes change, exactly as on the cartridge: the menus
-- (item menu, maps, text, file select) still read the raw A / B buttons.
--
-- START. The GBA swaps the SNES START and SELECT (0x08069AA8: GBA SELECT (4)
-- feeds the SNES START bit 0x10, GBA START (8) the SNES SELECT bit 0x20), so
-- GBA SELECT opens the item menu (0x0806CE54) and GBA START the SNES SELECT's
-- save / quit dialogue. That dialogue is the runtime's system menu here
-- (RESUME, SAVE GAME, OPTIONS, QUIT TO LAUNCHER), so START in play opens it --
-- which is also what START does in the Pokemon games (their START menu holds
-- SAVE / OPTION / QUIT).

local C = {}

C.DEFAULT_APP = "a"     -- the runtime: A is the action (cartridge mode 1)
C.DEFAULT_BARE = "r"    -- tests / harnesses without a host: cartridge mode 0

local function host(self) return self.opts and self.opts.host end

-- "a": action on A, item on R (mode 1); "r": action on R, item on A (mode 0)
function C.mode(game)
  if game.ctlMode == nil then
    local h = host(game)
    local v = h and h.gameOption and h:gameOption("controls")
    if v ~= "a" and v ~= "r" then v = game.opts and game.opts.controls end
    if v ~= "a" and v ~= "r" then v = h and C.DEFAULT_APP or C.DEFAULT_BARE end
    game.ctlMode = v
  end
  return game.ctlMode
end

function C.action(game) return C.mode(game) == "a" and "a" or "r" end
function C.item(game) return C.mode(game) == "a" and "r" or "a" end

-- the messages' button glyphs follow the mode (Text.BUTTON: 0x5B R, 0x5E A)
function C.applyGlyphs(game)
  local okT, Text = pcall(require, "src.zelda.alttp.Text")
  local B = okT and Text.BUTTON
  if not B then return end
  if C.mode(game) == "a" then B[0x5B], B[0x5E] = 0x0E, 0x0B else B[0x5B], B[0x5E] = 0x0B, 0x0E end
end

function C.set(game, v)
  game.ctlMode = (v == "a") and "a" or "r"
  local h = host(game)
  if h and h.gameOption then h:gameOption("controls", game.ctlMode) end
  C.applyGlyphs(game)
end

function C.label(game)
  return C.mode(game) == "a" and "A ACTION / R ITEM" or "R ACTION / A ITEM"
end

-- START in play: the cartridge's save / quit dialogue = the system menu
function C.startWanted(game)
  local inp = game.input
  if not (inp and inp.wasPressed and inp.wasPressed("start")) then return false end
  if game.state ~= "play" and game.state ~= "room" then return false end
  if game.scroll or game.gate or game.roomScroll or game.opening or game.dmap then return false end
  if game.exitDoor or (game.exitWalk and game.exitWalk > 0) then return false end
  local h = host(game)
  if not (h and h.openMenu) then return false end
  h:openMenu()
  return true
end

function C.install(G)
  function G:controlMode() return C.mode(self) end
  function G:actionKey() return C.action(self) end
  function G:itemKey() return C.item(self) end

  local upd0 = G.update
  function G:update(...)
    if self.ctlGlyphs ~= C.mode(self) then self.ctlGlyphs = self.ctlMode; C.applyGlyphs(self) end
    return upd0(self, ...)
  end

  local mw0 = G.menuWanted
  function G:menuWanted(...)
    if C.startWanted(self) then return false end
    return mw0(self, ...)
  end

  local mo0 = G.menuOptions
  function G:menuOptions(...)
    local rows = mo0 and mo0(self, ...) or {}
    rows[#rows + 1] = { id = "controls", label = "CONTROLS", value = C.label(self) }
    return rows
  end

  local mopt0 = G.menuOption
  function G:menuOption(id, dir, ...)
    if id == "controls" then return C.set(self, C.mode(self) == "a" and "r" or "a") end
    if mopt0 then return mopt0(self, id, dir, ...) end
  end
end

return C
