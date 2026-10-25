-- Read existing local imports; submit actual public menu intents for two turns.
-- CPU only, with no writes to normal generated data or saves.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local cache = assert(arg[1], "pass the existing local Gen2Recomp cache root")
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  for _, authored in ipairs({ false, true }) do
    for _, incoming in ipairs({ 33, 10, 45 }) do
      for _, itemNumber in ipairs({ 186, 219 }) do
        local entry = [=[return function(mod)
          mod.hooks:wrap("battle.enemy_action",function()
            return {move="INCOMING"}
          end)
          mod.exports.api=mod
        end]=]
        if authored then
          entry = entry:gsub(
            "          mod.exports.api",
            [=[
          assert(mod.content.moves:register("PORTABLE_MIRROR",{id="PORTABLE_MIRROR",name="PORTABLE_MIRROR",type="NORMAL",power=0,accuracy=100,pp=10,effect="MIRROR_MOVE_EFFECT"}))
          mod.exports.api]=],
            1
          )
        end
        local function configure(data, _, ids)
          for _, name in ipairs({ "pokemon", "moves", "items", "constants", "type_chart" }) do
            data[name] = assert(dofile(cache .. "/" .. version .. "/data/generated/" .. name .. ".lua"))
          end
          for name, n in pairs({ TACKLE = 33, STRUGGLE = 165, SCRATCH = 10, MIMIC = 102, FLY = 19 }) do
            ids[name] = assert(data.constants.moveOrder[n])
          end
          require("src.pokemon.Stats").setNatures(data.constants.natures)
          require("src.pokemon.Growth").setTables(data.constants.experienceTables)
        end
        entry = entry:gsub(
          '"INCOMING"',
          ('"%s"'):format(({ [33] = "TACKLE", [10] = "SCRATCH", [45] = "GROWL" })[incoming])
        )
        local f =
          require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
        f.game.save.options.ruleset = "gen3_emerald"
        T.link.prepare(f.data)
        local b = f.fresh("TACKLE").battle
        b:syncSides()
        assert(b.ruleset.baseDamageStyle == "gba")
        local function id(n)
          return assert(f.data.constants.moveOrder[n])
        end
        local parent = authored and "PORTABLE_MIRROR" or id(119)
        local public = assert(f.e.api.content.moves:get(parent))
        assert(public.effect == "MIRROR_MOVE_EFFECT")
        b.player.mon.moves = { { id = parent, pp = 10 } }
        b.enemy.mon.moves = { { id = id(incoming), pp = 10 } }
        for i, actor in ipairs({ b.player, b.enemy }) do
          actor.mon.nickname = i == 1 and "PLAYER" or "FOE"
          actor.mon.stats.hp, actor.mon.hp = 4000, 4000
          actor.curMoves, actor.abilityOverride = actor.mon.moves, false
        end
        b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
        for key, def in pairs(f.data.items) do
          if type(def) == "table" and tonumber(def.index) == itemNumber then
            b.player.mon.item = key
            break
          end
        end
        assert(b.player.mon.item)
        local used, damage, draws = {}, {}, {}
        f.e.api.events:on("battle.move_used", function(e)
          used[#used + 1] = {
            user = e.user.mon.nickname,
            move = e.move.id,
            called = e.isCalled or false,
            pp = e.user.mon.moves[1].pp,
          }
        end)
        f.e.api.events:on("battle.damage_dealt", function(e)
          damage[#damage + 1] = { user = e.user.mon.nickname, move = e.move.id, damage = e.damage }
        end)
        f.e.api.hooks:wrap("battle.crit", function()
          return false
        end)
        b.rng = function(lo, hi)
          local value = lo == 1 and hi == 100 and 1 or hi
          draws[#draws + 1] = { lo, hi, value }
          return value
        end
        local game, Input = b.game, require("src.core.Input")
        game.input, game.stack.states = Input, { b }
        b.phase, b.queue, b.current, b.frame, b.menuIndex, b.moveIndex = "menu", {}, nil, 0, 1, 1
        local intentId = 0
        local function submit(intent)
          local snapshot = assert(f.e.api.battle:snapshot())
          intentId = intentId + 1
          intent.id, intent.revision = intentId, snapshot.revision
          local ok, why = f.e.api.battle:submit(intent)
          assert(ok, why)
        end
        for turn = 1, 2 do
          submit({ kind = "menu", choice = "fight" })
          for _ = 1, 10 do
            if b.phase == "moveSelect" then
              break
            end
            Input.pressed = {}
            game.stack:update(1 / 60)
          end
          assert(b.phase == "moveSelect", "public fight intent opens the actual move menu")
          submit({ kind = "move", slot = 1 })
          for _ = 1, 18000 do
            if b.phase == "menu" and b.turnCount == turn then
              break
            end
            Input.pressed = { a = true }
            game.stack:update(1 / 60)
          end
          assert(b.phase == "menu" and b.turnCount == turn, "actual submitted imported turn must finish")
          assert(
            b.player.gbaLastTakenMove == id(incoming),
            "native incoming command records real recipient history"
          )
        end
        assert(
          #used == 5 and used[1].move == public.id and not used[1].called,
          "first Mirror fails without received history"
        )
        assert(used[3].move == public.id and not used[3].called, "second turn announces public caller")
        assert(
          used[4].move == f.e.api.content.moves:get(id(incoming)).id and used[4].called,
          "second turn executes copied public move"
        )
        assert(used[3].pp == 9 and used[4].pp == 8, "only parent command spends PP before copied event")
        assert(b.player.mon.moves[1].pp == 8, "two actual selected commands spend exactly two PP")
        assert(
          #f.result.errors == 0 and #f.result.loader.errors == 0,
          "public callbacks and registration stay error-free"
        )
        rows[#rows + 1] = {
          version = version,
          authored = authored,
          incoming = incoming,
          item = itemNumber,
          used = used,
          damage = damage,
          draws = draws,
          received = b.player.gbaLastTakenMove,
          pp = b.player.mon.moves[1].pp,
        }
        f.close()
      end
    end
  end
end
print("IMPORTED_MIRROR_SMOKE " .. require("src.link.Json").encode(rows))
