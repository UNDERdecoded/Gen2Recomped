-- THE POKeGEAR'S RADIO (overlay 101: pokegear_radio.c, overlay_101_021F49F8 /
-- 021F4F34 / 021F57B8 and radio/shows), the RADIO app of
-- src/ui/HgssPokegear.lua.
--
-- READ FROM CODE:
--   * the dial: pgradio NSCR 22 + skin on MAIN_2 over NSCR 28 + skin on
--     MAIN_3; the four channel buttons at tiles (2, 6) / (26, 6) / (2, 14) /
--     (26, 14), lit from the screen's atlas (4, 24), unlit (0, 24)
--     (Radio_ToggleChannelSelectionButtons)
--   * the tuning cursor (OBJ seq 0) inside the circle (128, 92) r 52
--     (sTuningAreaHitbox); its position kept in the save (the cartridge's
--     Pokegear_SetRadioCursorCoords, 128 / 128 on a new save)
--   * keys (Radio_HandleKeyInput): held directions move it 2 px a frame while
--     it stays in the circle; A steps the lit channel button (0..3) and snaps
--     the cursor to that station's centre; B puts the cursor on the bar
--   * touch (Radio_HandleTouchInput_Internal): the buttons y 48-76 / 112-140,
--     x 16-48 / 208-240 snap; a touch within 8 px of the cursor picks it up
--     and it follows the stylus inside the circle until released
--   * stations (Radio_GetTunedStationID): the circles of the set the map
--     allows -- Johto (112,76) (152,76) (96,108) (136,116), Kanto the first
--     three, Kanto + EXPN also (128,48); Alph / Rocket / Mahogany one at the
--     centre; no signal none -- each with an inner ring (clear) and an outer
--     one (static); the set by Radio_GetAvailableChannels: no radio signal on
--     the map -> none, the Ruins of Alph's halls -> Alph, Kanto (region) ->
--     none before FLAG_RESTORED_POWER (0x118), with EXPN after
--     FLAG_GOT_EXPN_CARD (0x11F), Mahogany's maps before
--     FLAG_ROCKET_HIDEOUT_CLEARED (0xCA) -> the signal, the Rocket takeover
--     (var 0x4077 2..4) -> Team Rocket, else Johto
--   * the show (RadioShow_TranslateStationID): 0 Pokemon Music, 1 Pokemon
--     Talk, 2 Trainer Profiles / That Town (hour % 2), 3 Search Party /
--     Serial Drama / Buena's Password (hour % 3), 4 Poke Flute, 5 Unown,
--     6 Team Rocket, 7 the Mahogany signal; each show's title (entry 0) and
--     host (1) from its bank (416, 414, 420, 415, 419, 413, 411, 417, 410,
--     418, 409); the title in MAIN_1's window (5, 1), the host in SUB_2's
--     (4, 16), the script in SUB_2's (2, 19), two lines
--   * POKeMON MUSIC (shows/pokemon_music.c): bank 416 2, then the day's line
--     (3 + weekday; 10 / 11 with the National Dex on Wednesday / Thursday; 12
--     on a Sunday without the GB Sounds) and its track -- March (Mon, Wed,
--     Fri, Sun), Lullaby (Tue, Thu, Sat), Hoenn / Sinnoh with the National Dex;
--     POKe FLUTE plays SEQ_GS_HUE, UNOWN SEQ_GS_RADIO_UNKNOWN
--   * THE SHOWS THEMSELVES -- every show's lines, its SEQ, the segment loop
--     (show, jingle, commercial, show), the line printer's timing and the
--     static on a weak signal -- are src/ui/HgssRadioShows.lua (the
--     RadioShow core, overlay_101_021F57B8.c, and radio/shows/*.c); this
--     module tunes it: Radio_OpenStation / _CloseStation /
--     RadioShow_SetStaticLevel / Radio_Run.

local Font = require("src.render.Font")
local Shows = require("src.ui.HgssRadioShows")

local Radio = {}
Radio.__index = Radio

local floor = math.floor
local CX, CY, CR = 128, 92, 52
local BUTTON_TILE = { [0] = { 2, 6 }, { 26, 6 }, { 2, 14 }, { 26, 14 } }
local BUTTON_RECT = { [0] = { 48, 76, 16, 48 }, { 48, 76, 208, 240 }, { 112, 140, 16, 48 }, { 112, 140, 208, 240 } }
-- sTuningHitboxes_*: {x, y, inner r, outer r} per station slot
local JOHTO = { { 112, 76, 4, 16 }, { 152, 76, 4, 20 }, { 96, 108, 4, 16 }, { 136, 116, 4, 20 } }
local SETS = {
  johto = JOHTO,
  kanto = { JOHTO[1], JOHTO[2], JOHTO[3] },
  expn = { JOHTO[1], JOHTO[2], JOHTO[3], JOHTO[4], { 128, 48, 4, 8 } },
  none = {},
  alph = { { 128, 92, 4, 16 } },
  rocket = { { 128, 92, 38, 52 } },
  mahogany = { { 128, 92, 38, 52 } },
}
local ALPH_MAPS = { [315] = true, [323] = true, [490] = true, [491] = true, [492] = true }
local MAHOGANY_MAPS = { [87] = true, [133] = true, [140] = true, [396] = true, [397] = true, [246] = true,
  [368] = true, [116] = true, [247] = true, [248] = true, [249] = true, [45] = true, [142] = true,
  [245] = true, [88] = true, [294] = true, [295] = true }
local function flag(save, id) return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end

function Radio.new(gear)
  local self = setmetatable({ gear = gear, game = gear.game, button = 0, lit = false, t = 0 }, Radio)
  local pg = gear:save()
  self.x, self.y = tonumber(pg.radioX) or 128, tonumber(pg.radioY) or 128
  if not self:inArea(self.x, self.y) then self.x, self.y = 128, 128 end
  self.set = self:availableSet()
  self.lines = {}
  -- RadioShow_Create: the shows' state lives as long as the radio app
  -- (lastEpisodeID, the commercial trigger); regionNo is the map's
  local header = gear:header()
  self.rs = Shows.new({
    game = self.game,
    regionNo = header and (tonumber(header.region) or 0) ~= 0 and 1 or 0,
    music = function(song, loop) self:music(song, loop) end,
    fade = function(frames)
      local ok, Music = pcall(require, "src.core.Music")
      if ok and Music.dsFade then pcall(Music.dsFade, 0, frames) end
    end,
    sounding = function()
      local ok, Music = pcall(require, "src.core.Music")
      if not (ok and Music.sounding and Music.current) then return false end
      return Music.current() == self.song and Music.sounding()
    end,
  })
  return self
end

function Radio:inArea(x, y)
  local dx, dy = x - CX, y - CY
  return dx * dx + dy * dy <= CR * CR
end

-- Radio_GetAvailableChannels
function Radio:availableSet()
  local header, id = self.gear:header()
  local save = self.game.save
  if header and header.radioSignal == false then return "none" end
  if id and ALPH_MAPS[id] then return "alph" end
  if header and (header.region or 0) ~= 0 then
    if not flag(save, 0x118) then return "none" end
    if flag(save, 0x11F) then return "expn" end
    return "kanto"
  end
  if id and MAHOGANY_MAPS[id] and not flag(save, 0xCA) then return "mahogany" end
  local ok, C = pcall(require, "src.script.Gen4Commands")
  local takeover = ok and C.getVar and tonumber(C.getVar(save, 0x4077)) or 0
  if takeover >= 2 and takeover <= 4 then return "rocket" end
  return "johto"
end

-- Radio_GetTunedStationID: station, signal (2 clear, 1 static) or nil
function Radio:tuned(x, y)
  for i, c in ipairs(SETS[self.set] or {}) do
    local dx, dy = x - c[1], y - c[2]
    local d2 = dx * dx + dy * dy
    if d2 <= c[3] * c[3] or d2 <= c[4] * c[4] then
      local station = i - 1
      if self.set == "rocket" then station = 6
      elseif self.set == "mahogany" then station = 7
      elseif self.set == "alph" then station = 5 end
      return station, d2 <= c[3] * c[3] and 2 or 1
    end
  end
  return nil, 0
end

-- RadioShow_TranslateStationID (the show a station plays now)
function Radio:showFor(station)
  return self.rs:translate(station)
end

-- SndRadio_StartSeq / SndRadio_StopSeq: a show's sequence starts from its
-- beginning (StopBGM first), `loop` false for the one-shot jingle
function Radio:music(song, loop)
  self.song = song
  local ok, Music = pcall(require, "src.core.Music")
  if not ok then return end
  pcall(Music.stop)
  if song then pcall(Music.play, self.game.data, song, loop) end
end

-- Radio_OpenStation: RadioShow_BeginSegment, static unless the signal is
-- clear (signal 2)
function Radio:open(station)
  self.rs:beginSegment(station, self.signal ~= 2)
  self:mirror()
end

-- what the show has put in its windows, for drawing and the harnesses
function Radio:mirror()
  local rs = self.rs
  self.show = rs.curStation
  self.title, self.host = rs.title, rs.host
  local lines = {}
  local rows = {}
  for _, e in ipairs(rs:window()) do rows[#rows + 1] = e end
  table.sort(rows, function(a, b) return a.y < b.y end)
  for _, e in ipairs(rows) do if e.y > -16 and e.y < 32 then lines[#lines + 1] = e.text end end
  self.lines = lines
end

-- Radio_CloseStation (RadioShow_EndSegment); StopBGM when the dial leaves
-- every station
function Radio:close(keepMusic)
  if self.station ~= nil then
    self.station, self.signal = nil, 0
    self.rs:endSegment()
    self.title, self.host, self.lines, self.show = nil, nil, {}, nil
    if not keepMusic then self:music(nil) end
  end
end

-- Radio_CoordsToStation
function Radio:retune()
  local station, signal = self:tuned(self.x, self.y)
  if station == nil then return self:close() end
  if station == self.station then
    if signal ~= self.signal then
      self.rs:setStatic(signal ~= 2)
      self.signal = signal
    end
    return
  end
  self:close(true)
  self.station, self.signal = station, signal
  self:open(station)
end

function Radio:enter()
  self.set = self:availableSet()
  -- Radio_Start (as the app fades in): the field's music stops. The radio
  -- overlay is built anew each time the app opens, its RadioShow with it.
  local rs = self.rs
  rs.curStation, rs.lastStation, rs.nextStation, rs.lastEpisodeID = 0, 0, 0, 0
  rs.triggerCommercials, rs.active, rs.buf = false, false, {}
  self.station = nil
  self:music(nil)
  self:retune()
end

function Radio:leave()
  local pg = self.gear:save()
  pg.radioX, pg.radioY = self.x, self.y
  -- Radio_VideoUnload: a tuned station keeps playing in the field
  -- (src/world/HgssRadioMusic.lua); the map's music comes back only for an
  -- untuned dial
  local Field = require("src.world.HgssRadioMusic")
  -- ...and so does the jingle or a commercial (isPlayingJingle,
  -- curStation == RADIO_STATION_COMMERCIALS)
  local rs = self.rs
  local between = rs.active and (rs.isPlayingJingle or rs.curStation == Shows.COMMERCIALS)
  if self.station ~= nil and self.song and not between then
    Field.keep(self.game, self.song)
    self:close(true)
    return
  end
  Field.clear(self.game)
  self:close()
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.restoreMap then pcall(Music.restoreMap, self.game.data) end
end

function Radio:snap(i)
  local c = JOHTO[i + 1]
  self.x, self.y = c[1], c[2]
  self:retune()
end

function Radio:keys(input)
  if not self.entered then self.entered = true; self:enter() end
  if input:wasPressed("b") then return self.gear:toBar() end
  if input:wasPressed("a") then
    self.button = self.lit and (self.button + 1) % 4 or self.button
    self.lit = true
    self:snap(self.button)
    self.gear:se("SEQ_SE_GS_GEARCURSOR")
    return
  end
  local dx, dy = 0, 0
  if input:isDown("left") then dx = -2 elseif input:isDown("right") then dx = 2 end
  if input:isDown("up") then dy = -2 elseif input:isDown("down") then dy = 2 end
  if dx == 0 and dy == 0 then return end
  local moved = false
  if self:inArea(self.x + dx, self.y) then self.x = self.x + dx; moved = true end
  if self:inArea(self.x, self.y + dy) then self.y = self.y + dy; moved = true end
  self.lit = false
  if moved then self:retune() end
end

function Radio:touch(x, y)
  if not self.entered then self.entered = true; self:enter() end
  for i = 0, 3 do
    local r = BUTTON_RECT[i]
    if y >= r[1] and y < r[2] and x >= r[3] and x < r[4] then
      self.button, self.lit = i, true
      self:snap(i)
      self.gear:se("SEQ_SE_GS_GEARCURSOR")
      return true
    end
  end
  if not self:inArea(x, y) then return false end
  local dx, dy = x - self.x, y - self.y
  if dx * dx + dy * dy <= 64 then
    self.x, self.y = x, y
    self.dragging = true
    self.busy = true
    self.lit = false
    self:retune()
    return true
  end
  return false
end

function Radio:busyUpdate(input, tap)
  if not self.dragging or not self.gear.touchHeld then
    self.dragging, self.busy = false, false
  end
end

function Radio:touchMove(x, y)
  if self.dragging and self:inArea(x, y) then
    self.x, self.y = x, y
    self:retune()
  end
end

function Radio:touchUp() self.dragging, self.busy = false, false end

function Radio:reselect() end

function Radio:update()
  self.t = self.t + 1
  if not self.entered and not self.gear.fade then self.entered = true; self:enter() end
  -- Radio_Run: RadioShow_Main once a frame while a station is open
  if self.station ~= nil and self.rs.active then
    self.rs:main()
    self:mirror()
  end
end

function Radio:drawTouch()
  local gear = self.gear
  gear:picture("radio_back")
  gear:picture("radio_top")
  if self.lit then
    local full = gear:img("radio_full")
    local at = BUTTON_TILE[self.button]
    if full then gear:tiles(full, 4, 24, 4, 4, at[1], at[2]) end
  end
  -- the tuning cursor, its five frames cycling
  local frame = floor(self.t / 8) % 5
  if not gear:obj("radio", 0, frame, self.x, self.y) then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("line", self.x, self.y, 6)
  end
  if self.title and self.title ~= "" then
    Font.pushStyle({ text = gear:ink("radioMain", 1, { 1, 1, 1 }), shadow = gear:ink("radioMain", 2, { 0.3, 0.3, 0.3 }) })
    Font.draw(self.title, 40, 8)
    Font.popStyle()
  end
end

function Radio:drawTop()
  local gear = self.gear
  gear:picture("radio_bottom")
  Font.pushStyle({ text = gear:ink("radioSub", 1, { 1, 1, 1 }), shadow = gear:ink("radioSub", 2, { 0.3, 0.3, 0.3 }) })
  if self.host and self.host ~= "" then Font.draw(self.host, 32, 128) end
  -- the script window, SUB_2 (2, 19) 28 x 4 tiles: two 16 px rows that
  -- scroll up 2 px a step; a line printed over another hides it up to its
  -- own width; a line with static is drawn glyph code by glyph code
  if self.station ~= nil then
    local WX, WY, WW, WH = 16, 152, 224, 32
    local sx, sy, sw, sh = love.graphics.getScissor()
    for _, e in ipairs(self.rs:window()) do
      local x0 = WX + (e.clip or 0)
      if x0 < WX + WW then
        -- the scissor is in canvas pixels, past whatever transform is on;
        -- inside a supersampled pass (src/render/SuperSample.lua) the
        -- scissor calls are wrapped to multiply by its R themselves
        local ax, ay = love.graphics.transformPoint(x0, WY)
        local bx, by = love.graphics.transformPoint(WX + WW, WY + WH)
        local SSok, SS = pcall(require, "src.render.SuperSample")
        local R = SSok and SS.active and tonumber(tostring(SS.key or ""):match("x(%d+)$")) or 1
        ax, ay, bx, by = ax / R, ay / R, bx / R, by / R
        love.graphics.intersectScissor(math.min(ax, bx), math.min(ay, by),
          math.max(0, math.abs(bx - ax)), math.max(0, math.abs(by - ay)))
        if e.codes then
          local pen = WX
          for _, code in ipairs(e.codes) do
            Font.drawCode(code, pen, WY + e.y)
            pen = pen + Font.advanceOf(code)
          end
        else
          Font.draw(e.text, WX, WY + e.y)
        end
        if sx then love.graphics.setScissor(sx, sy, sw, sh) else love.graphics.setScissor() end
      end
    end
  end
  Font.popStyle()
end

return Radio
