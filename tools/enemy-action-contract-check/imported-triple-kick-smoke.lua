-- Optional CPU-only check against locally imported cartridges; distributes no assets.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local cacheRoot = assert(arg[1], "pass the Gen2Recomp import-cache root")
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ "ordinary", "miss1", "miss2", "miss3", "sub_break", "endure" }) do
    local function configure(data, _, ids)
      local root = cacheRoot .. "/" .. version .. "/data/generated/"
      for _, name in ipairs({ "pokemon", "moves", "items", "constants", "type_chart" }) do
        data[name] = assert(dofile(root .. name .. ".lua"))
      end
      for name, number in pairs({ TACKLE = 33, STRUGGLE = 165, SCRATCH = 10, MIMIC = 102, FLY = 19 }) do
        ids[name] = assert(data.constants.moveOrder[number])
      end
      require("src.pokemon.Stats").setNatures(data.constants.natures)
      require("src.pokemon.Growth").setTables(data.constants.experienceTables)
    end
    local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure)
    T.link.prepare(f.data)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b:syncSides()
    local id = assert(f.data.constants.moveOrder[167])
    local def = f.data.moves[id]
    assert(def.index == 167 and def.gen3Effect == 104 and def.power == 10 and def.accuracy == 90)
    b.player.mon.moves = { { id = id, pp = def.pp } }
    b.player.curMoves = b.player.mon.moves
    local reply = mode == "endure" and "ENDURE" or "TACKLE"
    local replyId = mode == "endure" and assert(f.data.constants.moveOrder[203]) or f.ids.TACKLE
    b.enemy.mon.moves = { { id = replyId, pp = f.data.moves[replyId].pp } }
    b.enemy.curMoves = b.enemy.mon.moves
    b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
    if mode == "sub_break" then
      b.enemy.substituteHP = 1
    end
    if mode == "endure" then
      b.enemy.mon.hp = 1
      b.player.curStats.speed, b.enemy.curStats.speed = 100, 200
    end
    local checks, hits, draws = 0, {}, {}
    local missAt = tonumber(mode:match("miss(%d)"))
    local tripleAccuracy = false
    f.e.api.hooks:wrap("battle.accuracy", function(nextAccuracy, ctx)
      tripleAccuracy = ctx.move.id == "TRIPLE_KICK"
      if tripleAccuracy then
        checks = checks + 1
      end
      local out = nextAccuracy(ctx)
      tripleAccuracy = false
      return out
    end)
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    local off = f.e.api.events:on("battle.damage_dealt", function(e)
      if e.move.id == "TRIPLE_KICK" then
        hits[#hits + 1] = { damage = e.damage, substitute = e.substitute or false }
      end
    end)
    b.rng = function(lo, hi)
      local value = lo == 1 and hi == 100 and 1 or hi
      if tripleAccuracy and checks == missAt then
        value = 100
      end
      draws[#draws + 1] = { lo = lo, hi = hi, value = value }
      return value
    end
    f.e.choose(function()
      return { move = reply }
    end)
    local game = b.game
    game.input = require("src.core.Input")
    game.stack.states = { b }
    b.phase, b.queue, b.current, b.frame, b.menuIndex, b.moveIndex = "moveSelect", {}, nil, 0, 1, 1
    local snapshot = assert(f.e.api.battle:snapshot())
    assert(f.e.api.battle:submit({ id = 1, revision = snapshot.revision, kind = "move", slot = 1 }))
    for _ = 1, 18000 do
      if b.phase == "menu" and b.turnCount == 1 then
        break
      end
      require("src.core.Input").pressed = { a = true }
      game.stack:update(1 / 60)
    end
    assert(b.phase == "menu" and b.turnCount == 1, "public imported turn must finish")
    local expected = missAt and missAt - 1 or mode == "endure" and 1 or 3
    assert(#hits == expected, mode .. ": wrong reached kick count")
    assert(checks == (missAt or expected), mode .. ": wrong per-hit accuracy count")
    assert(b.player.curMoves[1].pp == def.pp - 1, "one learned PP per submitted attack")
    if mode == "ordinary" then
      assert(hits[1].damage < hits[2].damage and hits[2].damage < hits[3].damage)
    end
    if mode == "sub_break" then
      assert(hits[1].substitute and not hits[2].substitute and b.enemy.mon.hp < 400)
    end
    if mode == "endure" then
      assert(b.enemy.mon.hp == 1)
    end
    rows[#rows + 1] = {
      version = version,
      mode = mode,
      passed = true,
      checks = checks,
      hits = hits,
      pp = b.player.curMoves[1].pp,
      draws = draws,
    }
    off()
    f.close()
  end
end
print("IMPORTED_TRIPLE_KICK_SMOKE " .. require("src.link.Json").encode(rows))
