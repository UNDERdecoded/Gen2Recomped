-- Round 34: one entry of R27B.MODULES for this round's modules (the R27B
-- interface: spawnObject / spawnManager / roomInit / frame / draw), plus
-- drawWorld (one line in Field:drawWorld) and the room-load music rules.
--
--   Beanstalk34  BEANSTALK $2C types 7 / 8 / 9 in the field, the climb
--                rooms and the cloud tops; BACKGROUND_CLOUD $4A
--   DigCave34    DIGGING_CAVE_ENTRANCE_MANAGER $04 (the Mole Mitts caves)
--   Cloud34      CLOUD_OVERLAY_MANAGER $18 (Hyrule Field's cloud shadows)
--   Push34       furniture pushing Link out (sub_0800445C)
--   Objects34    GIANT_ROCK, GIANT_LEAF, BELL, HIDDEN_LADDER_DOWN, FIREPLACE,
--                SMOKE, STEAM
--   Vortex34     BIG_VORTEX $82 + PlayerParachute states 6 / 7 (with Whirlwind)
--   (WorldEvent34: worldEvent5's overlay, called by Fusion32)
--
-- CARTRIDGE BEHAVIOUR (music, zeldaret/tmc):
--   * LoadRoomBgm (gameUtils.c): queued_bgm = gAreaMetadata[area].queueBgm,
--     BGM_FIGHT_THEME2 ($33) while LV6_KANE_START (bank 10 flag $7C) is set.
--   * LoadRoomTileEntities (room.c): MUSIC_SETTER (tile entity type 7):
--     queued_bgm = t->_3.  Both run before the room's own init code, which
--     may set queued_bgm again.
--   * weatherChangeManager.c sub_08059608 ($10, Mt. Crenel's summit $06:00):
--     Link east of x $200 -> BGM_CRENEL_STORM ($1E), else BGM_MT_CRENEL
--     ($37); a change fades the music out (SONG_FADE_OUT_BGM) and starts the
--     new song $78 frames later.
-- SIMPLIFIED: the weather manager's palette mix (gPalette_549, MixPalettes)
--   and its rain BG3 / BG1 scroll are not ported (music only); the fade-out
--   is a stop.
local bit = require("bit")
local band = bit.band

local R = {}

R.MODULES = {
  "src.zelda.tmc.Beanstalk34",
  "src.zelda.tmc.DigCave34",
  "src.zelda.tmc.Cloud34",
  "src.zelda.tmc.Push34",
  "src.zelda.tmc.Objects34",
  "src.zelda.tmc.Vortex34",
  "src.zelda.tmc.Objects36", -- round 36: PRESSURE_PLATE $24
}

R.ROM_RANGES = {}

local loaded
local function mods()
  if loaded then return loaded end
  loaded = {}
  for _, name in ipairs(R.MODULES) do
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then
      loaded[#loaded + 1] = m
      for k, v in pairs(m.ROM_RANGES or {}) do R.ROM_RANGES[k] = v end
    elseif not ok and not tostring(m):find("module '" .. name .. "' not found", 1, true) then
      error(m, 0)
    end
  end
  return loaded
end
R.mods = mods

local MUSIC_SETTER = 7
local BANK10, LV6_KANE_START = 10, 0x7C
local BGM_FIGHT_THEME2, BGM_CRENEL_STORM, BGM_MT_CRENEL = 0x33, 0x1E, 0x37
local WEATHER_CHANGE_MANAGER = 0x10
R.BGM = { FIGHT_THEME2 = BGM_FIGHT_THEME2, CRENEL_STORM = BGM_CRENEL_STORM, MT_CRENEL = BGM_MT_CRENEL }

-- the queued song a room starts with before its init code (LoadRoomBgm +
-- MUSIC_SETTER); nil = the area's own
function R.roomBgm(f)
  local q
  local ok, kane = pcall(function()
    local BANK = f.BANK_OFFSET or require("src.zelda.tmc.Field").BANK_OFFSET
    -- round 49: gLocalFlagBanks is indexed by LOCAL_BANK_n (LOCAL_BANK_G = 0): FLAG_BANK_10 ($8C0)
    -- is entry BANK10 + 1 (entry 10 is FLAG_BANK_9, $800)
    return BANK and BANK[BANK10 + 1] and f:flag("bank", LV6_KANE_START, BANK[BANK10 + 1])
  end)
  if ok and kane then q = BGM_FIGHT_THEME2 end
  for _, t in ipairs(f.room and f.room.tileEntities or {}) do
    if t.type == MUSIC_SETTER then q = t.b end
  end
  return q
end

local function sendAll(name, ...)
  for _, m in ipairs(mods()) do
    if m[name] then local x = m[name](...) if x ~= nil then return x end end
  end
  return nil
end

function R.spawnObject(d, e) return sendAll("spawnObject", d, e) end

function R.spawnManager(d, m, dat)
  if m.id == WEATHER_CHANGE_MANAGER then
    d.field.weather34 = { room = d.field.room, wait = 0 }
    return true
  end
  return sendAll("spawnManager", d, m, dat)
end

-- R27B.roomInit runs inside Field:spawnRoomEntities, after the earlier
-- modules' room code: the room-load music only fills a song nobody set
function R.roomInit(f)
  if f.queuedBgm == nil then f.queuedBgm = R.roomBgm(f) end
  for _, m in ipairs(mods()) do if m.roomInit then m.roomInit(f) end end
end

-- sub_08059608
local function weather(f)
  local w = f.weather34
  if not w then return end
  if w.room ~= f.room then f.weather34 = nil return end
  if w.wait > 0 then
    w.wait = w.wait - 1
    if w.wait == 0 then f:bgm(w.song) end
    return
  end
  local east = (f.player and f.player.x or 0) > 0x200
  local want = east and BGM_CRENEL_STORM or BGM_MT_CRENEL
  local cur = w.song or (f.game.audio and f.game.audio.current)
  if cur ~= want then
    w.song, w.wait = want, 0x78
    f.queuedBgm = want
    f:bgm(nil) -- SONG_FADE_OUT_BGM
  end
end
R.weatherStep = weather

function R.frame(f, input)
  weather(f)
  for _, m in ipairs(mods()) do
    if m.frame and m.frame(f, input) then return true end
  end
  return false
end

function R.draw(f, font)
  for _, m in ipairs(mods()) do if m.draw then m.draw(f, font) end end
end

-- Field:drawWorld (after the priority passes, with R31 / R33)
function R.drawWorld(f)
  for _, m in ipairs(mods()) do if m.drawWorld then m.drawWorld(f) end end
end

function R.playerFrame(p, input)
  for _, m in ipairs(mods()) do
    if m.playerFrame and m.playerFrame(p, input) then return true end
  end
  return false
end

mods()
return R
