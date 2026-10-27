function love.conf(t)
 t.identity=assert(os.getenv('POKEPORT_IDENTITY'));assert(t.identity:match('^oasc%-gen2recomp%-qa%-mapviews%-'))
 t.version='12.0';t.window=false
 t.modules.graphics=false;t.modules.audio=false;t.modules.joystick=false;t.modules.physics=false
end
