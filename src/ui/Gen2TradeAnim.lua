-- Gold / Silver / Crystal's own trade cinematic
-- (engine/movie/trade_animation.asm), for in-game NPC trades and link
-- trades:
--
--   TradeAnimation         the player's mon leaves first -- NPC trades and
--                          the internally clocked side of a link
--   TradeAnimationPlayer2  the partner's mon arrives first -- the externally
--                          clocked side (opts.externalClock)
--
-- Gen 2 kept nothing of Red's movie but the idea.  The givemon slides in
-- under its stats window, poofs into a ball that rocks and hops into the
-- open end of a link TUBE, a bulge runs along it, the scene cuts to the two
-- Game Boys with both trainers' names under the tube and the mon's menu
-- icon riding through it in a bubble, and the same in reverse for the getmon,
-- which pops out of a ball dropping from the tube.
--
-- The asm is a jumptable script (TradeAnim_* commands) run once per frame by
-- DoTradeAnimation, with PlaySpriteAnimations after every command.  This
-- runs the same script with the same per-frame steps in a coroutine (see
-- TradeAnimKit): `self:frame()` is one trip round DoTradeAnimation's loop
-- (sprite anims step, wFrameCounter2 ticks), `self:block(n)` is a DelayFrames
-- inside a command, during which nothing else moves -- exactly the
-- difference that makes the ball keep rocking through EnterLinkTube's scroll
-- but freeze through its 80-frame pause.
--
-- The hardware it drives is modelled rather than imitated: two 32x32 BG
-- maps (vBGMap0 is the BG, vBGMap1 the window), wTilemap with WaitBGMap's
-- transfer to whichever hBGMapAddress names (and WaitTop turning it off
-- again), SCX on its 256-pixel ring, WX/WY, the five sprite-anim objects
-- (TRADE_POKE_BALL, TRADE_POOF, TRADE_TUBE_BULGE, TRADEMON_ICON,
-- TRADEMON_BUBBLE) with their framesets and OAM sets from the ROM and their
-- SpriteAnimFunc_* ported below, OBJ priority (the ball sinks BEHIND the
-- tube), and the CGB palettes through DmgToCgbBGPals / DmgToCgbObjPal0's
-- shade permutations -- so the tube flashing is rBGP xor %00111100 over the
-- tube palette, as on the cartridge.
--
-- Art and tables: field.gen2TradeAnim (src/import/Gen2TradeArt.lua).
-- Without them (an older cache, Prism / Polished Crystal) this hands over to
-- the Gen 1 movie, which is what Gen 2 played before.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")
local Kit = require("src.ui.TradeAnimKit")
local bit = require("bit")

local Gen2TradeAnim = {}
Gen2TradeAnim.__index = Gen2TradeAnim
Gen2TradeAnim.isOpaque = true

local RIGHT_ARROW, LEFT_ARROW = 0xED, 0xEE
local NEUTRAL = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                  { 0, 0, 0 } }

-- the few places the two releases' scripts and objects differ
local VARIANTS = {
  gold = {
    rockingBallWait = 64, bulgeWait = 128, bulgeStep = 1, scrollOut2 = 2,
    getmonCry = true, animateFrontpic = false, otGender = false,
    numberSpace = false,
  },
  crystal = {
    rockingBallWait = 32, bulgeWait = 64, bulgeStep = 2, scrollOut2 = 4,
    getmonCry = false, animateFrontpic = true, otGender = true,
    numberSpace = true,
  },
}

local SCRIPTS = {
  gold = {
    give = {
      "setupGivemonScroll", "showGivemonData", "doGivemonScroll", "wait80",
      "poof", "rockingBall", "enterLinkTube", "waitAnim", "bulgeThroughTube",
      "waitAnim", "textboxScrollStart", "giveTrademonSFX", "tubeToOT",
      "sentToOTText", "scrollOutRight",
    },
    get = {
      "otSendsText1", "otBidsFarewell", "scrollOutRight", "getTrademonSFX",
      "tubeToPlayer", "enterLinkTube", "dropBall", "exitLinkTube",
      "waitAnim", "showGetmonData", "poof", "waitAnim",
      "frontpicScrollStart", "wait80", "textboxScrollStart",
      "takeCareOfText", "scrollOutRight",
    },
    player2 = {
      "otSendsText2", "otBidsFarewell", "scrollOutRight", "getTrademonSFX",
      "tubeToOT", "enterLinkTube", "dropBall", "exitLinkTube", "waitAnim",
      "showGetmonData", "poof", "waitAnim", "frontpicScrollStart", "wait80",
      "textboxScrollStart", "takeCareOfText", "scrollOutRight",
      "setupGivemonScroll", "showGivemonData", "doGivemonScroll", "wait80",
      "poof", "rockingBall", "enterLinkTube", "waitAnim", "bulgeThroughTube",
      "waitAnim", "textboxScrollStart", "giveTrademonSFX", "tubeToPlayer",
      "sentToOTText", "scrollOutRight", "finish",
    },
  },
  crystal = {
    give = {
      "setupGivemonScroll", "showGivemonData", "doGivemonScroll", "wait80",
      "wait96", "poof", "rockingBall", "enterLinkTube", "waitAnim",
      "bulgeThroughTube", "waitAnim", "textboxScrollStart",
      "giveTrademonSFX", "tubeToOT", "sentToOTText", "scrollOutRight",
    },
    get = {
      "otSendsText1", "otBidsFarewell", "wait40", "scrollOutRight",
      "getTrademonSFX", "tubeToPlayer", "enterLinkTube", "dropBall",
      "exitLinkTube", "waitAnim", "showGetmonData", "poof", "waitAnim",
      "frontpicScrollStart", "animateFrontpic", "wait80IfOTEgg",
      "textboxScrollStart", "takeCareOfText", "scrollOutRight",
    },
    player2 = {
      "otSendsText2", "otBidsFarewell", "wait40", "scrollOutRight",
      "getTrademonSFX", "tubeToOT", "enterLinkTube", "dropBall",
      "exitLinkTube", "waitAnim", "showGetmonData", "poof", "waitAnim",
      "frontpicScrollStart", "animateFrontpic", "wait180IfOTEgg",
      "textboxScrollStart", "takeCareOfText", "scrollOutRight",
      "setupGivemonScroll", "showGivemonData", "doGivemonScroll", "wait40",
      "poof", "rockingBall", "enterLinkTube", "waitAnim", "bulgeThroughTube",
      "waitAnim", "textboxScrollStart", "giveTrademonSFX", "tubeToPlayer",
      "sentToOTText", "scrollOutRight", "finish",
    },
  },
}

-- ------------------------------------------------------------------ helpers

local function speciesName(game, mon)
  local def = game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

local function dexOf(game, mon)
  local def = game.data.pokemon[mon.species]
  return def and def.dex or 0
end

local function isEgg(mon)
  local ok, Party = pcall(require, "src.pokemon.Party")
  return ok and Party.isEgg and Party.isEgg(mon) or false
end

local function frontPic(game, mon)
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, mon.species, "front", { mon = mon, kind = "trade" })
  if not path then return nil, false end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok then return nil, false end
  return img, trueColor or false
end

local function newMap() return { cells = {}, items = {} } end

local function copyScreen(dst, src)
  for row = 0, 17 do
    for col = 0, 19 do dst.cells[row * 32 + col] = src.cells[row * 32 + col] end
  end
  dst.items = {}
  for i, item in ipairs(src.items) do dst.items[i] = item end
end

-- Sprites_Sine: a = d * sin(a * pi/32) from the cartridge's quarter-wave
-- table, with its 8-bit multiply and two's-complement negation
local function sine(table_, a, d)
  a = a % 64
  local negative = a >= 32
  local entry = table_[(a % 32)] or 0
  local h = math.floor(((d * entry) % 0x10000) / 256)
  if negative then h = (256 - h) % 256 end
  if h >= 128 then h = h - 256 end
  return h
end

-- ------------------------------------------------------------------ new

function Gen2TradeAnim.new(game, opts)
  opts = opts or {}
  local art = game.data.field and game.data.field.gen2TradeAnim
  if type(art) ~= "table" or art.format ~= 1 then
    return require("src.ui.TradeAnim").new(game, opts)
  end
  local self = setmetatable({}, Gen2TradeAnim)
  self.game = game
  self.art = art
  self.variant = VARIANTS[art.variant] or VARIANTS.crystal
  self.script = (SCRIPTS[art.variant] or SCRIPTS.crystal)
  self.player2 = opts.externalClock and true or false
  self.sent, self.received = opts.sent, opts.received
  self.onDone = opts.onDone
  local player = game.save.player or {}
  -- wPlayerTrademonSenderName / wOTTrademonSenderName
  self.playerName = opts.playerOt or player.name or "GOLD"
  self.otName = opts.enemyName or (self.received and self.received.ot)
    or "TRAINER"
  self.playerOtId = opts.playerOtId or (self.sent and self.sent.otId)
    or player.id or 0
  self.otOtId = opts.enemyOtId or (self.received and self.received.otId) or 0
  -- the first mon in the movie's own order is the one LinkTradeAnim_Load*
  -- calls "Player1"; TradeAnimationPlayer2 swaps them
  if self.player2 then
    self.link1, self.link2 = self.otName, self.playerName
  else
    self.link1, self.link2 = self.playerName, self.otName
  end
  self.otGender = opts.otGender      -- "male" / "female" (NPC: by dialog set)

  self.img = {
    tiles = Kit.image(art.tiles),
    arrows = Kit.image(art.arrows),
    obj = Kit.image(art.obj),
    bubble = Kit.image(art.bubble),
  }
  local iconPath = function(mon)
    return mon and art.icons and art.icons[mon.species]
  end
  self.icon = {
    sent = Kit.image(iconPath(self.sent)),
    received = Kit.image(iconPath(self.received)),
  }
  self.pic = {}
  self.pic.sent, self.pic.sentTrue = frontPic(game, self.sent)
  self.pic.received, self.pic.receivedTrue = frontPic(game, self.received)

  -- hardware
  self.tm = newMap()
  self.v98, self.v9C = newMap(), newMap()
  self.mapAddr = "98"            -- hBGMapAddress
  self.mapMode = false           -- hBGMapMode (WaitBGMap on, WaitTop off)
  self.scx, self.wx, self.wy = 0, 7, 0x90
  self.bgp, self.obp0 = 0xE4, 0xE4
  self.bgPal = nil               -- wBGPals pal 0 (WipeAttrmap: all of BG)
  self.obPal0 = self:mapObjectPal0()
  self.obPal7 = art.palettes.tube
  self.cleared = true            -- ClearBGPalettes: everything white
  self.objLayout = "ball"        -- which loader last filled vTiles0 $62+
  self.sprites = {}              -- wSpriteAnimationStructs, slot order
  self.oam = {}                  -- what PlaySpriteAnimations wrote
  self.frameCounter = 0          -- wFrameCounter
  self.frameCounter2 = 0         -- wFrameCounter2
  self.phase = "start"
  self.co = coroutine.create(function() self:run() end)
  return self
end

function Gen2TradeAnim:enter() end

-- OB pal 0 on the frontpic screens is still the field's: the player's own
-- PAL_OW_RED out of MapObjectPals, for the time of day it is
function Gen2TradeAnim:mapObjectPal0()
  local pals = self.art.palettes.mapOb0 or {}
  local tod = "DAY"
  local ok, P = pcall(require, "src.render.PaletteFX")
  if ok and P.gen2Tod then
    local t = tostring(P.gen2Tod() or ""):upper()
    if t:find("MORN") then tod = "MORN"
    elseif t:find("NIT") or t:find("NIGHT") then tod = "NITE" end
  end
  return pals[tod] or pals.DAY or self.art.palettes.partyOb0
end

-- ------------------------------------------------------------------ frames

function Gen2TradeAnim:transfer()
  if self.mapMode then
    copyScreen(self.mapAddr == "9C" and self.v9C or self.v98, self.tm)
  end
end

-- one DelayFrame with nothing but the BG transfer running
function Gen2TradeAnim:block(n)
  for _ = 1, n or 1 do
    self:transfer()
    Kit.stepText(self.text)
    if self.picAnim then self.picAnim:update(1 / 60) end
    coroutine.yield()
  end
end

-- the rest of one DoTradeAnimation pass: PlaySpriteAnimations,
-- wFrameCounter2++, DelayFrame
function Gen2TradeAnim:frame()
  self:playSpriteAnimations()
  self.frameCounter2 = (self.frameCounter2 + 1) % 256
  self:block(1)
end

function Gen2TradeAnim:update()
  if self.finished then return end
  local ok, err = coroutine.resume(self.co)
  if not ok then
    Logger.warn("gen2 trade animation stopped: %s", tostring(err))
    self:finish()
    return
  end
  if coroutine.status(self.co) == "dead" then self:finish() end
end

function Gen2TradeAnim:run()
  self:layout()
  local list
  if self.player2 then
    list = self.script.player2
  else
    list = {}
    for _, c in ipairs(self.script.give) do list[#list + 1] = c end
    for _, c in ipairs(self.script.get) do list[#list + 1] = c end
    list[#list + 1] = "finish"
  end
  for _, name in ipairs(list) do
    self.phase = name
    self[name](self)
  end
end

-- the tilemap helpers the commands share
function Gen2TradeAnim:waitBGMap()
  self.mapMode = true
  self:block(4)
end

function Gen2TradeAnim:waitTop()
  if self.mapMode then
    self:block(1)
    self.mapMode = false
  end
end

function Gen2TradeAnim:clearTilemap()
  self.tm = newMap()
  self:waitBGMap()
end

function Gen2TradeAnim:blankTilemap()
  self.tm = newMap()
end

function Gen2TradeAnim:place(list, w, tx, ty)
  for i, id in ipairs(list) do
    local col = tx + (i - 1) % w
    local row = ty + math.floor((i - 1) / w)
    self.tm.cells[row * 32 + col] = id
  end
end

-- ------------------------------------------------------------------ text

function Gen2TradeAnim:subs()
  local game = self.game
  local giveName = speciesName(game, self.sent)
  local getName = speciesName(game, self.received)
  -- the wPlayerTrademon* / wOTTrademon* buffers the lines read are never
  -- swapped; TradeAnimationPlayer2 only swaps the wLinkPlayer names and the
  -- send / get species the tube scenes use
  local p1Species, p2Species = giveName, getName
  local p1Sender, p2Sender = self.playerName, self.otName
  local out = {
    ["RAM:wPlayerTrademonSpeciesName"] = p1Species,
    ["RAM:wOTTrademonSpeciesName"] = p2Species,
    ["RAM:wPlayerTrademonSenderName"] = p1Sender,
    ["RAM:wOTTrademonSenderName"] = p2Sender,
  }
  local t = self.art.tokens or {}
  if t.playerSpeciesName then out[t.playerSpeciesName] = p1Species end
  if t.otSpeciesName then out[t.otSpeciesName] = p2Species end
  if t.playerSenderName then out[t.playerSenderName] = p1Sender end
  if t.otSenderName then out[t.otSenderName] = p2Sender end
  return out
end

-- PrintText into the bottom of wTilemap; it types at the text speed while
-- the movie waits
function Gen2TradeAnim:printText(key)
  local text = Kit.expand(self.game, key, self:subs())
  -- _MonNameSentToText is `text_start / done`: an empty box.  The importer
  -- writes a placeholder for a text with no characters; it prints nothing
  if not text or text:match("^Monnamesenttotext") then text = "" end
  self.text = Kit.textBox(self.game, text, false)
  local items = {}
  for _, item in ipairs(self.tm.items) do
    if item.kind ~= "textbox" then items[#items + 1] = item end
  end
  items[#items + 1] = { kind = "textbox", box = self.text }
  self.tm.items = items
  self.mapMode = true
  -- PrintText returns when the last letter is down
  for _ = 1, 600 do
    if self.text.done then break end
    self:block(1)
  end
end

function Gen2TradeAnim:wait80Frames() self:block(80) end

-- ------------------------------------------------------------------ objects

local OBJ_FRAMESET = {
  ball = "TradePokeBall", poof = "TradePoof", bulge = "TradeTubeBulge",
  icon = "TrademonIcon", bubble = "TrademonBubble",
}

-- InitSpriteAnimStruct at OAM pixel (x, y).  `depixel a, b, c, d` loads
-- d = a*8+c and e = b*8+d, and the struct takes YCOORD from d and XCOORD
-- from e -- so `depixel 10, 11, 4, 0` is x 88, y 84.
function Gen2TradeAnim:initSprite(kind, x, y)
  local s = {
    kind = kind, frameset = OBJ_FRAMESET[kind], x = x % 256, y = y % 256,
    xoff = 0, yoff = 0, dur = 0, durOff = 0, frame = -1, jt = 0,
    var1 = 0, var2 = 0, alive = true,
  }
  self.sprites[#self.sprites + 1] = s
  return s
end

function Gen2TradeAnim:clearSpriteAnims()
  self.sprites = {}
  self.oam = {}
end

-- GetSpriteAnimFrame: the oamset (or command) for this frame, and the
-- frame's flip flags
local function nextFrame(art, s)
  local fs = art.framesets[s.frameset]
  if not fs then return "delete" end
  for _ = 1, 8 do
    if s.dur > 0 then
      s.dur = s.dur - 1
      local f = fs.frames[s.frame + 1]
      return f.oam, f
    end
    s.frame = s.frame + 1
    local f = fs.frames[s.frame + 1]
    if not f then
      local tail = fs.tail
      if tail == "restart" then
        s.dur, s.frame = 0, -1
      elseif tail == "end" then
        s.dur, s.frame = 0, s.frame - 2
      else
        return tail
      end
    else
      s.dur = f.dur + s.durOff
      return f.oam, f
    end
  end
  return "wait"
end

-- the SpriteAnimFunc_* each object runs before its frame is drawn
function Gen2TradeAnim:spriteFunc(s)
  local game = self.game
  if s.kind == "ball" then
    -- SpriteAnimFunc_TradePokeBall
    local jt = s.jt
    if jt == 0 then
      s.frameset, s.dur, s.frame = "TradePokeBallWobble", 0, -1
      s.jt, s.var1 = 2, 0x20
      return
    elseif jt == 1 then
      s.jt, s.var1, s.var2 = 4, 0x30, 0x24
      return
    elseif jt == 2 then
      if s.var1 ~= 0 then s.var1 = s.var1 - 1 return end
      s.jt, s.var1 = 3, 0x40
      jt = 3
    end
    if jt == 3 then
      local a = s.var1
      if a < 48 then
        Sound.play(game.data, "Sfx_GotSafariBalls")
        s.alive = false
        return
      end
      s.var1 = a - 1
      s.yoff = sine(self.art.sine, a, 40)
    elseif jt == 4 then
      if s.var2 == 0 then
        s.yoff, s.jt = 0, 5
        return
      end
      s.yoff = sine(self.art.sine, s.var1, s.var2)
      s.var1 = (s.var1 + 1) % 256
      if s.var1 % 0x40 ~= 0 then return end
      s.var1 = 0x20
      s.var2 = (s.var2 - 0x0C) % 256
      Sound.play(game.data, "Sfx_SwitchPokemon")
    elseif jt == 5 then
      s.alive = false
    end
  elseif s.kind == "bulge" then
    -- SpriteAnimFunc_TradeTubeBulge
    local a = s.x
    s.x = (s.x + self.variant.bulgeStep) % 256
    if a >= 0xB0 then
      s.alive = false
    elseif a % 4 == 0 then
      Sound.play(game.data, "Sfx_PokeballsPlacedOnTable")
    end
  elseif s.kind == "icon" or s.kind == "bubble" then
    self:animateTrademonInTube(s)
  end
end

-- TradeAnim_AnimateTrademonInTube
function Gen2TradeAnim:animateTrademonInTube(s)
  local jt = s.jt
  if jt == 0 then                                   -- .InitTimer
    s.jt, s.var1 = 1, 0x80
    return
  end
  if jt == 1 then                                   -- .WaitTimer1
    local a = s.var1
    s.var1 = (s.var1 - 1) % 256
    if a ~= 0 then return end
    s.jt, jt = 2, 2
  end
  if jt == 2 then                                   -- .MoveRight
    if s.x < 0x94 then s.x = s.x + 1 return end
    s.jt, jt = 3, 3
  end
  if jt == 3 then                                   -- .MoveDown
    if s.y < 0x4C then s.y = s.y + 1 return end
    s.alive = false
    return
  end
  if jt == 4 then                                   -- .MoveUp
    if s.y ~= 0x2C then s.y = s.y - 1 return end
    s.jt, jt = 5, 5
  end
  if jt == 5 then                                   -- .MoveLeft
    if s.x ~= 0x58 then s.x = s.x - 1 return end
    s.jt, s.var1 = 6, 0x80
    return
  end
  if jt == 6 then                                   -- .WaitTimer2
    local a = s.var1
    s.var1 = (s.var1 - 1) % 256
    if a == 0 then s.alive = false end
  end
end

-- PlaySpriteAnimations: each live struct runs its function, then its
-- frameset writes OAM
function Gen2TradeAnim:playSpriteAnimations()
  local art = self.art
  local oam = {}
  local kept = {}
  for _, s in ipairs(self.sprites) do
    if s.alive then
      self:spriteFunc(s)
      local id, f = nextFrame(art, s)
      if id == "delete" then
        s.alive = false
      elseif type(id) == "number" then
        local set = art.oam[id]
        if set then
          local xflip = f and f.xflip
          local yflip = f and f.yflip
          for _, o in ipairs(set.objs) do
            local dy, dx, tile, attr = o[1], o[2], o[3], o[4]
            if yflip then dy = -8 - dy end
            if xflip then dx = -8 - dx end
            local a = attr
            if xflip then a = bit.bxor(a, 0x20) end
            if yflip then a = bit.bxor(a, 0x40) end
            oam[#oam + 1] = {
              y = (s.y + s.yoff + dy) % 256,
              x = (s.x + s.xoff + dx) % 256,
              tile = (art.objBase + set.vtile + tile) % 256,
              attr = a,
            }
          end
        end
      end
      if s.alive then kept[#kept + 1] = s end
    end
  end
  self.sprites = kept
  self.oam = oam
end

-- ------------------------------------------------------------------ palettes

function Gen2TradeAnim:monPal(mon)
  local P = require("src.render.PaletteFX")
  local shiny = false
  pcall(function() shiny = require("src.pokemon.Pokemon").isShiny(mon) end)
  return P.monPal(self.game.data, mon.species, nil, shiny)
end

-- SCGB_PLAYER_OR_MON_FRONTPIC_PALS then DmgToCgbBGPals %11100100
function Gen2TradeAnim:frontpicPals(mon)
  self.bgPal = self:monPal(mon)
  self.bgp = 0xE4
  self.cleared = false
end

-- SCGB_TRADE_TUBE, DmgToCgbBGPals %11100100 and DmgToCgbObjPal0 `objReg`
function Gen2TradeAnim:tradeTubePals(objReg)
  self.bgPal = self.art.palettes.tube
  self.obPal0 = self.art.palettes.partyOb0
  self.obPal7 = self.art.palettes.tube
  self.bgp = 0xE4
  self.obp0 = objReg or 0xE4
  self.cleared = false
end

-- TradeAnim_NormalPals
function Gen2TradeAnim:normalPals()
  self.obp0 = 0xE4
  self.bgp = 0xE4
  self.cleared = false
end

-- ------------------------------------------------------------------ layout

-- RunTradeAnimScript's .TradeAnimLayout and the music
function Gen2TradeAnim:layout()
  self.cleared = true                     -- ClearBGPalettes
  self:waitBGMap()
  self:clearSpriteAnims()
  self:clearTilemap()
  self.scx, self.wx, self.wy = 0, 7, 0x90
  self:block(1)                           -- LoadTradeBallAndCableGFX
  self.objLayout = "ball"
  self:normalPals()
  self.bgPal = nil
  local Music = require("src.core.Music")
  pcall(function()
    Music.play(self.game.data, Music.special(self.game.data, "evolution"))
  end)
end

-- ------------------------------------------------------------------ commands

function Gen2TradeAnim:wait80() self:block(80) self:frame() end
function Gen2TradeAnim:wait40() self:block(40) self:frame() end
function Gen2TradeAnim:wait96() self:block(96) self:frame() end

function Gen2TradeAnim:otEgg()
  return isEgg(self.received)
end

-- TradeAnim_Wait80IfOTEgg / Wait180IfOTEgg: the script pointer moves on
-- either way, the wait only happens for an egg
function Gen2TradeAnim:wait80IfOTEgg()
  if self:otEgg() then self:block(80) end
  self:frame()
end
function Gen2TradeAnim:wait180IfOTEgg()
  if self:otEgg() then self:block(180) end
  self:frame()
end

function Gen2TradeAnim:waitAnim()
  while self.frameCounter ~= 0 do
    self.frameCounter = self.frameCounter - 1
    self:frame()
  end
  self:frame()
end

function Gen2TradeAnim:setupGivemonScroll()
  self.wx, self.scx, self.wy = 0x8F, 0x88, 0x50
  self:frame()
end

-- the givemon (or, for Player2, the partner's mon) and its stats
-- ShowPlayerTrademonStats / ShowOTTrademonStats: always the player's own
-- mon and the partner's, whichever script is running
function Gen2TradeAnim:giveMon() return self.sent end
function Gen2TradeAnim:getMon() return self.received end

function Gen2TradeAnim:showGivemonData()
  local mon = self:giveMon()
  self:trademonStats(mon, self.playerName, self.playerOtId,
    self:playerGenderMark(mon))
  self:frontpicPals(mon)
  self:showFrontpic(mon)
  Sound.playCry(self.game.data, mon.species)
  self:frame()
end

function Gen2TradeAnim:doGivemonScroll()
  while self.wx ~= 7 do
    self.wx = self.wx - 4
    self.scx = (self.scx - 4) % 256
    self:frame()
  end
  self.wx, self.scx = 7, 0
  self:frame()
end

function Gen2TradeAnim:frontpicScrollStart()
  self.wx, self.wy = 7, 0x50
  self:frame()
end

function Gen2TradeAnim:textboxScrollStart()
  self.wx, self.wy = 7, 0x90
  self:frame()
end

function Gen2TradeAnim:poof()
  self:initSprite("poof", 11 * 8, 10 * 8 + 4)        -- depixel 10, 11, 4, 0
  self.frameCounter = 16
  Sound.play(self.game.data, "Sfx_BallPoof")
  self:frame()
end

function Gen2TradeAnim:rockingBall()
  self:initSprite("ball", 11 * 8, 10 * 8 + 4)
  self.frameCounter = self.variant.rockingBallWait
  self:frame()
end

function Gen2TradeAnim:dropBall()
  local s = self:initSprite("ball", 11 * 8, 10 * 8 + 4)
  s.jt, s.yoff = 1, -36                                -- YOFFSET $dc
  self.frameCounter = 56
  self:frame()
end

function Gen2TradeAnim:bulgeThroughTube()
  self.obp0 = 0xE4
  self:initSprite("bulge", 11 * 8, 5 * 8)             -- depixel 5, 11
  self.frameCounter = self.variant.bulgeWait
  self:frame()
end

function Gen2TradeAnim:giveTrademonSFX()
  Sound.play(self.game.data, "Sfx_GiveTrademon")
  self:frame()
end

function Gen2TradeAnim:getTrademonSFX()
  Sound.play(self.game.data, "Sfx_GetTrademon")
  self:frame()
end

-- TradeAnim_EnterLinkTube1 / 2
function Gen2TradeAnim:enterLinkTube()
  self.phase = "enter_tube"
  self:clearTilemap()
  self:waitTop()
  self.scx = 0xA0
  self:block(1)
  self:place(self.art.linkTube.ids, 12, 8, 2)
  self:waitBGMap()
  self:tradeTubePals(0xE4)
  Sound.play(self.game.data, "Sfx_Potion")
  self:frame()
  while true do
    if self.scx == 0 then
      self:block(80)
      self:frame()
      return
    end
    self.scx = (self.scx + 4) % 256
    self:frame()
  end
end

function Gen2TradeAnim:exitLinkTube()
  while self.scx ~= 0xA0 do
    self.scx = (self.scx - 4) % 256
    self:frame()
  end
  self:clearTilemap()
  self.scx = 0
  self:frame()
end

-- ------------------------------------------------------------------ stats

-- TrademonStats_PrintOTName's gender mark: the caught-by data of the mon
-- the player hands over, and the trade's own for the NPC's
function Gen2TradeAnim:playerGenderMark(mon)
  if not self.variant.otGender then return nil end
  local caught=require('src.pokemon.Gen2CaughtData')
  if mon and (caught.hasFields(mon)or mon.caughtData~=nil)then
    local gender=caught.playerGender(mon)
    if not gender then return " " end
    return gender=='girl'and "♀"or "♂"
  end
  local player = self.game.save.player or {}
  return player.gender == "girl" and "♀" or "♂"
end

function Gen2TradeAnim:otGenderMark()
  if not self.variant.otGender then return nil end
  if self.otGender == "female" then return "♀" end
  if self.otGender == "male" then return "♂" end
  return "♂"
end

-- TrademonStats_MonTemplate + the Print* helpers, into the window map
function Gen2TradeAnim:trademonStats(mon, ot, otId, mark)
  self:waitTop()
  self:blankTilemap()
  self.mapAddr = "9C"
  local items = self.tm.items
  items[#items + 1] = { kind = "box", tx = 3, ty = 0, tw = 15, th = 8 }
  items[#items + 1] = { kind = "stats", mon = mon, ot = ot, otId = otId,
                        mark = mark, egg = isEgg(mon) }
  self:waitBGMap()
  self:waitTop()
  self.mapAddr = "98"
end

-- TradeAnim_ShowFrontpic: the pic at (7,2) on the BG
function Gen2TradeAnim:showFrontpic(mon)
  self:block(1)
  self:block(7)                                      -- Request2bpp, 49 tiles
  self:waitTop()
  self:blankTilemap()
  local img, trueColor
  if mon == self.sent then
    img, trueColor = self.pic.sent, self.pic.sentTrue
  else
    img, trueColor = self.pic.received, self.pic.receivedTrue
  end
  self.tm.items[#self.tm.items + 1] = { kind = "pic", img = img,
    trueColor = trueColor, mon = mon }
  self:waitBGMap()
end

function Gen2TradeAnim:showGetmonData()
  local mon = self:getMon()
  self:trademonStats(mon, self.otName, self.otOtId, self:otGenderMark())
  self:frontpicPals(mon)
  self:showFrontpic(mon)
  if self.variant.getmonCry then Sound.playCry(self.game.data, mon.species) end
  self:frame()
end

-- AnimateTrademonFrontpic -> AnimateFrontpic ANIM_MON_TRADE:
-- Idle Play2 Idle Play SetWait Wait Cry Setup Play
function Gen2TradeAnim:animateFrontpic()
  local mon = self:getMon()
  if self.variant.animateFrontpic then
    self:trademonStats(mon, self.otName, self.otOtId, self:otGenderMark())
    self:frontpicPals(mon)
    self:showFrontpic(mon)
    local pa = require("src.pokemon.PicAnim").forMon(self.game.data, mon)
    if pa and pa.restart then
      pa.paused = false
      self.picAnim = pa
      for _ = 1, 2 do
        pa:restart("idle")
        for _ = 1, 600 do
          if not pa.steps then break end
          self:block(1)
        end
      end
    end
    self:block(18)                                     -- SetWait / Wait
    local src = Sound.playCry(self.game.data, mon.species)
    for _ = 1, 150 do                                  -- _PlayMonCry waits
      if not (src and src.isPlaying and src:isPlaying()) then break end
      self:block(1)
    end
    if pa and pa.restart then
      pa:restart("play")
      for _ = 1, 600 do
        if not pa.steps or pa.which ~= "play" then break end
        self:block(1)
      end
      pa.steps = nil
      self.picAnim = nil
    end
  end
  self:frame()
end

-- ------------------------------------------------------------------ tube

-- TradeAnim_TubeAnimJumptable: the BG for each leg of the trip
function Gen2TradeAnim:tubeState(state)
  local CABLE, JOIN, PORT = 0x60, 0x5B, 0x5D
  local gb = self.art.gameBoy
  self:blankTilemap()
  local cells = self.tm.cells
  if state == 0 or state == 3 then
    cells[3 * 32 + 9] = JOIN
    for col = 10, 19 do cells[3 * 32 + col] = CABLE end
    self:place(gb.ids, gb.w, 3, 2)
  elseif state == 1 then
    for col = 0, 19 do cells[3 * 32 + col] = CABLE end
  else
    for col = 0, 16 do cells[3 * 32 + col] = CABLE end
    cells[3 * 32 + 17] = PORT
    for row = 4, 6 do cells[row * 32 + 17] = 0x61 end
    cells[7 * 32 + 17] = 0x5F
    cells[7 * 32 + 16] = JOIN
    self:place(gb.ids, gb.w, 10, 6)
  end
end

-- TradeAnim_PlaceTrademonStatsOnTubeAnim: the names under the tube, on
-- the window
function Gen2TradeAnim:placeTrademonStatsOnTubeAnim(arrow)
  self.cleared = true                                -- ClearBGPalettes
  self:waitBGMap()
  self:waitTop()
  self.mapAddr = "9C"
  self:clearTilemap()
  local items = self.tm.items
  items[#items + 1] = { kind = "rule", tx = 0, ty = 0, w = 20 }
  items[#items + 1] = { kind = "text", tx = 0, ty = 1, text = self.link1 }
  -- right-aligned so the name ends in column 19 of the row above row 4
  local len = #(Font.encode and Font.encode(self.link2) or self.link2)
  items[#items + 1] = { kind = "text", tx = 20 - len, ty = 3, text = self.link2 }
  items[#items + 1] = { kind = "arrows", tx = 7, ty = 2, w = 6, code = arrow }
  self:waitBGMap()
  self:waitTop()
  self.mapAddr = "98"
  self:clearTilemap()
end

-- TradeAnim_TubeToOT1 / TubeToPlayer1 (TradeAnim_InitTubeAnim)
function Gen2TradeAnim:initTubeAnim(arrow, species, state, x, y, jt)
  self:placeTrademonStatsOnTubeAnim(arrow)
  self:clearSpriteAnims()
  -- hlbgcoord 20, 3: the cable run already waiting off screen to the right
  for col = 20, 31 do self.v98.cells[3 * 32 + col] = 0x60 end
  self:tubeState(state)
  self.scx, self.wx, self.wy = 0, 7, 0x70
  self:block(1)                                      -- LoadTradeBubbleGFX
  self.objLayout = "tube"
  self.tubeIcon = species
  local icon = self:initSprite("icon", x, y)
  icon.jt = jt
  local bubble = self:initSprite("bubble", x, y)
  bubble.jt = jt
  self:waitBGMap()
  self:tradeTubePals(0xD0)                           -- OBP0 %11010000
  self.frameCounter = 92
  self:frame()
end

-- ToOT2..8 / ToPlayer2..8: the tube scroll, step by step
function Gen2TradeAnim:flashBGPals()
  if self.frameCounter2 % 8 == 0 then self.bgp = bit.bxor(self.bgp, 0x3C) end
end

function Gen2TradeAnim:tubeScroll(delta, stopAt, state)
  repeat
    self:flashBGPals()
    self.scx = (self.scx + delta) % 256
    local done = self.scx == stopAt
    if done and state then self:tubeState(state) end
    self:frame()
  until done
end

function Gen2TradeAnim:tubeWait()
  while true do
    self:flashBGPals()
    if self.frameCounter == 0 then self:frame() return end
    self.frameCounter = self.frameCounter - 1
    self:frame()
  end
end

function Gen2TradeAnim:tubeEnd()
  self.cleared = true                                -- ClearBGPalettes
  self:waitBGMap()
  self:clearTilemap()
  self:clearSpriteAnims()
  self.v98, self.v9C = newMap(), newMap()
  self.scx, self.wy = 0, 0x90
  self:block(1)
  self.objLayout = "ball"
  self:waitBGMap()
  self:normalPals()
  self.bgPal = self.art.palettes.tube
  self:frame()
end

function Gen2TradeAnim:tubeToOT()
  self.phase = "tube_to_ot"
  local mon = self.player2 and self.received or self.sent
  self:initTubeAnim(RIGHT_ARROW, mon, 0, 11 * 8, 5 * 8 + 4, 0)
  self:tubeScroll(2, 0x50, 1)                        -- TubeToOT2
  self:tubeScroll(2, 0xA0, 2)                        -- TubeToOT3
  self:tubeScroll(2, 0x00)                           -- TubeToOT4
  self:tubeWait()                                    -- TubeToOT5
  self.frameCounter = 128                            -- TubeToOT6
  self:frame()
  self:tubeWait()                                    -- TubeToOT7
  self:tubeEnd()                                     -- TubeToOT8
end

function Gen2TradeAnim:tubeToPlayer()
  self.phase = "tube_to_player"
  local mon = self.player2 and self.sent or self.received
  self:initTubeAnim(LEFT_ARROW, mon, 2, 18 * 8 + 4, 9 * 8 + 4, 4)
  self:tubeWait()                                    -- TubeToPlayer2
  self:tubeScroll(-2, 0xB0, 1)                       -- TubeToPlayer3
  self:tubeScroll(-2, 0x60, 0)                       -- TubeToPlayer4
  self:tubeScroll(-2, 0x00)                          -- TubeToPlayer5
  self.frameCounter = 128                            -- TubeToPlayer6
  self:frame()
  self:tubeWait()                                    -- TubeToPlayer7
  self:tubeEnd()                                     -- TubeToPlayer8
end

-- ------------------------------------------------------------------ text

function Gen2TradeAnim:sentToOTText()
  self.phase = "sent_to_ot"
  self:printText("_MonNameSentToText")
  self:block(189)
  self:printText("_MonWasSentToText")
  self:wait80Frames()
  self:block(128)
  self:frame()
end

function Gen2TradeAnim:otBidsFarewell()
  self.phase = "bids_farewell"
  self:printText("_BidsFarewellToMonText")
  self:wait80Frames()
  self:printText("_MonNameBidsFarewellText")
  self:wait80Frames()
  self:frame()
end

function Gen2TradeAnim:otSendsText1()
  self.phase = "ot_sends"
  self:printText("_ForYourMonSendsText")
  self:wait80Frames()
  self:printText("_OTSendsText")
  self:wait80Frames()
  self:block(14)
  self:frame()
end

function Gen2TradeAnim:otSendsText2()
  self.phase = "will_trade"
  self:printText("_WillTradeText")
  self:wait80Frames()
  self:printText("_ForYourMonWillTradeText")
  self:wait80Frames()
  self:block(14)
  self:frame()
end

function Gen2TradeAnim:takeCareOfText()
  self.phase = "take_care"
  self:waitTop()
  -- rows 10-17 blanked: the stats window's half of the screen, on the BG
  local kept = {}
  for _, item in ipairs(self.tm.items) do
    if item.kind == "pic" then kept[#kept + 1] = item end
  end
  self.tm.items = kept
  self:waitBGMap()
  self:printText("_TakeGoodCareOfMonText")
  self:wait80Frames()
  self:frame()
end

-- TradeAnim_ScrollOutRight / ScrollOutRight2: the screen is copied to the
-- window, the BG cleared under it, and the window slides off to the right
function Gen2TradeAnim:scrollOutRight()
  self:waitTop()
  self.mapAddr = "9C"
  self:waitBGMap()
  self.wx, self.wy = 7, 0
  self:block(1)
  self:waitTop()
  self.mapAddr = "98"
  self:clearTilemap()
  self.text = nil
  self:frame()
  while self.wx < 0xA1 do
    self.wx = self.wx + self.variant.scrollOut2
    self:frame()
  end
  self.mapAddr = "9C"
  self:waitBGMap()
  self.wx, self.wy = 7, 0x90
  self.mapAddr = "98"
  self:frame()
end

function Gen2TradeAnim:finish()
  if self.finishing == nil and not self.finished and coroutine.running() == self.co then
    -- TradeAnim_End: one last pass, then LoadStandardFont and out
    self.finishing = true
    self.phase = "end"
    self:frame()
    return
  end
  if self.finished then return end
  self.finished = true
  self.phase = "done"
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

-- ------------------------------------------------------------------ colour

-- Everything on screen is coloured here, through the cartridge's own
-- palettes, so the frame opts out of the zone pass.
function Gen2TradeAnim:sgbPalettes()
  return { { colors = false, x = 0, y = 0, w = 160, h = 144 } }
end

-- ------------------------------------------------------------------ draw

function Gen2TradeAnim:drawItem(item, ox, oy)
  local tx, ty = item.tx or 0, item.ty or 0
  local x, y = ox + tx * 8, oy + ty * 8
  if item.kind == "box" then
    love.graphics.push()
    love.graphics.translate(ox, oy)
    Font.drawBox(item.tx, item.ty, item.tw, item.th)
    love.graphics.pop()
  elseif item.kind == "text" then
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(item.text or "", x, y)
    love.graphics.setColor(1, 1, 1, 1)
  elseif item.kind == "rule" then
    love.graphics.setColor(0, 0, 0, 1)
    for i = 0, item.w - 1 do Font.drawCode(0x7A, x + i * 8, y) end
    love.graphics.setColor(1, 1, 1, 1)
  elseif item.kind == "arrows" then
    local img = self.img.arrows
    for i = 0, item.w - 1 do
      if img then
        love.graphics.draw(img, Kit.tileQuad(img,
          item.code == RIGHT_ARROW and 0 or 1, 2), x + i * 8, y)
      else
        love.graphics.setColor(0, 0, 0, 1)
        Font.drawCode(item.code, x + i * 8, y)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  elseif item.kind == "stats" then
    self:drawStats(item, ox, oy)
  elseif item.kind == "pic" then
    if item.img then
      local frame = self.picAnim and self.picAnim:image(item.mon)
      local img = frame or item.img
      local w, h = img:getDimensions()
      local wt = math.ceil(w / 8)
      -- PadFrontpic: a 6x6 pic sits one tile in and down, a 5x5 one tile
      -- in and two down, inside the 7x7 at (7,2)
      local dx = wt >= 7 and 0 or 1
      local dy = wt >= 7 and 0 or (7 - wt)
      love.graphics.draw(img, ox + 56 + dx * 8, oy + 16 + dy * 8)
    end
  elseif item.kind == "textbox" then
    love.graphics.push()
    love.graphics.translate(ox, oy)
    item.box:draw()
    love.graphics.pop()
  end
end

-- TrademonStats_MonTemplate: "─── №." over the top border at (4,0), the
-- number at (10,0), the species at (4,2), OT/ and the name (+ the gender
-- mark) at (4,4)/(7,4), <ID>№. and the ID at (4,6)/(7,6).  An egg has none
-- of it: EGG, OT/?????, <ID>№.?????
function Gen2TradeAnim:drawStats(item, ox, oy)
  local x, y = ox, oy
  local function code(c, tx, ty)
    if c == 0x73 or c == 0x74 then
      -- <ID> and № are FontBattleExtra tiles (LoadFontsBattleExtra)
      local r, g, b, a = love.graphics.getColor()
      love.graphics.setColor(1, 1, 1, 1)
      pcall(require("src.render.HudTiles").statusTile, c, x + tx * 8, y + ty * 8)
      love.graphics.setColor(r, g, b, a)
    else
      Font.drawCode(c, x + tx * 8, y + ty * 8)
    end
  end
  local function text(s, tx, ty) Font.draw(s, x + tx * 8, y + ty * 8) end
  love.graphics.setColor(0, 0, 0, 1)
  if item.egg then
    text(Strings("EGG"), 4, 2)
    text(Strings("OT/?????"), 4, 4)
    code(0x73, 4, 6)
    code(0x74, 5, 6)
    text(".?????", 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  -- "───" lies over the border's own ─ tiles; the rest replaces them
  love.graphics.rectangle("fill", x + 7 * 8, y, (self.variant.numberSpace
    and 7 or 6) * 8, 8)
  love.graphics.setColor(0, 0, 0, 1)
  code(0x74, 8, 0)
  text(".", 9, 0)
  text(Kit.digits(dexOf(self.game, item.mon), 3), 10, 0)
  text(speciesName(self.game, item.mon), 4, 2)
  text(Strings("OT/"), 4, 4)
  text((item.ot or "") .. (item.mark or ""), 7, 4)
  code(0x73, 4, 6)
  code(0x74, 5, 6)
  text(".", 6, 6)
  text(Kit.digits(item.otId, 5), 7, 6)
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen2TradeAnim:drawMap(map, ox, oy, ring)
  local tiles = self.img.tiles
  local base = self.art.tileBase
  local perRow = self.art.tilesPerRow
  for key, id in pairs(map.cells) do
    local row, col = math.floor(key / 32), key % 32
    local px = col * 8 + ox
    local x = ring and Kit.wrapX(px) or px
    if x and tiles and id >= base then
      love.graphics.draw(tiles, Kit.tileQuad(tiles, id - base, perRow),
                         x, row * 8 + oy)
    end
  end
  for _, item in ipairs(map.items) do
    if ring then
      local x0 = ((item.tx or 0) * 8 + ox) % 256
      self:drawItem(item, x0 - (item.tx or 0) * 8, oy)
      self:drawItem(item, x0 - 256 - (item.tx or 0) * 8, oy)
    else
      self:drawItem(item, ox, oy)
    end
  end
end

-- the OBJ tile `id` names in vTiles0 right now: (sheet, index, perRow)
function Gen2TradeAnim:objTile(id)
  local rel = id - self.art.objBase
  if self.objLayout == "tube" then
    if rel >= 0 and rel < 8 then
      local mon = self.tubeIcon
      local icon = mon and (mon == self.sent and self.icon.sent
        or self.icon.received)
      return icon, rel, 8
    elseif rel >= 0x10 and rel < 0x14 then
      return self.img.bubble, rel - 0x10, 4
    end
  end
  if rel >= 0 and rel < 22 then return self.img.obj, rel, 8 end
  return nil
end

-- a lower OAM entry wins where two overlap, so the list is drawn last
-- entry first: the trademon's icon (OAM 0-3) over its bubble
function Gen2TradeAnim:drawSprites(prio)
  for i = #self.oam, 1, -1 do
    local o = self.oam[i]
    local isPrio = bit.band(o.attr, 0x80) ~= 0
    if isPrio == prio and o.x > 0 and o.x < 168 and o.y > 0 and o.y < 160 then
      local img, index, perRow = self:objTile(o.tile)
      if img then
        local pal = bit.band(o.attr, 7) == 7 and self.obPal7 or self.obPal0
        Kit.withCgb(pal, self.obp0, function()
          Kit.drawObjTile(img, index, o.x, o.y, bit.band(o.attr, 0x20) ~= 0,
                          bit.band(o.attr, 0x40) ~= 0, perRow)
        end)
      end
    end
  end
end

function Gen2TradeAnim:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.cleared then
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    return
  end
  -- BG and window in raw shades, offscreen, so the font and box art come
  -- out exactly as everywhere else before they are coloured
  self.canvas = self.canvas or love.graphics.newCanvas(160, 144)
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(1, 1, 1, 1)
  self:drawMap(self.v98, -self.scx, 0, true)
  local wx, wy = self.wx - 7, self.wy
  if wy < 144 and wx < 160 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", math.max(0, wx), wy, 160, 144)
    self:drawMap(self.v9C, wx, wy, false)
  end
  love.graphics.pop()
  -- BG colour 0 everywhere, then OBJ-behind-BG sprites, then the BG with
  -- its colour 0 keyed out (OAM_PRIO), then the ordinary sprites
  -- before any layout of its own (TradeAnimationPlayer2 prints first) BG
  -- pal 0 is still whatever TradeAnim_NormalPals re-applied: plain shades
  local pal = self.bgPal or NEUTRAL
  local c0 = pal[bit.band(self.bgp, 3) + 1]
  love.graphics.setColor(c0[1] / 255, c0[2] / 255, c0[3] / 255, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
  self:drawSprites(true)
  local P = require("src.render.PaletteFX")
  local keyed = P.keyedShader and P.keyedShader()
  if keyed then
    local map = Kit.dmgMap(self.bgp)
    local function c(i)
      local col = pal[map[i] + 1]
      return { col[1] / 255, col[2] / 255, col[3] / 255 }
    end
    love.graphics.setShader(keyed)
    keyed:send("c0", c(0))
    keyed:send("c1", c(1))
    keyed:send("c2", c(2))
    keyed:send("c3", c(3))
    love.graphics.draw(self.canvas)
    love.graphics.setShader()
  else
    Kit.withCgb(pal, self.bgp, function() love.graphics.draw(self.canvas) end)
  end
  self:drawSprites(false)
end

return Gen2TradeAnim
