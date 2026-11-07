-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE ROD ITSELF IN PLATINUM AND HEARTGOLD/SOULSILVER: cast, wait, the "!",
-- and the A press that lands it.
--
-- Before this the Gen 4 roll went through the Game Boy's `castLine` -- ". . ."
-- then "Oh! It's a bite!" straight into battle -- so the timing game the DS
-- games are known for did not exist: nothing could get away and nothing could
-- be reeled in too early.
--
-- pokeplatinum src/overlay005/fishing.c (GoFish's state table), at the
-- field's 30 frames a second:
--
--   CastRod          34 frames; SEQ_SE_DP_FW104 on frame 10
--   SetFishWait      delay ((LCRNG % 4) + 1) * 30, hook window by rod
--                    (sRodTypeHookTimingWindow: Old 45, Good 30, Super 15)
--   WaitForFish      A before the delay runs out -> "Reeled it in too quickly..."
--   (bite)           the "!" over the player
--   CheckForReelIn   A inside the window -> landed; window out -> "The Pokemon
--                    got away..."
--   ReelFishIn       15 frames, then "Landed a Pokemon!", then the battle
--   SetNoFishWait    120 frames; A first -> too quickly; else "Not even a nibble..."
--
-- The roll (Gen4Fishing.roll) is made BEFORE the cast, as
-- WildEncounters_TryFishingEncounter / FieldSystem_PerformFishEncounterCheck
-- are: a miss is decided before the line is in the water.
--
-- HeartGold/SoulSilver (asm/overlay_01_021FC66C.s, Task_OverworldFish) is the
-- same machine with the same windows (ov01_02208D7C 45/30/15) and two
-- follower additions: the window grows by the walking Pokemon's mood
-- (ov01_021FCCB0, table ov01_02208D88), and a friendly follower may wear the
-- "!" instead of the player (ov01_021FCC2C, not while surfing).
--
-- Messages: Platinum bank 213 (common_strings) 54-57, HGSS bank 40 49-52.
-- Approximated: the rod pose's frame timing (the fishing sheet's four
-- textures per facing, cast forward, jerked on a bite, drawn back on landing).

local Gen4FishingTask = {}
Gen4FishingTask.__index = Gen4FishingTask

Gen4FishingTask.FRAME = 1 / 30
Gen4FishingTask.HOOK = { old = 45, good = 30, super = 15 }
-- ov01_02208D88: [mood band][rod]
Gen4FishingTask.HGSS_MOOD_BONUS = {
  { 0, 0, 0 }, { 9, 6, 3 }, { 15, 12, 6 }, { 21, 18, 9 }, { 30, 24, 12 },
}
local ROD_INDEX = { old = 1, good = 2, super = 3 }

-- fishing.bin: per facing, four textures (north, south, west, east)
Gen4FishingTask.POSE = {
  up = { 0, 8, 9, 10 }, down = { 11, 12, 13, 14 },
  left = { 15, 1, 2, 3 }, right = { 4, 5, 6, 7 },
}

-- Black / White's rod sheet (Gen5PlayerForms): four a facing, right mirrored
Gen4FishingTask.BW_POSE = {
  up = { 0, 1, 2, 3 }, down = { 4, 5, 6, 7 },
  left = { 8, 9, 10, 11 }, right = { 8, 9, 10, 11 },
}
local function poseTable()
  return require("src.core.GameVersion").isGen5() and Gen4FishingTask.BW_POSE or Gen4FishingTask.POSE
end

local MESSAGES = {
  platinum = { bank = 213, nibble = 54, away = 55, early = 56, landed = 57 },
  hgss = { bank = 40, nibble = 49, away = 50, early = 51, landed = 52 },
  -- Black / White: story bank 263 (3 landed, 4 nibble, 5 too quickly, and
  -- 6 "Reeled it in too late!" where the DS games before said it got away)
  bw = { bank = 263, nibble = 4, away = 6, early = 5, landed = 3 },
}
local FALLBACK = {
  nibble = "Not even a nibble...", away = "The Pok\195\169mon got away...",
  early = "Reeled it in too quickly...", landed = "Landed a Pok\195\169mon!",
}

local function Game() return require("src.core.Game") end

local function isHgss()
  local GV = require("src.core.GameVersion")
  return GV.family() == "hgss"
end

function Gen4FishingTask.message(game, key)
  local GV = require("src.core.GameVersion")
  local m = MESSAGES[GV.isGen5() and "bw" or isHgss() and "hgss" or "platinum"]
  local ok, T = pcall(require, "src.import.Gen4Text")
  local text = ok and T.resolve and T.resolve(game.data, m.bank, m[key], game)
  if type(text) == "string" and text ~= "" then
    return (text:gsub("[\r\v\f]+$", ""))
  end
  return FALLBACK[key]
end

local function sound(game, name)
  pcall(function() require("src.core.Sound").play(game.data, name) end)
end

-- the HGSS follower's mood band (FieldSystem_UnkSub108_GetMonMood)
local function moodBand(mood)
  mood = tonumber(mood) or 0
  if mood <= -10 then return 1 end
  if mood <= 9 then return 2 end
  if mood < 50 then return 3 end
  if mood < 100 then return 4 end
  return 5
end

local function followerActive(game, ow)
  if not isHgss() then return false end
  local ok, F = pcall(require, "src.world.HgssFollowMon")
  if not (ok and F and F.isActive) then return false end
  local okA, active = pcall(F.isActive, game, ow)
  return okA and active and true or false, F
end

function Gen4FishingTask.hookWindow(game, ow, rod)
  local frames = Gen4FishingTask.HOOK[rod] or 45
  local active, F = followerActive(game, ow)
  if active then
    local mon = F.lead and F.lead(game.save)
    local row = Gen4FishingTask.HGSS_MOOD_BONUS[moodBand(mon and mon.hgssMood)]
    frames = frames + (row[ROD_INDEX[rod] or 1] or 0)
  end
  return frames
end

-- ov01_021FCC2C: a friendly follower (friendship >= 100, 20..50% by bracket)
-- shows the "!" itself, unless the player is surfing.
local function bubbleOwner(game, ow, rng)
  local active, F = followerActive(game, ow)
  if not active or (ow.player and ow.player.surfing) then return ow.player end
  local mon
  for _, m in ipairs(game.save.party or {}) do
    if not (m.isEgg or m.egg) and (tonumber(m.hp) or 1) > 0 then mon = m break end
  end
  local f = tonumber(mon and mon.friendship) or 0
  local chance = f <= 99 and 0 or f <= 149 and 20 or f <= 199 and 30 or f <= 249 and 40 or 50
  if chance > 0 and rng(0, 99) < chance then
    local npc = F.current and F.current(ow)
    if npc then return npc end
  end
  return ow.player
end

-- start(ow, rod, enc): push the task. `enc` is the roll's answer (nil: no bite).
function Gen4FishingTask.start(ow, rod, enc, opts)
  opts = opts or {}
  local game = Game()
  local self = setmetatable({
    name = "Gen4FishingTask", game = game, ow = ow, rod = rod or "old",
    enc = enc, state = "cast", counter = 0, acc = 0,
    rng = opts.rng or love.math.random,
  }, Gen4FishingTask)
  local p = ow.player
  local form = require("src.pokemon.Sprites").playerForm(game.data)
  local key = form and form.fishing
  local def = key and game.data.sprites and game.data.sprites[key]
  if p and def then
    local SpriteRenderer = require("src.render.SpriteRenderer")
    p.gen4FishSheets = p.gen4FishSheets or {}
    local sheet = p.gen4FishSheets[key]
    if not sheet then
      sheet = SpriteRenderer.new(def, "player")
      -- Black / White's 64 x 64 rod frames stand the rider where the 32 x 32
      -- walk frames do: the body is centred in the bigger frame
      if require("src.core.GameVersion").isGen5() and sheet.tileH == 64 then
        sheet.offsetY = sheet.offsetY - 16
      end
      p.gen4FishSheets[key] = sheet
      pcall(function() require("src.render.PlayerPalette").apply(sheet, game.data, game.save) end)
    end
    p.gen4Fish = { sprite = sheet, frame = poseTable()[p.facing or "down"][1],
                   flip = require("src.core.GameVersion").isGen5() and p.facing == "right" or nil }
  end
  game.stack:push(self)
  return self
end

function Gen4FishingTask:pose(step)
  local p = self.ow.player
  if not (p and p.gen4Fish) then return end
  local cycle = poseTable()[p.facing or "down"] or poseTable().down
  p.gen4Fish.frame = cycle[math.max(1, math.min(4, step))]
end

function Gen4FishingTask:say(key, after)
  self.waiting = true
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, Gen4FishingTask.message(self.game, key), function()
    self.waiting = false
    after()
  end))
end

function Gen4FishingTask:clearBubble()
  if self.bubble and self.ow.emote == self.bubble then self.ow.emote = nil end
  self.bubble = nil
end

function Gen4FishingTask:putAway(caught)
  self:clearBubble()
  if require("src.core.GameVersion").isGen5() then
    require("src.world.Gen5FishingLure").reel(self.ow, caught)
  end
  self.caught = caught
  self.state, self.counter = "putAway", 0
end

function Gen4FishingTask:frame(pressedA)
  local st = self.state
  if st == "cast" then
    self.counter = self.counter + 1
    if self.counter == 10 then sound(self.game, require("src.core.GameVersion").isGen5() and "SEQ_SE_FLD_19" or "SEQ_SE_DP_FW104") end
    self:pose(1 + math.floor(self.counter / 8))
    if self.counter < 34 then return end
    self:pose(4)
    self.counter = 0
    -- BLACK / WHITE: the lure lands on the water (src/world/Gen5FishingLure.lua)
    local bw = require("src.core.GameVersion").isGen5()
    if bw then require("src.world.Gen5FishingLure").cast(self.ow) end
    if self.enc then
      self.delay = ((self.rng(0, 65535) % 4) + 1) * 30
      self.hook = Gen4FishingTask.hookWindow(self.game, self.ow, self.rod)
      -- ...and waits rand(90) + 30 frames, the hook open 30 (ov21 0x21C5DF4)
      if bw then self.delay, self.hook = self.rng(0, 89) + 30, 30 end
      self.state = "waitFish"
    else
      self.counter = 30 * 4
      self.state = "waitNoFish"
    end
    -- SAME FRAME: FishingTask_CastRod returns TRUE, so SetFishWait /
    -- WaitForFish (or the no-fish pair) run in the cast's last frame --
    -- that frame already counts down and already reads A (pokeplatinum
    -- src/overlay005/fishing.c; HGSS ov01_021FC814 / _021FC84C /
    -- _021FC9DC all return 1). Platinum / HGSS only; BW keeps its own.
    if not bw then return self:frame(pressedA) end
  elseif st == "waitFish" then
    self.delay = self.delay - 1
    if pressedA then return self:early() end
    if self.delay > 0 then return end
    local owner = bubbleOwner(self.game, self.ow, self.rng)
    local frames = require("src.import.Gen4Emotes").FRAMES
    self.bubble = { npc = owner, frames = 9999, totalFrames = frames, bubble = 1, age = 0 }
    self.ow.emote = self.bubble
    sound(self.game, require("src.core.GameVersion").isGen5() and "SEQ_SE_FLD_07" or "SEQ_SE_DP_DECIDE")
    self.state, self.counter = "checkReel", 0
    -- ...and WaitForFish returns TRUE on the bite (HGSS ov01_021FC88C), so
    -- CheckForReelInFish spends its first frame of the window here: A is
    -- taken on N-1 frames after the "!", not N
    if not require("src.core.GameVersion").isGen5() then return self:frame(false) end
  elseif st == "checkReel" then
    self.hook = self.hook - 1
    self.counter = self.counter + 1
    -- the rod jerks while the fish is on
    self:pose(math.floor(self.counter / 4) % 2 == 0 and 3 or 4)
    if self.bubble then
      self.bubble.age = self.bubble.age + 1
      self.bubble.frames = math.max(1, self.bubble.totalFrames - self.bubble.age)
    end
    if pressedA then
      self:clearBubble()
      if require("src.core.GameVersion").isGen5() then require("src.world.Gen5FishingLure").remove(self.ow) end
      self.state, self.counter = "reel", 0
      return
    end
    if self.hook > 0 then return end
    self:clearBubble()
    self:pose(4)
    self.gotAway = true
    self:say("away", function() self:putAway(false) end)
  elseif st == "reel" then
    self.counter = self.counter + 1
    self:pose(4 - math.floor(self.counter / 5))
    if self.counter > 15 then
      self:say("landed", function() self:putAway(true) end)
    end
  elseif st == "waitNoFish" then
    self.counter = self.counter - 1
    if pressedA then return self:early() end
    if self.counter > 0 then return end
    self:say("nibble", function() self:putAway(false) end)
  elseif st == "putAway" then
    local p = self.ow.player
    if p then p.gen4Fish = nil end
    self.counter = self.counter + 1
    if self.counter > 2 then self:finish() end
  end
end

function Gen4FishingTask:early()
  self:pose(4)
  self:say("early", function() self:putAway(false) end)
end

function Gen4FishingTask:finish()
  if self.done then return end
  self.done = true
  local game, ow = self.game, self.ow
  if ow.player then ow.player.gen4Fish = nil end
  self:clearBubble()
  local stack = game.stack
  if stack.states and stack.states[#stack.states] == self then stack:pop() end
  local save = game.save
  save.gen4Records = save.gen4Records or {}
  -- Platinum's What's Fishing segment (fishing.c; src/script/PtTvRecords.lua)
  if self.caught or self.gotAway then
    pcall(function() require('src.script.PtTvRecords').fishing(save, self.rod, self.caught and self.enc or nil) end)
  end
  if self.caught then
    -- RECORD_CAUGHT_FISH / GAME_STAT_FISH_LANDED
    save.gen4Records.fishLanded = (save.gen4Records.fishLanded or 0) + 1
    local enc = self.enc
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, enc.species, enc.level,
      { hooked = true, nature = enc.nature, gender = enc.gender })
    if ow:inSafariGame() then battle:makeSafari(save.safari) end
    if enc.onePerfectIV and enc.gender == nil and battle.enemy and battle.enemy.mon then
      require("src.world.Gen45EncounterRate").onePerfectIV(game.data, battle.enemy.mon)
    end
    battle.onFinish = function(result) ow:afterBattle(result, battle) end
    ow:pushBattle(battle)
  elseif self.gotAway then
    save.gen4Records.fishGotAway = (save.gen4Records.fishGotAway or 0) + 1
  end
  if self.onDone then self.onDone(self.caught) end
end

function Gen4FishingTask:update(dt)
  if self.done or self.waiting then return end
  local input = self.game.input
  if input and input:wasPressed("a") then self.pendingA = true end
  self.acc = self.acc + (dt or Gen4FishingTask.FRAME)
  local steps = 0
  while self.acc >= Gen4FishingTask.FRAME - 1e-9 and steps < 4 and not self.waiting and not self.done do
    self.acc = self.acc - Gen4FishingTask.FRAME
    steps = steps + 1
    local a = self.pendingA
    self.pendingA = false
    self:frame(a)
  end
end

function Gen4FishingTask:draw() end

return Gen4FishingTask
