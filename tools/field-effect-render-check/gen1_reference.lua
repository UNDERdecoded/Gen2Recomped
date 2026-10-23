-- Explicit test-only Gen1 extension. Native Gen1 has no public field-data API.
-- Independently reads Game3 FieldEffects/FxRse records; never imports Gen2 code.
local M = {}
function M.install(Loader, f)
  local original = Loader._api
  Loader._api = function(loader, mod)
    local api = original(loader, mod)
    local data = rawget(api, "renderData") or {}
    api.renderData = data
    f.data = data
    function data:supportsFieldEffects(version, kind)
      return version == 1 and (kind == nil or kind == "grass" or kind == "ripple" or kind == "sparkle")
    end
    function data:fieldEffects(version, mapId)
      if version ~= 1 then
        return nil, "unsupported field effect version"
      end
      if mapId ~= "A" then
        return nil, "active map changed"
      end
      local out = {}
      local function add(kind, layer, index, frame, x, y, crop, owner)
        local s = f.sources[kind]
        local h = crop and 8 or 16
        out[#out + 1] = {
          id = kind .. ":" .. index,
          kind = kind,
          mapId = mapId,
          layer = layer,
          ownerId = owner,
          order = #out + 1,
          groundX = x + 8,
          groundY = y + 16,
          animationClock = f.clock,
          sheetId = "field:" .. kind,
          frame = frame,
          flipX = false,
          flipY = false,
          draw = { x = x, y = y, width = 16, height = h },
          source = { x = 0, y = frame * 16 + (crop and 8 or 0), width = 16, height = h },
          pixelSnap = "none",
          terrainOcclusion = kind == "ripple" and "reflectionCover" or "none",
        }
      end
      -- Native drawBehind paints a base pad as well as the cropped feet cover.
      local grass = f.FE._fx
      if grass then
        local frame = grass.seq and grass.frame or ({ 1, 2, 3, 4, 0 })[grass.step + 1]
        add("grass", "ground", "base", frame, grass.cx * 16, grass.cy * 16)
        local feet = f.player.py + 16
        if feet >= grass.cy * 16 + 8 and feet <= grass.cy * 16 + 18 then
          add("grass", "actorCover", "feet", frame, grass.cx * 16, grass.cy * 16 + 8, true, "player")
        end
      end
      for i, a in ipairs(f.FE._anims) do
        if a.kind == "ripple" then
          add("ripple", "ground", i, a.frame or 0, a.cx * 16, a.cy * 16 + 6)
        end
      end
      for i, e in ipairs(f.R._list) do
        if e.name == "small_sparkle" and not e.hidden and not (e.delay and e.delay > 0) then
          add(
            "sparkle",
            "front",
            i,
            e.a.frame or 0,
            math.floor(e.x - e.sheet.fw / 2),
            math.floor(e.y - e.sheet.fh / 2)
          )
          out[#out].flipX = e.a.hflip == true
          out[#out].flipY = e.a.vflip == true
        end
      end
      return {
        version = 1,
        generation = 3,
        mapId = mapId,
        cellSize = 16,
        coordinateBase = 0,
        coverage = "subset",
        supportedKinds = { "grass", "ripple", "sparkle" },
        effects = out,
      }
    end
    function data:fieldEffectSheet(version, mapId, id)
      if version ~= 1 or mapId ~= "A" then
        return nil, "stale or unsupported"
      end
      local kind = type(id) == "string" and id:match("^field:(%a+)$")
      local s = kind and f.sources[kind]
      if not s then
        return nil, "effect sheet not resident"
      end
      return {
        version = 1,
        generation = 3,
        id = id,
        format = "png",
        graphicsState = "source",
        width = 16,
        height = s.frames * 16,
        frameWidth = 16,
        frameHeight = 16,
        frames = s.frames,
        bytes = s.bytes,
      }
    end
    return api
  end
end
return M
