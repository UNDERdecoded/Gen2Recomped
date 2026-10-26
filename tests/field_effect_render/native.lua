-- Native Gen2 drawing oracle. Does not derive any geometry from public rows.
local M = {}
function M.attach(f)
  local Overworld = require("src.world.OverworldController")
  local Sprite = require("src.render.SpriteRenderer")
  -- Native methods use the engine's resident singleton; production reader uses
  -- loader.game. Both intentionally point to this ROM-free scene.
  local bound = false
  for i = 1, 30 do
    local name = debug.getupvalue(Overworld.drawGen3Grass, i)
    if name == "Game" then
      debug.setupvalue(Overworld.drawGen3Grass, i, f.game)
      bound = true
      break
    end
  end
  assert(bound, "native Game upvalue changed; update test oracle")
  setmetatable(f.world, { __index = Overworld })
  f.imageKinds = {}
  for _, kind in ipairs({ "ripple", "sparkle" }) do
    local sprite = Sprite.new(f.game.data.sprites[kind:upper()])
    f.world[kind == "ripple" and "_rippleSprite" or "_sparkleSprite"] = sprite
    f.imageKinds[sprite.image] = kind
  end
  function f.setClock(clock)
    f.world.ripples[1].clock = clock
    f.world.sparkles[1].clock = clock
    f.player.progress = clock % 17
  end
  function f.drawNative(layer, camera)
    if layer == "ground" then
      f.world:drawRipples(camera.x, camera.y)
    elseif layer == "front" then
      f.world:drawSparkles(camera.x, camera.y)
    else
      for _, e in ipairs(f.world.entities) do
        if not e.hidden then
          if f.world.map:isGrassCell(e.cellX, e.cellY) then
            f.world:drawGen3Grass(e.cellX, e.cellY, camera.x, camera.y, f.world:gen3GrassFrame(e, false))
          end
          if e.targetX and f.world.map:isGrassCell(e.targetX, e.targetY) then
            f.world:drawGen3Grass(e.targetX, e.targetY, camera.x, camera.y, f.world:gen3GrassFrame(e, true))
          end
        end
      end
      if f.world.grassImage then
        f.imageKinds[f.world.grassImage] = "grass"
      end
    end
  end
  return f
end
return M
