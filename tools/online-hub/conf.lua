-- The Link Hub runs headless: no window, no graphics, no audio.
function love.conf(t)
  t.identity = "pokeport_link_hub"
  t.console = true
  t.window = false
  t.modules.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.joystick = false
  t.modules.keyboard = false
  t.modules.mouse = false
  t.modules.touch = false
  t.modules.image = false
  t.modules.font = false
  t.modules.video = false
  t.modules.physics = false
end
