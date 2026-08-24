-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The event builder, as a popup over the whole window.
--
-- OVER THE WINDOW rather than in the drawer, for the same reason the asset
-- library is: an event is built by looking at a list of beats and a list of
-- flags at the same time, and neither of those fits in a column beside a map.
-- App paints it after the whole frame -- Kit has no z-order, so "on top" and
-- "drawn last" are the same statement -- and `Kit.tapAway` keeps the click
-- that opened it from closing it again.
--
-- WHAT IT EDITS is described in MapEvents: an event is its PARTS -- the
-- conditions, the beats, the flag it sets -- and the script rows are derived
-- from them every time they are needed. Read that file's header first; this
-- one is only the form.
--
-- THREE PANES, because there are three questions and mixing them is what makes
-- a script editor unusable: WHICH event (the list), WHAT it does (the beats),
-- and WHEN it runs (the conditions and the flag). The row of tabs at the top
-- is those three.

local MapEvents = require("tools.map-editor.MapEvents")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}

local EventMenu = {}

EventMenu.TABS = {
  { id = "list",  label = "EVENTS" },
  { id = "beats", label = "WHAT HAPPENS" },
  { id = "when",  label = "WHEN" },
  { id = "flags", label = "FLAGS" },
}

local function current(S)
  if not S.eventEditing then return nil end
  return MapEvents.get(S, S.mapId, S.eventEditing)
end

-- ---------------------------------------------------------------------------
-- the panes
-- ---------------------------------------------------------------------------

local function drawList(S, Kit, x, y, w, h)
  local s = Kit.scale
  local fy = y
  local rowH = 42 * s
  local btnH = 30 * s

  if Kit.button(x, fy, w, btnH, "+ NEW EVENT ON THE SELECTED CELL",
                { font = "small", kind = "accent" }) then
    local at = S.pvCell
    if at then
      local ev = MapEvents.create(S, { x = at.cx, y = at.cy, trigger = "step",
                                       name = string.format("Event at %d,%d",
                                                            at.cx, at.cy) })
      if ev then
        S.eventEditing = ev.id
        S.eventTab = "beats"
      end
    else
      S.eventNotice = "pick a cell on the map first"
    end
  end
  fy = fy + btnH + 4 * s
  -- AN EVENT ON AN OBJECT IS A DIFFERENT THING and says so rather than being a
  -- checkbox on the same button: one is a square you walk onto, the other is
  -- what somebody says when you talk to them, and they are stored in
  -- different places for that reason.
  if Kit.button(x, fy, w, btnH, "+ NEW EVENT ON THE SELECTED NPC",
                { font = "small" }) then
    local idx = S.objSelected
    if idx then
      local ev = MapEvents.create(S, { trigger = "talk", object = idx,
                                       once = false,
                                       name = "What NPC " .. tostring(idx)
                                              .. " does" })
      if ev then
        S.eventEditing = ev.id
        S.eventTab = "beats"
      end
    else
      S.eventNotice = "pick an NPC in the NPCs tool first"
    end
  end
  fy = fy + btnH + 8 * s

  local list = MapEvents.list(S, S.mapId)
  -- WHAT IS ALREADY HERE, under what the editor made. The list used to show
  -- only the editor's own and said "no events on this map yet" about Azalea
  -- Town, which has a dozen scripted objects and three step triggers of its
  -- own -- true of the store and false of the map, and the reader is looking
  -- at the map.
  local cart = {}
  do
    local okC, got = pcall(MapEvents.cartridgeEvents, S, S.mapId)
    if okC and type(got) == "table" then cart = got end
  end
  if #list == 0 and #cart == 0 then
    Kit.text("small", "nothing on this map yet.", x, fy, PAL.muted)
    return
  end
  local perPage = math.max(1, math.floor((y + h - fy) / rowH))
  local maxS = math.max(0, #list - perPage)
  S.eventScroll = math.max(0, math.min(S.eventScroll or 0, maxS))
  Kit.pushClip(x, fy, w, y + h - fy)
  for i = S.eventScroll + 1, math.min(#list, S.eventScroll + perPage) do
    local ev = list[i]
    local delW = 28 * s
    local on = S.eventEditing == ev.id
    if Kit.press(x, fy, w - delW - 4 * s, rowH - 4 * s) then
      S.eventEditing = ev.id
      S.cartSelected = nil        -- see the note on the cartridge rows below
      S.eventTab = "beats"
    end
    Kit.row(x, fy, w - delW - 4 * s, rowH - 4 * s, on)
    Kit.text("body", Kit.ellipsize("body", ev.name or ev.id,
                                   w - delW - 20 * s), x + 8 * s, fy + 4 * s)
    -- WHAT IT IS, on the row: where it fires, how many beats, and the flag it
    -- turns on. An event's name is whatever somebody typed and "Guard" tells
    -- you nothing about whether it has been wired up.
    local bits = {}
    bits[#bits + 1] = (ev.trigger == "talk")
      and ("talk to #" .. tostring(ev.object or "?"))
      or string.format("step on %s,%s", tostring(ev.x), tostring(ev.y))
    bits[#bits + 1] = #(ev.beats or {}) .. " beat"
      .. (#(ev.beats or {}) == 1 and "" or "s")
    if #(ev.requires or {}) > 0 then
      bits[#bits + 1] = #ev.requires .. " condition"
        .. (#ev.requires == 1 and "" or "s")
    end
    if ev.flag and ev.flag ~= "" then bits[#bits + 1] = "sets " .. ev.flag end
    Kit.text("small", Kit.ellipsize("small", table.concat(bits, "  -  "),
                                    w - delW - 16 * s),
             x + 8 * s, fy + 22 * s, PAL.muted)
    if Kit.button(x + w - delW, fy, delW, rowH - 4 * s, "x",
                  { font = "small", radius = 6 * s }) then
      MapEvents.delete(S, S.mapId, ev.id)
      if S.eventEditing == ev.id then S.eventEditing = nil end
      S.eventNotice = "deleted"
    end
    fy = fy + rowH
  end

  -- THE CARTRIDGE'S OWN.
  --
  -- These are ROM bytecode reached through a label; there is no way back from
  -- that to a list of beats, so this panel will not pretend to EDIT one --
  -- an editor that showed a decompiled guess would have the author changing a
  -- fiction while believing it was the scene.
  --
  -- What it does do is let you SELECT one, see everything that is actually
  -- known about it, and TAKE IT OVER: an authored event on the same trigger
  -- that the engine runs instead (MapEvents.adopt). That is the honest version
  -- of "editable" here, and it was the missing half -- the list showed these
  -- rows and nothing could be done with any of them.
  if #cart > 0 and fy < y + h - 20 * s then
    Kit.text("small", string.format(
      "ALREADY ON THIS MAP  -  %d, from the cartridge", #cart), x, fy,
      PAL.muted)
    fy = fy + 17 * s
    for ci, c in ipairs(cart) do
      if fy > y + h - 16 * s then break end
      local key = EventMenu.cartKey(c)
      local on = S.cartSelected == key
      local rh = 15 * s
      if Kit.press(x + 6 * s, fy - 2 * s, w - 12 * s, rh + 2 * s) then
        -- Toggle: a second press on the selected row puts the detail away,
        -- which is the only way back when the list is long.
        S.cartSelected = (not on) and key or nil
        -- ONE SELECTION AT A TIME. The right-hand pane draws whichever of the
        -- two is set, so leaving an editor event selected underneath a
        -- cartridge row would show that event's beats beside this row's
        -- highlight -- two things selected, one of them described.
        if S.cartSelected then
          S.eventEditing = nil
          S.eventTab = "beats"
        end
        S.eventNotice = nil
      end
      if on then Kit.row(x + 4 * s, fy - 2 * s, w - 8 * s, rh + 2 * s, true) end
      local where = (c.kind == "coord")
        and string.format("step %d,%d", c.x, c.y)
        or ("talk  " .. tostring(c.what or "spawns"))
      local flag = c.flag and ("  -  " .. MapEvents.flagLabel(c.flag)) or ""
      Kit.text("small", Kit.ellipsize("small",
               where .. "  -  " .. tostring(c.name) .. flag, w),
               x + 6 * s, fy, on and PAL.text or PAL.muted)
      fy = fy + rh
      if on then fy = EventMenu.drawCartDetail(S, Kit, c, x, fy, w, y + h) end
    end
  end
  Kit.popClip()
end

-- WHAT IS ACTUALLY KNOWN ABOUT ONE CARTRIDGE EVENT, and the two things that
-- can honestly be done with it.
--
-- Every line here is read out of the extracted data. Nothing is inferred and
-- nothing is decompiled: where it fires, which script label it jumps to, the
-- scene index for a coord event, the spawn flag, and for an object the fields
-- that are DATA rather than code -- position, sprite, movement -- which the
-- objects panel can already edit.
function EventMenu.drawCartDetail(S, Kit, c, x, fy, w, bottom)
  local s = Kit.scale
  local pad = 12 * s
  local function line(text, col)
    if fy > bottom - 14 * s then return false end
    Kit.text("small", Kit.ellipsize("small", text, w - pad - 8 * s),
             x + pad, fy, col or PAL.muted)
    fy = fy + 14 * s
    return true
  end

  if c.kind == "coord" then
    line(string.format("fires when the player steps on %d,%d", c.x, c.y))
    if c.scene ~= nil then
      line("scene " .. tostring(c.scene)
           .. " - only while the map is in that scene")
    end
    line("runs " .. tostring(c.script or "an unnamed script")
         .. " (cartridge bytecode)")
  else
    line("object #" .. tostring(c.object or "?")
         .. (c.x and string.format(" at %d,%d", c.x, c.y) or ""))
    if c.what == "script" then
      line("runs its own script when talked to (cartridge bytecode)")
    elseif c.what == "talks" then
      line("says a line of the cartridge's dialogue when talked to")
    elseif c.what == "trainer" then
      line("is a trainer - battles when talked to")
    end
  end
  if c.flag and c.flag ~= "" then
    line("gated on " .. MapEvents.flagLabel(c.flag))
  end

  -- THE ACTIONS. Take over is the one that always applies; editing the object
  -- is offered only where there IS an object, and it goes to the panel that
  -- already owns those fields rather than duplicating them here.
  local bw = math.floor((w - pad - 8 * s) / 2) - 4 * s
  if fy + 24 * s < bottom then
    local taken = nil
    for _, ev in ipairs(MapEvents.list(S, S.mapId)) do
      if (c.kind == "coord" and ev.x == c.x and ev.y == c.y)
         or (c.kind == "object" and ev.trigger == "talk"
             and ev.object == c.object) then
        taken = ev
      end
    end
    if Kit.button(x + pad, fy, bw, 22 * s,
                  taken and "OPEN MINE" or "TAKE OVER",
                  { font = "small", kind = taken and "ghost" or "accent" }) then
      local ev, why = taken or MapEvents.adopt(S, S.mapId, c)
      if ev then
        S.eventEditing = ev.id
        S.eventTab = "beats"
        S.cartSelected = nil
        -- SAID PLAINLY, because "take over" is a strong claim and the reader
        -- has to know which half they got: a step event stands in front of the
        -- cartridge's, a talk event replaces the NPC's dialogue outright.
        S.eventNotice = taken and "already taken over - opened it"
          or ((c.kind == "coord")
              and "this event now runs instead of the cartridge's on that square"
              or "this NPC now says what you write here instead")
      else
        S.eventNotice = tostring(why or "could not take it over")
      end
    end
    if c.kind == "object" and c.object then
      if Kit.button(x + pad + bw + 8 * s, fy, bw, 22 * s, "EDIT OBJECT",
                    { font = "small" }) then
        -- The objects panel owns position, sprite, movement and facing; this
        -- hands it the object rather than growing a second copy of that form.
        --
        -- Through `Sidebar.open`, which is the one door that sets the drawer
        -- state (`S.sidebar`) the panels are resolved from -- writing an
        -- `S.tool` of my own invention would have set a field nothing reads.
        local okSB, Sidebar = pcall(require, "tools.map-editor.Sidebar")
        if okSB and Sidebar.openId(S) ~= "objects" then
          Sidebar.open(S, "objects")
        end
        S.objSelected = c.object
        S.eventNotice = "opened object #" .. tostring(c.object)
      end
    end
    fy = fy + 26 * s
  end
  return fy + 4 * s
end

-- IDENTITY FOR A CARTRIDGE EVENT, in one place.
--
-- It has no id of its own -- it is a row derived from the map's data -- so it
-- is identified by what it IS: kind, object, and square. Built here rather
-- than at each site, because a selection key spelled two ways is a row that
-- highlights and a pane that stays empty, which is precisely the bug this pane
-- was reported for.
function EventMenu.cartKey(c)
  return tostring(c.kind) .. ":" .. tostring(c.object or "")
    .. ":" .. tostring(c.x or "") .. "," .. tostring(c.y or "")
end

-- The cartridge event the left list has selected, by the key that list builds.
--
-- Rebuilt from `cartridgeEvents` rather than stashed on S when the row was
-- pressed: the list is derived from the map's own data and can change under us
-- (an object edited, a map reloaded), and a stale copy of one row would be a
-- pane describing something that is no longer there.
function EventMenu.selectedCart(S)
  if not S.cartSelected then return nil end
  local okC, cart = pcall(MapEvents.cartridgeEvents, S, S.mapId)
  if not (okC and type(cart) == "table") then return nil end
  for _, c in ipairs(cart) do
    if EventMenu.cartKey(c) == S.cartSelected then return c end
  end
  return nil
end

-- One beat's fields, generated from the same table the lowering reads.
local function drawBeatArgs(S, Kit, ev, beat, spec, x, y, w)
  local s = Kit.scale
  local fy = y
  local fieldH = 26 * s
  local labelW = 78 * s
  for _, arg in ipairs(spec.args or {}) do
    Kit.text("small", arg.label or arg.key, x, fy + 6 * s, PAL.muted)
    local fx, fw = x + labelW, w - labelW
    if arg.kind == "choice" then
      local opts = arg.options or {}
      local cur = beat[arg.key] or opts[1]
      if Kit.button(fx, fy, fw, fieldH, tostring(cur), { font = "small" }) then
        local at = 1
        for i, o in ipairs(opts) do if o == cur then at = i end end
        beat[arg.key] = opts[(at % math.max(1, #opts)) + 1]
        MapEvents.save(S, S.mapId, ev)
      end
    elseif arg.kind == "flag" then
      -- FROM THE LIST, NOT TYPED. A misspelled flag is the failure mode this
      -- whole registry exists to prevent.
      if Kit.button(fx, fy, fw, fieldH,
                    Kit.ellipsize("small", beat[arg.key] or "(pick a flag)",
                                  fw - 12 * s), { font = "small" }) then
        S.eventFlagPick = { beat = beat, key = arg.key }
        S.eventTab = "flags"
      end
    elseif arg.kind == "number" then
      local v = Kit.textfield("ev-" .. tostring(beat) .. arg.key, fx, fy,
                              fw, fieldH, tostring(beat[arg.key] or ""),
                              arg.placeholder or "0")
      local n = tonumber(v)
      if n ~= beat[arg.key] then
        beat[arg.key] = n
        MapEvents.save(S, S.mapId, ev)
      end
    else
      local v = Kit.textfield("ev-" .. tostring(beat) .. arg.key, fx, fy,
                              fw, fieldH, tostring(beat[arg.key] or ""),
                              arg.placeholder or "")
      if v ~= (beat[arg.key] or "") then
        beat[arg.key] = v
        MapEvents.save(S, S.mapId, ev)
      end
    end
    fy = fy + fieldH + 4 * s
  end
  -- A PATH IS TYPED THE WAY IT IS READ, and echoed back so it is obvious when
  -- a stray character was dropped: "uul" and "up up left" are the same thing
  -- and neither is what you meant if the echo says two steps.
  for _, arg in ipairs(spec.args or {}) do
    if arg.kind == "path" then
      local dirs = MapEvents.parsePath(beat[arg.key])
      Kit.text("small", (#dirs == 0) and "u d l r, or 'up up left'"
               or ("-> " .. MapEvents.pathText(dirs)),
               x + labelW, fy, PAL.muted)
      fy = fy + 15 * s
    end
  end
  return fy
end

local function drawBeats(S, Kit, x, y, w, h)
  local s = Kit.scale
  local ev = current(S)
  if not ev then
    -- A CARTRIDGE EVENT IS A SELECTION TOO.
    --
    -- This pane draws from `S.eventEditing`, which only the editor's OWN
    -- events set -- so selecting one of the cartridge's filled the left list
    -- with a highlighted row and left the whole right-hand side blank, which
    -- reads as the menu being broken rather than as "there is nothing here to
    -- edit". There IS something to say: what it is, and that its script is
    -- bytecode this editor cannot open.
    local cart = EventMenu.selectedCart(S)
    if cart then
      Kit.text("body", tostring(cart.name or "cartridge event"), x, y)
      local fy = y + 22 * s
      Kit.text("small", "THIS ONE CAME WITH THE GAME", x, fy, PAL.yellow)
      fy = fy + 18 * s
      fy = EventMenu.drawCartDetail(S, Kit, cart, x - 12 * s, fy, w + 12 * s,
                                    y + h)
      Kit.text("small", Kit.wrap and Kit.wrap("small",
        "Its script is compiled into the cartridge, so there is no list of "
        .. "beats to show you -- taking it over gives you an event of your "
        .. "own on the same trigger, which runs instead.", w)
        or "Its script is compiled into the cartridge.", x, fy, PAL.muted)
      return
    end
    Kit.text("small", "pick an event on the left", x, y, PAL.muted)
    return
  end
  local fy = y
  local fieldH = 28 * s

  local name = Kit.textfield("ev-name", x, fy, w, fieldH, ev.name or "",
                             "name this event...")
  if name ~= (ev.name or "") then
    ev.name = name
    MapEvents.save(S, S.mapId, ev)
  end
  fy = fy + fieldH + 8 * s

  -- ADD A BEAT: the palette of them, wrapped, with the blurb under whichever
  -- is hovered. Every one of these lowers to a real command -- see MapEvents.
  Kit.text("small", "ADD", x, fy + 5 * s, PAL.muted)
  local bx, by = x + 34 * s, fy
  local bw, bh = 96 * s, 22 * s
  for _, spec in ipairs(MapEvents.BEATS) do
    if bx + bw > x + w then bx, by = x + 34 * s, by + bh + 4 * s end
    if Kit.button(bx, by, bw, bh,
                  Kit.ellipsize("small", spec.label, bw - 10 * s),
                  { font = "small", radius = 5 * s }) then
      ev.beats[#ev.beats + 1] = { kind = spec.kind }
      MapEvents.save(S, S.mapId, ev)
    end
    bx = bx + bw + 4 * s
  end
  fy = by + bh + 10 * s

  if #ev.beats == 0 then
    Kit.text("small", "nothing happens yet - add a beat above", x, fy,
             PAL.muted)
    return
  end

  Kit.pushClip(x, fy, w, y + h - fy)
  local ry = fy - (S.eventBeatScroll or 0)
  for i, beat in ipairs(ev.beats) do
    local spec = MapEvents.beatFor(beat.kind)
    local ctlW = 78 * s
    Kit.text("body", string.format("%d. %s", i,
             spec and spec.label or tostring(beat.kind)), x, ry)
    -- ORDER IS THE SCRIPT, so moving a beat is the commonest edit after
    -- adding one: an NPC who speaks after pushing you back reads as a bug.
    if i > 1 and Kit.button(x + w - ctlW, ry - 2 * s, 22 * s, 20 * s, "^",
                            { font = "small", radius = 4 * s }) then
      ev.beats[i], ev.beats[i - 1] = ev.beats[i - 1], ev.beats[i]
      MapEvents.save(S, S.mapId, ev)
    end
    if i < #ev.beats
       and Kit.button(x + w - ctlW + 26 * s, ry - 2 * s, 22 * s, 20 * s, "v",
                      { font = "small", radius = 4 * s }) then
      ev.beats[i], ev.beats[i + 1] = ev.beats[i + 1], ev.beats[i]
      MapEvents.save(S, S.mapId, ev)
    end
    if Kit.button(x + w - ctlW + 52 * s, ry - 2 * s, 22 * s, 20 * s, "x",
                  { font = "small", radius = 4 * s }) then
      table.remove(ev.beats, i)
      MapEvents.save(S, S.mapId, ev)
      break
    end
    ry = ry + 18 * s
    if spec then
      Kit.text("small", spec.blurb or "", x + 14 * s, ry, PAL.muted)
      ry = ry + 15 * s
      ry = drawBeatArgs(S, Kit, ev, beat, spec, x + 14 * s, ry, w - 20 * s)
    else
      Kit.text("small", "this build does not have that beat", x + 14 * s, ry,
               PAL.red)
      ry = ry + 15 * s
    end
    ry = ry + 6 * s
  end
  Kit.popClip()
  S._eventBeatH = ry + (S.eventBeatScroll or 0) - fy
end

local function drawWhen(S, Kit, x, y, w, h)
  local s = Kit.scale
  local ev = current(S)
  if not ev then
    Kit.text("small", "pick an event on the left", x, y, PAL.muted)
    return
  end
  local fy = y
  local fieldH = 28 * s

  Kit.text("small", "WHERE IT FIRES", x, fy, PAL.muted)
  fy = fy + 16 * s
  Kit.text("body", (ev.trigger == "talk")
           and ("when the player talks to object #" .. tostring(ev.object))
           or string.format("when the player steps on cell %s,%s",
                            tostring(ev.x), tostring(ev.y)), x, fy)
  fy = fy + 20 * s
  if ev.trigger ~= "talk" then
    if Kit.button(x, fy, w, fieldH, "MOVE IT TO THE SELECTED CELL",
                  { font = "small" }) then
      local at = S.pvCell
      if at then
        ev.x, ev.y = at.cx, at.cy
        MapEvents.save(S, S.mapId, ev)
        S.eventNotice = string.format("moved to %d,%d", at.cx, at.cy)
      else
        S.eventNotice = "pick a cell on the map first"
      end
    end
    fy = fy + fieldH + 10 * s
  end

  -- ONCE. See MapEvents' note on the `once` gate: an event tile with no memory
  -- fires every time the player crosses it, which for "the rival stops you at
  -- the gate" is the rival stopping you forever.
  local once = ev.once and true or false
  if Kit.checkbox(x, fy, w, 22 * s, once, "only the first time") then
    ev.once = not once
    MapEvents.save(S, S.mapId, ev)
  end
  fy = fy + 26 * s
  if ev.once and (not ev.flag or ev.flag == "") then
    Kit.text("small", "give it a flag below, or it cannot remember", x, fy,
             PAL.yellow)
    fy = fy + 16 * s
  end

  Kit.text("small", "WHEN IT FINISHES IT SETS", x, fy, PAL.muted)
  fy = fy + 16 * s
  -- THROUGH `flagLabel`, LIKE THE FLAGS TAB.
  --
  -- These two buttons printed the raw name, so a reader who picked a flag from
  -- a list of readable names ("Azalea gym cleared") saw it come back as
  -- EVENT_G2_0142 the moment it landed in a condition -- the same flag under
  -- two names, in two tabs of one menu, with nothing to say they were the same
  -- thing. The FLAGS tab has always done this; these were simply missed.
  if Kit.button(x, fy, w, fieldH,
                Kit.ellipsize("small",
                              ev.flag and MapEvents.flagLabel(ev.flag)
                                or "(no flag)", w - 12 * s),
                { font = "small" }) then
    S.eventFlagPick = { event = ev, key = "flag" }
    S.eventTab = "flags"
  end
  fy = fy + fieldH + 12 * s

  -- CONDITIONS. Every one of them means the same thing -- do not run -- which
  -- is why they lower to one exit label rather than one each.
  Kit.text("small", "ONLY WHEN", x, fy, PAL.muted)
  fy = fy + 16 * s
  for i, cond in ipairs(ev.requires or {}) do
    Kit.text("small", tostring(i) .. ".", x, fy + 6 * s, PAL.muted)
    if Kit.button(x + 20 * s, fy, w - 130 * s, fieldH,
                  Kit.ellipsize("small",
                                cond.flag and MapEvents.flagLabel(cond.flag)
                                  or "(pick a flag)",
                                w - 142 * s), { font = "small" }) then
      S.eventFlagPick = { cond = cond, key = "flag", event = ev }
      S.eventTab = "flags"
    end
    if Kit.button(x + w - 106 * s, fy, 78 * s, fieldH,
                  (cond.state == false) and "is NOT set" or "is set",
                  { font = "small" }) then
      cond.state = (cond.state == false) and true or false
      MapEvents.save(S, S.mapId, ev)
    end
    if Kit.button(x + w - 24 * s, fy, 24 * s, fieldH, "x",
                  { font = "small", radius = 5 * s }) then
      table.remove(ev.requires, i)
      MapEvents.save(S, S.mapId, ev)
      break
    end
    fy = fy + fieldH + 4 * s
  end
  if Kit.button(x, fy, w, fieldH - 2 * s, "+ CONDITION", { font = "small" }) then
    ev.requires[#ev.requires + 1] = { flag = nil, state = true }
    MapEvents.save(S, S.mapId, ev)
  end
  fy = fy + fieldH + 12 * s

  -- WHAT THE ENGINE WILL ACTUALLY RUN, checked by the engine's own validator.
  -- An editor that passed a script the game refuses moves the discovery to the
  -- one moment it cannot be fixed.
  local ok, problems, rows = MapEvents.validate(ev, S.mapId)
  Kit.text("small", string.format("%d script row%s", #rows,
           #rows == 1 and "" or "s"), x, fy, ok and PAL.muted or PAL.red)
  fy = fy + 16 * s
  if not ok then
    for _, why in ipairs(problems or {}) do
      Kit.text("small", Kit.ellipsize("small", tostring(why), w), x, fy,
               PAL.red)
      fy = fy + 14 * s
    end
  end
end

local function drawFlags(S, Kit, x, y, w, h)
  local s = Kit.scale
  local fy = y
  local fieldH = 28 * s

  local pick = S.eventFlagPick
  if pick then
    Kit.text("small", "pick a flag, or make one", x, fy, PAL.yellow)
    fy = fy + 16 * s
  end

  S.eventNewFlag = Kit.textfield("ev-newflag", x, fy, w - 80 * s, fieldH,
                                 S.eventNewFlag or "", "house_unlock_door")
  if Kit.button(x + w - 76 * s, fy, 76 * s, fieldH, "MAKE",
                { font = "small", kind = "accent" }) then
    local name, why = MapEvents.addFlag(S, S.eventNewFlag)
    if name then
      S.eventNewFlag = ""
      S.eventNotice = name .. " created"
      if pick then EventMenu.assignFlag(S, name) end
    else
      S.eventNotice = tostring(why)
    end
  end
  fy = fy + fieldH + 4 * s
  Kit.text("small", "spaces become underscores; a flag is just a name",
           x, fy, PAL.muted)
  fy = fy + 18 * s

  S.eventFlagQuery = Kit.textfield("ev-flagq", x, fy, w, fieldH,
                                   S.eventFlagQuery or "", "search flags...")
  fy = fy + fieldH + 6 * s

  local mine = {}
  for _, f in ipairs(MapEvents.flags(S)) do mine[f] = true end
  local all = MapEvents.knownFlags(S, 400)
  local hits = {}
  for _, f in ipairs(all) do
    if MapEvents.flagMatches(f, S.eventFlagQuery) then hits[#hits + 1] = f end
  end
  local rowH = 24 * s
  local perPage = math.max(1, math.floor((y + h - fy) / rowH))
  local maxS = math.max(0, #hits - perPage)
  S.eventFlagScroll = math.max(0, math.min(S.eventFlagScroll or 0, maxS))
  if #hits == 0 then
    Kit.text("small", "no flags yet - make one above", x, fy, PAL.muted)
    return
  end
  Kit.pushClip(x, fy, w, y + h - fy)
  for i = S.eventFlagScroll + 1,
          math.min(#hits, S.eventFlagScroll + perPage) do
    local name = hits[i]
    local delW = mine[name] and 24 * s or 0
    -- THE NAME, NOT THE BIT INDEX. `EVENT_G2_1600` is what gets stored and
    -- what every script and imported save agrees on; it is also opaque, and
    -- choosing which flag gates a door out of a list of numbers is guesswork.
    -- See MapEvents.flagLabel.
    local label = MapEvents.flagLabel(name)
    if label ~= name then label = label .. "   (" .. name .. ")" end
    -- WHEN THIS TAB IS BEING USED AS A PICKER, a row is the answer to a
    -- question and pressing it should answer. Reached any other way it is a
    -- list of flags to INSPECT -- so the row opens the flag rather than
    -- assigning it nowhere.
    if Kit.button(x, fy, w - delW - (delW > 0 and 4 * s or 0), rowH - 2 * s,
                  Kit.ellipsize("small", label, w - 20 * s),
                  { font = "small",
                    kind = (S.flagOpen == name) and "accent" or nil }) then
      if pick then
        EventMenu.assignFlag(S, name)
      else
        S.flagOpen = (S.flagOpen ~= name) and name or nil
      end
    end
    -- Only flags this project invented can be dropped: the cartridge's are
    -- shown so they can be USED, and removing one from a list it is not in
    -- would be a button that lies.
    if delW > 0 and Kit.button(x + w - delW, fy, delW, rowH - 2 * s, "x",
                               { font = "small", radius = 4 * s }) then
      MapEvents.removeFlag(S, name)
    end
    fy = fy + rowH
    if not pick and S.flagOpen == name then
      fy = EventMenu.drawFlagUses(S, Kit, name, x, fy, w, y + h)
    end
  end
  Kit.popClip()
end

-- WHO IS WATCHING THIS FLAG, and the one link worth editing from here.
--
-- THE HONEST ANSWER TO "WHAT RULE DOES THIS FLAG RUN". None: `setevent` and
-- `clearevent` lower to a bit write and nothing else -- the cartridge has no
-- on-set hook. Everything a flag does is done by the things READING it, so
-- this lists them. See MapEvents.flagUses.
--
-- THE OBJECT LINK IS INVERTED and it is the thing people get wrong: an object
-- carrying `eventFlag` is HIDDEN while that flag is SET. So "set the flag to
-- remove the guard" is right and "set the flag to spawn the guard" is exactly
-- backwards -- which is why the row says which way round it is rather than
-- printing the field name.
function EventMenu.drawFlagUses(S, Kit, name, x, fy, w, bottom)
  local s = Kit.scale
  local pad = 12 * s
  -- THE WHOLE GAME, not the open map.
  --
  -- This asked `flagUses`, which answers for one map -- while the list it sits
  -- in is built by walking EVERY map. So six hundred world-wide flags were
  -- answered map-locally and almost every one said "nothing watches this yet",
  -- which is true of the open map and false of the game. See
  -- MapEvents.flagIndex: one pass, bucketed by flag, cached against the edit
  -- stamp.
  local row = MapEvents.flagWatchers(S, name)
  local function line(text, col)
    if fy > bottom - 14 * s then return false end
    Kit.text("small", Kit.ellipsize("small", text, w - pad - 6 * s),
             x + pad, fy, col or PAL.muted)
    fy = fy + 14 * s
    return true
  end

  if row.total == 0 then
    line("nothing anywhere in the game reads this flag yet", PAL.muted)
  else
    line(string.format("%d watcher%s across %d map%s", row.total,
                       row.total == 1 and "" or "s", #row.maps,
                       #row.maps == 1 and "" or "s"), PAL.caption)
  end

  -- THE OPEN MAP FIRST, and named as such: it is the one whose objects the
  -- reader can actually see and change from here.
  local here = row.byMap[S.mapId]
  local function detail(m, indent)
    for _, obj in ipairs(m.objects) do
      line(indent .. string.format("hides %s #%s while set",
                                   tostring(obj.name or obj.sprite or "object"),
                                   tostring(obj.index or "?")))
    end
    for _, door in ipairs(m.doors) do
      line(indent .. string.format("opens the door at %s,%s when set",
                                   tostring(door.bx), tostring(door.by)))
    end
    for _, e in ipairs(m.events) do
      line(indent .. string.format("%s %s",
                                   tostring(e.event.name or e.event.id), e.how))
    end
    for _, t in ipairs(m.trainers) do
      line(indent .. string.format("marks trainer #%s beaten", tostring(t.index)))
    end
  end

  if here then
    line("on this map:", PAL.caption)
    detail(here, "  ")
  end

  local others = 0
  for _, m in ipairs(row.maps) do
    if m.id ~= S.mapId then others = others + 1 end
  end
  if others > 0 then
    line(string.format("elsewhere (%d map%s):", others,
                       others == 1 and "" or "s"), PAL.caption)
    local shown = 0
    for _, m in ipairs(row.maps) do
      if m.id ~= S.mapId then
        if shown >= 6 then
          line(string.format("  ...and %d more", others - shown))
          break
        end
        if fy <= bottom - 16 * s then
          -- OPENS THAT MAP. Being told a flag matters somewhere else and then
          -- having to find it in the list is the half that gets skipped.
          if Kit.button(x + pad, fy - 2 * s, w - pad - 6 * s, 16 * s,
                        Kit.ellipsize("small",
                          string.format("  %s  -  %d watcher%s", m.id, m.n,
                                        m.n == 1 and "" or "s"),
                          w - pad - 20 * s),
                        { font = "small", kind = "ghost" }) then
            S.mapId = m.id
            S._pvCenteredFor = nil
            S.eventNotice = "opened " .. m.id
          end
          fy = fy + 16 * s
          shown = shown + 1
        end
      end
    end
  end

  -- THE EDITABLE HALF. Attaching a flag to an object is the lever behind
  -- "unlock the door" and "remove the NPC blocking the path" -- the two things
  -- this whole flag system was asked for -- and it lived only in the objects
  -- panel, one selection at a time, with no way to see what a flag already
  -- touched.
  --
  -- THE LINK IS INVERTED and it is the thing people get wrong: an object
  -- carrying `eventFlag` is HIDDEN while that flag is SET. So "set the flag to
  -- remove the guard" is right and "set the flag to spawn the guard" is exactly
  -- backwards -- which is why the button says which way round it is rather than
  -- naming the field.
  local sel = S.objSelected
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  local obj = def and def.objects and def.objects[sel] or nil
  if obj and fy + 24 * s < bottom then
    local already = (obj.eventFlag == name)
    local label = already
      and string.format("STOP HIDING %s WITH THIS",
                        tostring(obj.name or obj.sprite or "the selected NPC"))
      or string.format("HIDE %s WHILE THIS IS SET",
                       tostring(obj.name or obj.sprite or "the selected NPC"))
    if Kit.button(x + pad, fy, w - pad - 6 * s, 22 * s,
                  Kit.ellipsize("small", label, w - pad - 20 * s),
                  { font = "small", kind = already and "ghost" or "accent" })
    then
      local okOB, Objects = pcall(require, "tools.map-editor.panels.Objects")
      if okOB and Objects.writeField then
        Objects.writeField(S, obj, "eventFlag", (not already) and name or nil)
        S.eventNotice = already
          and "that NPC no longer follows this flag"
          or "that NPC is now hidden whenever this flag is set"
      end
    end
    fy = fy + 26 * s
  elseif fy + 16 * s < bottom then
    line("select an NPC in the NPCs panel to attach this flag to one",
         PAL.muted)
  end
  return fy + 4 * s
end

-- Put the picked flag wherever the pick came from, and go back.
function EventMenu.assignFlag(S, name)
  local pick = S.eventFlagPick
  if not pick then return false end
  local target = pick.cond or pick.beat or pick.event
  if target then target[pick.key or "flag"] = name end
  local ev = pick.event or current(S)
  if ev then MapEvents.save(S, S.mapId, ev) end
  S.eventFlagPick = nil
  S.eventTab = pick.cond and "when" or (pick.beat and "beats" or "when")
  return true
end

-- ---------------------------------------------------------------------------
-- the popup
-- ---------------------------------------------------------------------------

function EventMenu.draw(S, Kit)
  if not (S and S.eventMenuOpen) then return false end
  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 14 * s

  local pw = math.min(winW - 40 * s, 900 * s)
  local ph = math.min(winH - 40 * s, 660 * s)
  local px0 = math.floor((winW - pw) / 2)
  local py0 = math.floor((winH - ph) / 2)

  -- Before any widget of this popup: the swallow only reaches what is drawn
  -- after it. See Kit.tapAway.
  local tapped = Kit.tapAway("event-menu", px0, py0, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.55)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 12 * s, 12 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)

  local x = px0 + pad
  local y = py0 + pad
  local w = pw - 2 * pad
  Kit.caption(x, y, "EVENTS - " .. tostring(S.mapId or "no map"))
  if Kit.button(px0 + pw - pad - 28 * s, y - 4 * s, 28 * s, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.eventMenuOpen = false
    return true
  end
  y = y + Kit.textHeight("caption") + 8 * s

  S.eventTab = S.eventTab or "list"
  local tw = (w - 18 * s) / #EventMenu.TABS
  for i, t in ipairs(EventMenu.TABS) do
    if Kit.chip(x + (i - 1) * (tw + 6 * s), y, tw, 26 * s, t.label,
                S.eventTab == t.id) then
      S.eventTab = t.id
    end
  end
  y = y + 26 * s + 10 * s

  local bodyH = (py0 + ph - pad - 20 * s) - y
  -- THE EVENT LIST STAYS ON SCREEN WHILE THE OTHER PANES ARE OPEN. Building an
  -- event is going back and forth between what it does and when it runs, and a
  -- list you have to leave to do either is a list you lose your place in.
  local listW = math.min(300 * s, w * 0.38)
  if S.eventTab == "list" then
    drawList(S, Kit, x, y, w, bodyH)
  else
    drawList(S, Kit, x, y, listW, bodyH)
    local rx = x + listW + 12 * s
    local rw = w - listW - 12 * s
    if S.eventTab == "beats" then
      drawBeats(S, Kit, rx, y, rw, bodyH)
    elseif S.eventTab == "when" then
      drawWhen(S, Kit, rx, y, rw, bodyH)
    else
      drawFlags(S, Kit, rx, y, rw, bodyH)
    end
  end

  if S.eventNotice then
    Kit.text("small", Kit.ellipsize("small", S.eventNotice, w),
             x, py0 + ph - pad - 14 * s, PAL.yellow)
  end

  if tapped then S.eventMenuOpen = false end
  return true
end

function EventMenu.wheelmoved(S, dy)
  if not (S and S.eventMenuOpen) then return false end
  if S.eventTab == "beats" then
    S.eventBeatScroll = math.max(0, (S.eventBeatScroll or 0) - (dy or 0) * 24)
  elseif S.eventTab == "flags" then
    S.eventFlagScroll = math.max(0, (S.eventFlagScroll or 0) - (dy or 0))
  else
    S.eventScroll = math.max(0, (S.eventScroll or 0) - (dy or 0))
  end
  return true
end

function EventMenu.keypressed(S, key)
  if not (S and S.eventMenuOpen) then return false end
  if key == "escape" then
    if S.eventFlagPick then
      S.eventFlagPick = nil
    else
      S.eventMenuOpen = false
    end
    return true
  end
  return true
end

return EventMenu
