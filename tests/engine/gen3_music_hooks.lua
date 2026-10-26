package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local before = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_bgm_hooks.lua").run(".", "gen2", version)
  T.eq(#rows, 23, "every public music hook, event and ownership scenario executes")
  local byName = {}
  for _, row in ipairs(rows) do
    byName[row.case] = row
    if row.case:sub(1, 6) == "native" then
      T.eq(#row.calls, 0, "native carriers do not enter shared mod music hooks or events")
      for _, frame in ipairs(row.frames) do
        T.eq(
          frame.producer,
          version == "firered" and 282 or 403,
          "a shared selection/volume wrapper cannot replace or silence the actual native producer"
        )
      end
    end
    for _, call in ipairs(row.calls) do
      if call.context then
        T.eq(call.context.mapSong, nil, "native map identities cannot leak into the shared music context")
        T.eq(call.context.onBike, false, "shared music retains the generic player's bike context")
        T.eq(call.context.surfing, false, "shared music retains the generic player's surf context")
        if call.name == "music.volume" then
          T.eq(call.context.fading, false, "a native fade does not become a generic music fade")
          T.check(
            call.context.song == nil or call.context.song == "MUS_CYCLING" or call.context.song == "MUS_SURF",
            "the volume hook observes the shared physical song"
          )
          if row.case == "file-location" then
            T.eq(call.context.x, 5, "volume context reads the actual engine world's x")
            T.eq(call.context.y, 6, "volume context reads the actual engine world's y")
            T.eq(call.context.mapId, "OWNED_HOOK_MAP", "volume context preserves the actual engine map")
            T.eq(call.context.tod, "night", "volume context preserves time of day")
          end
        end
      end
    end
  end
  local swapped
  for _, call in ipairs(byName["file-select"].calls) do
    if call.name == "music.started" then
      swapped = call.event.song
    end
  end
  T.eq(swapped, "MUS_SURF", "the public selector changes the actual shared music cue")
  T.eq(
    #byName["file-silence"].calls,
    1,
    "a nil selector returns before source construction and started events"
  )
  for _, frame in ipairs(byName["file-silence"].frames) do
    for _, source in ipairs(frame.state.voices) do
      T.eq(source.playing, false, "a silenced shared cue cannot leave a source playing")
    end
  end
  local voices = byName["file-volume"].frames[1].state.voices
  T.eq(voices[#voices].volume, 0.35, "the volume wrapper scales the actual shared Source")
  local changes = {}
  for _, call in ipairs(byName["file-options"].calls) do
    if call.tick == 2 then
      changes[#changes + 1] = call.result
    end
  end
  T.same(
    changes,
    { 0.7, 0.3, 0.3 },
    "options reapply the stored level, new level and regular audio service in order"
  )
  changes = {}
  for _, call in ipairs(byName["file-options-out"].calls) do
    if call.tick == 2 then
      changes[#changes + 1] = call
    end
  end
  T.eq(#changes, 4, "options during a native fade retain all four public volume observations")
  T.eq(
    changes[1].context.optionScale,
    62 / 64,
    "the option preflight observes the actual previous fade level"
  )
  local order = {}
  for _, call in ipairs(byName["file-fanfare"].calls) do
    if call.tick == 5 then
      order[#order + 1] = call.name
    end
  end
  T.same(
    order,
    { "music.volume", "music.stopped", "music.select", "music.volume", "music.started" },
    "fanfare completion follows the old shared update before replacing its source"
  )
  local deferred = byName["file-map-fanfare"].frames
  local cycling = version == "firered" and 282 or 403
  local title = version == "firered" and 278 or 413
  T.eq(
    deferred[3].state.deferred,
    cycling,
    "a map cue defers its shared song while the fanfare owns the clock"
  )
  T.eq(deferred[6].state.song, title, "map ownership cannot switch before the fanfare timer completes")
  T.eq(deferred[7].state.song, cycling, "the completed fanfare starts the pending map cue")
  for _, name in ipairs({ "file-cry", "file-cry-stop" }) do
    local row = byName[name]
    T.eq(row.crySamples, 5645, "native world cry commands render the real owned PCM")
    T.eq(#row.calls, 22, "native cry start/end/stop cannot add shared music volume callbacks")
    local entered = 0
    for _, call in ipairs(row.calls) do
      if call.tick == 2 then
        entered = entered + 1
      end
    end
    T.eq(entered, 1, "the cry start tick contains only the normal shared audio-service callback")
  end
end
V.set(before)
T.finish("native/shared public music hooks, option order and map fanfare ownership")
