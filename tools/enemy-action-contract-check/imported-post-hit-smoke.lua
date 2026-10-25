-- CPU-only scenarios using existing local imported definitions and controlled battlers.
-- No cache, normal save, mod assets or graphics are written.
package.path = "./?.lua;./?/init.lua;" .. package.path
local root = assert(arg[1])
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  for _, actor in ipairs({ 0, 1 }) do
    for _, number in ipairs({ 33, 3 }) do
      for _, item in ipairs({ 187, 219 }) do
        for _, override in ipairs({ false, true }) do
          local f = require("tests.enemy_actions.fixture").new(
            ".",
            "gen2",
            version,
            3,
            "unified",
            function(data, _, ids)
              for _, name in ipairs({ "pokemon", "moves", "items", "constants", "type_chart" }) do
                data[name] = assert(dofile(root .. "/" .. version .. "/data/generated/" .. name .. ".lua"))
              end
              for name, n in pairs({ TACKLE = 33, STRUGGLE = 165, SCRATCH = 10, MIMIC = 102, FLY = 19 }) do
                ids[name] = assert(data.constants.moveOrder[n])
              end
              require("src.pokemon.Stats").setNatures(data.constants.natures)
              require("src.pokemon.Growth").setTables(data.constants.experienceTables)
            end
          )
          f.game.save.options.ruleset = "gen3_emerald"
          local b = f.fresh("TACKLE").battle
          b:syncSides()
          b.ruleset.enemyUnlimitedPP = false
          local user = actor == 0 and b.player or b.enemy
          local target = actor == 0 and b.enemy or b.player
          for i, a in ipairs({ b.player, b.enemy }) do
            a.mon.stats.hp = 4000
            a.mon.hp = 4000
            a.mon.nickname = "P" .. (i - 1)
            a.mon.item = nil
            a.abilityOverride = false
          end
          user.mon.hp = 2000
          local key
          for id, def in pairs(f.data.items) do
            if type(def) == "table" and def.index == item then
              key = id
              break
            end
          end
          user.mon.item = assert(key)
          local move = assert(f.data.constants.moveOrder[number])
          local def = assert(f.data.moves[move])
          assert(math.floor(def.flags / 32) % 2 == 1)
          user.mon.moves = { { id = move, pp = 10 } }
          user.curMoves = user.mon.moves
          local reads, draws, damage = {}, {}, {}
          f.e.api.hooks:wrap("held_item.trigger", function(nextRead, c)
            reads[#reads + 1] = {
              holder = c.mon.nickname,
              item = c.item,
              trigger = c.trigger,
              effect = c.effect,
              parameter = c.parameter,
            }
            if override and c.trigger == "flinch" and c.mon.nickname == user.mon.nickname then
              if item == 187 then
                return "HELD_FLINCH", 256
              else
                return "HELD_SHELL_BELL", 0
              end
            end
            return nextRead(c)
          end)
          f.e.api.hooks:wrap("battle.crit", function()
            return false
          end)
          f.e.api.events:on("battle.damage_dealt", function(e)
            damage[#damage + 1] = e.damage
          end)
          b.rng = function(lo, hi)
            local v = lo == 0 and hi == 99 and 0 or lo == 1 and hi == 100 and 1 or hi
            draws[#draws + 1] = { lo, hi, v }
            return v
          end
          b:executeAction(user, target, user.curMoves[1])
          assert(#damage > 0 and damage[1] > 0)
          if item == 219 then
            assert(
              user.mon.hp == 2000 + math.max(1, math.floor(damage[1] / (override and 1 or 8))),
              "first-damage Shell Bell share"
            )
          else
            assert(
              (target.flinched or false) == (override or actor == 0),
              "native canonical player parameter"
            )
          end
          assert(user.curMoves[1].pp == 9 and b._gbaMoveFrame == nil)
          assert(#f.result.loader.errors == 0, table.concat(f.result.loader.errors, "\n"))
          assert(#f.result.errors == 0, "no swallowed public callback errors")
          rows[#rows + 1] = {
            version = version,
            actor = actor,
            move = number,
            item = item,
            override = override,
            hp = user.mon.hp,
            damage = damage,
            reads = reads,
            draws = draws,
          }
          f.close()
        end
      end
    end
  end
end
print("IMPORTED_POST_HIT_SMOKE " .. require("src.link.Json").encode(rows))
