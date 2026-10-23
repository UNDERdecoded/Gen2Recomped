-- Mod-owned billboard resources. Only the public actor data handle is used.
local M = {}
function M.new(data)
  if not data or not data.supportsActors or not data:supportsActors(1) then
    return nil, "actor render data v1 unavailable"
  end
  local self = { sheets = {} }
  local function release(row)
    if not row then
      return
    end
    for _, q in pairs(row.quads) do
      q:release()
    end
    row.image:release()
  end
  function self:invalidate()
    for _, row in pairs(self.sheets) do
      release(row)
    end
    self.sheets = {}
  end
  function self:prepare(frame)
    local scene, err = data:actors(1, frame.mapId)
    if not scene then
      self:invalidate()
      return nil, err
    end
    local wanted, visible = {}, {}
    local camera = frame.camera
    for _, a in ipairs(scene.actors) do
      local d = a.draw
      if
        d.x + d.width > camera.x
        and d.y + d.height > camera.y
        and d.x < camera.x + frame.viewWidth
        and d.y < camera.y + frame.viewHeight
      then
        visible[#visible + 1] = a
        wanted[a.sheetId] = true
      end
    end
    local sources = {}
    for id in pairs(wanted) do
      local source, why = data:actorSheet(1, frame.mapId, id)
      if not source then
        self:invalidate()
        return nil, why
      end
      sources[id] = source
    end
    -- Tail guard after all file observations: never draw a stale-world scene.
    local tail, why = data:actors(1, frame.mapId)
    if not tail then
      self:invalidate()
      return nil, why
    end
    for id, row in pairs(self.sheets) do
      if not wanted[id] then
        release(row)
        self.sheets[id] = nil
      end
    end
    local ok, reason = pcall(function()
      for id, source in pairs(sources) do
        local old = self.sheets[id]
        if not old or old.bytes ~= source.bytes then
          local file = love.filesystem.newFileData(source.bytes, "actor.png")
          local decoded, pixels = pcall(love.image.newImageData, file)
          file:release()
          if not decoded then
            error(pixels)
          end
          local w, h = pixels:getDimensions()
          if w ~= source.width or h ~= source.height then
            pixels:release()
            error("actor image changed")
          end
          local made, image = pcall(love.graphics.newImage, pixels)
          pixels:release()
          if not made then
            error(image)
          end
          local row = { bytes = source.bytes, image = image, quads = {} }
          self.sheets[id] = row
          release(old)
          image:setFilter("nearest", "nearest")
          for f = 0, source.frames - 1 do
            row.quads[f] =
              love.graphics.newQuad(0, f * source.frameHeight, source.frameWidth, source.frameHeight, w, h)
          end
        end
      end
    end)
    if not ok then
      self:invalidate()
      return nil, reason
    end
    return visible
  end
  -- Invoke inside a world-pass callback, after selecting its camera transform.
  -- A 3D consumer can use prepare() and place the same textures itself.
  function self:draw(actors)
    for _, a in ipairs(actors) do
      local row, d = self.sheets[a.sheetId], a.draw
      love.graphics.draw(
        row.image,
        row.quads[a.frame],
        d.x + (a.flipX and d.width or 0),
        d.y,
        0,
        a.flipX and -1 or 1,
        1
      )
    end
  end
  return self
end
return M
