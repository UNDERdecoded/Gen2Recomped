-- Shared drawing and input for the world screens (WorldMenu, ChatOverlay,
-- GhostInteract), on WS2's CodeStyle: the running game's own font and
-- window frame, on the UI surface the game uses (160x144 / 240x160 /
-- 256x192).

local CodeStyle = require("src.ui.online.CodeStyle")

local WorldUi = {}

function WorldUi.style(game)
  return CodeStyle.new(CodeStyle.defaultKind(game))
end

function WorldUi.surface()
  return CodeStyle.surface()
end

function WorldUi.sound(game, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound and Sound.play and game and game.data then pcall(Sound.play, game.data, name or "Select") end
end

-- up/down over n rows (skipping disabled ones); returns the new index
function WorldUi.nav(game, index, rows)
  local input = game and game.input
  if not input then return index end
  local n = #rows
  if n == 0 then return index end
  local step = input:wasPressed("down") and 1 or (input:wasPressed("up") and -1 or 0)
  if step == 0 then return index end
  local i = index
  for _ = 1, n do
    i = (i - 1 + step) % n + 1
    if not rows[i].disabled then break end
  end
  if i ~= index then WorldUi.sound(game, "Select") end
  return i
end

-- a framed list: title on top, one row per line, cursor on `index`.
-- rows = { { label = "TRADE", value = "8" (right-aligned), disabled = bool } }
function WorldUi.drawList(st, x, y, w, rows, index, title, opts)
  opts = opts or {}
  local lh = st:lineHeight()
  local rowH = opts.rowH or (lh + 2)
  local first = opts.first or 1
  local visible = opts.visible or #rows
  local h = (title and (lh + 4) or 0) + math.min(#rows, visible) * rowH + 10
  st:box(x, y, w, h)
  local ty = y + 6
  local C = CodeStyle.colors
  if title then
    st:text(title, x + 8, ty)
    ty = ty + lh + 4
  end
  -- the cursor is drawn, not typed: not every cartridge font has a ">"
  local indent = 14
  for i = first, math.min(#rows, first + visible - 1) do
    local r = rows[i]
    local color = r.disabled and C.dim or nil
    if i == index then
      local cy = ty + math.floor(lh / 2)
      st:setColor(color or C.ink)
      love.graphics.polygon("fill", x + 5, cy - 3, x + 5, cy + 3, x + 9, cy)
      love.graphics.setColor(1, 1, 1, 1)
    end
    st:text(r.label, x + indent, ty, color)
    if r.value then
      local v = tostring(r.value)
      st:text(v, x + w - 8 - st:width(v), ty, r.valueColor or color)
    end
    ty = ty + rowH
  end
  return h
end

-- wrapped lines in a frame; returns the frame height
function WorldUi.drawText(st, x, y, w, text, color)
  local lh = st:lineHeight()
  local lines = {}
  for para in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    for _, l in ipairs(st:wrap(para, w - 16)) do lines[#lines + 1] = l end
    if para == "" then lines[#lines + 1] = "" end
  end
  local h = #lines * (lh + 1) + 12
  st:box(x, y, w, h)
  for i, l in ipairs(lines) do st:text(l, x + 8, y + 6 + (i - 1) * (lh + 1), color) end
  return h
end

-- a map's display name for the player list
function WorldUi.mapName(game, mapId)
  local def = game and game.data and game.data.maps and mapId and game.data.maps[mapId]
  local name = def and (def.displayName or def.name or def.label)
  if type(name) ~= "string" or name == "" then name = tostring(mapId or "?") end
  if #name > 14 then name = name:sub(1, 14) end
  return name
end

return WorldUi
