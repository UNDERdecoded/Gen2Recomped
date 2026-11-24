-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 34: the music for the remaining events, and more sound events.
--
-- MUSIC IDS (the GBA's own, written to RAM 0x03002230 + 0xA3C; Audio.lua
-- plays song = table 0x198C50 [id]). Every id below is read at import from
-- the `movs` at its writer (M.MUSIC); the writers were matched to the SNES
-- routines (zelda3 names) by their shape -- the same tests, tables and calls:
--   0x01 title          0x0812E47C (the title module, table 0x0814CA40)
--   0x03 rain / curfew  0x080F3882 (Uncle_DeclareCurfew, after message 13)
--   0x05 palace         0x0806E3A8 (Dungeon_SetBossMusicUnorthodox, room 0x17)
--   0x06 Zelda's rescue 0x080F3EB0 (Zelda's cell: message, speeds 0, music)
--   0x09 castle         0x080F4336 (Zelda becomes the follower) / 0x0806D8CC
--   0x0A sanctuary      0x0806D8A8 (Dungeon_PlayMusicIfDefeated, room 0x12)
--   0x0C bunny          0x080736C0 (MirrorWarp_Finalize: no moon pearl)
--   0x0D boss           0x0806D2A0 (the boss-room list 0x14CB74, not clear),
--                       0x0806E3CC (room 7), 0x08070C74 (a boss's start)
--   0x0E Dark World     0x08073670
--   0x0F dark mountain  0x080736B6 (Skull Woods 0x40, Dark Death Mountain
--                       0x43 / 0x45 / 0x47 after a warp)
--   0x11 crystal        0x08118844 (the crystal's ancilla, no song playing)
--   0x12 Agahnim        0x0806E3B6 (room 0x10) / 0x0806EB00 (room 0x30)
--   0x15 minigame       0x080F939E (unused here: the entrances set it)
--   0x17 fanfare        0x080ACE44 (receipt of 0x20 / 0x37-0x39: crystal,
--                       pendants) and 0x080CE856 (Ganon's death, type > 0xD5)
--   0x18 mirror warp    0x08073594 (the warp's first step)
--   0x1A file select    0x080B1020 (GameOver_Finalize_GAMEOVR)
--   0x1B Ganon reveal   0x080DA928 (Agahnim 2: Sprite_SpawnPhantomGanon)
--   0x1C Ganon's room   0x0810A440 (SpritePrep_Ganon)
--   0x1D Ganon fight    0x0810A620 (Sprite_D6_Ganon state 0, delay 32)
--   0x1E Triforce room  0x0806B58C (Module19_TriforceRoom step 4)
--   0x1F ending         0x0806B74C (Module19 step 11)
--   0x20 staff roll     0x080B8A48 (EndSequence_32; 0x21 when the end
--                       sequence index is past 0x27 -- a second credits
--                       table at 0x08170ADC, not used by the port)
-- Room rules (the same order as the cartridge): Dungeon_PlayMusicIfDefeated
-- after a doorway / a fall (room 0x12 -> 0x0A, room 2 -> 9, a boss room of
-- the list with a live sprite on screen -> 0x0D, room 0x8A -> fade, 0xEC
-- none); after stairs / a fall also Dungeon_SetBossMusicUnorthodox (room
-- 0x10 -> 0x12, room 7 -> 0x0D, room 0x17 -> 5 unless 5 plays) and after
-- straight stairs Module07_11_19 (room 0x30 -> 0x12, room 0x40 -> 9).
--
-- SOUNDS (ids into the table 0x198C94, read from their call sites):
--   door open 0x37 / shutter close 0x38   0x080810AC (OperateShutterDoors;
--                                         key doors 0x08085D08 use 0x37 too)
--   arrow 0x1B                            0x080A1D1C (LinkItem_Bow, after
--                                         AncillaAdd_Arrow; 0x40 with none)
--   enemy killed 0x54                     0x080C2160 (the damage routine:
--                                         health <= 0, not type 0x1B)
--   low health 0x50                       0x080A7228 (Hud_RefillLogic:
--                                         health < table 0x16B645 [max >> 3],
--                                         timer 0x20 -> a beep every 32 frames)
--   rupee count 0x73                      the same (every 8th counted frame)
--   stairs 0x34 / 0x32                    0x0806DDF4 (Module07_08_00_InitStairs:
--                                         0x32 with which_staircase & 8)
--   menu cursor 0x45                      0x080AA4F8 (r33's menuMove)
--
-- OURS: fades act on the stream's volume (Audio.lua); the transition kind
-- (doorway / stairs / fall) is read from the port's own room change; the
-- port counts rupees at once, so the count sound runs on a counter of its
-- own; spiral stairs 0x5E sound "up" and 0x5F "down" (the GBA picks by
-- which_staircase_index, not traced into the port's stairs); the game-over
-- screen's 0x1A is not played (the port's game over has no continue menu:
-- the music fades, the room's own song comes back with Link); the Kakariko
-- chase song (0x16), the Agahnim warp's 0x18 (the port leaves the room at
-- once) and the fairy queen's 0x14 are not wired.

local bit = require("bit")
local band = bit.band

local M = { NAME = "mus34" }

-- name -> the `movs rN, #imm` address
M.MUSIC = {
  title = 0x0812E4A6, curfew = 0x080F3886, palace = 0x0806E3D2, rescue = 0x080F3EEA,
  zeldaFollows = 0x080F433A, castle = 0x0806D8D0, sanctuary = 0x0806D8AC,
  bunny = 0x080736C0, boss = 0x0806D30A, bossFall = 0x0806E3CC, darkWorld = 0x08073670,
  darkMountain = 0x080736B6, crystal = 0x0811887C, agahnim = 0x0806E3BA,
  agahnimStairs = 0x0806EB04, castleStairs = 0x0806EB28, minigame = 0x080F93A2,
  fanfare = 0x080ACE6E, ganonWin = 0x080CE85A, warp = 0x080735CE, fileSelect = 0x080B109A,
  ganonReveal = 0x080DA95C, ganonRoom = 0x0810A472, ganonFight = 0x0810A646,
  triforce = 0x0806B630, ending = 0x0806B764, staff = 0x080B8C58, staff2 = 0x080B8BBA,
  lightWorld = 0x0807367C, town = 0x0807368C,
  -- r35: the overworld song rule 0x080732FC (light / dark world, Skull Woods
  -- / Dark Death Mountain, the Lost Woods), the Master Sword's pedestal, the
  -- fairy queen (for Audio.ID / Audio.SNES, bound at load)
  owLW = 0x0807332C, owDW = 0x08073332, owSkull = 0x08073344, woods = 0x08073390,
  sword = 0x080D46B8, fairy = 0x080DFA34,
}
-- r35: no expected ids here (they are the cartridge's); the check is the
-- shape: every site is a movs of a song number 1..0x22, and the sites the
-- cartridge shares a song between agree (the routines are each other's copies)
M.SAME = { { "castle", "zeldaFollows", "castleStairs" }, { "boss", "bossFall" },
           { "agahnim", "agahnimStairs" }, { "fanfare", "ganonWin" } }
M.SOUND = {
  doorOpen = 0x08081158, shutterClose = 0x080811B4, arrow = 0x080A1E4A, noArrow = 0x080A1EB0,
  enemyDie = 0x080C2320, lowHealth = 0x080A739A, rupeeCount = 0x080A72EC,
  stairsUp = 0x0806DE06, stairsDown = 0x0806DE1A, keyDoor = 0x08085DE0,
}
M.CONST = { fadeFrames = 0x08068594, lowVol = 0x08129FC8, beepTimer = 0x080A7396 }
M.OFF = { bossRooms = 0x14CB74, bossCount = 17, lowHealth = 0x16B645, lowHealthN = 21 }

local function movsImm(rom, at)
  local h = rom:u16(at - 0x08000000)
  if bit.rshift(h, 11) ~= 4 then return nil end   -- 00100 nnn iiiiiiii
  return band(h, 0xFF)
end

function M.extract(rom, R, check)
  local t = { music = {}, sfx = {} }
  for name, at in pairs(M.MUSIC) do
    local v = movsImm(rom, at)
    check(v ~= nil and v >= 1 and v <= 0x22, "music site %s at %08X: %s", name, at, tostring(v))
    t.music[name] = v
  end
  for name, at in pairs(M.SOUND) do
    local v = movsImm(rom, at)
    check(v ~= nil, "sound site %s at %08X is not movs", name, at)
    t.sfx[name] = v
  end
  for name, at in pairs(M.CONST) do
    local v = movsImm(rom, at)
    check(v ~= nil, "constant %s at %08X is not movs", name, at)
    t[name] = v
  end
  for _, g in ipairs(M.SAME) do
    for i = 2, #g do check(t.music[g[i]] == t.music[g[1]], "music sites %s / %s differ", g[1], g[i]) end
  end
  t.bossRooms = {}
  for i = 0, M.OFF.bossCount - 1 do t.bossRooms[i + 1] = rom:u16(M.OFF.bossRooms + i * 2) end
  t.lowHealth = rom:bytesU8(M.OFF.lowHealth, M.OFF.lowHealthN)
  check(t.bossRooms[1] == 0xC8 and t.bossRooms[17] == 0x8A and t.lowHealth[1] == 9
        and t.fadeFrames == 0x28 and t.beepTimer == 0x20, "music 34 tables")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.mus34 end
M.T = T

local function Snd() return require("src.zelda.alttp.AlttpSound") end
local function Sfx() return require("src.zelda.alttp.Sfx") end

function M.music(game, name)
  local t = T(game)
  local id = t and t.music[name]
  if id and game.music and game.music.playId then game.music:playId(id) end
  game.mus34Log = game.mus34Log or {}
  if #game.mus34Log >= 64 then table.remove(game.mus34Log, 1) end
  game.mus34Log[#game.mus34Log + 1] = name
  return id
end

function M.sound(game, name)
  local t = T(game)
  local id = t and t.sfx[name]
  if not id then return nil end
  return Sfx().start(game, id, name)
end

local function current(game) return game.music and game.music.current end

-- Sprite_CheckIfScreenIsClear on the loaded room
local function screenClear(game)
  local acts = game.actors
  if not (acts and acts.list and acts.inside) then return true end
  local ok, r = pcall(function() return require("src.zelda.alttp.DesertPalace").screenClear(acts) end)
  if not ok then
    for _, b in ipairs(acts.list) do if not b.dead then return false end end
    return true
  end
  return r
end

-- Dungeon_PlayMusicIfDefeated (0x0806D844 / 0x0806D2A0)
function M.ifDefeated(game, room)
  local t = T(game)
  if not t then return end
  if room == 0x12 then return M.music(game, "sanctuary") end
  if room == 2 then return M.music(game, "castle") end
  for i = #t.bossRooms, 1, -1 do
    if t.bossRooms[i] == room then
      if room == 0x8A then game.music:playId(0xFFF1) return end
      if room == 0xEC then return end
      if not screenClear(game) then return M.music(game, "boss") end
      return
    end
  end
end

-- Dungeon_SetBossMusicUnorthodox (0x0806E3A8)
function M.unorthodox(game, room)
  if room == 0x10 then return M.music(game, "agahnim") end
  local t = T(game)
  if room ~= 7 and room ~= 0x17 then return end
  if room == 0x17 and current(game) == (t and t.music.palace) then return end
  -- kept while a song plays (not faded) and pendant bit 0 is Link's
  local faded = game.music.fade ~= nil or game.music.current == nil
  if not faded and band(game.progress.pendants or 0, 1) ~= 0 then return end
  return M.music(game, room == 7 and "bossFall" or "palace")
end

-- Module07_11_19_SetSongAndFilter (0x0806EAD4): straight stairs
function M.straightStairs(game, room)
  if room == 0x30 then return M.music(game, "agahnimStairs") end
  if room == 0x40 then return M.music(game, "castleStairs") end
end

-- MirrorWarp_FinalizeAndLoadDestination (0x08073644)
function M.afterWarp(game)
  local lk = game.link
  local screen = game.area and game.area.parent or 0
  local dw = lk.world == "dw"
  local pearl = not require("src.zelda.alttp.DarkWorld").isBunny(game)
  local name
  if dw and not pearl then name = "bunny"
  elseif screen > 0x3F or dw then name = "darkWorld"
  else
    name = "lightWorld"
    if screen == 0x18 and Snd().progressIndicator(game) <= 2 then name = "town" end
  end
  if screen == 0x40 or screen == 0x43 or screen == 0x45 or screen == 0x47 then
    name = pearl and "darkMountain" or "bunny"
  end
  return M.music(game, name)
end

-- the room rules after a change inside (kind: "door", "stairs", "straight", "other")
local function roomChanged(game, room, kind)
  if kind == "stairs" or kind == "straight" or kind == "other" then M.unorthodox(game, room) end
  if kind == "straight" then M.straightStairs(game, room) end
  if kind ~= "stairs" and kind ~= "straight" then M.ifDefeated(game, room) end
end
M.roomChanged = roomChanged

-- Hud_RefillLogic's low-health beep and rupee count (once a frame)
local function hudFrame(game)
  local t = T(game)
  local st = game.stats
  if not (t and st) then return end
  -- the rupee count (rupee_sfx_sound_delay)
  local r = st.rupees or 0
  game.mus34Rupees = game.mus34Rupees or r
  if game.mus34Rupees ~= r then
    game.mus34Rupees = game.mus34Rupees + (game.mus34Rupees < r and 1 or -1)
    local d = game.mus34RupeeDelay or 0
    if band(d, 7) == 0 then M.sound(game, "rupeeCount") end
    game.mus34RupeeDelay = d + 1
  else
    game.mus34RupeeDelay = 0
  end
  -- link_lowlife_countdown_timer_beep
  local cap = st.healthMax or 24
  local lim = t.lowHealth[math.min(#t.lowHealth, math.floor(cap / 8) + 1)] or 9
  if (st.health or 0) > 0 and st.health < lim then
    local tm = game.mus34Beep or 0
    if tm == 0 then
      tm = t.beepTimer or 0x20
      M.sound(game, "lowHealth")
      game.lowHealthBeeps = (game.lowHealthBeeps or 0) + 1
    end
    game.mus34Beep = tm - 1
  else
    game.mus34Beep = 0
  end
end
M.hudFrame = hudFrame

-- a sprite whose health reached 0 this frame (the damage routine's kill sound)
local function killsFrame(game)
  local acts = game.actors
  if not (acts and acts.list) then return end
  local seen = game.mus34Hp
  if not seen or game.mus34HpList ~= acts.list then
    seen = setmetatable({}, { __mode = "k" })
    game.mus34Hp, game.mus34HpList = seen, acts.list
  end
  for _, a in ipairs(acts.list) do
    local hp = a.hp
    if hp then
      local was = seen[a]
      if was and was > 0 and hp <= 0 and a.type ~= 0x1B then
        M.sound(game, "enemyDie")
        game.enemyKills34 = (game.enemyKills34 or 0) + 1
      end
      seen[a] = hp
    end
  end
end

-- the events seen once a frame (after the game's own update)
local function eventsFrame(game, s)
  local playing = game.state == "play" or game.state == "room"
  if game.state == "title" or game.state == "front" then
    if not s.title then s.title = true; M.music(game, "title") end
    return
  end
  s.title = nil
  -- the ending (Ending27): Module19 / Module1A steps
  local e = game.ending27
  if e then
    if e.phase ~= s.endPhase then
      s.endPhase = e.phase
      if e.phase == "fadeout" then game.music:playId(0xFFF1)
      elseif e.phase == "walkin" then M.music(game, "triforce")
      elseif e.phase == "brighten" then M.music(game, "staff") end
    end
    if e.phase == "approach" and not game.textBox and not s.endingSong then
      s.endingSong = true
      M.music(game, "ending")
    end
    return
  end
  s.endPhase, s.endingSong = nil, nil
  -- game over: the death fades the music; the room / area song after it
  if game.gameOver and not s.over then
    s.over = true
    game.music:playId(0xFFF1)
  elseif not game.gameOver and s.over then
    s.over = nil
    if game.music.current == nil or game.music.fade then
      game.music:stop()
      if game.state == "room" and game.interior then
        local m = Snd().roomMusic(game, game.interior.entranceId)
        if m then game.music:playId(m) end
      elseif game.area then
        game.music:playForScreen(game.area.parent, game.link.world)
      end
    end
  end
  -- the mirror warp: 0x18 at its start, the destination's song at its end
  if game.mirrorWarp and not s.warp then
    s.warp = true
    M.music(game, "warp")
  elseif not game.mirrorWarp and s.warp then
    s.warp = nil
    M.afterWarp(game)
  end
  -- Zelda follows (the follower's song)
  local z = game.progress and game.progress.zelda or 0
  if s.zelda ~= nil and s.zelda == 0 and z == 1 then M.music(game, "zeldaFollows") end
  s.zelda = z
  -- the crystal: the fanfare, then the crystal's song once nothing plays
  local c = game.crystal27
  if c then
    if not s.crystal then s.crystal = c; s.crystalSong = nil; M.music(game, "fanfare") end
    if c.phase ~= "held" and not s.crystalSong and game.music:idle() then
      s.crystalSong = true
      M.music(game, "crystal")
    end
  else
    s.crystal = nil
  end
  if game.phantomGanon and not s.phantom then s.phantom = true; M.music(game, "ganonReveal") end
  -- Ganon: his room's song, his fight, his death
  local acts = game.actors
  if acts and acts.list and game.state == "room" then
    for _, a in ipairs(acts.list) do
      if a.ganonBoss and not a.dead then
        if not a.mus34 then a.mus34 = 1; M.music(game, "ganonRoom") end
        if a.mus34 == 1 and (a.ai or 0) == 0 and a.delay == 32 then a.mus34 = 2; M.music(game, "ganonFight") end
        if a.endSet and a.mus34 ~= 3 then a.mus34 = 3; M.music(game, "ganonWin") end
      end
    end
  end
  -- the room rules after a change inside a building
  if game.state == "room" and game.interior then
    local room = game.interior.room
    if s.room ~= room then
      if s.room ~= nil and not s.entered then
        s.pending = { room = room, kind = game.mus34Kind or "other", t = 0 }
      end
      s.room, s.entered = room, nil
      game.mus34Kind = nil
    end
    local p = s.pending
    if p then
      p.t = p.t + 1
      if (acts and acts.room == p.room) or p.t >= 4 or p.kind == "stairs" or p.kind == "straight" then
        s.pending = nil
        roomChanged(game, p.room, p.kind)
      end
    end
  else
    s.room, s.pending = nil, nil
  end
  -- the item menu's cursor
  local mn = game.menu
  if mn and mn.cur then
    if s.menuCur ~= nil and mn.cur ~= s.menuCur and mn.state == 5 then Sfx().play(game, "menuMove") end
    s.menuCur = mn.cur
  else
    s.menuCur = nil
  end
  if playing and not game.textBox and not game.menu and not game.gameOver then
    hudFrame(game)
    killsFrame(game)
  end
  -- the bow: an arrow, or the "can't" sound with none left
  local shot = game.arrowsShot or 0
  if shot > (s.arrows or shot) then M.sound(game, "arrow") end
  if s.bow and not game.bowUse and shot == (s.arrows or shot) then M.sound(game, "noArrow") end
  s.arrows, s.bow = shot, game.bowUse ~= nil
end
M.eventsFrame = eventsFrame

function M.install(G)
  if G.mus34 then return end
  G.mus34 = true
  local update = G.update
  function G:update(dt)
    local r = update(self, dt)
    self.mus34s = self.mus34s or {}
    eventsFrame(self, self.mus34s)
    return r
  end
  -- an entrance is the entrance table's song (AlttpSound), not a room rule
  local enter = G.enterRoom
  function G:enterRoom(entrance)
    local r = enter(self, entrance)
    local s = self.mus34s or {}
    self.mus34s = s
    s.room, s.entered, s.pending = self.interior and self.interior.room, nil, nil
    return r
  end
  local scroll = G.startRoomScroll
  function G:startRoomScroll(dir, leavesRoom, stairRoom)
    local at = self.stairAt
    if stairRoom then
      self.mus34Kind = (at == 0x38 or at == 0x39) and "straight" or "stairs"
      M.sound(self, (at == 0x39 or at == 0x5F) and "stairsDown" or "stairsUp")
    elseif leavesRoom then
      self.mus34Kind = "door"
    end
    return scroll(self, dir, leavesRoom, stairRoom)
  end
  local show = G.showMessage
  function G:showMessage(n)
    local r = show(self, n)
    local Actors = require("src.zelda.alttp.Actors")
    if n == Actors.MSG_ZELDA then M.music(self, "rescue")
    elseif n == G.MSG_UNCLE_LEAVES then M.music(self, "curfew") end
    return r
  end
  -- the pendants' receipt (Palace.takePrize; the crystal is seen by its
  -- ancilla in eventsFrame)
  local P = require("src.zelda.alttp.Palace")
  if not P.mus34 then
    P.mus34 = true
    local take = P.takePrize
    P.takePrize = function(game, a, ...)
      if not game.crystal27 then M.music(game, "fanfare") end
      local r = take(game, a, ...)
      return r
    end
  end
  -- doors: OperateShutterDoors / the key doors (not while a room loads)
  local I = require("src.zelda.alttp.Interior")
  if not I.mus34 then
    I.mus34 = true
    local quiet = 0
    local load = I.loadRoom
    function I:loadRoom(...)
      quiet = quiet + 1
      local ok, r = pcall(load, self, ...)
      quiet = quiet - 1
      if not ok then error(r, 0) end
      return r
    end
    local entry = I.entryShutters
    if entry then
      function I:entryShutters(...)
        quiet = quiet + 1
        local ok, r = pcall(entry, self, ...)
        quiet = quiet - 1
        if not ok then error(r, 0) end
        return r
      end
    end
    local open, close = I.openLock, I.closeLock
    function I:openLock(lock)
      local was = lock.open
      local r = open(self, lock)
      local game = M.lastGame
      if quiet == 0 and not was and game and game.interior == self
         and (lock.kind == "shutter" or lock.kind == "key" or lock.kind == "bigkey") then
        M.sound(game, "doorOpen")
        game.doorSounds34 = (game.doorSounds34 or 0) + 1
      end
      return r
    end
    function I:closeLock(lock)
      local was = lock.open
      local r = close(self, lock)
      local game = M.lastGame
      if quiet == 0 and was and game and game.interior == self and lock.kind == "shutter" then
        M.sound(game, "shutterClose")
        game.doorSounds34 = (game.doorSounds34 or 0) + 1
      end
      return r
    end
  end
  local u2 = G.update
  function G:update(dt)
    M.lastGame = self
    return u2(self, dt)
  end
end

return M
