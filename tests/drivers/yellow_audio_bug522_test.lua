-- Manual check that Yellow's bank $1f music headers, wave table and cry
-- data read from the right ROM addresses (#522). Before the fix every
-- header past Music_YellowIntro (a 3-channel header where Red's
-- Music_IntroBattle was 4) was read 3 bytes off, so Viridian Forest's
-- Music_Dungeon2 lost 3 of its 4 channels and its tempo command; every
-- song's channel 3 sampled engine code instead of a wave table.
--   POKEPORT_DRIVER=tests/drivers/yellow_audio_bug522_test.lua POKEPORT_IDENTITY=bug522 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ChipSynth = require("src.core.ChipSynth")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local audio = game.data.audio or {}
  local header = audio.musicHeaders and audio.musicHeaders.Music_Dungeon2

  -- pokeyellow.sym: Music_Dungeon2 = 1f:42a9 (bank 31, address 17065)
  check("Music_Dungeon2 header reads pokeyellow.sym's address",
        header and header.address == 17065 and header.bank == 31)

  -- pokeyellow.sym: CryData = 0e:5462 (bank 14, address 21602)
  local cry = audio.cryData
  check("cryData reads pokeyellow.sym's CryData",
        cry and cry.address == 21602 and cry.bank == 14)

  -- pokeyellow only has one wave table, Audio1_WavePointers.wave0 = 02:5a26
  local waves = audio.waveBanks or {}
  local waveOk = true
  for _, engine in ipairs({ "1", "2", "3" }) do
    local w = waves[engine]
    if not (w and w.address == 23078 and w.bank == 2) then waveOk = false end
  end
  check("all three waveBanks point at Audio1_WavePointers.wave0", waveOk)

  -- Rebuild the engine exactly as ChipAudio does and count the channels a
  -- misread header would drop to 1 (see headerChannels, ChipSynth.lua).
  local engine, engErr
  if header then
    local ok
    ok, engine = pcall(ChipSynth.newEngine, game.data, header)
    if not ok then engErr = engine; engine = nil end
  end
  check("Music_Dungeon2 engine builds" .. (engErr and (": " .. tostring(engErr)) or ""),
        engine ~= nil)
  check("Music_Dungeon2 has all 4 channels, not the misread header's 1",
        engine and #engine.channels == 4)

  -- Ch1 opens with the tempo command (dungeon2.asm "Music_Dungeon2_Ch1::
  -- tempo 144"); a header pointed at the wrong row drops it and the engine
  -- is left at the 0x100 default, ~1.78x slower.
  if engine and engine.channels[1] then
    engine.channels[1]:nextEvent()
  end
  check("Ch1's tempo command set engine.tempo to 144, not the 0x100 default",
        engine and engine.tempo == 144)

  -- pokered data/maps/objects/ViridianForest.asm: the south gate warps land
  -- around (16-18, 47); one step north of that is inside the forest proper.
  local MAP = "VIRIDIAN_FOREST"
  local STAND = { x = 16, y = 46, facing = "up" }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)

  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    local function nearestWalkable()
      for dy = -3, 3 do
        for dx = -3, 3 do
          local cx, cy = STAND.x + dx, STAND.y + dy
          if ow.map:isWalkableCell(cx, cy) then return cx, cy end
        end
      end
      return nil
    end
    local cx, cy = nearestWalkable()
    if cx then
      U.log("start cell blocked, standing at", cx, cy, "instead")
      U.teleport(game, MAP, cx, cy, "up")
    end
  end

  if game.save and game.save.options and game.save.options.musicVol == 0 then
    U.log("FAIL musicVol is 0 -- turn it up, this run is silent by design")
  end

  U.log("Standing in Viridian Forest; Music_Dungeon2 is playing now.")
  U.log("Right: four voices at a brisk clip -- lead melody, a counter line")
  U.log("underneath it, a soft rounded bass, and a hi-hat tick on top.")
  U.log("Wrong (the bug): one thin lonely voice at a noticeably slower,")
  U.log("draggy tempo, with no bass or hi-hat at all.")
  U.log("Also listen to that bass note's timbre -- it should be a soft")
  U.log("rounded triangle-ish tone, not a harsh buzzy rasp (waveBanks).")

  while true do
    coroutine.yield()
  end
end
