-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Existing mod copyright and MIT notices remain in ../LICENSE. Separate static/dynamic shadow planning; no engine records.
local V = ...
local Stamp = V.require("RenderStamp")
local Shadow = V.require("ShadowMap")
local Mesher = V.require("ChunkMesher")
local Tier = V.require("Tier")
local Card = { GRID = 256 }
local static, dynamic = Stamp.new(), Stamp.new()
local plan = { bounds = {} }
local staleFrames, lastDynamic = 0, -1000
function Card.bounds(x0, x1, z0, z1, out)
  out = out or {}
  out[1] = math.floor(x0 / Card.GRID) * Card.GRID
  out[2] = math.ceil(x1 / Card.GRID) * Card.GRID
  out[3] = math.floor(z0 / Card.GRID) * Card.GRID
  out[4] = math.ceil(z1 / Card.GRID) * Card.GRID
  return out
end
function Card.prepare(
  state,
  terrain,
  nbMesh,
  water,
  nbWater,
  posed,
  cx,
  cy,
  vw,
  vh,
  battleToken,
  animation,
  firstPerson,
  atlasFor,
  poseFrame
)
  local x0, x1, z0, z1 = Shadow.groundBounds(cx, cy, vw, vh)
  Card.bounds(x0, x1, z0, z1, plan.bounds)
  static.begin()
  local put = static.put
  for i = 1, 4 do
    put(plan.bounds[i])
  end
  put(Shadow.KX)
  put(Shadow.KZ)
  put(state.map)
  put(terrain)
  put(water)
  if atlasFor then
    put(atlasFor(state.map))
  end
  put(Mesher.flowers(state.map))
  for i, nb in ipairs(state.neighbors or {}) do
    put(nb.map)
    put(nb.ox)
    put(nb.oy)
    put(nbMesh[i])
    put(nbWater and nbWater[i])
    put(Mesher.flowers(nb.map))
    if atlasFor then
      put(atlasFor(nb.map))
    end
  end
  for i = 1, #animation do
    put(animation[i])
  end
  put(Tier.caps().shadowRes)
  plan.staticToken = static.token()
  plan.static = not Shadow.hasFrame() or not Shadow.isAnchored() or Shadow.stale(plan.staticToken)
  dynamic.begin()
  put = dynamic.put
  put(plan.staticToken)
  put(firstPerson)
  put(battleToken)
  -- Authored figures can arrive independently of the terrain mesh.
  put(Mesher.figures(state.map))
  for _, nb in ipairs(state.neighbors or {}) do
    put(Mesher.figures(nb.map))
  end
  for _, p in ipairs(posed) do
    put(p.sprite.def)
    put(p.sprite.def.image)
    put(p.px)
    put(p.py)
    put(p.gh)
    put(p.lift or 0)
    put(p.facing)
    put(p.phase)
    put(p.flip)
    put(p.frame)
    put(p.sprite:resolveImage())
    if poseFrame then
      local frame, mirror = poseFrame(p)
      put(frame)
      put(mirror)
    end
  end
  plan.dynamicToken = dynamic.token()
  plan.dynamic = plan.static or not Shadow.dynamicActive() or plan.dynamicToken ~= plan.lastDynamicToken
  if plan.dynamic then
    staleFrames = staleFrames + 1
    local hz = Tier.caps().shadowHz
    if not plan.static and hz and hz > 1 and staleFrames - lastDynamic < hz then
      plan.dynamic = false
    end
  end
  return plan
end
function Card.commitStatic()
  static.commit()
end
function Card.commitDynamic()
  dynamic.commit()
  plan.lastDynamicToken = plan.dynamicToken
  lastDynamic = staleFrames
end
return Card
