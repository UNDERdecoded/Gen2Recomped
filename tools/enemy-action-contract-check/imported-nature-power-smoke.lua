-- Existing local imports, controlled battlers and actual public menu submissions.
-- No normal save or generated asset is written; no graphical acceptance is claimed.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local cache = assert(arg[1], "pass the existing local Gen2Recomp cache root")
local chained = arg[2] == "--sleep-talk"
local children = { [0] = 78, 75, 89, 56, 57, 61, 157, 247, 129, 129 }
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  for _, authored in ipairs({ false, true }) do
    for terrain = 0, 9 do
      for _, itemNumber in ipairs({ 186, 219 }) do
        local entry = [=[return function(mod)
     local choice
     mod.hooks:wrap("battle.enemy_action",function(nextAction,...)
      if choice then return choice(nextAction,...)end
      return nextAction(...)
     end)
     mod.exports.choose=function(fn)choice=fn end
     mod.exports.api=mod
    end]=]
        if authored then
          entry = entry:gsub(
            "     local choice",
            [=[     assert(mod.content.moves:register("PORTABLE_NATURE",{id="PORTABLE_NATURE",name="PORTABLE_NATURE",type="NORMAL",power=0,accuracy=100,pp=10,effect="NATURE_POWER"}))
     local choice]=],
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
        local f =
          require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
        f.game.save.options.ruleset = "gen3_emerald"
        T.link.prepare(f.data)
        local b = f.fresh("TACKLE").battle
        b:syncSides()
        b.terrain = terrain
        assert(b.ruleset.baseDamageStyle == "gba")
        local function id(n)
          return assert(f.data.constants.moveOrder[n])
        end
        local parent = authored and "PORTABLE_NATURE" or id(267)
        local publicParent = assert(f.e.api.content.moves:get(parent))
        assert(publicParent.effect == "NATURE_POWER")
        local child = assert(f.e.api.content.moves:get(id(children[terrain])))
        local selected = chained and id(214) or parent
        local publicSelected = assert(f.e.api.content.moves:get(selected))
        local learned = { { id = selected, pp = 10 }, { id = chained and parent or id(33), pp = 10 } }
        b.player.mon.moves, b.player.curMoves = learned, learned
        b.enemy.mon.moves = { { id = id(33), pp = 10 } }
        b.enemy.curMoves = b.enemy.mon.moves
        b.player.mon.nickname, b.enemy.mon.nickname = "PLAYER", "FOE"
        for _, a in ipairs({ b.player, b.enemy }) do
          a.mon.stats.hp = 4000
          a.mon.hp = 4000
          a.abilityOverride = false
        end
        b.player.mon.hp = 2000
        if chained then
          b.player.mon.status, b.player.sleepTurns = "SLP", 4
        end
        for key, def in pairs(f.data.items) do
          if type(def) == "table" and tonumber(def.index) == itemNumber then
            b.player.mon.item = key
            break
          end
        end
        assert(b.player.mon.item)
        b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
        local used, damage, draws = {}, {}, {}
        local beforeFoe
        f.e.api.events:on("battle.move_used", function(e)
          if e.user.mon.nickname == "PLAYER" then
            used[#used + 1] = {
              move = e.move.id,
              called = e.isCalled or false,
              pp = e.user.mon.moves[1].pp,
              target = e.target.mon.nickname,
            }
          else
            beforeFoe = b.player.mon.hp
          end
        end)
        f.e.api.events:on("battle.damage_dealt", function(e)
          if e.user.mon.nickname == "PLAYER" then
            damage[#damage + 1] = e.damage
          end
        end)
        f.e.api.hooks:wrap("battle.crit", function()
          return false
        end)
        b.rng = function(lo, hi)
          local value = lo == 1 and hi == 100 and 1 or hi
          draws[#draws + 1] = { lo, hi, value }
          return value
        end
        f.e.choose(function()
          return { move = "TACKLE" }
        end)
        local game = b.game
        game.input = require("src.core.Input")
        game.stack.states = { b }
        b.phase, b.queue, b.current, b.frame, b.menuIndex, b.moveIndex = "moveSelect", {}, nil, 0, 1, 1
        local snapshot = assert(f.e.api.battle:snapshot())
        local ok, why =
          f.e.api.battle:submit({ kind = "move", slot = 1, id = 1, revision = snapshot.revision })
        assert(ok, why)
        for _ = 1, 18000 do
          if b.phase == "menu" and b.turnCount == 1 then
            break
          end
          require("src.core.Input").pressed = { a = true }
          game.stack:update(1 / 60)
        end
        assert(b.phase == "menu" and b.turnCount == 1, "actual submitted imported turn must finish")
        assert(#used == (chained and 3 or 2) and used[1].move == publicSelected.id and not used[1].called)
        local final = used[#used]
        assert(
          final.move == child.id and final.called,
          "actual terrain child uses advertised public identity"
        )
        assert(used[1].pp == 10, "selected announcement precedes its PP command")
        if chained then
          assert(
            used[2].move == publicParent.id and used[2].called and used[2].pp == 9 and final.pp == 9,
            "native called Nature Power borrows no PP from the outer Sleep Talk"
          )
        else
          assert(final.pp == 10, "Nature Power child announces before its selected PP command")
        end
        assert(b.player.lastMove == parent, "inner native caller preserves resulting move history")
        if itemNumber == 186 then
          assert(
            b.player.choicedMove == require("src.battle.Gen3ChoiceBand").identity(b, parent),
            "native Choice Band owns the innermost caller"
          )
        end
        assert(learned[1].pp == 9 and learned[2].pp == 10, "only selected caller slot spends PP")
        local healing = itemNumber == 219 and damage[1] and math.max(1, math.floor(damage[1] / 8)) or 0
        assert(beforeFoe == 2000 + healing, "native move-end healing completes before the next actor")
        if terrain == 0 then
          assert(b.enemy.mon.status == "PAR" and #damage == 0, "actual Stun Spore status handler executes")
        else
          assert(#damage > 0 and damage[1] > 0, "actual imported damaging child executes")
        end
        assert(
          #f.result.errors == 0 and #f.result.loader.errors == 0,
          "public callbacks and registration remain error-free"
        )
        rows[#rows + 1] = {
          version = version,
          authored = authored,
          chained = chained,
          terrain = terrain,
          item = itemNumber,
          used = used,
          damage = damage,
          draws = draws,
          pp = learned[1].pp,
          beforeFoe = beforeFoe,
        }
        f.close()
      end
    end
  end
end
print("IMPORTED_NATURE_POWER_SMOKE " .. require("src.link.Json").encode(rows))
