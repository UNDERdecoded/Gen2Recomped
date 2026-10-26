function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'));assert(t.identity:match('^oasc%-gen2recomp%-qa%-field%-move%-gpu%-'))
 t.version='12.0';t.gammacorrect=false;t.window.width,t.window.height=320,240;t.window.vsync=0;t.window.highdpi=false
 t.modules.audio,t.modules.joystick,t.modules.physics=false,false,false
 t.graphics.renderers={assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))}
end
