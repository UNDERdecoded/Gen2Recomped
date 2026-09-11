-- Voxel Tileset Editor -- LOVE configuration.
--
-- A SEPARATE DESKTOP APP, not a mode of the game.  It never loads the
-- engine, never opens a ROM and never touches a save: it reads the ROM
-- cache the game already wrote, asks the installed voxel mod's own
-- TileShape what a tile is, and writes a profile back out.
--
-- THE WINDOW IS SIZED AT RUNTIME, NOT HERE.  love.conf runs before there is
-- a window to ask about the screen, so a size written here is a guess -- and
-- the guess that shipped (1600x940) is wider than a 1080p desktop the moment
-- Windows is set to 125% or 150%, which is the default on most laptops.  The
-- window then extends past the right edge of the screen and the panel there
-- is not "cut off", it is off the display entirely, where no amount of
-- scrolling can reach it.  So: open small, then fit to the desktop in
-- love.load, where the desktop can actually be measured.
--
-- AND highdpi IS OFF.  With it on, LOVE hands back window dimensions in
-- points while the framebuffer is points x scale, and every layout number in
-- this program is a pixel.  Mixing the two is how this codebase once drew a
-- whole 3D world into the top-left corner at a third size -- the scale got
-- paid twice.  One unit, one pixel, everywhere.
function love.conf(t)
  t.identity = "Gen2Recomp-VoxelTilesetEditor"
  t.version = "11.4"
  t.console = false
  t.window.title = "Voxel Tileset Editor -- Dramatic Shape"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 820
  t.window.minheight = 560
  t.window.resizable = true
  t.window.vsync = 1
  t.window.depth = 24
  t.window.msaa = 0
  t.window.highdpi = false
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
