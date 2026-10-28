-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'))
 t.window.width,t.window.height,t.window.vsync=64,64,0
 t.graphics=t.graphics or{};t.graphics.renderers={assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))}
 t.modules.audio=false
end
