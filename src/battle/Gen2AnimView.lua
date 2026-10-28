-- Native object drawing over the genuine GSC VM's emitted OAM.
-- Object layout/flip math retains Gen2AnimPlayer provenance (Cedric);
-- public owner integration by Roxas2712, see NOTICE.md and contribution licence.
-- GSC BG/OBJ register integration follows Gen1Recomp535a5ec0 under
-- compat/gen1-gsc/LICENSE.MD; inherited object-drawing rights remain intact.
local Palette = require('src.render.Gen2PaletteDraw')
local PaletteFX = require('src.render.PaletteFX')
local View = {}
View.__index = View
local slots = {
  PAL_BATTLE_OB_ENEMY=0, PAL_BATTLE_OB_PLAYER=1, PAL_BATTLE_OB_GRAY=2,
  PAL_BATTLE_OB_YELLOW=3, PAL_BATTLE_OB_RED=4, PAL_BATTLE_OB_GREEN=5,
  PAL_BATTLE_OB_BLUE=6, PAL_BATTLE_OB_BROWN=7,
}
function View.new(anims, data)
  return setmetatable({data=anims or {}, gameData=data or {}, images={}, quads={}}, View)
end
function View:image(path)
  if not path then return nil end
  if self.images[path] == nil then
    local ok, image = pcall(love.graphics.newImage, path)
    if ok and image and image.setFilter then image:setFilter('nearest','nearest') end
    self.images[path] = ok and image or false
  end
  return self.images[path] or nil
end
function View:release()
  for _, image in pairs(self.images) do
    if image and image.release then image:release() end
  end
  self.images, self.quads = {}, {}
  self:releaseBg()
end
function View:objPalette(name, battle)
  local index = slots[name] or tonumber(name)
  if index == 0 or index == 1 then
    local mon = battle and battle[index == 0 and 'enemy' or 'player']
    mon = mon and (mon.mon or mon)
    if mon then
      return PaletteFX.monPal(self.gameData, mon.species, nil,
        require('src.pokemon.Pokemon').isShiny(mon)) or PaletteFX.GRAYS
    end
  end
  return self.data.palettes and self.data.palettes[(index or 2)-2] or PaletteFX.GRAYS
end
function View:quad(gfx, tile, image)
  local sheet = self.data.gfx and self.data.gfx[gfx]
  if not sheet or tile < 0 or tile >= sheet.tiles then return nil end
  local bySheet = self.quads[gfx] or {}; self.quads[gfx] = bySheet
  if not bySheet[tile] then
    local w,h = image:getDimensions()
    local cols = sheet.cols or sheet.wide or 16
    bySheet[tile] = love.graphics.newQuad((tile%cols)*8, math.floor(tile/cols)*8, 8,8,w,h)
  end
  return bySheet[tile]
end
function View:drawObjects(runner, battle)
  local g = love and love.graphics
  if not g then return end
  g.push('all')
  local ok, err = pcall(function()
    g.setColor(1,1,1,1)
    local active,activeByte
    for _, obj in ipairs(runner:oam()) do
      local entry,index
      for i=#runner.loaded,1,-1 do
        local loaded=runner.loaded[i]
        if obj.tile>=loaded.tile and obj.tile<loaded.tile+math.max(loaded.tiles,1)then
          entry,index=loaded,obj.tile-loaded.tile
          break
        end
      end
      local sheet=entry and not entry.battler and self.data.gfx and self.data.gfx[entry.gfx]
      local image=sheet and self:image(sheet.image)
      local quad=image and self:quad(entry.gfx,index,image)
      if quad then
        local colors = self:objPalette(obj.palette, battle)
        local slot=slots[obj.palette]or tonumber(obj.palette)
        local byte=(slot==2 or slot==3)and runner.bg and runner.bg.obp0 or nil
        if colors~=active or byte~=activeByte then
          if not Palette.useRaw(Palette.remap(Palette.resolve(colors),byte))then g.setShader()end
          active,activeByte=colors,byte
        end
        local attr = obj.attr or 0
        local sx = math.floor(attr/32)%2 == 1 and -1 or 1
        local sy = math.floor(attr/64)%2 == 1 and -1 or 1
        g.draw(image,quad,obj.x-8+(sx<0 and 8 or 0),obj.y-16+(sy<0 and 8 or 0),0,sx,sy)
      end
    end
  end)
  g.pop()
  if not ok then error(err,0) end
end

-- The public runner is now the actual command/object/BG owner. A restart
-- creates a fresh runner, so retained consumers never rebind to another move.
function View.runner(player)return player.runtime end
-- BG methods use the same concrete view object as native OAM drawing.
for name,method in pairs(require('src.battle.Gen2BgView'))do View[name]=method end
return View
