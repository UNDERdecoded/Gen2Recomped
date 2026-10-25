package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local E = require("src.import.RomExtractorGen3")
T.eq(E.STAGE_COUNT, #E.DATA_STAGES + #E.ASSET_STAGES, "import progress includes every registered stage")
local Import = require("src.import.Gen3SubstituteArt")
local Fixture = dofile("tests/substitute_art/fixture.lua")
local previousImage = love.image
love.image = { newImageData = Fixture.image }
local function literal(raw)
  local size, out = #raw, { string.char(16, #raw % 256, math.floor(#raw / 256), 0) }
  for i = 1, size, 8 do
    out[#out + 1] = string.char(0)
    for j = i, math.min(size, i + 7) do
      out[#out + 1] = string.char(raw[j])
    end
  end
  return table.concat(out)
end
local palette, front, back = {}, {}, {}
for i = 1, 32 do
  palette[i] = 0
end
palette[1], palette[2] = 0xB2, 0x63 -- transparent RGB is retained too
palette[3], palette[4] = 31, 0
palette[5], palette[6] = 0xE0, 3
for i = 1, 2048 do
  front[i], back[i] = 0x21, 0x12
end
front[2] = 0x10
local function extractor(change)
  local symbols = { gSubstituteDollPal = 0, gSubstituteDollFrontGfx = 64, gSubstituteDollBackGfx = 4096 }
  local bytes = literal(palette)
  bytes = bytes .. string.rep("\0", 64 - #bytes) .. literal(front)
  bytes = bytes .. string.rep("\0", 4096 - #bytes) .. literal(back)
  if change then
    bytes, symbols = change(bytes, symbols)
  end
  local e, writes, images = E.new(bytes, "firered", { symbols = symbols }), {}, {}
  e.saveImage = function(_, image, path)
    images[path] = image
  end
  e.write = function(_, name, value)
    writes[name] = value
  end
  return e, writes, images
end
local e, writes, images = extractor()
local record = assert(Import.extract(e))
T.eq(record.width, 64, "native doll keeps its full OAM width")
T.eq(writes.constants.gen3SubstituteArt, record, "only decoded art is advertised to runtime")
local r, g, b, a = images["battle/substitute_front.png"]:getPixel(0, 0)
T.same({ r, g, b, a }, { 248 / 255, 0, 0, 1 }, "low nibble is the left pixel")
r, g, b, a = images["battle/substitute_front.png"]:getPixel(1, 0)
T.same({ r, g, b, a }, { 0, 248 / 255, 0, 1 }, "high nibble is the right pixel")
r, g, b, a = images["battle/substitute_front.png"]:getPixel(2, 0)
T.same({ r, g, b, a }, { 144 / 255, 232 / 255, 192 / 255, 0 }, "transparent native RGB is retained")
r, g, b, a = images["battle/substitute_back.png"]:getPixel(0, 0)
T.same({ r, g, b, a }, { 0, 248 / 255, 0, 1 }, "front and back are separate cartridge sheets")
for _, change in ipairs({
  function(bytes, symbols)
    symbols.gSubstituteDollPal = nil
    return bytes, symbols
  end,
  function(bytes, symbols)
    symbols.gSubstituteDollBackGfx = #bytes
    return bytes, symbols
  end,
  function(bytes, symbols)
    return bytes:sub(1, 64) .. string.char(0) .. bytes:sub(66), symbols
  end,
  function(bytes, symbols)
    return bytes:sub(1, 6) .. string.char(128) .. bytes:sub(8), symbols
  end,
  function(bytes, symbols)
    return bytes:sub(1, 4096) .. string.char(16, 1, 0, 0), symbols
  end,
}) do
  local invalid, invalidWrites, invalidImages = extractor(change)
  T.eq(Import.extract(invalid), nil, "malformed/missing art is refused")
  T.eq(next(invalidWrites), nil, "invalid art cannot advertise a partial record")
  T.eq(next(invalidImages), nil, "all three blobs validate before any image write")
end
local V, Draw = require("src.core.GameVersion"), require("src.battle.Gen3SubstituteArt")
V.set("firered")
local raw = {
  singles = { { x = 72, y = 80 }, { x = 176, y = 40 } },
  doubles = { { x = 32, y = 80 }, { x = 200, y = 40 }, { x = 90, y = 88 }, { x = 152, y = 32 } },
}
local battle = {
  data = { constants = { gen3SubstituteArt = record, gen3BattlerCoords = raw } },
  isDouble = function(self)
    return self.double
  end,
  gen3AnimShake = function()
    return -5, 2
  end,
  gen3SurfaceWidth = function()
    return 320
  end,
}
local graphics, Assets = love.graphics, require("src.render.Assets")
local originalDraw, originalNewImage = graphics.draw, graphics.newImage
local drawn = {}
graphics.newImage = function(path)
  local relative = path:gsub("^assets/generated/", "")
  local image = images[relative]
  if not image then
    return originalNewImage(path)
  end
  image.path = path
  return image
end
graphics.draw = function(...)
  drawn[#drawn + 1] = { ... }
end
Assets.flush()
graphics.setColor(0.2, 0.4, 0.6, 0.7)
for _, double in ipairs({ false, true }) do
  battle.double = double
  for id = 0, double and 3 or 1 do
    local player = id % 2 == 0
    local actor = { position = id, isPlayer = player }
    local pose = assert(Draw.pose(battle, actor))
    local point = (double and raw.doubles or raw.singles)[id + 1]
    T.eq(pose.image, player and record.back or record.front, "each slot selects its native facing")
    T.eq(pose.x, point.x + 40 - 32 - 5, "native OAM X includes centered wide field and live offset")
    T.eq(pose.y, point.y + (player and 17 or 16) - 32 + 2, "native OAM Y uses the Substitute coordinate")
    require("src.battle.BattleState").drawSubstituteDoll(battle, actor)
    local call = drawn[#drawn]
    T.eq(call[1].path, pose.image, "actual battle renderer loads the imported facing through Assets")
    T.same({ call[2], call[3] }, { pose.x, pose.y }, "actual draw uses native coordinates and live offsets")
    T.same({ graphics.getColor() }, { 0.2, 0.4, 0.6, 0.7 }, "doll drawing preserves graphics color state")
  end
end
local paints = {}
battle.gen3AnimTint = function()
  return 1, 1, 1, 0.5
end
graphics.draw = function(...)
  paints[#paints + 1] = { args = { ... }, color = { graphics.getColor() }, blend = graphics.getBlendMode() }
end
graphics.setBlendMode("alpha")
T.check(Draw.draw(battle, { position = 0, isPlayer = true }), "native doll accepts live palette fade")
T.eq(#paints, 2, "actual renderer composites both native palette contributions")
T.same(paints[1].color, { 0.1, 0.2, 0.3, 0.7 }, "base draw retains incoming alpha and untinted contribution")
T.same(paints[2].color, { 0.5, 0.5, 0.5, 0.7 }, "white contribution retains incoming alpha")
T.eq(paints[2].blend, "add", "palette contribution adds through sprite coverage")
T.eq(graphics.getBlendMode(), "alpha", "native palette draw restores blend state")
T.same({ graphics.getColor() }, { 0.2, 0.4, 0.6, 0.7 }, "native palette draw restores incoming color")
local B, actor = require("src.battle.BattleState"), { position = 0, isPlayer = true }
battle.gen3AnimMonBgHidden = function()
  return false
end
battle.gen3AnimRotate = function() end
battle.gen3AnimSquash = function() end
battle.gen3AnimSpecialMonState = B.gen3AnimSpecialMonState
battle.battlerPic = function()
  return images["battle/substitute_back.png"]
end
battle.drawBattlerPicAt = function(self, user)
  B.drawSubstituteDoll(self, user)
end
battle._gbaEffectPresentation = { user = actor, alpha = 0.5 }
paints = {}
B.drawBattlerPic(battle, actor, 0, 0, 1)
T.eq(#paints, 2, "complete battler wrapper retains native doll palette draws")
T.eq(paints[1].color[4], 0.35, "real battler wrapper applies native fade alpha to the doll")
T.eq(paints[2].color[4], 0.35, "palette contribution shares native fade alpha")
T.same({ graphics.getColor() }, { 0.2, 0.4, 0.6, 0.7 }, "complete battler wrapper restores incoming alpha")
graphics.draw, graphics.newImage = originalDraw, originalNewImage
Assets.flush()
V.set("red")
T.eq(Draw.pose(battle, { isPlayer = true }), nil, "legacy rendering is forwarded")
love.image = previousImage
T.finish("native GBA Substitute art import and placement")
