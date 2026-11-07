-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S PHENOMENA: shaking grass, dust clouds, rippling water and
-- the flying shadows over bridges -- read off the field overlay (ov21), not
-- guessed. Addresses are Pokemon Black (US); notes in docs/hgss-bw-import.md.
--
-- THE ROLL (0x21AA80C, run once a finished step by 0x218AC84 after 0x21AA944
-- has checked whether the player stands on the spot):
--   * only while no spot exists, on a zone with wild data
--   * a step counter (fieldstate+0xC) climbs; at the threshold of the zone's
--     cadence -- the encounter table's byte 7, table 0x21D8E70: 0 and 1 every
--     20 steps at 10%, 2 every 5 steps at 15% -- it rolls rand(1000) < 10 x
--     chance and is reset, hit or miss
--   * the window (0x21AABF4, rectangles at 0x21D8E76): an 11 x 11 square
--     round the player, of which cadences 0 / 1 take one half picked by
--     rand(4) (east, west, north or south) and cadence 2 the whole; clamped
--     to the player's own 32 x 32 block
--   * every tile in it is sorted by 0x21AB504 (the behaviour -> kind table in
--     Gen5FieldRules); a bridge (0x20) always counts, anything else needs the
--     encounter bit; one is drawn with rand(count), and refused if a person
--     stands there (the player is not asked)
--   * nothing about Repel, the bike or the season gates it
-- THE SPOT lasts while the zone does (no distance rule): a warp or a zone
-- change clears it, a person walking onto it clears it, a failed cast at it
-- clears it.
--
-- STEPPING ON IT (0x21AA944): r = rand(1000); the flying shadow gives an
-- item when r >= 200 (80%), the dust cloud when r >= 400 (60%); otherwise --
-- and always for grass and water -- a guaranteed battle (0x21A9F40 type 1,
-- no rate roll) from the phenomenon list, or the rippling-surf list when the
-- tile is water. Items (0x21AB018 / 0x21AB070): dust -- 10% an evolution
-- stone or Oval Stone (0x21D8E8A), 85% one of the 17 Gems, 5% an Everstone;
-- shadow -- 90% one of the six Wings, 10% a Pretty Wing.
--
-- THE PICTURE (0x21ADAAC, resources 0x21DE094, kind -> resource 0x21D9238):
--   kinds 0-2 grass   models 60 + season + 4 x kind (short_grass, 3 = long)
--   kind 3  tall grass  68 + season (long_grass)       sound SEQ_SE_FLD_70
--   kind 4  dust        76 soil_smoke, anims 147 / 119  SEQ_SE_FLD_73
--   kind 5  water 0x3D  72 freshwater_in, anim 115      SEQ_SE_FLD_71
--   kind 6  rippling    74 sea_out, anim 117            SEQ_SE_FLD_71
--   kind 7  shadow      75 bird_shadow, 146 / 118       SEQ_SE_FLD_72
-- The animation steps one frame a field tick and loops; each time it comes
-- round to frame 0 the sound plays, louder the nearer the player is: volume
-- {127, 90, 60, 40} by min(distance / 5, 3) (0x21D9234). The models are drawn
-- here as the billboards and ground decals they are, moved by the same
-- per-frame tracks (gen5_field_effects.anims).

local Rules = require("src.world.Gen5FieldRules")

local P = {}

P.KIND = { [0x04] = 0, [0x05] = 1, [0x21] = 2, [0x08] = 3, [0x0A] = 4,
           [0x3D] = 5, [0x3F] = 6, [0x43] = 6, [0x20] = 7 }
P.CADENCE = { [0] = { steps = 20, chance = 10 }, [1] = { steps = 20, chance = 10 },
              [2] = { steps = 5, chance = 15 } }
P.HALVES = { { 0, 5, -5, 5 }, { -5, 0, -5, 5 }, { -5, 5, -5, 0 }, { -5, 5, 0, 5 } }
P.FULL = { -5, 5, -5, 5 }
P.SHADOW_ITEM, P.DUST_ITEM = 200, 400
P.STONES = { 80, 81, 82, 83, 84, 85, 107, 108, 109, 110 }
P.EVERSTONE = 229
P.SOUND = { [0] = "SEQ_SE_FLD_70", "SEQ_SE_FLD_70", "SEQ_SE_FLD_70", "SEQ_SE_FLD_70",
            "SEQ_SE_FLD_73", "SEQ_SE_FLD_71", "SEQ_SE_FLD_71", "SEQ_SE_FLD_72" }
P.VOLUME = { 127, 90, 60, 40 }
P.BLOCK = 32

local function Game() return package.loaded["src.core.Game"] end
local function rand(n) return love.math.random(0, n - 1) end

local function view(ow)
  local G = Game()
  local def = ow and ow.map and ow.map.def
  if not (G and def and def.gen5) then return nil end
  local Encounter = require("src.world.Encounter")
  local ok, v = pcall(Encounter.forMap, G.data, def, ow.map.id, nil, G.save)
  return ok and type(v) == "table" and v.family == "bw" and v or nil
end

-- the zone's cadence: its table's byte 7 (a cache from before it was kept
-- has none, and is taken as the commonest, 0)
function P.cadence(v)
  local raw = v and v.raw
  return P.CADENCE[tonumber(raw and raw.phenomenon) or 0] or P.CADENCE[0]
end

local function behaviourAt(map, x, y)
  if not (map.inBounds and map:inBounds(x, y)) then return nil end
  return map:cellBehaviour(x, y)
end

function P.kindAt(map, x, y)
  local b = behaviourAt(map, x, y)
  local k = b and P.KIND[b]
  if k == nil then return nil end
  if k ~= 7 and not Rules.ENCOUNTER[b] then return nil end
  return k
end

local function occupied(ow, x, y)
  for _, npc in ipairs(ow.npcs or {}) do
    if not npc.hidden and npc.cellX == x and npc.cellY == y then return true end
  end
  return false
end

-- spawn(ow, v, cadence) -> the spot or nil (0x21AABF4 / 0x21AACD4)
function P.spawn(ow, v, cadence)
  local p, map, def = ow.player, ow.map, ow.map.def
  local rect = (cadence == P.CADENCE[2]) and P.FULL or P.HALVES[rand(4) + 1]
  -- the player's 32 x 32 block, in this map's local cells
  local gx, gy = (def.originX or 0) + p.cellX, (def.originY or 0) + p.cellY
  local bx, by = gx - gx % P.BLOCK, gy - gy % P.BLOCK
  local cands = {}
  for dy = rect[3], rect[4] do
    for dx = rect[1], rect[2] do
      local tx, ty = gx + dx, gy + dy
      if tx >= bx and tx < bx + P.BLOCK and ty >= by and ty < by + P.BLOCK then
        local lx, ly = tx - (def.originX or 0), ty - (def.originY or 0)
        local k = P.kindAt(map, lx, ly)
        if k then cands[#cands + 1] = { lx, ly, k } end
      end
    end
  end
  if #cands == 0 then return nil end
  local c = cands[rand(#cands) + 1]
  if occupied(ow, c[1], c[2]) then return nil end
  local spot = { x = c[1], y = c[2], kind = c[3], mapId = map.id, age = 0 }
  ow.gen5Spot = spot
  if os.getenv("BW_SPOT_TRACE") then
    print(("[spot] spawned %s (%d,%d) kind %d of %d candidates"):format(map.id, spot.x, spot.y, spot.kind, #cands))
  end
  return spot
end

-- once a finished step (OverworldController's step hook, BW maps only)
function P.step(ow)
  local spot = ow.gen5Spot
  if spot and spot.mapId ~= (ow.map and ow.map.id) then ow.gen5Spot, spot = nil, nil end
  if spot and occupied(ow, spot.x, spot.y) then ow.gen5Spot, spot = nil, nil end
  if spot then return end
  local v = view(ow)
  if not v then return end
  local cad = P.cadence(v)
  ow.gen5SpotSteps = (ow.gen5SpotSteps or 0) + 1
  if ow.gen5SpotSteps < cad.steps then return end
  ow.gen5SpotSteps = 0
  local hit = rand(1000) < cad.chance * 10
  if os.getenv("BW_SPOT_TRACE") then print(("[spot] roll at %d steps: %s"):format(cad.steps, tostring(hit))) end
  if hit then P.spawn(ow, v, cad) end
end

function P.clear(ow) ow.gen5Spot = nil end

function P.at(ow, x, y)
  local s = ow and ow.gen5Spot
  return s and s.mapId == (ow.map and ow.map.id) and s.x == x and s.y == y and s or nil
end

local function giveItem(ow, item)
  local G = Game()
  local data, save = G.data, G.save
  local key = ("ITEM_%03d"):format(item)
  pcall(function() require("src.inventory.Bag").add(save, data.items[key] and key or item, 1, data) end)
  local def = data.items and (data.items[item] or data.items[key])
  local U = require("src.inventory.Gen5ItemUse")
  local line = U.storyLine(data, 283, 4, { save.player and save.player.name or "", def and def.name or tostring(item) },
    ("%s found %s!"):format(save.player and save.player.name or "", def and def.name or tostring(item)))
  pcall(function() require("src.core.Sound").play(data, "SEQ_ME_ITEM") end)
  G.stack:push(require("src.render.TextBox").new(G, line))
end

function P.dustItem()
  local r = rand(100)
  if r < 10 then return P.STONES[rand(#P.STONES) + 1] end
  if r < 95 then return 548 + math.floor(rand(1700) / 100) end
  return P.EVERSTONE
end
function P.shadowItem()
  if rand(100) < 90 then return 565 + math.floor(rand(600) / 100) end
  return 571
end

-- the step's encounter, before the ordinary roll: true when the spot took it
function P.encounter(ow, encDef)
  local p = ow.player
  local spot = P.at(ow, p.cellX, p.cellY)
  if not spot then return false end
  ow.gen5Spot = nil
  local r = rand(1000)
  if spot.kind == 7 and r >= P.SHADOW_ITEM then giveItem(ow, P.shadowItem()) return true end
  if spot.kind == 4 and r >= P.DUST_ITEM then giveItem(ow, P.dustItem()) return true end
  local v = encDef and encDef.family == "bw" and encDef or view(ow)
  local water = spot.kind == 5 or spot.kind == 6
  local tbl = v and (water and v.raw and v.raw.ripplingSurf and v.raw.ripplingSurf.slots
                     or v.raw and v.raw.rustling)
  if not (tbl and tbl[1] and (tonumber(tbl[1].species) or 0) > 0) then return true end
  local G = Game()
  -- 0x021AA9EA runs the walking check in mode 1: a forced encounter (flag
  -- 0x8), so neither Repel nor Keen Eye / Intimidate refuses it (0x021A996C);
  -- the lead's other rules apply (src/world/Gen5WildLead.lua)
  local enc = require("src.world.Gen5WildLead").choose(G.data, G.save, tbl, love.math.random,
                                                       { forced = true })
  if not (enc and enc.species) then return true end
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(G, enc.species, enc.level,
    { nature = enc.nature, gender = enc.gender })
  ow.gen5EncSteps = 0       -- mode 1 runs 0x021A9F40, which zeroes the step counter
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  return true
end

-- the rod (Gen4Fishing.roll's BW arm): the lure on the spot fishes the
-- rippling list and always bites (0x21AA180); elsewhere the rate is rolled
function P.fishTable(ow, v, tx, ty)
  local spot = P.at(ow, tx, ty)
  if spot and v.ripplingRod then return v.ripplingRod, true end
  return v.superRod, false
end

-- ---------------------------------------------------------------- drawing

local images = {}
local function image(data, key)
  if images[key] ~= nil then return images[key] or nil end
  local fx = data and data.gen5_field_effects
  local rec = fx and fx.textures and fx.textures[key]
  local img = false
  if rec and rec.rgba then
    local ok, made = pcall(function()
      local d = love.image.newImageData(rec.width, rec.height, "rgba8", rec.rgba)
      local i = love.graphics.newImage(d)
      i:setFilter("nearest", "nearest")
      return i
    end)
    img = ok and made or false
  end
  images[key] = img
  return img or nil
end

local SEASON = { [0] = "sp", "su", "au", "wi" }

-- what the spot's resource draws: { tex, anim, srt, flat, scale }
local function look(spot, season)
  local k, s = spot.kind, SEASON[season] or "sp"
  if k <= 2 then
    local member = 60 + season + 4 * k
    if k == 2 then return { tex = ("%d/naga_kusa_%s"):format(68 + season, s), anim = 142 + season, sway = true } end
    local name = ("ee_kusa_%s%s"):format(s, (k == 1 and season == 3) and "2" or "")
    return { tex = ("%d/%s"):format(member, name), anim = 134 + season + 4 * k, sway = true, flat = true }
  elseif k == 3 then
    return { tex = ("%d/naga_kusa_%s"):format(68 + season, s), anim = 142 + season, sway = true }
  elseif k == 4 then
    return { tex = "76/mogu_kemu01", anim = 147, scaleAnim = 119, spin = true }
  elseif k == 5 or k == 6 then
    local suffix = k == 6 and "s" or ""
    return { rings = { ("%d/uo_kage01%s"):format(k == 6 and 74 or 72, suffix),
                       ("%d/uo_kage02%s"):format(k == 6 and 74 or 72, suffix) },
             scaleAnim = k == 6 and 117 or 115, flat = true }
  end
  return { tex = "75/tori_kage01", anim = 146, scaleAnim = 118, flat = true, sway = true }
end

local function at(arr, f)
  if type(arr) ~= "table" or #arr == 0 then return nil end
  return arr[math.min(#arr, f)] or arr[#arr]
end

-- every engine tick (the field's tick is two): the loop and its sound
function P.tick(ow)
  local spot = ow and ow.gen5Spot
  if not spot then return end
  spot.age = (spot.age or 0) + 1
  local G = Game()
  local fx = G and G.data and G.data.gen5_field_effects
  local lk = look(spot, Rules.season(G and G.save))
  local an = fx and fx.anims and fx.anims[lk.anim or lk.scaleAnim]
  local frames = (an and an.frames) or 16
  if spot.age % (frames * 2) == 1 then
    local p = ow.player
    local d = math.max(math.abs(spot.x - p.cellX), math.abs(spot.y - p.cellY))
    local vol = P.VOLUME[math.min(math.floor(d / 5), 3) + 1] / 127
    pcall(function()
      local src = require("src.core.Sound").playSe(G.data, P.SOUND[spot.kind])
      if src and src.setVolume then src:setVolume(src:getVolume() * vol) end
    end)
  end
end

-- draw(ow, ground, cam): in the overworld's effect pass, on the 3D ground
function P.draw(ow, ground, cam)
  local spot = ow and ow.gen5Spot
  if not (spot and ground) or spot.mapId ~= (ow.map and ow.map.id) then return end
  local G = Game()
  local data = G and G.data
  local fx = data and data.gen5_field_effects
  if not fx then return end
  local lk = look(spot, Rules.season(G.save))
  local f30 = math.floor((spot.age or 0) / 2)
  local an = fx.anims and fx.anims[lk.anim]
  local sc = fx.anims and fx.anims[lk.scaleAnim]
  local frames = (an and an.frames) or (sc and sc.frames) or 16
  local frame = f30 % frames + 1
  local Draw = require("src.world.Gen4EmoteDraw")
  local px, py = spot.x * 16, spot.y * 16
  local g = love.graphics
  local gs = ground.groundScale or 1
  local function one(img, sx, sy, ox, oy, rot, flat)
    local w, h = img:getWidth(), img:getHeight()
    local function paint(cx, cy)
      g.setColor(1, 1, 1, 1)
      if flat then
        g.draw(img, cx + (ox or 0), cy + (oy or 0) * gs, rot or 0, sx, sy * gs, w / 2, h / 2)
      else
        g.draw(img, cx + (ox or 0), cy - h / 2 * sy + (oy or 0), rot or 0, sx, sy, w / 2, h / 2)
      end
    end
    local free = ground.freeMode and ground:freeMode()
    if free then
      ground:freeEntity(px, py, cam.x, cam.y, 0, function()
        paint(px + 8 - cam.x, py + 12 - cam.y)
      end, 4)
    else
      local cx, cy = Draw.groundSpot(ground, px, py, cam)
      paint(cx, cy - 4)
    end
  end
  g.push("all")
  if lk.rings then
    for i, key in ipairs(lk.rings) do
      local img = image(data, key)
      local j = sc and sc.joints and sc.joints[i]
      local sx = j and at(j.sx, frame) or 1
      if img then one(img, sx, (j and at(j.sz, frame)) or sx, 0, 0, 0, true) end
    end
  else
    local img = image(data, lk.tex)
    if img then
      local srt = an and an.srt
      local ox = lk.sway and srt and (at(srt.tS, frame) or 0) * img:getWidth() or 0
      local oy = lk.sway and srt and (at(srt.tT, frame) or 0) * img:getHeight() or 0
      local rot = 0
      if lk.spin and srt then
        local c, s = at(srt.rc, frame) or 1, at(srt.rs, frame) or 0
        rot = math.atan2(s, c)
      end
      local j = sc and sc.joints and sc.joints[1]
      local s = j and at(j.sx, frame) or 1
      one(img, s, s, ox, oy, rot, lk.flat)
    end
  end
  g.pop()
end

return P
