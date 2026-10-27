-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native Gen2 window drawer over the existing scene/queue. Contract checked
-- against Gen1Recomp 535a5ec0 src/ui/gen2/BattleState.lua; existing project
-- rights and notices remain applicable. No separate battle renderer/controller.
local Version = require('src.core.GameVersion')
local Chrome = require('src.ui.Gen2Chrome')
local Scope = require('src.render.GraphicsScope')
local M = {}

function M.install(Screen)
  function Screen:drawsWidescreen() return Version.isGen2() end

  function Screen:panelSize() return self:uiSize() end

  function Screen:battlePanelScale(width, height)
    local pw, ph = self:panelSize()
    if self:wantsFillScale() then
      local _, _, w, h = Chrome.playfieldRect(width, height)
      return math.min(w / pw, h / ph)
    end
    return Chrome.fitScaleFor(width, height, pw / 8, ph / 8)
  end

  function Screen:drawWidescreen(width, height)
    local ok, why = Scope.call(function()
      local G = love.graphics
      G.origin()
      local scale = self:battlePanelScale(width, height)
      if not self:wideLayout() then
        return Chrome.withPanel(width, height, 1, 1, 1,
          function() self:drawScene() end, scale)
      end
      local pw, ph = self:panelSize()
      Chrome.letterbox(width, height, 1, 1, 1)
      local x, y = Chrome.fitOriginFor(width, height, scale, pw / 8, ph / 8)
      G.translate(x, y); G.scale(scale, scale)
      Chrome.clipTo(0, 0, pw, ph)
      return require('src.battle.WideBattle').draw(self)
    end)
    if not ok then error(why, 0) end
  end
end
return M
