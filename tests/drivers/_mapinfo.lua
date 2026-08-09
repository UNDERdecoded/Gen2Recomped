-- scratch: print tileset + size for the maps named in MAPINFO
return function(game)
  local U = require("tests.drivers.util")
  U.wait(2)
  local want = (os.getenv("MAPINFO") or ""):upper()
  for id, def in pairs(game.data.maps) do
    for pat in want:gmatch("[^,]+") do
      if id:find(pat, 1, true) then
        U.log(("%-28s %-22s %dx%d blocks  ts=%s")
          :format(id, def.label or "?", def.width, def.height, def.tileset))
      end
    end
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
end
