-- Native classic composition retained from src/battle/BattleState.lua.
-- The Gen2 scene-owner split reuses its real panels, FX and OAM; it does not
-- own battle decisions or animation time. Existing source provenance remains.
local Timing=require('src.core.Timing')
local Runtime=require('src.mods.Runtime')
local M={}
function M.install(Screen)
  function Screen:drawPanel()
  -- AskName: ClearSprites + wild ClearScreenArea -- white field under the
  -- nickname TextBox / YES/NO (naming_screen.asm); overlays draw on top.
  if self.blankForAskName then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    return
  end
  local fx = self.fx
  -- window shakes (SE_SHAKE_SCREEN / the enemy-hit vertical shake);
  -- the animations-off fallback keeps the old +-2 alternation
  local sx = (fx and fx.shakeX) or 0
  local sy = (fx and fx.shakeY) or 0
  if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
    sx = self.frame % 4 < 2 and 2 or -2
  end
  -- intro slide-in offset: 2 px per frame, so 144 px over 72 frames
  local slide = (self.introSlide or 0) * Timing.BATTLE_SLIDE_PX_PER_FRAME

  if self:colorMode() then
    -- SGB pipeline: gray BG canvas -> (wavy) -> zone recolor with the
    -- BGP fade -> mon pics -> OAM anim sprites (never BGP-faded)
    local g = love.graphics
    local wavy = fx and fx.wavy
    -- push("all")/pop restores the bound canvas, a mod's depth set included
    g.push("all")
    g.setCanvas(self.bgCanvas)
    -- The white paper the whole battle is drawn on -- unless something has
    -- put a WORLD where the paper goes, in which case painting it is what
    -- hides the world.  Clearing to transparent instead leaves only what is
    -- actually drawn (HUDs, boxes, pics) and lets the 3D frame underneath
    -- show between them.  The zone shader passes alpha through unchanged
    -- (PaletteFX.shader: `vec4(mapped, p.a)`), so transparency survives the
    -- colour pass rather than being remapped to a palette shade.
    if self:worldBackdrop() then
      g.clear(0, 0, 0, 0)
    else
      g.setColor(1, 1, 1, 1)
      g.rectangle("fill", 0, 0, 160, 144)
    end
    g.setColor(1, 1, 1, 1)
    -- the party ball rows are OBJ sprites on hardware (see drawBallRow):
    -- collect them here and draw them over the finished zone pass instead
    local balls = self:gen2BallColors() and {} or nil
    self.deferBalls = balls
    self:drawHUDs(slide)
    self.deferBalls = nil
    self:drawTextArea()
    if wavy then
      -- the mon pics are BG tiles on the GB, so SE_WAVY_SCREEN bends
      -- them too: bake them into the canvas as DMG grays and let the
      -- zone pass color them by region (exactly what the SGB did)
      self.grayPics = true
      g.setScissor(0, 0, 160, 96) -- BG pics live above the text box
      self:drawPicsLayer(slide, 0, 0)
      g.setScissor()
      self.grayPics = nil
    end
    g.pop()
    self:drawZonePass(self:applyWavy(self.bgCanvas), sx, sy)
    if balls and balls[1] then
      -- they ride the window shake with the HUD chrome they sit in
      local shifted = sx ~= 0 or sy ~= 0
      if shifted then g.push() g.translate(sx, sy) end
      g.setColor(1, 1, 1, 1)
      for _, row in ipairs(balls) do
        self:drawBallRow(row[1], row[2], row[3], row[4])
      end
      if shifted then g.pop() end
    end
    if not wavy then
      -- the pics are BG tiles in rows 0-11 on the GB: they can never
      -- cover the text box, whatever the SE offsets do (a vertical
      -- window shake moves the box down with everything else)
      g.setScissor(0, 0, 160, 96 + math.max(0, sy))
      self:drawPicsLayer(slide, sx, sy)
      g.setScissor()
    end
  else
    -- flat fallback (headless / no shader support): pre-colorized pics
    -- on white, no palette fades -- and the same exception as above, so the
    -- two paths agree about when there is paper to paint
    love.graphics.setColor(1, 1, 1, 1)
    if not self:worldBackdrop() then
      love.graphics.rectangle("fill", 0, 0, 160, 144)
    end
    local shaking = sx ~= 0 or sy ~= 0
    if shaking then
      love.graphics.push()
      love.graphics.translate(sx, sy)
    end
    self:drawPicsLayer(slide, 0, 0)
    self:drawHUDs(slide)
    self:drawTextArea()
    if shaking then
      love.graphics.pop()
    end
  end
  end

  -- panelFn replaces the BG panel; native wide layout also supplies its
  -- translated OAM pass and surface dimensions through the same real site.
  function Screen:drawSceneBody(panelFn,objectsFn,width,height)
    local g=love.graphics
    g.push('all')
    local ok,why=pcall(function()
      local panel=panelFn or function()self:drawPanel()end
      if self.anim and self.anim.bg and self.animView then
        self.animView:present(self.anim,panel,self,width or 160)
      else panel()end
      if self.blankForAskName then return end
      self:drawLiftedRows(width)
      if objectsFn then objectsFn()else self:drawAnimLayer(self:colorMode())end
      local fx=self.fx
      if fx and fx.flash and fx.flash>0 and self.frame%4<2 then
        g.setShader();g.setColor(1,1,1,.85)
        g.rectangle('fill',0,0,width or 160,height or 144)
      end
    end)
    g.pop()
    if not ok then error(why,0)end
  end
  function Screen:drawScene(bodyFn)
    if bodyFn then bodyFn()else self:drawSceneBody()end
    love.graphics.setColor(1,1,1,1)
    if Runtime.wantsHook('battle.overlay')then
      Runtime.call('battle.overlay',function()end,self)
    end
  end
end
return M
