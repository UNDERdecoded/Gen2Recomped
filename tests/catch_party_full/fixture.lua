local F = {}

function F.new(root, version, api, format, noMod)
  local T = require("tests.modkit")
  local V = require("src.core.GameVersion")
  V.set(version or "red")
  local data = T.fixtures.fresh()
  local Json = require("src.link.Json")
  local files = {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_catch_party_full/" .. name, "rb"))
    files["mods/portable_catch_party_full/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_catch_party_full/manifest.json"])
  manifest.api, manifest.callback_format = api or 2, format or "native"
  files["mods/portable_catch_party_full/manifest.json"] = Json.encode(manifest)
  local run = T.sdk.loadMods(noMod and {} or { "mods/portable_catch_party_full" }, {
    data = data,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#run.errors == 0, table.concat(run.errors, "\n"))
  local exported = run.loader.exports.portable_catch_party_full
  assert(noMod or exported and type(exported.set) == "function", "consumer entry did not execute")
  require("src.render.Font").load(data)
  require("src.battle.TypeChart").load(data)
  local Pokemon = require("src.pokemon.Pokemon")
  local Save = require("src.core.SaveData")
  local Battle = require("src.battle.BattleState")
  local Boxes = require("src.pokemon.Boxes")
  if Boxes.load then
    Boxes.load(nil)
  end
  local function fresh(destination, isNew)
    local save = Save.newGame()
    save.party = {}
    for _ = 1, destination == "party" and 1 or 6 do
      save.party[#save.party + 1] = Pokemon.new(data, "FIXMON_A", 10)
    end
    save.pokedex.owned.FIXMON_B = not isNew or nil
    if destination == "full" then
      local boxes = Boxes.ensure(save)
      local count = type(Boxes.count) == "function" and Boxes.count() or Boxes.COUNT
      local capacity = type(Boxes.capacity) == "function" and Boxes.capacity() or Boxes.CAPACITY
      for i = 1, count do
        for slot = 1, capacity do
          boxes[i][slot] = save.party[1]
        end
      end
    end
    local pushed = {}
    local game = {
      data = data,
      save = save,
      stack = {
        top = function()
          return nil
        end,
        push = function(_, screen)
          pushed[#pushed + 1] = screen
        end,
        pop = function() end,
      },
    }
    local b = Battle.newWild(game, "FIXMON_B", 3)
    b.queue, b.nextInsert = {}, 0
    b.lastBall = "POKE_BALL"
    return b, save, pushed
  end
  local function capture(destination, isNew)
    local b, save, pushed = fresh(destination, isNew)
    local caught = b.enemy.mon
    local event, eventNickname
    local off = run.loader.events:on("pokemon.caught", function(ctx)
      event, eventNickname = ctx, ctx.mon.nickname
    end)
    b:storeCaughtMon()
    off()
    local stored
    if destination == "party" then
      stored = save.party[2]
    elseif destination == "box" then
      stored = save.boxes and save.boxes[1] and save.boxes[1][1]
    end
    local occurrences = 0
    for _, mon in ipairs(save.party) do
      if mon == caught then
        occurrences = occurrences + 1
      end
    end
    for _, box in ipairs(save.boxes or {}) do
      for _, mon in ipairs(box) do
        if mon == caught then
          occurrences = occurrences + 1
        end
      end
    end
    local ui = {}
    for _, row in ipairs(b.queue) do
      if row.ui then
        ui[#ui + 1] = row.ui
      end
    end
    return {
      occurrences = occurrences,
      battle = b,
      save = save,
      caught = caught,
      stored = stored,
      event = event,
      eventNickname = eventNickname,
      ui = ui,
      pushed = pushed,
    }
  end
  return {
    T = T,
    data = data,
    run = run,
    exports = exported,
    fresh = fresh,
    capture = capture,
    close = run.release,
  }
end

return F
