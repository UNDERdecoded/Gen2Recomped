-- Native indexed picture replacements. Full six/seven-tile boxes compose
-- with the existing palette, resize, slide and lifted-row draw owners.
local Version=require('src.core.GameVersion')
local Pictures=require('src.battle.Gen2PicturePresentation')
local M={}
function M.back(screen,b)
  if screen._gen2PicBack~=nil then return screen._gen2PicBack end
  return b.isPlayer
end
local function record(screen)
  local anims=screen.data and screen.data.battle_anims
  local art=anims and anims.pictureArt
  return art and art.version==1 and art or nil
end
function M.replacement(screen,b,back)
  if not(Version.isGen2() and b)then return end
  -- Keep the native faint picture owner; a combat substitute cannot replace
  -- the Pokemon while that owner's cropped sink is running.
  if b.fainted or screen:fxFaintActive(b)then return end
  local art=record(screen)
  local kind=Pictures.override(screen,b)
  local row=art and type(kind)=='string' and art[kind]
  if not row then return end
  if back==nil then back=M.back(screen,b)end
  local path=row[back and 'player'or'enemy']
  local images=screen._gen2PictureImages
  if not(type(path)=='string' and images)then return end
  local pal=images.palette(screen.data,b.mon.species,
    require('src.pokemon.Pokemon').isShiny(b.mon))
  return images.load(path,pal,false),kind
end
function M.install(Screen,images)
  Screen._gen2PictureImages=images
  function Screen:gen2ObjectPictureSource(side)
    if not Version.isGen2()then return end
    local b=self[side]
    if not b then return end
    local art=record(self)
    local kind=Pictures.override(self,b)
    local row=art and type(kind)=='string'and art[kind]
    local path=row and row[side]
    if path then return {path=path}end
    local image=Pictures.sprite(self,b)
    local meta=images.source(image)
    if meta then return {path=meta.path,crop=meta.crop,trueColor=meta.trueColor}end
  end
  local sprite=Screen.pictureSprite
  function Screen:pictureSprite(b)
    return M.replacement(self,b) or sprite(self,b)
  end
  local pic=Screen.battlerPic
  function Screen:battlerPic(b)
    local replacement=M.replacement(self,b)
    if replacement then return self:picImage(replacement)end
    return pic(self,b)
  end
  local path=Screen.pictureScalePath
  function Screen:pictureScalePath(b,value)
    if M.replacement(self,b)then
      return images.path(Pictures.sprite(self,b)) or value
    end
    return path(self,b,value)
  end
  local doll=Screen.substituteDoll
  function Screen:substituteDoll(back)
    if not Version.isGen2()then return doll and doll(self,back)end
    local art=record(self)
    local path=art and art.substitute and art.substitute.sheet
    if not path then return end
    -- Public source callers own their palette operation. Return indexed art,
    -- not an already coloured/register-remapped capture.
    local image=images.load(path,nil,false)
    if not image then return end
    local cached=self._gen2DollQuads
    if not(cached and cached.image==image)then
      local w,h=image:getDimensions()
      cached={image=image,front=love.graphics.newQuad(0,0,16,16,w,h),
        back=love.graphics.newQuad(0,16,16,16,w,h)}
      self._gen2DollQuads=cached
    end
    return image,back and cached.back or cached.front
  end
end
return M
