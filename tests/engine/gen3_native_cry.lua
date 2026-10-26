package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Sound, V = require("src.core.Sound"), require("src.core.GameVersion")
local beforeVersion = V.get()
local expected = {
  silent = 0,
  ["no-pack"] = 64,
  ["mode-five"] = 10,
  ["mode-seven"] = 9,
  ["mode-eleven"] = 9,
  ["mode-twelve"] = 9,
  ["early-source-end"] = 2,
  ["zero-species"] = 64,
  ["old-unown-species"] = 64,
  ["unsupported-species"] = 64,
  consecutive = 16,
  ["consecutive-no-pack"] = 128,
  ["file-override"] = 3,
  ["string-override"] = 3,
  ["disabled-override"] = 64,
  ["disabled-after-native"] = 64,
}
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_cry_commands.lua").run(".", "gen2", version)
  T.eq(#rows, 33, "all native command, variable, mode, override and wait cases execute")
  for _, row in ipairs(rows) do
    T.eq(row.completed, expected[row.case] or 8, row.case .. " follows native completion timing")
    T.eq(row.frames[#row.frames].running, false, "completed cry releases the actual script runner")
    for _, frame in ipairs(row.frames) do
      T.eq(type(frame.finished), "boolean", "native completion stays boolean")
      T.eq(type(frame.running), "boolean", "native script status stays boolean")
    end
  end
  for _, speed in ipairs({ 1, 2, 10 }) do
    local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
    local hardware = dofile("tests/native_cry/fixture.lua").install(false, f)
    local Game, Fixed = require("src.core.Game"), require("src.core.FixedStep")
    local stack = require("src.core.StateStack")
    stack:init()
    local game = setmetatable({
      data = f.data,
      save = f.game.save,
      stack = stack,
      input = require("src.core.Input"),
      speedOverride = speed,
    }, { __index = Game })
    game.input:init()
    local ow = setmetatable(
      { npcs = { {}, {} }, player = { facing = "up" } },
      { __index = require("src.world.OverworldController") }
    )
    local runner = require("src.script.ScriptRunner").new(game, ow)
    local hookEvents, ended = {}, {}
    f.e.api.hooks:wrap("script.command", function(next, ctx, name, args)
      hookEvents[#hookEvents + 1] = { edge = "before", name = name }
      local result = next(ctx, name, args)
      hookEvents[#hookEvents + 1] = { edge = "after", name = name }
      return result
    end)
    f.e.api.events:on("script.ended", function(event)
      ended[#ended + 1] = {
        completed = event.completed,
        value = require("src.script.Gen3Commands").getVar(game.save, 0x4001),
      }
    end)
    local script = assert(require("src.script.Gen3ScriptVM").compile({
      map_scripts = {
        source = "RomExtractorGen3",
        scripts = {
          OWNED_GAME_CRY = {
            { "lockall" },
            { "setvar", 0x8004, 4 },
            { "setvar", 0x8005, 0 },
            { "playmoncry", 0x8004, 0x8005 },
            { "waitmoncry" },
            { "setvar", 0x4001, 1 },
            { "releaseall" },
            { "end" },
          },
        },
      },
    }, "OWNED_GAME_CRY"))
    local steps, completed, freezeBroken = 0, nil, false
    stack:push({
      update = function()
        hardware.tick(steps)
        if steps == 0 then
          runner:run(script, {
            source = {
              modId = "portable_held_item",
              mapId = "OWNED_CRY_MAP",
              hook = "native_cry",
              strict = true,
            },
          })
        else
          runner:update()
        end
        if
          runner:isRunning()
          and (not ow.gen3Locked or not ow.npcs[1].gen3ScriptFrozen or not ow.npcs[2].gen3ScriptFrozen)
        then
          freezeBroken = true
        end
        if require("src.script.Gen3Commands").getVar(game.save, 0x4001) == 1 then
          completed = completed or steps
        end
        steps = steps + 1
      end,
    })
    Fixed:init(function(dt)
      game:step(dt)
    end)
    for _ = 1, 70 do
      game:update(1 / 60)
    end
    T.eq(completed, 8, "actual game clock completes the native eight-frame owned cry")
    local snapshot = require("src.core.NativeCryPlayer").snapshot()
    T.check(
      snapshot.clock >= 70,
      "Game:update advances the independent real audio clock after script completion"
    )
    T.check(snapshot.clock < 80, "fast-forward cannot multiply the real audio clock after completion")
    T.eq(runner:isRunning(), false, "native cry returns through the real Game/state clocks")
    T.eq(freezeBroken, false, "field objects stay frozen throughout the yielding cry")
    T.eq(ow.gen3Locked, nil, "releaseall restores the field")
    for _, npc in ipairs(ow.npcs) do
      T.eq(npc.gen3ScriptFrozen, nil, "releaseall restores each NPC")
    end
    T.eq(runner.ctx.g3Locked, nil, "completed cry retains no input lock")
    T.eq(runner.ctx.source.mapId, "OWNED_CRY_MAP", "native cry retains source metadata")
    local entered, exited
    for i, event in ipairs(hookEvents) do
      if event.name == "g3_wait_cry" then
        if event.edge == "before" then
          T.eq(entered, nil, "wait hook enters once")
          entered = i
        else
          T.eq(exited, nil, "wait hook returns once")
          exited = i
        end
      end
    end
    T.check(entered and exited and entered < exited, "public hooks surround the yielding native cry wait")
    T.same(ended, { { completed = true, value = 1 } }, "one script-ended event follows the write")
    local latest = assert(Sound.playCry(f.data, "CHARMANDER"))
    local ownedState = require("src.core.NativeCryPlayer").snapshot()
    local isolated = assert(Sound.playCry(f.data, "CHARMANDER", { isolated = true, mode = 4 }))
    T.neq(latest, isolated, "isolated dex playback owns a fresh source")
    T.same(
      require("src.core.NativeCryPlayer").snapshot(),
      ownedState,
      "isolated playback leaves native wait state and controls intact"
    )
    local same = assert(Sound.playCry(f.data, "CHARMANDER"))
    T.neq(latest, same, "repeated native cries never rewind a playing source")
    T.eq(latest.input, same.input, "repeat playback reuses only immutable rendered PCM")
    Sound.stopCry()
    T.eq(same:isPlaying(), false, "stopCry stops the most recent native source")
    T.eq(latest:isPlaying(), true, "stopCry retains earlier overlapping sources")
    T.eq(isolated:isPlaying(), true, "stopCry does not stop independently owned dex playback")
    Sound.invalidate("cry:CHARMANDER")
    T.eq(latest:isPlaying(), false, "species invalidation releases old native voices")
    T.eq(isolated:isPlaying(), false, "species invalidation also releases device-bound isolated sources")
    local fresh = assert(Sound.playCry(f.data, "CHARMANDER"))
    T.neq(fresh.input, latest.input, "invalidation rebuilds cached native PCM")
    Sound.suspend()
    T.eq(fresh:isPlaying(), false, "session suspension stops native cries")
    T.eq(Sound.playCry(f.data, "CHARMANDER"), nil, "suspended playback cannot create a new source")
    Sound.resume()
    T.check(Sound.playCry(f.data, "CHARMANDER") ~= nil, "resumed session rebuilds the native source")
    Sound.invalidate()
    local originalSound = love.sound
    love.sound = nil
    T.eq(
      Sound.playCry(f.data, "CHARMANDER"),
      nil,
      "headless native playback does not require a SoundData device"
    )
    love.sound = originalSound
    T.eq(Sound.isCryFinished(), false, "headless playback retains the real recording's native duration")
    local wait, polls = Sound.waitCry(), 0
    repeat
      polls = polls + 1
    until wait()
    T.eq(polls, 8, "headless logic fallback follows recording length instead of the no-pack delay")
    Sound.invalidate()
    local originalAudio = love.audio
    love.audio = nil
    T.eq(Sound.playCry(f.data, "CHARMANDER"), nil, "native controls tolerate an unavailable output device")
    love.audio = originalAudio
    T.eq(Sound.isCryFinished(), false, "an absent output device does not skip the native wait")
    Sound.invalidate()
    local originalBuilder = love.audio.newSource
    love.audio.newSource = function()
      error("owned native-cry device-loss case")
    end
    T.eq(Sound.playCry(f.data, "CHARMANDER"), nil, "device loss is contained at the hardware boundary")
    love.audio.newSource = originalBuilder
    T.check(
      Sound.playCry(f.data, "CHARMANDER") ~= nil,
      "device recovery retries the cached PCM with a fresh source"
    )
    hardware.close()
    f.close()
  end
end
-- Exercise the unchanged structural importer and writer against owned bytes.
local count, wave = 388, 388 * 24
local bytes = {}
for i = 1, wave + 16 + 400 do
  bytes[i] = 0
end
local function put(offset, value, size)
  for i = 0, size - 1 do
    bytes[offset + i + 1] = math.floor(value / 256 ^ i) % 256
  end
end
for direction = 0, 1 do
  for index = 0, count - 1 do
    local at = (direction * count + index) * 12
    put(at, direction, 1)
    put(at + 1, 60, 1)
    put(at + 4, 0x08000000 + wave, 4)
  end
end
put(wave + 4, 8000 * 1024, 4)
put(wave + 12, 400, 4)
local chars = {}
for i, value in ipairs(bytes) do
  chars[i] = string.char(value)
end
local importer = require("src.import.RomExtractorGen3").new(table.concat(chars), "firered")
local order = {}
for i = 1, 412 do
  order[i] = "OWNED_" .. i
end
importer._constants = { speciesOrder = order }
importer:extractCries()
T.eq(importer._audio.gen3Cries.mapping, "native-species-v1", "import declares native mapping provenance")
T.eq(importer._audio.gen3Cries.species, 411, "all supported raw species receive their native cry")
for species, index in pairs({
  [1] = 0,
  [4] = 3,
  [251] = 250,
  [252] = 200,
  [276] = 200,
  [277] = 273,
  [280] = 270,
  [317] = 251,
  [411] = 387,
}) do
  T.eq(
    importer._audio.cries[order[species]].m4a,
    index,
    "structural importer retains native reorder " .. species
  )
end
T.eq(importer._audio.cries[order[412]], nil, "unsupported egg slot is not assigned an arbitrary cry")
T.check(
  love.filesystem.getInfo("data/generated/audio.lua") ~= nil,
  "actual writer stores the mapped registry in isolated test FS"
)
V.set(beforeVersion)
T.finish("native cry PCM, script/audio clocks, field ownership, isolated playback and mapping")
