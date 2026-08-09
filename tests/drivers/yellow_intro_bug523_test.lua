-- Manual check that the Yellow intro now runs long enough for
-- Music_YellowIntro's descending run and long final note to be audible
-- before title.asm's unconditional StopAllMusic swaps in the title theme
-- (#523). Never taps a button: Game:load() already pushed YellowIntro,
-- so this driver only watches it play out at real, unaccelerated speed.
-- POKEPORT_SPEED must stay unset -- Music runs on its own real-time 60Hz
-- accumulator (Game:update), decoupled from the fast-forwardable logic
-- clock, so speeding up the driver would desync the exact ordering under
-- test here instead of just playing it back faster.
--   POKEPORT_DRIVER=tests/drivers/yellow_intro_bug523_test.lua POKEPORT_IDENTITY=bug523 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Music = require("src.core.Music")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  check("booted into a state (Yellow intro, per bootScreens)",
        game.stack:top() ~= nil)

  if game.save and game.save.options and game.save.options.musicVol == 0 then
    U.log("FAIL musicVol is 0 -- turn it up, this run is silent by design")
  end

  local sawIntroSong = false
  local sawTitleSong = false

  -- Music.lua keeps the current song in a module-local `state` table with
  -- no public getter, so watch the one seam that is public: wrap Music.play
  -- itself for the life of this driver and log what it's handed. Both the
  -- YellowIntro:beginScenes() pcall and title.asm's StopAllMusic-then-
  -- PlaySound land here.
  local frame = 0
  local originalPlay = Music.play
  Music.play = function(data, song, loop, ctx)
    if song and song:find("Intro") and not sawIntroSong then
      sawIntroSong = true
      U.log("Music_YellowIntro started")
    end
    if song == "Music_TitleScreen" and not sawTitleSong then
      sawTitleSong = true
      U.log("Music_TitleScreen started")
    end
    return originalPlay(data, song, loop, ctx)
  end

  -- 40s ceiling counted from driver start, not from the intro song: roughly 500 frames of
  -- boot and bootScreens run before Music_YellowIntro begins, and the title swap lands
  -- around frame 1680 (28s), so a 20s ceiling expired before the moment under test (#523).
  while frame < 40 * 60 and not sawTitleSong do
    frame = frame + 1
    coroutine.yield()
  end

  check("Music_YellowIntro started", sawIntroSong)
  check("the movie reached the title screen and Music_TitleScreen took over",
        sawTitleSong)

  U.log("Listen for Music_YellowIntro's ending: a short descending run of")
  U.log("notes (F#, F, F#...F#, E, D#, C#) followed by one long low note,")
  U.log("right before the title theme cuts in. Before #523 the swap landed")
  U.log("early and those descending notes never played -- the track just")
  U.log("stopped mid-phrase. The swap itself is still an abrupt cut by")
  U.log("design (pokeyellow's title.asm stops the intro song unconditionally,")
  U.log("it never waits for it to finish); what changed is how much of the")
  U.log("track plays before that cut lands.")

  while true do
    coroutine.yield()
  end
end
