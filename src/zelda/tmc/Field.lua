-- The Minish Cap overworld / interiors: one room at a time, Link, the
-- room's entities and their cartridge scripts, exits, camera, text, HUD.
--
-- Coordinates are room-local pixels (the cartridge adds gRoomControls
-- origin_x/_y; with the origin at 0 the numbers in scripts and exit lists
-- are used as they are).  The camera follows the target and clamps to the
-- room, like sub_08080974 / UpdateScroll.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Room = require("src.zelda.tmc.Room")
local Player = require("src.zelda.tmc.Player")
local Script = require("src.zelda.tmc.Script")
local Anim = require("src.zelda.tmc.Anim")
local TextBox = require("src.zelda.tmc.TextBox")
local Kinstone = require("src.zelda.tmc.Kinstone")
local Objects = require("src.zelda.tmc.Objects")
local Items = require("src.zelda.tmc.Items")
local Enemies = require("src.zelda.tmc.Enemies")
local Menu = require("src.zelda.tmc.Menu")
local Hud = require("src.zelda.tmc.Hud")
local Dungeon = require("src.zelda.tmc.Dungeon")
local Native = require("src.zelda.tmc.Native")

local Field = {}
Field.__index = Field

local W, H = 240, 160
local KIND = { ENEMY = 3, PROJECTILE = 4, OBJECT = 6, NPC = 7, PLAYER_ITEM = 8, MANAGER = 9 }
Field.KIND = KIND

-- global flags the field consults (include/flags.h)
Field.FLAG_TABIDACHI = 0x15 -- "departure": enemies appear in room lists [2]
Field.FLAG_EZERO_1ST = 0x14 -- met Ezlo

-- ---------------------------------------------------------------------------
function Field.new(game, save)
  local self = setmetatable({
    game = game, assets = game.assets, save = save,
    entities = {}, camX = 0, camY = 0, fadeLevel = 1, fadeTarget = 0, fadeSpeed = 16,
    textbox = nil, roomFlags = {}, frame = 0, ghosts = {}, toast = nil,
  }, Field)
  self.mem = game.scriptMem
  self.kinstone = Kinstone.new(self)
  self._objects = Objects.new(self)
  self._items = Items.new(self)
  self._enemies = Enemies.new(self)
  self._dungeon = Dungeon.new(self)
  self.menu = Menu.new(self)
  local okHud, hud = pcall(Hud.new, self.assets)
  self.hud = okHud and hud or nil
  self.portals = {}
  save.equip = save.equip or {}
  save.collected = save.collected or {}
  local st = save.status
  self:enterRoom(st.area, st.room, st.x, st.y, st.facing or 4)
  return self
end

-- ---------------------------------------------------------------------------
-- flags / inventory / stats: the script host interface (Script.lua)
-- ---------------------------------------------------------------------------
local function flagSet(t, k) return t[k] == true end

function Field:areaBank()
  local info = self.room and self.room.areaInfo
  return info and info.flagBank or 0
end

-- Local flags are one bit array; an area's bank is a bit offset into it
-- (gLocalFlagBanks: LOCAL_BANK_n -> FLAG_BANK_n, include/flags.h).
-- CheckLocalFlagByBank takes the offset itself.
local BANK_OFFSET = { [0] = 0, 0, 0x100, 0x200, 0x300, 0x400, 0x500, 0x5C0, 0x680,
                      0x740, 0x800, 0x8C0, 0x9C0, 0xA80 }
Field.BANK_OFFSET = BANK_OFFSET

local function localKey(self, kind, idx, bank)
  if kind == "bank" then return (bank or 0) + idx end
  return (BANK_OFFSET[self:areaBank()] or 0) + idx
end

function Field:flag(kind, idx, bank)
  local f = self.save.flags
  if kind == "global" then return flagSet(f.global, idx) end
  if kind == "room" then return flagSet(self.roomFlags, idx) end
  f.loc = f.loc or {}
  return flagSet(f.loc, localKey(self, kind, idx, bank))
end

function Field:setFlag(kind, idx, value, bank)
  local f = self.save.flags
  local t, k = nil, idx
  if kind == "global" then t = f.global
  elseif kind == "room" then t = self.roomFlags
  else
    f.loc = f.loc or {}
    t, k = f.loc, localKey(self, kind, idx, bank)
  end
  t[k] = value and true or nil
end

function Field:inventory(item)
  local d = self._dungeon and self._dungeon:inventory(item)
  if d then return d end
  return self.save.items[item] or 0
end

function Field:setInventory(item, v)
  self.save.items[item] = (v ~= 0) and v or nil
end

function Field:stat(name) return self.save.stats[name] or 0 end

function Field:modStat(name, delta)
  local s = self.save.stats
  if name == "rupees" then
    s.rupees = math.max(0, math.min(s.maxRupees or 999, (s.rupees or 0) + delta))
  elseif name == "health" then
    s.health = math.max(0, math.min(s.maxHealth, (s.health or 0) + delta))
  else
    s[name] = (s[name] or 0) + delta
  end
end

function Field:hasSword()
  local items = self.save.items
  -- ITEM_SMITH_SWORD 1 .. ITEM_FOURSWORD 6 (include/item.h)
  return (items[1] or items[2] or items[3] or items[4] or items[5] or items[6]) ~= nil
end

function Field:objects() return self._objects end
function Field:dungeon() return self._dungeon end
function Field:items() return self._items end
function Field:enemies() return self._enemies end

-- the item on button A or B (the pause menu sets them)
function Field:equipped(b) return self.save.equip and self.save.equip[b] end

-- ForceEquipItem: the same item on both buttons swaps them
function Field:equip(b, item)
  local eq = self.save.equip
  local other = b == "a" and "b" or "a"
  if eq[other] == item then eq[other] = eq[b] end
  eq[b] = item
end

-- a message as plain text (menus)
function Field:plainText(index)
  local bytes = self.assets:message(index)
  if not bytes then return "" end
  local lines = TextBox.parse(bytes, self.save.name)
  local out = {}
  for _, l in ipairs(lines) do
    local s = {}
    for _, r in ipairs(l) do s[#s + 1] = r.text end
    out[#out + 1] = table.concat(s)
  end
  return (table.concat(out, " "):gsub("^%s+", ""))
end

function Field:markCollected(key) self.save.collected[key] = true end
function Field:collected(key) return self.save.collected[key] == true end

-- a short-lived effect: an object definition's animation played once
function Field:addFx(x, y, obj, objType)
  local d = self._objects:def(obj, objType)
  if not d then return end
  local e = { kind = 6, id = obj, form = objType, x = x, y = y, z = 0, fx = true, animationState = 0,
              field82 = 0, interactType = 0, anim = Anim.new() }
  self._objects:dress(e, d, objType == nil and 0 or objType)
  e.objAnim = 0
  self.entities[#self.entities + 1] = e
end

-- R: talk to who is in front, else open / read / lift / portal
function Field:tryAction(player)
  if self:tryInteract(player) then return true end
  if self._dungeon:tryAction(player) then return true end
  return self._objects:tryAction(player)
end

-- out of hearts: back to the room's entrance with three hearts (the
-- cartridge offers CONTINUE from the last door; this is that, minus the
-- game-over screen)
-- GAME OVER (gameOverTask.c, our layout): CONTINUE or SAVE AND QUIT.
-- Continuing refills three hearts and starts again at the entrance of the
-- room Link fell in.
function Field:onPlayerDied()
  self.gameOver = { cursor = 1, t = 0 }
  if self.assets.manifest.gfxGroups then
    self.gameOver = require("src.zelda.tmc.GameOver").new(self)
  end
  self:bgm(nil)
end

function Field:updateGameOver(input)
  local go = self.gameOver
  if go.ppu then
    local r = go:update(input)
    if not r then return end
    local s = self.save.stats
    s.health = math.min(s.maxHealth, 24)
    self.gameOver = nil
    if r == "quit" then self.game:toTitle() return end
    local st = self.entry or self.save.status
    self.player.state = "normal"
    self.player.invuln = 60
    self:enterRoom(st.area, st.room, st.x, st.y, st.facing)
    return
  end
  go.t = go.t + 1
  if go.t < 40 then return end
  if input.pressed("up") or input.pressed("down") then go.cursor = 3 - go.cursor; self:sound(0x69) end
  if input.pressed("a") or input.pressed("start") then
    self:sound(0x6A)
    local s = self.save.stats
    s.health = math.min(s.maxHealth, 24)
    self.gameOver = nil
    if go.cursor == 2 then
      if self.game.opts.host and self.game.opts.host.requestSave then self.game.opts.host:requestSave() end
      self.game:toTitle()
      return
    end
    local st = self.entry or self.save.status
    self.player.state = "normal"
    self.player.invuln = 60
    self:enterRoom(st.area, st.room, st.x, st.y, st.facing)
  end
end

function Field:drawGameOver(font)
  local g = love.graphics
  local go = self.gameOver
  if go.ppu then return go:draw() end
  g.setColor(0, 0, 0, math.min(0.85, go.t / 40))
  g.rectangle("fill", 0, 0, W, H)
  if go.t < 40 then return end
  g.setFont(font)
  g.setColor(0.9, 0.15, 0.15, 1)
  g.printf("GAME OVER", 0, 40, W, "center")
  for i, label in ipairs({ "CONTINUE", "SAVE AND QUIT" }) do
    g.setColor(i == go.cursor and 1 or 0.6, i == go.cursor and 0.95 or 0.6, i == go.cursor and 0.5 or 0.6, 1)
    g.printf((i == go.cursor and "> " or "  ") .. label, 0, 76 + (i - 1) * 18, W, "center")
  end
  g.setColor(1, 1, 1, 1)
end

function Field:kinstoneFused(id) return self.kinstone:isFused(id) end

function Field:playerInRegion(x, y, w, h)
  local p = self.player
  return math.abs(p.x - x) < w and math.abs(p.y - y) < h
end

-- InitItemGetSequence: the item goes into the inventory, Link holds it up
-- and the item's message (gItemMetaData textCategory/textId) is shown
local EQUIP_SLOT = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
                     [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
function Field:giveItem(item, param)
  local s = self.save.stats
  if item == 0x5C then
    self.kinstone:addPiece(param)
  elseif item >= 0x50 and item <= 0x53 then -- map, compass, big key, small key
    self._dungeon:give(item)
  elseif item >= 0x54 and item <= 0x59 then -- ITEM_RUPEE1 .. ITEM_RUPEE200
    self:modStat("rupees", ({ [0x54] = 1, [0x55] = 5, [0x56] = 20, [0x57] = 50, [0x58] = 100, [0x59] = 200 })[item])
  elseif item == 0x3F then -- ITEM_SHELLS
    self:modStat("shells", math.max(1, param or 0))
  elseif item == 0x5F then -- ITEM_HEART
    self:modStat("health", 8)
  elseif item == 0x62 then -- ITEM_HEART_CONTAINER
    s.maxHealth = math.min((s.maxHealth or 24) + 8, 0xA0)
    s.health = s.maxHealth
  elseif item == 0x63 then -- ITEM_HEART_PIECE
    s.heartPieces = (s.heartPieces or 0) + 1
    if s.heartPieces >= 4 then
      s.heartPieces = 0
      s.maxHealth = math.min((s.maxHealth or 24) + 8, 0xA0)
      s.health = s.maxHealth
    end
  else
    self.save.items[item] = math.max(1, self.save.items[item] or 0)
    -- a new button item goes on a free button (B first), as the cartridge
    -- sets the Smith's Sword on B and the shield on A
    local meta = self.assets.manifest.itemMeta and self.assets.manifest.itemMeta[item]
    if meta and EQUIP_SLOT[meta.slot] then
      local eq = self.save.equip
      local cur = eq.b and self.assets.manifest.itemMeta[eq.b]
      if meta.slot == 0 and (not eq.b or (cur and cur.slot == 0)) then eq.b = item
      elseif meta.slot == 0 and eq.a and self.assets.manifest.itemMeta[eq.a].slot == 0 then eq.a = item
      elseif not eq.b then eq.b = item
      elseif not eq.a then eq.a = item end
    end
  end
  local meta = self.assets.manifest.itemMeta and self.assets.manifest.itemMeta[item]
  local text = meta and meta.text or 0
  if text ~= 0 and self.assets:message(text) then
    self:sound(0x109) -- SFX_ITEM_GET
    self:message(text)
    if self.player then self.player:startItemGet(item) end
  else
    self:sound(0x6F)
  end
end

function Field:sound(id) if self.game.audio then self.game.audio:playSfx(id) end end

function Field:bgm(id)
  if not self.game.audio then return end
  if id == "area" then id = self.room and self.room.areaInfo and self.room.areaInfo.bgm end
  if id then self.game.audio:playBgm(id) else self.game.audio:stopBgm() end
end

-- SetFade (src/fade.c): "out" covers the screen, "in" uncovers it; white
-- for FADE_BLACK_WHITE; speed is progress per frame out of 256 (the
-- script's SetFadeTime value, 256 = instant).  "invert" turns the current
-- fade round.  Iris fades use the same (not the circle).
function Field:fade(kind, white, speed)
  if kind == "invert" then
    self.fadeTarget = 1 - (self.fadeTarget or 0)
  else
    self.fadeTarget = (kind == "out") and 1 or 0
    if kind == "in" and self.fadeLevel == 0 then self.fadeLevel = 1 end
  end
  if white ~= nil then self.fadeWhite = white end
  self.fadeStep = (speed or self.fadeSpeed or 16) / 256
end

-- InitScreenShake(time, magnitude)
function Field:shake(time, magnitude)
  self.shakeT, self.shakeMag = time, math.max(1, magnitude % 8)
end

-- a THOUGHT_BUBBLE over an entity: kind 0 "!", 1 "?", 2 sleep
function Field:bubble(who, kind, ox, oy)
  who.bubbleKind, who.bubbleT = kind, 60
  if os.getenv and os.getenv("TMC_DEBUG") then self.game:log("bubble " .. kind .. " at frame " .. self.frame) end
  who.bubbleOX, who.bubbleOY = ox or 8, oy or -24
end

-- the script host's Call / CallWithArg
function Field:callNative(fn, e, ctx)
  return Native.call(self, fn, e, ctx, Script.active)
end

function Field:fadeActive() return self.fadeLevel ~= self.fadeTarget end

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
function Field:message(index, entity, pos, kind)
  local bytes = self.assets:message(index)
  if not bytes then return end
  local top = self.player and (self.player.y - self.camY) > 100
  self.textbox = TextBox.new(bytes, { playerName = self.save.name, top = top, assets = self.assets })
  self.textOwner = entity
  self.textKind = kind
end

function Field:messageActive() return self.textbox ~= nil end

-- StartPlayerScript: a cutscene script that drives Link (src/script.c);
-- his input is off until it ends
function Field:startPlayerScript(ptr)
  if not (self.mem and self.mem:valid(ptr)) then return end
  self.playerScript = Script.new(self.mem, ptr)
  self.player.control = false
  self.player.field80 = 0
end

-- the new-file intro: Link asleep in bed (ANIM_SLEEP_NOCAP) while the
-- player script runs; when it ends he wakes (ANIM_WAKEUP_NOCAP) and steps
-- out of bed (script_BedInLinksRoom's walk is approximated by a hop to
-- the floor below the bed)
function Field:startIntro(script)
  self.intro = { phase = "sleep" }
  self.player.scriptAnim = 0x73A
  self.player.x, self.player.y, self.player.animationState = 0x90, 0x38, 4
  self:startPlayerScript(script)
end

function Field:updateIntro()
  local it = self.intro
  local p = self.player
  if it.phase == "sleep" and not self.playerScript then
    it.phase = "wake"
    it.t = 40
    p.scriptAnim = 0x73B
  elseif it.phase == "wake" then
    it.t = it.t - 1
    if it.t <= 0 then
      p.scriptAnim = nil
      p.y = p.y + 22
      p.control = true
      p.animId = -1
      self.intro = nil
    end
  end
end

function Field:runPlayerScript()
  local ps = self.playerScript
  if not ps then return end
  local p = self.player
  p.speed = p.speed or 0x100
  local ok, err = pcall(ps.run, ps, p, self)
  if not ok then self.game:log("player script: " .. tostring(err)); ps.stopped = true end
  ps:postActions(p)
  p.scriptWalking = (p.field80 or 0) == 4
  if ps.stopped then
    self.playerScript = nil
    p.control = true
    p.scriptWalking = nil
  end
end

function Field:inputLocked()
  return self.textbox ~= nil or self.transition ~= nil or self.kinstone.active or (self.menu and self.menu.open)
    or self.pan ~= nil
end

-- ---------------------------------------------------------------------------
-- rooms
-- ---------------------------------------------------------------------------
function Field:enterRoom(area, room, x, y, facing)
  local r, err = Room.load(self.assets, area, room)
  if not r then
    -- an unknown room (a special-map room or a bad save): fall back to
    -- the new-game room rather than a black screen
    self.game:log("room " .. area .. ":" .. room .. " failed: " .. tostring(err))
    r = assert(Room.load(self.assets, 0x22, 0x15))
    x, y = 0x90, 0x38
  end
  self.assets:dropAtlases(area)
  self.room = r
  self.roomFlags = {}
  self.entities = {}
  self.portals = {}
  if self._dungeon then self._dungeon:reset() end
  self.cameraTarget = nil
  self.entry = { area = area, room = room, x = x, y = y, facing = facing }
  Script.resetSync()
  if not self.player then self.player = Player.new(self, x, y, facing)
  else
    self.player.x, self.player.y = x, y
    if facing then self.player.animationState = facing end
    self.player.state = "normal"
  end
  -- PL_NO_CAP until Ezlo joins (InitializePlayer checks EZERO_1ST)
  self.player.hasCap = self:flag("global", Field.FLAG_EZERO_1ST)
  self.player.animId = -1
  local st = self.save.status
  st.area, st.room, st.x, st.y, st.facing = area, room, x, y, self.player.animationState
  self:updateProgress()
  self.queuedBgm = nil
  self.save.visited = self.save.visited or {}
  self.save.visited[area * 256 + room] = true
  self:spawnRoomEntities()
  pcall(self.kinstone.applyWorldEvents, self.kinstone)
  self._objects:roomLoaded()
  self:snapCamera()
  self.swapGroups = {}
  self:updateTileSwap()
  -- gArea.queued_bgm when room code set one, else the area's
  if self.queuedBgm then self:bgm(self.queuedBgm) else self:bgm("area") end
  self.game:onRoomChanged(area, room)
end

function Field:spawnRoomEntities()
  local lists = self.room.entities
  self:loadEntityList(nil, lists[1])
  self:loadEntityList(nil, lists[0])
  if self:flag("global", Field.FLAG_TABIDACHI) then self:loadEntityList(nil, lists[2]) end
  local code = self.game.roomCode and self.game.roomCode[self.room.area * 256 + self.room.room]
  if code then pcall(code, self) end
end

-- an EntityData list at cartridge address `addr`, parsed from the entity
-- region the importer copied (entity_headers.s), or from the room's extras
function Field:entityListAt(addr)
  local info = self.room.areaInfo
  local hit = info and info.entityLists and info.entityLists[addr]
  if hit then return hit end
  local A = self.assets
  local reg = A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local blob = A.entityBlob
  local o = addr - reg.base
  if o < 0 or o + 16 > #blob then return nil end
  local u16 = A.u16
  local list = {}
  for i = 0, 127 do
    local q = o + 16 * i
    local kind = blob:byte(q + 1)
    if not kind or kind == 0xFF then break end
    list[#list + 1] = {
      kind = band(kind, 0x0F), collision = rshift(kind, 4),
      pool = blob:byte(q + 2), id = blob:byte(q + 3), paramA = blob:byte(q + 4),
      paramB = u16(blob, q + 4) + u16(blob, q + 6) * 65536,
      x = u16(blob, q + 8), y = u16(blob, q + 10),
      paramC = u16(blob, q + 12) + u16(blob, q + 14) * 65536,
    }
  end
  return list
end

-- DelayedEntityLoadManager (src/manager/delayedEntityLoadManager.c): the
-- room property [type] is a list of NPCStruct (16 bytes: id, type, type2,
-- layer, x, y, script, timer, progressBitfield), $FF-terminated; each
-- entry whose bit (1 << gSave.global_progress) is set becomes an NPC (the
-- manager's timer 0) or an object.  The cartridge streams them in as they
-- come on screen; here they all appear with the room.
function Field:delayedEntityLoad(d)
  local props = self.room.maps.header.props
  local addr = props and props[d.paramA]
  if not addr then return end
  local A = self.assets
  local reg = A.manifest.entityRegion
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local blob, u16 = A.entityBlob, A.u16
  local o = addr - reg.base
  if o < 0 or o + 16 > #blob then return end
  local asObject = band(rshift(d.paramB, 8), 0xFF) ~= 0
  local mask = 2 ^ (self.save.progress or 1)
  for i = 0, 63 do
    local q = o + 16 * i
    local id = blob:byte(q + 1)
    if not id or id == 0xFF then break end
    local bits = u16(blob, q + 14)
    if math.floor(bits / mask) % 2 == 1 then
      local script = u16(blob, q + 8) + u16(blob, q + 10) * 65536
      self:spawn({
        kind = asObject and KIND.OBJECT or KIND.NPC, id = id, paramA = blob:byte(q + 2),
        paramB = blob:byte(q + 3), pool = script ~= 0 and 0x4F or 0x0F,
        x = u16(blob, q + 4), y = u16(blob, q + 6), paramC = script,
      })
    end
  end
end

-- UpdateGlobalProgress (src/gameUtils.c): the story stage, from flags
function Field:updateProgress()
  local p = 1
  if self:flag("bank", 118, 0x300) then p = 9           -- SEIIKI_STAINED_GLASS
  elseif self:flag("global", 6) then p = 8              -- LV5_CLEAR
  elseif self:flag("bank", 50, 0x300) then p = 7        -- OUBO_KAKERA
  elseif self:flag("global", 5) then p = 6              -- LV4_CLEAR
  elseif self:flag("global", 4) then p = 5              -- LV3_CLEAR
  elseif self:flag("bank", 160, 0x100) then p = 4       -- SOUGEN_08_TORITSUKI
  elseif self:flag("global", 2) then p = 2 end          -- LV1_CLEAR
  self.save.progress = p
end

-- LoadRoomEntityList(ptr) from a script or room code, or a list table
function Field:loadEntityList(addr, list)
  list = list or (addr and self:entityListAt(addr))
  if not list then return end
  self.listSerial = (self.listSerial or 0) + 1
  for i, d in ipairs(list) do
    self.spawnKey = string.format("%02x:%02x:%s:%d", self.room.area, self.room.room, tostring(addr or list), i)
    self:spawn(d)
  end
  self.spawnKey = nil
end

function Field:npcDef(id, form)
  local d = self.assets.manifest.npcDefs and self.assets.manifest.npcDefs[id]
  if d and d.type == 2 then d = d.forms and (d.forms[form] or d.forms[0]) end
  if d and d.type == 1 then return d end
  return nil
end

function Field:spawn(d)
  local e = {
    kind = d.kind, id = d.id, form = d.paramA, param = d.paramB,
    x = d.x, y = d.y, z = 0, animationState = 4, field80 = 0, field82 = 0,
    speed = 0x100, interactType = 0, anim = Anim.new(), data = d,
  }
  local placed = band(d.pool, 0xF0)
  if placed ~= 0 and placed ~= 0x20 and placed ~= 0x40 then e.unplaced = true end
  if d.kind == KIND.NPC then
    local def = self:npcDef(d.id, d.paramA)
    if def then
      e.def = def
      e.sprite = def.sprite
      e.palette = self.assets:objPalette(def.palette, self.room.atlas and self.room.atlas.palettes)
      e.gfx = (def.gfxType == 0 and def.gfx ~= 0) and def.gfx or nil
      e.talkable = true
      e.solid = true
    end
  end
  if band(d.pool, 0xF0) == 0x40 and d.paramC ~= 0 and self.mem and self.mem:valid(d.paramC) then
    e.script = Script.new(self.mem, d.paramC)
  end
  if d.kind == KIND.ENEMY and not e.script then
    local en = self._enemies:spawn(d)
    if en then self.entities[#self.entities + 1] = en end
    return en
  end
  if d.kind == KIND.PROJECTILE then
    local pe = self._dungeon:spawnProjectile(d)
    if pe then self.entities[#self.entities + 1] = pe end
    if pe ~= false then return pe end
  end
  if d.kind == KIND.OBJECT and not e.script then
    local de = self._dungeon:spawnObject(d)
    if de then self.entities[#self.entities + 1] = de return de end
    if de == nil then return nil end
  end
  if d.kind == KIND.MANAGER then
    if self._dungeon:spawnManager(d) then return nil end
    if d.id == 3 then self._objects:addPortal(d) end -- MINISH_PORTAL_MANAGER
    if d.id == 0x16 then self:delayedEntityLoad(d) end -- DELAYED_ENTITY_LOAD_MANAGER
    return nil
  end
  if d.kind == KIND.OBJECT then
    local O = self._objects
    if d.id == Objects.OBJ.GROUND_ITEM and not e.script then
      -- an item placed in the room: once taken it stays taken
      local key = self.spawnKey
      if key and self:collected(key) then return nil end
      return O:groundItem(d.paramA, band(d.paramB, 0xFF), d.x, d.y, { key = key })
    end
    local def = O:def(d.id, d.paramA)
    if def and def.draw ~= 0 then
      O:dress(e, def, 0)
      e.objAnim = 0
      if d.id == Objects.OBJ.POT then e.liftable = true; e.solid = true end
    end
  end
  if d.kind == KIND.NPC or e.script or (d.kind == KIND.OBJECT and e.sprite) then
    self.entities[#self.entities + 1] = e
  end
  return e
end

-- NPCs are solid to Link (their hitbox is about 12x8 at the feet)
function Field:entityBlocks(who, x, y)
  for _, e in ipairs(self.entities) do
    if e.solid and not e.hidden and not e.deleted and not e.unplaced and e ~= who then
      if math.abs(e.x - x) < 10 and math.abs(e.y - y) < 7 then
        -- only block when moving closer (never trap Link inside one)
        local d0 = math.abs(e.x - who.x) + math.abs(e.y - who.y)
        local d1 = math.abs(e.x - x) + math.abs(e.y - y)
        if d1 < d0 then return true end
      end
    end
  end
  return false
end

function Field:tryInteract(player)
  local fx, fy = player:frontPoint(10)
  local best, bestD
  for _, e in ipairs(self.entities) do
    if e.talkable and not e.hidden and not e.deleted then
      local d = math.abs(e.x - fx) + math.abs(e.y - fy)
      if d < 18 and (not bestD or d < bestD) then best, bestD = e, d end
    end
  end
  if best then
    best.interactType = 1
    return true
  end
  return false
end

function Field:onSwordSwing(player) end

-- ---------------------------------------------------------------------------
-- tileset managers (src/manager/*TileSetManager.c): each slot picks the
-- first of its regions on screen (CheckRegionsOnScreen) and the room's BG
-- graphics take that group's blocks
-- ---------------------------------------------------------------------------
local function regionOnScreen(camX, camY, r)
  local x = camX - r[2] + W
  local y = camY - r[3] + H
  return x >= 0 and x < r[4] + W and y >= 0 and y < r[5] + H
end

function Field:updateTileSwap()
  local defs = self.assets.manifest.tileSwaps
  local def = defs and defs[self.room.area * 256 + self.room.room]
  if not def then return end
  local changed = false
  for si, regions in ipairs(def.slots) do
    local hit = false
    for _, r in ipairs(regions) do
      if regionOnScreen(self.camX, self.camY, r) then
        if self.swapGroups[si] ~= r[1] then self.swapGroups[si] = r[1]; changed = true end
        hit = true
        break
      end
    end
    -- Not the cartridge: if a slot has never matched (the camera starts
    -- outside every region) the cartridge would show whatever VRAM held --
    -- the default tileset, i.e. smeared tiles.  Load the nearest region's
    -- group instead.
    if not hit and self.swapGroups[si] == nil and #regions > 0 then
      local best, bd = nil, math.huge
      local cx, cy = self.camX + W / 2, self.camY + H / 2
      for _, r in ipairs(regions) do
        local dx = math.max(r[2] - cx, 0, cx - (r[2] + r[4]))
        local dy = math.max(r[3] - cy, 0, cy - (r[3] + r[5]))
        local d = dx * dx + dy * dy
        if d < bd then best, bd = r[1], d end
      end
      self.swapGroups[si] = best
      changed = true
    end
  end
  if not changed then return end
  local A = self.assets
  A.swapBlobs = A.swapBlobs or {}
  local blob = A.swapBlobs[def.file]
  if not blob then blob = A.store:read(def.file) or ""; A.swapBlobs[def.file] = blob end
  local blocks, keyParts, pals = {}, {}, nil
  for si = 1, #def.slots do
    local g = self.swapGroups[si]
    keyParts[#keyParts + 1] = tostring(g)
    if g and def.groups[g] then
      for _, b in ipairs(def.groups[g]) do
        blocks[#blocks + 1] = { b[3], blob:sub(b[1] + 1, b[1] + b[2]) }
      end
    end
  end
  local g1 = self.swapGroups[1]
  if def.palettes and g1 and def.palettes[g1] then pals = { def.palettes[g1] } end
  local key = table.concat(keyParts, ",")
  self.room:applySwap({ key = key, blocks = blocks, paletteGroups = pals })
  A:dropAtlases(self.room.area, self.room.area * 256 + self.room.maps.header.ts .. ":" .. key)
end

-- ---------------------------------------------------------------------------
-- exits
-- ---------------------------------------------------------------------------
function Field:startTransition(exit, dir)
  if self.transition then return end
  local p = self.player
  local dest = self.assets:area(exit.area)
  local destRoom = dest and dest.rooms and dest.rooms[exit.room]
  if not destRoom then return end
  local nx, ny
  local worldX, worldY = self.room.x + p.x, self.room.y + p.y
  if exit.endX <= 0x3FF then nx = exit.endX else nx = worldX - destRoom.x end
  if exit.endY <= 0x3FF then ny = exit.endY else ny = worldY - destRoom.y end
  -- a border warp lands just inside the new room's edge
  if dir == 0 then ny = math.min(ny, destRoom.h - 8) end
  if dir == 2 then ny = math.max(ny, 8) end
  if dir == 1 then nx = math.max(nx, 8) end
  if dir == 3 then nx = math.min(nx, destRoom.w - 8) end
  -- Transition.facing_direction is the start_anim (an animationState)
  local facing = dir and dir * 2 or (exit.facing and exit.facing % 8) or p.animationState
  self.transition = { exit = exit, x = nx, y = ny, facing = facing, phase = "out" }
  if exit.sfx and exit.sfx ~= 0 then self:sound(exit.sfx) end
  self.fadeTarget = 1
end

-- ACT_TILE_40 ($28, stairs) / ACT_TILE_41 ($29, doors), include/tiles.h.
-- Pushing into one (it is solid, $0F)
-- with an area warp just beyond starts that warp (beanstalkSubtask.c,
-- the ACT_TILE_40 case of the player's tile actions).
Field.ACT_TILE_STAIRS, Field.ACT_TILE_DOOR = 0x28, 0x29

function Field:doorExit(input)
  local p, r = self.player, self.room
  if p.minish or not p.moving and not (input.down("up") or input.down("down")
     or input.down("left") or input.down("right")) then return nil end
  local held = (p.animationState == 0 and input.down("up")) or (p.animationState == 4 and input.down("down"))
    or (p.animationState == 2 and input.down("right")) or (p.animationState == 6 and input.down("left"))
  if not held then return nil end
  local fx, fy = p:frontPoint(8)
  local found = false
  for _, dy in ipairs({ 0, 2, 4 }) do
    local tx, ty = math.floor(fx / 16), math.floor((fy + dy) / 16)
    local ttype = r:tileType(p.layer, tx, ty)
    if ttype and ttype < 0x4000 then
      local act = self.assets.actTile[ttype] or 0
      if act == Field.ACT_TILE_STAIRS or act == Field.ACT_TILE_DOOR then found = true break end
    end
  end
  if not found then return nil end
  for d = 4, 16, 4 do
    local ex, ey = p:frontPoint(d)
    local e = r:areaExitAt(ex, ey + 2)
    if e then return e end
  end
  -- a door with no warp of its own leads to the next room of the area
  local adj = self:adjacentRoom(p.animationState / 2)
  if adj then adj.door = true end
  return adj, adj and p.animationState / 2
end

-- Rooms of one area tile the area's map (RoomHeader map_x/map_y): walking
-- off an edge with no border warp scrolls into the room on the other side.
-- Returned as a border-style warp that keeps the world coordinates.
function Field:adjacentRoom(dir)
  local p, r = self.player, self.room
  local wx, wy = r.x + p.x, r.y + p.y
  if dir == 0 then wy = r.y - 4 elseif dir == 2 then wy = r.y + r.height + 4
  elseif dir == 1 then wx = r.x + r.width + 4 else wx = r.x - 4 end
  local info = r.areaInfo
  for id, room in pairs(info and info.rooms or {}) do
    if id ~= r.room and room.file and wx >= room.x and wx < room.x + room.w
       and wy >= room.y and wy < room.y + room.h then
      return { warpType = 0, area = r.area, room = id, endX = 0xFFFF, endY = 0xFFFF, shape = 0, facing = dir * 2 }
    end
  end
  return nil
end

function Field:checkExits(input)
  if self.noExits then return end -- test harnesses pin the player in a room
  local p, r = self.player, self.room
  local e = r:areaExitAt(p.x, p.y)
  if e then return self:startTransition(e) end
  local d, ddir = self:doorExit(input)
  if d then return self:startTransition(d, ddir) end
  local edge = 3
  local function try(dir)
    local ex = r:borderExit(dir, p.x, p.y) or self:adjacentRoom(dir)
    if ex then self:startTransition(ex, dir) end
  end
  if p.y <= edge + 6 and input.down("up") then try(0)
  elseif p.y >= r.height - edge and input.down("down") then try(2)
  elseif p.x <= edge + 4 and input.down("left") then try(3)
  elseif p.x >= r.width - edge - 4 and input.down("right") then try(1) end
end

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------
-- a camera pan (CameraTargetManager, the script camera commands): the
-- camera holds on (x, y) for `frames` while the world waits
function Field:panCamera(x, y, frames)
  self.pan = { x = x, y = y, t = frames }
end

function Field:snapCamera()
  local t = self.cameraTarget or self.player
  if self.pan then
    t = self.pan
    self.pan.t = self.pan.t - 1
    if self.pan.t <= 0 then self.pan = nil end
  end
  local r = self.room
  local cx = t.x - W / 2
  local cy = t.y - H / 2
  cx = math.max(0, math.min(cx, r.width - W))
  cy = math.max(0, math.min(cy, r.height - H))
  if r.width < W then cx = (r.width - W) / 2 end
  if r.height < H then cy = (r.height - H) / 2 end
  cx, cy = math.floor(cx), math.floor(cy)
  -- a camera moved by a script or a pan scrolls there (gRoomControls
  -- scrollSpeed px a frame, 2 by default) and back, instead of jumping
  if self.cameraTarget or self.pan or self.scrolling then
    local s = self.scrollSpeed or 2
    local dx, dy = cx - self.camX, cy - self.camY
    self.scrolling = math.abs(dx) > 0 or math.abs(dy) > 0
    self.camX = self.camX + math.max(-s, math.min(s, dx))
    self.camY = self.camY + math.max(-s, math.min(s, dy))
  else
    self.camX, self.camY = cx, cy
  end
end

function Field:updateFade()
  local step = self.fadeStep or (1 / 16)
  if self.fadeLevel < self.fadeTarget then self.fadeLevel = math.min(self.fadeTarget, self.fadeLevel + step)
  elseif self.fadeLevel > self.fadeTarget then self.fadeLevel = math.max(self.fadeTarget, self.fadeLevel - step) end
end

function Field:update(input)
  self.frame = self.frame + 1
  self:updateFade()

  local tr = self.transition
  if tr then
    if tr.phase == "out" and self.fadeLevel >= 1 then
      -- InitializePlayer clears the player state on every room change; the
      -- spawn type decides Minish size (PL_SPAWN_MINISH 1, DROP_MINISH 6, 9)
      local k = tr.exit.kind
      self.player.minish = (k == 1 or k == 6 or k == 9)
      self.player.animId = -1
      self:enterRoom(tr.exit.area, tr.exit.room, tr.x, tr.y, tr.facing)
      tr.phase = "in"
      self.fadeTarget = 0
    elseif tr.phase == "in" and self.fadeLevel <= 0 then
      self.transition = nil
    end
    return
  end

  if self.textbox then
    self.textbox:update({
      a = input.pressed("a"), b = input.pressed("b") or input.pressed("r"),
      left = input.pressed("left"), right = input.pressed("right"),
      up = input.pressed("up"), down = input.pressed("down"),
    })
    if self.textbox.done then
      self.textResult = self.textbox.result
      self.textbox = nil
    end
  end

  if self.gameOver then return self:updateGameOver(input) end
  if self.hud then self.hud:update(self.save.stats, function(id) self:sound(id) end) end
  if self.menu.open then
    self.menu:update(input)
    return
  end
  if self.intro then self:updateIntro() end
  if self.playerScript then
    self:runPlayerScript()
    self.player:update(input)
  elseif self.kinstone.active then
    self.kinstone:update(input)
  elseif not self.textbox then
    if input.pressed("start") and self.player.state == "normal" then self.menu:toggle() return end
    if input.pressed("l") then self.kinstone:openFuse() end
    -- SELECT asks Ezlo (offline; online SELECT is an emote)
    if input.pressed("select") and not self.game.net and self.player.hasCap then
      self:message(self.areaHint or 0x0B01, nil, nil, "ezlo")
    end
    self.player:update(input)
    self._dungeon:update(input)
    if self.player.state == "normal" and (input.down("up") or input.down("down") or input.down("left") or input.down("right")) then
      self._dungeon:tryDoor(self.player)
    end
    if self.player.state ~= "portal" and self.player.state ~= "dead" then self:checkExits(input) end
  else
    -- the item stays held up while its message shows
    if self.player.state == "itemget" then self.player:update(input) end
  end

  -- entities: scripts every frame, even under a text box (they wait on it)
  for i = #self.entities, 1, -1 do
    local e = self.entities[i]
    if e.script and not e.script.stopped then
      local ok, err = pcall(e.script.run, e.script, e, self)
      if not ok then e.script.stopped = true; self.game:log("script: " .. tostring(err)) end
      e.script:postActions(e)
    end
    if e.enemy or e.projectile then
      if not e.deleted then self._enemies:update(e) end
    elseif e.ground then
      if not e.deleted then self._objects:updateGround(e); e.anim:update(1) end
    elseif e.thrown then
      if not e.deleted then self._objects:updateThrown(e); e.anim:update(1) end
    elseif e.fx then
      e.anim:update(1)
      if e.anim.done then e.deleted = true end
    end
    if e.deleted then table.remove(self.entities, i)
    elseif e.literalAnim then
      local idx = e.objAnim or e.forceAnim or 0
      if not e.enemy and not e.projectile and idx ~= e.animIndex then
        e.animIndex = idx
        e.anim:set(self.assets:sprite(e.sprite), idx, true)
      end
    elseif e.sprite then
      local spr = self.assets:sprite(e.sprite)
      local idx = e.forceAnim or Script.npcAnimIndex(e)
      e.forceAnim = nil
      if idx ~= e.animIndex then e.animIndex = idx; e.anim:set(spr, idx, true) end
      e.anim:update(band(e.field82 or 0, 4) ~= 0 and 2 or 1)
    end
  end

  self:snapCamera()
  self:updateTileSwap()
  self.room:updateAnims()
  self:updateHudUi()
  for _, g in pairs(self.ghosts) do if g.update then g:update() end end
end

-- y-sorted sprites between the two BG layers
function Field:drawEntities()
  local list = {}
  for _, e in ipairs(self.entities) do
    if e.sprite and not e.hidden and not e.unplaced and not e.dying then list[#list + 1] = e end
  end
  if not self.intro then list[#list + 1] = self.player end
  for _, g in pairs(self.ghosts) do
    if g.area == self.room.area and g.room == self.room.room then list[#list + 1] = g end
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  self.drawList = list
  local A = self.assets
  local camX, camY = self.camX, self.camY
  -- GetPlayerPalette: object palette $16 (hurt blink $1A/$1B, charms $17-$19)
  local linkPal = A:objPalette(0x16)
  for _, e in ipairs(list) do
    if e == self.player then
      e:draw(camX, camY, linkPal)
    elseif e.drawGhost then
      e:drawGhost(self, camX, camY)
    elseif e.boss then
      self._enemies.boss:draw(e, camX, camY)
    else
      local frame = e.staticFrame or e.anim.frame
      if frame ~= 0xFF then
        local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette,
          "e" .. tostring(e.def and e.def.palette) .. ":" .. tostring(e.kind), e.gfx)
        if img and e.enemy and e.iframes > 0 and e.iframes % 4 < 2 then img = nil end
        if img then
          local x = math.floor(e.x - camX)
          local y = math.floor(e.y - camY - (e.z or 0))
          if e.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
          else love.graphics.draw(img, x + ox, y + oy) end
        end
      end
      if e.bubble then
        self:bubble(e, e.bubble == "?" and 1 or 0)
        e.bubble = nil
      end
    end
  end
end

-- THOUGHT_BUBBLE ($56) over who has one; its animation index is the kind
function Field:drawBubbles(list)
  local d = self._objects:def(0x56, 0)
  if not d then return end
  for _, e in ipairs(list) do
    if e.bubbleT and e.bubbleT > 0 then
      e.bubbleT = e.bubbleT - 1
      local s = self.assets:sprite(d.sprite)
      local keys = s and s.anims and s.anims[e.bubbleKind or 0]
      -- the animation pops in over a few frames and settles on its last
      -- keyframe (held 255): show the settled bubble
      local frame
      for _, k in ipairs(keys or {}) do if k[1] ~= 0xFF then frame = k[1] end end
      if frame then
        local img, ox, oy = self.assets:spriteFrame(d.sprite, frame, self.assets:objPalette(d.palette), "bubble",
          require("src.zelda.tmc.Assets").gfxSource(d.gfxType, d.gfx))
        if img then
          local bx, by = math.floor(e.x + e.bubbleOX - self.camX + ox), math.floor(e.y + e.bubbleOY - self.camY + oy)
          love.graphics.draw(img, bx, by)
          -- the red mark: the cartridge draws it from another frame of the
          -- same sprite; here it is the cartridge font's ! / ? in red
          local mark = ({ [0] = "!", [1] = "?" })[e.bubbleKind or 0]
          if mark and self.game.font then
            love.graphics.setFont(self.game.font)
            love.graphics.setColor(0.85, 0.1, 0.1, 1)
            local w = self.game.font:getWidth(mark)
            love.graphics.print(mark, bx + math.floor((img:getWidth() - w) / 2), by - 1)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
    end
  end
end

-- what R would do now (the R button's label)
function Field:rAction()
  local p = self.player
  if p.state == "carry" then return "Throw" end
  if p.minish and #self.portals > 0 and self._objects:portalNear(p) then return "Grow" end
  if self._objects:portalNear(p) and self:flag("global", 0x14) then return "Shrink" end
  local fx, fy = p:frontPoint(10)
  for _, e in ipairs(self.entities) do
    if not e.deleted and not e.hidden and math.abs(e.x - fx) + math.abs(e.y - fy) < 18 then
      if e.talkable then return "Talk" end
      if e.liftable then return "Lift" end
      if e.big and e.shown and not e.opened and p.animationState == 0 then return "Open" end
    end
  end
  return nil
end

-- the B / A / R buttons (InitUI: buttonX $B8 / $D0 / $D8, buttonY $1C /
-- $1C / $0E): the equipped items and the R action
-- the HUD's floating elements (ui.c through Ui.lua): A / B / R buttons,
-- the items on A / B, the R action label and the beating heart, drawn by
-- the cartridge's sprites into a transparent OBJ-only picture
local R_ACTIONS = { Throw = 3, Read = 4, Check = 5, Open = 6, Talk = 7, Grab = 8, Lift = 9,
                    Grow = 10, Shrink = 11 }
function Field:hudUi()
  if not self._hudUi then
    local Ppu = require("src.zelda.tmc.Ppu")
    local Ui = require("src.zelda.tmc.Ui")
    local p = Ppu.new(self.assets)
    p.transparent = true
    p.dispcnt = 0x1040
    for _, g in ipairs({ 16, 23 }) do p:loadGfxGroup(g) end
    p:loadGfxGroup(self:inventory(0x08) ~= 0 and 24 or 25)
    p:loadGfxGroup(self:inventory(0x0C) ~= 0 and 28 or 27)
    p:loadPaletteGroup(11); p:loadPaletteGroup(12)
    local ui = Ui.new(p)
    ui:initField()
    self._hudUi = ui
  end
  return self._hudUi
end

function Field:updateHudUi()
  local ui = self:hudUi()
  local s = self.save.stats
  ui:update({ equipped = { a = self:equipped("a"), b = self:equipped("b") },
              health = math.floor((s.health or 0) / 2),
              messageActive = self.textbox ~= nil,
              rAction = R_ACTIONS[self:rAction() or ""] or 0,
              counts = { [7] = { s.bombCount or 0, s.bombMax or 10 }, [9] = { s.arrowCount or 0, s.arrowMax or 30 } } })
end

function Field:drawButtons(font)
  local ui = self:hudUi()
  ui.ppu:flush()
  ui:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(ui.ppu:render(), 0, 0)
end

function Field:drawHud(font)
  local g = love.graphics
  local s = self.save.stats
  local info = self.room and self.room.areaInfo
  local keys = (info and (info.location or 0) >= 0x17) and self:dungeon():state().keys or nil
  if self.hud and self.hud:draw(s, keys) then self:drawButtons(font) return end
  local hearts = math.floor((s.maxHealth or 24) / 8)
  for i = 0, hearts - 1 do
    local hx, hy = 8 + (i % 10) * 9, 6 + math.floor(i / 10) * 8
    local fill = math.max(0, math.min(8, (s.health or 0) - i * 8)) / 8
    g.setColor(0.15, 0.05, 0.05, 1)
    g.polygon("fill", hx, hy + 2, hx + 2, hy, hx + 4, hy + 2, hx + 6, hy, hx + 8, hy + 2, hx + 4, hy + 7)
    if fill > 0 then
      g.setColor(0.95, 0.2, 0.25, 1)
      g.setScissor()
      g.polygon("fill", hx + 1, hy + 2, hx + 2, hy + 1, hx + 4, hy + 3, hx + 6, hy + 1, hx + 7, hy + 2, hx + 4, hy + 6)
    end
  end
  g.setFont(font)
  g.setColor(0.4, 1, 0.4, 1)
  g.print(string.format("%03d", s.rupees or 0), W - 34, H - 16)
  g.setColor(1, 1, 1, 1)
end

function Field:draw(font)
  local g = love.graphics
  local r = self.room
  local sx, sy = 0, 0
  if self.shakeT and self.shakeT > 0 then
    self.shakeT = self.shakeT - 1
    sx, sy = math.random(-self.shakeMag, self.shakeMag), math.random(-self.shakeMag, self.shakeMag)
  end
  local camX0, camY0 = self.camX, self.camY
  self.camX, self.camY = camX0 + sx, camY0 + sy
  local bd = r:backdrop()
  g.clear(bd[1], bd[2], bd[3], 1)
  g.setColor(1, 1, 1, 1)
  r:drawLayer("bottom", self.camX, self.camY)
  self:drawEntities()
  g.setColor(1, 1, 1, 1)
  if not self.debugNoTop then r:drawLayer("top", self.camX, self.camY) end
  if self.drawList then
    local l = self.drawList
    if self.intro then l = { self.player } end
    self:drawBubbles(l)
  end
  -- asleep in bed: the cartridge's BED_COVER object draws the blanket
  -- around him; here Link is drawn over the top layer instead
  if self.intro then self.player:draw(self.camX, self.camY, self.assets:objPalette(0x16)) end
  self:drawHud(font)
  if self.kinstone.active then self.kinstone:draw(font) end
  if self.menu.open then self.menu:draw(font) end
  if self.textbox then self.textbox:draw(font, W, H) end
  if self.toast then
    g.setColor(0, 0, 0, 0.6)
    g.rectangle("fill", 0, 20, W, 14)
    g.setColor(1, 1, 1, 1)
    g.printf(self.toast.text, 0, 21, W, "center")
    self.toast.t = self.toast.t - 1
    if self.toast.t <= 0 then self.toast = nil end
  end
  self.camX, self.camY = camX0, camY0
  if self.gameOver then self:drawGameOver(font) end
  if self.fadeLevel > 0 then
    local c = self.fadeWhite and 1 or 0
    g.setColor(c, c, c, self.fadeLevel)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function Field:showToast(text, frames)
  self.toast = { text = text, t = frames or 120 }
end

return Field
