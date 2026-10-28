-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Gen2 display zones belong to the completed colour frame, after indexed
-- native BG/OBJ/UI bakes and before present/output effects. In Classic those
-- bakes are grayscale and this pass supplies the green ramp exactly once.
local P = require("src.render.PaletteFX")
local Gbc = require("src.render.Gen2PaletteDraw")
local Runtime = require("src.mods.Runtime")
local M = {}
local target
local function identity(_, zones) return zones end
function M.zones(game)
  local colors = P.presentColors()
  local zones = colors and {{x=0,y=0,w=160,h=144,colors=colors}} or nil
  if Runtime.wantsHook("render.zones") then
    zones = Runtime.call("render.zones", identity, game, zones)
  end
  return zones
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function number(n, fallback) return finite(n) and n or fallback end
-- Public complete-frame zone drawing, also used by a composition owner.
-- Coordinates retain the Gen1/Gen2 160x144 zone protocol and cover the local
-- gameplay surface; an outer GameViewport applies any physical cutout.
function M.blit(source, zones, w, h)
  local g=love.graphics
  -- push/pop restores shader identity, but not uniforms of the shared indexed
  -- shader. Borrow the palette owner's scope before resetting graphics state.
  Gbc.withRaw(nil,function()
    g.push("all")
    local ok,why=xpcall(function()
      g.origin();g.setColor(1,1,1,1);g.setShader();g.setScissor()
      for _,zone in ipairs(zones or {}) do
        local x=number(zone.x,0)*w/160
        local y=number(zone.y,0)*h/144
        local right=x+number(zone.w,160)*w/160
        local bottom=y+number(zone.h,144)*h/144
        local x1,y1=math.floor(math.max(0,x)),math.floor(math.max(0,y))
        local x2,y2=math.ceil(math.min(w,right)),math.ceil(math.min(h,bottom))
        if x2>x1 and y2>y1 then
          g.setScissor(x1,y1,x2-x1,y2-y1)
          if zone.colors==false then g.setShader();g.draw(source,0,0)
          else Gbc.withRaw(zone.colors,function()g.draw(source,0,0)end) end
        end
      end
    end,debug.traceback)
    g.pop()
    if not ok then error(why,0) end
  end)
end
function M.apply(source, zones, w, h)
  if not (type(zones)=="table" and zones[1]) then return source end
  local g=love.graphics
  if not (g.newCanvas and Gbc.available()) then return source end
  local dpi=source.getDPIScale and source:getDPIScale() or 1
  if not target or target:getWidth()~=w or target:getHeight()~=h
      or (target.getDPIScale and target:getDPIScale()~=dpi) then
    if target then target:release() end
    target=g.newCanvas(w,h,{format="normal",dpiscale=dpi,msaa=0})
    target:setFilter("nearest","nearest")
  end
  local previous={g.getCanvas()}
  Gbc.withRaw(nil,function()
    g.push("all")
    local ok,why=xpcall(function()
      g.setCanvas(target);g.origin();g.setShader();g.setScissor()
      g.setColorMask(true,true,true,true);g.setStencilTest();g.setDepthMode()
      g.setBlendMode("alpha","premultiplied");g.clear(0,0,0,1)
      M.blit(source,zones,w,h)
    end,debug.traceback)
    g.setCanvas(unpack(previous));g.pop()
    if not ok then error(why,0) end
  end)
  return target
end
function M.reset()
  if target then target:release();target=nil end
end
return M
