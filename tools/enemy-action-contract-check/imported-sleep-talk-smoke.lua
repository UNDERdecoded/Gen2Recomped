package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local cacheRoot = assert(arg[1], "pass the local Gen2Recomp cache root")
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ "repeat", "zero_pp", "empty", "forbidden", "early_wake", "awake" }) do
    local function configure(data, _, ids)
      local root = cacheRoot .. "/" .. version .. "/data/generated/"
      for _, name in ipairs({ "pokemon", "moves", "items", "constants", "type_chart" }) do
        data[name] = assert(dofile(root .. name .. ".lua"))
      end
      for name, n in pairs({ TACKLE = 33, STRUGGLE = 165, SCRATCH = 10, MIMIC = 102, FLY = 19 }) do
        ids[name] = assert(data.constants.moveOrder[n])
      end
      require("src.pokemon.Stats").setNatures(data.constants.natures)
      require("src.pokemon.Growth").setTables(data.constants.experienceTables)
    end
    local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure)
    T.link.prepare(f.data)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b:syncSides()
    local function id(n)
      return assert(f.data.constants.moveOrder[n])
    end
    local caller = id(214)
    assert(f.data.moves[caller].gen3Effect == 97 and f.data.moves[caller].power == 0)
    local nums = { 214, 33, 10 }
    if mode == "empty" then
      nums = { 214, 118, 119, 274 }
    end
    if mode == "forbidden" then
      nums = { 214, 264, 253, 19 }
    end
    local moves = {}
    for _, n in ipairs(nums) do
      moves[#moves + 1] = { id = id(n), pp = f.data.moves[id(n)].pp }
    end
    b.player.mon.moves, b.player.curMoves = moves, moves
    b.enemy.mon.moves = { { id = id(33), pp = f.data.moves[id(33)].pp } }
    b.enemy.curMoves = b.enemy.mon.moves
    b.player.mon.nickname, b.enemy.mon.nickname = "PLAYER", "FOE"
    b.player.mon.status, b.player.sleepTurns = "SLP", 4
    if mode == "awake" then
      b.player.mon.status, b.player.sleepTurns = nil, nil
    end
    if mode == "early_wake" then
      b.player.abilityOverride, b.player.sleepTurns = "EARLY_BIRD", 2
    end
    if mode == "zero_pp" then
      for i = 2, #moves do
        moves[i].pp = 0
      end
    end
    b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
    local used, draws = {}, {}
    local off = f.e.api.events:on("battle.move_used", function(e)
      if e.user.mon.nickname == "PLAYER" then
        used[#used + 1] = { move = e.move.id, target = e.target.mon.nickname, called = e.isCalled or false }
      end
    end)
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    b.rng = function(lo, hi)
      local v = lo == 1 and 1 or hi
      draws[#draws + 1] = { lo = lo, hi = hi, value = v }
      return v
    end
    f.e.choose(function()
      return { move = "TACKLE" }
    end)
    local game = b.game
    game.input = require("src.core.Input")
    game.stack.states = { b }
    b.phase, b.queue, b.current, b.frame, b.menuIndex, b.moveIndex = "moveSelect", {}, nil, 0, 1, 1
    local serial = 0
    local function submit(action)
      serial = serial + 1
      action.id, action.revision = serial, assert(f.e.api.battle:snapshot()).revision
      local ok, why = f.e.api.battle:submit(action)
      assert(ok, why)
    end
    local turns = mode == "repeat" and 4 or 1
    for turn = 1, turns do
      if turn > 1 then
        submit({ kind = "menu", choice = "fight" })
      end
      submit({ kind = "move", slot = turn == 4 and 2 or 1 })
      for _ = 1, 18000 do
        if b.phase == "menu" and b.turnCount == turn then
          break
        end
        require("src.core.Input").pressed = { a = true }
        game.stack:update(1 / 60)
      end
      assert(b.phase == "menu" and b.turnCount == turn, "public imported turn must finish")
    end
    local children = 0
    assert(#f.result.loader.errors == 0, table.concat(f.result.loader.errors, "\n"))
    for _, e in ipairs(used) do
      if e.move == "SLEEP_TALK" then
        assert(e.target == "FOE", "native DEPENDS caller uses its resolved foe target")
      end
      if e.called then
        children = children + 1
        assert(e.target == "FOE" and e.move == "TACKLE")
      end
    end
    assert(
      children == (mode == "repeat" and 3 or mode == "zero_pp" and 1 or 0),
      "wrong native called execution"
    )
    assert(moves[1].pp == f.data.moves[caller].pp - (mode == "repeat" and 3 or 1), "only caller PP is spent")
    if mode == "repeat" then
      assert(b.player.mon.status == nil, "wake allows the independently selected ordinary move")
      assert(
        moves[2].pp == f.data.moves[id(33)].pp - 1,
        "called Tackle PP stays intact until independently selected"
      )
    end
    if mode == "zero_pp" then
      assert(moves[2].pp == 0 and moves[3].pp == 0)
    end
    if mode == "early_wake" then
      assert(b.player.mon.status == nil and b.player.sleepTurns == nil)
    end
    assert(b._gbaMoveFrame == nil, "nested dispatcher restores its frame")
    rows[#rows + 1] = {
      version = version,
      mode = mode,
      passed = true,
      turns = turns,
      used = used,
      draws = draws,
      callerPP = moves[1].pp,
      childPP = moves[2].pp,
      status = b.player.mon.status,
      sleep = b.player.sleepTurns,
    }
    off()
    f.close()
  end
end
print("IMPORTED_SLEEP_TALK_SMOKE " .. require("src.link.Json").encode(rows))
