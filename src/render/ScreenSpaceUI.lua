-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Optional window-resolution UI. Simulation/input remain native; only an
-- explicitly advertised drawer leaves the cartridge-sized UI canvas.
local NativeScreenOverlay = require('src.render.NativeScreenOverlay')
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
-- Gen2's reference renderer paints native overlays on its full-resolution
-- scene, under a cartridge-grid transform. A drawer that resets origin()
-- therefore gets real window pixels, not a 160x144 intermediate texture.
function M.hasNativeStack(stack, scene, first, world)
  for i=first,#scene.states do
    local state=scene.states[i]
    if state and state~=world and visible(stack,state) and type(state.draw)=='function' then return true end
  end
  return false
end
function M.drawNativeStack(stack, scene, first, world, renderer, viewport, opaque)
  local G=love.graphics
  G.push('all');G.origin();G.setShader();G.setScissor();G.setColor(1,1,1,1);G.setBlendMode('alpha')
  local ok,err=pcall(function()
    if opaque then G.rectangle('fill',0,0,viewport.width,viewport.height) end
    M.classic(function()
      for i=first,#scene.states do
        local state=scene.states[i]
        if state and state~=world and visible(stack,state) and type(state.draw)=='function' then
          G.push('all')
          -- Declared larger native surfaces retain their own origin. Plain
          -- GB states stay centred in a parent's expanded surface.
          if type(state.uiSize)=='function' then
            local sized,w,h=pcall(state.uiSize,state)
            if sized and type(w)=='number' and w>0 and type(h)=='number' and h>0 then
              G.translate((renderer.WIDTH-w)/2,(renderer.HEIGHT-h)/2)
            end
          end
          local drawn,why=pcall(NativeScreenOverlay.screen,state,viewport.width,viewport.height)
          G.pop()
          if not drawn then error(why,0) end
        end
      end
    end,renderer,viewport.width,viewport.height)
  end)
  G.pop()
  if not ok then error(err,0) end
end
function M.draw(owner, renderer, viewport, zones, overlay)
  local G = love.graphics
  G.push('all')
  G.origin();G.setShader();G.setScissor();G.setColor(1,1,1,1);G.setBlendMode('alpha')
  local ok, err = pcall(NativeScreenOverlay.window, owner, viewport.width, viewport.height)
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
