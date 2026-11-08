-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TV / CAST: WHAT A SECOND DISPLAY IS FOR.
--
-- Reported from play: "when screen casting their phone over WiFi to the TV
-- it's showing the bottom screen of the dual screen mode instead of streaming
-- the main launcher and game to their TV ... we need an option to switch the
-- screencast mode from bottom screen, top screen or mirror."
--
-- Android hands a Miracast / Smart View / Chromecast mirroring sink to an app
-- as a presentation display -- the same kind of display the AYN Thor's lower
-- panel is -- and the Android host (mobile/second-display/SecondDisplayHost
-- .java) used to put the DS bottom screen on any such display. Putting
-- anything there replaces Android's own mirror, so the TV lost the game.
--
--   MIRROR  the TV shows exactly what the phone shows.  The host puts nothing
--           on it and does not report it as a panel, so Android's mirroring
--           shows through and no bottom screen or launcher panel goes there.
--   BOTTOM  the DS bottom screen on the display, the top screen on the phone:
--           what the Thor's lower panel has always done.
--   TOP     the main picture (game or launcher) on the display, sent down-
--           scaled by src/render/CastTop.lua; the phone shows the bottom
--           screen full-window and takes its taps.  With no bottom screen
--           (Gen 1-3, the launcher) the phone keeps the normal picture.
--
-- WHERE IT IS KEPT: second_display/mode.txt, the file the host reads.  Not
-- options.lua: that file travels with saves (portable folders, cloud sync),
-- and a choice about THIS phone's TV must not follow a save onto the handheld.
-- It is also the one place both ends already share, so there is no second
-- copy to drift.
--
-- NEVER SET is its own answer, and it depends on what the host found: a
-- built-in second panel keeps BOTTOM (the Thor must not regress), an external
-- or cast display gets MIRROR.  The host applies the same rule to a missing
-- mode.txt, so an old Lua talking to this host behaves the same way.

local Transport = require("src.render.SecondScreen")

local CastDisplay = {}

CastDisplay.MODES = { "mirror", "bottom", "top" }
CastDisplay.LABELS = { mirror = "MIRROR", bottom = "BOTTOM", top = "TOP" }
CastDisplay.ROW_LABEL = "TV / CAST"

-- Swappable for the check tool.
CastDisplay._transport = Transport

local cached, cachedRead = nil, false

-- The stored choice, or nil when the player has never made one.
function CastDisplay.setting()
  if not cachedRead then
    local T = CastDisplay._transport
    local ok, m = pcall(function() return T.readCastMode and T.readCastMode() end)
    cached = ok and m or nil
    cachedRead = true
  end
  return cached
end

function CastDisplay.forget()
  cached, cachedRead = nil, false
end

-- Does the host here understand the option?  Only an Android host that
-- writes the cast fields reads mode.txt; everywhere else (desktop, iOS, an
-- older APK) there is nothing for the row to change, so it is not shown.
function CastDisplay.supported()
  local T = CastDisplay._transport
  local ok, yes = pcall(function() return T.castSupported and T.castSupported() end)
  return (ok and yes) and true or false
end

-- none | builtin | external
function CastDisplay.kind()
  local T = CastDisplay._transport
  local ok, k = pcall(function() return T.hostKind and T.hostKind() end)
  return (ok and k) or "none"
end

-- The never-set answer for a kind of display.  With nothing attached the next
-- display is far likelier to be a TV than a panel that was not there at boot.
function CastDisplay.default(kind)
  if (kind or CastDisplay.kind()) == "builtin" then return "bottom" end
  return "mirror"
end

function CastDisplay.effective()
  return CastDisplay.setting() or CastDisplay.default()
end

function CastDisplay.label(mode)
  return CastDisplay.LABELS[mode or CastDisplay.effective()] or "MIRROR"
end

function CastDisplay.set(mode)
  local valid = false
  for _, m in ipairs(CastDisplay.MODES) do if m == mode then valid = true end end
  if not valid then mode = nil end
  local T = CastDisplay._transport
  local ok = pcall(function() return T.writeCastMode(mode) end)
  cached, cachedRead = mode, true
  -- the panel-or-not answer changes with this; do not wait out a probe
  pcall(function() if T.forget then T.forget() end end)
  return ok
end

-- One step through MIRROR -> BOTTOM -> TOP, either way.  From never-set it
-- starts at the default it was showing, so the first press always changes
-- what the row says.
function CastDisplay.step(dir)
  local current = CastDisplay.effective()
  local at = 1
  for i, m in ipairs(CastDisplay.MODES) do if m == current then at = i end end
  local by = (tonumber(dir) or 1) < 0 and -1 or 1
  local nextMode = CastDisplay.MODES[(at - 1 + by) % #CastDisplay.MODES + 1]
  CastDisplay.set(nextMode)
  return nextMode
end

-- A one-line explanation for the launcher's settings page.
function CastDisplay.note()
  local kind = CastDisplay.kind()
  local found = (kind == "builtin" and "Second screen found: built-in panel.")
    or (kind == "external" and "Second screen found: TV / cast display.")
    or "No second screen right now."
  return found .. " MIRROR shows the phone's own picture on the TV. BOTTOM puts"
    .. " the DS bottom screen there. TOP sends the game to the TV and keeps the"
    .. " bottom screen on the phone."
end

return CastDisplay
