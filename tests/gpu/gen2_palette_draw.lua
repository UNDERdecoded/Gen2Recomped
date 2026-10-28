-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Call run() from an isolated LÖVE host, on each graphics backend.
local M = {}
function M.run()
  require('src.core.ModCompat').install()
  local G = require('src.render.GbcPalette')
  local P = require('src.render.PaletteFX')
  local V = require('src.core.GameVersion')
  local beforeVersion, beforeMode, beforeMap = V.get(), P.mode, P.shadeMap()
  V.set('crystal')
  local checks = 0
  local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
  end
  local A = {{247,239,229},{213,19,43},{23,193,79},{17,31,151}}
  local B = {{233,227,211},{7,59,199},{163,41,137},{3,11,29}}
  local shades = love.image.newImageData(4,1,'rgba8')
  for x=0,3 do local n=1-x/3;shades:setPixel(x,0,n,n,n,1-x/4) end
  local image = love.graphics.newImage(shades);image:setFilter('nearest','nearest')
  local canvas = love.graphics.newCanvas(4,12,{format='rgba8',dpiscale=1})
  local expected = {}
  local function draw(row, palette, keyed, tint)
    love.graphics.setColor(unpack(tint or {1,1,1,1}))
    love.graphics.draw(image,0,row)
    expected[row] = {palette=palette,keyed=keyed,tint=tint or {1,1,1,1}}
  end
  love.graphics.push('all')
  local ok, why = pcall(function()
    love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
    love.graphics.setBlendMode('replace','premultiplied')
    check(G.with(A,function()draw(0,A,false,{0.5,0.75,1,0.8})end),'normal draw unavailable')
    check(G.keyedWith(A,function()draw(1,A,true)end),'keyed draw unavailable')
    G.withRaw(A,function()
      draw(2,A)
      G.withRaw(B,function()draw(3,B)end)
      draw(4,A)
      local success,err=pcall(function()G.withRaw(B,function()error('nested failure',0)end)end)
      check(not success and err=='nested failure','nested callback error lost')
      draw(5,A)
      G.keyedWith(B,function()draw(6,B,true)end)
      draw(7,A)
    end)
    P.setShadeMap({[0]=3,[1]=2,[2]=1,[3]=0})
    G.with(A,function()draw(8,{A[4],A[3],A[2],A[1]})end)
    G.withRaw(A,function()draw(9,A)end)
    local foreign=love.graphics.newShader([[
      vec4 effect(vec4 tint,Image image,vec2 uv,vec2 screen){return vec4(0.2,0.4,0.6,0.8);}
    ]])
    love.graphics.setShader(foreign)
    G.withRaw(B,function()draw(10,B)end)
    check(love.graphics.getShader()==foreign,'foreign shader identity not restored')
    love.graphics.setColor(1,1,1,1);love.graphics.draw(image,0,11)
    love.graphics.setCanvas();love.graphics.setShader()
    local pixels=canvas:newImageData()
    for row,expect in pairs(expected)do
      for x=0,3 do
        local r,g,b,a=pixels:getPixel(x,row)
        local rgb=expect.palette[x+1];local tint=expect.tint
        local wanted={rgb[1]/255*tint[1],rgb[2]/255*tint[2],rgb[3]/255*tint[3],
          expect.keyed and x==0 and 0 or (1-x/4)*tint[4]}
        for c,value in ipairs({r,g,b,a})do
          check(math.abs(value-wanted[c])<=2/255,'pixel mismatch row '..row..' shade '..x..' channel '..c)
        end
      end
    end
    for x=0,3 do
      local pixel={pixels:getPixel(x,11)}
      for c,n in ipairs({0.2,0.4,0.6,0.8})do check(math.abs(pixel[c]-n)<=2/255,'foreign shader pixel not restored')end
    end
  end)
  love.graphics.pop()
  P.setShadeMap(beforeMap);P.setMode(beforeMode);V.set(beforeVersion)
  if not ok then error(why,0)end
  return {passed=true,checks=checks,scope='GPU pixel equality for shade palette, tint, alpha, keying, nested success/error and foreign shader restoration'},canvas
end
return M
