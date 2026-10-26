function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'))
 t.version=love.getVersion()>=12 and '12.0'or'11.5'
 t.window.width,t.window.height,t.window.vsync=160,96,0
 t.modules.audio,t.modules.joystick,t.modules.physics=false,false,false
 local backend=os.getenv('POKEPORT_GRAPHICS_BACKEND')
 if t.graphics and backend then t.graphics.renderers={backend}end
end
