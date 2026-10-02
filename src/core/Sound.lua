-- Sound effects and cries synthesized from compact ROM channel programs,
-- from def-local chip programs (ChipAsm), or loaded from file definitions --
-- the branch is chosen per definition, not by a global import flag. Sources
-- are cached; a definition that fails to load caches as `false` so it is
-- logged once and skipped, never disabling the rest of the audio. Headless
-- use is a safe no-op.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local Sound = {}

local cache = {}
-- port addition: 0-7 SFX volume from save.options.sfxVol (OptionsMenu),
-- scaling the 0.8 base every source gets
local BASE_VOLUME = 0.8
local volumeScale = 1
-- port addition (Yellow only): 0-7 trim from save.options.pikaVol on top of
-- the SFX level, for Pikachu's voice clips alone.  Yellow voices every
-- Pikachu cry with PCM samples that are far louder and far more frequent
-- than the chip cries around them (the follower alone talks on every
-- interaction), so this is the one source players want to pull down
-- without muting the rest of the SFX bus.  7 = untouched, 0 = silent.
local pikaScale = 1

-- AUDIO SESSION SUSPEND (mobile interruption: an incoming phone call).
--
-- iOS takes the audio session away from the app for the length of a call and
-- hands back a NEW one afterwards; SDL reports the transition as
-- SDL_APP_WILLENTERBACKGROUND, which reaches us as love.focus(false) ->
-- Game:focus -> Music.suspend -> Sound.suspend.  Android sends the same app
-- events.
--
-- Two distinct things have to be prevented here, and they are not the same
-- thing:
--
--  1. PLAYING INTO A DEAD DEVICE.  Source:stop / Source:play / setVolume /
--     setLooping are unremarkable on a healthy device and are exactly what
--     OpenAL refuses once the device behind them is invalidated; LOVE raises
--     that refusal as a Lua error.  They were bare calls below.  They are
--     guarded now, because the focus event arrives a frame after the
--     interruption has already taken effect.
--
--  2. POISONING THE CACHE.  playPath / playCry / playPikaCry / startLoop
--     cache a def that fails to build as `false` -- "known bad, already
--     logged" -- and never try it again for the rest of the session.
--     love.audio.newSource against a device that has gone away fails, so
--     without the gates below a call arriving at the wrong moment would mark
--     whatever effect the game happened to play as permanently broken.  So
--     while the session is suspended nothing is built at all, and
--     Sound.resume drops the cache so sources built against the OLD session
--     are re-rendered the next time they are asked for.
local sessionSuspended = false

-- See sessionSuspended: logged at debug rather than swallowed, so a raise
-- from one of these on desktop (where there is no session to lose) still
-- leaves a line naming the call that failed.
local function safeAudio(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Logger.debug("audio: %s failed (%s) -- the audio device is gone or going "
      .. "(incoming call / backgrounding on mobile)", what, tostring(err))
  end
  return ok
end

-- Restart a one-shot from its beginning.  stop-then-play is the idiom every
-- caller below used inline; it is also two device calls in a row, which is
-- exactly the shape that needs the guard.  Returns false when nothing was
-- started, so callers do not report a sound that never sounded.
local function restart(src)
  if sessionSuspended or not src then return false end
  safeAudio("Source:stop", src.stop, src)
  return safeAudio("Source:play", src.play, src)
end

-- cache keys whose volume the Pikachu trim applies to: the PCM clips, plus
-- the chip PIKACHU cry that a Yellow cache without extracted clips falls
-- back to (playCry).  Red/Blue never reach the second branch, so a shared
-- options.lua carrying a low pikaVol cannot quiet their Pikachu.
local function isPikaKey(key)
  if type(key) ~= "string" then return false end
  if key:sub(1, 8) == "pikacry:" then return true end
  return key == "cry:PIKACHU"
    and require("src.core.GameVersion").isYellow()
end

-- A CRY IS NOT A SOUND EFFECT AT FULL TILT.
--
-- Reported from play: "the pokemon cries theyre seeming a little loud and
-- obnoxious not matching emeralds presentation of them".  On the cartridge a
-- cry sounds at CRY_VOLUME out of the mixer's 256 -- well under half -- and
-- the song ducks underneath it.  Both numbers are read off the ROM at import
-- (RomExtractorGen3:extractCryVolume, five agreeing PlayCry sites) and
-- arrive as constants.gen3Cry; a cache without them changes nothing.
local function cryScale(data)
  local c = data and data.constants and data.constants.gen3Cry
  local volume = c and tonumber(c.volume)
  local scale = c and tonumber(c.scale)
  if not (volume and scale and scale > 0) then return 1 end
  return volume / scale
end

Sound.cryScale = cryScale

local function volumeFor(key)
  local scale = volumeScale
  if isPikaKey(key) then scale = scale * pikaScale end
  return BASE_VOLUME * scale
end

-- Fanfares occupy the music's tone channels on the Game Boy: their sfx
-- headers claim channels 5-7 (= hardware channels 1-3), silencing the
-- song until they finish (audio/headers/sfxheaders*.asm; the game also
-- blocks on them via PlaySoundWaitForCurrent/WaitForSoundToFinish).
-- The Poké Flute even issues SFX_STOP_ALL_MUSIC first
-- (engine/items/item_effects.asm).  Music.lua pauses the current song
-- while one of these plays and resumes it afterwards.  Ordinary short
-- SFX (menu beeps, hits, cries) stay overlaid.
-- data.audio.fanfares supersedes this; the copy stays as the fallback for
-- caches built before the importer wrote the table, and a def may claim the
-- behavior for itself with fanfare = true.
local FANFARES = {
  Level_Up = true,
  Caught_Mon = true,
  Get_Item1 = true,
  Get_Item2 = true,
  Get_Key_Item = true,
  Pokedex_Rating = true,
  Dex_Page_Added = true,
  Pokeflute = true,
}

-- which mod put this key in the registry, for attributed failure logs
local function owner(data, kind, key)
  local owners = data and data.audio and data.audio._owners
  local map = owners and owners[kind]
  return map and map[key] or "base"
end

-- one log line, plus an entry in the loader's error feed when a mod owns the
-- def, so the manager's errors screen can flag that mod
local function reportBadDef(kind, key, who, err)
  Logger.warn("audio: bad %s def %q (mod %s): %s", kind, key, who, tostring(err))
  Runtime.reportError(who,
    ("audio: bad %s def %q: %s"):format(kind, key, tostring(err)))
end

local function isChipDef(def)
  return type(def) == "table" and (def.chip ~= nil or def.address ~= nil)
end

-- OpenAL only spatializes 1-channel Sources, and one left at the default
-- (0,0,0) position sits on top of the listener, which OpenAL renders as an
-- ambient sound spread over every output channel the device has: on an
-- interface with more than two outputs the SFX also came out of outputs 5+6
-- while the 2-channel music stayed on 1+2 (#626).  A Source cannot change its
-- channel count after the fact, so a mono file def is re-decoded and its
-- sample duplicated into a stereo buffer, which OpenAL never spatializes.
-- Chip SFX and cries are already stereo at the source (ChipSynth
-- renderEffectData); this covers file defs, i.e. Yellow's 8-bit mono PCM
-- Pikachu clips (RomExtractor extractPikachuCries) and mod-supplied wav/ogg
-- SFX. Decode channel count from SoundData and emit 16-bit stereo, including
-- 8-bit cartridge clips on Switch. Every step is guarded: a stub without love.sound, or a
-- decoder that will not hand back SoundData, keeps the original Source.
local function widenMono(source, file)
  if not (source and love.sound and love.sound.newSoundData) then
    return source
  end
  local built, widened = pcall(function()
    local mono = love.sound.newSoundData(file)
    if mono:getChannelCount()~=1 then return source end
    local frames = mono:getSampleCount()
    local stereo = love.sound.newSoundData(frames, mono:getSampleRate(),
                                           16, 2)
    for index = 0, frames - 1 do
      local value = mono:getSample(index)
      stereo:setSample(index, 1, value)
      stereo:setSample(index, 2, value)
    end
    return love.audio.newSource(stereo, "static")
  end)
  if built and widened then return widened end
  return source
end

-- a file def carries an optional playback rate; a bare string is shorthand
-- for { file = <string> }
local function newFileSource(def)
  local file = type(def) == "table" and def.file or def
  if type(file) ~= "string" then return nil, "no chip program and no file" end
  local ok, s = pcall(love.audio.newSource, file, "static")
  if not ok or not s then return nil, ok and "no source" or tostring(s) end
  s = widenMono(s, file) -- keep mono defs off the surround channels (#626)
  if type(def) == "table" and def.pitch then pcall(s.setPitch, s, def.pitch) end
  return s
end

local function newSfxSource(data, key, def, pitch, tempo)
  if type(def) == "table" and def.nds ~= nil then
    local ok, src = pcall(require("src.audio.NitroAudio").new, data, def)
    if not ok then return nil, tostring(src) end
    src:setLooping(false)
    return src
  end
  -- A GEN 3 SOUND EFFECT IS A SONG, played to its end.  The cartridge's own
  -- scripts say so: `playse` takes a number out of the same table the map
  -- themes come from, and the only thing that makes one an effect is that it
  -- stops instead of looping.  It has no chip program and no file, which is
  -- what every one of them used to fall through to.
  if type(def) == "table" and def.m4a then
    local ok, sd = pcall(require("src.core.ChipAudio").newM4AEffect, data, def)
    if not ok then return nil, tostring(sd) end
    if not sd then return nil, "no source" end
    return sd
  end
  if isChipDef(def) then
    local ok, s = pcall(require("src.core.ChipAudio").newSfx,
      data, key:match("^([^@]+)") or key, pitch, tempo, def)
    if not ok then return nil, tostring(s) end
    if not s then return nil, "no source" end
    return s
  end
  return newFileSource(def)
end

local function playPath(data, key, def, pitch, tempo)
  key = tostring(key)
  if not love.audio or not def then return nil end
  -- INTERRUPTION: building a Source now would fail and cache `false` below,
  -- permanently disabling this effect (see sessionSuspended, case 2)
  if sessionSuspended then return nil end
  local src = cache[key]
  if src == false then return nil end -- known bad, already logged
  if not src then
    local s, err = newSfxSource(data, key, def, pitch, tempo)
    if not s then
      cache[key] = false
      reportBadDef("sfx", key, owner(data, "sfx", key), err)
      return nil
    end
    safeAudio("Source:setVolume", s.setVolume, s, volumeFor(key))
    cache[key] = s
    src = s
  end
  if not restart(src) then return nil end
  return src
end

local function ducks(data, name, def)
  if type(def) == "table" and def.fanfare then return true end
  local fanfares = data.audio and data.audio.fanfares or FANFARES
  return fanfares[name] and true or false
end

local function played(kind, name, species)
  if not Runtime.wants("sound.played") then return end
  Runtime.emit("sound.played", { kind = kind, name = name, species = species })
end

-- returns the started source (nil headless, or when the def failed to load)
-- so callers that block on a fanfare like the original's
-- PlaySoundWaitForCurrent -> WaitForSoundToFinish can poll it
function Sound.play(data, name)
  local sfx = data.audio and data.audio.sfx
  local def = sfx and sfx[name]
  local src = playPath(data, name, def)
  if not src then return end
  if ducks(data, name, def) then
    require("src.core.Music").duckForFanfare(src)
  end
  played("sfx", name)
  return src
end

-- PLAY A CARTRIDGE SOUND BY ITS NUMBER.
--
-- Every other caller here names a ROLE -- "Ball_Toss", "Press_AB" -- because
-- that is the vocabulary shared across four generations.  The Gen 3 ball
-- animation does not have roles: the cartridge's own code says `PlaySE(56)`,
-- and the four bounce sounds are four consecutive numbers with no names
-- anywhere in the ROM.  So this answers a number, by looking for a role that
-- already plays it.
--
-- A number no role covers plays nothing and says nothing: the animation is
-- still right, it is just quieter, and inventing a substitute sound would be
-- worse than silence.
local byNumber = nil
function Sound.playId(data, id)
  id = tonumber(id)
  local sfx = data and data.audio and data.audio.sfx
  if not (id and sfx) then return end
  if byNumber == nil or byNumber.__sfx ~= sfx then
    byNumber = { __sfx = sfx }
    for name, def in pairs(sfx) do
      local n = type(def) == "table" and tonumber(def.m4a or def.nds)
      if n and byNumber[n] == nil then byNumber[n] = name end
    end
  end
  local name = byNumber[id]
  if not name then return end
  return Sound.play(data, name)
end

-- Play a move's sound with its MoveSoundTable pitch/tempo modifiers
-- (data/moves/sfx.asm; GetMoveSound loads them into wFrequencyModifier/
-- wTempoModifier and the battle sound engine applies them to every
-- battle SFX -- audio/engine_2.asm Audio2_ApplyFrequencyModifier/
-- Audio2_SetSfxTempo).  The extractor pre-synthesizes one WAV per
-- distinct (sfx, pitch, tempo) as "<name>@<pitch><tempo>" keys in the
-- sfx table; older audio.lua builds without the variants fall back to
-- the unmodified sound.
-- anim: a moves.lua anim table { sound, pitch, tempo }.
function Sound.playMove(data, anim)
  if not anim or not anim.sound then return end
  local sfx = data.audio and data.audio.sfx
  if not sfx then return end
  local name = anim.sound
  local pitch, tempo = anim.pitch or 0, anim.tempo or 0x80
  -- a chip program synthesizes the modified variant on demand; a file def
  -- can only reach for a pre-rendered one
  if isChipDef(sfx[name]) then
    if playPath(data, ("%s@%02x%02x"):format(name, pitch, tempo),
        sfx[name], pitch, tempo) then
      played("move", name)
    end
    return
  end
  if pitch ~= 0 or tempo ~= 0x80 then
    local key = ("%s@%02x%02x"):format(name, pitch, tempo)
    if sfx[key] then
      if playPath(data, key, sfx[key]) then played("move", name) end
      return
    end
  end
  if playPath(data, name, sfx[name]) then played("move", name) end
end

-- A derived cry ({ base = "RHYDON", pitch, length }) borrows another
-- species' program and applies its own modifiers, so a new species needs no
-- assets at all.  Chains are followed; the modifiers nearest the caller win.
local function resolveCry(data, def, depth)
  if type(def) ~= "table" or not def.base then return def end
  if depth > 8 then return nil, "cry base chain too deep" end
  local cries = data.audio and data.audio.cries
  local baseDef = cries and cries[def.base]
  if not baseDef then
    return nil, "unknown base cry " .. tostring(def.base)
  end
  local resolved, err = resolveCry(data, baseDef, depth + 1)
  if not resolved then return nil, err end
  if type(resolved) ~= "table" or not (resolved.header or resolved.chip) then
    return nil, "base cry " .. tostring(def.base) .. " is not a chip program"
  end
  return {
    header = resolved.header, chip = resolved.chip,
    pitch = def.pitch or resolved.pitch,
    length = def.length or resolved.length,
  }
end

local function newCrySource(data, species, def)
  -- A GEN 3 CRY names a recording rather than a chip program, so there is no
  -- base chain to resolve and no header to look up: the index IS the def.
  if type(def) == "table" and def.m4a then
    local ok, s = pcall(require("src.core.ChipAudio").newCry, data, species, def)
    if not ok then return nil, tostring(s) end
    if not s then return nil, "no source" end
    return s
  end
  local resolved, err = resolveCry(data, def, 0)
  if not resolved then return nil, err end
  if type(resolved) == "table" and (resolved.header or resolved.chip) then
    local ok, s = pcall(
      require("src.core.ChipAudio").newCry, data, species, resolved)
    if not ok then return nil, tostring(s) end
    if not s then return nil, "no source" end
    return s
  end
  return newFileSource(resolved)
end

-- Yellow's voiced Pikachu clips (audio/pikachu_pcm.asm
-- PlayPikachuSoundClip): 1-bit PCM decoded to WAVs at import
-- (data.audio.pikaCries = clip count).  Returns the source, nil when the
-- cache carries no clips (Red/Blue) or headless.
function Sound.playPikaCry(data, n)
  if not love.audio then return nil end
  -- INTERRUPTION: same cache-poisoning gate as playPath (sessionSuspended)
  if sessionSuspended then return nil end
  local count = data.audio and data.audio.pikaCries
  if not count then return nil end
  n = math.max(1, math.min(count, n or 1))
  local key = "pikacry:" .. n
  local src = cache[key]
  if src == false then return nil end
  if not src then
    local path = ("assets/generated/audio/pika_cries/cry_%02d.wav"):format(n)
    local ok, s = pcall(love.audio.newSource, path, "static")
    if not ok or not s then
      cache[key] = false
      return nil
    end
    -- the importer writes these clips as 8-bit mono (RomExtractor
    -- extractPikachuCries), so they need the same widening as the chip
    -- effects to stay off a multi-output device's surround channels (#626)
    s = widenMono(s, path)
    safeAudio("Source:setVolume", s.setVolume, s, volumeFor(key))
    cache[key] = s
    src = s
  end
  if not restart(src) then return nil end
  played("cry", "PIKACHU_PCM_" .. n, "PIKACHU")
  return src
end

-- returns the source (nil headless) so callers that block on the cry
-- like the original's PlayCry -> WaitForSoundToFinish can poll it
function Sound.playCry(data, species, opts)
  if not love.audio then return nil end
  -- INTERRUPTION: same cache-poisoning gate as playPath (sessionSuspended)
  if sessionSuspended then return nil end
  -- Yellow voices every Pikachu cry with the PCM clips (the chip cry is
  -- never used for the species there); clip 1 is the everyday "Pika!"
  if species == "PIKACHU" then
    local src = Sound.playPikaCry(data, 1)
    if src then return src end
  end
  local cries = data.audio and data.audio.cries
  local def = cries and cries[species]
  if not def and type(species) == "number" then
    local mon = data.pokemon and data.pokemon[species]
    def = cries and mon and cries[mon.name]
  end
  if not def then return nil end
  local key = "cry:" .. tostring(species)
  local src = cache[key]
  if src == false then return nil end
  if not src then
    local s, err = newCrySource(data, species, def)
    if not s then
      cache[key] = false
      reportBadDef("cry", tostring(species),
        owner(data, "cries", species), err)
      return nil
    end
    safeAudio("Source:setVolume", s.setVolume, s, volumeFor(key))
    cache[key] = s
    src = s
  end
  -- set every time rather than at build: the cached source outlives a change
  -- of game, and the scale is the loaded cartridge's
  pcall(src.setVolume, src, volumeFor(key) * cryScale(data))
  -- Interactive Dex playback owns its source; loop/effect settings must never
  -- leak onto the cached cry used by battles, NPC scripts or other menus.
  if opts and opts.isolated and src.clone then
    local ok,copy=pcall(src.clone,src)
    if ok and copy then src=copy end
  end
  if not restart(src) then return nil end
  require("src.core.Music").duckForCry(data, src)
  played("cry", species, species)
  return src
end

-- GROWL/ROAR are the only two moves that play a cry (IsCryMove checks
-- wAnimationID); GetMoveSound still adds their own MoveSoundTable pitch/
-- tempo bytes on top of the cry's species modifiers before the tempo
-- register is set (Audio2_SetSfxTempo: tempo9bit = wTempoModifier+$80).
-- $80 is the table's "no extra shift" tempo byte (every other move's
-- entry defaults to it), so the two moves' own bytes -- Growl's $c0,
-- Roar's $40 -- are the *extra* shift on top of whatever the species'
-- cry already sounds like. The generated cry source already includes the
-- species' pitch/tempo, so layer the move's extra shift on with
-- Source:setPitch (pitch mod is left unmodeled: both moves set it $00).
-- tempoMod 0 means "no data", not "shift by -128": the Gen2 importer fills
-- move.anim with a { sound = SFX_00, pitch = 0, tempo = 0 } placeholder
-- because it does not read MoveSoundTable, and treating that as a real byte
-- doubled the pitch of every Gen2 cry.  Only a genuine, non-default byte
-- shifts anything.
function Sound.playMoveCry(data, species, tempoMod)
  local src = Sound.playCry(data, species)
  if tempoMod == 0 then tempoMod = nil end
  if src and tempoMod and tempoMod ~= 0x80 then
    pcall(src.setPitch, src, 256 / (128 + tempoMod))
  end
  return src
end

-- is a previously played one-shot still sounding?  (ShakeElevator's
-- .musicLoop polls wChannelSoundIDs+CHAN5 until SFX_SAFARI_ZONE_PA
-- ends.)  Headless / never-played names read as silent.
function Sound.isPlaying(name)
  local src = cache[tostring(name)]
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  return ok and playing or false
end

-- cut a one-shot short (the SFX_STOP_ALL_MUSIC beats around the
-- elevator shake stop the last collision thud mid-ring)
function Sound.stop(name)
  local src = cache[tostring(name)]
  if src then pcall(src.stop, src) end
end

function Sound.anyPlaying(kind)
  for key,src in pairs(cache) do
    local cry=tostring(key):sub(1,4)=='cry:'
    if src and ((kind=='cry' and cry) or (kind=='sfx' and not cry)) then
      local ok,playing=pcall(src.isPlaying,src);if ok and playing then return true end
    end
  end
  return false
end

-- Looping sources (the low-health alarm): started/stopped by game
-- states. ChipAudio generates the two-tone siren used by runtime imports;
-- legacy data can still provide a looping static source.
local loopCache = {}
local looping = {}

function Sound.startLoop(data, name)
  if looping[name] then return end
  if not love.audio then return end
  -- INTERRUPTION: same cache-poisoning gate as playPath (sessionSuspended).
  -- BattleState calls this every frame the siren should be sounding, so
  -- returning here costs nothing: it restarts on the frame after the resume.
  if sessionSuspended then return end
  local sfx = data.audio and data.audio.sfx
  local def = sfx and sfx[name]
  local alarm = not def and name == "Low_Health_Alarm"
  if not def and not alarm then return end
  local src = loopCache[name]
  if src == false then return end
  if not src then
    local s, err
    if alarm then
      -- the synthesized siren is the default, not the rule: a registered
      -- Low_Health_Alarm def of any shape replaces it
      local ok, generated = pcall(require("src.core.ChipAudio").newLowHealthAlarm)
      if ok then s = generated else err = tostring(generated) end
    else
      s, err = newSfxSource(data, name, def)
    end
    if not s then
      loopCache[name] = false
      reportBadDef("sfx", name, owner(data, "sfx", name), err or "no source")
      return
    end
    safeAudio("Source:setLooping", s.setLooping, s, true)
    safeAudio("Source:setVolume", s.setVolume, s, volumeFor(name))
    loopCache[name] = s
    src = s
  end
  -- INTERRUPTION: if the device is gone the siren simply does not start and
  -- `looping` stays empty, so BattleState's per-frame startLoop retries it on
  -- the next frame (and Sound.resume has dropped the dead Source by then)
  if not safeAudio("Source:play", src.play, src) then return end
  looping[name] = src
end

function Sound.stopLoop(name)
  local src = looping[name]
  if src then
    pcall(src.stop, src)
    looping[name] = nil
  end
end

-- is a looping source currently sounding? (drivers assert on this)
function Sound.isLooping(name)
  return looping[name] ~= nil
end

-- 0-7 SFX volume level (0 mutes); cached sources (menu beeps, cries,
-- the low-health alarm loop) update immediately so the change is heard
-- on the next play
local function reapplyVolumes()
  for key, src in pairs(cache) do
    if src then pcall(src.setVolume, src, volumeFor(key)) end
  end
  for key, src in pairs(loopCache) do
    if src then pcall(src.setVolume, src, volumeFor(key)) end
  end
end

function Sound.setVolumeLevel(level)
  volumeScale = math.max(0, math.min(7, level or 7)) / 7
  reapplyVolumes()
end

-- 0-7 Pikachu-voice trim on top of the SFX level (7 = no trim, 0 mutes the
-- clips while the rest of the SFX bus keeps its level).  Yellow only: on
-- Red/Blue no cached key answers isPikaKey, so this is inert there.
function Sound.setPikaVolumeLevel(level)
  pikaScale = math.max(0, math.min(7, level or 7)) / 7
  reapplyVolumes()
end

-- hot reload / jukebox A-B: drop one key's sources (its pitch-tempo
-- variants included) or all of them, so the next play re-resolves the def
function Sound.invalidate(name)
  local function evict(store, key)
    local src = store[key]
    if src then pcall(src.stop, src) end
    store[key] = nil
  end
  for _, store in ipairs({ cache, loopCache }) do
    for key in pairs(store) do
      if not name or key == name or key:sub(1, #name + 1) == name .. "@" then
        evict(store, key)
      end
    end
  end
  for key, src in pairs(looping) do
    if not name or key == name then
      pcall(src.stop, src)
      looping[key] = nil
    end
  end
end

-- the flush fan-out calls with no key, dropping everything, so an edited
-- def is re-resolved on the next play (20 §2 cache contract, audio row)
Assets.register(Sound.invalidate)

-- ---------------------------------------------------------------------------
-- audio session suspend / resume (see sessionSuspended at the top)
-- ---------------------------------------------------------------------------

-- Driven by Music.suspend out of Game:focus / Game:visible, mobile only.
function Sound.suspend()
  if sessionSuspended then return end
  sessionSuspended = true
  -- A LOOPING source (the low-health siren, the link tournament theme) is the
  -- only kind that is still sounding when the call arrives.  Ask it to stop
  -- while the device may still take the call, and forget it, so its owner's
  -- per-frame startLoop restarts it on the way back instead of believing a
  -- dead Source is still playing.
  for key, src in pairs(looping) do
    safeAudio("Source:stop", src.stop, src)
    looping[key] = nil
  end
end

-- Sources built against the session the OS has just replaced are not reliably
-- usable again, and OpenAL offers nothing that answers "is this Source still
-- alive".  Dropping the cache is the only reliable answer: every def is
-- re-resolved and re-rendered the next time it is asked for, exactly as after
-- a hot reload.  This also clears the `false` "known bad" entries, so an
-- effect that failed to build during the interruption gets another chance
-- rather than staying silent for the rest of the session.
function Sound.resume()
  if not sessionSuspended then return end
  sessionSuspended = false
  Sound.invalidate()
end

-- re-apply persisted audio options (Game calls this on boot and after
-- loading a save)
function Sound.applyOptions(opts)
  Sound.setVolumeLevel(opts and opts.sfxVol or 7)
  Sound.setPikaVolumeLevel(opts and opts.pikaVol or 7)
end

return Sound
