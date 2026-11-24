-- Round 32 / 33: what a Kinstone fusion shows after the fusion window
-- (src/menu/kinstoneMenu.c KinstoneMenu_Type2 -> MenuFadeIn(subtask,
-- worldEventId); src/subtask/subtaskWorldEvent.c, src/worldEvent/*.c,
-- src/subtask/subtaskLocalMapHint.c).  Listed in R27B.MODULES (frame /
-- draw); started from one line in KinstoneMenu's KM:exit (state 6, fused).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * KinstoneMenu_Type2 with the fusion done: gKinstoneWorldEvents[id]
--     .subtask != 0 -> MenuFadeIn(that subtask, worldEventId) before the
--     fuser's "fusing" message.
--   * SUBTASK_WORLDEVENT (8): the event's room as an auxiliary room (no
--     player), scroll origin + (offsetX, offsetY); then
--     gWorldEventFunctions[type] -- the patterns (round 33):
--       - 0: fade in, TEXT_EMPTY $01, 120 frames.
--       - 1 / 3 / 11 / 24: the room, then sub_0801876C(id, 1) (the entity
--         appears) and sub_080553E0 (FX_BIG_EXPLOSION2 at the event's x / y);
--         type 1 with a white flash; 180 (1, 11) / 120 frames.
--       - 2: the closed chest tile (TILE_TYPE_115) + the FX + SFX_SECRET_BIG.
--       - 4 / 6 / 7 / 8 / 9: the room as it is before (sub_0801876C(id, 0):
--         the blockers of Fusion33.tiles, or TREE_THORNS), a white fade out
--         and in (FADE_IN_OUT | FADE_BLACK_WHITE), the room again as it is
--         after (sub_08054974 reload / sub_0801876C(id, 1)), the FX (not 4)
--         and SFX_SECRET_BIG; 120 frames.
--       - 10 (WorldEvent_Beanstalk): the beanstalk's flag, BEANSTALK type 0
--         at the event's x / y, 390 frames: beanstalk.c -- the sprout plays
--         animation 0 three times, then animation 1 (SFX_198 every 17
--         frames), then the stalk (type 1) and the climbing top (type 2):
--         the top plays its animation, a leaf (types 4-6, gUnk_08120DFC) on
--         each frame flagged 1, and at the end a stalk section (type 3) and
--         climbs $38 px, until above the area.
--       - 25: the entity (type2 1), 120 frames.
--     Then Subtask_WorldEvent_End: the Kinstone's map marker != 0 ->
--     SUBTASK_LOCALMAPHINT, else a fade back to the field.
--   * SUBTASK_LOCALMAPHINT (subtaskLocalMapHint.c sub_080A6B04): the area
--     map of the region holding the event's world position (_c, _e:
--     GetOverworldLocation's windcrestId) as pause screen 6 draws it, BG3
--     filled with $5001, colours 0 / $5F = $475F, two markers: Link's
--     (100 / 101 + $100) and the event's (marker + 100); scrolled so the
--     event's y sits $3C below the top (at most unk2); 30 frames (SFX_103
--     at 1), then the markers blink and A / B / START leave.
-- SIMPLIFIED: entities other than the beanstalk play their animation 0 only
--   (no object code runs); the room init code (sub_0804B0E8) is not run
--   (round 34: worldEvent5's BG3 cloud overlay fade, WorldEvent34.lua); type 12-23 events show the room
--   for 120 frames.
local bit = require("bit")
local band = bit.band

local M = {}
M.SUBTASK_WORLDEVENT = 8
M.SUBTASK_LOCALMAPHINT = 10
local TEXT_EMPTY_01 = 0x0001
local SFX_SECRET_BIG, SFX_198, SFX_103 = 0x73, 0x198, 0x103
local WE_TABLES = { [1] = 0x080FEC28, [3] = 0x080FEBE8, [7] = 0x080FECC8, [9] = 0x080FEE78, [25] = 0x080FED18,
                    [11] = 0x080FED58 }
local SPECIAL_FX, FX_BIG_EXPLOSION2, BEANSTALK, TREE_THORNS = 0x0F, 0x43, 0x2C, 0x9E
-- the patterns of src/worldEvent/*.c
local FLASH_OUT = { [4] = true, [6] = true, [7] = true, [8] = true, [9] = true }
local FX_AT = { [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [9] = true, [11] = true, [24] = true }
local SECRET = { [2] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true }
local TIMER = { [1] = 180, [11] = 180, [10] = 390 }

-- ---------------------------------------------------------------------------
-- the view's entities
-- ---------------------------------------------------------------------------
local Anim = require("src.zelda.tmc.Anim")

local function newEnt(c, f, id, form, anim, x, y, gfxSrc)
  local O = f:objects()
  local d = O and O:def(id, form)
  if not d then return nil end
  local A = f.assets
  local spr = A:sprite(d.sprite)
  local e = { def = d, sprite = d.sprite, spr = spr, x = x, y = y, prio = 4, anim = Anim.new(), flipX = false,
              pal = A:objPalette(d.palette, c.room.atlas and c.room.atlas.palettes),
              gfx = gfxSrc or require("src.zelda.tmc.Assets").gfxSource(d.gfxType, d.gfx), timer = 0, sub = 0, form = form }
  if not (spr and spr.anims and spr.anims[anim]) then anim = 0 end
  e.anim:set(spr, anim, true)
  c.ents[#c.ents + 1] = e
  return e
end
local function setAnim(e, n) e.anim:set(e.spr, n, true) end
local function lastKey(e) return band(e.anim.flags or 0, 0x80) ~= 0 end

-- beanstalk.c (round 33)
local E14 = require("src.zelda.tmc.RomTables").t("Fusion32.E14") -- gUnk_08120E14
local DFC = require("src.zelda.tmc.RomTables").t("Fusion32.DFC") -- gUnk_08120DFC {type, x, y, flipX}
local stalkUpdate

-- LoadGfxGroup($11): OBJ tiles for the stalk / leaves (spriteVramOffset $1C0)
local function stalkGfx(f)
  local A = f.assets
  if A.stalkGfx33 ~= nil then return A.stalkGfx33 or nil end
  A.objVram = A.objVram or A.store:read("objvram.bin") or ""
  local list = A.manifest.gfxGroups and A.manifest.gfxGroups[0x11]
  local blob = A.store:read("gfxgroups.bin") or ""
  local vram = A.objVram
  for _, it in ipairs(list or {}) do
    local dest, off, len = it[1], it[2], it[3]
    if dest >= 0x06010000 and dest < 0x06018000 then
      local o = dest - 0x06010000
      if #vram < o + len then vram = vram .. string.rep("\0", o + len - #vram) end
      vram = vram:sub(1, o) .. blob:sub(off + 1, off + len) .. vram:sub(o + len + 1)
    end
  end
  A.stalkGfx33 = list and { raw = vram, first = 0x1C0, key = "stalk33" } or false
  return A.stalkGfx33 or nil
end

local function newStalk(c, f, typ, x, y)
  local gfx = (typ ~= 0) and stalkGfx(f) or nil
  local e = newEnt(c, f, BEANSTALK, typ, E14[typ][1], x, y, gfx)
  if not e then return nil end
  e.stalk, e.prio = typ, E14[typ][2]
  stalkUpdate(c, f, e) -- Beanstalk_Init ends with Beanstalk_Action1
  return e
end

local function soundTimer(f, e)
  if e.timer == 0 then e.timer = 16; f:sound(SFX_198) else e.timer = e.timer - 1 end
end

function stalkUpdate(c, f, e)
  local t = e.stalk
  if t == 0 then
    if e.sub == 0 then
      e.anim:update(1)
      if lastKey(e) then
        if e.timer < 2 then e.timer = e.timer + 1
        else setAnim(e, 1); e.timer = 16; e.sub = 1 end
      end
    elseif e.sub == 1 then
      soundTimer(f, e)
      e.anim:update(1)
      if lastKey(e) then
        newStalk(c, f, 1, e.x, e.y)
        newStalk(c, f, 2, e.x, e.y - 16)
        e.hidden = true
        e.sub = 2
      end
    else
      soundTimer(f, e)
    end
  elseif t == 2 then
    e.anim:update(1)
    if band(e.anim.flags or 0, 1) ~= 0 then
      local d = DFC[e.timer]
      local l = newStalk(c, f, d[1], e.x + d[2], e.y - d[3])
      if l then l.flipX = d[4] end
      e.timer = e.timer + 1
      if e.timer > 5 then e.timer = 0 end
    end
    if lastKey(e) then
      newStalk(c, f, 3, e.x, e.y)
      e.y = e.y - 0x38
      if (c.room.y or 0) + e.y < 0 then e.deleted = true end
    end
  elseif t >= 4 and t <= 6 then
    if not lastKey(e) then e.anim:update(1) end
  end
end

-- ---------------------------------------------------------------------------
-- start (KM:exit(6): the fused Kinstone `id`)
-- ---------------------------------------------------------------------------
local function loadRoom(f, we)
  local ok, room = pcall(require("src.zelda.tmc.Room").load, f.assets, we.area, we.room)
  if ok then return room end
  return nil
end

local function eventEntity(c, f, typ, form)
  local base = WE_TABLES[typ]
  if not base then return nil end
  local l = f:entityListAt(base + 16 * (c.we.entity or 0))
  local d = l and l[1]
  if not (d and d.kind == 6) then return require("src.zelda.tmc.WorldEvent37").other(c, f, d, typ, newEnt) end -- round 37: a golden enemy (type 1)
  local e = newEnt(c, f, d.id, form or d.paramA or 0, 0, d.x, d.y)
  if e then require("src.zelda.tmc.WorldEvent37").attach(c, f, e, d, typ) end -- round 37: the object's own code in the view
  return e
end

-- the room as sub_0801876C(id, fused) leaves it (the view's copy)
local function stateTiles(c, f, fused)
  local F33 = require("src.zelda.tmc.Fusion33")
  pcall(F33.tiles, f.assets, c.room, c.weId, c.we, fused, function() return false end)
end

function M.start(f, id)
  local K = f.kinstone
  local data = K and K.data
  local ev = data and data.events and data.events[id]
  if not ev or ev.subtask ~= M.SUBTASK_WORLDEVENT then return false end
  local we = data.world and data.world[ev.worldEvent]
  if not we then return false end
  local room = loadRoom(f, we)
  if not room then return false end
  local c = { we = we, ev = ev, id = id, weId = ev.worldEvent, room = room, phase = 0, t = 0, black = 16, white = 0,
              whiteDir = 0, out = 0, ents = {} }
  c.camX, c.camY = we.scrollX or 0, we.scrollY or 0
  local t = we.type
  -- the "before" picture
  stateTiles(c, f, false)
  if t == 7 and we.entity ~= 0x80 then c.before = eventEntity(c, f, 7) end
  if t == 25 then local e = eventEntity(c, f, 25, 0); if e then e.type2 = 1 end end
  if t == 10 then
    -- WorldEvent_Beanstalk_0: SetLocalFlagByBank(gLocalFlagBanks[bank], flag)
    local BANK = f.BANK_OFFSET or require("src.zelda.tmc.Field").BANK_OFFSET
    if BANK and BANK[we.bank or 0] then pcall(f.setFlag, f, "bank", we.flag or 0, true, BANK[we.bank]) end
  end
  if t == 5 then stateTiles(c, f, true); require("src.zelda.tmc.WorldEvent34").start(c, f) end -- round 34: WorldEvent_5_0
  f.fusion32 = c
  return true
end

-- the change (WorldEvent_n's middle step)
local function change(c, f)
  local t, we = c.we.type, c.we
  if FLASH_OUT[t] then
    -- sub_08054974(id, 0): the room again; sub_0801876C(id, 1)
    local r = loadRoom(f, we)
    if r then c.room = r end
    if c.before then for i, e in ipairs(c.ents) do if e == c.before then table.remove(c.ents, i) break end end end
    c.before = nil
    stateTiles(c, f, true)
    if t == 9 then eventEntity(c, f, 9) end
  elseif t == 2 or t == 5 then
    stateTiles(c, f, true)
  elseif t == 1 or t == 3 or t == 11 then
    eventEntity(c, f, t)
  elseif t == 10 then
    newStalk(c, f, 0, we.x, we.y)
  end
  if FX_AT[t] then
    local fx = newEnt(c, f, SPECIAL_FX, FX_BIG_EXPLOSION2, FX_BIG_EXPLOSION2, we.x, we.y)
    if fx then fx.fx, fx.prio = true, 0 end
  end
  if SECRET[t] then f:sound(SFX_SECRET_BIG) end
  if t == 1 or FLASH_OUT[t] then c.white, c.whiteDir = 16, -1 end -- FADE_BLACK_WHITE | FADE_INSTANT: from white
  c.timer = TIMER[t] or 120
end

local function press(input)
  local p = {}
  for _, k in ipairs({ "a", "b", "up", "down", "left", "right" }) do p[k] = input and input.pressed and input.pressed(k) or false end
  return p
end

-- ---------------------------------------------------------------------------
-- the local map hint (subtaskLocalMapHint.c)
-- ---------------------------------------------------------------------------
local function hintStart(f, c)
  local MM = require("src.zelda.tmc.MapMenu")
  local Menu = require("src.zelda.tmc.Menu")
  local p0 = require("src.zelda.tmc.Ppu")
  local wt = p0.table({ A = f.assets }, "worldEvents")
  if not wt then return nil end
  local a = wt.base + 20 * c.weId
  local mx, my = wt.u16(a + 12), wt.u16(a + 14)
  local loc = MM.location(p0.table({ A = f.assets }, "overworldLocs"), mx, my)
  if not loc then return nil end
  local m = Menu.new(f)
  m.screen = 6
  local ok = pcall(function()
    -- sub_080A4D34 / sub_080A4DB8(6) / sub_080A67C4(region)
    m:openMenu()
    m.mapPpu = m.ppu
    m.cursors[4] = loc.id
    m:setScreen(6)
  end)
  if not ok or not m.ppu then return nil end
  local p = m.ppu
  m.ui.elements = {} -- (MemClear(gHUD.elements): no KeyButtonLayout here)
  p:setColor(0, 0x475F); p:setColor(0x5F, 0x475F)
  for i = 0, 0x7FF do p:set16(p.bg[3].buf + 2 * i, 0x5001) end
  p.bg[3].updated = true
  -- the two markers (sub_080A698C)
  local st = MM.mapStatus(f)
  local list = {}
  local function add(x, y, v)
    local px, py = MM.regionPos(m, loc.id, x, y)
    if px then list[#list + 1] = { blink = bit.rshift(v, 8), frame = band(v, 0xFF), sprite = 0x1FB, x = px, y = py } end
    return py
  end
  add(st.owx or 0, st.owy or 0, (f.player.hasCap and 100 or 101) + 0x100)
  local py = add(mx, my, (c.ev.marker or 0) + 100)
  m.hintMarkers = list
  m.mapMarkers = {}
  m.scroll = 0
  local e = m.region
  if e and e.u2 ~= 0 and py then
    local v = py - 0x3C
    if v > 0 then m.scroll = math.min(v, e.u2) end
  end
  m.state = 2
  pcall(MM.showAreaName, m, loc.id, 2) -- ShowAreaName(r, 2)
  return { m = m, timer = 30, fade = 8 }
end

local function hintFrame(f, h, input)
  if h.fade > 0 then h.fade = h.fade - 1 return true end
  h.m.ticks = (h.m.ticks or 0) + 1
  h.m.mapTicks = (h.m.mapTicks or 0) + 1
  if h.timer == 0 then
    h.m.mapMarkers = h.m.hintMarkers -- sub_080A66D0
    if input and (input.pressed("a") or input.pressed("b") or input.pressed("start")) then return false end
    return true
  end
  if h.timer == 1 then f:sound(SFX_103) end
  h.timer = h.timer - 1
  return true
end

local function hintDraw(h)
  local MM = require("src.zelda.tmc.MapMenu")
  local m = h.m
  m.ppu:flush()
  pcall(MM.draw, m)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(MM.compose, m)
  if h.fade > 0 then
    love.graphics.setColor(0, 0, 0, h.fade / 8)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end
M._hintStart = hintStart

-- ---------------------------------------------------------------------------
-- frame / draw
-- ---------------------------------------------------------------------------
function M.frame(f, input)
  local c = f.fusion32
  if not c then return false end
  c.t = c.t + 1
  if c.hint then
    if not hintFrame(f, c.hint, input) then c.hint = nil; c.phase = 5; c.out = 16 end
    return true
  end
  if f.textbox then
    f.textbox:update(press(input))
    if f.textbox.done then f.textbox = nil end
  end
  if c.black > 0 and c.phase < 4 then c.black = c.black - 1 end
  if c.whiteDir ~= 0 then
    c.white = c.white + c.whiteDir
    if c.white >= 16 then c.white, c.whiteDir = 16, 0 elseif c.white <= 0 then c.white, c.whiteDir = 0, 0 end
  end
  -- UpdateEntities
  for i = #c.ents, 1, -1 do
    local e = c.ents[i]
    if e.stalk then stalkUpdate(c, f, e)
    elseif e.viewUpdate then e.viewUpdate(c, f, e) -- round 37 (WorldEvent37.lua)
    elseif not e.static then e.anim:update(1) end
    if e.fx and e.anim.done then e.deleted = true end
    if e.deleted then table.remove(c.ents, i) end
  end
  local t = c.we.type
  if c.phase == 0 then
    if c.black == 0 then
      if t == 0 then
        f:message(TEXT_EMPTY_01)
        c.timer, c.phase = 120, 2
      elseif FLASH_OUT[t] then
        c.whiteDir, c.phase = 1, 1 -- FADE_IN_OUT | FADE_BLACK_WHITE: out to white
      else
        change(c, f)
        c.phase = 2
      end
    end
  elseif c.phase == 1 then
    if c.white >= 16 and c.whiteDir == 0 then change(c, f); c.phase = 2 end
  elseif c.phase == 2 then
    if c.we5 and c.we5.phase ~= 3 then -- round 34: worldEvent5's cloud overlay (WorldEvent34.lua)
      require("src.zelda.tmc.WorldEvent34").frame(c, f)
      if c.we5.phase == 3 then c.timer = 1 end
      return true
    end
    if not f.textbox and c.whiteDir == 0 and not c.hold37 then -- round 37: an entity still running its event (WorldEvent37)
      c.timer = c.timer - 1
      if c.timer <= 0 then
        -- Subtask_WorldEvent_End
        if (c.ev.marker or 0) ~= 0 then
          local ok, h = pcall(hintStart, f, c)
          if ok and h then c.hint = h; return true end
        end
        c.phase, c.out = 5, 16
      end
    end
  else
    c.out = c.out - 1
    if c.out <= 0 then f.fusion32 = nil end
  end
  return true
end

local function drawEnt(f, c, e)
  if e.hidden then return end
  local frame = e.frameOverride or e.anim.frame -- round 37: a frameIndex set by the object's code
  if not frame or frame == 0xFF then return end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(e.sprite, frame, e.pal, "we33:" .. tostring(e.def.palette), e.gfx)
  if not img then return end
  local x, y = math.floor(e.x - c.camX), math.floor(e.y - c.camY)
  if e.anim:hflip() ~= (e.flipX or false) then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

function M.draw(f)
  local c = f.fusion32
  if not c then return end
  if c.hint then hintDraw(c.hint) return end
  local g = love.graphics
  local r = c.room
  local bd = r:backdrop()
  g.setColor(bd[1] or 0, bd[2] or 0, bd[3] or 0, 1)
  g.rectangle("fill", 0, 0, 240, 160)
  g.setColor(1, 1, 1, 1)
  pcall(r.drawLayer, r, "bottom", c.camX, c.camY)
  -- DrawEntities: a lower spritePriority on top, then the lower y
  local list = {}
  for _, e in ipairs(c.ents) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    return a.y < b.y
  end)
  for _, e in ipairs(list) do pcall(drawEnt, f, c, e) end
  pcall(r.drawLayer, r, "top", c.camX, c.camY)
  if c.we5 then pcall(require("src.zelda.tmc.WorldEvent34").draw, c, f) end -- round 34: worldEvent5's BG3
  local a = c.black / 16
  if c.phase == 5 then a = 1 - math.max(0, c.out) / 16 end
  if a > 0 then g.setColor(0, 0, 0, a); g.rectangle("fill", 0, 0, 240, 160) end
  if c.white > 0 then g.setColor(1, 1, 1, c.white / 16); g.rectangle("fill", 0, 0, 240, 160) end
  g.setColor(1, 1, 1, 1)
end

return M
