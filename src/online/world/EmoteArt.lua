-- The bubbles a world player raises over their head, in the running game's
-- own art where it has one (docs/online-design.md 2.8 "emote"):
--
--   Gen 4 / 5   data.gen4_emotes[kind] (Platinum/HGSS fldeff "!" and "!!";
--               Black/White's named bubbles where the cache has them)
--   Gen 3       data.constants.gen3Emotes[role].image (Hoenn's "!", "?" and
--               heart icons, frame 0)
--   Gen 1 / 2   data.field.emotionBubbles (the emotion_bubbles sheet:
--               "!", "?", happy)
--
-- and a drawn bubble with the symbol for anything the game has no art for.
--
--   EmoteArt.draw(data, e, cx, bottomY)  -- centred on cx, bottom edge at bottomY
--
-- Images are made once per dataset and kept.

local EmoteArt = {}

-- which cartridge art answers which world emote
local G4 = { ["!"] = "exclamation", ["?"] = "question", note = "note", ["..."] = "dots",
             heart = "heart", smile = "smile" }
local G3 = { ["!"] = "exclamation", ["?"] = "question", heart = "heart" }
local GB = { ["!"] = 1, ["?"] = 2, smile = 3 }

local cache = setmetatable({}, { __mode = "k" })

local function store(data)
  local c = cache[data]
  if not c then c = {} cache[data] = c end
  return c
end

local function gen4Image(data, kind)
  local c = store(data)
  local key = "g4:" .. kind
  if c[key] ~= nil then return c[key] end
  local rec = data.gen4_emotes and data.gen4_emotes[kind]
  local img = false
  if type(rec) == "table" and rec.rgba and rec.width and rec.height then
    local ok, made = pcall(function()
      local id = love.image.newImageData(rec.width, rec.height, "rgba8", rec.rgba)
      local im = love.graphics.newImage(id)
      im:setFilter("nearest", "nearest")
      return im
    end)
    img = ok and made or false
  end
  c[key] = img
  return img
end

local function gen3Image(data, role)
  local c = store(data)
  local key = "g3:" .. role
  if c[key] ~= nil then return c[key] end
  local icons = data.constants and data.constants.gen3Emotes
  local rec = icons and icons[role]
  local out = false
  if rec and rec.image then
    local ok, img = pcall(require("src.render.Assets").image, rec.image)
    if ok and img then
      local fw, fh = tonumber(rec.width) or 16, tonumber(rec.height) or 16
      local iw, ih = img:getDimensions()
      out = { img = img, quad = love.graphics.newQuad(0, 0, fw, fh, iw, ih), w = fw, h = fh }
    end
  end
  c[key] = out
  return out
end

-- The Game Boy sheet is OBJ art shown through OBP0 = %11010000 ("3100"),
-- as OverworldController's obpEmoteImage bakes it: OBJ colours 0 and 1 are
-- white, 2 light grey, 3 black.  Blitting the raw sheet left the bubble's
-- inside grey.  Colour 0's alpha keys the corners out and is kept.
function EmoteArt.obpImage(path)
  local Assets = require("src.render.Assets")
  if not (love.image and love.image.newImageData and Assets.imageData) then
    return Assets.image(path)
  end
  local id = Assets.imageData(path)
  id = id:clone()
  id:mapPixel(function(_, _, r, _, _, a)
    local v = 0
    if r > 0.5 then v = 1
    elseif r > 0.17 then v = 170 / 255 end
    return v, v, v, a
  end)
  local img = love.graphics.newImage(id)
  img:setFilter("nearest", "nearest")
  return img
end

local function gbImage(data, index)
  local c = store(data)
  local key = "gb:" .. index
  if c[key] ~= nil then return c[key] end
  local bubble = data.field and data.field.emotionBubbles
  local rect = bubble and bubble.bubbles and bubble.bubbles[index]
  local out = false
  if bubble and bubble.path and rect then
    local ok, img = pcall(EmoteArt.obpImage, bubble.path)
    if ok and img then
      local iw, ih = img:getDimensions()
      out = { img = img, quad = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, iw, ih),
              w = rect.w, h = rect.h }
    end
  end
  c[key] = out
  return out
end

local SYMBOL = { ["!"] = "!", ["?"] = "?", smile = ":)" }

-- the shapes a font may not have: a heart, a note, three dots
local function drawShape(e, cx, cy)
  local g = love.graphics
  if e == "heart" then
    g.setColor(0.86, 0.16, 0.3, 1)
    g.circle("fill", cx - 2, cy - 1, 2.6)
    g.circle("fill", cx + 2, cy - 1, 2.6)
    g.polygon("fill", cx - 4.6, cy, cx + 4.6, cy, cx, cy + 4.5)
    return true
  elseif e == "note" then
    g.setColor(0.1, 0.25, 0.75, 1)
    g.ellipse("fill", cx - 1.5, cy + 2.5, 2.6, 2)
    g.rectangle("fill", cx + 0.5, cy - 4, 1.3, 6.5)
    g.polygon("fill", cx + 1.8, cy - 4, cx + 4.5, cy - 2, cx + 1.8, cy - 1.5)
    return true
  elseif e == "..." then
    g.setColor(0, 0, 0, 1)
    for i = -1, 1 do g.rectangle("fill", cx + i * 3 - 1, cy + 1, 2, 2) end
    return true
  end
  return false
end

local function drawnBubble(e, cx, bottom)
  local g = love.graphics
  local text = SYMBOL[e]
  local font = g.getFont()
  local w = math.max(14, text and (font:getWidth(text) + 6) or 14)
  local h = 14
  local x, y = math.floor(cx - w / 2), math.floor(bottom - h - 3)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x, y, w, h, 3, 3)
  g.polygon("fill", cx - 3, y + h - 1, cx + 3, y + h - 1, cx, y + h + 3)
  g.setColor(0, 0, 0, 1)
  g.setLineWidth(1)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  if not drawShape(e, math.floor(cx) + 0.5, y + h / 2) then
    g.setColor(0, 0, 0, 1)
    text = text or "?"
    g.print(text, math.floor(cx - font:getWidth(text) / 2), y + math.floor((h - font:getHeight()) / 2))
  end
  g.setColor(1, 1, 1, 1)
end

-- the source this game will draw `e` with: "gen4", "gen3", "gb" or "drawn"
function EmoteArt.source(data, e)
  if not data then return "drawn" end
  if data.gen4_emotes and G4[e] and data.gen4_emotes[G4[e]] then return "gen4" end
  local icons = data.constants and data.constants.gen3Emotes
  if icons and G3[e] and icons[G3[e]] then return "gen3" end
  local bubble = data.field and data.field.emotionBubbles
  if bubble and GB[e] and bubble.bubbles and bubble.bubbles[GB[e]] then return "gb" end
  return "drawn"
end

function EmoteArt.draw(data, e, cx, bottom)
  local src = EmoteArt.source(data, e)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if src == "gen4" then
    local img = gen4Image(data, G4[e])
    if img then
      local w, h = img:getDimensions()
      g.draw(img, math.floor(cx - w / 2), math.floor(bottom - h))
      return
    end
  elseif src == "gen3" then
    local rec = gen3Image(data, G3[e])
    if rec then
      g.draw(rec.img, rec.quad, math.floor(cx - rec.w / 2), math.floor(bottom - rec.h))
      return
    end
  elseif src == "gb" then
    local rec = gbImage(data, GB[e])
    if rec then
      g.draw(rec.img, rec.quad, math.floor(cx - rec.w / 2), math.floor(bottom - rec.h))
      return
    end
  end
  drawnBubble(e, cx, bottom)
end

return EmoteArt
