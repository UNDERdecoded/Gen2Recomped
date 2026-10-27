function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'));t.version='12.0'
 assert(t.identity:match('^oasc%-gen2recomp%-qa%-'))
 t.window.width,t.window.height,t.window.vsync=160,96,0
 t.modules.audio,t.modules.joystick,t.modules.physics=false,false,false
 if t.graphics then t.graphics.renderers={assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))}end
end
