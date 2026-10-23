package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/level_visible/fixture.lua")
local Version = require("src.core.GameVersion")
local Font, Hud = require("src.render.Font"), require("src.render.HudTiles")
local Battle = require("src.battle.BattleState")
local G3 = require("src.battle.Gen3Battle")
-- Upvalue leaf spies require interpreted calls: LuaJIT can retain old leaf closures.
if jit then
  jit.off(Battle.drawHUDs, true)
end
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  if Version.generation(version) <= 3 then
    for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
      local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
      local game, mon, e = f.game, f.mon, f.exports
      game.save = require("src.core.SaveData").newGame()
      game.save.party = { mon }
      mon.nickname, mon.hp, mon.stats.hp = "SCOUT", 60, 60
      f.result.loader.game = game
      f.patch(love.graphics, "polygon", function() end)
      f.patch(love.graphics, "getScissor", function() end)
      Font.load(game.data)
      local rows = {}
      local function text(s, x, y)
        rows[#rows + 1] = { text = tostring(s), x = x, y = y }
        return Font.width(s)
      end
      f.patch(Font, "draw", text)
      f.patch(Font, "drawCode", function(code, x, y)
        rows[#rows + 1] = { code = code, x = x, y = y }
      end)
      for _, key in ipairs({ "tile", "statusTile" }) do
        f.patch(Hud, key, function(code, x, y)
          rows[#rows + 1] = { code = code, x = x, y = y }
        end)
      end
      local function capture(draw)
        rows = {}
        draw()
        return rows
      end
      local function has(list, needle)
        for _, row in ipairs(list) do
          if row.text and row.text:find(needle, 1, true) then
            return true
          end
        end
        return false
      end
      local function levelCount(list)
        local count = 0
        for _, row in ipairs(list) do
          if
            row.text
            and (
              row.text == "42"
              or row.text == "43"
              or row.text == "100"
              or row.text == "Lv42"
              or row.text == "Lv100"
            )
          then
            count = count + 1
          end
        end
        return count
      end
      local b = Battle.newWild(game, "FIXMON_C", 42)
      b.player.isPlayer, b.enemy.isPlayer = true, false
      b:syncSides()
      b.phase, b.frame, b.shown, b.fx = "contract", 0, {}, {}
      b.showPlayerBack, b.showEnemyTrainer, b.enemySendingOut, b.introBalls = false, false, false, false
      b.growInScale = function()
        return nil
      end
      b.colorMode = function()
        return false
      end
      b.demoHidesPlayer = function()
        return false
      end
      -- The classic compositor captures its tile leaf during module load.
      for i = 1, 100 do
        local name, value = debug.getupvalue(Battle.drawHUDs, i)
        if not name then
          break
        end
        if name == "hudTile" then
          debug.setupvalue(Battle.drawHUDs, i, Hud.tile)
          local close = f.close
          f.close = function()
            debug.setupvalue(Battle.drawHUDs, i, value)
            close()
          end
          break
        end
      end
      local nativeSeen = {}
      local off = f.result.loader.hooks:wrap("pokemon.level_visible", function(next, m, ctx)
        T.eq(ctx.game, game, "native producer supplies live Game")
        T.check(m == mon or m == b.enemy.mon or m == b.player.mon, "native producer supplies actual mon")
        if ctx.where == "battle.player" or ctx.where == "battle.enemy" then
          T.eq(
            ctx.where,
            m == b.enemy.mon and "battle.enemy" or "battle.player",
            "native side, including partners"
          )
        end
        nativeSeen[ctx.where] = (nativeSeen[ctx.where] or 0) + 1
        return next(m, ctx)
      end, 1000)
      local function cycle(label, surfaces, draw, expected)
        for _, where in ipairs(surfaces) do
          e.hide(where, false)
        end
        local stock = capture(draw)
        T.eq(levelCount(stock), expected, version .. " " .. label .. " native level count")
        nativeSeen = {}
        for _, where in ipairs(surfaces) do
          e.hide(where, true)
        end
        local hidden = capture(draw)
        T.eq(levelCount(hidden), 0, label .. " omits level digits")
        for _, row in ipairs(hidden) do
          T.check(row.code ~= 0x6E and row.code ~= 0x70, label .. " no orphan level/TO glyph")
          T.check(row.text ~= "TO" and not (row.text or ""):find("Lv42", 1, true), "no orphan label")
        end
        for _, where in ipairs(surfaces) do
          T.check((nativeSeen[where] or 0) > 0, label .. " producer identifies " .. where)
          e.hide(where, false)
        end
        T.check(has(hidden, "SCOUT") or has(hidden, b.player.name), label .. " nickname remains")
        local restored = capture(draw)
        T.same(restored, stock, label .. " restores exact printed rows")
      end
      if Version.generation() <= 2 then
        cycle("classic battle", { "battle.player", "battle.enemy" }, function()
          b:drawHUDs(0)
        end, 2)
        cycle("wide battle", { "battle.player", "battle.enemy" }, function()
          local wide = require("src.battle.WideBattle")
          wide.gen2Panel(b, b.player, 9 * 8, 7 * 8, true, false)
          wide.gen2Panel(b, b.enemy, 0, 0, false, false)
        end, 2)
        -- One surface can hide without hiding the other side.
        e.hide("battle.enemy", true)
        T.eq(
          levelCount(capture(function()
            b:drawHUDs(0)
          end)),
          1,
          "per-side native battle omission"
        )
        e.hide("battle.player", true)
        b.player.shownStatus, b.enemy.shownStatus = "PSN", "PSN"
        T.check(
          has(
            capture(function()
              b:drawHUDs(0)
            end),
            "PSN"
          ),
          "hidden levels retain battle status"
        )
        b.player.shownStatus, b.enemy.shownStatus = nil, nil
        local party = require("src.ui.PartyMenu").new(game)
        cycle("party", { "party" }, function()
          party:draw()
        end, 1)
        mon.level = 100
        cycle("party level 100", { "party" }, function()
          party:draw()
        end, 1)
        mon.level = 42
        local summary = require("src.ui.SummaryMenu").new(game, mon)
        for page = 1, Version.isGen2() and 3 or 2 do
          summary.page = page
          local count = Version.isGen2() and (page == 1 and 2 or 1) or 1
          cycle("summary page " .. page, { "summary" }, function()
            summary:draw()
          end, count)
        end
        mon.isEgg = true
        local calls = e.seen.calls
        capture(function()
          party:draw()
        end)
        T.eq(e.seen.calls, calls, "egg does not query or invent a level")
        mon.isEgg = nil
      else
        cycle("GBA no-art battle", { "battle.player", "battle.enemy" }, function()
          G3.drawHUDs(b, 0)
        end, 2)
        e.hide("battle.player", true)
        e.hide("battle.enemy", true)
        b.player.shownStatus, b.enemy.shownStatus = "PSN", "PSN"
        T.check(
          has(
            capture(function()
              G3.drawHUDs(b, 0)
            end),
            "PSN"
          ),
          "GBA fallback preserves status text"
        )
        b.player.shownStatus, b.enemy.shownStatus = nil, nil
        local image = love.graphics.newCanvas(128, 64)
        f.patch(require("src.render.Assets"), "image", function()
          return image
        end)
        local record = { images = { player = "panel", opponent = "panel" } }
        game.data.constants.gen3BattleHud = record
        cycle("GBA panel battle", { "battle.player", "battle.enemy" }, function()
          G3.drawHUDs(b, 0)
        end, 2)
        local w = {
          name = { x = 8, y = 3, w = 56 },
          level = { x = 64, y = 3 },
          bar = { x = 40, y = 16 },
          label = { x = 24, y = 16 },
        }
        record.windows = { player = w, opponent = w }
        cycle("GBA native windows", { "battle.player", "battle.enemy" }, function()
          G3.drawHUDs(b, 0)
        end, 2)
        record.windows = nil
        game.data.constants.gen3BattlerCoords = {
          healthbox = {
            playerLeft = { x = 159, y = 76 },
            playerRight = { x = 171, y = 101 },
            opponentLeft = { x = 44, y = 19 },
            opponentRight = { x = 32, y = 44 },
          },
        }
        b.isDouble = function()
          return true
        end
        local partner = { name = "SCOUT", mon = b.player.mon, isPlayer = true, shownHP = mon.hp }
        b.battlerAt = function(self, pos)
          return pos == 2 and partner or (pos % 2 == 0 and self.player or self.enemy)
        end
        cycle("GBA doubles", { "battle.player", "battle.enemy" }, function()
          G3.drawHUDs(b, 0)
        end, 4)
        local party = require("src.ui.Gen3PartyMenu").new(game)
        local panel = { x = 0, y = 0, wide = true, width = 100, index = 1 }
        cycle("GBA party slot", { "party" }, function()
          party:drawMember(mon, panel, false)
        end, 1)
        local summary = require("src.ui.Gen3SummaryMenu").new(game, { mon = mon })
        cycle("GBA summary fallback", { "summary" }, function()
          summary:drawHeader()
        end, 1)
        summary.hasArt = true
        cycle("GBA summary art", { "summary" }, function()
          summary:drawHeader()
        end, 1)
        local labels = {}
        for i = 1, 20 do
          labels[i] = { x = 0, y = 0 }
        end
        game.data.constants.gen3SummaryWindows = { labels = labels }
        cycle("GBA summary windows", { "summary" }, function()
          summary:drawHeader()
        end, 1)
        if version == "firered" then
          summary.page = 3
          cycle("FireRed summary", { "summary" }, function()
            summary:drawFireRed({})
          end, 1)
          summary.moveSelect = true
          e.hide("summary", true)
          local calls = e.seen.calls
          local detailRows = capture(function()
            summary:drawFireRed({})
          end)
          T.eq(has(detailRows, "Lv42"), false, "move detail native omission")
          T.eq(e.seen.calls, calls, "move detail cannot invent a level")
        end
      end
      off()
      f.close()
    end
  end
end
Version.set(originalVersion)
T.finish("pokemon.level_visible native renderers")
