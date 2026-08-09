-- Gen2 audio: every song, SFX and cry header in the extracted tables must
-- decode with the gen2 dialect and render audible PCM.
local U = require("tests.drivers.util")

return function(game)
  local ChipSynth = require("src.core.ChipSynth")
  local Music = require("src.core.Music")
  local data = game.data
  local audio = data.audio
  local pass, fail = 0, 0

  local function check(name, ok, detail)
    if ok then
      pass = pass + 1
    else
      fail = fail + 1
      U.log(("FAIL %s%s"):format(name, detail and (" -- " .. detail) or ""))
    end
  end

  check("runtime audio", audio.runtime == true, tostring(audio.runtime))
  check("gen2 flag", audio.gen2 == true)
  check("programs.bin", love.filesystem.getInfo(audio.programFile) ~= nil,
        tostring(audio.programFile))
  check("wave table", audio.waveBanks and audio.waveBanks.gen2 ~= nil)
  check("drumkits", audio.drumkits and audio.drumkits.gen2 ~= nil)

  -- one full song: New Bark Town is three channels in the ROM header
  local newBark = audio.songs.Music_NewBarkTown
  check("Music_NewBarkTown present", newBark ~= nil)
  if newBark then
    local ok, engine = pcall(ChipSynth.newEngine, data, newBark,
                             { allowLoops = false })
    check("Music_NewBarkTown engine", ok, tostring(engine))
    if ok then
      check("Music_NewBarkTown channels", #engine.channels == 3,
            tostring(#engine.channels))
      local peak = 0
      for _ = 1, 44100 * 2 do
        local value = engine:sample()
        if value < 0 then value = -value end
        if value > peak then peak = value end
      end
      check("Music_NewBarkTown audible", peak > 0.02, tostring(peak))
    end
  end

  -- every song header must at least build an engine with channels
  local songFails, songCount = {}, 0
  for name, def in pairs(audio.songs) do
    songCount = songCount + 1
    local ok, engine = pcall(ChipSynth.newEngine, data, def,
                             { allowLoops = false })
    if not ok or #engine.channels == 0 then
      songFails[#songFails + 1] = name .. ": " .. tostring(engine)
    end
  end
  check(("all %d songs build"):format(songCount), #songFails == 0,
        songFails[1])

  -- SFX and cries render to non-empty buffers
  local sfxFails, sfxCount = {}, 0
  for name, def in pairs(audio.sfx) do
    sfxCount = sfxCount + 1
    local ok, sound = pcall(ChipSynth.renderEffectData, data, def,
                            { frequencyOffset = 0, frameTicks = 0x100 })
    if not ok or not sound then
      sfxFails[#sfxFails + 1] = name .. ": " .. tostring(sound)
    end
  end
  check(("all %d sfx render"):format(sfxCount), #sfxFails == 0, sfxFails[1])

  local cryFails, cryCount = {}, 0
  for species, cry in pairs(audio.cries) do
    cryCount = cryCount + 1
    local ok, sound = pcall(ChipSynth.renderEffectData, data, cry.header,
                            { frequencyOffset = cry.pitch,
                              cryLength = cry.length })
    if not ok or not sound then
      cryFails[#cryFails + 1] = species .. ": " .. tostring(sound)
    end
  end
  check(("all %d cries render"):format(cryCount), #cryFails == 0, cryFails[1])

  -- map themes and the roles the engine asks for by name
  check("NEW_BARK_TOWN theme",
        audio.mapSongs.NEW_BARK_TOWN == "Music_NewBarkTown",
        tostring(audio.mapSongs.NEW_BARK_TOWN))
  check("outdoor set has New Bark Town",
        audio.outdoorSongs.Music_NewBarkTown == true)
  check("outdoor set excludes Pokecenter",
        audio.outdoorSongs.Music_PokemonCenter ~= true)
  for _, role in ipairs({ "wild", "trainer", "gym", "final",
                          "wildWin", "trainerWin", "gymWin" }) do
    local song = audio.battle[role]
    check("battle." .. role, song ~= nil and audio.songs[song] ~= nil,
          tostring(song))
  end
  for _, role in ipairs({ "heal", "title", "credits", "hallOfFame",
                          "bike", "surf", "evolution" }) do
    local song = Music.special(data, role)
    check("special." .. role, song ~= nil and audio.songs[song] ~= nil,
          tostring(song))
  end

  -- the gen-1 labels the port's call sites still use must resolve
  for _, name in ipairs({ "Press_AB", "Collision", "Get_Item1", "Heal_HP",
                          "Ball_Poof", "Cut", "Ledge_Jump", "Wrong" }) do
    check("alias " .. name, audio.sfx[name] ~= nil)
  end

  -- script ops address music and SFX by table index
  check("musicIndex", audio.musicIndex["60"] == "Music_NewBarkTown",
        tostring(audio.musicIndex["60"]))
  check("sfxIndex", audio.sfxIndex["4"] == "Sfx_Potion",
        tostring(audio.sfxIndex["4"]))

  -- the script commands themselves: `playmusic MUSIC_NEW_BARK_TOWN`,
  -- `musicfadeout`, `playmapmusic` and `playsound`
  U.newGame(game)
  U.teleport(game, "NEW_BARK_TOWN", 4, 6)
  local ow = game.stack:top()
  local ctx = { game = game, overworld = ow }
  local Cmd = require("src.script.Commands")
  require("src.script.Gen2Commands")

  Cmd.g2_music(ctx, 1)
  check("g2_music plays the title theme",
        Music.current() == "Music_TitleScreen", tostring(Music.current()))
  Cmd.g2_mapmusic(ctx)
  check("g2_mapmusic restores the map theme",
        Music.current() == "Music_NewBarkTown", tostring(Music.current()))
  Cmd.g2_musicfade(ctx, 47, 8)
  check("g2_musicfade swaps the song",
        Music.current() == "Music_ChampionBattle", tostring(Music.current()))
  Cmd.g2_music(ctx, 0)
  check("MUSIC_NONE stops the music", Music.current() == nil,
        tostring(Music.current()))
  Cmd.g2_keepmusic(ctx)
  check("g2_keepmusic sets the no-map-music bit", ow.keepMusicOnce == true)
  check("g2_sfx runs", pcall(Cmd.g2_sfx, ctx, 4))
  check("g2_sfx_name runs", pcall(Cmd.g2_sfx_name, ctx, "Sfx_EnterDoor"))
  -- Script_playsound 27 is the wall opening in the Ruins of Alph
  check("Sfx id 27 resolves", audio.sfxIndex["27"] ~= nil,
        tostring(audio.sfxIndex["27"]))

  U.log((("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail)))
  love.event.quit()
end
