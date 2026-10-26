-- Test-only reference extension. Gen1 does not expose these methods upstream.
-- It observes real Game3 player/object-pool shapes and uses OwSprites.pose;
-- it never imports the Gen2 reader or asks asset_stream to hydrate graphics.
local R = {}
function R.install(Loader, fixture)
  local Ow = require("src.core.game3.ow_sprites")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local original = Loader._api
  Loader._api = function(loader, mod)
    local api = original(loader, mod)
    local data = rawget(api, "renderData") or {}
    api.renderData = data
    fixture.data = data
    local function sample(version, expected)
      if version ~= 1 then
        return nil, "unsupported actor data version"
      end
      if expected ~= "A" then
        return nil, "active map changed"
      end
      local actors = {}
      local function add(e, kind, mapId, ox, oy)
        if e.visible == false or e.hidden or e.invisible then
          return
        end
        local phase = kind == "player" and (e.animCmd % 2 == 0 and 1 or 0)
          or (e.moving and (e.animClock or 0) % 16 < 8 and 1 or 0)
        local step = kind == "player" and e.animCmd <= 1 or e.stepFlip == true
        local native = fixture.sprites[e.graphicsId]
        local frame, flip = Ow.pose(native, e.facing, phase, step)
        local localId = e.localId
        actors[#actors + 1] = {
          id = kind == "player" and "player" or ("npc:%d:%s:%d:%d:%d"):format(#mapId, mapId, localId, ox, oy),
          kind = kind,
          mapId = mapId,
          localId = kind == "npc" and localId or nil,
          x = e.px + ox,
          y = e.py + oy,
          groundX = e.px + ox + 8,
          groundY = e.py + oy + 16,
          elevation = e.elevation or 0,
          facing = e.facing,
          animationClock = e.observedClock or e.animClock or 0,
          moving = e.moving == true,
          surfing = false,
          spinning = false,
          sheetId = "sprite:AVATAR",
          frame = frame,
          flipX = flip,
          draw = {
            x = e.px + ox,
            y = e.py + oy + 16 - native.height,
            width = native.width,
            height = native.height,
          },
          source = { x = 0, y = frame * native.height, width = native.width, height = native.height },
        }
      end
      add(Player, "player", "A", 0, 0)
      for _, e in ipairs(Objects.poolForDraw(Objects.snapshotPool())) do
        add(e, "npc", "A", 0, 0)
      end
      for _, g in ipairs(fixture.neighbors) do
        for _, e in ipairs(Objects.poolForDraw(g.pool)) do
          add(e, "npc", g.mapId, g.x, g.y)
        end
      end
      table.sort(actors, function(a, b)
        if a.groundY ~= b.groundY then
          return a.groundY < b.groundY
        end
        if a.groundX ~= b.groundX then
          return a.groundX < b.groundX
        end
        return a.id < b.id
      end)
      return {
        version = 1,
        generation = 3,
        mapId = expected,
        coordinateBase = 0,
        cellSize = 16,
        actors = actors,
      }
    end
    function data:supportsActors(version)
      return version == 1
    end
    function data:actors(version, expected)
      return sample(version, expected)
    end
    function data:actorSheet(version, expected, sheetId)
      local s, err = sample(version, expected)
      if not s then
        return nil, err
      end
      if sheetId ~= "sprite:AVATAR" or #s.actors == 0 then
        return nil, "actor sheet not resident"
      end
      local f = assert(io.open(fixture.root .. "/tests/actor_render/assets/gen1.png", "rb"))
      local bytes = f:read("*a")
      f:close()
      return {
        version = 1,
        generation = 3,
        id = sheetId,
        format = "png",
        graphicsState = "source",
        width = 16,
        height = 288,
        frameWidth = 16,
        frameHeight = 32,
        frames = 9,
        bytes = bytes,
      }
    end
    return api
  end
end
return R
