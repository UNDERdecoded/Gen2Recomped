-- Native producers, observed through a sandboxed mod loaded by the real SDK.
-- Do not emit these events from the test: a missing call site must fail here.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
local GameVersion = require("src.core.GameVersion")
local Overworld = require("src.world.OverworldController")
local BirchSpeech = require("src.ui.BirchSpeech")
local Gen4Battle = require("src.battle.Gen4Battle")
local Pokemon = require("src.pokemon.Pokemon")

local savedVersion = GameVersion.get()
local savedGame = {}
for _, key in ipairs({ "data", "save", "stack", "input", "overworld", "world", "renderer" }) do
  savedGame[key] = { Game[key] }
end
GameVersion.set("red")
local data = T.fixtures.fresh()
local run = T.sdk.loadMods(
  { "mods/seam_probe" },
  {
    data = data,
    fs = T.sdk.memfs({
      ["mods/seam_probe/manifest.json"] = [[{
    "id":"seam_probe", "name":"Native seam probe", "version":"1.0.0",
    "api":2, "entry":"main.lua", "affects_link":false
  }]],
      ["mods/seam_probe/main.lua"] = [[
    local mod = ...
    local seen = {}
    mod.exports.seen = seen
    local names = {
      "intro.birch_speech.started", "intro.birch_speech.finished",
      "pokemon.egg_hatched", "world.blocks_replaced", "world.tick",
    }
    for _, name in ipairs(names) do
      seen[name] = {}
      mod.events:on(name, function(payload)
        local events = seen[name]
        events[#events + 1] = payload
      end)
    end
    mod.exports.hideHUD = true
    mod.exports.hudCalls = 0
    mod.hooks:wrap("battle.status_hud_visible", function(nextFn, battle)
      mod.exports.hudCalls = mod.exports.hudCalls + 1
      mod.exports.battle = battle
      if mod.exports.hideHUD then return false end
      return nextFn(battle)
    end)
  ]],
    }),
  }
)
T.eq(#run.errors, 0, "the public-API probe loads without errors")
local exports = assert(run.loader.exports.seam_probe)
local seen = exports.seen
local stack = { states = {} }
function stack:push(state)
  self.states[#self.states + 1] = state
end
function stack:pop()
  return table.remove(self.states)
end
function stack:top()
  return self.states[#self.states]
end
Game.data, Game.stack = data, stack
Game.save = { player = { map = "FIX_TOWN", name = "TEST", id = 123 }, options = {} }
Game.input = {
  wasPressed = function()
    return false
  end,
  isDown = function()
    return false
  end,
}
Game.renderer = {
  worldViewSize = function()
    return 160, 144
  end,
}

-- enter() establishes the native module's Game reference and real runner.
-- Map loading is the ROM/graphics boundary; provide a tiny idle map there.
local map = {
  id = "FIX_TOWN",
  def = { width = 2, height = 2 },
  blockPatch = {},
  renderer = {
    rebuilds = 0,
    rebuild = function(self)
      self.rebuilds = self.rebuilds + 1
    end,
  },
  warpAtCell = function()
    return nil
  end,
}
function map:blockAt(bx, by)
  return self.blockPatch[by * 2 + bx + 1] or 0
end
local world = setmetatable({
  setMap = function(self)
    self.map = map
    self.player = {
      cellX = 0,
      cellY = 0,
      px = 0,
      py = 0,
      update = function()
        return false
      end,
    }
    self.npcs, self.ghosts, self.entities, self.cast = {}, {}, {}, {}
  end,
}, { __index = Overworld })
world:enter("FIX_TOWN", 0, 0, "down")

-- Birch start and finish reach subscribers at their real lifecycle boundary.
GameVersion.set("emerald")
data.constants.gen3Intro = { lines = { "WELCOME", "WORLD", "PLAYER", "GENDER" } }
data.text.WELCOME, data.text.GENDER = "Welcome!", "Boy or girl?"
local done = false
local speech = BirchSpeech.new(Game, function()
  done = true
end)
stack:push(speech)
speech:enter()
T.eq(#seen["intro.birch_speech.started"], 1, "enter publishes one Birch start")
T.eq(seen["intro.birch_speech.started"][1].speech, speech, "start identifies the live speech")
T.check(stack:top() ~= speech, "start advances into the first real text box")
stack:pop()
speech.answers = { name = "TEST", gender = "girl" }
speech:finish()
T.eq(#seen["intro.birch_speech.finished"], 1, "finish publishes one Birch completion")
local finished = seen["intro.birch_speech.finished"][1]
T.eq(finished.speech, speech, "finish identifies the same speech")
T.eq(finished.answers, speech.answers, "finish carries the recorded answers")
T.check(done and #stack.states == 0, "finish then closes the speech and calls its continuation")

-- Batch block changes publish only actual writes, clipped to map dimensions.
GameVersion.set("red")
T.eq(world:replaceBlocks({ 1, 0, 2, 0, 99 }), true, "native batch changes map blocks")
T.eq(#seen["world.blocks_replaced"], 1, "batch emits one event")
T.eq(seen["world.blocks_replaced"][1].mapId, "FIX_TOWN", "batch reports the map")
T.eq(seen["world.blocks_replaced"][1].count, 2, "batch counts changed cells only")
T.eq(map.blockPatch[1], 1, "first block is written")
T.eq(map.blockPatch[3], 2, "second changed block is written")
T.eq(map.blockPatch[5], nil, "extra input cannot extend the map")
T.eq(map.renderer.rebuilds, 1, "batch rebuilds once")
T.eq(world:replaceBlocks({ 1, 0, 2, 0 }), false, "identical batch does nothing")
T.eq(world:replaceBlocks(nil), false, "missing batch does nothing")
T.eq(#seen["world.blocks_replaced"], 1, "no-op batches publish no event")

-- A headless logic update emits even though draw() was never called.
world:update(1 / 60)
T.eq(#seen["world.tick"], 1, "native update publishes one simulation tick")
local tick = seen["world.tick"][1]
T.eq(tick.dt, 1 / 60, "tick carries the simulation dt")
T.eq(tick.mapId, "FIX_TOWN", "tick carries the active map")
T.eq(tick.overworld, world, "tick identifies the native world")
T.eq(tick.scripted, false, "an idle runner is reported as idle")
world.runner:run({ { "wait", 5 } })
T.eq(world.runner:isRunning(), true, "the native wait command holds a script open")
world:update(1 / 30)
T.eq(#seen["world.tick"], 2, "scripted updates still publish exactly one tick")
T.eq(seen["world.tick"][2].scripted, true, "tick reports the real running script")
T.eq(seen["world.tick"][2].dt, 1 / 30, "tick does not hardcode the frame interval")

-- Hatching is announced after the native dialogue callback, with a healed
-- ordinary Pokemon rather than an egg. Use Emerald to avoid Johto's second
-- nickname prompt; the native hatch method itself remains under test.
GameVersion.set("emerald")
local egg = Pokemon.new(data, "FIXMON_A", 5, function(a)
  return a
end)
egg.isEgg, egg.eggSteps, egg.eggCycles = true, 0, 0
egg.hp, egg.status = 1, "PSN"
T.eq(world:hatchEgg(egg), true, "native hatch accepts the egg")
T.eq(#seen["pokemon.egg_hatched"], 0, "hatch is not announced before dialogue finishes")
local box = stack:pop()
T.check(box ~= nil, "hatch opens its native text box")
box.onDone()
T.eq(#seen["pokemon.egg_hatched"], 1, "dialogue completion publishes the hatch")
T.eq(seen["pokemon.egg_hatched"][1].mon, egg, "hatch identifies the live Pokemon")
T.eq(egg.isEgg, nil, "the announced Pokemon is no longer an egg")
T.eq(egg.eggSteps, nil, "hatch clears egg step bookkeeping")
T.eq(egg.eggCycles, nil, "hatch clears egg cycle bookkeeping")
T.eq(egg.hp, egg.stats.hp, "hatch heals HP before publication")
T.eq(egg.status, nil, "hatch cures status before publication")
T.eq(egg.happiness, 120, "hatch applies base happiness before publication")
T.eq(world:hatchEgg(nil), false, "missing egg is rejected")
T.eq(#seen["pokemon.egg_hatched"], 1, "rejected hatch does not publish")

-- A public wrapper can suppress native Sinnoh/Unova healthboxes before any
-- battler/graphics access. Returning true prevents fallback Game Boy panels.
GameVersion.set("platinum")
local battle = {}
T.eq(Gen4Battle.drawHealthboxes(battle), true, "hidden native HUD is handled")
T.eq(exports.hudCalls, 1, "native healthbox draw consults the public hook")
T.eq(exports.battle, battle, "the hook receives the live battle")
exports.hideHUD = false
T.eq(
  Gen4Battle.drawHealthboxes(battle),
  false,
  "delegating preserves the native fallback when healthbox art is absent"
)
T.eq(exports.hudCalls, 2, "delegation still goes through the public wrapper")
exports.hideHUD = true
GameVersion.set("black")
T.eq(Gen4Battle.drawHealthboxes(battle), true, "the shared native path also hides Unova boxes")
T.eq(exports.hudCalls, 3, "Unova consults the same public wrapper")

T.eq(#run.errors, 0, "native callbacks produce no attributed mod errors")
run.loader.events:removeOwner("seam_probe")
run.loader.hooks:removeOwner("seam_probe")
for _, name in ipairs({
  "intro.birch_speech.started",
  "intro.birch_speech.finished",
  "pokemon.egg_hatched",
  "world.blocks_replaced",
  "world.tick",
}) do
  T.eq(Runtime.wants(name), false, "unloading removes subscription: " .. name)
end
T.eq(Runtime.wantsHook("battle.status_hud_visible"), false, "unloading removes the HUD hook")
run.release()
GameVersion.set(savedVersion)
for key, value in pairs(savedGame) do
  Game[key] = value[1]
end
T.finish("native public mod seams")
