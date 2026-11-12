-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROOM ACTORS (round 6): the sprites of the castle escape, from the
-- cartridge's room sprite lists (RomMap.roomSprites, the SNES
-- Dungeon_LoadSprites), with the cartridge's combat tables (RomMap.combat:
-- health, bump damage, hit boxes, Link's damage, the sword's hit boxes and
-- swing timing). Pure logic; the game draws them.
--
-- From the cartridge: which sprite stands where in which room and on which
-- level, its subtype (patrol direction), its key drop, its health, its hit
-- box, the damage it deals Link (kPlayerDamages by bump class), the sword's
-- per-step hit boxes and step lengths (kSpinAttackDelays), chest contents.
-- OURS (docs/zelda/alttp.md "Round 6"): the AI is a reduced port of the SNES
-- guard logic (patrol along the subtype's direction, turn at walls, chase
-- when Link is in front within 80 px, chase speed 1 px a frame, patrol
-- 0.5 px); the sword's damage assumes damage class 1 for every enemy (the
-- SNES enemy_damage_data is not located: 2 points with the fighter sword);
-- round 10: the sword's knockback and Link's are the cartridge's (A:recoilStep,
-- A.project, Escape hurtLink); Link is invulnerable 58 frames after a hit;
-- round 10: "kill to open" tags follow the cartridge's quadrant rule; the 0x4B
-- knights appear only once Zelda follows (their SNES spawn rule is not
-- read); critters wander at random.

local bit = require("bit")
local band = bit.band
local Guard = require("src.zelda.alttp.Guard")

local A = {}
A.__index = A

local SOLDIER = { [0x41] = true, [0x42] = true, [0x43] = true, [0x44] = true, [0x45] = true,
                  [0x46] = true, [0x47] = true, [0x48] = true, [0x49] = true, [0x4A] = true,
                  [0x4B] = true, [0x6A] = true }
local CRITTER = { [0x6D] = true, [0x6E] = true, [0x6F] = true }
A.SOLDIER, A.CRITTER = SOLDIER, CRITTER
-- round 10: what a bush / pot secret can hold besides items (zelda3
-- kSpawnSecretItems: 0x3E hoarder, 0x79 bee, 0x0B cucco, 0x41/0x42 soldiers)
local SECRET = { [0x79] = "bee", [0x0B] = "cucco", [0x3E] = "hoarder" }
A.SECRET = SECRET
-- round 17: + the Eastern Palace's enemies (Palace.FIGHTS)
local Palace = require("src.zelda.alttp.Palace")
local function fights(t) return SOLDIER[t] or CRITTER[t] or t == 0x79 or t == 0x3E or Palace.FIGHTS[t] end
A.fights = fights
A.UNCLE, A.ZELDA, A.MANTLE, A.PULL, A.TRAP, A.KEY = 0x73, 0x76, 0xEE, 0x04, 0x06, 0xE4

-- messages (BMG index): the uncle in the passage, Zelda freed, the shelf,
-- the switch before the sanctuary, the priest
A.MSG_UNCLE = 14
A.MSG_ZELDA = 33
A.MSG_SHELF = 34
A.MSG_SWITCH = 42
A.MSG_PRIEST = 23

local DIRV = { [0] = { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }   -- up, down, left, right

-- the escape's progress (saved): sword, zelda (1 = follows), escaped
function A.newProgress()
  return { sword = false, zelda = 0, escaped = false, bigKey = {}, items = {} }
end

function A.new(game)
  local self = setmetatable({ game = game, list = {}, room = nil, frame = 0 }, A)
  return self
end

local function combat(game) return game.data.roomIdx.combat end

-- sprite hit box: kSpriteHitbox_* by flags4 & 0x1F
function A.hitbox(cb, a)
  local i = band(cb.flags4[a.type + 1] or 0, 0x1F) + 1
  local xo = (cb.hitXLo[i] or 0) % 256 + (cb.hitXHi[i] or 0) * 256
  local yo = (cb.hitYLo[i] or 0) % 256 + (cb.hitYHi[i] or 0) * 256
  if xo >= 0x8000 then xo = xo - 0x10000 end
  if yo >= 0x8000 then yo = yo - 0x10000 end
  if xo > 0x7FFF then xo = xo - 0x10000 end
  return a.x + xo, a.y + yo, cb.hitXSize[i] or 16, cb.hitYSize[i] or 16
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end
A.overlap = overlap
-- r20: Link_SetupHitBox (0x86F70A): Link's body box against sprites
function A.linkBox(lk) return lk.x + 4, lk.y + 8, 8, 8 end
-- r20: CheckIfHitBoxesOverlap (0x86F836): boxes that only touch count
-- (b - a + bsize in 0 .. asize + bsize on both axes)
function A.overlapCart(ax, ay, aw, ah, bx, by, bw, bh)
  local ty = by - ay + bh
  if ty < 0 or ty > ah + bh then return false end
  local tx = bx - ax + bw
  return tx >= 0 and tx <= aw + bw
end
-- round 16: the walls a sprite meets (BallChain.lua)
function A:walkableFor(a, x, y) return A._walkable(self.inside, a, x, y) end

-- spawn the room's sprites
function A:enterRoom(inside)
  local game = self.game
  local idx = game.data.roomIdx
  local room = inside.room
  self.room, self.list, self.inside = room, {}, inside
  local spr = idx.sprites and idx.sprites[room + 1] or {}
  local cb = combat(game)
  local prog = game.progress
  inside.mem.taken = inside.mem.taken or {}
  -- round 13: the cartridge's kill memory (Dungeon_ResetSprites 0x89C114,
  -- Sprite_ManuallySetDeathFlagUW, Dungeon_LoadSingleSprite): a killed
  -- sprite stays dead while its room is one of the last 4 rooms entered;
  -- entering a palace or continuing (Module_PreDungeon / Death_Func15 ->
  -- Sprite_ResetAll, here a new Interior) clears it
  local km = self.kills
  if not km or km.inside ~= inside then
    km = { inside = inside, hist = {}, dead = {} }
    self.kills = km
  end
  local known = false
  for _, r in ipairs(km.hist) do if r == room then known = true end end
  if not known then
    table.insert(km.hist, 1, room)
    if #km.hist > 4 then local old = table.remove(km.hist); km.dead[old] = nil end
  end
  local deadHere = km.dead[room] or {}
  -- round 17: the room's overlords and the palace sprites' counters
  Palace.enterRoom(self, inside)
  for i, s in ipairs(spr) do
    local keep = true
    local t = s.type
    if deadHere[i] and band(cb and cb.deflBits and cb.deflBits[t + 1] or 0, 1) == 0 then keep = false end
    if t == 0x4B and prog.zelda < 1 then keep = false end
    if t == A.UNCLE and room == 0x104 and not game.opening then keep = false end
    if t == A.ZELDA and room ~= 0x80 then keep = false end
    if t == A.ZELDA and prog.zelda >= 1 then keep = false end
    if t == A.MANTLE and inside.mem.mantleMoved then keep = "moved" end
    if s.drop and inside.mem.taken[i] then keep = keep and "nodrop" end
    -- r19: a room's own absorbable sprite (0xD8-0xE3: room 0x89's fairies)
    -- is the prize it shows (Sprite_D8_Heart ... Sprite_E3_Fairy), placed:
    -- no lifetime (OURS: it rests where the list puts it)
    local Dr = require("src.zelda.alttp.Drops")
    if keep and t ~= A.KEY and Dr.ABSORB and Dr.ABSORB[t] and game.spawnDrop and inside.attrs then
      game.drops = game.drops or {}
      game:spawnDrop(t, s.x, s.y)
      local dd = game.drops[#game.drops]
      if dd and dd.type == t then dd.placed, dd.life, dd.lower, dd.room = true, 1e9, s.lower or false, room end
      keep = false
    end
    if keep then
      local a = { type = t, x = s.x, y = s.y, lower = s.lower, sub = s.sub, index = i,
                  hp = cb and cb.health[t + 1] or 1, drop = (keep ~= "nodrop") and s.drop or nil,
                  dir = 1, t = 0, state = "idle" }
      if SOLDIER[t] then
        a.state = "patrol"
        local st = band(s.sub, 7)
        a.dir = (st >= 1 and st <= 4) and bit.bxor(st - 1, 1) or 1
        a.wait = 64
      elseif CRITTER[t] then
        a.state = "wander"; a.wait = 32
      end
      if t == A.MANTLE and keep == "moved" then a.x = a.x + 34 end
      -- round 16: people (Npc.lua): their SpritePrep offsets
      local np = require("src.zelda.alttp.Npc").TYPES[t]
      if np then
        a.npc = true
        if np.prep then a.x, a.y = a.x + np.prep[1], a.y + np.prep[2] end
      end
      -- round 13: the sword guards run the cartridge's guard routine indoors
      if Guard.TYPES[t] and inside.attrs and cb and cb.guardXvel then Guard.prep(a, i) end
      -- round 14: the green knife guard's own routine (Guard.updateRecruit)
      if t == 0x4B and inside.attrs and cb and cb.recruitXvel then
        Guard.prepRecruit(a, i, require("src.zelda.alttp.Drops").rng(game:dropRng()))
      end
      -- round 17: the Eastern Palace's sprites (Palace.lua)
      if Palace.TYPES[t] and inside.attrs and Palace.ready(game) then Palace.prep(self, a, i - 1) end
      self.list[#self.list + 1] = a
    end
  end
  -- the follower walks in behind Link
  self.trail = nil
  self.cleared = false
end

function A:hostiles()
  local n = 0
  for _, a in ipairs(self.list) do
    if fights(a.type) and not a.dead then n = n + 1 end
  end
  return n
end

-- is (x, y) inside a solid actor (the mantle, an NPC)?
function A:solidAt(x, y)
  for _, a in ipairs(self.list) do
    if a.type == A.MANTLE and not a.dead and self.game and combat(self.game) then
      -- round 10: the shelf blocks with its cartridge hit box (48 x 20 below
      -- its top; the SNES repels Link from it); OURS: not once it has slid
      -- aside (the doorway behind it stays clear)
      local hx, hy, hw, hh = A.hitbox(combat(self.game), a)
      local moved = self.inside and self.inside.mem and self.inside.mem.mantleMoved
      if not moved and x >= hx and x < hx + hw and y >= hy and y < hy + hh then return a end
    elseif (a.type == A.MANTLE or a.type == A.UNCLE or (a.type == A.ZELDA and not a.follow)
            or require("src.zelda.alttp.Npc").TYPES[a.type]) and not a.dead then
      local w = a.type == A.MANTLE and 32 or 16
      if x >= a.x and x < a.x + w and y >= a.y and y < a.y + 16 then return a end
    end
  end
end

local function walkable(inside, a, nx, ny)
  local saved = inside.lower
  inside.lower = a.lower
  local ok = not (inside:blocked(nx + 2, ny + 8) or inside:blocked(nx + 13, ny + 8)
                  or inside:blocked(nx + 2, ny + 15) or inside:blocked(nx + 13, ny + 15))
  inside.lower = saved
  return ok
end
A._walkable = walkable

-- one frame of every actor. `link` = { x, y, lower }, returns nothing; hits
-- on Link are reported through game:hurtLink(dmg, fromX, fromY)
function A:update()
  local game, inside = self.game, self.inside
  if not inside then return end
  self.frame = self.frame + 1
  -- r20: set_when_damaging_enemies counts down (Sprite_Main: & 0x7F)
  if band(game.swde or 0, 0x7F) ~= 0 then game.swde = game.swde - 1 else game.swde = 0 end
  local lk = game.link
  local cb = combat(game)
  local camx, camy = 0, 0
  if inside.camera then camx, camy = inside:camera(lk.x, lk.y, 240, 160) end
  for _, a in ipairs(self.list) do
    if not a.dead then
      a.t = a.t + 1
      local ox, oy = a.x, a.y
      if a.guard then
        -- round 13: Guard.lua (Guard_Main; its own recoil step)
        Guard.update(self, a, lk, camx, camy)
      elseif a.recoil and not a.palace and self:recoilStep(a) then
        -- round 10: knocked back / stunned (Sprite_ReturnIfRecoiling)
        -- r20: not the palace's sprites: their own routines run first and
        -- call Sprite_ReturnIfRecoiling where the cartridge does (the Armos
        -- Knights fall and drop out of their ring before it; before, a
        -- stunned knight hung in the air and then jumped back to its spot)
      elseif a.recruit then
        Guard.updateRecruit(self, a, lk)
      elseif a.palace then
        -- round 17: the Eastern Palace's sprites (Palace.lua)
        Palace.update(self, a, lk)
      elseif a.type == 0x6A and inside.attrs and require("src.zelda.alttp.BallChain").ready(game) then
        -- round 16: the cartridge's ball-and-chain guard (BallChain.lua)
        require("src.zelda.alttp.BallChain").update(self, a, lk)
      elseif SOLDIER[a.type] then
        self:soldier(a, lk)
      elseif CRITTER[a.type] then
        self:critter(a)
      elseif SECRET[a.type] then
        self[SECRET[a.type]](self, a, lk)
      elseif a.type == 0xBB and inside.attrs then
        -- r22: the shop clerk and his wares (Shop.lua)
        require("src.zelda.alttp.Shop").update(self, a, lk)
      elseif a.type == 0x3B and inside.attrs then
        -- r21: the dash item (the Book of Mudora, bonk keys; DashItem.lua)
        require("src.zelda.alttp.DashItem").update(self, a, lk)
      elseif a.desert then
        -- r23: the desert statues and plaque (Desert.lua)
        require("src.zelda.alttp.Desert").update(self, a, lk)
      elseif a.type == A.KEY then
        if overlap(lk.x + 2, lk.y + 8, 12, 14, a.x + 4, a.y + 4, 8, 8) then
          a.dead = true
          -- r22: a pot's key sets the room's key flag (Interior.liftPot)
          if a.potKey then inside.mem.potKey = true end
          game:getItem(a.big and 0x32 or 0x24)
        end
      elseif a.type == A.MANTLE and not inside.mem.mantleMoved then
        self:mantle(a, lk)
      end
      -- round 7: walking (for the walk frames of the drawing)
      if a.x ~= ox or a.y ~= oy then a.movedT = a.t end
      a.moving = a.movedT ~= nil and a.t - a.movedT < 4
      -- r20: the hit timer (Sprite_TimersAndOam): the damage a hit gave is
      -- taken when the timer reaches 24 (Sprite_MiniMoldorm_Recoil)
      if a.inv and a.inv > 0 then
        if a.inv == 24 and a.pend then self:takeDamage(a) end
        a.inv = a.inv - 1
        if a.inv == 0 then a.invSword = nil end
      end
      -- contact damage to Link (not while recoiling: the SNES AI returns early)
      -- r20: Sprite_CheckDamageToPlayer_1: only on frames where (slot ^
      -- frame) & 3 == 0 and not while the sprite's hit timer runs; Link's
      -- box is Link_SetupHitBox (x + 4, y + 8, 8 x 8), the sprite's is
      -- lifted by its height (Sprite_SetupHitBox: y - z)
      if fights(a.type) and cb and (a.lower or false) == (inside.lower or false) and not a.recoil
         and not ((a.aux4 or 0) > 0 and not a.palace) and not a.dead and not a.dying and not a.untouchable
         and not a.noTouch   -- r26b: the sprite checks its own contact (Dungeons26.lua)
         and band(bit.bxor(a.k or a.index or 0, self.frame), 3) == 0 and not ((a.inv or 0) > 0)
         and (a.z or 0) >= 0 and a.type ~= 0x85 then   -- (r20: 0x85 touches Link in Palace.yellowStalfos)
        local hx, hy, hw, hh = A.hitbox(cb, a)
        local lx, ly, lw, lh = A.linkBox(lk)
        if A.overlapCart(lx, ly, lw, lh, hx, hy - (a.z or 0), hw, hh) then
          local cls = band(a.bump or cb.bump[a.type + 1] or 0, 0x0F)   -- r25: a.bump (SpritePrep_Raven / _Tektite)
          game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
        end
      end
    end
  end
  -- room tags: kill enemies (1-10) / pull lever (0x14) open the shutters
  -- round 10: the cartridge's quadrant rule (zelda3 kDungTagroutines 1-9:
  -- RoomTag_NorthWestTrigger .. Dung_TagRoutine_0x30 test which quadrant /
  -- half Link is in, then RoomTag_QuadrantTrigger opens the trapdoors when
  -- Sprite_CheckIfScreenIsClear finds no live sprite on screen; here "on
  -- screen" = in Link's quadrant, the 256 x 256 the SNES camera shows)
  -- round 16: tags 0x0A (RoomTag_RoomTrigger: every enemy of the room) and
  -- 0x0B-0x13 (the quadrant rule with a push block: dung_flag_trapdoors_down
  -- = !dung_flag_movable_block_was_pushed, so a second push closes them)
  do
    local hdr = inside.hdr
    for _, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
      if tag == 0x0A and not self.cleared then
        local clear = true
        for _, a in ipairs(self.list) do if not a.dead and fights(a.type) then clear = false break end end
        -- r21: a sprite still in its death puff is not gone yet
        if clear and require("src.zelda.alttp.Effects").dying(game) then clear = false end
        if clear then self.cleared = true; game:openShutters() end
      elseif tag >= 0x0B and tag <= 0x13 then
        local rx, ry = lk.x >= 256, lk.y >= 256
        local q = tag - 0x0A
        local here = ({ [1] = not rx and not ry, [2] = rx and not ry, [3] = not rx and ry, [4] = rx and ry,
                        [5] = not rx, [6] = rx, [7] = not ry, [8] = ry, [9] = true })[q]
        local want = inside.blockPushed and true or false
        if here and want ~= (self.pushOpen or false) then
          self.pushOpen = want
          if want then game:openShutters() elseif game.closeShutters then game:closeShutters() end
        end
      end
    end
  end
  if not self.cleared then
    local hdr = inside.hdr
    for _, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
      if tag >= 1 and tag <= 9 and not self.cleared then
        local rx, ry = lk.x >= 256, lk.y >= 256
        local here = ({ [1] = not rx and not ry, [2] = rx and not ry, [3] = not rx and ry, [4] = rx and ry,
                        [5] = not rx, [6] = rx, [7] = not ry, [8] = ry, [9] = true })[tag]
        if here then
          local clear = true
          local qx, qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
          for _, a in ipairs(self.list) do
            if not a.dead and fights(a.type) and math.floor((a.x + 8) / 256) == qx
               and math.floor((a.y + 8) / 256) == qy then clear = false break end
          end
          if clear and require("src.zelda.alttp.Effects").dying(game) then clear = false end
          if clear then
            self.cleared = true
            game:openShutters()
          end
        end
      end
    end
  end
  self.spawnedHostiles = self.spawnedHostiles or self:hostiles() > 0
  -- round 17: the overlords (cannons, the Armos coordinator) and the
  -- switch / prize room tags (Palace.roomTags)
  Palace.updateOverlords(self, camx, camy)
  if Palace.ready(game) then Palace.roomTags(self, lk) end
  self:updateFollower()
end

-- Round 10: the cartridge's sprite recoil (zelda3 Sprite_ReturnIfRecoiling,
-- 0x86FF78; masks read from 0x171DC0): sprite_F counts down from 15; on frames where
-- frame_counter & kMasks[F >> 2] == 0 the sprite moves by its recoil
-- velocity (1/16 px a frame, Sprite_MoveXY) unless a wall stops that axis;
-- a strong recoil (|v| >= 0x20) ends in F = 144: 16 frames stunned in place.
function A:recoilStep(a)
  local masks = combat(self.game).recoilMasks or {}
  local F = a.recoil
  if F == 0 then a.recoil = nil return false end
  if band(F, 0x7F) == 0 then a.recoil = nil return false end
  F = F - 1
  if F == 0 and (math.abs(a.rvx) >= 0x20 or math.abs(a.rvy) >= 0x20) then F = 144 end
  a.recoil = F
  if F < 128 and band(self.frame, masks[math.floor(F / 4) + 1] or 0) == 0 then
    local inside = self.inside
    local sx = (a.subx or 0) + a.rvx
    local sy = (a.suby or 0) + a.rvy
    local mx = (sx >= 0) and math.floor(sx / 16) or -math.floor(-sx / 16)
    local my = (sy >= 0) and math.floor(sy / 16) or -math.floor(-sy / 16)
    a.subx, a.suby = sx - mx * 16, sy - my * 16
    if mx ~= 0 then
      if walkable(inside, a, a.x + mx, a.y) then a.x = a.x + mx else a.rvx, a.subx = 0, 0 end
    end
    if my ~= 0 then
      if walkable(inside, a, a.x, a.y + my) then a.y = a.y + my else a.rvy, a.suby = 0, 0 end
    end
  end
  if a.recoil == 0 then a.recoil = nil end
  return true
end

-- Sprite_ProjectSpeedTowardsLink (0x86E991): `vel` on the major axis, the
-- minor axis by the cartridge's integer stepping. Returns vx, vy pointing
-- from (sx, sy) to (tx, ty).
function A.project(sx, sy, tx, ty, vel)
  if vel == 0 then return 0, 0 end
  local dx, dy = tx - sx, ty - sy
  local r12, r13 = math.min(255, math.abs(dy)), math.min(255, math.abs(dx))
  local swapped = false
  if r13 < r12 then swapped = true; r12, r13 = r13, r12 end
  local xv, yv, t = vel, 0, 0
  for _ = 1, vel do
    t = t + r12
    if t >= r13 then t = t - r13; yv = yv + 1 end
  end
  if swapped then xv, yv = yv, xv end
  return (dx < 0) and -xv or xv, (dy < 0) and -yv or yv
end

function A:soldier(a, lk)
  local inside = self.inside
  local dx, dy = lk.x - a.x, lk.y - a.y
  if a.state == "patrol" then
    -- notices Link in front of him within 80 px (or close by)
    local v = DIRV[a.dir]
    local ahead = dx * v[1] + dy * v[2]
    local side = math.abs(dx * v[2]) + math.abs(dy * v[1])
    -- round 13: only on its own level (the cartridge's probes and touch test
    -- compare sprite_floor with link_is_on_lower_level)
    local same = (a.lower or false) == (inside.lower or false)
    if same and ((ahead > 0 and ahead < 80 and side < 24) or (math.abs(dx) < 24 and math.abs(dy) < 24)) then
      a.state = "chase"
    else
      if a.t % 2 == 0 then
        local nx, ny = a.x + v[1], a.y + v[2]
        if walkable(inside, a, nx, ny) then a.x, a.y = nx, ny else a.wait = 0 end
      end
      a.wait = a.wait - 1
      if a.wait <= 0 then
        a.dir = ({ [0] = 2, 3, 1, 0 })[a.dir]
        a.wait = 64
      end
    end
  elseif a.state == "chase" then
    local sx = dx > 1 and 1 or (dx < -1 and -1 or 0)
    local sy = dy > 1 and 1 or (dy < -1 and -1 or 0)
    if math.abs(dx) > math.abs(dy) then a.dir = sx < 0 and 2 or 3 else a.dir = sy < 0 and 0 or 1 end
    if walkable(inside, a, a.x + sx, a.y) then a.x = a.x + sx end
    if walkable(inside, a, a.x, a.y + sy) then a.y = a.y + sy end
  end
end

-- Round 10: the actors a secret holds (zelda3 Sprite_SpawnSecret 0x868264
-- and their AIs). Velocities in 1/16 px (Sprite_MoveXY, 8.8 fixed point).
local function moveXY(self, a, walls)
  a.subx = (a.subx or 0) + (a.vx or 0)
  a.suby = (a.suby or 0) + (a.vy or 0)
  local mx = (a.subx >= 0) and math.floor(a.subx / 16) or -math.floor(-a.subx / 16)
  local my = (a.suby >= 0) and math.floor(a.suby / 16) or -math.floor(-a.suby / 16)
  a.subx, a.suby = a.subx - mx * 16, a.suby - my * 16
  local hit = false
  if mx ~= 0 then
    if not walls or walkable(self.inside, a, a.x + mx, a.y) then a.x = a.x + mx else hit = true end
  end
  if my ~= 0 then
    if not walls or walkable(self.inside, a, a.x, a.y + my) then a.y = a.y + my else hit = true end
  end
  return hit
end
A.moveXY = moveXY

-- a simple frame-seeded random byte (OURS: the cartridge's RNG is Drops.rng)
local function rnd(self, a, k)
  return (self.frame * 73 + (a.seed or 0) * 151 + (k or 0) * 37) % 256
end

-- Bee_Main (0x9EDD45): 16 px up in the air; every k + A frames it heads for
-- Link's position plus (rng & 3) * 5 at speed 20; A starts at 32 (the
-- secret's sprite_A) and drops by 8 every 256 frames down to 16; it does
-- not hurt Link for its first 32 frames (sprite_delay_aux4); no walls.
function A:bee(a, lk)
  a.z = 16
  if (a.aux4 or 0) > 0 then a.aux4 = a.aux4 - 1 end
  moveXY(self, a, false)
  a.gfx = math.floor(((a.seed or 0) + self.frame) / 2) % 2
  if self.frame % 256 == 0 and (a.A or 32) ~= 16 then a.A = (a.A or 32) - 8 end
  a.delay = (a.delay or 0) - 1
  if a.delay <= 0 then
    local tx = lk.x + (rnd(self, a, 1) % 4) * 5
    local ty = lk.y + (rnd(self, a, 2) % 4) * 5
    a.vx, a.vy = A.project(a.x, a.y, tx, ty, 20)
    a.flip = a.vx >= 0
    a.delay = (a.seed or 0) % 16 + (a.A or 32)
  end
end

-- Sprite_Hoarder_Frantic (0x86A91D): runs at 16 away from Link (re-aimed
-- every 32 frames), turns diagonally at walls, gone after 192 counts of
-- every other frame.
function A:hoarder(a, lk)
  a.sub2 = (a.sub2 or 0) + 1
  local j = math.floor(a.sub2 / 2) % 4
  a.gfx = (j % 2)
  if a.wall then
    a.aux4 = 16
    local r = rnd(self, a, 3) % 4
    a.vx, a.vy = (r % 2 == 0) and -16 or 16, (r < 2) and -16 or 16
    a.wall = false
  else
    a.wall = moveXY(self, a, true)
  end
  if (a.aux4 or 0) > 0 then a.aux4 = a.aux4 - 1 end
  if (a.aux4 or 0) == 0 and (self.frame + (a.seed or 0)) % 32 == 0 then
    local px, py = A.project(a.x, a.y, lk.x, lk.y, 16)
    a.vx, a.vy = -px, -py
  end
  if self.frame % 2 == 0 then
    a.G = (a.G or 0) + 1
    if a.G >= 192 then a.dead = true end
  end
end

-- The cucco (Sprite_0B_Cucco): calm, then a hop in a random direction;
-- hit with the sword it flees from Link (Cucco_Flee: re-aimed every 32
-- frames at 16). Round 11: the calm state is the GBA's Cucco_Calm
-- (0x080EA700): when its timer is out, j = rng & 15 picks the hop's
-- velocities from the cartridge's tables (RomMap.cuccoVel) and the timer
-- becomes (rng & 0x1F) + 16, both numbers from the cartridge's random
-- routine (0x080CEFE0, Drops.rng); Chicken_Hopping moves it on every other
-- frame (by slot parity), z velocity 10 falling 2 a frame, a wall ends the
-- hop, and on landing with the timer out it waits 32 frames. OURS: the
-- slot number is the actor's seed; no avenging flock.
function A:cucco(a, lk)
  local game = self.game
  local tab = game.data and game.data.t and game.data.t.items and game.data.t.items.cuccoVel
  if tab and a.state ~= "flee" then
    if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
    if a.state ~= "hop" then
      if (a.delay or 0) == 0 then
        local D = require("src.zelda.alttp.Drops")
        local st = game:dropRng()
        local j = band(D.rng(st), 15)
        a.vx, a.vy = tab[j + 1], tab[17 + j]
        a.delay = band(D.rng(st), 0x1F) + 0x10
        a.state, a.zv = "hop", a.zv or 10
        a.rngHops = (a.rngHops or 0) + 1
      end
    else
      if band(bit.bxor(a.seed or 0, self.frame), 1) ~= 0 and moveXY(self, a, true) then a.state = "calm" end
      a.zz = (a.zz or 0) + (a.zv or 10)
      a.zv = (a.zv or 10) - 2
      if a.zz < 0 then
        a.zz = 0
        if (a.delay or 0) == 0 then a.delay, a.state = 32, "calm" end
        a.zv = 10
      end
      a.z = math.floor(a.zz / 16)
    end
    if (a.vx or 0) ~= 0 then a.flip = a.vx > 0 end
    return
  end
  if a.state == "flee" then
    moveXY(self, a, true)
    if (self.frame + (a.seed or 0)) % 32 == 0 then
      local px, py = A.project(a.x, a.y, lk.x, lk.y, 16)
      a.vx, a.vy = -px, -py
    end
    a.fleeT = (a.fleeT or 0) + 1
    if a.fleeT > 240 then a.state, a.fleeT = "calm", 0 end
    return
  end
  a.delay = (a.delay or 0) - 1
  if a.state == "hop" then
    if self.frame % 2 == 1 then moveXY(self, a, true) end
    a.zv = (a.zv or 10) - 2
    a.zz = (a.zz or 0) + a.zv
    if a.zz < 0 then
      a.zz, a.zv = 0, 10
      if a.delay <= 0 then a.state, a.delay = "calm", 32 end
    end
    a.z = math.floor(a.zz / 16)
  elseif a.delay <= 0 then
    local r = rnd(self, a, 4)
    a.vx, a.vy = (r % 16) - 8, (math.floor(r / 16) % 16) - 8
    a.delay = (rnd(self, a, 5) % 32) + 16
    a.state = "hop"
  end
  if (a.vx or 0) ~= 0 then a.flip = a.vx > 0 end
end

-- Round 10: the throne room's shelf (Sprite_EE_MovableMantle): while Link
-- touches it on its layer walking right (link_actual_vel_x >= 24), with
-- Zelda following and the lamp, sprite_subtype2 counts frames and G every
-- other one; from G = 8 it moves right at x velocity 2 (1/16 px), and stops
-- at G = 0x90 (about 34 px). OURS: "touching" is Link's box against the
-- shelf's cartridge hit box grown 4 px left (it is solid here, the SNES
-- repels Link).
function A:mantle(a, lk)
  local game = self.game
  local items = game.progress.items or {}
  local lamp = false
  for _, id in ipairs(items) do if id == 0x12 then lamp = true end end
  if game.progress.zelda ~= 1 or not lamp or not game.pushRight then return end
  -- (OURS: no layer test -- the dais stairs put Link on our lower layer
  -- while the shelf's list entry is on the upper one)
  local hx, hy, hw, hh = A.hitbox(combat(game), a)
  if not overlap(lk.x + 3, lk.y + 8, 12, 12, hx - 4, hy, hw + 4, hh) then return end
  a.G = a.G or 0
  if a.G >= 0x90 then return end
  game.progress.startPoint = 4   -- r12: Sprite_EE_MovableMantle, the throne room
  a.sub2 = (a.sub2 or 0) + 1
  if a.sub2 % 2 == 0 then a.G = a.G + 1 end
  a.sliding = true
  if a.G >= 8 then
    a.xs = (a.xs or 0) + 2
    if a.xs >= 16 then a.x, a.xs = a.x + 1, a.xs - 16 end
  end
  if a.G >= 0x90 then a.sliding = nil; self.inside.mem.mantleMoved = true end
end

-- spawn what a secret holds at (x, y) (Sprite_SpawnSecret's per-type setup)
function A:spawnSecret(t, x, y, lower)
  local cb = combat(self.game)
  self.seeds = (self.seeds or 0) + 1
  local a = { type = t, x = x, y = y, lower = lower or false, t = 0, index = -1, dir = 1,
              hp = cb and cb.health[t + 1] or 1, seed = self.seeds * 7, secret = true, state = "idle" }
  if SOLDIER[t] then
    -- 0x41/0x42: sprite_hit_timer 160 (flashing), straight into the chase
    a.state, a.inv, a.wait = "chase", 32, 64
  elseif t == 0x79 then
    a.state, a.A, a.aux4, a.delay = "wander", 32, 32, 0
  elseif t == 0x3E then
    a.state, a.aux2, a.vx, a.vy = "wander", 128, 0, 0
  elseif t == 0x0B then
    a.state, a.delay = "calm", 16
  end
  self.list[#self.list + 1] = a
  return a
end

function A:critter(a)
  a.wait = a.wait - 1
  if a.wait <= 0 then
    a.dir = (a.dir + 1 + (self.frame + a.index * 7) % 3) % 4
    a.wait = 24 + (self.frame * 13 + a.index * 5) % 40
  end
  local v = DIRV[a.dir]
  local nx, ny = a.x + v[1], a.y + v[2]
  if walkable(self.inside, a, nx, ny) then a.x, a.y = nx, ny else a.wait = 0 end
end

-- Link's sword hit box this frame (cartridge kPlayer_SetupActionHitBox),
-- or nil on steps with no box (Tab4)
local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end
function A.swordBox(cb, lk, step, oamOffs, yt, rt)
  if (cb.swordTab4[step + 1] or 0) ~= 0 then return nil end
  local t = lk.facing * 8 + step + 1
  -- player_oam_x/y_offset of this swing step (CalculateSwordHitBox)
  -- r19: of the pose LinkOam drew (yt, rt): the swing is row 0x27 at the
  -- step; the held sword row 2, its jerks row 3 (Game:linkPose)
  local ox, oy = 0, 0
  if oamOffs and cb.swordOamY then
    local i = (oamOffs[math.floor(lk.facing / 2) * 40 + (yt or 39) + 1] or 0) + (rt or step)
    ox, oy = cb.swordOamX[i + 1] or 0, cb.swordOamY[i + 1] or 0
  end
  local x = lk.x + wrap8((cb.swordX[t + 1] or 0) + ox)
  local y = lk.y + wrap8((cb.swordY[t + 1] or 0) + oy)
  return x, y, cb.swordW[t + 1] or 0, cb.swordH[t + 1] or 0
end

-- the sword hits actors overlapping its box
-- round 9: a thrown bush / pot / rock (zelda3 ThrownSprite_CheckDamageToSingleSprite):
-- the object's box (x, y - z + 8, 15 x 8), damage class 1 for an outdoor
-- bush else 3 (Ancilla_CheckDamageToSprite_preset), recoil = its speed * 2.
-- Returns the number of actors hit.
function A:thrownHit(x, y, w, h, cls, vx, vy, lower)
  return self:swordHit(x, y, w, h, { cls = cls, rvx = vx * 32, rvy = vy * 32, lower = lower })
end

function A:swordHit(x, y, w, h, how)
  local game = self.game
  local cb = combat(game)
  local hit = 0
  for _, a in ipairs(self.list) do
    if a.type == 0x0B and not a.dead and not (how and how.lower ~= nil and (a.lower or false) ~= how.lower) then
      -- round 10: the cucco takes no damage; a hit sends it fleeing (Cucco_Flee)
      local hx, hy, hw, hh = A.hitbox(combat(game), a)
      if overlap(x, y, w, h, hx, hy, hw, hh) and not (a.inv and a.inv > 0) then
        a.state, a.inv, a.hits = "flee", 16, (a.hits or 0) + 1
      end
    end
    -- (round 10: a fresh bee ignores the sword while its sprite_delay_aux4 runs)
    -- r20: the sword, the dash and thrown things wait for the hit timer to
    -- run out (sprite_hit_timer & 0x80 after a sword hit); arrows do not
    -- (Ancilla_CheckSpriteCollision has no hit-timer test)
    local timerBusy = a.inv and a.inv > 0 and not (how and how.arrow)
    if how and how.sword and a.inv and a.inv > 0 and not a.invSword then timerBusy = false end
    if not a.dead and fights(a.type) and not timerBusy and not (a.type == 0x79 and (a.aux4 or 0) > 0) and not a.untouchable
       and not (how and how.lower ~= nil and (a.lower or false) ~= how.lower)
       and not (how and how.only and how.only ~= a) then
      local hx, hy, hw, hh = A.hitbox(cb, a)
      -- round 14: Guard_ParrySwordAttacks -- Link's sword on the guard's
      -- weapon is parried before it can reach the body
      if how and how.sword and require("src.zelda.alttp.Guard").parry(self, a, x, y, w, h) then
        hit = hit
      elseif a.palace and (a.z or 0) >= 0 and A.overlapCart(x, y, w, h, hx, hy - (a.z or 0), hw, hh) and Palace.swordImmune(a, how) then
        -- round 17: the cartridge tinks (deflection bit 4 / flags3 0x40)
        -- r20: no hit timer; the sword's tink pushes Link back
        -- (Sprite_CheckDamageFromLink "getting_out": recoil 4, 16 frames)
        self.tinks = (self.tinks or 0) + 1
        if how and how.sword then self:tinkLink(a) end
      elseif (a.z or 0) >= 0 and A.overlapCart(x, y, w, h, hx, hy - (a.z or 0), hw, hh)
             and not (how and how.dmg and ((how.dmg(a.type) or 0) == 0 or how.dmg(a.type) >= 249))
             and not (how and how.sword and self:swordDamage(a, how) == 0) then
        -- round 18: arrows and bombs use the cartridge's per-type damage
        -- subclass (Items.damage; 0 and the special codes 249+ do nothing)
        -- r20: the sword too (Sprite_CalculateSwordDamage: the class by
        -- sword level, spin, held; A:swordDamage). The damage waits in the
        -- hit timer (0x9D for the sword, 0x20 for arrows and bombs) and is
        -- taken at 24 (A:takeDamage); the sword pokes set
        -- set_when_damaging_enemies = 16 (the held sword's jerks)
        local dmg
        if how and how.sword then dmg = self:swordDamage(a, how)
        else dmg = (how and how.dmg and how.dmg(a.type)) or cb.enemyDamage[(how and how.cls or 1) * 8 + 1 + 1] or 2 end
        a.pend = math.max(a.pend or 0, dmg)
        if how and how.sword then
          a.inv, a.invSword = 0x1D, true
          game.swde = 16
        else
          a.inv = 0x20
        end
        a.state = SOLDIER[a.type] and "chase" or a.state
        -- round 10: Sprite_AttemptZapDamage: recoil away from Link at 0x50
        -- (B held < 9 frames) else 0x40, in 1/16 px; sprite_F = 15
        local lk = game.link
        local px, py = A.project(a.x, a.y, lk.x, lk.y, (how and how.vel) or 0x50)
        a.rvx, a.rvy = -px, -py
        if how and how.rvx then a.rvx, a.rvy = how.rvx, how.rvy end
        a.subx, a.suby = 0, 0
        a.recoil = 15
        hit = hit + 1
      end
    end
  end
  return hit
end

-- r20: Sprite_CalculateSwordDamage (0x86ED3F): the damage class is
-- kSprite_Func14_Damage[sword level - 1 | 4 spinning | 8 held out] (the
-- dash: no flags), then kEnemyDamages[class * 8 | enemy_damage_data[type *
-- 16 | class]]
function A:swordDamage(a, how)
  local game = self.game
  local cb = combat(game)
  local i = ((game.progress and game.progress.swordLevel) or 1) - 1
  if how.run then i = i
  elseif how.spin then i = i + 4
  elseif how.held or (how.bFrames or 0) >= 9 then i = i + 8 end
  local cls = (cb.swordClass and cb.swordClass[i + 1]) or 1
  return require("src.zelda.alttp.Items").damage(game, cls, a.type)
end

-- r20: Sprite_MiniMoldorm_Recoil at hit timer 24: the health drops by the
-- damage given; at 0 the sprite dies (its key drops)
function A:takeDamage(a)
  local dmg = a.pend or 0
  a.pend = nil
  if a.dead then return end
  a.hp = a.hp - dmg
  if a.hp <= 0 then
    a.dead = true
    local function death()
      self:died(a)
      if a.drop then
        self.inside.mem.taken[a.index] = true
        self.list[#self.list + 1] = { type = A.KEY, x = a.x, y = a.y, lower = a.lower,
                                      big = a.drop == 2, t = 0, index = -1 }
      end
    end
    -- r21: the death puff (Effects.lua: SpriteModule_Die, 31 frames after a
    -- sword hit, 15 else); the prize / key drop when it ends. The Armos
    -- Knights keep their own death (Palace.lua)
    local p = (a.type ~= 0x53 and a.type ~= 0x54) and require("src.zelda.alttp.Effects").death(self.game, a, a.invSword) or nil
    if p then p.prize = death else death() end
  end
end

-- r20: the sword on a sprite it cannot hurt (Sprite_CheckDamageFromLink's
-- "getting_out"): while set_when_damaging_enemies is 0, Link recoils at
-- speed 4 and is held 16 frames (Sprite_ApplyRecoilToLink(k, 4))
function A:tinkLink(a)
  local game = self.game
  if (game.swde or 0) ~= 0 then return end
  game.swde = 16
  local lk = game.link
  local vx, vy = A.project(a.x, a.y, lk.x, lk.y + 8, 4)
  if not game.recoil then game.recoil = { vx = vx, vy = vy, t = 16, sx = 0, sy = 0, tink = true, vz = 2 } end
end

-- round 13: Sprite_DoTheDeath (0x86F923): the kill memory, and the prize
-- an enemy without a key leaves (sprite_flags5 & 15 = its prize pack; pack
-- p - 1 drops when rng & kPrizeMasks[p - 1] == 0, kPrizeItems[pack * 8 +
-- the pack's counter], kPrizeZ: z velocity & 0xF0, x + (& 15))
function A:died(a)
  local game = self.game
  local cb = combat(game)
  if a.palace then Palace.died(self, a) end
  local km = self.kills
  if km and a.index and a.index > 0 and self.room then
    km.dead[self.room] = km.dead[self.room] or {}
    km.dead[self.room][a.index] = true
  end
  if a.drop or not cb or not cb.flags5 then return end
  local prize = band(a.flags5 or cb.flags5[a.type + 1] or 0, 0x0F)   -- r25: a.flags5 (SpritePrep_Raven)
  if prize == 0 or not game.spawnDrop then return end
  prize = prize - 1
  local tabs = game.data.t and game.data.t.drops
  if not tabs or not tabs.prizeItems then return end
  local Drops = require("src.zelda.alttp.Drops")
  if band(Drops.rng(game:dropRng()), cb.prizeMasks[prize + 1] or 1) ~= 0 then return end
  game.prizeCtr = game.prizeCtr or {}
  local c = game.prizeCtr[prize] or 0
  game.prizeCtr[prize] = band(c + 1, 7)
  local item = tabs.prizeItems[prize * 8 + c + 1]
  if not item then return end
  local pz = (tabs.prizeZ and tabs.prizeZ[item - 0xD8 + 1]) or 0
  game.prizes = (game.prizes or 0) + 1
  game:spawnDrop(item, a.x + band(pz, 0x0F), a.y, { zvel = band(pz, 0xF0), flag = 0 })
end

-- the actor Link talks to / acts on: a point in front of him
function A:facing(px, py)
  local lv = self.inside and (self.inside.lower or false)
  for _, a in ipairs(self.list) do
    -- round 10: only what is on Link's level (a lower-floor guard under the
    -- throne room's shelf hid the shelf from A)
    if not a.dead and not (fights(a.type) and (a.lower or false) ~= lv) then
      local w = a.type == A.MANTLE and 32 or 16
      if px >= a.x - 2 and px < a.x + w + 2 and py >= a.y - 2 and py < a.y + 18 then return a end
    end
  end
end

-- Zelda following Link (SNES tagalong: she replays Link's steps 20 frames
-- behind)
function A:updateFollower()
  local game = self.game
  if game.progress.zelda ~= 1 then self.follower = nil return end
  local lk = game.link
  self.trail = self.trail or {}
  local tr = self.trail
  local last = tr[#tr]
  if not last or last[1] ~= lk.x or last[2] ~= lk.y then
    tr[#tr + 1] = { lk.x, lk.y, lk.facing }
    if #tr > 20 then table.remove(tr, 1) end
  end
  local p = tr[1]
  self.follower = { x = p[1], y = p[2], facing = p[3], moving = #tr >= 20 and last ~= nil and (last[1] ~= lk.x or last[2] ~= lk.y) }
end

return A
