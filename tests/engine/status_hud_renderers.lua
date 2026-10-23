package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/status_hud/fixture.lua")
local Version = require("src.core.GameVersion")
local Visibility = require("src.battle.StatusHUDVisibility")
local Battle = require("src.battle.BattleState")
local G3 = require("src.battle.Gen3Battle")
local G4 = require("src.battle.Gen4Battle")
local G5 = require("src.battle.Gen5BattleHud")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local b, e = f.battle, f.exports
    T.eq(f.public:supports("hooks", "battle.status_hud_visible"), true, version .. " capability")
    for _, owner in ipairs({ b, {} }) do
      local calls = e.seen.calls
      T.eq(Visibility.forBattle(owner), true, "native or partial owner visible")
      T.eq(e.seen.calls, calls + 1, "one hook dispatch, including DS native method")
      T.eq(e.seen.state, owner, "same opaque owner")
      e.hide(true)
      T.eq(Visibility.forBattle(owner), false, "native or partial owner hidden")
      e.hide(false)
    end
    b.statusHUDVisible = function()
      return false
    end
    local calls = e.seen.calls
    T.eq(Visibility.forBattle(b), false, "legacy override veto")
    T.eq(e.seen.calls, calls, "legacy veto precedes hook")
    b.statusHUDVisible = function()
      return true
    end
    e.hide(true)
    T.eq(Visibility.forBattle(b), false, "hook veto survives legacy true")
    b.statusHUDVisible = function()
      error("legacy failure")
    end
    T.eq(Visibility.forBattle(b), false, "legacy failure retains public predicate")
    b.statusHUDVisible = Battle.statusHUDVisible
    e.hide(false)
    if Version.isGen3() then
      local Assets = require("src.render.Assets")
      local image = love.graphics.newImage("contract-healthbox.png")
      local summaryImage = love.graphics.newImage("contract-summary.png")
      f.patch(Assets, "image", function(path)
        return path == "summary" and summaryImage or image
      end)
      b.data.constants.gen3BattleHud = {
        images = {
          player = "panel",
          opponent = "panel",
          playerDoubles = "panel",
          opponentDoubles = "panel",
        },
      }
      b.data.constants.gen3BattlerCoords = {
        healthbox = {
          playerLeft = { x = 159, y = 76 },
          playerRight = { x = 171, y = 101 },
          opponentLeft = { x = 44, y = 19 },
          opponentRight = { x = 32, y = 44 },
        },
      }
      local panels, summaries = 0, 0
      f.patch(love.graphics, "draw", function(img)
        if img == image then
          panels = panels + 1
        end
        if img == summaryImage then
          summaries = summaries + 1
        end
      end)
      for _, double in ipairs({ false, true }) do
        b.isDouble = function()
          return double
        end
        b.battlerAt = function(self, pos)
          return pos % 2 == 0 and self.player or self.enemy
        end
        panels = 0
        G3.drawHUDs(b, 0)
        T.eq(panels, double and 4 or 2, "native GBA art for every active panel")
        panels = 0
        e.hide(true)
        G3.drawHUDs(b, 0)
        T.eq(panels, 0, "native GBA single/double art entirely hidden")
        e.hide(false)
      end
      -- Intro party summaries are independent of status panels.
      b.data.constants.gen3BattleHud.partySummary = {
        bar = "summary",
        balls = "summary",
        count = 1,
        icons = { healthy = 0, empty = 0 },
        player = { barX = 0, barY = 0, ballX = 0, ballY = 0 },
      }
      b.introBalls, b.playerParty = true, { b.player.mon }
      summaries = 0
      e.hide(true)
      G3.drawHUDs(b, 0)
      T.check(summaries > 0, "hidden GBA status preserves party summary")
    elseif Version.generation() >= 4 then
      local delegated = 0
      f.patch(G5, "active", function()
        return true
      end)
      f.patch(G5, "drawHealthboxes", function()
        delegated = delegated + 1
        return true
      end)
      local calls = e.seen.calls
      T.eq(G4.drawHealthboxes(b), true, "existing DS delegation handled")
      T.eq(e.seen.calls, calls + 1, "DS true dispatches once")
      T.eq(delegated, 1, "native DS healthbox delegate executes")
      e.hide(true)
      T.eq(G4.drawHealthboxes(b), true, "hidden DS handled, no GB fallback")
      T.eq(delegated, 1, "hidden DS skips healthbox delegate")
    else
      local balls = 0
      b.introBalls, b.playerParty = true, { b.player.mon }
      b.drawBallRow = function()
        balls = balls + 1
      end
      e.hide(true)
      b:drawHUDs(0)
      T.eq(balls, 1, "hidden GB status preserves intro party row")
      b.introBalls, b.showEnemyBalls, b.enemyParty = false, true, { b.enemy.mon }
      balls = 0
      b:drawHUDs(0)
      T.eq(balls, 1, "hidden GB status preserves replacement party row")
    end
    f.close()
  end
end
Version.set(originalVersion)
T.finish("battle.status_hud_visible native renderers")
