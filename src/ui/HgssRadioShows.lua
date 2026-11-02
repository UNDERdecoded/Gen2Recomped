-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE POKeGEAR RADIO'S SHOWS -- what plays and what prints once a station is
-- tuned (src/ui/HgssGearRadio.lua owns the dial). pokeheartgold, overlay 101:
--
--   * THE CORE (src/application/pokegear/radio/overlay_101_021F57B8.c):
--     RadioShow_BeginSegment / _EndSegment / _Main / _TranslateStationID,
--     the line printer (RadioPrintInit, RadioPrintAdvance, Radio_RunTextPrinter,
--     Radio_RunTextPrinter_WaitJingle, RadioShow_DelayAndScrollLine,
--     RadioShow_ScrollTextOffWindow, RadioShow_Delay) and PrintRadioLine with
--     String_RadioAddStatic (pm_string.c). Ported state for state, frame for
--     frame: a message is split at its newlines and printed a line at a time
--     into the two-row script window -- the first line on row 0 (or row 1 when
--     a line is already showing), 45 frames, the next on row 1, then for every
--     further line 45 frames, an 8-step 2 px scroll and a print on row 1; at
--     the end of the segment the window scrolls 34 px off and 15 frames later
--     the next segment begins (the hour is read again then, so station 2 / 3
--     move on to the next show at the hour).
--   * THE SHOWS (radio/shows/*.c), one setup / print / teardown each:
--       0 Pokemon Music (pokemon_music.c)      SEQ by weekday, GB Sounds
--       1 Pokemon Talk (pokemon_talk.c)        SEQ_GS_OHKIDO_RABO
--       2 Pokemon Search Party                 SEQ_GS_RADIO_VARIETY
--       3 Serial Radio Drama                   SEQ_GS_RADIO_VARIETY
--       4 Buena's Password                     SEQ_GS_AIKOTOBA
--       5 Trainer Profiles                     SEQ_GS_RADIO_TRAINER
--       6 That Town, These People              SEQ_GS_RADIO_PT
--       7 Poke Flute                           SEQ_GS_HUE
--       8 Unown                                SEQ_GS_RADIO_UNKNOWN
--       9 Team Rocket                          SEQ_GS_SENKYO_R
--      10 Mahogany's signal                    SEQ_GS_KAIDENPA
--      11 Commercials (commercials.c)          silent (after the jingle)
--     The talk shows end on their sign-off line over SEQ_GS_RADIO_JINGLE, wait
--     for the jingle to end and raise triggerCommercials: the next segment is
--     a commercial, then the station's show again.
--   * TEXT: each show's bank (409..420), the place names (bank 279, else 280
--     line 2 -- BufferLandmarkName), species names (bank 237), Buena's
--     passwords (bank 66 line 40 + set). Buffers live in the show's own
--     MessageFormat (`self.buf`), swapped into game.stringBuffers only while a
--     line is formatted so a script's buffers are never touched.
--   * RANDOMNESS: LCRandom / MTRandom are love.math.random here (the same
--     ranges and the same modulo picks); the cartridge's seeds are not kept.

local Font = require("src.render.Font")

local RS = {}
RS.__index = RS

local floor = math.floor

RS.MUSIC, RS.TALK, RS.SEARCH, RS.DRAMA, RS.BUENA, RS.TRAINER, RS.TOWN = 0, 1, 2, 3, 4, 5, 6
RS.FLUTE, RS.UNOWN, RS.ROCKET, RS.MAHOGANY, RS.COMMERCIALS = 7, 8, 9, 10, 11

-- RadioPrintState
local P_NULL, P_WAIT_FIRST, P_NEXT, P_WAIT_SCROLL, P_WAIT_SCROLL_EXIT, P_WAIT_EXIT, P_EXIT = 0, 1, 2, 3, 4, 5, 6

local function rand(n)
  local r = (love and love.math and love.math.random) or math.random
  return r(0, 65535) % n
end
RS.rand = rand

-- ---------------------------------------------------------------- the save

local function flag(save, id)
  return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true
end
local function flypoint(save, n)
  return flag(save, 0x9B0 + n)   -- FLAG_SYS_FLYPOINT_PALLET + n
end
local function hasItem(game, n)
  local inv = (game.save or {}).inventory or {}
  local keys = { ("ITEM_%03d"):format(n), n, tostring(n) }
  local def = game.data and game.data.items and game.data.items[n]
  if type(def) == "table" and def.id then keys[#keys + 1] = def.id end
  if n == 502 then keys[#keys + 1] = "ITEM_GB_SOUNDS" end
  if n == 472 then keys[#keys + 1] = "ITEM_BLUE_CARD" end
  for _, k in ipairs(keys) do
    if (tonumber(inv[k]) or 0) > 0 then return true end
  end
  return false
end
local function owned(save)
  local set = {}
  local dex = save and save.pokedex
  for k, v in pairs((dex and dex.owned) or {}) do
    if v == true or (type(v) == "number" and v > 0) then
      local id = tonumber(k) or tonumber(tostring(k):match("(%d+)%s*$"))
      if id then set[id] = true end
    end
  end
  return set
end

-- ---------------------------------------------------------------- object

-- opts: game, regionNo (0 Johto / 1 Kanto: MapHeader_GetRegionNo of the
-- player's map), music(song, loop) (SndRadio_StartSeq / StopSeq), fade(frames)
-- (StopBGM with a fade), sounding() (SndRadio_CountPlayingSeq ~= 0)
function RS.new(opts)
  local self = setmetatable({}, RS)
  self.game = opts.game
  self.regionNo = opts.regionNo or 0
  self.musicFn, self.fadeFn, self.soundingFn = opts.music, opts.fade, opts.sounding
  self.curStation, self.lastStation, self.nextStation = 0, 0, 0
  self.lastEpisodeID = 0
  self.triggerCommercials = false
  self.buf = {}
  self.rows = {}
  self.title, self.host = "", ""
  self.active = false
  return self
end

function RS:music(song, loop) if self.musicFn then self.musicFn(song, loop) end end

-- ReadMsgDataIntoString (no placeholders expanded)
function RS:raw(bank, index)
  local ok, T = pcall(require, "src.import.Gen4Text")
  if not ok then return "" end
  local s = T.resolve(self.game.data, bank, index, nil)
  return type(s) == "string" and s or ""
end

-- ReadMsgDataIntoString + StringExpandPlaceholders(self.msgFormat)
function RS:format(bank, index)
  local ok, T = pcall(require, "src.import.Gen4Text")
  if not ok then return "" end
  local game = self.game
  local saved = game.stringBuffers
  local b = {}
  for i = 0, 7 do b[i + 1] = self.buf[i] or "" end
  game.stringBuffers = b
  local okR, s = pcall(T.resolve, game.data, bank, index, game)
  game.stringBuffers = saved
  return okR and type(s) == "string" and s or ""
end

-- BufferLandmarkName: bank 279, a 0 / out-of-range mapsec reads bank 280 line 2
function RS:landmark(slot, mapsec)
  local s = mapsec and mapsec ~= 0 and self:raw(279, mapsec) or ""
  if s == "" then s = self:raw(280, 2) end
  self.buf[slot] = s
end
function RS:species(slot, species) self.buf[slot] = self:raw(237, species or 0) end

-- ------------------------------------------------------- the script window

-- String_RadioAddStatic(line, 70): every non-space glyph, 70 times in 101,
-- becomes the widest of the ellipsis / two dots / one dot its width allows
local CHAR_ELLIPSIS, CHAR_ONE_DOT, CHAR_TWO_DOTS = 431, 491, 492
function RS.static(text, level)
  local codes = Font.encode(text)
  local space = Font.encode(" ")[1]
  local w3, w1, w2 = Font.advanceOf(CHAR_ELLIPSIS), Font.advanceOf(CHAR_ONE_DOT), Font.advanceOf(CHAR_TWO_DOTS)
  for i, c in ipairs(codes) do
    if c ~= space and rand(101) < level then
      local w = Font.advanceOf(c)
      if w >= w3 then codes[i] = CHAR_ELLIPSIS
      elseif w >= w2 then codes[i] = CHAR_TWO_DOTS
      elseif w >= w1 then codes[i] = CHAR_ONE_DOT end
    end
  end
  return codes
end

-- PrintRadioLine: AddTextPrinter at row y (16 px a row). The glyph cells it
-- writes overwrite what was under them, so a line printed over an older one
-- hides the older one up to its own width.
function RS:printLine(text, row)
  local entry = { text = text, y = row * 16 }
  if self.statik then entry.codes = RS.static(text, 70) end
  local w = Font.width(text)
  for _, e in ipairs(self.rows) do
    if e.y == entry.y then e.clip = math.max(e.clip or 0, w) end
  end
  self.rows[#self.rows + 1] = entry
  self.lastLine = text
end

-- ScrollWindow(win, up, 2 px): what leaves the 32 px window is gone
function RS:scroll()
  local keep = {}
  for _, e in ipairs(self.rows) do
    e.y = e.y - 2
    if e.y > -16 then keep[#keep + 1] = e end
  end
  self.rows = keep
end

function RS:clearWindow() self.rows = {} end

function RS:delayAndScrollLine()
  if self.delayCounter < self.delayFrames then
    self.delayCounter = self.delayCounter + 1
    return false
  end
  if self.scrollCounter ~= 0 then self:scroll() end
  local c = self.scrollCounter
  self.scrollCounter = c + 1
  if c < 8 then return false end
  self.scrollCounter, self.delayCounter = 0, 0
  return true
end

function RS:scrollTextOffWindow()
  self:scroll()
  local c = self.scrollCounter
  self.scrollCounter = c + 1
  if c < self.scrollFrames then return false end
  self.scrollCounter = 0
  return true
end

function RS:delay()
  local c = self.delayCounter
  self.delayCounter = c + 1
  if c < self.delayFrames then return false end
  self.delayCounter = 0
  return true
end

local function splitLines(s)
  local out = {}
  for l in ((s or ""):gsub("[\v\f]", "\n") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = l end
  if #out == 0 then out[1] = "" end
  return out
end

function RS:advance()
  self.isSecondLine = true
  self:printLine(self.msgLines[self.curLineIdx + 1] or "", 1)
  self.curLineIdx = self.curLineIdx + 1
  return self.curLineIdx >= self.numLines
end

-- RadioPrintInit(msgId, textNoScroll) on the show's own bank
function RS:printInit(msgId, noScroll, bank)
  self.textNoScroll = noScroll and true or false
  self.msgLines = splitLines(self:format(bank or self.bank, msgId))
  self.curLineIdx = 0
  self.numLines = #self.msgLines
  self.printState = P_NULL
  self:printLine(self.msgLines[1], self.isSecondLine and 1 or 0)
  self.curLineIdx = 1
  if self.curLineIdx >= self.numLines then self.printState = P_WAIT_EXIT
  elseif not self.isSecondLine then self.printState = P_WAIT_FIRST
  else self.printState = P_WAIT_SCROLL end
  if self.onPrint then self.onPrint(msgId) end
end

function RS:printAndPlayJingle(msgId)
  self:printInit(msgId, false)
  self.textNoScroll = true
  self.isPlayingJingle = true
  self:music(nil)
  self:music("SEQ_GS_RADIO_JINGLE", false)
  self.jingleFrames = 0
end

function RS:runTextPrinter()
  local s = self.printState
  if s == P_NULL then return false end
  if s == P_NEXT then
    if self:advance() then
      self.printState = self.textNoScroll and P_EXIT or P_WAIT_SCROLL_EXIT
    else
      self.printState = P_WAIT_SCROLL
    end
  elseif s == P_WAIT_SCROLL then
    if self:delayAndScrollLine() then self.printState = P_NEXT end
  elseif s == P_WAIT_FIRST then
    if self:delay() then self.printState = P_NEXT end
  elseif s == P_WAIT_SCROLL_EXIT then
    if self:delayAndScrollLine() then self.printState = P_EXIT end
  elseif s == P_WAIT_EXIT or s == P_EXIT then
    if s == P_WAIT_EXIT and not self:delay() then return false end
    self.printState = P_NULL
    return true
  end
  return false
end

-- SndRadio_CountPlayingSeq: the jingle is a one-shot; with no audio to ask
-- (a headless run) it counts as over at once. Ten seconds is the backstop.
function RS:jinglePlaying()
  self.jingleFrames = (self.jingleFrames or 0) + 1
  if self.jingleFrames > 600 then return false end
  return self.soundingFn and self.soundingFn() or false
end

function RS:runTextPrinterWaitJingle()
  if self.printWithJingleState == 0 then
    if self:runTextPrinter() then self.printWithJingleState = 1 end
  elseif self.printWithJingleState == 1 then
    if not self:jinglePlaying() then
      self.printWithJingleState = 0
      return true
    end
  end
  return false
end

-- --------------------------------------------------------------- the core

-- RadioShow_TranslateStationID
function RS:translate(station)
  if station >= 8 then station = 0 end
  if self.triggerCommercials then
    self.triggerCommercials = false
    return RS.COMMERCIALS
  end
  local t = os.date("*t")
  local hour = type(t) == "table" and tonumber(t.hour) or 0
  if station == 0 then return RS.MUSIC end
  if station == 1 then return RS.TALK end
  if station == 2 then return RS.TRAINER + hour % 2 end
  if station == 3 then return RS.SEARCH + hour % 3 end
  if station == 4 then return RS.FLUTE end
  if station == 5 then return RS.UNOWN end
  if station == 6 then return RS.ROCKET end
  if station == 7 then return RS.MAHOGANY end
  return RS.MUSIC
end

local SHOWS

function RS:beginSegment(station, statik)
  self.isSecondLine = false
  if station >= 8 then station = 0 end
  self.nextStation = station
  if self.curStation ~= RS.COMMERCIALS then self.lastStation = self.curStation end
  self.curStation = self:translate(station)
  self.runState = 0
  self.delayFrames, self.delayCounter = 45, 0
  self.scrollFrames, self.scrollCounter = 8, 0
  self.statik = statik and true or false
  self.isPlayingJingle = false
  self.printWithJingleState = 0
  self.printState = P_NULL
  if self.curStation ~= RS.COMMERCIALS and self.lastStation ~= self.curStation then
    self.lastEpisodeID = 0
  end
  self:clearWindow()
  self.data = { state = 0 }
  self.onPrint = nil
  local show = SHOWS[self.curStation]
  show.setup(self, self.data)
  self.active = true
end

function RS:endSegment()
  if self.data then self.data = nil end
  self:clearWindow()
  self.triggerCommercials = false
  self.active = false
end

function RS:setStatic(statik) self.statik = statik and true or false end

function RS:main()
  if not self.active then return end
  local rs = self.runState
  if rs == 0 then
    local show = SHOWS[self.curStation]
    if show.print(self, self.data) then self.runState = 1 end
  elseif rs == 1 then
    self.data = nil
    self.scrollFrames, self.delayFrames = 16, 15
    self.runState = 2
  elseif rs == 2 then
    if self:scrollTextOffWindow() then self.runState = 3 end
  elseif rs == 3 then
    if self:delay() then
      self:beginSegment(self.nextStation, self.statik)
      self.runState = 0
    end
  end
end

-- the window's contents, for drawing: { text, codes?, y, clip? }
function RS:window() return self.rows end

-- the title / host a show reads into its strings
local function titled(self, bank, host)
  self.bank = bank
  self.title = self:raw(bank, 0)
  self.host = host and self:raw(bank, 1) or ""
end

-- -------------------------------------------------- the shows themselves

-- the shape four of them share: an intro line, `pick(d)`'s message(s), the
-- jingle sign-off, then the commercials
local function talkShow(intro, outro, count)
  return function(self, d)
    local s = d.state
    d.selector = d.selector or 0
    if s == 0 then
      self:printInit(intro)
      d.state = 1
      return false
    end
    if s == 1 then
      if not self:runTextPrinter() then return false end
      d.state, s = 2, 2   -- falls through into case 2
    end
    if s == 2 then
      self:printInit(d.msgIDs[d.selector + 1])
      d.state = 3
    elseif s == 3 then
      if not self:runTextPrinter() then return false end
      d.selector = d.selector + 1
      if d.selector < count then d.state = 2 else d.state = 4 end
    elseif s == 4 then
      if self:delayAndScrollLine() then
        self:printAndPlayJingle(outro)
        d.state = 5
      end
    elseif s == 5 then
      if self:runTextPrinterWaitJingle() then
        self.triggerCommercials = true
        return true
      end
    end
    return false
  end
end

-- POKeMON MUSIC (pokemon_music.c)
local MUSIC_DEFAULT = { [0] = "SEQ_GS_RADIO_MARCH", "SEQ_GS_RADIO_KOMORIUTA", "SEQ_GS_RADIO_R_101", "SEQ_GS_RADIO_R_201" }
local MUSIC_GB = {
  "SEQ_GS_P_TITLE", "SEQ_GS_P_OPENING_TITLE_G", "SEQ_GS_P_ENDING", "SEQ_GS_P_ENDING2", "SEQ_GS_P_SENKYO",
  "SEQ_GS_P_E_MINAKI", "SEQ_GS_P_IBUKI", "SEQ_GS_P_EYE_J_SHOUJO", "SEQ_GS_P_EYE_J_SHOUNEN",
  "SEQ_GS_P_EYE_J_AYASHII", "SEQ_GS_P_EYE_BOUZU", "SEQ_GS_P_EYE_MAIKO", "SEQ_GS_P_EYE_ROCKET",
  "SEQ_GS_P_EYE_K_SHOUJO", "SEQ_GS_P_EYE_K_SHOUNEN", "SEQ_GS_P_EYE_K_AYASHII", "SEQ_GS_P_VS_ROCKET",
  "SEQ_GS_P_AIKOTOBA", "SEQ_GS_P_RADIO_JINGLE", "SEQ_GS_P_OHKIDO_RABO", "SEQ_GS_P_RADIO_MARCH",
  "SEQ_GS_P_RADIO_KOMORIUTA", "SEQ_GS_P_HUE", "SEQ_GS_P_POKEMON_THEME", "SEQ_GS_P_OHKIDO",
}
RS.MUSIC_GB = MUSIC_GB
local GB = 4

local function today()
  local t = os.date("*t")
  return t.wday - 1, t.day
end

local Music = {
  setup = function(self, d)
    local national = ((self.game.save or {}).pokedex or {}).national and true or false
    d.weekday, d.tuneInDay = today()
    d.queuedMsg = 3 + d.weekday
    local w = d.weekday
    if w == 0 then
      if hasItem(self.game, 502) then d.queuedTrack = GB
      else d.queuedTrack, d.queuedMsg = 0, 12 end
    elseif w == 1 or w == 5 then d.queuedTrack = 0
    elseif w == 3 then
      if national then d.queuedTrack, d.queuedMsg = 2, 10 else d.queuedTrack = 0 end
    elseif w == 2 or w == 6 then d.queuedTrack = 1
    elseif w == 4 then
      if national then d.queuedTrack, d.queuedMsg = 3, 11 else d.queuedTrack = 1 end
    end
    titled(self, 416, true)
    self:music(nil)
    -- RadioShow_PokemonMusic_StartPlaying
    local track = d.queuedTrack
    local seq
    if track == GB then
      track = floor((rand(25000)) / 1000)
      seq = MUSIC_GB[track + 1]
    else
      seq = MUSIC_DEFAULT[track]
    end
    d.playingTrack = track
    self:music(seq)
    self.isSecondLine = false
  end,
  print = function(self, d)
    local s = d.state
    if s == 0 then
      self:printInit(2)
      d.state = 1
    elseif s == 1 then
      if self:runTextPrinter() then d.state = 2 end
    elseif s == 2 then
      local _, day = today()
      d.afterIntroDay = day
      self:printInit(d.queuedMsg)
      d.state = 3
    elseif s == 3 then
      if self:runTextPrinter() then
        local _, day = today()
        if day == d.afterIntroDay and day == d.tuneInDay then
          d.state = 2
          return false
        end
        self.isPlayingJingle = true
        if self.fadeFn then self.fadeFn(30) end
        d.state = 4
      end
    elseif s == 4 then
      if self:delayAndScrollLine() then return true end
    end
    return false
  end,
}

-- POKeMON TALK (pokemon_talk.c)
local TALK_FILTER = { [449] = true, [513] = true, [487] = true, [315] = true, [490] = true, [491] = true,
  [492] = true, [237] = true, [238] = true, [239] = true, [242] = true, [243] = true, [298] = true, [357] = true }
local MAP_ROUTE_47, MAP_ROUTE_48, MAP_ID_MAX, MAX_SPECIES = 151, 152, 540, 493
local FLYPOINT_UNK25 = 25

local function headers(data)
  local ok, Gear = pcall(require, "src.ui.HgssPokegear")
  return ok and Gear.headers and Gear.headers(data) or {}
end

-- RadioShow_PokemonTalk_SampleSpeciesFromMapEncounters
local function sampleSpecies(enc, caught)
  local species, priority, seen = {}, {}, {}
  local function add(sp)
    sp = tonumber(sp) or 0
    if sp == 0 or sp > MAX_SPECIES or seen[sp] then return end
    seen[sp] = true
    species[#species + 1] = sp
    if not caught[sp] then priority[#priority + 1] = sp end
  end
  enc = enc or {}
  if (tonumber(enc.grassRate) or 0) ~= 0 then
    local timed = enc.timed or {}
    for i = 1, 12 do
      local g = (enc.grass or {})[i]
      add((timed.morning or {})[i] or (g and g.species))
      add((timed.day or {})[i] or (g and g.species))
      add((timed.night or {})[i] or (g and g.species))
    end
  end
  for _, block in ipairs({ { enc.surf, 5 }, { enc.rockSmash, 2 }, { enc.oldRod, 5 }, { enc.goodRod, 5 }, { enc.superRod, 5 } }) do
    local b = block[1]
    if type(b) == "table" and (tonumber(b.rate) or 0) ~= 0 then
      for i = 1, block[2] do add(((b.slots or {})[i] or {}).species) end
    end
  end
  local nightFish = enc.hgssSwarm and tonumber(enc.hgssSwarm.nightFish) or 0
  if nightFish ~= 0 then add(nightFish) end
  if #species == 0 then return 0 end
  if #priority == 0 or (#priority == 1 and rand(1000) < 500) then
    return species[rand(#species) + 1]
  end
  return priority[rand(#priority) + 1]
end
RS.sampleSpecies = sampleSpecies

function RS:talkSample(d)
  local data = self.game.data or {}
  local save = self.game.save or {}
  local hs = headers(data)
  local visited25 = flypoint(save, FLYPOINT_UNK25)
  local landmarks = {}
  for i = 0, MAP_ID_MAX - 1 do
    local h = hs[i]
    if h and h.encounters ~= nil and (tonumber(h.region) or 0) == self.regionNo
       and not TALK_FILTER[i] and (visited25 or (i ~= MAP_ROUTE_47 and i ~= MAP_ROUTE_48)) then
      landmarks[#landmarks + 1] = i
      if #landmarks >= 150 then break end
    end
  end
  d.pairs = {}
  if #landmarks == 0 then return end
  local caught = owned(save)
  local secs = {}
  for i = 0, 4 do
    local index, sec
    local tries = 0
    repeat
      index = landmarks[rand(#landmarks) + 1]
      sec = tonumber(hs[index].mapsec) or 0
      tries = tries + 1
    until not secs[sec] or tries > 5000
    secs[sec] = true
    local enc = data.encounters and data.encounters[tonumber(hs[index].encounters)]
    d.pairs[i + 1] = { sec, sampleSpecies(enc, caught), index }
  end
end

local Talk = {
  setup = function(self, d)
    titled(self, 414, true)
    -- the swarm (RoamerSave_OutbreakActive, GetSwarmInfoFromRand)
    local save = self.game.save or {}
    local okO, Out = pcall(require, "src.world.HgssOutbreaks")
    if okO and Out.active(save) then
      local entry = Out.today(save)
      local data = self.game.data or {}
      local def = entry and data.maps and data.maps[entry[1]]
      local area = def and data.encounters and data.encounters[def.encounters]
      local sw = area and area.hgssSwarm or {}
      local hdr = def and headers(data)[tonumber(def.header)]
      d.swarmSpecies = tonumber(sw[entry[2]]) or 0
      d.swarmSec = hdr and tonumber(hdr.mapsec) or 0
    end
    self:talkSample(d)
    local step = (rand(3) + 1) * 2
    local p1, p2 = rand(13), rand(13)
    d.flavor = {}
    for i = 1, 5 do
      d.flavor[i] = { p1, p2 }
      p1, p2 = (p1 + step) % 13, (p2 + step) % 13
    end
    d.selector = 0
    self:music(nil)
    self:music("SEQ_GS_OHKIDO_RABO")
  end,
  print = function(self, d)
    local s = d.state
    if s == 0 then
      self:printInit(2)
      d.state = 1
      return false
    end
    if s == 1 then
      if not self:runTextPrinter() then return false end
      if (d.swarmSpecies or 0) == 0 then
        d.state = 3
      else
        self:landmark(0, d.swarmSec)
        self:species(1, d.swarmSpecies)
        self:printInit(32)
        d.state = 2
      end
      return false
    end
    if s == 2 then
      if not self:runTextPrinter() then return false end
      d.state, s = 3, 3   -- falls through into case 3
    end
    if s == 3 then
      local p = d.pairs[d.selector + 1]
      if not p then return true end
      self:landmark(0, p[1])
      self:species(1, p[2])
      self:printInit(4)
      d.state = 4
    elseif s == 4 then
      if not self:runTextPrinter() then return false end
      for i = 0, 1 do
        local f = d.flavor[d.selector + 1][i + 1]
        self.buf[i + 2] = self:raw(414, 13 * i + 6 + f)
      end
      self:printInit(5)
      d.state = 5
    elseif s == 5 then
      if not self:runTextPrinter() then return false end
      d.selector = d.selector + 1
      if d.selector < 5 then d.state = 3 else d.state = 6 end
    elseif s == 6 then
      if self:delayAndScrollLine() then
        self:printAndPlayJingle(3)
        d.state = 7
      end
    elseif s == 7 then
      if self:runTextPrinterWaitJingle() then
        self.triggerCommercials = true
        return true
      end
    end
    return false
  end,
}

-- POKeMON SEARCH PARTY (pokemon_search_party.c)
local PSP_UNLOCK = { [0] = 0, 0, 1, 2, 3, 4, 5, 6, 6, 6, 7, 7, 7 }
local Search = {
  setup = function(self, d)
    titled(self, 419, true)
    local save = self.game.save or {}
    local data = self.game.data
    local f = { [0] = true }
    f[1] = flag(save, 0x7B)    -- FLAG_BEAT_AZALEA_ROCKETS
    local okB, Badges = pcall(require, "src.inventory.Badges")
    local list = okB and Badges.list(data) or {}
    f[2] = okB and list[3] and Badges.has(save, list[3]) or false   -- BADGE_PLAIN
    f[3] = flag(save, 0xC6)    -- FLAG_BEAT_RADIO_TOWER_ROCKETS
    local count = okB and Badges.count(data, save) or 0
    f[4], f[5], f[7] = count >= 8, count >= 9, count >= 16
    f[6] = flypoint(save, 5)   -- FLYPOINT_VERMILION
    d.unlocked = {}
    for i = 0, 12 do
      if f[PSP_UNLOCK[i]] then d.unlocked[#d.unlocked + 1] = i end
    end
    local num = #d.unlocked
    d.episodeID = rand(num)
    if d.episodeID == self.lastEpisodeID then d.episodeID = (d.episodeID + 1) % num end
    self.lastEpisodeID = d.episodeID
    self:music(nil)
    self:music("SEQ_GS_RADIO_VARIETY")
  end,
  print = function(self, d)
    local s = d.state
    if s == 0 then
      self:printInit(2)
      d.state = 1
    elseif s == 1 then
      if self:runTextPrinter() then
        self:printInit(4 + d.unlocked[d.episodeID + 1])
        d.state = 2
      end
    elseif s == 2 then
      if self:runTextPrinter() then d.state = 3 end
    elseif s == 3 then
      if self:delayAndScrollLine() then
        self:printAndPlayJingle(3)
        d.state = 4
      end
    elseif s == 4 then
      if self:runTextPrinterWaitJingle() then
        self.triggerCommercials = true
        return true
      end
    end
    return false
  end,
}

-- the shape of the drama and Buena's password: intro, one message, jingle
local function oneMessage(msgOf)
  return function(self, d)
    local s = d.state
    if s == 0 then
      self:printInit(2)
      d.state = 1
    elseif s == 1 then
      if self:runTextPrinter() then
        self:printInit(msgOf(self, d))
        d.state = 2
      end
    elseif s == 2 then
      if self:runTextPrinter() then d.state = 3 end
    elseif s == 3 then
      if self:delayAndScrollLine() then
        self:printAndPlayJingle(3)
        d.state = 4
      end
    elseif s == 4 then
      if self:runTextPrinterWaitJingle() then
        self.triggerCommercials = true
        return true
      end
    end
    return false
  end
end

-- SERIAL RADIO DRAMA (serial_radio_drama.c): one of 22 episodes
local Drama = {
  setup = function(self, d)
    titled(self, 413, true)
    d.episodeID = rand(22)
    if d.episodeID == self.lastEpisodeID then d.episodeID = (d.episodeID + 1) % 22 end
    self.lastEpisodeID = d.episodeID
    self:music(nil)
    self:music("SEQ_GS_RADIO_VARIETY")
  end,
  print = oneMessage(function(self, d) return 4 + d.episodeID end),
}

-- BUENA'S PASSWORD (buenas_password.c): line 4 with the Blue Card (today's
-- password, bank 66 line 40 + VAR_BUENAS_PASSWORD_SET % 30, in buffer 0 --
-- Gen4Commands.buenasPasswordSet, the roll Buena's desk reads), line 5
-- without; starting line 4 sets FLAG_DAILY_HEARD_BUENAS_PASSWORD (0xAB6)
local Buena = {
  setup = function(self, d)
    titled(self, 411, true)
    d.msgID = hasItem(self.game, 472) and 4 or 5
    local save = self.game.save or {}
    local okC, C = pcall(require, "src.script.Gen4Commands")
    local set = (okC and C.buenasPasswordSet and C.buenasPasswordSet(save)) or 0
    self.buf[0] = self:raw(66, 40 + (tonumber(set) or 0) % 30)
    self:music(nil)
    self:music("SEQ_GS_AIKOTOBA")
  end,
  print = oneMessage(function(self, d)
    if d.msgID == 4 then
      local okF, Flags = pcall(require, "src.script.Flags")
      if okF then Flags.set(self.game.save, "FLAG_G4_0AB6")
      else self.game.save.flags = self.game.save.flags or {}; self.game.save.flags.FLAG_G4_0AB6 = true end
    end
    return d.msgID
  end),
}

-- TRAINER PROFILES (trainer_profiles.c): three different of 16 profiles
local Trainer = {
  setup = function(self, d)
    titled(self, 420, true)
    d.msgIDs = {}
    for i = 1, 3 do
      local id, dup
      repeat
        id = 4 + rand(16)
        dup = false
        for j = 1, i - 1 do if d.msgIDs[j] == id then dup = true end end
      until not dup
      d.msgIDs[i] = id
    end
    self:music(nil)
    self:music("SEQ_GS_RADIO_TRAINER")
  end,
  print = talkShow(2, 3, 3),
}

-- THAT TOWN, THESE PEOPLE (that_town_these_people.c): three different of the
-- 20 episodes the fly points unlock
local TTTP_UNLOCK = { [0] = 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 }
local Town = {
  setup = function(self, d)
    titled(self, 415, true)
    local save = self.game.save or {}
    local f = { [0] = true, flypoint(save, 15), flypoint(save, 19), flypoint(save, 21), flypoint(save, 5) }
    local unlocked = {}
    for i = 0, 19 do
      if f[TTTP_UNLOCK[i]] then unlocked[#unlocked + 1] = i end
    end
    d.msgIDs = {}
    for i = 1, 3 do
      local id, dup
      local tries = 0
      repeat
        id = 4 + unlocked[rand(#unlocked) + 1]
        dup = false
        for j = 1, i - 1 do if d.msgIDs[j] == id then dup = true end end
        tries = tries + 1
      until not dup or tries > 5000
      d.msgIDs[i] = id
    end
    self:music(nil)
    self:music("SEQ_GS_RADIO_PT")
  end,
  print = talkShow(2, 3, 3),
}

-- the stations that only play: Poke Flute, Unown, Mahogany; Team Rocket's
-- prints its one line over and over
local function music(bank, seq)
  return {
    setup = function(self) titled(self, bank, false); self:music(nil); self:music(seq) end,
    print = function() return false end,
  }
end

local Rocket = {
  setup = function(self, d)
    titled(self, 418, true)
    self:music(nil)
    self:music("SEQ_GS_SENKYO_R")
  end,
  print = function(self, d)
    if d.state == 0 then
      self:printInit(2)
      d.state = 1
    elseif d.state == 1 then
      if self:runTextPrinter() then d.state = 0 end
    end
    return false
  end,
}

-- COMMERCIALS (commercials.c): {unlock, region bits (1 Johto, 2 Kanto),
-- channel (0xFF any)} per commercial, from line 2
local C_ALWAYS, C_POKEDEX, C_ECRUTEAK, C_CIANWOOD, C_OLIVINE, C_CLEAR, C_VERMILION, C_POWER = 0, 1, 2, 3, 4, 5, 6, 7
local COMMERCIALS = {
  { C_ALWAYS, 3, 0xFF }, { C_ALWAYS, 3, 0xFF }, { C_ALWAYS, 3, 0xFF }, { C_ALWAYS, 3, 0xFF }, { C_ALWAYS, 3, 0xFF },
  { C_ALWAYS, 1, 0xFF }, { C_ALWAYS, 1, 0xFF }, { C_ALWAYS, 1, 0xFF }, { C_ALWAYS, 1, 0xFF },
  { C_ALWAYS, 3, 2 }, { C_ALWAYS, 3, 2 },
  { C_POKEDEX, 3, 0xFF }, { C_POKEDEX, 3, 0xFF }, { C_POKEDEX, 3, 0xFF }, { C_POKEDEX, 3, 0xFF },
  { C_ECRUTEAK, 1, 3 }, { C_ECRUTEAK, 1, 3 }, { C_ECRUTEAK, 1, 3 }, { C_ECRUTEAK, 1, 2 }, { C_ECRUTEAK, 1, 2 },
  { C_ECRUTEAK, 3, 2 },
  { C_CIANWOOD, 3, 2 }, { C_CIANWOOD, 1, 3 },
  { C_OLIVINE, 3, 1 }, { C_OLIVINE, 3, 1 }, { C_OLIVINE, 3, 1 }, { C_OLIVINE, 3, 1 }, { C_OLIVINE, 3, 1 },
  { C_OLIVINE, 3, 1 },
  { C_CLEAR, 3, 3 },
  { C_VERMILION, 2, 3 }, { C_VERMILION, 2, 3 }, { C_VERMILION, 2, 3 }, { C_VERMILION, 2, 3 }, { C_VERMILION, 2, 3 },
  { C_POWER, 3, 3 },
}
RS.COMMERCIAL_TABLE = COMMERCIALS

local Commercials = {
  setup = function(self, d)
    self.triggerCommercials = false
    self.bank = 412
    self.title = self:raw(412, 0)
    self.host = ""
    local save = self.game.save or {}
    local f = {
      [C_ALWAYS] = true, [C_POKEDEX] = flag(save, 0x6B), [C_ECRUTEAK] = flypoint(save, 16),
      [C_CIANWOOD] = flypoint(save, 18), [C_OLIVINE] = flypoint(save, 17), [C_VERMILION] = flypoint(save, 5),
      [C_CLEAR] = flag(save, 0x964), [C_POWER] = flag(save, 0x118),
    }
    local unlocked = {}
    for i, c in ipairs(COMMERCIALS) do
      if f[c[1]] and (c[3] == 0xFF or c[3] == self.nextStation) then
        local bit = self.regionNo + 1
        if floor(c[2] / bit) % 2 == 1 then unlocked[#unlocked + 1] = i - 1 end
      end
    end
    d.msgID = 2 + unlocked[rand(#unlocked) + 1]
  end,
  print = function(self, d)
    local s = d.state
    if s == 0 then
      self:printInit(d.msgID, true)
      d.state = 1
    elseif s == 1 then
      if self:runTextPrinter() then d.state = 2 end
    elseif s == 2 then
      if self:delay() then return true end
    end
    return false
  end,
}

SHOWS = {
  [RS.MUSIC] = Music, [RS.TALK] = Talk, [RS.SEARCH] = Search, [RS.DRAMA] = Drama, [RS.BUENA] = Buena,
  [RS.TRAINER] = Trainer, [RS.TOWN] = Town, [RS.FLUTE] = music(417, "SEQ_GS_HUE"),
  [RS.UNOWN] = music(410, "SEQ_GS_RADIO_UNKNOWN"), [RS.ROCKET] = Rocket,
  [RS.MAHOGANY] = music(409, "SEQ_GS_KAIDENPA"), [RS.COMMERCIALS] = Commercials,
}
RS.SHOWS = SHOWS

return RS
