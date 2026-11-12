-- The pause MAP pages (src/menu/pauseMenu.c screens 4 and 5,
-- pauseMenuScreen6.c screen 6; common.c DrawDungeonFeatures /
-- DrawDungeonMap; game.c UpdateWindcrests; gameUtils.c
-- UpdatePlayerMapCoords / UpdatePlayerRoomStatus), drawn through Ppu.lua.
--
--  4  world map: the regions (gUnk_08128DE8), clouds over regions not yet
--     visited (OBJs in OBJ-window mode, WINOUT $3D3F hides BG1 under them),
--     Link's marker, the region cursor, the region name (ShowAreaName).
--  5  dungeon map: room outlines from gMapData drawn as 4bpp pixels into
--     gDungeonMap (char data at $06006000), colour 8 for the current room
--     (palette entries 200-207 rotate every 8 frames), the floor list,
--     Link's floor, map / big key / compass icons, compass markers (chests,
--     boss, entrance), the dungeon name.
--  6  area map: one region's map (gfx group $5F + region, palette group
--     $BA + region), scrolled with up / down, Link's and fusion markers; BG3
--     switches priority per scanline (an HBlank DMA to BG3CNT) so the map
--     only shows inside its window.
--
-- Menu.lua owns the page machinery (fades, {START, L, R, B} tables); it
-- calls init / update / draw / compose here for screens 4-6.

local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local Layout = require("src.zelda.tmc.Layout")

local MapMenu = {}

local SPRITE = 0x1FB          -- DRAW_DIRECT_SPRITE_INDEX (USA)
local SPRITE_ICONS = 0x144    -- SUB_080A5D1C_SPRITE_INDEX (USA)
local SPRITE_ITEMS = 0x142
local DUNGEON_MAP_VRAM = 0x06006000
local PAL_ROTATE = 200         -- gPaletteBuffer[200..207]

local AD = {
  keys5 = 0x08128D38, floorY = 0x08128D3C, scroll5 = 0x08128D43,
  keys4 = 0x08128DD4, layout4 = 0x08128DD8, regions = 0x08128DE8,
  keys6 = 0x08128E80, layout6 = 0x08128E84, region6 = 0x08128E94,
  hints = 0x08128F58, fontRegion = 0x08128FC0, fontDungeon = 0x08128FD8,
  dungeonNames = 0x08128FF0,
}
MapMenu.AD = AD

-- ---------------------------------------------------------------------------
-- field side: what the cartridge keeps in gRoomTransition.player_status
-- and gSave.windcrests
-- ---------------------------------------------------------------------------
local function mapStatus(field)
  local s = field.save
  s.mapStatus = s.mapStatus or {}
  return s.mapStatus
end
MapMenu.mapStatus = mapStatus

local function areaFlags(field)
  local info = field.room and field.room.areaInfo
  return info and info.flags or 0
end

-- AreaIsOverworld (USA: AR_ALLOWS_WARP | AR_IS_OVERWORLD) / AreaIsDungeon
function MapMenu.isOverworld(field) return areaFlags(field) == 0x81 end
function MapMenu.isDungeon(field) return band(rshift(areaFlags(field), 2), 1) == 1 end

-- gOverworldLocations: the location (windcrest id) of world pixel x, y
function MapMenu.location(data, x, y)
  if not data then return nil end
  x, y = math.floor(x / 16), math.floor(y / 16)
  for i = 0, 31 do
    local a = data.base + 8 * i
    local minX = data.u8(a)
    if minX == 0xFF then break end
    if minX <= x and data.u8(a + 2) >= x and data.u8(a + 1) <= y and data.u8(a + 3) >= y then
      return { id = data.u8(a + 4), minX = minX, minY = data.u8(a + 1), text = data.u16(a + 6) }
    end
  end
  return nil
end

-- the menu-data reader for a table without a Ppu (Ppu:table is a method
-- only for its `A` field)
local function tableOf(assets, name)
  return require("src.zelda.tmc.Ppu").table({ A = assets }, name)
end
MapMenu.tableOf = tableOf

-- UpdatePlayerMapCoords + UpdateWindcrests: every frame in the field
function MapMenu.track(field)
  local r, p = field.room, field.player
  if not (r and p) then return end
  local st = mapStatus(field)
  local x, y = r.x + math.floor(p.x), r.y + math.floor(p.y)
  if MapMenu.isOverworld(field) then
    st.owx, st.owy = x, y
    field._mapLocs = field._mapLocs or tableOf(field.assets, "overworldLocs") or false
    local loc = MapMenu.location(field._mapLocs or nil, x, y)
    if loc then field.save.windcrests = bor(field.save.windcrests or 0, lshift(1, loc.id)) end
  elseif MapMenu.isDungeon(field) then
    st.dmx, st.dmy = x, y
  end
end

-- room entry: LoadRoomVisitTile (the ROOM_VISIT_MARKER tile entity sets its
-- local flag) and UpdatePlayerRoomStatus's dungeon entrance
function MapMenu.roomEntered(field)
  local r = field.room
  if not r then return end
  for _, te in ipairs(r.tileEntities or {}) do
    if te.type == 1 then field:setFlag("local", te.flag, true) end
  end
  local st = mapStatus(field)
  local inDungeon = MapMenu.isDungeon(field)
  if inDungeon and not field._mapWasDungeon then
    st.darea, st.droom = r.area, r.room
    st.dx, st.dy = r.x + math.floor(field.player.x), r.y + math.floor(field.player.y)
  end
  field._mapWasDungeon = inDungeon
  MapMenu.track(field)
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function readLayout(t, a)
  local l = {}
  for i = 1, 9 do l[i] = t.u8(a + i - 1) end
  l.elements = {}
  local p = a + 9
  while t.u8(p) ~= 0xFF and #l.elements < 8 do
    l.elements[#l.elements + 1] = { t.u8(p), t.u8(p + 1) }
    p = p + 2
  end
  return l
end

local function keysAt(t, a) return { t.u8(a), t.u8(a + 1), t.u8(a + 2), t.u8(a + 3) } end

local function dungeonIdx(m)
  local info = m.field.room.areaInfo
  return (info and info.location or 0) - 23
end

-- ShowAreaName(windcrest / dungeon, type): the name into BG0 row $11
local function showAreaName(m, id, kind)
  local p, d2 = m.ppu, m.ppu:table("pauseData2")
  local text, font = 0, nil
  if kind == 0 and band(m.field.save.windcrests or 0, lshift(1, id)) == 0 then
    text = 0
  elseif kind == 0 or kind == 2 then
    local locs = p:table("overworldLocs")
    text = locs and locs.u16(locs.base + 8 * id + 6) or 0
    font = d2 and p:font("pauseData2", AD.fontRegion)
  elseif kind == 1 then
    text = d2 and d2.u16(AD.dungeonNames + 2 * id) or 0
    font = d2 and p:font("pauseData2", AD.fontDungeon)
  end
  if m.areaNameShown ~= text then
    m.areaNameShown = text
    p:fill(Layout.gBG0Buffer + 0x220 * 2, 0x100, 0)
    if band(text, 0xFF) ~= 0 and font then p:showTextBox(text, font) end
    p.bg[0].updated = true
  end
  p.bg[0].y = 2
end

local function dd(m, sprite, frame, x, y, _4, _8)
  m.ppu:drawDirect(sprite, frame, { x = x, y = y, _4 = _4 or 0, _6 = 0, _8 = _8 or 0 })
end

local function itemFrame(m, anim)
  local s = m.field.assets:sprite(SPRITE_ITEMS)
  local keys = s and s.anims[anim]
  return keys and keys[1] and keys[1][1]
end

-- ---------------------------------------------------------------------------
-- dungeon map (common.c)
-- ---------------------------------------------------------------------------
local function floorMeta(m, d)
  local t = m.ppu:table("dungeonFloors")
  if not t then return { numFloors = 1, highestFloor = 2, unk2 = 2 } end
  local a = t.base + 4 * d
  return { numFloors = t.u8(a), highestFloor = t.u8(a + 1), unk2 = t.u8(a + 2) }
end
MapMenu.floorMeta = floorMeta

local function hasCompass(m) return m.field._dungeon and m.field._dungeon:inventory(0x51) == 1 end
local function hasMap(m) return m.field._dungeon and m.field._dungeon:inventory(0x50) == 1 end    -- ITEM_DUNGEON_MAP
local function hasBigKey(m) return m.field._dungeon and m.field._dungeon:inventory(0x52) == 1 end -- ITEM_BIG_KEY

-- sub_0801DF10: the flag bank offset a layout room's flags live in
local function bankOffset(m, lay)
  if lay[4] == 1 then return 0x300 end
  local info = m.field.assets:area(lay[1])
  return m.field.BANK_OFFSET[info and info.flagBank or 0] or 0
end

local function roomHeader(m, area, room)
  local a = m.field.assets:area(area)
  return a and a.rooms and a.rooms[room]
end

-- IsRoomVisited
local function roomVisited(m, hdr, bank)
  for _, te in ipairs(hdr and hdr.tileEntities or {}) do
    if te.type == 1 then return m.field:flag("bank", te.flag, bank) end
  end
  return false
end

-- DrawMapPixel into gDungeonMap (16 tiles a row, 4bpp)
local function mapPixel(buf, x, y, color)
  if x < 0 or y < 0 or x > 127 or y > 127 then return end
  local o = ((rshift(y, 3) * 16 + rshift(x, 3)) * 32) + band(y, 7) * 4 + rshift(band(x, 7), 1)
  local b = buf[o + 1] or 0
  if band(x, 1) == 0 then b = bor(band(b, 0xF0), color) else b = bor(band(b, 0x0F), lshift(color, 4)) end
  buf[o + 1] = b
end

-- DrawDungeonFeatures + LoadDungeonMap: the room outlines of a floor
function MapMenu.drawFeatures(m, floor)
  local f = m.field
  local d = dungeonIdx(m)
  local floors = f.assets.manifest.dungeonMaps and f.assets.manifest.dungeonMaps[d]
  local buf = {}
  for i = 1, 0x2000 do buf[i] = 0 end
  local info = f.room.areaInfo
  local blob = f.assets.dmapBlob or f.assets.store:read("dmap.bin") or ""
  f.assets.dmapBlob = blob
  if floors and floors[floor] and info and band(rshift(info.flags or 0, 3), 1) == 1 then
    for _, lay in ipairs(floors[floor]) do
      local hdr = roomHeader(m, lay[1], lay[2])
      local features = 0
      if lay[1] == f.room.area and lay[2] == f.room.room then
        features = 8
      else
        if hasMap(m) then features = 2 end
        if roomVisited(m, hdr, bankOffset(m, lay)) then features = 3 end
      end
      if band(lay[3], 1) ~= 0 then features = 0 end
      if features ~= 0 and hdr then
        local mapX, mapY = math.floor(hdr.x / 16), math.floor(band(hdr.y, 0x7FF) / 16)
        local w, h = math.floor(hdr.w / 16), math.floor(hdr.h / 16)
        local stride = math.floor((w + 3) / 4)
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local byte = blob:byte(lay[5] + y * stride + rshift(x, 2) + 1) or 0
            local v = band(rshift(byte, 2 * (3 - band(x, 3))), 3)
            local color = v
            if v == 2 then color = features elseif v == 3 then color = 7 end
            mapPixel(buf, mapX + x, mapY + y, color)
          end
        end
      end
    end
  end
  local s = {}
  for i = 1, #buf do s[i] = string.char(buf[i]) end
  m.ppu:write(DUNGEON_MAP_VRAM, table.concat(s))
end

-- DrawDungeonMap: the marker list (gMapDataBottomSpecial) {type, x, y}
function MapMenu.markers(m, floor)
  local f = m.field
  local st = mapStatus(f)
  local list = {}
  list[1] = { 1, band(rshift(st.dmx or 0, 4), 0x7F), band(rshift(st.dmy or 0, 4), 0x7F) }
  local d = dungeonIdx(m)
  local floors = f.assets.manifest.dungeonMaps and f.assets.manifest.dungeonMaps[d]
  for _, lay in ipairs(floors and floors[floor] or {}) do
    local hdr = roomHeader(m, lay[1], lay[2])
    if hdr and hdr.tileEntities then
      local bank = bankOffset(m, lay)
      if hasCompass(m) then
        for _, te in ipairs(hdr.tileEntities) do
          if (te.type == 2 or te.type == 3) and not f:flag("bank", te.flag, bank) then
            local mx, my = hdr.x % 0x800, hdr.y % 0x800
            if te.type == 2 then
              list[#list + 1] = { 2, rshift(bor(band(lshift(te.pos, 4), 0x3F0), 8) + mx, 4),
                                  rshift(bor(band(rshift(te.pos, 2), 0x3F0), 8) + my, 4) }
            else
              list[#list + 1] = { 2, rshift(mx + te.pos, 4), rshift(my + te.c + 256 * te.d, 4) }
            end
          end
        end
      end
      if hasCompass(m) and band(lay[3], 2) ~= 0 and not f:flag("global", d + 1) then
        list[#list + 1] = { 3, math.floor((math.floor(hdr.w / 2) + hdr.x) / 16) % 128,
                            math.floor((math.floor(hdr.h / 2) + hdr.y) / 16) % 128 }
      end
      if lay[1] == st.darea and lay[2] == st.droom then
        list[#list + 1] = { 4, band(rshift(st.dx or 0, 4), 0x7F), band(rshift(st.dy or 0, 4), 0x7F) }
      end
    end
  end
  m.mapMarkers = list
  return list
end

function MapMenu.loadFloor(m, floor)
  MapMenu.drawFeatures(m, floor)
  MapMenu.markers(m, floor)
end

-- ---------------------------------------------------------------------------
-- screens
-- ---------------------------------------------------------------------------
local function regionEntry(t, i)
  local a = AD.regions + 8 * i
  local u0, u2 = t.u16(a), t.u16(a + 2)
  return { up = band(u0, 31), down = band(rshift(u0, 5), 31), left = band(u2, 31), right = band(rshift(u2, 5), 31),
           x = t.u8(a + 6), y = t.u8(a + 7) }
end

local function region6(t, i)
  local a = AD.region6 + 8 * i
  return { u0 = t.u8(a), u1 = t.u8(a + 1), u2 = t.u8(a + 2), u3 = t.u8(a + 3), u4 = t.u8(a + 4),
           u5 = t.s8(a + 5), u6 = t.s8(a + 6), u7 = t.u8(a + 7) }
end

-- PauseMenu_Variant0: the cursors the map pages start on
local function freshCursors(m)
  if m.mapPpu == m.ppu then return end
  m.mapPpu = m.ppu
  local st = mapStatus(m.field)
  local loc = MapMenu.location(m.ppu:table("overworldLocs"), st.owx or 0, st.owy or 0)
  m.cursors[4] = loc and loc.id or 0
  m.cursors[5] = rshift(st.dmy or 0, 11)
end

-- sub_080A69E0: a world position on region `r`'s map, or nil
local function regionPos(m, r, x, y)
  if bor(x, y) == 0 then return nil end
  local loc = MapMenu.location(m.ppu:table("overworldLocs"), x, y)
  if not loc or loc.id ~= r then return nil end
  if r == 4 or r == 7 then
    local h = roomHeader(m, r == 4 and 9 or 7, 0)
    y = y - (h and h.y or 0)
  elseif r == 15 then
    x = x - 0x108
  end
  local function div(a, b) local q = a / b return q >= 0 and math.floor(q) or math.ceil(q) end
  return div((x - loc.minX * 16) * 100, 0x23A), div((y - loc.minY * 16) * 100, 0x23A)
end

-- sub_080A68D4: Link's marker, map hints, fusion markers
local function region6Markers(m)
  local f, st = m.field, mapStatus(m.field)
  local list = {}
  local function add(x, y, sprite, v)
    local px, py = regionPos(m, m.cursor, x, y)
    if px then list[#list + 1] = { blink = rshift(v, 8), frame = band(v, 0xFF), sprite = sprite, x = px, y = py } end
  end
  add(st.owx or 0, st.owy or 0, SPRITE, (f.player.hasCap and 100 or 101) + 0x100)
  local hints = m.ppu:table("pauseData2")
  local mask = f.save.mapHints or 0
  for i = 0, 31 do
    local a = AD.hints + 8 * i
    if not hints or hints.u8(a) == 0 then break end
    if band(mask, lshift(1, i)) ~= 0 then add(hints.u16(a + 4), hints.u16(a + 6), SPRITE, hints.u8(a + 3)) end
  end
  local ks = f.assets.manifest.kinstones
  local we = m.ppu:table("worldEvents")
  if ks and we and f.kinstone then
    for i = 10, 100 do
      local ev = ks.events[i]
      if ev and f.kinstone:isFused(i) and ev.marker ~= 0 then
        local a = we.base + 20 * ev.worldEvent
        add(we.u16(a + 12), we.u16(a + 14), SPRITE, ev.marker + 100)
      end
    end
  end
  m.mapMarkers = list
end

function MapMenu.init(m, n)
  local p, t = m.ppu, m.data
  freshCursors(m)
  m.cursor = m.cursors[n] or 0
  m.areaNameShown = nil
  m.mapTicks = 0
  p.winout = nil
  if n == 4 then
    -- sub_080A6290
    m.ui:layout(readLayout(t, AD.layout4))
    m.keys = keysAt(t, AD.keys4)
    p:loadGfxGroup(0x81)
    p.bg[1].y, p.bg[2].y = -4, -4
    m.field.save.windcrests = bor(m.field.save.windcrests or 0, 0x10780)
  elseif n == 5 then
    -- sub_080A5C44
    m.keys = keysAt(t, AD.keys5)
    -- LoadDungeonMap is LoadResourceAsync: the copy lands after the gfx group
    p:loadGfxGroup(0x81)
    MapMenu.loadFloor(m, m.cursor)
    local d = math.max(0, dungeonIdx(m))
    m.dungeon = d
    showAreaName(m, d, 1)
    local o = t.s8(AD.scroll5 + 2 * d)
    p.bg[1].x, p.bg[1].y = p.bg[1].x + o, p.bg[1].y + o
  elseif n == 6 then
    -- sub_080A6650 / sub_080A67C4 / sub_080A68D4
    m.ui:layout(readLayout(t, AD.layout6))
    m.cursor = m.cursors[4] or 0
    local r = m.cursor
    p:loadPaletteGroup(r + 0xBA)
    local g = r + 0x5F
    if r == 9 and m.field:flag("global", m.field.FLAG_TATEKAKE_HOUSE or 0x3B) then g = 0x70
    elseif r == 0xB and m.field.kinstone and m.field.kinstone:isFused(0x0E) then g = 0x71
    elseif r == 0xE and m.field.room.area == 8 then g = m.field.room.room % 3 + 0x72 end
    p:loadGfxGroup(g)
    local e = region6(t, r)
    m.region = e
    m.scroll = rshift(e.u2, 1)
    m.keys = keysAt(t, AD.keys6)
    region6Markers(m)
  end
end

function MapMenu.update(m, input)
  local f, t = m.field, m.data
  m.mapTicks = (m.mapTicks or 0) + 1
  if m.state ~= 2 then return end
  if m.screen == 4 then
    -- sub_080A62E0
    local e = regionEntry(t, m.cursor)
    local to = -1
    if input.pressed("a") then
      if band(f.save.windcrests or 0, lshift(1, m.cursor)) ~= 0 then
        f:sound(0x6A)
        m.cursors[4] = m.cursor
        m.nextScreen, m.state = 6, 3
        return
      end
    elseif input.pressed("up") then to = e.up
    elseif input.pressed("down") then to = e.down
    elseif input.pressed("left") then to = e.left
    elseif input.pressed("right") then to = e.right end
    if to >= 0 and to <= 16 then m.cursor = to; f:sound(0x69) end
    showAreaName(m, m.cursor, 0)
  elseif m.screen == 5 then
    -- sub_080A5C9C
    local fm = floorMeta(m, m.dungeon or 0)
    local c = m.cursor
    if input.pressed("up") then if c > 0 then c = c - 1 end
    elseif input.pressed("down") then if fm.numFloors - 1 > c then c = c + 1 end end
    if c ~= m.cursor then
      m.cursor = c
      MapMenu.loadFloor(m, c)
      f:sound(0x69)
    end
  elseif m.screen == 6 then
    -- sub_080A667C (held keys)
    local s = m.scroll
    if input.down("up") then if s ~= 0 then s = s - 2 end
    elseif input.down("down") then
      if m.region.u2 > s then s = s + 2 end
      if m.region.u2 < s then s = m.region.u2 end
    end
    m.scroll = math.max(0, s)
    showAreaName(m, m.cursor, 0)
  end
end

function MapMenu.draw(m)
  local p, f, t = m.ppu, m.field, m.data
  local ticks = m.mapTicks or 0
  if m.screen == 4 then
    -- sub_080A6378 / sub_080A6438 / sub_080A6498
    if band(ticks, 0x20) ~= 0 then
      local hints = p:table("pauseData2")
      local mask = f.save.mapHints or 0
      for i = 0, 31 do
        local a = AD.hints + 8 * i
        if not hints or hints.u8(a) == 0 then break end
        if band(mask, lshift(1, i)) ~= 0 then dd(m, SPRITE, hints.u8(a), hints.u8(a + 1), hints.u8(a + 2), 0x400, 0) end
      end
    end
    local st = mapStatus(f)
    if band(ticks, 0x20) == 0 then
      local x = math.floor((st.owx or 0) * 160 / 0xF90) + 0x28
      local y = math.floor(lshift(st.owy or 0, 7) / 0xC60) + 0xC
      dd(m, SPRITE, f.player.hasCap and 0x59 or 0x5A, x, y, 0x400, 0x7000)
    end
    local e = regionEntry(t, m.cursor)
    dd(m, SPRITE, m.cursor * 3 + 0x26 + (band(rshift(ticks, 4), 1) == 0 and 1 or 0), e.x, e.y, 0x400, 0)
    for i = 0, 0x10 do
      if band(f.save.windcrests or 0, lshift(1, i)) == 0 then
        local r = regionEntry(t, i)
        dd(m, SPRITE, 0x28 + 3 * i, r.x, r.y, 0x800, 0)
      end
    end
    p.winout = 0x3D3F
  elseif m.screen == 5 then
    -- DrawDungeonMapActually
    local fm = floorMeta(m, m.dungeon or 0)
    local base = t.u8(AD.floorY + fm.numFloors)
    local st = mapStatus(f)
    local here = rshift(st.dmy or 0, 11)
    dd(m, SPRITE, band(ticks, 0x10) == 0 and 0x75 or 0x74, 0x34, base + m.cursor * 12, 0x400, 0)
    dd(m, SPRITE, band(ticks, 0x20) ~= 0 and 0x78 or 0x79, 0x20, base + here * 12, 0x400, 0)
    if hasMap(m) then dd(m, SPRITE_ICONS, itemFrame(m, 0x50) or 0, 0x18, 0x7E, 0x400, 0x4380) end
    if hasBigKey(m) then dd(m, SPRITE_ICONS, itemFrame(m, 0x52) or 0, 0x2E, 0x7E, 0x400, 0x4380) end
    if hasCompass(m) then
      dd(m, SPRITE_ICONS, itemFrame(m, 0x51) or 0, 0x45, 0x7E, 0x400, 0x380)
      dd(m, SPRITE, band(ticks, 0x20) ~= 0 and 0x7A or 0x7B, 0x46, base + (fm.highestFloor - fm.unk2) * 12, 0x400, 0)
    end
    local fr = fm.highestFloor + 0x82
    for i = 0, fm.numFloors - 1 do
      dd(m, SPRITE, fr - i, 0x34, base + 12 * i, 0x400, 0)
    end
    for _, o in ipairs(m.mapMarkers or {}) do
      local frame = 0xFF
      if o[1] == 1 then frame = here == m.cursor and 0x7D or 0x7E
      elseif o[1] == 2 then frame = 0x80
      elseif o[1] == 3 then frame = 0x81
      elseif o[1] == 4 then frame = 0x7F end
      dd(m, SPRITE, frame, o[2] + 0x50 - p.bg[1].x, o[3] + 0x10 - p.bg[1].y, 0x400, 0)
    end
    -- PauseMenu_Screen_5: rotate palette entries 200-207 every 8 frames
    if band(ticks, 7) == 0 and ticks ~= m.lastRotate then
      m.lastRotate = ticks
      local c0 = p.pal[PAL_ROTATE]
      for i = 0, 6 do p.pal[PAL_ROTATE + i] = p.pal[PAL_ROTATE + i + 1] end
      p.pal[PAL_ROTATE + 7] = c0
      p.dirty = true
    end
  elseif m.screen == 6 then
    -- PauseMenu_Screen_6 / sub_080A66D0
    local e = m.region
    p.bg[1].y = -e.u5
    p.bg[2].y = m.scroll - e.u6
    if band(ticks, 0x10) ~= 0 then
      if m.scroll ~= 0 then dd(m, SPRITE, 0x71, 0x78, 0x0C, 0, 0x800) end
      if e.u2 > m.scroll then dd(m, SPRITE, 0x72, 0x78, 0x84, 0, 0x800) end
    end
    local phase = band(ticks, 0x20) ~= 0
    for _, o in ipairs(m.mapMarkers or {}) do
      if (o.blink == 1) == phase then
        dd(m, o.sprite, o.frame, o.x + e.u7, o.y + e.u3 - m.scroll, 0, 0xC00)
      end
    end
  end
end

-- screen 6's picture: BG3CNT is $1E0A (priority 2, in front of the map)
-- on every scanline except 8 .. unk5 + unk4 - 1, where it is $1E0B
function MapMenu.compose(m)
  local p = m.ppu
  if m.screen ~= 6 or not m.region then
    love.graphics.draw(p:render(), 0, 0)
    return
  end
  local y1 = m.region.u5 + m.region.u4
  p.bg[3].control = 0x1E0A
  love.graphics.draw(p:render("bg3front"), 0, 0)
  p.bg[3].control = 0x1E0B
  local img = p:render()
  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.intersectScissor(0, 8, 240, math.max(0, y1 - 8))
  love.graphics.draw(img, 0, 0)
  love.graphics.setScissor(sx, sy, sw, sh)
end

return MapMenu
