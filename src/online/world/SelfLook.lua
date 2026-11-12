-- YOUR OWN CHARACTER IN YOUR LOOK, offline and online.
--
-- The local player wears the MY LOOK choice (src/online/world/Avatar.lua;
-- OPTIONS -> MY LOOK offline, WORLDS / ONLINE -> MY LOOK online) everywhere:
-- single-player, a world, a link room -- the same look other players see.
-- With no look saved (or after RESET + SAVE) the game's own sheets come back
-- untouched.
--
-- WHAT IS SWAPPED.  Only the plain walk / idle sheet (`player.sprite`) and
-- the run sheet (`player.runSprite`; a chosen sheet with no run cycle runs on
-- its walk frames).  The bike and surf sheets keep the game's frames and only
-- wear the colour.  The field-move pose, the diving suit, fishing, Gen 4
-- fishing, and every special player state (HGSS Rocket disguise, Platinum's
-- Pokemon Center pose, Pokemon mode -- anything that moved `walkId` off the
-- normal form's sheet) keep the game's own frames: on those only the colour
-- is applied.
--
-- HOW.  Player:pose picks one of those instance fields, so swapping the
-- instances is enough for every draw path (flat GB/GBA, Gen 4/5 billboards in
-- the cartridge / first / third person cameras, dual screen, cast).  Nothing
-- in data.sprites is written.  The originals are kept on `player._look.orig`;
-- when the game rebuilds a sheet (refreshForm, a costume) the rebuilt one
-- becomes the original and the look is laid over it again next step.
--
-- Ticked once per logic step from Game:_step (beside HotActions).

local Avatar = require("src.online.world.Avatar")

local SelfLook = {}

SelfLook.FIELDS = { "sprite", "runSprite", "bikeSprite", "surfSprite" }

-- in a world, or inside a link room right now
function SelfLook.online(game)
  local W = package.loaded["src.online.world.OnlineWorld"]
  local c = W and W.client and W.client()
  if c and c.state == "in" then return true end
  local LR = package.loaded["src.online.LinkRooms"]
  local s = LR and LR.session
  local ow = game and game.overworld
  if s and s.roomMap and not s.peerLeft and ow and ow.map
     and tostring(ow.map.id) == tostring(s.roomMap) then
    return true
  end
  return false
end

-- the saved choice as { s = key in this cache or nil, t = tint or nil }
-- (asked every step: the answer is kept while the stored entry is the same
-- table -- Avatar.store always writes a new one)
local memo = { raw = nil, sprites = nil, want = nil }
function SelfLook.desired(game)
  local raw = Avatar.rawSaved(game)
  if not raw then return nil end
  local sprites0 = game.data and game.data.sprites
  if memo.raw == raw and memo.sprites == sprites0 and memo.game == Avatar.slot(game) then return memo.want end
  local want = SelfLook.compute(game)
  memo.raw, memo.sprites, memo.game, memo.want = raw, sprites0, Avatar.slot(game), want
  return want
end

function SelfLook.compute(game)
  local c = Avatar.saved(game)
  if not c then return nil end
  local sprites = (game.data and game.data.sprites) or {}
  local s = c.s and sprites[c.s] and c.s or nil
  -- the paint: whole-sprite tint and/or per-part colours
  local t = Avatar.paint({ t = c.t, c = c.c })
  if not (s or t) then return nil end
  return { s = s, t = t }
end

-- the game's normal walking sheet for this player (a costume moves walkId
-- off it)
function SelfLook.normalWalk(game)
  local data = game and game.data
  local okF, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  local walk = okF and FieldDefaults.fieldValue and FieldDefaults.fieldValue(data, "playerSprites", "walk")
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  local form = okS and Sprites.playerForm and Sprites.playerForm(data, game and game.save)
  if okS and form and require("src.core.GameVersion").isGen5() then
    local okB, Forms = pcall(require, "src.world.Gen5PlayerForms")
    if okB and Forms.fix then
      local okX, fixed = pcall(Forms.fix, data, form)
      if okX and fixed then form = fixed end
    end
  end
  if type(form) == "table" and form.walk and data and data.sprites and data.sprites[form.walk] then
    walk = form.walk
  end
  return walk
end

local function newSprite(def)
  local SpriteRenderer = require("src.render.SpriteRenderer")
  return SpriteRenderer.new(def, "player")
end

-- a tinted copy of one of the game's own sheets (same frames)
local function tinted(sr, t)
  if not (sr and sr.def and t) then return nil end
  local ok, copy = pcall(newSprite, sr.def)
  if not ok or not copy then return nil end
  Avatar.dress(copy, t)
  return copy
end

local function sigOf(want, p)
  return ("%s|%s|%s|%s"):format(tostring(want.s), Avatar.paintSig(want.t),
    tostring(p.walkId), tostring(p.bikeId))
end

-- put the game's sheets back (only where ours are still in place)
function SelfLook.restore(p)
  local L = p and p._look
  if not L then return false end
  for _, f in ipairs(SelfLook.FIELDS) do
    if p[f] == L.mine[f] then p[f] = L.orig[f] end
  end
  p._look = nil
  return true
end

function SelfLook.apply(game, p, want)
  local data = game.data or {}
  local sprites = data.sprites or {}
  local orig = {}
  for _, f in ipairs(SelfLook.FIELDS) do orig[f] = p[f] end
  local mine = {}
  local special = p.walkId ~= nil and p.walkId ~= SelfLook.normalWalk(game)
  local def = want.s and sprites[want.s]
  if def and not special then
    local ok, sr = pcall(newSprite, def)
    if ok and sr then
      if want.t then Avatar.dress(sr, want.t) end
      mine.sprite = sr
      local runDef = type(def.run) == "string" and sprites[def.run] or nil
      if runDef then
        local okR, rs = pcall(newSprite, runDef)
        if okR and rs then
          if want.t then Avatar.dress(rs, want.t) end
          mine.runSprite = rs
        end
      end
      -- no run cycle of its own: run on the walk frames
      if not mine.runSprite and orig.runSprite then mine.runSprite = sr end
    end
  elseif want.t then
    mine.sprite = tinted(orig.sprite, want.t)
    mine.runSprite = tinted(orig.runSprite, want.t)
  end
  if want.t then
    mine.bikeSprite = tinted(orig.bikeSprite, want.t)
    mine.surfSprite = tinted(orig.surfSprite, want.t)
  end
  for _, f in ipairs(SelfLook.FIELDS) do
    if mine[f] then p[f] = mine[f] else mine[f] = orig[f] end
  end
  p._look = { orig = orig, mine = mine, sig = sigOf(want, p) }
end

-- once per logic step
function SelfLook.step(game)
  local ow = game and game.overworld
  local p = ow and ow.player
  if not p then return end
  -- (offline too: one look everywhere; SelfLook.online still tells callers
  -- whether the player is in a world / room)
  local want = SelfLook.desired(game)
  local L = p._look
  if L then
    -- the game rebuilt a sheet under us: that is the new original
    local rebuilt = false
    for _, f in ipairs(SelfLook.FIELDS) do
      if p[f] ~= L.mine[f] then
        L.orig[f] = p[f]
        L.mine[f] = p[f]
        rebuilt = true
      end
    end
    if not want then return SelfLook.restore(p) end
    if not rebuilt and L.sig == sigOf(want, p) then return end
    SelfLook.restore(p)
  end
  if want then SelfLook.apply(game, p, want) end
end

-- the game's own on-foot sheet (fishing draws over it)
function SelfLook.ownSprite(p)
  local L = p and p._look
  return L and L.orig.sprite or nil
end

return SelfLook
