-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Immediate-mode widget kit for the save editor, drawn in the launcher's
-- visual language (see Theme.lua and SaveEditor.dc.html).
--
-- Call Kit.beginFrame(mx, my, clicked, wheel) once per love.draw() before any
-- widget and Kit.endFrame() after the last one; widgets read the frame's mouse
-- state to decide hover / click, and endFrame retires the text-input queue so a
-- keystroke is never applied twice.  The wheel notches accumulated since the
-- last frame arrive the same way and are retired the same way: an unclaimed
-- notch dies with the frame rather than scrolling something later (#595).
--
-- Hit testing is a plain rect with no z-order, so panels must draw
-- overlapping controls in dispatch order and every target is >= 26px tall
-- (rule 6 of the design spec) -- that sizing is the whole accessibility story
-- here.

local Theme = require("Theme")
local PAL = Theme.PAL

local Kit = {}
Kit.mouseX, Kit.mouseY = 0, 0
Kit.mouseClicked = false  -- left button pressed this frame
Kit.wheelY = 0            -- wheel notches queued since the last frame (#595)
Kit.focus = nil           -- id of the text field receiving keystrokes
Kit.time = 0
Kit.fonts = {}
Kit.scale = 1

local G = love and love.graphics or nil
local edits = {}          -- queued textinput / backspace since the last frame
-- Per-field caret / selection / scroll for Kit.textarea. Declared up here
-- because Kit.blur drops a field's state when it loses focus, and blur is
-- defined long before the widget is.
local areaState = {}
local kbField = nil       -- id of the field the OS soft keyboard is raised for

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is
-- active, and that call is what raises the Android/iOS soft keyboard; the
-- rect keeps the focused field visible above it.  Desktop has text input on
-- by default and the launcher hosting this editor depends on that -- the
-- launcher's own fields (slot rename #205, mod index prompt, find search)
-- follow the same rule since #578: arm on open, lower only on mobile -- so
-- neither side ever turns desktop text input off, since setTextInput is
-- global SDL state, not per-widget (#529).
-- Does this platform raise a keyboard of its OWN when text input is armed,
-- rather than having a physical one always available?
--
-- The name was `mobile` and the test was Android-or-iOS, which quietly
-- meant "the Switch is a desktop". It is not: love-nx has no physical
-- keyboard and arms the system keyboard APPLET, so it belongs on this side
-- of the line and nothing here ever lowered text input for it. That left
-- SDL text input started forever after the first field, and since
-- setTextInput(true) into an already-started state is a no-op, the applet
-- could never be raised a second time -- one search per session.
--
-- Asked as a capability rather than by listing devices, so the next console
-- port is not a fourth name to remember.
local function softKeyboardPlatform()
  local ok, Platform = pcall(require, "src.core.Platform")
  if ok and type(Platform) == "table" and type(Platform.isNX) == "function" then
    local okNX, isNX = pcall(Platform.isNX)
    if okNX and isNX then return true end
  end
  local osName = love and love.system and love.system.getOS
    and love.system.getOS()
  return osName == "Android" or osName == "iOS" or osName == "NX"
end

local function syncSoftKeyboard(id, x, y, w, h)
  if not (love and love.keyboard and love.keyboard.setTextInput) then return end
  if id then
    if kbField ~= id then
      kbField = id
      love.keyboard.setTextInput(true, math.floor(x), math.floor(y),
        math.ceil(w), math.ceil(h))
    end
  elseif kbField then
    kbField = nil
    if softKeyboardPlatform() then love.keyboard.setTextInput(false) end
  end
end

local function canPrintf()
  return G and type(G.printf) == "function"
end

function Kit.beginFrame(mx, my, clicked, wheel)
  Kit.mouseX, Kit.mouseY = mx, my
  Kit.mouseClicked = clicked
  Kit.wheelY = wheel or 0
  -- Counted so a modal can tell "the frame I went up" from "a frame later".
  -- See Kit.tapAway.
  Kit.frame = (Kit.frame or 0) + 1
  -- Nothing has claimed this frame's click for typing yet. See endFrame.
  Kit._fieldTookClick = false
  if love and love.timer and love.timer.getTime then
    Kit.time = love.timer.getTime()
  end
end

-- Retire this frame's keystrokes.  Anything typed while no field had focus is
-- dropped here rather than replayed into the next field that gets clicked.
-- A wheel notch no list claimed retires with them, for the same reason.
function Kit.endFrame()
  -- A CLICK THAT NO FIELD TOOK ENDS TYPING.
  --
  -- Focus was only ever dropped by pressing Return, Escape, or another field.
  -- So after typing a map name into the search box, clicking the viewport left
  -- the caret exactly where it was -- and every key after that went into the
  -- box. W, A, S and D moved nothing and typed "wasd" into the search
  -- instead, which reads as the map not responding to the keyboard at all.
  --
  -- Decided HERE rather than in the viewport, because the viewport is not
  -- special: pressing a button, a list row, a swatch, or empty card space all
  -- mean the reader has moved on. The one thing that should keep focus is
  -- another text field, and a field says so by claiming the click.
  --
  -- After the frame, because the claim can only be known once every widget
  -- that could make it has been drawn.
  if Kit.mouseClicked and Kit.focus and not Kit._fieldTookClick then
    Kit.blur()
  end
  for i = #edits, 1, -1 do edits[i] = nil end
  Kit.wheelY = 0
end

-- Rebuild the font set when the window size changes.  `s` matched the
-- launcher's height/768 scale alone until #497: a phone in portrait
-- (720x1560) is TALLER than the desktop reference and barely half as wide, so
-- a height-only scale drew a 1.6x desktop layout into a 720px window and every
-- right-aligned cluster in the chrome landed on top of the block to its left.
-- The layout needs roughly 1000 logical px of width, so the window now pays
-- for both axes.  Every desktop and landscape size still lands on the height
-- term, which is why they stay pixel-identical to before.
function Kit.layout(width, height)
  local s = Theme.clamp(math.min(width / 1000, height / 768), 0.62, 1.6)
  local key = ("%dx%d"):format(width, height)
  if Kit._fontKey ~= key then
    Kit._fontKey = key
    Kit.fonts = Theme.fonts(s)
  end
  Kit.scale = s
  return s
end

-- ------------------------------------------------------------ input plumbing
-- App forwards love.textinput / love.keypressed here so Kit.textfield can be a
-- real editable field.  Events arrive before draw, so they queue and the
-- focused field drains them while it renders.
function Kit.textinput(text)
  if not Kit.focus then return false end
  edits[#edits + 1] = text
  return true
end

-- Returns true when the key was consumed by the focused field, so App can
-- leave its own shortcuts alone while the user is typing.
-- Empty the focused field.
--
-- Backspace cannot be reached on a device with no keyboard: the editor's
-- only pad path is App.gamepadpressed, which maps A/B/start/select/
-- shoulders/dpad and has no delete verb, and B is already "back". So the
-- field could only ever GROW, and the only way out was to close the
-- editor -- which is exactly what was reported. A queued sentinel rather
-- than a direct write because the value lives with the caller and is only
-- handed to Kit for the frame it is drawn in.
function Kit.clearField()
  if not Kit.focus then return false end
  edits[#edits + 1] = "\f"
  return true
end

-- The keys a MULTI-LINE field claims that a single-line one does not.
--
-- Queued as tables beside the plain-string edits rather than instead of them:
-- `Kit.textfield` walks this list and only understands strings, and rewriting
-- every field in the editor to teach it a second shape would be a large change
-- to fix a small one. A string is a character or one of the three sentinels; a
-- table is a named key with its modifiers, and a reader that does not know what
-- that means skips it.
local NAV_KEYS = {
  left = true, right = true, up = true, down = true,
  home = true, ["end"] = true, pageup = true, pagedown = true,
  delete = true, backspace = true, tab = true,
}

function Kit.keypressed(key)
  if not Kit.focus then return false end
  local ctrl = false
  if love and love.keyboard and love.keyboard.isDown then
    ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  end
  local shift = false
  if love and love.keyboard and love.keyboard.isDown then
    shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  end

  -- The structured form first, for whoever wants it.
  if NAV_KEYS[key] or ctrl then
    edits[#edits + 1] = { key = key, ctrl = ctrl, shift = shift }
  end

  if key == "backspace" then
    edits[#edits + 1] = "\b"
    return true
  elseif key == "return" or key == "kpenter" then
    -- A MULTI-LINE FIELD KEEPS RETURN. Enter in a one-line box means "done";
    -- in a paragraph of dialogue it means a new line, and blurring the field
    -- every time the author pressed it made writing anything longer than a
    -- sentence impossible.
    edits[#edits + 1] = { key = "return", ctrl = ctrl, shift = shift }
    edits[#edits + 1] = "\r"
    return true
  elseif key == "escape" then
    edits[#edits + 1] = "\r"
    return true
  end
  if NAV_KEYS[key] or ctrl then return true end
  -- other keys fall through to App while a field is hot
  return false
end

function Kit.blur()
  -- A textarea's caret, selection and scroll go with its focus. Kept, they
  -- would be restored the next time that id is drawn -- with a caret pointing
  -- into a string that may since have been replaced by another object's.
  if Kit.focus then areaState[Kit.focus] = nil end
  Kit.focus = nil
  syncSoftKeyboard(nil)  -- the soft keyboard follows focus down too (#529)
end

-- ------------------------------------------------------------- hit testing
function Kit.hit(x, y, w, h)
  return Kit.mouseX >= x and Kit.mouseX <= x + w
     and Kit.mouseY >= y and Kit.mouseY <= y + h
end

function Kit.hover(x, y, w, h)
  return Kit.hit(x, y, w, h)
end

-- Kit hit-tests without a z-order, so an overlay cannot just be drawn last:
-- every widget underneath it would still take the same click.  A modal raises
-- this shield over the layers it covers (App.draw does it around the chrome
-- and the panel while the species picker is up) and lowers it for its own
-- layer (#541).
Kit.blockClicks = false

-- ...and a shield over ONE RECTANGLE, for an overlay that covers part of the
-- screen rather than all of it.
--
-- The map editor's tool drawer is the case. It covers the right-hand side, and
-- the panel underneath drew its own controls there before the drawer painted
-- over them -- so those need shielding. But the MAP is still visible on the
-- left, and the whole point of a drawer rather than a tab is that you can go
-- on working on it: the tile painter's clicks land on the map, not in the
-- drawer. The global shield made that impossible -- with a drawer open, every
-- click on the panel was refused, so the one tool whose clicks belong to the
-- map could never receive one.
--
-- Tested against the POINTER rather than against the widget: what is being
-- intercepted is the click, and a widget straddling the edge should still
-- answer for the half of it that is in the open.
Kit.blockRect = nil

local function pointerBlocked()
  local r = Kit.blockRect
  if not r then return false end
  return Kit.mouseX >= r[1] and Kit.mouseX <= r[1] + r[3]
     and Kit.mouseY >= r[2] and Kit.mouseY <= r[2] + r[4]
end

Kit.pointerBlocked = pointerBlocked

function Kit.press(x, y, w, h)
  if Kit.blockClicks or pointerBlocked() then return false end
  return Kit.mouseClicked and Kit.hit(x, y, w, h)
end

-- ------------------------------------------------- tapping away from a modal
--
-- A CLICK IS NOT CONSUMED BY THE WIDGET THAT ANSWERS IT. `Kit.mouseClicked`
-- stays true for the whole frame, on purpose -- it is what lets several
-- widgets read the same pointer without an event queue. The consequence is
-- that a modal opened by a button is opened DURING the frame whose click is
-- still in the buffer, and every modal is drawn after the thing that opened
-- it: the button is outside the modal's rectangle, so the modal's own
-- tap-outside-to-close test reads the opening click as a tap-away and shuts
-- in the frame it went up. On screen it is a flash.
--
-- Every modal in the editor had to solve this and most of them did not. Two
-- carried hand-rolled `_justOpened` flags; four had no guard at all -- the
-- voxel class picker, the profile picker, the wild-encounter picker and the
-- add-a-tileset question -- and every one of them flashed and vanished.
--
-- SO THE GUARD LIVES HERE, and it needs nothing from the caller. A modal is
-- identified by a string; if it did not ask this question on the PREVIOUS
-- frame then this is the frame it went up, and the click in the buffer is the
-- one that opened it. A modal that closes and reopens later gets the guard
-- again for free, because the frames in between are ones it did not ask.
--
-- AND THE CLICK IS SWALLOWED FOR THE REST OF THAT FRAME, which is the half
-- that skipping the outside test does not cover.
--
-- A modal is drawn AFTER the button that opened it and most of them are
-- CENTRED, so the modal lands under a pointer that is still sitting on the
-- button -- and the same click, still in the buffer, is then read by whichever
-- of the modal's own rows happens to be beneath the cursor. From outside that
-- is a popup that "auto-selects what I'm hovering over before I can click
-- anything": the class picker answered itself, the tileset question answered
-- itself, and no amount of guarding the tap-outside test helped, because the
-- click was being taken by a widget INSIDE the modal.
--
-- Clearing `Kit.mouseClicked` here is safe precisely because of the drawing
-- order that caused the problem: everything with a prior claim on this click
-- has already been drawn and has already had it. What is left is the modal
-- that just went up, and it should start the next frame with a clean pointer.
--
-- Returns true only for a real tap outside, on a frame after the first.
local modalFrame = {}

function Kit.tapAway(id, x, y, w, h)
  local now = Kit.frame or 0
  local last = modalFrame[id]
  modalFrame[id] = now
  if last ~= now - 1 then
    -- the frame it went up
    Kit.mouseClicked = false
    return false
  end
  if Kit.blockClicks or pointerBlocked() then return false end
  return (Kit.mouseClicked and not Kit.hit(x, y, w, h)) or false
end

-- Forget a modal's frame stamp. Not required -- the "was it drawn last frame"
-- test recovers on its own -- but a modal that closes itself can say so, which
-- makes the next opening frame's guard exact rather than inferred.
function Kit.forgetModal(id)
  modalFrame[id] = nil
end

-- ------------------------------------------------------------------- text
local function font(name)
  return Kit.fonts[name] or Kit.fonts.small
end

-- EVERY STRING THIS FILE DRAWS IS SCRUBBED FIRST, and the scrub belongs here
-- rather than at the call sites.
--
-- `love.graphics.print` and `Font:getWidth` RAISE on bytes that are not valid
-- UTF-8 -- and the editor draws cartridge text, which is a GB character
-- encoding that has never been UTF-8. One panel slicing a line into columns by
-- byte count cut a multi-byte character in half and took the whole application
-- down with "UTF-8 decoding error: Not enough space", from inside `print`,
-- three frames into opening the NPC tool.
--
-- Fixing the caller fixes one caller. This is the one place every label, every
-- number and every line of dialogue in the editor passes through, so it is the
-- only place that can promise a bad byte cannot crash the app. `utf8Safe`
-- returns the string untouched when it is pure ASCII, which it is for
-- everything except the dialogue.
local function safe(str)
  return Theme.utf8Safe(tostring(str))
end

Kit.safeText = safe

function Kit.text(name, str, x, y, c, a)
  if not G then return 0 end
  local f = font(name)
  if not f then return 0 end
  str = safe(str)
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  G.print(str, x, y)
  return f:getWidth(str)
end

function Kit.textRight(name, str, x2, y, c, a)
  local f = font(name)
  if not f then return end
  str = safe(str)
  Kit.text(name, str, x2 - f:getWidth(str), y, c, a)
end

function Kit.textCenter(name, str, x, y, w, c, a)
  if not G then return end
  local f = font(name)
  if not f then return end
  str = safe(str)
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  if canPrintf() then
    G.printf(str, x, y, w, "center")
  else
    G.print(str, x + (w - f:getWidth(str)) / 2, y)
  end
end

function Kit.textHeight(name)
  local f = font(name)
  return f and f:getHeight() or 12
end

-- MEASURING RAISES TOO, not only drawing: `Font:getWidth` decodes the string
-- to walk it, so a layout that measures a cartridge line before deciding where
-- to put it crashes in exactly the same way `print` does.
function Kit.textWidth(name, str)
  local f = font(name)
  return f and f:getWidth(safe(str)) or 0
end

-- ------------------------------------------------------------ wrapping text
--
-- WRAPPED BY MEASURING, NOT BY COUNTING CHARACTERS.
--
-- The NPC panel divided its column width by `6 * s` -- a guess at how wide one
-- character is -- and cut each line at that many characters. Kit's scale moves
-- with the window and none of these fonts is fixed-width, so the guess was
-- wrong in both directions at once: short lines left a third of the column
-- empty and long ones ran off the end of it. No window size made it right,
-- because the width was never measured.
--
-- Here rather than in the panel because measuring text is what this file is
-- for, and because the next panel that needs a paragraph should not write its
-- own.
--
-- BY CHARACTER WHEN A WORD IS TOO LONG FOR THE COLUMN, and characters means
-- CHARACTERS. The editor draws cartridge text -- a GB encoding decoded into
-- UTF-8 -- so a glyph can be two or three bytes wide and `sub` counts bytes.
-- Cutting one in half took the whole application down inside `print` once
-- already; `Theme.chars` splits on character boundaries.
--
-- EXPLICIT LINE BREAKS SURVIVE. A dialogue box's own breaks are meaningful,
-- and flattening them into one paragraph to re-break somewhere else loses the
-- shape the line was written in.
function Kit.wrap(name, str, width)
  str = safe(tostring(str or ""))
  width = tonumber(width) or 0
  local function fits(s2) return Kit.textWidth(name, s2) <= width end
  local function glyphs(s2)
    if Theme and type(Theme.chars) == "function" then return Theme.chars(s2) end
    local out = {}
    for ch in tostring(s2):gsub("[\128-\255]", "?"):gmatch(".") do
      out[#out + 1] = ch
    end
    return out
  end
  local function breakWord(word, into)
    local g = glyphs(word)
    local at = 1
    while at <= #g do
      local take = 1
      while at + take <= #g and fits(table.concat(g, "", at, at + take)) do
        take = take + 1
      end
      into[#into + 1] = table.concat(g, "", at, math.min(#g, at + take - 1))
      at = at + take
    end
  end

  local out = {}
  for para in (str .. "\n"):gmatch("([^\n]*)\n") do
    if para == "" then
      out[#out + 1] = ""
    else
      local line = nil
      for word in para:gmatch("%S+") do
        local try = line and (line .. " " .. word) or word
        if line == nil then
          if fits(word) then line = word else breakWord(word, out) end
        elseif fits(try) then
          line = try
        else
          out[#out + 1] = line
          if fits(word) then line = word
          else line = nil; breakWord(word, out) end
        end
      end
      if line then out[#out + 1] = line end
    end
  end
  if #out == 0 then out[1] = "" end
  return out
end

function Kit.ellipsize(name, str, maxW)
  return Theme.ellipsize(font(name), str, maxW)
end

-- 12px / 2px-tracked uppercase section caption -- the design's one and only
-- section header.  Returns the caption's height so callers can stack below.
function Kit.caption(x, y, str, c)
  if not G then return Kit.textHeight("caption") end
  local f = font("caption")
  if not f then return 12 end
  G.setFont(f)
  Theme.col(c or PAL.caption, 1)
  Theme.spaced(f, str, x, y, 2 * Kit.scale)
  return f:getHeight()
end

function Kit.captionWidth(str)
  return Theme.spacedWidth(font("caption"), str, 2 * Kit.scale)
end

-- --------------------------------------------------------------- surfaces
function Kit.card(x, y, w, h, r)
  Theme.card(x, y, w, h, r or 16 * Kit.scale)
end

-- A list row.  `selected` rings it in the accent colour (green for "this is
-- the thing you are editing", blue for "this is the thing you are browsing")
-- instead of filling it, so sprites and HP colours stay readable.  Returns
-- true when the row was clicked this frame.
function Kit.row(x, y, w, h, selected, accent, r)
  r = r or 12 * Kit.scale
  if not G then return Kit.press(x, y, w, h) end
  accent = accent or PAL.green
  if selected then Theme.glow(x, y, w, h, r, accent, 0.45) end
  Theme.row(x, y, w, h, r, 0.6)
  if selected then
    Theme.stroke(x, y, w, h, r, accent, 0.85, 1.5 * Kit.scale)
  end
  return Kit.press(x, y, w, h)
end

function Kit.meter(x, y, w, h, pct, c)
  Theme.meter(x, y, w, h, pct, c)
end

-- Dashed empty-state box with a centred hint.
function Kit.emptyBox(x, y, w, h, message)
  if not G then return end
  Theme.col(PAL.cardBorder, 0.4)
  if G.setLineWidth then G.setLineWidth(math.max(1, 1 * Kit.scale)) end
  Theme.dashed(x, y, w, h, 12 * Kit.scale, 7 * Kit.scale, 5 * Kit.scale)
  if G.setLineWidth then G.setLineWidth(1) end
  local f = font("button")
  if not f then return end
  Kit.textCenter("button", message, x + 12 * Kit.scale,
    y + h / 2 - f:getHeight() / 2, w - 24 * Kit.scale, PAL.muted)
end

-- --------------------------------------------------------------- buttons
-- Button kinds, straight out of the spec's colour semantics:
--   primary  green gradient  -- the single "commit this" control (Save)
--   ghost    glassy white    -- neutral verbs (Reload, Open, Add)
--   accent   blue tint       -- steppers, pagers, in-panel navigation
--   good     green tint      -- safe helpers (Full heal, max a DV)
--   danger   red tint        -- destructive verbs, always two-click
--   disabled steel           -- never hidden, always explained in the status bar
local KINDS = {
  primary  = { fillTop = PAL.green, fillBot = PAL.greenDark, aTop = 1, aBot = 1,
               ink = PAL.greenInk, border = nil, glow = PAL.green },
  ghost    = { fillTop = { 255, 255, 255 }, fillBot = { 255, 255, 255 },
               aTop = 0.14, aBot = 0.03, ink = PAL.heading,
               border = { 255, 255, 255 }, borderA = 0.18 },
  accent   = { flat = PAL.blue, flatA = 0.14, ink = PAL.blueInk,
               border = PAL.cardBorder, borderA = 0.35 },
  good     = { flat = PAL.green, flatA = 0.1, ink = PAL.green,
               border = PAL.green, borderA = 0.45 },
  danger   = { flat = PAL.red, flatA = 0.12, ink = PAL.redSoft,
               border = PAL.red, borderA = 0.45 },
  disabled = { flat = { 120, 132, 158 }, flatA = 0.22, ink = PAL.steel,
               border = PAL.steel, borderA = 0.3 },
}

-- opts: { kind, font, enabled, align, radius, glow }
-- Returns true when clicked (never when disabled).
function Kit.button(x, y, w, h, label, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local kind = KINDS[enabled and (opts.kind or "ghost") or "disabled"]
  local r = opts.radius or 10 * Kit.scale
  local hot = enabled and Kit.hover(x, y, w, h)

  if G then
    if opts.glow and enabled then
      Theme.glow(x, y, w, h, r, kind.glow or PAL.green, opts.glow)
    end
    if kind.flat then
      Theme.col(kind.flat, kind.flatA * (hot and 1.6 or 1))
      G.rectangle("fill", x, y, w, h, r, r)
    else
      Theme.gradRounded(x, y, w, h, r, kind.fillTop, kind.fillBot,
        kind.aTop * (hot and 1.4 or 1), kind.aBot * (hot and 1.6 or 1))
    end
    if kind.border then
      Theme.stroke(x, y, w, h, r, kind.border, kind.borderA * (hot and 1.5 or 1), 1)
    end
    -- Kit.button was the one text path here that did not scrub: text, textRight,
    -- textCenter, textWidth and wrap all run through safe(), and a label that
    -- reaches print/printf/getWidth unscrubbed raises on bad UTF-8 mid-draw.
    label = safe(label)
    local f = font(opts.font or "button")
    if f then
      G.setFont(f)
      Theme.col(kind.ink, 1)
      local ty = y + (h - f:getHeight()) / 2
      if opts.align == "left" then
        G.print(label, x + 10 * Kit.scale, ty)
      elseif canPrintf() then
        G.printf(label, x, ty, w, "center")
      else
        G.print(label, x + (w - f:getWidth(label)) / 2, ty)
      end
    end
  end
  return enabled and Kit.press(x, y, w, h) or false
end

-- A small square control: the +/- steppers, the arrow cyclers, the row ✕.
function Kit.stepper(x, y, w, h, glyph, opts)
  opts = opts or {}
  opts.kind = opts.kind or "accent"
  opts.font = opts.font or "small"
  opts.radius = opts.radius or 6 * Kit.scale
  return Kit.button(x, y, w, h, glyph, opts)
end

-- A pill toggle (badges, dex SEEN/OWN, event sub-tabs).  `on` colours it;
-- returns true when clicked.
function Kit.chip(x, y, w, h, label, on, onColor, offColor)
  local c = on and (onColor or PAL.green) or (offColor or PAL.steel)
  if G then
    local r = 6 * Kit.scale
    Theme.col(c, on and 0.16 or 0.06)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, PAL.cardBorder, Kit.hover(x, y, w, h) and 0.5 or 0.28, 1)
    Kit.textCenter("micro", label, x, y + (h - Kit.textHeight("micro")) / 2, w,
      c, on and 1 or 0.75)
  end
  return Kit.press(x, y, w, h)
end

-- Checkbox row: a 20px box plus a mono label, the Events grid's unit.
-- Returns (newChecked, changed) so callers can write true/nil on a flip.
function Kit.checkbox(x, y, w, h, checked, label, labelColor)
  local clicked = Kit.row(x, y, w, h, false, nil, 9 * Kit.scale)
  local box = 20 * Kit.scale
  local bx, by = x + 12 * Kit.scale, y + (h - box) / 2
  if G then
    Theme.col(checked and PAL.green or PAL.rowBg, checked and 1 or 0.9)
    G.rectangle("fill", bx, by, box, box, 5 * Kit.scale, 5 * Kit.scale)
    Theme.stroke(bx, by, box, box, 5 * Kit.scale, PAL.cardBorder, 0.4, 1)
    if checked then
      Kit.textCenter("small", "X", bx, by + (box - Kit.textHeight("small")) / 2,
        box, PAL.greenInk)
    end
    local lx = bx + box + 12 * Kit.scale
    Kit.text("mono", Kit.ellipsize("mono", label, x + w - lx - 10 * Kit.scale), lx,
      y + (h - Kit.textHeight("mono")) / 2, labelColor or (checked and PAL.text or PAL.muted))
  end
  if clicked then return not checked, true end
  return checked, false
end

-- --------------------------------------------------------------- text field
-- A real editable field.  The Events filter used to edge-detect love.keyboard
-- state because Kit had no input widget; this replaces that hack, and App
-- routes love.textinput / love.keypressed in through Kit.textinput /
-- Kit.keypressed.  Returns the (possibly edited) value; the caller stores it.
function Kit.textfield(id, x, y, w, h, value, placeholder)
  value = tostring(value or "")
  if Kit.press(x, y, w, h) then
    Kit.focus = id
    Kit._fieldTookClick = true      -- see Kit.endFrame
    -- Drop the latch so a tap on the ALREADY-focused field raises the
    -- keyboard again. On a platform with a real keyboard that is invisible;
    -- on one whose keyboard is a modal applet it is the only way to get a
    -- second go at the same box.
    kbField = nil
  end
  local focused = (Kit.focus == id)
  if focused then
    -- raise (or hand off) the soft keyboard while this field owns focus (#529)
    syncSoftKeyboard(id, x, y, w, h)
    for _, e in ipairs(edits) do
      -- Structured key entries belong to Kit.textarea; a single-line field has
      -- no caret to move and skips them rather than concatenating a table.
      if type(e) == "table" then                             -- not ours
      elseif e == "\b" then
        value = value:sub(1, -2)
      elseif e == "\f" then
        value = ""
      elseif e == "\r" then
        Kit.blur()  -- commit/cancel also lowers the soft keyboard (#529)
        focused = false
      else
        value = value .. e
      end
    end
  end
  if G then
    local r = 8 * Kit.scale
    Theme.col(PAL.rowBg, 0.7)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, focused and PAL.blue or PAL.cardBorder,
      focused and 0.8 or 0.3, focused and 1.5 * Kit.scale or 1)
    local pad = 10 * Kit.scale
    local ty = y + (h - Kit.textHeight("mono")) / 2
    if value == "" and not focused then
      Kit.text("mono", placeholder or "", x + pad, ty, PAL.faint)
    else
      local shown = Theme.ellipsizeLeft(font("mono"), value, w - 2 * pad)
      local tw = Kit.text("mono", shown, x + pad, ty, PAL.heading)
      -- caret: blinks only while focused, parked at the end of the text
      if focused and (Kit.time % 1) < 0.55 then
        Theme.col(PAL.blue, 1)
        G.rectangle("fill", x + pad + tw + 2, ty, math.max(1, Kit.scale),
          Kit.textHeight("mono"))
      end
    end
  end
  return value
end

-- ---------------------------------------------------------------- textarea
--
-- A MULTI-LINE FIELD WITH A CARET, A SELECTION, AND KEYS THAT REPEAT.
--
-- `Kit.textfield` is a one-line box that appends what you type and drops the
-- last character on backspace. For a name or a number that is the whole job.
-- For a line of NPC dialogue it produced three separate complaints, and each
-- one is a different missing piece rather than three views of one:
--
--   * HELD BACKSPACE DID NOTHING. Kit sees a key PRESS; the operating
--     system's own auto-repeat arrives as repeated keypressed events only if
--     the host forwards them, and this one does not. So erasing a sentence
--     meant tapping forty times. Fixed by watching the key's held state
--     ourselves -- `isDown` plus a delay and a rate -- which also makes the
--     behaviour the same on every platform instead of inheriting whatever the
--     OS was set to.
--
--   * ONE LINE, SHOWING THE TAIL. `ellipsizeLeft` keeps the end of the string
--     in view, which is right for a path and wrong for prose: the author could
--     see "...2recomped" and nothing else, with no way to read what they had
--     written. Wrapped over as many lines as the box has room for, scrolled to
--     follow the caret.
--
--   * NO SELECTION. Without one there is no select-all, no cut, no replacing a
--     phrase -- the only edit available was "backspace to it".
--
-- STATE LIVES HERE, KEYED BY ID, because the caller owns the string and hands
-- it over per frame; a caret parked in the caller would have to be threaded
-- through every panel that draws a field. Weak-keyed by nothing -- ids are
-- short strings and there are a handful -- but dropped on blur so a field
-- reopened later starts clean.
-- `atEnd` seeds the caret the first time a field is seen.
--
-- AT THE END, NOT AT ZERO. A field opened on existing text and typed into
-- should extend it; a caret parked at the front means the first character the
-- author types lands before everything they wrote, which is not a behaviour
-- anyone expects from a text box. A click sets the caret from where it landed,
-- so this only decides the case where focus arrived some other way.
local function areaFor(id, atEnd)
  local st = areaState[id]
  if not st then
    st = { caret = atEnd or 0, anchor = nil, scroll = 0,
           repeatAt = nil, repeatKey = nil }
    areaState[id] = st
  end
  return st
end

-- Character offsets, not byte offsets, everywhere in this widget: a caret
-- between the two halves of a multi-byte glyph is a caret that draws in the
-- wrong place and deletes half a character.
local function glyphsOf(str)
  if Theme and type(Theme.chars) == "function" then return Theme.chars(str) end
  local out = {}
  for ch in tostring(str):gmatch(".") do out[#out + 1] = ch end
  return out
end

local function sub(g, from, to)
  return table.concat(g, "", math.max(1, from), math.min(#g, to))
end

-- The selection as an ordered pair, or nil when there is none.
local function selection(st, n)
  if not st.anchor then return nil end
  local a, b = st.anchor, st.caret
  if a == b then return nil end
  if a > b then a, b = b, a end
  return math.max(0, a), math.min(n, b)
end

function Kit.textareaValue(id) return areaState[id] end

-- Wrap `value` and remember, per line, the character offset it starts at, so a
-- caret can be turned into a row and column and back.
local function layout(name, value, width)
  local lines = Kit.wrap(name, value, width)
  local starts, at = {}, 0
  local g = glyphsOf(value)
  local cursor = 1
  for i, line in ipairs(lines) do
    -- Find where this line begins in the source. `wrap` drops the space it
    -- broke on, so skip separators rather than assuming a fixed stride.
    while cursor <= #g and (g[cursor] == " " or g[cursor] == "\n") do
      cursor = cursor + 1
    end
    starts[i] = cursor - 1
    cursor = cursor + #glyphsOf(line)
  end
  return lines, starts, #g
end

-- A multi-line editable field. Returns the (possibly changed) value.
function Kit.textarea(id, x, y, w, h, value, placeholder)
  value = tostring(value or "")
  local st = areaFor(id, #glyphsOf(value))
  local pad = 8 * Kit.scale
  local lineH = Kit.textHeight("mono") + 2 * Kit.scale
  local innerW = w - 2 * pad
  local rows = math.max(1, math.floor((h - 2 * pad) / lineH))
  local lines, starts, n = layout("mono", value, innerW)

  local function caretAt(px, py)
    local row = math.floor((py - y - pad) / lineH) + 1 + st.scroll
    row = math.max(1, math.min(#lines, row))
    local line = lines[row] or ""
    local g = glyphsOf(line)
    local col, best = 0, math.huge
    for i = 0, #g do
      local dx = math.abs(x + pad + Kit.textWidth("mono", sub(g, 1, i)) - px)
      if dx < best then best, col = dx, i end
    end
    return math.min(n, (starts[row] or 0) + col)
  end

  -- ------------------------------------------------------------- pointer
  if Kit.press(x, y, w, h) then
    Kit.focus = id
    Kit._fieldTookClick = true      -- see Kit.endFrame
    kbField = nil
    st.caret = caretAt(Kit.mouseX, Kit.mouseY)
    st.anchor = st.caret
    st.dragging = true
  end
  if st.dragging then
    local down = love and love.mouse and love.mouse.isDown
      and love.mouse.isDown(1)
    if down and Kit.focus == id then
      st.caret = caretAt(Kit.mouseX, Kit.mouseY)
    else
      st.dragging = false
    end
  end

  local focused = (Kit.focus == id)
  local g = glyphsOf(value)

  local function replaceSelection(with)
    local a, b = selection(st, n)
    if a then
      value = sub(g, 1, a) .. with .. sub(g, b + 1, #g)
      st.caret = a + #glyphsOf(with)
      st.anchor = nil
    else
      value = sub(g, 1, st.caret) .. with .. sub(g, st.caret + 1, #g)
      st.caret = st.caret + #glyphsOf(with)
    end
    g = glyphsOf(value)
    n = #g
  end

  local function deleteBack()
    local a, b = selection(st, n)
    if a then
      replaceSelection("")
      return
    end
    if st.caret <= 0 then return end
    value = sub(g, 1, st.caret - 1) .. sub(g, st.caret + 1, #g)
    st.caret = st.caret - 1
    g = glyphsOf(value); n = #g
  end

  local function deleteForward()
    local a = selection(st, n)
    if a then replaceSelection("") return end
    if st.caret >= n then return end
    value = sub(g, 1, st.caret) .. sub(g, st.caret + 2, #g)
    g = glyphsOf(value); n = #g
  end

  if focused then
    syncSoftKeyboard(id, x, y, w, h)

    -- ------------------------------------------------ held-key repeat
    --
    -- Watched rather than waited for: the host forwards a key PRESS and not
    -- the OS's auto-repeat, so a held backspace produced exactly one delete.
    -- 0.45s before the first repeat and ~30/s after is the rate a text field
    -- is expected to have; slower feels broken, faster overshoots.
    local held = nil
    if love and love.keyboard and love.keyboard.isDown then
      for _, k in ipairs({ "backspace", "delete", "left", "right",
                           "up", "down" }) do
        if love.keyboard.isDown(k) then held = k break end
      end
    end
    if held ~= st.repeatKey then
      st.repeatKey = held
      st.repeatAt = held and (Kit.time + 0.45) or nil
    elseif held and st.repeatAt and Kit.time >= st.repeatAt then
      st.repeatAt = Kit.time + 0.033
      edits[#edits + 1] = { key = held, repeated = true,
        shift = love.keyboard.isDown("lshift")
             or love.keyboard.isDown("rshift") }
    end

    for _, e in ipairs(edits) do
      if type(e) == "string" then
        if e == "\b" then
          deleteBack()
        elseif e == "\f" then
          value, st.caret, st.anchor = "", 0, nil
          g, n = {}, 0
        elseif e == "\r" then
          -- handled by the structured entry (return inserts a newline);
          -- escape blurs.
        else
          replaceSelection(e)
        end
      else
        local k = e.key
        local function moveTo(pos)
          if e.shift then
            st.anchor = st.anchor or st.caret
          else
            st.anchor = nil
          end
          st.caret = math.max(0, math.min(n, pos))
        end
        if k == "backspace" then
          if e.repeated then deleteBack() end
        elseif k == "delete" then
          deleteForward()
        elseif k == "left" then
          moveTo(st.caret - 1)
        elseif k == "right" then
          moveTo(st.caret + 1)
        elseif k == "home" then
          moveTo(0)
        elseif k == "end" then
          moveTo(n)
        elseif k == "up" or k == "down" then
          -- By ROW, so the caret lands under where it was rather than a
          -- fixed number of characters away.
          local row, col = 1, st.caret
          for i = #lines, 1, -1 do
            if st.caret >= (starts[i] or 0) then
              row, col = i, st.caret - (starts[i] or 0)
              break
            end
          end
          local want = row + (k == "up" and -1 or 1)
          want = math.max(1, math.min(#lines, want))
          moveTo((starts[want] or 0)
                 + math.min(col, #glyphsOf(lines[want] or "")))
        elseif k == "return" then
          replaceSelection("\n")
        elseif e.ctrl and k == "a" then
          st.anchor, st.caret = 0, n
        elseif e.ctrl and (k == "c" or k == "x") then
          local a, b = selection(st, n)
          if a and love and love.system and love.system.setClipboardText then
            love.system.setClipboardText(sub(g, a + 1, b))
            if k == "x" then replaceSelection("") end
          end
        elseif e.ctrl and k == "v" then
          if love and love.system and love.system.getClipboardText then
            local paste = love.system.getClipboardText()
            if type(paste) == "string" and paste ~= "" then
              replaceSelection(paste)
            end
          end
        end
      end
    end
    st.caret = math.max(0, math.min(n, st.caret))
    lines, starts, n = layout("mono", value, innerW)
  end

  -- keep the caret on screen
  do
    local row = 1
    for i = #lines, 1, -1 do
      if st.caret >= (starts[i] or 0) then row = i break end
    end
    if row - 1 < st.scroll then st.scroll = row - 1 end
    if row > st.scroll + rows then st.scroll = row - rows end
    st.scroll = math.max(0, math.min(math.max(0, #lines - rows), st.scroll))
  end

  -- ------------------------------------------------------------- drawing
  if G then
    local r = 8 * Kit.scale
    Theme.col(PAL.rowBg, 0.7)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, focused and PAL.blue or PAL.cardBorder,
      focused and 0.8 or 0.3, focused and 1.5 * Kit.scale or 1)

    if value == "" and not focused then
      Kit.text("mono", placeholder or "", x + pad, y + pad, PAL.faint)
    else
      local a, b = selection(st, n)
      for i = 1, rows do
        local row = i + st.scroll
        local line = lines[row]
        if line then
          local ly = y + pad + (i - 1) * lineH
          -- selection band first, so the glyphs sit on top of it
          if a then
            local s0, s1 = starts[row] or 0, (starts[row] or 0) + #glyphsOf(line)
            local from = math.max(a, s0)
            local to = math.min(b, s1)
            if to > from then
              local lg = glyphsOf(line)
              local px = Kit.textWidth("mono", sub(lg, 1, from - s0))
              local pw = Kit.textWidth("mono", sub(lg, from - s0 + 1, to - s0))
              Theme.col(PAL.blue, 0.35)
              G.rectangle("fill", x + pad + px, ly, math.max(1, pw), lineH)
            end
          end
          Kit.text("mono", line, x + pad, ly, PAL.heading)
          if focused and (Kit.time % 1) < 0.55 then
            local s0 = starts[row] or 0
            local lg = glyphsOf(line)
            if st.caret >= s0 and st.caret <= s0 + #lg then
              local cx = x + pad + Kit.textWidth("mono", sub(lg, 1, st.caret - s0))
              Theme.col(PAL.blue, 1)
              G.rectangle("fill", cx, ly, math.max(1, Kit.scale), lineH)
            end
          end
        end
      end
      -- MORE TEXT THAN FITS, said rather than left to be discovered. The old
      -- field's whole problem was showing part of the string with nothing to
      -- indicate the rest.
      if #lines > rows then
        Kit.text("small", string.format("%d/%d", st.scroll + rows, #lines),
                 x + w - 42 * Kit.scale, y + h - 14 * Kit.scale, PAL.faint)
      end
    end
  end
  return value
end

-- ------------------------------------------------------------------ pager
-- Prev / Next / "1-12 of 151".  Drawn even when there is a single page, so a
-- list is never silently truncated (rule 5 of the design spec).  Returns the
-- new offset.
function Kit.pager(x, y, w, offset, total, perPage)
  local h = 30 * Kit.scale
  local bw = 74 * Kit.scale
  local maxOffset = math.max(0, total - perPage)
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.button(x, y, bw, h, "Prev", { kind = "accent", font = "small",
      enabled = offset > 0, radius = 8 * Kit.scale }) then
    offset = math.max(0, offset - perPage)
  end
  if Kit.button(x + bw + 10 * Kit.scale, y, bw, h, "Next", { kind = "accent",
      font = "small", enabled = offset < maxOffset, radius = 8 * Kit.scale }) then
    offset = math.min(maxOffset, offset + perPage)
  end
  local shown = math.min(perPage, math.max(0, total - offset))
  local label = ("%d-%d of %d"):format(total > 0 and offset + 1 or 0,
    offset + shown, total)
  Kit.text("mono", label, x + 2 * bw + 20 * Kit.scale,
    y + (h - Kit.textHeight("mono")) / 2, PAL.caption)
  return offset, h
end

-- ----------------------------------------------------------------- scroll
-- Mouse wheel over a list body (#595): same offset contract as Kit.pager, so
-- a list can carry both and stay on one page counter.  Three rules, all of
-- them consequences of Kit having no z-order:
--   * only the list the pointer is inside takes the notch,
--   * the notch is consumed, so two stacked lists cannot both eat it,
--   * Kit.blockClicks shields it exactly as it shields Kit.press, or the
--     panel under an open species picker would scroll through the modal.
local SCROLL_ROWS = 3

function Kit.scroll(x, y, w, h, offset, total, perPage)
  local maxOffset = math.max(0, (total or 0) - (perPage or 0))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks or pointerBlocked() or (Kit.wheelY or 0) == 0 then
    return offset
  end
  if not Kit.hit(x, y, w, h) then return offset end
  -- LOVE reports wheel-up as positive y; up moves the window toward the top
  -- of the list, which is a smaller offset.
  local rows = math.max(1, math.min(SCROLL_ROWS, perPage or SCROLL_ROWS))
  local step = (Kit.wheelY > 0) and -rows or rows
  Kit.wheelY = 0
  return Theme.clamp(offset + step, 0, maxOffset)
end

-- Clip drawing to a rect (list bodies).  No-ops under the headless stub.
function Kit.pushClip(x, y, w, h)
  -- A compact mobile viewport can leave a panel with no room for a list.
  -- LÖVE rejects negative scissor dimensions, so treat an exhausted clip
  -- region as empty instead of passing invalid geometry through to it.
  Kit._clipActive = G and G.setScissor ~= nil
  if Kit._clipActive then
    if w <= 0 or h <= 0 then
      G.setScissor(0, 0, 0, 0)
    else
      G.setScissor(math.floor(x), math.floor(y), math.ceil(w), math.ceil(h))
    end
  end
end

function Kit.popClip()
  if Kit._clipActive and G and G.setScissor then G.setScissor() end
  Kit._clipActive = false
end

return Kit
