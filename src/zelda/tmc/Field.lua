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
  -- round 10: a game saved at Minish size continues at Minish size (the
  -- cartridge keeps the spawn type in gSave.saved_status)
  self._startMinish = st.minish
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
-- Bug round (user report: "can't open chests"): sub_080782C0 runs before
-- the item buttons and takes A (INPUT_INTERACT) as well as R (INPUT_ACTION)
-- for talking, signs, chests and key doors. Lifting (IsTryingToPickupObject,
-- INPUT_LIFT_THROW), portals and rolling stay on R.
function Field:tryInteractA(player)
  if self:tryInteract(player) then return true end
  if self._dungeon:tryAction(player) then return true end
  return self._objects:tryAction(player, true)
end

function Field:tryAction(player)
  if self:tryInteract(player) then return true end
  if require("src.zelda.tmc.CrenelPath").liftBean(self, player) then return true end -- round 8: the Crenel bean
  if require("src.zelda.tmc.Bombs").tryLift(self, player) then return true end -- round 20: a placed bomb (RegisterCarryEntity)
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
function Field:giveItem(item, param, delay)
  local s = self.save.stats
  local pieces0 = s.heartPieces or 0 -- round 22: the piece-of-heart message counts the pieces before this one
  local bottled = require("src.zelda.tmc.CrenelPath").giveItem(self, item) -- round 8: bottles
  require("src.zelda.tmc.ItemsR26").giveItem(self, item, param) -- round 26A: GiveItem's item/stat cases (boomerangs, quiver, arrows, wallet)
  local r27 = require("src.zelda.tmc.R27A").giveItem(self, item, param) -- round 27A: figurines, side-quest items (R27A.lua)
  if bottled or r27 then -- the contents went into a bottle
  elseif item == 0x5C then
    self.kinstone:addPiece(param)
  elseif item == 0x65 then -- round 18: ITEM_BOMBBAG (Bombs.lua, GiveItem case 8)
    require("src.zelda.tmc.Bombs").giveBag(self)
  elseif item == 0x6C or item == 0x6D then -- round 18: ITEM_BOMBS10 / 30 (GiveItem case 9: ModBombs)
    require("src.zelda.tmc.Bombs").mod(self, item == 0x6C and 10 or 30)
  elseif item >= 0x50 and item <= 0x53 then -- map, compass, big key, small key
    self._dungeon:give(item)
  elseif item >= 0x54 and item <= 0x59 then -- ITEM_RUPEE1 .. ITEM_RUPEE200
    self:modStat("rupees", ({ [0x54] = 1, [0x55] = 5, [0x56] = 20, [0x57] = 50, [0x58] = 100, [0x59] = 200 })[item])
  elseif item == 0x3F then -- ITEM_SHELLS
    self:modStat("shells", math.max(1, param or 0))
  elseif item == 0x5F then -- ITEM_HEART
    self:modStat("health", 8)
  elseif item == 0x60 then -- round 20: ITEM_FAIRY (gItemMetaData type 1: ModHealth($20), a touched fairy healed nothing)
    self:modStat("health", 0x20)
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
    -- round 10: GiveItem -> PutItemOnSlot (itemUtils.c): only button items
    -- 1..$1F are equipped, on A if empty, else B if empty, else on the
    -- button holding the same menu slot (the shield lands on A, the Smith's
    -- Sword then on B; quest items such as $35 are never equipped)
    require("src.zelda.tmc.Ceremony").putItemOnSlot(self, item)
  end
  local meta = self.assets.manifest.itemMeta and self.assets.manifest.itemMeta[item]
  local text = meta and meta.text or 0
  if (delay or 0) ~= 0 and self.player then
    -- round 22: InitItemGetSequence's other timers (ItemGet.lua)
    require("src.zelda.tmc.ItemGet").start(self, item, param, delay, pieces0)
  elseif text ~= 0 and self.assets:message(text) then
    -- round 22: Link raises the item first; SFX_ITEM_GET on his frame flag
    -- $41, the message on $42 (linkHoldingItem.c, ItemGet.lua)
    require("src.zelda.tmc.ItemGet").start(self, item, param, 0, pieces0)
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
  -- a plain fade ends an iris (DispReset / sub_0801E104); a closed iris
  -- was a black screen, so the plain fade carries on from black
  if self.iris then
    if self.iris.out and self.iris.size <= 0 then self.fadeLevel = 1; self.fadeWhite = false end
    self.iris = nil
  end
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
-- (objectUtils.c CreateSpeechBubble + thoughtBubble.c: timer 45, kind 2
-- stays; SFX_METAL_CLINK for "!", SFX_F3 for "?"; the animation is played)
function Field:bubble(who, kind, ox, oy)
  who.bubbleKind, who.bubbleT, who.bubbleAge = kind, (kind == 2) and 0x7FFFFFFF or 45, 0
  who.bubbleStart, who.bubbleAnim = self.frame or 0, nil
  local sfx = ({ [0] = 0x74, [1] = 0xF3 })[kind]
  if sfx and self.sound then self:sound(sfx) end
  if os.getenv and os.getenv("TMC_DEBUG") then self.game:log("bubble " .. kind .. " at frame " .. self.frame) end
  who.bubbleOX, who.bubbleOY = ox or 8, oy or -24
end

-- the script host's Call / CallWithArg
function Field:callNative(fn, e, ctx)
  return Native.call(self, fn, e, ctx, Script.active)
end

function Field:fadeActive()
  return self.fadeLevel ~= self.fadeTarget or (self.iris ~= nil and self.iris.active)
end

-- SetFadeIrisForCameraTarget / SetFadeIris (fade.c): a circular window
-- around the camera target.  `out` (FADE_IN_OUT) closes it from size $96
-- to 0, otherwise it opens from 0 and the window is dropped past 150
-- (palettes unfaded: FADE_INSTANT is cleared, ResetFadeMask).  The
-- size moves by the fade speed each frame (sub_080502A4); outside the
-- window nothing is drawn (win_outside_cnt 0).
function Field:fadeIris(out, speed)
  local p = self.player
  local x, y = 120, 80
  if p then x, y = math.floor(p.x) - math.floor(self.camX), math.floor(p.y) - math.floor(self.camY) end
  self.iris = { out = out and true or false, x = x, y = y, size = out and 0x96 or 0,
                speed = speed or self.fadeSpeed or 16, active = true }
  if not out then self.fadeLevel, self.fadeTarget = 0, 0 end
end

-- FadeMain's iris step
function Field:updateIris()
  local ir = self.iris
  if not ir or not ir.active then return end
  if ir.out then
    ir.size = ir.size - ir.speed
    if ir.size <= 0 then ir.size = 0; ir.active = false end
  else
    ir.size = ir.size + ir.speed
    if ir.size > 150 then self.iris = nil end
  end
end

-- sub_0801E24C + sub_0801E290: the window's per-scanline span for a circle
-- of radius `r` at (cx, cy).  Returns rows[0..159] = {x1, x2} (shown
-- columns x1 <= x < x2; {0, 0} = the row is all outside).
function Field.irisSpans(cx, cy, r)
  local half = {}
  local i, r2 = 0, r
  local d = 3 - r2 * 2
  while i <= r2 do
    half[i] = r2; half[r2] = i
    if d < 0 then d = d + 6 + i * 4; i = i + 1
    else d = d + 10 + (i - r2) * 4; i = i + 1; r2 = r2 - 1 end
  end
  local rows = {}
  for y = 0, 159 do rows[y] = { 0, 0 } end
  for k = 0, r - 1 do
    local h = half[k] or 0
    local x1, x2 = cx - h, cx + h
    if x1 < 0 then x1 = 0 end
    if x2 > 0xEF then x2 = 0xF0 end
    local yb, yf = cy - k, cy + k
    if yb >= 0 and yb < 160 then rows[yb] = { x1, x2 } end
    if yf >= 0 and yf < 160 then rows[yf] = { x1, x2 } end
  end
  return rows
end

function Field:drawIris()
  local ir = self.iris
  if not ir then return end
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  local rows = Field.irisSpans(ir.x, ir.y, math.max(0, math.floor(ir.size)))
  for y = 0, 159 do
    local x1, x2 = rows[y][1], rows[y][2]
    if x2 <= x1 then g.rectangle("fill", 0, y, 240, 1)
    else
      if x1 > 0 then g.rectangle("fill", 0, y, x1, 1) end
      if x2 < 240 then g.rectangle("fill", x2, y, 240 - x2, 1) end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
function Field:message(index, entity, pos, kind)
  local bytes = self.assets:message(index)
  if not bytes then return end
  local top = self.player and (self.player.y - self.camY) > 100
  self.textbox = TextBox.new(bytes, { playerName = self.save.name, top = top, assets = self.assets,
    number = self.messageRupees, continue = function(id) return self.assets:message(id) end }) -- round 8
  self.messageRupees = nil
  self.textOwner = entity
  self.textKind = kind
end

function Field:messageActive() return self.textbox ~= nil or require("src.zelda.tmc.ItemGet").pending(self) end -- round 22: an item's message still to come

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
function Field:startIntro(script, x, y)
  self.intro = { phase = "sleep" }
  self.player.scriptAnim = 0x73A
  self.player.x, self.player.y, self.player.animationState = x or 0x90, y or 0x38, 4
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
  -- round 9: sub_unk3_HyruleTown_0 (src/roomInit.c): at global progress 1
  -- Hyrule Town is swapped for the festival town (area $15) before the
  -- room loads, ZELDA_CHASE ($1C) is set (so CreateZeldaFollower puts
  -- Zelda behind Link), and Link starts at the middle of the room's width
  -- (gRoomTransition.player_status.start_pos_x = pixel_width >> 1)
  if area == 0x02 and room == 0x00 then
    self:updateProgress()
    if (self.save.progress or 1) == 1 then
      self:setFlag("global", 0x1C, true)
      area = 0x15
      local fr = Room.load(self.assets, 0x15, 0x00)
      if fr and fr.width then x = math.floor(fr.width / 2) end
    end
  end
  local r, err = Room.load(self.assets, area, room)
  if not r then
    -- an unknown room (a special-map room or a bad save): fall back to
    -- the new-game room rather than a black screen
    self.game:log("room " .. area .. ":" .. room .. " failed: " .. tostring(err))
    r = assert(Room.load(self.assets, 0x22, 0x15))
    x, y = 0x90, 0x38
  end
  -- round 9: the festival room takes the town's place in the world map
  -- (sub_unk3_HyruleTown_0: map_x = town map_x + $130, map_y = town's), so
  -- its border exits land where the town's would
  if area == 0x15 and room == 0x00 then
    local tr = Room.load(self.assets, 0x02, 0x00)
    if tr and tr.x then r.x, r.y = tr.x + 0x130, tr.y end
  end
  self.assets:dropAtlases(area)
  self.room = r
  self.assets.curBg = r.atlas and r.atlas.palettes -- round 13: OBJ palette 5 / BG-copy palettes
  self.roomFlags = {}
  self.entities = {}
  self.portals = {}
  if self._dungeon then self._dungeon:reset() end
  self.cameraTarget = nil
  self.camFree = nil -- round 14 (Seamless.lua sets it again after a scroll)
  self.entry = { area = area, room = room, x = x, y = y, facing = facing }
  Script.resetSync()
  if not self.player then self.player = Player.new(self, x, y, facing)
    if self._startMinish then self.player.minish = true; self._startMinish = nil end -- round 10
  else
    self.player.x, self.player.y = x, y
    if facing then self.player.animationState = facing end
    self.player.state = "normal"
    -- bug round: ClearPlayerState (InitializePlayer) drops the held object
    -- on a room change; a pot carried out of a door stayed drawn over Link
    self.player.carried = nil
    -- round 8: a scene cut off by a warp leaves no script animation on Link
    -- (the room's script entities are gone; a player script still running
    -- across the change keeps its own)
    if not self.playerScript then self.player.scriptAnim, self.player.scriptWalking = nil, nil end
    self.player.extUpdate, self.player.climbing = nil, nil
    -- round 23: InitializePlayer sets collisionLayer from player_status.layer;
    -- a room change without a transition layer starts on layer 1 (the
    -- tile-type flags, Layers.surface, move him from there)
    if not self.cartRide then self.player.layer = 1 end -- (a mine cart ride keeps its rails' layer: Minecart.onEnterRoom)
  end
  -- PL_NO_CAP until Ezlo joins (InitializePlayer checks EZERO_1ST)
  self.player.hasCap = self:flag("global", Field.FLAG_EZERO_1ST)
  self.player.animId = -1
  local st = self.save.status
  st.area, st.room, st.x, st.y, st.facing = area, room, x, y, self.player.animationState
  st.minish = self.player.minish or nil -- round 10
  self:updateProgress()
  self.queuedBgm = nil
  self.save.visited = self.save.visited or {}
  self.save.visited[area * 256 + room] = true
  require("src.zelda.tmc.Drops").roomLoaded(self) -- round 9: the area droptable, drops on
  require("src.zelda.tmc.Bombs").roomLoaded(self) -- round 18: bombable walls, destructible tiles
  self:spawnRoomEntities()
  require("src.zelda.tmc.ZeldaFollower").ensure(self) -- round 6: CreateZeldaFollower / ENT_PERSIST
  pcall(self.kinstone.applyWorldEvents, self.kinstone)
  self._objects:roomLoaded()
  self:snapCamera()
  self.swapGroups = {}
  self:updateTileSwap()
  -- gArea.queued_bgm when room code set one, else the area's
  if self.queuedBgm then self:bgm(self.queuedBgm) else self:bgm("area") end
  pcall(require('src.zelda.tmc.MapMenu').roomEntered, self) -- round 5: map status, visit tiles
  require("src.zelda.tmc.Minecart").onEnterRoom(self) -- round 7: a ride crossing rooms
  require("src.zelda.tmc.LilyRide").onEnterRoom(self) -- round 16: a lily pad crossing rooms
  self.game:onRoomChanged(area, room)
end

function Field:spawnRoomEntities()
  local lists = self.room.entities
  self._specialWarps = nil -- round 10: SpecialWarp.lua lists of this room
  self:loadEntityList(nil, lists[1])
  self:loadEntityList(nil, lists[0])
  if self:flag("global", Field.FLAG_TABIDACHI) then self:loadEntityList(nil, lists[2]) end
  local code = self.game.roomCode and self.game.roomCode[self.room.area * 256 + self.room.room]
  if code then pcall(code, self) end
  require("src.zelda.tmc.R26").roomInit(self) -- round 26b: dungeon room init (R26.lua)
  require("src.zelda.tmc.R27A").roomInit(self) -- round 27A: overworld room init (R27A.lua)
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
        paramB = blob:byte(q + 3), type2 = blob:byte(q + 3), pool = script ~= 0 and 0x4F or 0x0F,
        x = u16(blob, q + 4), y = u16(blob, q + 6), paramC = script,
      })
    end
  end
end

-- UpdateGlobalProgress (src/gameUtils.c): the story stage, from flags
function Field:updateProgress()
  local p = 1
  -- round 9: USA flag ids (SEIIKI_STAINED_GLASS $78, SOUGEN_08_TORITSUKI $9C)
  if self:flag("bank", 0x78, 0x300) then p = 9           -- SEIIKI_STAINED_GLASS
  elseif self:flag("global", 6) then p = 8              -- LV5_CLEAR
  elseif self:flag("bank", 50, 0x300) then p = 7        -- OUBO_KAKERA
  elseif self:flag("global", 5) then p = 6              -- LV4_CLEAR
  elseif self:flag("global", 4) then p = 5              -- LV3_CLEAR
  elseif self:flag("bank", 0x9C, 0x100) then p = 4      -- SOUGEN_08_TORITSUKI
  elseif self:flag("global", 2) then p = 2 end          -- LV1_CLEAR
  self.save.progress = p
end

-- LoadRoomEntityList(ptr) from a script or room code, or a list table
function Field:loadEntityList(addr, list)
  list = list or (addr and self:entityListAt(addr))
  if not list then return end
  self.listSerial = (self.listSerial or 0) + 1
  for i, d in ipairs(list) do
    if addr then
      self.spawnKey = string.format("%02x:%02x:%s:%d", self.room.area, self.room.room, tostring(addr), i)
    else
      -- round 19: a list without a ROM address is keyed by the entity's own
      -- data (stable per room and entity; the table's address changed every
      -- run, so placed rupees came back after a reload)
      self.spawnKey = string.format("%02x:%02x:e%x:%x:%x:%x:%d:%d", self.room.area, self.room.room, d.kind or 0, d.id or 0,
        d.paramA or 0, d.paramB or 0, d.x or 0, d.y or 0)
    end
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
    require("src.zelda.tmc.Fusers").onSpawn(self, e, d) -- round 6: GetFuserId / GetFusionToOffer
    require("src.zelda.tmc.NpcParts").attach(self, e) -- round 7: LoadExtraSpriteData
    if d.id == 0x57 then e.staticFrame = 0 end -- round 17: PHONOGRAPH sets frameIndex 0 itself (phonograph.c)
  end
  if band(d.pool, 0xF0) == 0x40 and d.paramC ~= 0 and self.mem and self.mem:valid(d.paramC) then
    e.script = Script.new(self.mem, d.paramC)
  end
  if d.kind == KIND.NPC and not e.script then require("src.zelda.tmc.RouteNatives").npcSpawn(self, e, d) end -- round 10
  if d.kind == KIND.ENEMY and not e.script then
    local en = self._enemies:spawn(d)
    if en and not en.layer then
      -- round 23: LoadRoomEntity (room.c) for enemies too: the kind byte's
      -- layer ($20 -> 2, $10 -> 1), else ResolveCollisionLayer
      local cl = band(d.collision or 0, 3)
      en.layer = (cl == 1 or cl == 2) and cl or require("src.zelda.tmc.Layers").resolve(self, en)
    end
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
    if d.id == 0x06 then require("src.zelda.tmc.SpecialWarp").add(self, d) end -- round 10: SPECIAL_WARP_MANAGER
    return nil
  end
  if d.kind == KIND.OBJECT then
    local O = self._objects
    if d.id == Objects.OBJ.GROUND_ITEM and not e.script then
      -- an item placed in the room: once taken it stays taken
      local key = self.spawnKey
      if key and self:collected(key) then return nil end
      -- round 9: entity->timer = paramB >> 8 is ItemOnGround's kind; kind 7
      -- (buried: the red rupees by Link's house, dug up with the Mole Mitts)
      -- and 8 (sunken: found by diving) start with spriteSettings.draw = 0
      local gk = band(rshift(d.paramB or 0, 8), 0xFF)
      local gi = O:groundItem(d.paramA, band(d.paramB, 0xFF), d.x, d.y, { key = key, kind = gk })
      if gi and (gk == 7 or gk == 8) then
        gi.hidden, gi.buried = true, gk
        gi.originalTile = self.room:tileType(1, math.floor(d.x / 16), math.floor(d.y / 16))
      end
      return gi
    end
    local def = O:def(d.id, d.paramA)
    if def and def.draw ~= 0 then
      O:dress(e, def, 0)
      e.objAnim = 0
      if d.id == Objects.OBJ.POT then
        e.liftable = true; e.solid = true
        -- round 16: Pot_Init: the kind byte's layer ($10 -> 1, $20 -> 2), else
        -- ResolveCollisionLayer (room $15's pots stand on the raised floor)
        local cl = band(d.collision or 0, 3)
        e.layer = (cl == 1 or cl == 2) and cl or require("src.zelda.tmc.Layers").resolve(self, e)
      end
    end
    -- round 7: furniture, archways, masks...: a fixed frame set by their init
    local OS = require("src.zelda.tmc.ObjStatic")
    if def and OS.FRAME[d.id] then
      if not e.sprite then O:dress(e, def, 0); e.objAnim = 0 end
      OS.apply(self, e, d)
    end
    -- round 15: an entity starts zeroed, so an object whose Init sets no
    -- frame and starts no animation shows its frame 0 (the cartridge's
    -- frameIndex 0) until something animates it
    if def and e.sprite and not e.staticFrame then
      local spr = self.assets:sprite(e.sprite)
      if not (spr and spr.anims and spr.anims[0]) then e.zeroFrame = true end
    end
  end
  -- round 10: CutsceneObj.lua C-only types (the Jabber Nut, $6A type 7)
  local cOnly = d.kind == KIND.OBJECT and d.id == 0x6A and d.paramA == 0x07
  if d.kind == KIND.NPC or e.script or (d.kind == KIND.OBJECT and e.sprite) or cOnly then
    self.entities[#self.entities + 1] = e
  end
  return e
end

-- NPCs are solid to Link (their hitbox is about 12x8 at the feet)
function Field:entityBlocks(who, x, y)
  -- round 10: Minish Link's hitbox is a quarter of Link's (sub_080085CC's
  -- Minish table; the overlap test sums both half sizes): the Minish
  -- Village's doorways have room for him beside a villager
  local hx, hy = 10, 7
  if who and who.minish then hx, hy = 6, 4 end
  -- round 11: with the ROM's hitboxes (manifest.r11) NPCs no longer block;
  -- the solid ones push Link out as the cartridge does (Hitboxes.lua)
  local r11 = self.assets.manifest.r11 ~= nil
  for _, e in ipairs(self.entities) do
    if e.solid and not e.hidden and not e.deleted and not e.unplaced and e ~= who and not (r11 and e.kind == 7) then
      local hit
      if e.liftable and e.id == 0x05 and not e.pushT and who and not who.minish then
        -- round 12: a pot stands on SPECIAL_TILE_0, a solid tile (pot.c
        -- Pot_Init): Link's box against the whole tile, so he leans on it
        -- (and pushes it) instead of slipping round its smaller box
        local tl, tt = math.floor(e.x / 16) * 16, math.floor(e.y / 16) * 16
        local function over(px, py) return px - 4 < tl + 16 and px + 4 > tl and py - 5 < tt + 16 and py + 2 > tt end
        if over(x, y) and (not over(who.x, who.y)
           or math.abs(x - tl - 8) + math.abs(y - 3 - tt - 8) < math.abs(who.x - tl - 8) + math.abs(who.y - 3 - tt - 8)) then return true end
        hit = false
      else
        hit = math.abs(e.x - x) < hx and math.abs(e.y - y) < hy
      end
      if hit then
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
  local HB = require("src.zelda.tmc.Hitboxes") -- round 11: sub_080784E4's point and box
  for _, e in ipairs(self.entities) do
    local hit = e.talkable and not e.hidden and not e.deleted and HB.interactHit(self, player, e)
    if hit ~= nil and e.talkable and not e.hidden and not e.deleted then
      -- INTERACTION_CHECK objects answer full-size Link only
      if hit and not (e.kind == 6 and player.minish) then
        local d = math.abs(e.x - player.x) + math.abs(e.y - player.y)
        if not bestD or d < bestD then best, bestD = e, d end
      end
    elseif e.talkable and not e.hidden and not e.deleted then
      local d = math.abs(e.x - fx) + math.abs(e.y - fy)
      -- round 10: a checkable object on a raised spot (the Jabber Nut on
      -- the barrel Minish's leaf table) reaches a little further, as its
      -- hitbox does on the cartridge (AddInteractableCheckableObject)
      local reach = (e.kind == 6) and 24 or 18
      if d < reach and (not bestD or d < bestD) then best, bestD = e, d end
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

-- round 15: HyruleTownTileSetManager_BuildSecondOracleHouse: when slot 1
-- loads group 2, the red house's metatiles (SetTileByIndex: metatile
-- indices) by story flag: TATEKAKE_HOUSE ($18) the finished house,
-- TATEKAKE_TOCHU ($19) its frame; neither: the empty lot of the ROM map
Field.FLAG_TATEKAKE_HOUSE, Field.FLAG_TATEKAKE_TOCHU = 0x18, 0x19
function Field.buildOracleHouse(r, house, tochu)
  if house then
    for l = 0, 3 do for i = 0, 3 do r:setTile(1, 2 + i, 24 + l, 1195 + l * 16 + i) end end
    for l = 0, 2 do for i = 0, 3 do r:setTile(2, 2 + i, 24 + l, 1088 + l * 16 + i) end end
    r:setTile(2, 2, 23, 214); r:setTile(2, 3, 23, 215)
  elseif tochu then
    for l = 0, 4 do for i = 0, 3 do r:setTile(1, 2 + i, 24 + l, 1190 + l * 16 + i) end end
    r:setTile(2, 2, 24, 1092); r:setTile(2, 5, 24, 1093)
    r:setTile(2, 2, 25, 1108); r:setTile(2, 5, 25, 1109)
  end
end

-- round 14: the tileset manager's choice for a camera at (camX, camY) in
-- `room`, as a swap spec for Room:applySwap; `groups` (slot -> group) is
-- the previous choice and is updated.  Returns spec, changed.
function Field.swapFor(assets, room, camX, camY, groups)
  local defs = assets.manifest.tileSwaps
  local def = defs and defs[room.area * 256 + room.room]
  if not def then return nil, false end
  local changed = false
  for si, regions in ipairs(def.slots) do
    local hit = false
    for _, r in ipairs(regions) do
      if regionOnScreen(camX, camY, r) then
        if groups[si] ~= r[1] then groups[si] = r[1]; changed = true end
        hit = true
        break
      end
    end
    -- Not the cartridge: if a slot has never matched (the camera starts
    -- outside every region) the cartridge would show whatever VRAM held --
    -- the default tileset, i.e. smeared tiles.  Load the nearest region's
    -- group instead.
    if not hit and groups[si] == nil and #regions > 0 then
      local best, bd = nil, math.huge
      local cx, cy = camX + W / 2, camY + H / 2
      for _, r in ipairs(regions) do
        local dx = math.max(r[2] - cx, 0, cx - (r[2] + r[4]))
        local dy = math.max(r[3] - cy, 0, cy - (r[3] + r[5]))
        local d = dx * dx + dy * dy
        if d < bd then best, bd = r[1], d end
      end
      groups[si] = best
      changed = true
    end
  end
  local A = assets
  A.swapBlobs = A.swapBlobs or {}
  local blob = A.swapBlobs[def.file]
  if not blob then blob = A.store:read(def.file) or ""; A.swapBlobs[def.file] = blob end
  local blocks, keyParts, pals = {}, {}, nil
  for si = 1, #def.slots do
    local g = groups[si]
    keyParts[#keyParts + 1] = tostring(g)
    if g and def.groups[g] then
      for _, b in ipairs(def.groups[g]) do
        blocks[#blocks + 1] = { b[3], blob:sub(b[1] + 1, b[1] + b[2]) }
      end
    end
  end
  local g1 = groups[1]
  if def.palettes and g1 and def.palettes[g1] then pals = { def.palettes[g1] } end
  -- round 15: the finished red house's graphics (BuildSecondOracleHouse)
  if def.oracle and groups.oracle and groups[2] == 2 then
    A.swapBlobs[def.oracle.file] = A.swapBlobs[def.oracle.file] or A.store:read(def.oracle.file) or ""
    blocks[#blocks + 1] = { def.oracle.vram, A.swapBlobs[def.oracle.file] }
    keyParts[#keyParts + 1] = "oracle"
  end
  return { key = table.concat(keyParts, ","), blocks = blocks, paletteGroups = pals }, changed
end

function Field:updateTileSwap()
  local r = self.room
  if r.area == 0x02 and r.room == 0x00 then self.swapGroups.oracle = self:flag("global", Field.FLAG_TATEKAKE_HOUSE) or nil end
  local spec, changed = Field.swapFor(self.assets, self.room, self.camX, self.camY, self.swapGroups)
  if not (spec and changed) then return end
  if r.area == 0x02 and r.room == 0x00 and self.swapGroups[2] == 2 and not r._oracleBuilt then
    r._oracleBuilt = true
    Field.buildOracleHouse(r, self:flag("global", Field.FLAG_TATEKAKE_HOUSE), self:flag("global", Field.FLAG_TATEKAKE_TOCHU))
  end
  self.room:applySwap(spec)
  self.assets:dropAtlases(self.room.area, self.room.area * 256 + self.room.maps.header.ts .. ":" .. spec.key)
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
  -- round 14 (Seamless.lua): a scroll, a crossfade, or the cartridge's fade
  require("src.zelda.tmc.Seamless").plan(self, self.transition, exit, dir)
  if self.transition.kind == "cart" then self.fadeTarget = 1 end
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
  if require("src.zelda.tmc.Story27Town").closedDoorAhead(self, p) then return nil end -- round 27A: a closed scripted HOUSE_DOOR_EXT blocks its doorway
  local fx, fy = p:frontPoint(8)
  local found = false
  local ftx, fty
  for _, dy in ipairs({ 0, 2, 4 }) do
    local tx, ty = math.floor(fx / 16), math.floor((fy + dy) / 16)
    local ttype = r:tileType(p.layer, tx, ty)
    if ttype and ttype < 0x4000 then
      local act = self.assets.actTile[ttype] or 0
      if act == Field.ACT_TILE_STAIRS or act == Field.ACT_TILE_DOOR then found = true; ftx, fty = tx, ty break end
    end
  end
  if not found then return nil end
  -- round 14 (DoorWalk.lua): ACT_TILE_41 ($29) is a walkable threshold on
  -- the cartridge (Link walks on to the room edge, under the door's
  -- ARCHWAY); only a solid one still works as a door here
  local fact = self.assets.actTile[r:tileType(p.layer, ftx, fty) or 0]
  if fact == Field.ACT_TILE_DOOR and r.coll and (r.coll[p.layer == 2 and 2 or 1][fty * r.tw + ftx] or 0) ~= 0x0F then return nil end
  -- round 14: ACT_TILE_40 with an area transition: PLAYER_ROOM_EXIT (Link
  -- steps into the doorway; the transition rectangle then warps)
  if fact == Field.ACT_TILE_STAIRS then
    local DW = require("src.zelda.tmc.DoorWalk")
    local tr = DW.enterTransition(self, p)
    if tr then DW.startEnter(self, p, tr) return nil end
  end
  -- round 11: a door with no warp of its own only leads on through the
  -- room edge it sits on (the door Link just came in by, under his feet,
  -- must not send him through the far side of the room)
  local function onFacedEdge()
    if not (r.width and r.height) then return true end
    local s = p.animationState
    local tw, th = math.floor(r.width / 16), math.floor(r.height / 16)
    if s == 0 then return fty <= 4 elseif s == 4 then return fty >= th - 5
    elseif s == 6 then return ftx <= 4 else return ftx >= tw - 5 end
  end
  for d = 4, 16, 4 do
    local ex, ey = p:frontPoint(d)
    local e = r:areaExitAt(ex, ey + 2)
    if e then return e end
  end
  -- bug round: a house door with no area warp beyond it lets Link out
  -- through the room's border warp on that side (Link's house: the south
  -- border warp to South Hyrule Field). The door tile is solid here, so
  -- walking could never reach the edge on a new game.
  if not onFacedEdge() then return nil end
  local bdir = p.animationState / 2
  local bx = r:borderExit(bdir, p.x, p.y)
  if bx then return bx, bdir end
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
  if require("src.zelda.tmc.SpecialWarp").update(self) then return end -- round 10
  local e = r:areaExitAt(math.floor(p.x), math.floor(p.y)) -- round 14: x.HALF.HI
  if e then return self:startTransition(e) end
  local d, ddir = self:doorExit(input)
  if d then return self:startTransition(d, ddir) end
  local edge = 3
  local function try(dir)
    local ex = r:borderExit(dir, p.x, p.y) or self:adjacentRoom(dir)
    if ex then self:startTransition(ex, dir) end
  end
  -- round 19: UpdatePlayerCollision (beanstalkSubtask.c) + sub_0807BDB8:
  -- moving towards an edge within 10 px of it, with the tile just ahead
  -- (gUnk_080B4490: N (0,-9) E (6,0) S (0,3) W (-6,0)) of collision $FF,
  -- takes the border exit.  (Link stopped by a $FF bottom row at y 792 of
  -- an 800-high room never reached the old height - 3 test.)
  do
    local u, dn, l, rt = input.down("up"), input.down("down"), input.down("left"), input.down("right")
    local x, y = math.floor(p.x), math.floor(p.y)
    local AHEAD = { [0] = { 0, -9 }, { 6, 0 }, { 0, 3 }, { -6, 0 } }
    local function edgeTile(i)
      local o = AHEAD[i]
      local tx, ty = math.floor((x + o[1]) / 16), math.floor((y + o[2]) / 16)
      if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return true end
      return (r.coll[p.layer == 2 and 2 or 1][ty * r.tw + tx] or 0) == 0xFF
    end
    local idx
    if u and not (l or rt) then if y < 10 then idx = 0 end
    elseif u and rt then if y < 10 then idx = 0 end; if r.width - 10 < x then idx = 1 end
    elseif rt and not (u or dn) then if r.width - 10 < x then idx = 1 end
    elseif dn and rt then if r.height - 10 < y then idx = 2 end; if r.width - 10 < x then idx = 1 end
    elseif dn and not (l or rt) then if r.height - 10 < y then idx = 2 end
    elseif dn and l then if r.height - 10 < y then idx = 2 end; if x < 10 then idx = 3 end
    elseif l and not (u or dn) then if x < 10 then idx = 3 end
    elseif u and l then if y < 10 then idx = 0 end; if x < 10 then idx = 3 end end
    if idx and not p.carried and edgeTile(idx) then
      local ex = r:borderExit(idx, p.x, p.y) or self:adjacentRoom(idx)
      if ex then return self:startTransition(ex, idx) end
    end
  end
  if p.y <= edge + 6 and input.down("up") then try(0)
  elseif p.y >= r.height - edge and input.down("down") then try(2)
  elseif p.x <= edge + 4 and input.down("left") then try(3)
  elseif p.x >= r.width - edge - 4 and input.down("right") then try(1) end
end

-- the room change itself (all kinds of transition)
function Field:transitionSwitch(tr)
  -- InitializePlayer clears the player state on every room change; the
  -- spawn type decides Minish size (PL_SPAWN_MINISH 1, DROP_MINISH 6, 9)
  local k = tr.exit.kind
  self.player.minish = (k == 1 or k == 6 or k == 9)
  self.player.animId = -1
  self:enterRoom(tr.exit.area, tr.exit.room, tr.x, tr.y, tr.facing)
  if tr.exit.layer and tr.exit.layer > 0 then self.player.layer = tr.exit.layer end -- round 13: a hole's layer
  if tr.exit.layer == 0 then self.player.layer = require("src.zelda.tmc.Layers").resolve(self, self.player) end -- round 23: layer 0 -> ResolveCollisionLayer (player.c PlayerInit)
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
  -- round 14 (Seamless.lua): after a seamless room change the camera
  -- eases from where it was to here
  if self.camFree then require("src.zelda.tmc.Seamless").ease(self, cx, cy) end
end

function Field:updateFade()
  self:updateIris()
  local step = self.fadeStep or (1 / 16)
  if self.fadeLevel < self.fadeTarget then self.fadeLevel = math.min(self.fadeTarget, self.fadeLevel + step)
  elseif self.fadeLevel > self.fadeTarget then self.fadeLevel = math.max(self.fadeTarget, self.fadeLevel - step) end
end

function Field:update(input)
  self.frame = self.frame + 1
  -- UpdatePlayerInput: a running player macro replaces the pad (round 5)
  -- round 9: the message box reads gInput itself (the pad), not the
  -- macro: the festival's TryOutShield macro runs under message $2C
  local padInput = input
  -- round 9: gInput.newKeys for CheckAnyKeyPressed
  self.anyKeyPressed = false
  for _, k in ipairs({ "a", "b", "l", "r", "start", "select", "up", "down", "left", "right" }) do
    if input.pressed(k) then self.anyKeyPressed = true break end
  end
  if self.playerMacro then input, self.macroInput = require("src.zelda.tmc.PlayerMacro").frame(self, input) else self.macroInput = false end
  if self.frame % 8 == 0 then require('src.zelda.tmc.MapMenu').track(self) end -- round 5: UpdatePlayerMapCoords / UpdateWindcrests
  self:updateFade()
  require("src.zelda.tmc.Bg3").update(self) -- round 15: BG3 scroll steps
  if require("src.zelda.tmc.R27A").frame(self, input) then return end -- round 27A: side-system screens (R27A.lua)
  if require("src.zelda.tmc.R27B").frame(self, input) then return end -- round 27b: the ending / credits screens (R27B.lua)
  if self.enemyHold then self.enemyHold = self.enemyHold - 1; if self.enemyHold <= 0 then self.enemyHold = nil end end

  local tr = self.transition
  local Seam = require("src.zelda.tmc.Seamless")
  if tr and tr.kind == "scroll" then
    -- round 14: the room changes under Link's feet; the camera eases over
    local old = { room = self.room, camX = self.camX, camY = self.camY }
    self:transitionSwitch(tr)
    self.transition = nil
    Seam.afterScroll(self, old, tr)
    tr = nil
  elseif tr and tr.kind == "xfade" then
    -- round 14: the old picture (captured by Field:draw) fades out over
    -- the new room
    if tr.phase == "out" then
      tr.wait = (tr.wait or 0) + 1
      if tr.captured or tr.wait > 2 then
        self:transitionSwitch(tr)
        tr.phase, tr.t = "xfade", 0
      end
    else
      tr.t = tr.t + 1
      self:snapCamera()
      if tr.t >= Seam.XFADE then
        self.transition = nil
        require("src.zelda.tmc.DoorWalk").arrive(self)
      end
    end
    return
  end
  if tr then
    if tr.phase == "out" and self.fadeLevel >= 1 then
      self:transitionSwitch(tr)
      tr.phase = "in"
      self.fadeTarget = 0
    elseif tr.phase == "in" and self.fadeLevel <= 0 then
      self.transition = nil
      require("src.zelda.tmc.DoorWalk").arrive(self) -- round 14: out of a doorway
    end
    return
  end

  if self.textbox then
    local ti = padInput
    self.textbox:update({
      a = ti.pressed("a"), b = ti.pressed("b") or ti.pressed("r"),
      left = ti.pressed("left"), right = ti.pressed("right"),
      up = ti.pressed("up"), down = ti.pressed("down"),
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
    if e.fusing then require("src.zelda.tmc.Fusers").update(self, e) -- round 6: the NPC's fuse action
    elseif e.follower then require("src.zelda.tmc.ZeldaFollower").update(self, e) -- round 6
    elseif e.script and not e.script.stopped then
      local ok, err = pcall(e.script.run, e.script, e, self)
      if not ok then e.script.stopped = true; self.game:log("script: " .. tostring(err)) end
      e.script:postActions(e)
    end
    if e.kind == 6 and e.id == 0x6A then require("src.zelda.tmc.CutsceneObj").update(self, e) end -- round 10
    if e.enemy or e.projectile then
      -- round 15: after a seamless room change the new room's enemies wait
      -- until the cartridge's scroll would have ended (Seamless.hold)
      if not e.deleted and not (self.enemyHold and self.enemyHold > 0) then self._enemies:update(e) end
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
      -- round 10: a scripted object's type action calls GetNextFrame
      -- (cutsceneMiscObject.c and most scripted objects)
      if e.script and e.kind == 6 and not e.enemy and not e.projectile then e.anim:update(1) end
    elseif e.sprite then
      local spr = self.assets:sprite(e.sprite)
      if e.forceAnim then e.lookFrame = nil end -- round 11: a script animation ends a look frame
      local idx = e.forceAnim or Script.npcAnimIndex(e)
      e.forceAnim = nil
      if e.lookFrame then
        -- round 11: forestMinish.c sub_08060158 set the frame bytes itself
        -- (frameDuration $F0: the animation does not step)
        e.anim.frame, e.anim.flags, e.anim.flip = e.lookFrame.frameIndex, e.lookFrame.frame, 1
      else
        if idx ~= e.animIndex then e.animIndex = idx; e.anim:set(spr, idx, true) end
        e.anim:update(band(e.field82 or 0, 4) ~= 0 and 2 or 1)
      end
    end
    if e.parts then require("src.zelda.tmc.NpcParts").update(self, e) end -- round 7: the NPC's _Head
  end

  require("src.zelda.tmc.Hitboxes").update(self) -- round 11: solid NPCs push Link out
  require("src.zelda.tmc.PushAnim").tick(self) -- round 12: pushed pots sliding
  require("src.zelda.tmc.GustJar").tick(self) -- round 13: the Gust Jar's shots
  require("src.zelda.tmc.FuseBubble").update(self) -- round 7: CAMERA_TARGET
  self:snapCamera()
  require("src.zelda.tmc.Seamless").preload(self) -- round 14: the rooms ahead
  self:updateTileSwap()
  self.room:updateAnims()
  self:updateHudUi()
  for _, g in pairs(self.ghosts) do if g.update then g:update() end end
end

-- y-sorted sprites between the two BG layers
function Field:drawEntities(top)
  local list = {}
  for _, e in ipairs(self.entities) do
    if e.sprite and not e.hidden and not e.unplaced and not e.dying then list[#list + 1] = e end
  end
  if not self.intro then list[#list + 1] = self.player end
  for _, g in pairs(self.ghosts) do
    if g.area == self.room.area and g.room == self.room.room then list[#list + 1] = g end
  end
  -- archways sit on the top layer (collision layer 2): over Link
  -- round 9: ResolveOamDrawPriority (asm/src/intr.s): each sprite's key is
  -- (~spritePriority.b0 & 7) << 29 | (y + $80000000) >> 3, i.e. the lower
  -- b0 (4 by default, AppendEntityToList) wins, then the larger y (with its
  -- sub-pixel part); the first OAM entry draws on top.  We paint in reverse
  -- (last on top).  Equal keys keep a fixed order (list order, Link over a
  -- sprite on the very same y) so two sprites on one line never flicker.
  local player = self.player
  local function key(e)
    local k = (7 - (e.spritePriority or 4)) * 0x100000 + (e.y or 0)
    if e.overLink then k = k + 0x800000 end
    return k
  end
  for i, e in ipairs(list) do e._drawSeq = (e == player) and 1e9 or i end
  table.sort(list, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then return ka < kb end
    return a._drawSeq < b._drawSeq
  end)
  self.drawList = list
  -- round 14: the OBJ priority passes are in Field:draw (Priority.lua);
  -- drawEntities(nil) still draws the whole sorted list for old callers
  if top == "sort" then return list end
  self:drawSpriteList(list)
end

-- round 14: draw one already sorted list of sprites (last on top)
function Field:drawSpriteList(list)
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
      (e.impl or self._enemies.boss):draw(e, camX, camY)
    else
      local frame = e.staticFrame or e.anim.frame
      if frame == 0xFF and e.zeroFrame then frame = 0 end -- round 15
      if e.parts then -- round 7: multi-part NPCs draw their parts instead
        require("src.zelda.tmc.NpcParts").draw(self, e, math.floor(e.x - camX), math.floor(e.y - camY - (e.z or 0)), e.anim:hflip() ~= (e.flipX or false))
      elseif frame ~= 0xFF then
        local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette,
          "e" .. tostring(e.def and e.def.palette) .. ":" .. tostring(e.kind), e.gfx)
        if img and e.enemy and e.iframes > 0 and e.iframes % 4 < 2 then img = nil end
        if img then
          local x = math.floor(e.x - camX + (e.spriteOX or 0))
          local y = math.floor(e.y - camY - (e.z or 0) + (e.spriteOY or 0))
          -- round 15: a huge decoration's parallax (macroDecorations.c
          -- sub_08097F34 / F10: y + (y >> k) - (scroll >> k), room-relative)
          if e.macroShift then y = y + math.floor(e.y / 2 ^ e.macroShift) - math.floor(camY / 2 ^ e.macroShift) end
          if e.affine then -- round 6: an affine OBJ (scale, angle $10000 = a turn)
            love.graphics.draw(img, x, y, -e.affine.r / 0x10000 * 2 * math.pi, e.affine.s, e.affine.s, -ox, -oy)
          elseif e.flipY then love.graphics.draw(img, x + ox, y - oy, 0, 1, -1) -- round 10: a pot flipped by the Cane
          elseif e.anim:hflip() ~= (e.flipX or false) then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
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

-- the keyframe shown `age` frames into an animation ({frame, duration}
-- keys; a duration of 255 holds, frame $FF is blank); nil when blank
function Field.bubbleFrame(keys, age)
  if not keys or #keys == 0 then return nil end
  local t = age
  for i, k in ipairs(keys) do
    local dur = k[2] or 1
    if dur == 0xFF or i == #keys or t < dur then
      if k[1] == 0xFF then return nil end
      return k[1]
    end
    t = t - dur
  end
end

-- THOUGHT_BUBBLE ($56) over who has one; its animation index is the kind
function Field:drawBubbles(list)
  local d = self._objects:def(0x56, 0)
  if not d then return end
  for _, e in ipairs(list) do
    -- the bubble's timer and animation run on game frames (ThoughtBubble_
    -- Update), however often the picture is drawn
    if e.bubbleT and e.bubbleT > 0 and e.bubbleStart then
      local age = (self.frame or 0) - e.bubbleStart
      if e.bubbleKind ~= 2 then e.bubbleT = 45 - age end
    end
    if e.bubbleT and e.bubbleT > 0 then
      local s = self.assets:sprite(d.sprite)
      local keys = s and s.anims and s.anims[e.bubbleKind or 0]
      -- InitializeAnimation(type2) then GetNextFrame each frame (Anim.lua:
      -- durations, the end flag and its loop-back; frame $FF draws nothing)
      if not e.bubbleAnim then
        e.bubbleAnim = require("src.zelda.tmc.Anim").new()
        e.bubbleAnim:set(s, e.bubbleKind or 0, true)
        e.bubbleAge = 0
      end
      local age = e.bubbleStart and ((self.frame or 0) - e.bubbleStart) or ((e.bubbleAge or 0) + 1)
      if age > (e.bubbleAge or 0) then e.bubbleAnim:update(age - (e.bubbleAge or 0)); e.bubbleAge = age end
      local frame = keys and e.bubbleAnim.frame
      if frame == 0xFF then frame = nil end
      if frame then
        local img, ox, oy = self.assets:spriteFrame(d.sprite, frame, self.assets:objPalette(d.palette), "bubble",
          require("src.zelda.tmc.Assets").gfxSource(d.gfxType, d.gfx))
        if img then
          local bx, by = math.floor(e.x + e.bubbleOX - self.camX + ox), math.floor(e.y + e.bubbleOY - self.camY + oy)
          -- the mark ("!" / "?" / sleep) is the frame's first OAM piece,
          -- tiles 5-7 of the fixed block, drawn over the bubble
          love.graphics.draw(img, bx, by)
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

-- mode nil: everything into the 240x160 canvas; "world": the zoomed world
-- only (the runtime's zoom canvas, one game pixel a pixel); "overlay": the
-- HUD, text and fades only, over a transparent canvas (View.lua)
function Field:draw(font, mode)
  local g = love.graphics
  if mode == "overlay" then g.clear(0, 0, 0, 0) return self:drawOverlay(font) end
  local r = self.room
  local sx, sy = 0, 0
  if self.shakeT and self.shakeT > 0 then
    self.shakeT = self.shakeT - 1
    sx, sy = math.random(-self.shakeMag, self.shakeMag), math.random(-self.shakeMag, self.shakeMag)
  end
  local camX0, camY0 = self.camX, self.camY
  self.camX, self.camY = camX0 + sx, camY0 + sy
  self._shake = { sx, sy }
  -- round 14 (View.lua): zoomed, or the seamless camera past the room's
  -- edge: the rooms around are drawn too; a zoomed world goes to the
  -- runtime's zoom canvas ("world", Game:viewSize) and the HUD to the
  -- normal canvas at the normal scale (Game:drawOverlay)
  local V = require("src.zelda.tmc.View")
  local z = V.factor(self.game)
  local function picture()
    if mode == "world" then
      V.draw(self, z, 0, 0, 1 / z, function() self:drawWorld() end)
    elseif V.active(self) then
      V.draw(self, z, 0, 0, 1, function() self:drawWorld() end)
    else
      local bd = r:backdrop()
      g.clear(bd[1], bd[2], bd[3], 1)
      g.setColor(1, 1, 1, 1)
      self:drawWorld()
    end
  end
  picture()
  local Seam = require("src.zelda.tmc.Seamless")
  Seam.capture(self, picture) -- round 14: the crossfade's old picture
  Seam.drawFade(self)
  if mode == "world" then
    self.camX, self.camY = camX0, camY0
    return
  end
  if self.game._zoomed and V.factor(self.game) ~= 1 then
    -- (the runtime calls drawOverlay for the HUD)
    self.camX, self.camY = camX0, camY0
    return
  end
  self.camX, self.camY = camX0, camY0
  self:drawOverlay(font)
end

-- the HUD, menus, text, toasts, game over, iris and fades
function Field:drawOverlay(font)
  local g = love.graphics
  self:drawHud(font)
  if self.kinstone.active then self.kinstone:draw(font) end
  if self.menu.open then self.menu:draw(font) end
  require("src.zelda.tmc.R27A").draw(self, font) -- round 27A (R27A.lua)
  require("src.zelda.tmc.R27B").draw(self, font) -- round 27b (R27B.lua)
  if self.textbox then self.textbox:draw(font, W, H) end
  if self.toast then
    g.setColor(0, 0, 0, 0.6)
    g.rectangle("fill", 0, 20, W, 14)
    g.setColor(1, 1, 1, 1)
    g.printf(self.toast.text, 0, 21, W, "center")
    self.toast.t = self.toast.t - 1
    if self.toast.t <= 0 then self.toast = nil end
  end
  if self.gameOver then self:drawGameOver(font) end
  self:drawIris()
  if self.fadeLevel > 0 then
    local c = self.fadeWhite and 1 or 0
    g.setColor(c, c, c, self.fadeLevel)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

-- round 14: the room picture at the current camera: the GBA's priority
-- passes (Priority.lua: BGs and OBJs from priority 3 to 0, OBJs over BGs
-- of the same priority, BG1 over BG2), the bubbles, the fusion bubble
function Field:drawWorld()
  local r = self.room
  love.graphics.setColor(1, 1, 1, 1)
  require("src.zelda.tmc.Priority").compose(self, r)
  if self.drawList then
    local l = self.drawList
    if self.intro then l = { self.player } end
    self:drawBubbles(l)
  end
  require("src.zelda.tmc.FuseBubble").draw(self) -- round 7: the fusion bubble
  -- asleep in bed: the cartridge's BED_COVER object draws the blanket
  -- around him; here Link is drawn over the top layer instead
  if self.intro then self.player:draw(self.camX, self.camY, self.assets:objPalette(0x16)) end
end

function Field:showToast(text, frames)
  self.toast = { text = text, t = frames or 120 }
end

return Field
