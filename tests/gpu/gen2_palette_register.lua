-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- ROM-free pixel verification in a separate LÖVE host on each backend.
local M = {}
function M.run()
  require('src.core.ModCompat').install()
  local G = require('src.render.GbcPalette')
  local P = require('src.render.PaletteFX')
  local V = require('src.core.GameVersion')
  local version, mode, map = V.get(), P.mode, P.shadeMap()
  local g = love.graphics
  local A={{251,241,239},{211,37,53},{17,181,89},{29,31,157}}
  local B={{233,227,223},{13,67,197},{163,41,131},{3,7,11}}
  local C={107,149,207}
  local shades = love.image.newImageData(4,1,'rgba8')
  local rgba = love.image.newImageData(9,1,'rgba8')
  for i=0,3 do
    local n=1-i/3;shades:setPixel(i,0,n,n,n,1-i/5)
    for p,colors in ipairs({A,B}) do
      local c=colors[i+1];rgba:setPixel((p-1)*4+i,0,c[1]/255,c[2]/255,c[3]/255,1-i/5)
    end
  end
  rgba:setPixel(8,0,C[1]/255,C[2]/255,C[3]/255,0.4)
  local indexed, colored = g.newImage(shades), g.newImage(rgba)
  indexed:setFilter('nearest','nearest');colored:setFilter('nearest','nearest')
  local canvas=g.newCanvas(17,257,{format='rgba8',dpiscale=1})
  local checks=0
  local function check(ok,why) checks=checks+1;assert(ok,why) end
  g.push('all')
  local ok,why=xpcall(function()
    V.set('crystal');P.setMode('gbc')
    g.setCanvas(canvas);g.clear(0,0,0,0);g.origin()
    g.setBlendMode('replace','premultiplied');g.setColor(0.5,0.75,1,0.8)
    local native = assert(P.shader(),'native palette shader unavailable')
    for byte=0,255 do
      G.setBgp(byte)
      check(G.use(A),'forward shader unavailable')
      g.draw(indexed,0,byte)
      -- Native PaletteFX owns the same register and the real optimized
      -- userdata upload path, rather than just a fake public shader object.
      P.sendColors(native,A);g.setShader(native);g.draw(indexed,4,byte)
      -- The explicit backward byte is independent of the standing register.
      G.setBgp(0xff)
      local applied,ambiguous=G.useRemap({A},byte,{B})
      check(applied and ambiguous==0,'backward shader unavailable or ambiguous')
      g.draw(colored,8,byte)
    end
    G.setBgp(nil)
    local display=P.displayColors
    P.displayColors=function()return B end
    local changed,changeError=pcall(function()
      if P._beginColorBatch then check(P._beginColorBatch(native)==nil,'overridden display resolver entered a trusted native batch') end
      P.sendColors(native,A);g.setShader(native);g.draw(indexed,0,256)
    end)
    P.displayColors=display
    if not changed then error(changeError,0) end
    g.setCanvas();g.setShader()
    local pixels=g.readbackTexture and g.readbackTexture(canvas) or canvas:newImageData()
    for byte=0,255 do
      for x=0,16 do
        local color,alpha
        if x<8 then
          local shade=x%4;local field=math.floor(byte/4^shade)%4
          color,alpha=A[field+1],1-shade/5
        elseif x<12 then
          local shade=x-8;local field=math.floor(byte/4^shade)%4
          color,alpha=A[field+1],1-shade/5
        elseif x<16 then color,alpha=B[x-11],1-(x-12)/5
        else color,alpha=C,0.4 end
        local wanted={color[1]/255*0.5,color[2]/255*0.75,color[3]/255,alpha*0.8}
        -- PaletteFX's native final-zone shader deliberately ignores the
        -- draw tint. The public indexed/remap shaders compose with it.
        if x>=4 and x<8 then wanted={color[1]/255,color[2]/255,color[3]/255,alpha} end
        local actual={pixels:getPixel(x,byte)}
        for c=1,4 do check(math.abs(actual[c]-wanted[c])<=2/255,
          'register '..byte..' pixel '..x..' channel '..c..' got '..actual[c]..' expected '..wanted[c])end
      end
    end
    for x=0,3 do
      local actual={pixels:getPixel(x,256)}
      local wanted={B[x+1][1]/255,B[x+1][2]/255,B[x+1][3]/255,1-x/5}
      for c=1,4 do check(math.abs(actual[c]-wanted[c])<=2/255,'native upload ignored replaced display resolver')end
    end
  end,debug.traceback)
  g.pop();P.setShadeMap(map);P.setMode(mode);V.set(version)
  indexed:release();colored:release();shades:release();rgba:release()
  if not ok then canvas:release();error(why,0) end
  return {passed=true,checks=checks,scope='All 256 BGP bytes: native and public indexed draws, composited BG permutation, OBJ preservation, unrelated RGB preservation, alpha and tint'},canvas
end
return M
