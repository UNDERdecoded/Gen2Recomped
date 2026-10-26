-- Owned mod music files exercise actual native host adapters and shared music.
local M = {}
function M.install(root, backend, version, f, options)
  options = options or {}
  local native = backend == "gen1"
  local hardware = dofile(root .. "/tests/native_cry/fixture.lua").install(native, f)
  local Music = require("src.core.Music")
  Music.reload()
  local songs = {
    MUS_TITLE = { file = "owned-bgm-title.ogg" },
    MUS_CYCLING = { file = "owned-bgm-cycle.ogg" },
    MUS_SURF = { file = "owned-bgm-surf.ogg" },
  }
  if options.policy then
    for _, name in ipairs({
      "MUS_DESERT",
      "MUS_ABNORMAL_WEATHER",
      "MUS_ENCOUNTER_MAGMA",
      "MUS_MT_CHIMNEY",
      "MUS_ROUTE110",
      "MUS_ROUTE119",
    }) do
      songs[name] = { file = "owned-bgm-" .. name .. ".ogg" }
    end
  end
  local ids = version == "firered" and { 278, 282, 305 } or { 413, 403, 365 }
  local mapId = (version == "firered" and "FR_" or "EM_") .. "OWNED_BGM_MAP"
  f.data.maps = { [mapId] = { id = mapId, music = ids[1], mapType = 1 } }
  local world = { map = { id = mapId }, player = { cellX = 2, cellY = 3 }, npcs = {} }
  local savedRuntime, runtime, audio, savedAudio, selected, savedMod
  local space, savedStore, player, savedX, savedY
  if native then
    runtime = require("src.core.game3.runtime")
    savedRuntime = { session = runtime.session, game = runtime._game }
    runtime.session, runtime._game = { version = version, map = mapId, x = 2, y = 3 }, f.game
    local Song = require("src.core.game3.song_ids")
    selected = Song.current
    Song.select(version)
    audio = require("src.core.game3.audio")
    savedAudio = {}
    for key, value in pairs(audio) do
      if type(value) ~= "function" then
        savedAudio[key] = value
      end
    end
    audio._currentSong, audio._mapSong, audio._savedSong, audio._bgmSource = nil, ids[1], nil, nil
    audio._fadeOut, audio._fadeIn, audio._fanfareActive, audio._fanfareDeferred = nil, nil, false, nil
    local Mod = require("src.core.game3.mod_audio")
    savedMod = {}
    for key, value in pairs(Mod) do
      if type(value) ~= "function" then
        savedMod[key] = value
      end
    end
    Mod.install({ audio = { songs = songs } })
    audio.applyEngineOptions({ musicVol = 7, sfxVol = 7 })
    audio.playSong(ids[1])
    if options.policy then
      space = require("src.core.game3.scripting.space")
      savedStore, space.store = space.store, { flags = {}, vars = {} }
      player = require("src.core.game3.player")
      savedX, savedY = player.cellX, player.cellY
      require("src.core.game3.weather")
    end
  else
    f.data.audio.songs, f.data.audio.mapSongs = songs, { [mapId] = "MUS_TITLE" }
    Music.applyOptions({ musicVol = 7 })
    Music.playMap(f.data, mapId, false, false)
  end
  local sources, originalBuilder = {}, love.audio.newSource
  -- Initial source came from the actual startup above; retain all source
  -- records through the hardware trace rather than replacing music functions.
  love.audio.newSource = function(...)
    local source = originalBuilder(...)
    sources[#sources + 1] = source
    return source
  end
  local function resolve(label)
    if native then
      return audio.resolveSong(label)
    end
    return require("src.core.Gen3SongIds").resolve(label, version)
  end
  return {
    ids = ids,
    hardware = hardware,
    location = function(input)
      local id = native and (version == "firered" and "FR_" or "EM_") .. input.name
        or ("MAP_G%02d_N%02d"):format(input.group, input.number)
      f.data.maps[id] = {
        id = id,
        group = input.group,
        number = input.number,
        music = input.music,
        mapType = 1,
      }
      world.map, world.player.cellX, world.player.cellY = { id = id }, input.x or 2, 3
      if native then
        runtime.session.map, runtime.session.x, runtime.session.y = id, world.player.cellX, 3
        runtime.session.savedWeather = input.weather or 0
        player.cellX, player.cellY = world.player.cellX, 3
        space.store.flags, space.store.vars = {}, {}
        local Flags = require("src.core.game3.scripting.flags")
        for key, value in pairs(input.flags or {}) do
          Flags.setFlag(space.store, nil, key, value)
        end
        for key, value in pairs(input.vars or {}) do
          Flags.setVar(space.store, nil, key, value)
        end
      else
        f.game.save.gen3Weather = input.weather or 0
        f.game.save.gen3WeatherActive = input.activeWeather or 0
        f.game.save.flags, f.game.save.gen3Vars = {}, {}
        for key, value in pairs(input.flags or {}) do
          f.game.save.flags[("FLAG_G3_%04X"):format(key)] = value
        end
        for key, value in pairs(input.vars or {}) do
          f.game.save.gen3Vars[key] = value
        end
      end
    end,
    start = function(rows)
      local runner
      if native then
        local ir = {}
        for _, row in ipairs(rows) do
          local copy = { op = row[1] }
          for i = 2, #row do
            copy[i - 1] = row[i]
          end
          ir[#ir + 1] = copy
        end
        runner = require("src.core.game3.scripting.vm").new({
          scripts = { OWNED_BGM = ir },
          adapters = require("src.core.game3.scripting.adapters").host(nil, f.game, world),
        })
        assert(runner:start("OWNED_BGM"))
      else
        local code = assert(require("src.script.Gen3ScriptVM").compile({
          map_scripts = {
            source = "RomExtractorGen3",
            scripts = { OWNED_BGM = rows },
          },
        }, "OWNED_BGM"))
        runner = require("src.script.ScriptRunner").new(f.game, world)
        runner:run(code, { source = { modId = "portable_held_item", strict = true } })
      end
      return runner
    end,
    state = function()
      if native then
        local function copy(fade)
          if not fade then
            return nil
          end
          local out = {}
          for k, v in pairs(fade) do
            if k ~= "gen" then
              out[k] = v
            end
          end
          return out
        end
        return {
          song = audio._currentSong and audio._currentSong.id,
          mapSong = resolve(audio._mapSong),
          savedSong = audio._savedSong,
          currentMapMusic = audio.currentMapMusic(),
          fadeOut = copy(audio._fadeOut),
          fadeIn = copy(audio._fadeIn),
          deferred = audio._fanfareDeferred,
          physicalSong = Music.current(),
          voices = hardware.voices(),
        }
      end
      local state = assert(Music.nativeSnapshot())
      state.level = nil
      state.physicalSong = Music.current()
      state.voices = hardware.voices()
      return state
    end,
    update = hardware.update,
    tick = hardware.tick,
    trace = hardware.trace,
    options = function(level)
      local opts = type(level) == "table" and level or { musicVol = level, sfxVol = 7 }
      if native then
        audio.applyEngineOptions(opts)
      else
        Music.applyOptions(opts)
      end
    end,
    close = function()
      love.audio.newSource = originalBuilder
      if native then
        if space then
          space.store, player.cellX, player.cellY = savedStore, savedX, savedY
        end
        audio.stopAll()
        require("src.core.game3.mod_audio").reset()
        for key, value in pairs(audio) do
          if type(value) ~= "function" then
            audio[key] = nil
          end
        end
        for key, value in pairs(savedAudio) do
          audio[key] = value
        end
        local Mod = require("src.core.game3.mod_audio")
        for key, value in pairs(Mod) do
          if type(value) ~= "function" then
            Mod[key] = nil
          end
        end
        for key, value in pairs(savedMod) do
          Mod[key] = value
        end
        runtime.session, runtime._game = savedRuntime.session, savedRuntime.game
        require("src.core.game3.song_ids").select(selected)
      else
        Music.reload()
      end
      hardware.close()
    end,
  }
end
return M
