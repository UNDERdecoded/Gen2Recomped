-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native station playback owns the map cue after leaving the radio. This
-- covers channel entry/exit; cartridge show-driven song changes are separate.
local Music = require("src.core.Music")
local M = {}
local SONGS = {
  OAKS_POKEMON_TALK = "Music_ProfOaksPokemonTalk",
  POKEDEX_SHOW = "Music_PokemonCenter",
  POKEMON_MUSIC = "Music_TitleScreen",
  LUCKY_CHANNEL = "Music_GameCorner",
  PLACES_AND_PEOPLE = "Music_ViridianCity",
  LETS_ALL_SING = "Music_Bicycle",
  ROCKET_RADIO = "Music_RocketTheme",
  POKE_FLUTE_RADIO = "Music_PokeFluteChannel",
  UNOWN_RADIO = "Music_RuinsOfAlphRadio",
  EVOLUTION_RADIO = "Music_LakeOfRageRocketRadio",
  BUENAS_PASSWORD = "Music_BuenasPassword",
}
M.FLUTE = SONGS.POKE_FLUTE_RADIO

function M.tune(game, station)
  if not require("src.core.GameVersion").isGen2() then return nil end
  local song = SONGS[station]
  local songs = game.data and game.data.audio and game.data.audio.songs
  Music.stop()
  if song and songs and songs[song] then
    Music.play(game.data, song)
    -- Observe the actual selected cue: an audio hook can replace/silence it,
    -- and a missing or failed Source must never manufacture flute playback.
    local current = Music.current()
    if current then return { song = current } end
  end
  return { restore = true }
end

function M.finish(game, playing)
  if not playing then return end
  if playing.restore and Music.current() == nil then
    Music.restoreMap(game.data)
  elseif Music.current() == playing.song then
    Music.setMapSong(playing.song)
  end
end

function M.snorlaxAwake(player)
  if Music.current() ~= M.FLUTE or not player then return false end
  local x, y = player.cellX, player.cellY
  return (x == 33 and y == 8) or (x == 34 and y == 10)
    or (x == 35 and y == 10) or (x == 36 and (y == 8 or y == 9))
end

return M
