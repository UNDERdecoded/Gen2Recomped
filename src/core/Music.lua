-- Music playback supports compact ROM channel programs synthesized live by
-- ChipAudio, def-local chip programs (ChipAsm), and file definitions.  The
-- branch is chosen per song definition, never by a global import flag, so a
-- file-backed song and a chip song coexist in one dataset.  Songs with split
-- files chain def.file into def.loopFile in Music.update().
-- Map themes switch on map change; battles override with the battle
-- theme and restore afterwards; riding the bike overrides outdoor map
-- themes with the bike song until dismount.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local Music = {}

local VOLUME = 0.7

-- port additions driven by OptionsMenu / save.options: musicVol scales
-- VOLUME (0-7 level like the GB's NR50 master volume) and musicFilter
-- low-passes the song.  Each filter step keeps 40% of the previous
-- step's treble (highgain 0.4^level), so 2X/3X are the 1X filter
-- applied twice/three times over.
local volumeScale = 1
local FILTER_HIGHGAIN = { 0.4, 0.16, 0.064 }
local filterLevel = 0

-- Forward-declared here so applyVolume (below) closes over the real playback
-- state rather than a nil global: the table literal is assigned further down,
-- but a `local state = {}` there would leave every reference above it bound
-- to the global `state`.  Before this, registering the `music.volume` mod
-- hook crashed applyVolume on `state.current` (a nil index).
local state

-- Emerald's PlayCry_Normal (ROM:00A3400) does not pause the song for a cry
-- the way a fanfare does: it calls m4aMPlayVolumeControl on gMPlayInfo_BGM
-- with a volume of 85 out of the mixer's 256, holding the song down while
-- the cry sounds and restoring it after.  cryDuck carries that factor (the
-- extractor writes it as constants.gen3Cry.duckBgm/scale) and Music.update
-- clears it once the cry source has finished.
local cryDuck = nil

-- AUDIO SESSION SUSPEND / RESUME state (mobile interruption: an incoming
-- call).  Declared up here with the other module state because Music.stop --
-- defined well above the suspend/resume pair itself -- has to be able to
-- cancel a pending re-cue.  See the block above sourceStopped for the whole
-- story.
local sessionSuspended = false
local suspendedSong -- the label to re-cue on the way back, or nil

-- Re-cue retry budget after a resume: once a second for five seconds, ticked
-- from Music.update.  SDL blocks inside its event pump for the whole length
-- of an iOS call, so the background AND the foreground app events usually
-- arrive in ONE love.event.poll batch -- suspend and resume therefore run on
-- the same frame, which can be a beat before the OS has actually handed the
-- audio device back.  Long enough to cover that; short enough that a
-- genuinely broken def is not re-reported forever.
local RESUME_RETRY_FRAMES = 60
local RESUME_RETRY_TRIES = 5
local resumeRetry -- { song, wait, left } while a resume re-cue is still owed

-- THE DS SOUND PLAYER'S TWO LEVELS (Platinum's scripts): the BGM's own fade
-- level, which `fadeoutbgm` / `fadeinbgm` ramp over 60 Hz frames
-- (Sound_FadeOutBGM / Sound_FadeInBGM) and a new song resets, and the field
-- player's volume, which `setplayervolume` sets and which outlives songs
-- (NNS_SndPlayerSetPlayerVolume). Both multiply the option volume.
local dsLevel, dsPlayer, dsFade = 1, 1, nil

local function applyVolume(src)
  if not src then return end
  local vol = VOLUME * volumeScale * dsLevel * dsPlayer
  if cryDuck then vol = vol * cryDuck.scale end
  if Runtime.wantsHook("music.volume") then
    local ctx = {
      song = state.current,
      mapSong = state.mapSong,
      onBike = state.onBike,
      surfing = state.surfing,
      fading = state.fade ~= nil,
      optionScale = volumeScale,
    }
    local ok, Game = pcall(require, "src.core.Game")
    if ok and Game then
      local ow = Game.overworld
      if ow and ow.player then
        ctx.x, ctx.y = ow.player.cellX, ow.player.cellY
        ctx.mapId = ow.map and ow.map.id
        ctx.tod = ow.tod
      end
    end
    vol = Runtime.call("music.volume", function(v) return v end, vol, ctx)
    vol = tonumber(vol) or (VOLUME * volumeScale)
    if vol < 0 then vol = 0 end
  end
  pcall(src.setVolume, src, vol)
end

-- Source:setFilter needs OpenAL EFX; the pcall degrades to unfiltered
-- audio where it's missing (and under the headless stub)
local function applyFilter(src)
  if not src then return end
  if filterLevel > 0 then
    pcall(src.setFilter, src, { type = "lowpass", volume = 1,
                                highgain = FILTER_HIGHGAIN[filterLevel] })
  else
    pcall(src.setFilter, src)
  end
end

state = {
  current = nil,      -- song label
  chip = false,       -- the playing song is a synthesized channel program
  source = nil,       -- currently playing source
  loopSource = nil,   -- pre-loaded loop body waiting for the intro to end
  mapSong = nil,      -- song to restore after a battle
  onBike = false,     -- bike theme overrides outdoor map themes
  surfing = false,    -- surf theme likewise (home/audio.asm MUSIC_SURFING)
  pendingRestore = nil,
  fanfare = nil,      -- fanfare SFX source; the song pauses while it plays
  fanfareResume = false, -- start/resume state.source when the fanfare ends
  fade = nil,         -- active volume-ramp fade-out (see Music.fadeOut)
  failed = {},        -- labels whose def could not be started; logged once
}

-- Is a fanfare SFX (Sound.lua's FANFARES) still sounding?
local function fanfareActive()
  local src = state.fanfare
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  if ok and playing then return true end
  state.fanfare = nil
  require("src.core.ChipAudio").holdMusic(false)
  return false
end

-- Called by Sound.play when a fanfare starts: fanfares own the music
-- channels on the Game Boy, so the current song halts and resumes when
-- the jingle ends (see update()).
-- Called by Sound.playCry: unlike a fanfare, the song keeps playing and is
-- merely attenuated for as long as the cry sounds.
function Music.duckForCry(data, src)
  local c = data and data.constants and data.constants.gen3Cry
  local duck = c and tonumber(c.duckBgm)
  local scale = c and tonumber(c.scale)
  if not (duck and scale and scale > 0) then return end
  if duck >= scale then return end
  cryDuck = { src = src, scale = duck / scale }
  if not state.fade then
    applyVolume(state.source)
    applyVolume(state.loopSource)
  end
end

-- true while a cry is still holding the song down
local function cryDuckActive()
  if not cryDuck then return false end
  local src = cryDuck.src
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  return ok and playing
end

function Music.duckForFanfare(src)
  if not src then return end
  state.fanfare = src
  -- ChipAudio is what starts a chip song, so the pause below cannot hold one
  -- that has not started yet (nor one Music.play swaps in mid-jingle) (#398)
  require("src.core.ChipAudio").holdMusic(true)
  if state.source then
    local ok, playing = pcall(state.source.isPlaying, state.source)
    if ok and playing then
      pcall(state.source.pause, state.source)
      state.fanfareResume = true
    end
  end
end

-- Overworld themes where the bike can be ridden (outdoor maps plus the
-- caves/dungeons where gen-1 allows cycling).  Indoor themes such as
-- Pokecenter/Gym/SilphCo never get replaced by the bike theme.
-- data.audio.outdoorSongs supersedes this; the copy stays as the fallback
-- for caches built before the importer wrote the table.
local OUTDOOR = {
  Music_PalletTown = true,
  Music_Cities1 = true,
  Music_Cities2 = true,
  Music_Celadon = true,
  Music_Cinnabar = true,
  Music_Vermilion = true,
  Music_Lavender = true,
  Music_Routes1 = true,
  Music_Routes2 = true,
  Music_Routes3 = true,
  Music_Routes4 = true,
  Music_IndigoPlateau = true,
  Music_SafariZone = true,
  Music_Dungeon1 = true,
  Music_Dungeon2 = true,
  Music_Dungeon3 = true,
}

-- Scene themes the engine asks for by role rather than by label, so a total
-- conversion can rename every song.  data.audio.special supersedes this.
local SPECIAL = {
  heal = "Music_PkmnHealed",
  title = "Music_TitleScreen",
  credits = "Music_Credits",
  hallOfFame = "Music_HallOfFame",
  introBattle = "Music_IntroBattle",
  oakRoute = "Music_Routes2",
  bike = "Music_BikeRiding",
  surf = "Music_Surfing",
  evolution = "Music_SafariZone",
  -- PlayTrainerMusic's three encounter stings
  meetEvil = "Music_MeetEvilTrainer",
  meetFemale = "Music_MeetFemaleTrainer",
  meetMale = "Music_MeetMaleTrainer",
}

-- the label a scene role resolves to; call sites keep their own presence
-- guard on the resolved label
function Music.special(data, key)
  local special = data and data.audio and data.audio.special
  local label = special and special[key]
  if label ~= nil then return label end
  return SPECIAL[key]
end

local function outdoorSongs(data)
  return data and data.audio and data.audio.outdoorSongs or OUTDOOR
end

local function songDef(data, song)
  return data and data.audio and data.audio.songs and data.audio.songs[song]
end

-- which mod put this label in the registry, for attributed failure logs
local function songOwner(data, song)
  local owners = data and data.audio and data.audio._owners
  local songs = owners and owners.songs
  return songs and songs[song] or "base"
end

-- one log line, plus an entry in the loader's error feed when a mod owns the
-- def, so the manager's errors screen can flag that mod
local function reportBadDef(data, song, err)
  local who = songOwner(data, song)
  Logger.warn("audio: bad song def %q (mod %s): %s", song, who, tostring(err))
  Runtime.reportError(who,
    ("audio: bad song def %q: %s"):format(song, tostring(err)))
end

local function stopSource(src)
  if src then pcall(src.stop, src) end
end

local function newSource(file)
  local ok, src = pcall(love.audio.newSource, file, "stream")
  if ok and src then return src end
  return nil, ok and "no source" or tostring(src)
end

-- Build the new song's sources; the caller only tears the old song down
-- once this succeeded, so a broken def costs nothing but a log line.
-- Returns src, loopSrc, isChip -- or nil plus the reason.
local function startSong(data, def, wantLoop)
  -- A GEN 3 SONG IS NEITHER OF THE TWO SHAPES BELOW, and that is why Hoenn
  -- was silent.  It carries no chip program and no sound file: it carries
  -- track pointers and a voicegroup, and it is played by a sequencer over
  -- sampled instruments (src/core/M4ASynth.lua).  All 611 of them fell
  -- through to "no chip program and no file", got marked failed, and the
  -- region never made a sound.
  --
  -- The test is the song's own shape rather than the game's version: a mod
  -- that hands a Gen 1 game an M4A song is asking for the M4A player, and a
  -- Gen 3 dataset whose music image failed to import still has its chip and
  -- file defs answered by the branches below.
  if def.nds ~= nil then
    local ok, src = pcall(require("src.audio.NitroAudio").new, data, def)
    if ok and src then return src, nil, false end
    return nil, nil, nil, tostring(src)
  elseif type(def.tracks) == "table" and #def.tracks > 0 then
    local ok, src = pcall(
      require("src.core.ChipAudio").playMusic, data, def, wantLoop, "m4a")
    if ok and src then return src, nil, true end
    return nil, nil, nil, ok and "no source" or tostring(src)
  elseif def.chip or (def.address and def.bank) then
    local ok, src = pcall(
      require("src.core.ChipAudio").playMusic, data, def, wantLoop)
    if ok and src then return src, nil, true end
    return nil, nil, nil, ok and "no source" or tostring(src)
  elseif def.file then
    local src, err = newSource(def.file)
    if not src then return nil, nil, nil, err end
    -- a missing loop body degrades to the intro file alone
    local loopSrc = def.loopFile and newSource(def.loopFile) or nil
    return src, loopSrc, false
  end
  return nil, nil, nil, "no chip program and no file"
end

-- the single choke point every song choice passes through, so one hook
-- covers map themes, battle themes, jingles and scene music
local function selectSong(song, ctx)
  if not Runtime.wantsHook("music.select") then return song end
  return Runtime.call("music.select", function(chosen) return chosen end, song, {
    reason = ctx and ctx.reason or "direct",
    mapId = ctx and ctx.mapId,
    mapSong = state.mapSong,
    onBike = state.onBike,
    surfing = state.surfing,
    kind = ctx and ctx.kind,
    battleKind = ctx and ctx.kind,
    trainerId = ctx and ctx.trainerId,
  })
end

function Music.play(data, song, loop, ctx)
  if not song then return end
  if not love.audio then return end -- headless test stub
  song = selectSong(song, ctx)
  -- a hook may silence the cue outright, or swap in a label the dedupe
  -- below has to compare against
  if not song or song == state.current then return end
  local def = songDef(data, song)
  if not def or state.failed[song] then return end
  local wantLoop = loop ~= false
  local src, loopSrc, isChip, err = startSong(data, def, wantLoop)
  if not src then
    state.failed[song] = true
    reportBadDef(data, song, err)
    return
  end
  stopSource(state.source)
  stopSource(state.loopSource)
  -- a chip song holds the streaming source; ChipAudio.playMusic already
  -- swapped it when the new song is chip-backed too
  if state.chip and not isChip then require("src.core.ChipAudio").stopMusic() end
  state.fade = nil
  -- a new sequence starts at its full level; the player volume stays
  dsLevel, dsFade = 1, nil
  if loopSrc then
    -- intro plays once, then update() chains to the loop body
    -- (for one-shot jingles the body plays once and doesn't repeat)
    pcall(src.setLooping, src, false)
    pcall(loopSrc.setLooping, loopSrc, wantLoop)
    applyVolume(loopSrc)
    applyFilter(loopSrc)
  else
    pcall(src.setLooping, src, wantLoop)
  end
  applyVolume(src)
  applyFilter(src)
  -- a fanfare owns the music channels: hold the new song until it ends
  -- (update() starts it, like the paused-song resume)
  if fanfareActive() then
    state.fanfareResume = true
  else
    pcall(src.play, src)
  end
  local previous = state.current
  state.source, state.loopSource, state.chip = src, loopSrc, isChip
  state.current = song
  if Runtime.wants("music.started") then
    Runtime.emit("music.started", {
      song = song, previous = previous, chip = isChip,
      reason = ctx and ctx.reason or "direct",
    })
  end
end

-- the label of the song currently playing, or nil
function Music.current()
  return state.current
end

function Music.stop()
  local previous = state.current
  stopSource(state.source)
  stopSource(state.loopSource)
  require("src.core.ChipAudio").stopMusic()
  state.current, state.source, state.loopSource, state.fade = nil, nil, nil, nil
  state.chip = false
  state.pendingRestore = nil
  -- An explicit stop outranks a pending resume re-cue: whoever called this
  -- wants silence, and the retry in Music.update fires on a nil state.current
  resumeRetry = nil
  if previous and Runtime.wants("music.stopped") then
    Runtime.emit("music.stopped", { song = previous })
  end
end

-- hot reload: forget the failed defs and the playing label so the next cue
-- re-resolves against the freshly merged registries
function Music.reload()
  state.failed = {}
  Music.stop()
end

-- Ramp the current song's volume to silence, then stop it, mirroring the
-- Game Boy's audio fade-out (home/fade_audio.asm FadeOutAudio +
-- home/audio.asm's .fadeOut): rAUDVOL's master volume steps 7 -> 0 in
-- integer levels, one level every `control` frames, and the music stops
-- when it reaches 0.  `control` is the wAudioFadeOutControl value the ROM
-- writes (oak_speech.asm sets 10 at the shrink beat -> 7*10 = 70 frames
-- to silence).  Ticked once per frame from Music.update().
function Music.fadeOut(control)
  if not state.source then Music.stop() return end
  control = math.max(1, control or 10)
  state.fade = {
    control = control,
    counter = control,       -- frames until the next volume step
    level = 7,               -- current master-volume level (rAUDVOL nibble)
    from = VOLUME * volumeScale, -- level-7 (full) source volume
  }
end

-- the song a map should currently play, honoring the bike/surf overrides
local function effectiveMapSong(data, song)
  if not song or not outdoorSongs(data)[song] then return song end
  if state.onBike then
    local bike = Music.special(data, "bike")
    if bike and songDef(data, bike) then return bike end
  end
  if state.surfing then
    local surf = Music.special(data, "surf")
    if surf and songDef(data, surf) then return surf end
  end
  return song
end

-- overworld map theme; onBike/surfing override outdoor themes with the
-- bike/surf songs and restore the map theme when they end
function Music.playMap(data, mapId, onBike, surfing)
  local song = data and data.audio and data.audio.mapSongs
    and mapId and data.audio.mapSongs[mapId] or nil
  local nights = data and data.audio and data.audio.mapNightSongs
  if nights and nights[mapId] then
    local hour = tonumber(os.date('%H')) or 12
    if hour < 4 or hour >= 20 then song = nights[mapId] end
  end
  state.mapSong = song
  state.onBike = not not onBike
  state.surfing = not not surfing
  local play = effectiveMapSong(data, song)
  -- FieldBGM_PlayForMapHeader starts the map's BGM at its full level, so a
  -- script's fade-out does not carry silence onto a map with the same song
  if dsFade == nil and dsLevel < 1 then
    dsLevel = 1
    applyVolume(state.source)
    applyVolume(state.loopSource)
  end
  if play then Music.play(data, play, nil, { reason = "map", mapId = mapId }) end
end

-- toggle the surf override mid-map (starting/ending a surf)
function Music.setSurfing(data, surfing)
  state.surfing = not not surfing
  local play = effectiveMapSong(data, state.mapSong)
  if play then Music.play(data, play, nil, { reason = "map" }) end
end

-- battle themes; kind = "wild"|"trainer"|"gym"|"final"
function Music.playBattle(data, kind, trainerId)
  local b = data.audio and data.audio.battle
  if b then
    Music.play(data, b[kind] or b.wild, nil,
      { reason = "battle", kind = kind, trainerId = trainerId })
  end
end

-- victory theme (Music_DefeatedWildMon/Trainer/GymLeader): starts the
-- moment the win is decided and loops until the battle screen closes
-- (each Defeated* song ends in `sound_loop 0, .mainloop`); the battle's
-- finish() restores the map theme, like the overworld reload's
-- PlayDefaultMusicFadeOutCurrent.  Returns true if the theme started.
function Music.playVictory(data, kind, trainerId)
  local b = data.audio and data.audio.battle
  local jingle = b and b[kind .. "Win"]
  if jingle and songDef(data, jingle) then
    Music.play(data, jingle, nil,
      { reason = "victory", kind = kind, trainerId = trainerId })
    return true
  end
  return false
end

-- one-shot jingle (PkmnHealed, Jigglypuff's song): the map theme
-- resumes when it ends, via update()
function Music.playOnce(data, song)
  if not songDef(data, song) then return false end
  Music.play(data, song, false, { reason = "once" })
  -- play() can no-op (hook silence, failed def); only arm restore when
  -- the jingle actually became current
  if state.current ~= song then return false end
  state.pendingRestore = true
  return true
end

local function chipAwaitingFirstBuffer()
  return state.chip
     and require("src.core.ChipAudio").awaitingFirstBuffer()
end

-- is a playOnce jingle still in flight?  (AnimateHealingMachine's
-- .waitLoop2 / Mom heal / captain rub hold until MUSIC_PKMN_HEALED ends.)
-- pendingRestore stays set from playOnce until Music.update restores the
-- map theme, covering the threaded chip "empty QueueableSource" window
-- where Source:isPlaying is briefly false before the first buffer lands.
function Music.oneShotPlaying()
  return state.pendingRestore == true
end

function Music.restoreMap(data)
  state.current = nil
  state.pendingRestore = nil
  local play = effectiveMapSong(data, state.mapSong)
  if play then Music.play(data, play, nil, { reason = "map" }) end
end

-- Sound_FadeOutBGM / Sound_FadeInBGM: ramp the BGM's own level (0..1) to
-- `to` over `frames` 60 Hz frames; `from` starts it somewhere else first
-- (BGM_FADE_IN_TYPE_FROM_ZERO). Music.dsFading() is ScriptContext_IsSoundFadeFinished.
function Music.dsFade(to, frames, from)
  if from then dsLevel = from end
  frames = math.max(0, math.floor(tonumber(frames) or 0))
  if frames == 0 then dsLevel, dsFade = to, nil
  else dsFade = { from = dsLevel, to = to, frames = frames, left = frames } end
  applyVolume(state.source)
  applyVolume(state.loopSource)
end
function Music.dsFading() return dsFade ~= nil end
function Music.setPlayerLevel(level)
  dsPlayer = math.max(0, math.min(1, tonumber(level) or 1))
  applyVolume(state.source)
  applyVolume(state.loopSource)
end
function Music.dsLevels() return dsLevel, dsPlayer end

-- 0-7 music volume (0 mutes), applied to the playing song and the
-- queued loop body as well as everything played later
function Music.setVolumeLevel(level)
  volumeScale = math.max(0, math.min(7, level or 7)) / 7
  applyVolume(state.source)
  applyVolume(state.loopSource)
end

-- music low-pass filter level, 0 (OFF) to 3
function Music.setFilterLevel(level)
  filterLevel = math.max(0, math.min(3, level or 0))
  applyFilter(state.source)
  applyFilter(state.loopSource)
end

-- re-apply persisted audio options (Game calls this on boot and after
-- loading a save)
function Music.applyOptions(opts)
  require("src.core.ChipAudio").setStereo(opts and opts.stereo)
  Music.setVolumeLevel(opts and opts.musicVol or 7)
  Music.setFilterLevel(opts and opts.musicFilter or 0)
end

-- ---------------------------------------------------------------------------
-- AUDIO SESSION SUSPEND / RESUME (mobile interruption: an incoming call)
--
-- Reported from play: on iOS, taking a phone call crashed the game.  iOS
-- hands the audio session to the phone app for the length of the call and
-- gives the game a NEW one afterwards; SDL reports the transition as
-- SDL_APP_WILLENTERBACKGROUND / SDL_APP_DIDENTERBACKGROUND and LOVE delivers
-- it as love.focus(false) / love.visible(false), so Game:focus is the hook.
-- Android sends the same app events (and loses its GL context on top of it).
--
-- This pair is the policy; the two modules underneath hold the mechanism.
-- ChipAudio owns the streaming QueueableSource that is queued into on every
-- single frame -- the site that actually crashes -- and Sound owns the cached
-- one-shots.  Game:audioSession gates the whole thing on
-- Platform.detect().mobile, so on desktop, where alt-tab has always kept the
-- music playing, none of this runs.

function Music.suspend()
  if sessionSuspended then return end
  sessionSuspended = true
  resumeRetry = nil -- a fresh interruption outranks the last one's re-cue
  -- A one-shot jingle is not worth resuming: by the time the call ends the
  -- beat it was scoring is long over, and state.pendingRestore already means
  -- "put the map theme back when this ends", which is what resume then does.
  suspendedSong = (not state.pendingRestore) and state.current or nil
  require("src.core.ChipAudio").suspend()
  require("src.core.Sound").suspend()
  stopSource(state.source)
  stopSource(state.loopSource)
  -- Drop our handles here rather than in resume: these Sources belong to the
  -- session that is being taken away, and the next Music.update must not find
  -- them and start poking them.
  state.source, state.loopSource = nil, nil
  state.fanfare, state.fanfareResume = nil, false
  state.fade = nil
  state.chip = false
  -- ...and forget the label, or the re-cue in resume is deduped away by
  -- Music.play's `song == state.current` guard and the game comes back silent
  state.current = nil
end

function Music.resume(data)
  if not sessionSuspended then return end
  sessionSuspended = false
  require("src.core.ChipAudio").resume()
  require("src.core.Sound").resume()
  local song = suspendedSong
  suspendedSong = nil
  -- A def that failed to START during the interruption is not a bad def: the
  -- device was gone.  state.failed is a permanent "never try this label
  -- again" latch, so clear it, or one badly timed call silences a song for
  -- the rest of the session.
  state.failed = {}
  if state.pendingRestore then
    -- the jingle the call interrupted is over as far as the player is
    -- concerned; do what Music.update would have done when it ended
    Music.restoreMap(data)
  elseif song then
    -- loop = true unconditionally: the only non-looping songs are the
    -- one-shot jingles, and those took the branch above
    Music.play(data, song, true, { reason = "resume" })
    -- And if the device was still not ready on this exact frame, do not leave
    -- the label latched as bad -- the next map / battle cue must be free to
    -- try it again.  This is the one place where a failure is known to be the
    -- platform's fault rather than the def's.
    --
    -- ...and arm the retry, because on iOS there may BE no next cue.  SDL
    -- blocks inside its event pump for the whole call, so the background and
    -- foreground events usually land in one poll batch: this runs a frame or
    -- two before the OS hands the audio device back, the map has not changed,
    -- and nothing else would ever re-cue the theme.  Without the retry the
    -- game comes back permanently silent, which is the second-worst outcome
    -- after the crash.
    if state.current ~= song then
      state.failed[song] = nil
      resumeRetry = { song = song, wait = RESUME_RETRY_FRAMES,
                      left = RESUME_RETRY_TRIES }
    end
  end
end

local function sourceStopped(src)
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  return ok and not playing
end

-- call once per frame: chains a finished intro into its loop body and
-- restores the map theme after a one-shot jingle
function Music.update(data)
  if data and data.audio and data.audio.ndsArchive then require("src.audio.NitroAudio").update() end
  -- INTERRUPTION: the OS holds the audio session (an incoming call), every
  -- Source we had is gone, and Music.resume is what rebuilds them.  Nothing
  -- in here is worth doing against a device that is not there -- and the
  -- ChipAudio.update on the next line is the call that crashed.
  if sessionSuspended then return end
  -- The other half of the same case: the re-cue in Music.resume can land
  -- before the OS has handed the audio device back, and nothing else re-cues
  -- a map theme that never stopped being the map theme.  So the retry is
  -- ticked here, on the once-a-frame clock, and only while NOTHING is
  -- playing -- if the resume took, or the player crossed a seam and the new
  -- map cued its own theme, this must not fight it.
  if resumeRetry then
    if state.current ~= nil or resumeRetry.left <= 0 then
      resumeRetry = nil
    else
      resumeRetry.wait = resumeRetry.wait - 1
      if resumeRetry.wait <= 0 then
        resumeRetry.wait = RESUME_RETRY_FRAMES
        resumeRetry.left = resumeRetry.left - 1
        state.failed[resumeRetry.song] = nil
        Music.play(data, resumeRetry.song, true, { reason = "resume" })
      end
    end
  end
  if state.chip then require("src.core.ChipAudio").update() end
  -- restore the song's level once the cry that ducked it has finished
  if cryDuck and not cryDuckActive() then
    cryDuck = nil
    if not state.fade then
      applyVolume(state.source)
      applyVolume(state.loopSource)
    end
  end
  -- distance / indoor muffling mods re-apply volume every frame while
  -- subscribed; otherwise applyVolume only runs on song/option changes
  if Runtime.wantsHook("music.volume") and not state.fade then
    applyVolume(state.source)
    applyVolume(state.loopSource)
  end
  -- (the DS fade, ticked here: see dsLevel above)
  if dsFade then
    dsFade.left = dsFade.left - 1
    if dsFade.left <= 0 then dsLevel, dsFade = dsFade.to, nil
    else dsLevel = dsFade.to + (dsFade.from - dsFade.to) * dsFade.left / dsFade.frames end
    applyVolume(state.source)
    applyVolume(state.loopSource)
  end
-- volume ramp (Music.fadeOut): hold the current level for `control`
  -- frames, then drop one level (FadeOutAudio decrements both rAUDVOL
  -- nibbles when its counter reaches 0); at level 0 the music stops.
  if state.fade then
    local f = state.fade
    f.counter = f.counter - 1
    if f.counter <= 0 then
      f.counter = f.control
      f.level = f.level - 1
      if f.level <= 0 then
        state.fade = nil
        Music.stop()
        return
      end
      local vol = f.from * f.level / 7
      if state.source then pcall(state.source.setVolume, state.source, vol) end
      if state.loopSource then
        pcall(state.loopSource.setVolume, state.loopSource, vol)
      end
    end
    return
  end
  -- while a fanfare plays the song stays paused (a paused source reads
  -- as stopped, so the intro-chain/restore checks below must not run);
  -- when it ends, the song picks up where it left off
  if state.fanfare then
    if fanfareActive() then return end
    if state.fanfareResume and state.source then
      pcall(state.source.play, state.source)
    end
    state.fanfareResume = false
  end
  if state.chip and not state.fanfare then
    require("src.core.ChipAudio").ensureMusicPlaying()
  end
  if state.loopSource and sourceStopped(state.source) then
    local loopSrc = state.loopSource
    state.loopSource = nil
    state.source = loopSrc
    pcall(loopSrc.play, loopSrc)
  end
  -- do not treat "threaded source still waiting on its first buffer" as
  -- ended, or playOnce jingles get restored over before they can sound
  if state.pendingRestore and sourceStopped(state.source)
     and not state.loopSource and not chipAwaitingFirstBuffer() then
    Music.restoreMap(data)
  end
end

return Music
