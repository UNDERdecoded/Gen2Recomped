function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'))
 t.window.width,t.window.height=480,320;t.window.vsync=0;t.window.highdpi=false
 t.modules.audio,t.modules.joystick,t.modules.physics=false,false,false
 t.graphics=t.graphics or{};t.graphics.renderers={assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))}
end
