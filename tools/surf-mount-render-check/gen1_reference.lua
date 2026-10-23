-- Test-only Gen1 host extension; no Gen2 reader or private application imports.
local M = {}
function M.install(Loader, f)
  local original = Loader._api
  Loader._api = function(loader, mod)
    local api = original(loader, mod)
    local data = rawget(api, "renderData") or {}
    api.renderData = data
    f.data = data
    function data:supportsSurfMounts(version)
      return version == 1
    end
    function data:surfMounts(version, mapId)
      if version ~= 1 then
        return nil, "unsupported surf mount data version"
      end
      if mapId ~= "A" then
        return nil, "active map changed"
      end
      local P, b, s = f.player, f.FE._surfBob, f.sheet
      local mounts = {}
      if P.surfing or P.surfHopping or P.dismounting then
        local facing = P.facing or "down"
        local step = b and math.floor(b.animClock / 48) % 2 or 0
        local frame, flip = 0, false
        if s.frames < 6 then
          local object = f.FE.manifestObject("surf_blob")
          local seq = object
            and object.anims
            and object.anims[({ down = 1, up = 2, left = 3, right = 4 })[facing] or 1]
          local cmd = seq and seq[1]
          frame = cmd and cmd[2] or 0
          flip = cmd and cmd[4] == true or false
        else
          frame = (({ down = 0, up = 2, left = 4, right = 4 })[facing] or 0) + step
          flip = facing == "right"
        end
        local ax, ay = P.px, P.py
        local state = "riding"
        if P.surfHopping then
          ax, ay = (P.targetX or P.cellX) * 16, (P.targetY or P.cellY) * 16
          state = "boarding"
        elseif P.dismounting then
          ax, ay = P.cellX * 16, P.cellY * 16
          state = "dismounting"
        end
        mounts[1] = {
          id = "surf:player",
          kind = "surf",
          state = state,
          ownerId = "player",
          mapId = mapId,
          layer = "ground",
          groundX = ax + 8,
          groundY = ay + 16,
          elevation = P.elevation or 0,
          facing = facing,
          riderPose = { x = P.px, y = P.py + (P.spriteYOffset or 0) },
          sheetId = "surf:player",
          frame = frame,
          flipX = flip,
          flipY = false,
          draw = { x = ax - 8, y = ay - 8 + (b and b.y2 or 0), width = 32, height = 32 },
          source = { x = 0, y = frame * 32, width = 32, height = 32 },
          pixelSnap = "none",
        }
      end
      return { version = 1, generation = 3, mapId = mapId, cellSize = 16, coordinateBase = 0, mounts = mounts }
    end
    function data:surfMountSheet(version, mapId, id)
      local scene, why = self:surfMounts(version, mapId)
      if not scene then
        return nil, why
      end
      if id ~= "surf:player" or #scene.mounts == 0 then
        return nil, "surf mount sheet not resident"
      end
      return {
        version = 1,
        generation = 3,
        id = id,
        format = "png",
        graphicsState = "source",
        width = 32,
        height = 32 * f.sheet.frames,
        frameWidth = 32,
        frameHeight = 32,
        frames = f.sheet.frames,
        bytes = f.bytes,
      }
    end
    return api
  end
end
return M
