-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional window-resolution UI. Simulation/input remain native; only an
-- explicitly advertised drawer leaves the cartridge-sized UI canvas.
local M = {}
local function visible(stack, state)
  return not stack.renderVisible or stack:renderVisible(state)
end
function M.select(stack, scene, first)
  for i = #scene.states, first, -1 do
    local state = scene.states[i]
    if visible(stack, state) and type(state.drawsWidescreen) == 'function'
        and type(state.drawWidescreen) == 'function' and state:drawsWidescreen() then
      return state, i
    end
  end
end
function M.classic(draw, renderer, width, height)
  local G = love.graphics
  local uw, uh = renderer:uiSize()
  local p = renderer.uiPresentation
  if not p then
    local scale = math.max(1, math.floor(math.min(width / uw, height / uh)))
    p = { x=(width-uw*scale)/2, y=(height-uh*scale)/2, scaleX=scale, scaleY=scale }
  end
  G.push('all')
  G.origin()
  G.translate(p.x+(uw-renderer.WIDTH)*p.scaleX/2, p.y+(uh-renderer.HEIGHT)*p.scaleY/2)
  G.scale(p.scaleX,p.scaleY)
  local ok, err = pcall(draw)
  G.pop()
  if not ok then error(err,0) end
end
function M.draw(owner, renderer, viewport, zones, overlay)
  local G = love.graphics
  G.push('all')
  G.origin();G.setShader();G.setScissor();G.setColor(1,1,1,1);G.setBlendMode('alpha')
  local ok, err = pcall(owner.drawWidescreen, owner, viewport.width, viewport.height)
  G.pop()
  if not ok then error(err,0) end
  -- The classic canvas contains only states above this owner. Reapply it
  -- after the high-resolution drawer so a native textbox keeps its parent.
  if overlay then
    local p = renderer.uiPresentation
    if not p then
      p = {x=viewport.gameX,y=viewport.gameY,scaleX=viewport.scale/(viewport.dpiX or 1),scaleY=viewport.scale/(viewport.dpiY or 1)}
    end
    G.push('all');G.origin();G.setShader();G.setColor(1,1,1,1);G.setBlendMode('alpha','premultiplied')
    local overlayOK, overlayError = pcall(renderer.blitCanvas,renderer,renderer.canvas,p.scaleX,p.scaleY,zones,p.scaleX,p.scaleY,
      p.x,p.y,0,0,viewport.width,viewport.height,viewport.dpiX or 1,viewport.dpiY or 1)
    G.pop()
    if not overlayOK then error(overlayError,0) end
  end
end
return M
