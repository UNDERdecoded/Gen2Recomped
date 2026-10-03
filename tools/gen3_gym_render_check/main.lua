-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).
-- Run with lovec tools/gen3_gym_render_check <Emerald cache> [PNG directory].
-- Uses real GPU rendering; the black space outside each small gym room is
-- intentional. A room arrival must contain the extracted tileset's art.
function love.load(args)
  package.path = love.filesystem.getWorkingDirectory() .. '/?.lua;' .. package.path
  local ok, err = pcall(function()
    local dataset = args[1] or 'G:/Gen2Recomped/emerald'
    local data = {}
    for _, name in ipairs({'maps','tilesets','map_tilesets','constants'}) do
      data[name] = assert(loadfile(dataset .. '/data/generated/' .. name .. '.lua'))()
    end
    require('src.core.GameVersion').set('emerald')
    local map = require('src.world.MapLoader').load(data, 'MAP_G08_N01')
    local canvas = love.graphics.newCanvas(240,160)
    local output = args[2]
    local doors = 0
    for i, warp in ipairs(map.def.warps) do
      if warp.destMap == map.id then
        local dest = map.def.warps[warp.destWarp]
        local cx,cy = dest.x*16 + 16-120,dest.y*16+8-80
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0,0,0,1)
        love.graphics.setColor(1,1,1,1)
        map.renderer:draw(cx,cy,240,160)
        map.renderer:drawAbove(cx,cy,240,160)
        love.graphics.setCanvas()
        local image = canvas:newImageData()
        local lit = 0
        for y=0,159,2 do for x=0,239,2 do
          local r,g,b = image:getPixel(x,y)
          if r+g+b > .1 then lit = lit+1 end
        end end
        assert(lit > 1000, 'warp '..i..' rendered a black room: '..lit..' lit samples')
        if output then
          local f = assert(io.open(output..'/gym-warp-'..i..'.png','wb'))
          f:write(image:encode('png'):getString()); f:close()
        end
        doors = doors + 1
      end
    end
    print('PASS: '..doors..' gym room arrivals contain visible ROM art')
  end)
  if not ok then print('FAIL: '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
