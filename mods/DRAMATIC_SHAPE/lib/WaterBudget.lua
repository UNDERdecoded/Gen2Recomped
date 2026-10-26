-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local V = ...
local Card = {}
local Scale = V.require("RenderScale")
local Mat = V.require("Mat4")
local State = V.require("ShaderState")
local waves, waveShader, lastTime, lastSource
local layer, layerW, layerH, composite, drawing
local COMPOSITE = [[
#ifdef VERTEX
uniform mat4 vp;
uniform mat4 model;
uniform vec3 curve;
vec4 position(mat4 tp,vec4 p){
 vec4 w=model*p;vec2 d=w.xz-curve.xy;
 if(curve.z>0.0)w.y-=dot(d,d)*curve.z;
 return vp*w;
}
#endif
#ifdef PIXEL
uniform Image layer;
vec4 effect(vec4 color,Image atlas,vec2 uv,vec2 sc){
 vec4 c=Texel(layer,sc/love_ScreenSize.xy);
 if(c.a<0.5)discard;
 return c;
}
#endif
]]
function Card.enabled()
  return V.renderBudget ~= false
end
function Card.defaultLevel()
  V.require("Tier").caps()
  return (not Card.enabled() or (not Scale.mobile() and V.require("Tier").name == "high")) and 2 or 1
end
function Card.steps(steps, refine)
  local tier = V.require("Tier").caps()
  return Card.enabled() and (tier.waterRaySteps or 12) or steps or 24,
    Card.enabled() and (tier.waterRayRefine or 3) or refine or 5
end
function Card.waveTexture(time, source)
  if not Card.enabled() or waves == false then
    return nil
  end
  if not waves then
    local ok, made = pcall(love.graphics.newCanvas, 256, 256, { format = "r8", dpiscale = 1, readable = true })
    if not ok then
      waves = false
      return nil
    end
    waves = made
    waves:setFilter("linear", "linear")
    waves:setWrap("repeat", "repeat")
  end
  if source ~= lastSource then
    local ok, made = pcall(love.graphics.newShader, "uniform float waveT;\n" .. source .. [[
vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return vec4(waveRaw(uv*256.0),0.0,0.0,1.0);}
]])
    if not ok then
      waves:release()
      waves = false
      return nil
    end
    if waveShader then
      waveShader:release()
    end
    waveShader, lastSource, lastTime = made, source, nil
  end
  if lastTime ~= time then
    love.graphics.push("all")
    love.graphics.setCanvas(waves)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setDepthMode()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader(waveShader)
    waveShader:send("waveT", time)
    love.graphics.rectangle("fill", 0, 0, 256, 256)
    love.graphics.pop()
    lastTime = time
  end
  return waves
end
function Card.begin(w, h)
  if not Card.enabled() or layer == false then
    return false
  end
  local ww, hh = math.max(1, math.ceil(w / 2)), math.max(1, math.ceil(h / 2))
  if not composite then
    local ok, made = pcall(love.graphics.newShader, V.require("GraphicsCompat").shader(COMPOSITE))
    if not ok then
      layer = false
      return false
    end
    composite = made
  end
  if not layer or layerW ~= ww or layerH ~= hh then
    local ok, made = V.require("PixelCanvas").new(ww, hh)
    if not ok then
      if layer then
        layer:release()
      end
      layer = false
      return false
    end
    if layer then
      layer:release()
    end
    layer, layerW, layerH = made, ww, hh
    layer:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  local ok = pcall(love.graphics.setCanvas, { layer, depth = true })
  if not ok then
    love.graphics.pop()
    layer:release()
    layer = false
    return false
  end
  love.graphics.setScissor()
  love.graphics.setDepthMode("lequal", true)
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.clear(0, 0, 0, 0, true, true)
  drawing = true
  return true, ww, hh
end
function Card.finish()
  if drawing then
    love.graphics.pop()
    drawing = false
  end
end
function Card.composite(draws, vp, curve)
  if not (layer and composite) then
    return
  end
  love.graphics.push("all")
  love.graphics.setShader(composite)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setDepthMode("lequal", true)
  State.send(composite, "vp", "row", vp)
  State.send(composite, "curve", curve)
  State.send(composite, "layer", layer)
  for _, d in ipairs(draws) do
    State.send(composite, "model", "row", d[3] or Mat.identity())
    local mesh = d[1]
    if type(mesh) == "table" and mesh.parts then
      V.require("MeshBatch").draw(mesh, d[2])
    else
      love.graphics.draw(mesh)
    end
  end
  love.graphics.pop()
end
function Card.invalidate()
  Card.finish()
  for _, object in ipairs({ waves or false, waveShader or false, layer or false, composite or false }) do
    if object and object.release then
      object:release()
    end
  end
  waves, waveShader, lastTime, lastSource, layer, composite = nil, nil, nil, nil, nil, nil
end
return Card
