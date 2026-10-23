-- Mod-owned billboard resources. Only the public mount data handle is used.
local M = {}
function M.new(data)
  if not data or not data.supportsSurfMounts or not data:supportsSurfMounts(1) then
    return nil, "mount render data v1 unavailable"
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
    local scene, err = data:surfMounts(1, frame.mapId)
    if not scene then
      self:invalidate()
      return nil, err
    end
    local wanted, visible = {}, {}
    local camera = frame.camera
    self.camera = { x = camera.x, y = camera.y }
    for _, a in ipairs(scene.mounts) do
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
      local source, why = data:surfMountSheet(1, frame.mapId, id)
      if not source then
        self:invalidate()
        return nil, why
      end
      sources[id] = source
    end
    -- Tail guard after all file observations: never draw a stale-world scene.
    local tail, why = data:surfMounts(1, frame.mapId)
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
          local file = love.filesystem.newFileData(source.bytes, "mount.png")
          local decoded, pixels = pcall(love.image.newImageData, file)
          file:release()
          if not decoded then
            error(pixels)
          end
          local w, h = pixels:getDimensions()
          if w ~= source.width or h ~= source.height then
            pixels:release()
            error("mount image changed")
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
        end
      end
    end)
    if not ok then
      self:invalidate()
      return nil, reason
    end
    local built, failure = pcall(function()
      for _, mount in ipairs(visible) do
        local r = mount.source
        local key = table.concat({ r.x, r.y, r.width, r.height }, ":")
        local row = self.sheets[mount.sheetId]
        if not row.quads[key] then
          local source = sources[mount.sheetId]
          row.quads[key] = love.graphics.newQuad(r.x, r.y, r.width, r.height, source.width, source.height)
        end
      end
    end)
    if not built then
      self:invalidate()
      return nil, failure
    end
    return visible
  end
  -- Invoke inside a world-pass callback, after selecting its camera transform.
  -- A 3D consumer can use prepare() and place the same textures itself.
  function self:draw(mounts, layer, ownerId)
    if layer ~= "ground" and layer ~= "actorUnderlay" then
      return nil, "explicit mount layer required"
    end
    if layer == "actorUnderlay" and not ownerId then
      return nil, "mount owner required"
    end
    local count = 0
    love.graphics.setColor(1, 1, 1, 1)
    for _, m in ipairs(mounts) do
      if m.layer == layer and (layer ~= "actorUnderlay" or m.ownerId == ownerId) then
        local row, d, r = self.sheets[m.sheetId], m.draw, m.source
        local c = self.camera
        local x, y = d.x, d.y
        if m.pixelSnap == "floorRelative" then
          x, y = math.floor(x - c.x) + c.x, math.floor(y - c.y) + c.y
        end
        love.graphics.draw(
          row.image,
          row.quads[table.concat({ r.x, r.y, r.width, r.height }, ":")],
          x + (m.flipX and d.width or 0),
          y + (m.flipY and d.height or 0),
          0,
          m.flipX and -1 or 1,
          m.flipY and -1 or 1
        )
        count = count + 1
      end
    end
    return count
  end
  return self
end
return M
