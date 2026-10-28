-- Gen1Recomp-derived picture/register integration. GPLv3 plus Additional
-- Terms, compat/gen1-gsc/LICENSE.MD. See pinned provenance.json.
-- The existing native screen still owns images, battlers and all clocks.
local Version=require('src.core.GameVersion')
local Palette=require('src.render.Gen2PaletteDraw')
local Chrome=require('src.battle.Gen2BgPaint')
local M={}
local SIZES={[0]=6,[1]=4,[2]=2,[3]=7,[4]=5,[5]=3}

-- Per-mon CopyPals first, whole-BG BGP second. Compose indices before the
-- existing image owner bakes them; never guess shades from finished RGB.
function M.paletteByte(monByte,bgByte)
  local mon=Palette.bgpShades(monByte)
  local bg=Palette.bgpShades(bgByte)
  local out=0
  for i=0,3 do out=out+mon[bg[i+1]+1]*4^i end
  return out
end
local function withPalette(screen,side,body)
  if screen._gen2PicPaletteSide==side then return body()end
  local state=screen:animPicState(side)
  local previous=Palette.bgp
  local owner=screen._gen2PicPaletteSide
  screen._gen2PicPaletteSide=side
  Palette.setBgp(M.paletteByte(state and state.shade,previous))
  local ok,why=pcall(body)
  Palette.setBgp(previous)
  screen._gen2PicPaletteSide=owner
  if not ok then error(why,0)end
end
function M.install(Screen)
  -- Compose the native picture observation with the real BG owner. A later
  -- public method override remains visible to the actual picture drawer.
  local read=Screen.animPicState
  function Screen:animPicState(side)
    local state=read and read(self,side)
    local bg=self.anim and self.anim.bg
    if not bg then return state end
    state=state or {}
    state.hidden=state.hidden or bg.hidden[side]
    state.size,state.shade=bg.picSize[side],bg.monShade[side]
    state.slide,state.lifted=bg.slide[side]or 0,bg.liftedRows[side]
    return state
  end
  local draw=Screen.drawBattlerPic
  function Screen:drawBattlerPic(b,x,y,scale)
    if not Version.isGen2() or not(self.anim and self.anim.bg) then
      return draw(self,b,x,y,scale)
    end
    local side=b.isPlayer and 'player'or'enemy'
    local back=b.isPlayer
    if self._gen2PicBack~=nil then back=self._gen2PicBack end
    local state=self:animPicState(side)
    if state and state.hidden then return end
    if self.liftedPass and not(state and state.lifted)then return end
    if not self.liftedPass then x=x+(state and state.slide or 0)end
    local size=state and SIZES[state.size]
    if size then
      local image=self:battlerPic(b)
      if image then
        local factor=size/(back and 6 or 7)
        x=x+math.floor(image:getWidth()*scale*(1-factor)/2)
        y=y+math.floor(image:getHeight()*scale*(1-factor))
        scale=scale*factor
      end
    end
    local function paint()withPalette(self,side,function()draw(self,b,x,y,scale)end)end
    local lifted=state and state.lifted
    if not lifted then return paint()end
    local bandY=(back and 48 or 0)+lifted[1]*8
    local bandH=lifted[2]*8
    local function band(top,height)
      local g=love.graphics
      g.push('all')
      local ok,why=pcall(function()
        Chrome.clipTo(0,top,160,height)
        paint()
      end)
      g.pop()
      if not ok then error(why,0)end
    end
    if self.liftedPass then band(bandY,bandH)
    else
      if bandY>0 then band(0,bandY)end
      local below=144-bandY-bandH
      if below>0 then band(bandY+bandH,below)end
    end
  end
  local drawPic=Screen.drawPic
  if drawPic then
  function Screen:drawPic(mon,back)
    if not Version.isGen2() or not(self.anim and self.anim.bg)then
      return drawPic(self,mon,back)
    end
    local side=self.player and self.player.mon==mon and 'player'
      or self.enemy and self.enemy.mon==mon and 'enemy'
      or (back and 'player'or'enemy')
    return withPalette(self,side,function()drawPic(self,mon,back)end)
  end
  end
  function Screen:drawLiftedRows(width)
    local bg=self.anim and self.anim.bg
    local rows=bg and bg.liftedRows
    if not(rows and(rows.player or rows.enemy))then return end
    local before=self.liftedPass
    self.liftedPass=true
    local previous=Palette.setBgp(bg.bgp)
    local g=love.graphics
    g.push('all')
    local ok,why=pcall(function()
      local slide=(self.introSlide or 0)*require('src.core.Timing').BATTLE_SLIDE_PX_PER_FRAME
      if width and width>160 then
        require('src.battle.WideBattle').drawPicRegions(self,slide)
      else
        if rows.enemy then self:drawPicsLayer(slide,0,0,'enemy',true)end
        if rows.player then self:drawPicsLayer(slide,0,0,'player',true)end
      end
    end)
    g.pop()
    Palette.setBgp(previous)
    self.liftedPass=before
    if not ok then error(why,0)end
  end
end
return M
