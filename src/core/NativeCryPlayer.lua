-- Native GBA cry state is independent of the SE players and legacy cry cache.
local Player = {}
local clock, untilFrame, source, controls = 0, nil, nil, nil
local voices = {}
local rendered = setmetatable({}, { __mode = "k" })
local function sounding(src)
  if not src then
    return false
  end
  local ok, value = pcall(src.isPlaying, src)
  return ok and value and true or false
end
local function rawSpecies(data, species, options)
  if options.nativeSpecies ~= nil then
    return tonumber(options.nativeSpecies)
  end
  if type(species) == "number" then
    return species
  end
  for number, id in pairs(data and data.constants and data.constants.speciesOrder or {}) do
    if id == species then
      return number
    end
  end
end
function Player.finished()
  if untilFrame and clock >= untilFrame then
    return true
  end
  if source then
    return not sounding(source)
  end
  return untilFrame == nil or clock >= untilFrame
end
function Player.tick()
  clock = clock + 1
end
function Player.wait()
  local previous = clock
  return function()
    if Player.finished() then
      return true
    end
    if clock == previous then
      Player.tick()
    end
    previous = clock
    return Player.finished()
  end
end
function Player.play(data, species, options, legacy, volumeScale, mono)
  options = options or {}
  local audio = data and data.audio or {}
  local definition = audio.cries and audio.cries[species]
  local owner = audio._owners and audio._owners.cries and audio._owners.cries[species]
  local raw = rawSpecies(data, species, options)
  local nativeIndex = require("src.core.NativeCrySpecies").index(raw)
  local explicitIndex = type(definition) == "table" and tonumber(definition.m4a)
  local legacyIndex = raw and raw >= 277 and raw - 26 or nativeIndex
  local overridden = definition ~= nil
    and (
      owner ~= nil and owner ~= "base"
      or explicitIndex == nil
      or explicitIndex ~= nativeIndex and explicitIndex ~= legacyIndex
    )
  if overridden then
    local replacement = legacy()
    if not options.isolated then
      source = replacement
      untilFrame = not source and clock + 64 or nil
    end
    return replacement, true
  end
  local params = require("src.core.NativeCryPcm").params(
    options.mode,
    require("src.core.GameVersion").get(),
    options.volume
  )
  if not options.isolated then
    controls = params
  end
  if not (audio.gen3 and audio.gen3Cries and audio.gen3Cries.table and nativeIndex ~= nil) then
    if not options.isolated then
      untilFrame = clock + 64
    end
    return nil
  end
  local pan = options.pan and options.pan ~= 0 and require("src.core.NativeSoundPan").value(options.pan)
    or nil
  local outputMono = options.mono
  if outputMono == nil then
    outputMono = mono
  end
  local key = table.concat({
    nativeIndex,
    tostring(options.mode),
    tostring(options.volume),
    tostring(pan),
    outputMono and "m" or "s",
    require("src.core.GameVersion").get(),
  }, ":")
  local cache = rendered[data] or { count = 0 }
  rendered[data] = cache
  local hit = cache[key]
  local ok, sound, info = true, hit and hit.sound, hit and hit.info
  if not hit then
    ok, sound, info = pcall(require("src.core.M4ASynth").renderNativeCry, data, nativeIndex, {
      mode = options.mode,
      version = require("src.core.GameVersion").get(),
      volume = options.volume,
      pan = pan,
      mono = outputMono,
    })
    if ok and sound and info then
      if cache.count >= 24 then
        cache = { count = 0 }
        rendered[data] = cache
      end
      cache.count = cache.count + 1
      cache[key] = { sound = sound, info = info }
    end
  end
  if not ok or not info then
    if not options.isolated then
      untilFrame = clock + 64
    end
    return nil
  end
  if not options.isolated then
    source, untilFrame = nil, clock + info.frames
    require("src.core.Music").nativeCryStarted(params, options, Player.finished)
  end
  local result
  if sound and love.audio and love.audio.newSource then
    local made, src = pcall(love.audio.newSource, sound, "static")
    if made and src then
      pcall(src.setVolume, src, volumeScale)
      local played = pcall(src.play, src)
      if played then
        result = src
        if not options.isolated then
          source = src
        end
        local active = {}
        for _, entry in ipairs(voices) do
          if sounding(entry.source) then
            active[#active + 1] = entry
          end
        end
        voices = active
        voices[#voices + 1] = { source = src, species = species }
      end
    end
  end
  return result
end
function Player.stop()
  if source then
    pcall(source.stop, source)
  end
  source, untilFrame = nil, nil
  require("src.core.Music").nativeCryStopped()
end
function Player.invalidate(name)
  rendered = setmetatable({}, { __mode = "k" })
  local retained = {}
  local cleared = false
  for _, entry in ipairs(voices) do
    if not name or name == "cry:" .. tostring(entry.species) then
      pcall(entry.source.stop, entry.source)
      if entry.source == source then
        source, untilFrame, cleared = nil, nil, true
      end
    else
      retained[#retained + 1] = entry
    end
  end
  voices = retained
  if not name then
    source, untilFrame, cleared = nil, nil, true
  end
  if cleared then
    require("src.core.Music").nativeCryStopped()
  end
end
function Player.snapshot()
  local params = {}
  for key, value in pairs(controls or {}) do
    params[key] = value
  end
  return { clock = clock, untilFrame = untilFrame, finished = Player.finished(), controls = params }
end
return Player
