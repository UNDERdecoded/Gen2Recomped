-- VR: the raw OpenGL this mod is otherwise proud to never need.
--
-- OpenXR hands over its swapchain images as GL TEXTURE IDS, and LOVE never
-- exposes the GL names behind its own canvases -- so getting a rendered
-- eye from a love Canvas into a headset means dropping below LOVE for a
-- few calls a frame: discover the canvas's framebuffer, blit it into the
-- swapchain texture, and put the pipeline back exactly as LOVE believes it
-- to be. Everything here is that, and only that.
--
-- Three rules keep this safe:
--
--   discovery over spelunking. The canvas's FBO id is read from the
--   driver with documented queries (bind the canvas THROUGH LOVE, ask
--   GL_DRAW_FRAMEBUFFER_BINDING) rather than from LOVE's internals, so a
--   LOVE patch cannot move it out from under us.
--
--   restore what LOVE caches. LOVE tracks the bound framebuffer and skips
--   redundant binds, so raw binds must end back at the exact binding LOVE
--   thinks is current -- the default framebuffer, 0, since every call
--   here runs between LOVE passes -- or LOVE's next draw lands in ours.
--
--   pcall at the rim, ffi inside. The FFI setup can fail (headless, a GL
--   context without FBO entry points); it fails ONCE, at load(), and
--   callers see `nil, reason` rather than an error mid-frame.

local VRGL = {}

local ffi = nil
local gl = nil                -- opengl32 exports (GL 1.1 + wgl)
local ext = {}                -- post-1.1 entry points via wglGetProcAddress
local ready = false
local reason = nil
local fbo = nil               -- our scratch framebuffer, made once

local GL = {
  FRAMEBUFFER = 0x8D40,
  READ_FRAMEBUFFER = 0x8CA8,
  DRAW_FRAMEBUFFER = 0x8CA9,
  DRAW_FRAMEBUFFER_BINDING = 0x8CA6,
  COLOR_ATTACHMENT0 = 0x8CE0,
  COLOR_BUFFER_BIT = 0x4000,
  NEAREST = 0x2600,
  LINEAR = 0x2601,
  TEXTURE_2D = 0x0DE1,
  FRONT = 0x0404,
  BACK = 0x0405,
}
VRGL.GL = GL

local CDEF = [[
typedef void (__stdcall *PROC)();
void* wglGetCurrentDC(void);
void* wglGetCurrentContext(void);
PROC wglGetProcAddress(const char*);
unsigned int glGetError(void);
void glGetIntegerv(unsigned int pname, int* params);
void glReadBuffer(unsigned int mode);
void glFlush(void);
void glCopyTexSubImage2D(unsigned int target, int level, int xoffset,
                         int yoffset, int x, int y, int width, int height);
void glBindTexture(unsigned int target, unsigned int texture);
typedef void (__stdcall *pfn_glBindFramebuffer)(unsigned int, unsigned int);
typedef void (__stdcall *pfn_glGenFramebuffers)(int, unsigned int*);
typedef void (__stdcall *pfn_glDeleteFramebuffers)(int, const unsigned int*);
typedef void (__stdcall *pfn_glFramebufferTexture2D)(unsigned int,
    unsigned int, unsigned int, unsigned int, int);
typedef void (__stdcall *pfn_glBlitFramebuffer)(int, int, int, int,
    int, int, int, int, unsigned int, unsigned int);
]]

-- One-time FFI setup. Idempotent, and every path out records why it
-- stopped, so VR's status line can say something better than "no".
function VRGL.load()
  if ready then return true end
  if reason then return false, reason end
  local ok, err = pcall(function()
    ffi = require("ffi")
    -- cdef survives a reload; redefinition is the only error worth eating
    pcall(ffi.cdef, CDEF)
    gl = ffi.load("opengl32")
    local function proc(name, typ)
      local p = gl.wglGetProcAddress(name)
      if p == nil then error(name .. " not exposed by this GL context", 0) end
      return ffi.cast(typ, p)
    end
    ext.glBindFramebuffer = proc("glBindFramebuffer", "pfn_glBindFramebuffer")
    ext.glGenFramebuffers = proc("glGenFramebuffers", "pfn_glGenFramebuffers")
    ext.glDeleteFramebuffers =
      proc("glDeleteFramebuffers", "pfn_glDeleteFramebuffers")
    ext.glFramebufferTexture2D =
      proc("glFramebufferTexture2D", "pfn_glFramebufferTexture2D")
    ext.glBlitFramebuffer = proc("glBlitFramebuffer", "pfn_glBlitFramebuffer")
  end)
  if not ok then
    reason = "GL interop unavailable: " .. tostring(err)
    return false, reason
  end
  ready = true
  return true
end

-- The window's device and GL contexts, which the OpenXR session binds to.
function VRGL.contexts()
  if not VRGL.load() then return nil, nil end
  return gl.wglGetCurrentDC(), gl.wglGetCurrentContext()
end

-- The GL framebuffer behind a LOVE canvas. Bound through LOVE (so LOVE's
-- own cache stays truthful), read from the driver, then released.
function VRGL.canvasFBO(canvas)
  if not VRGL.load() then return nil end
  local id = nil
  local ok = pcall(function()
    love.graphics.setCanvas(canvas)
    local out = ffi.new("int[1]")
    gl.glGetIntegerv(GL.DRAW_FRAMEBUFFER_BINDING, out)
    id = out[0]
    love.graphics.setCanvas()
  end)
  pcall(love.graphics.setCanvas)
  return ok and id or nil
end

-- Blit a LOVE canvas's pixels into a GL texture (an XR swapchain image),
-- flipped vertically on the way: LOVE renders its canvases y-down, GL
-- textures composite y-up, and the blit is the one place the two meet.
--
-- `srcFBO` comes from canvasFBO (cache it -- it is stable for the
-- canvas's lifetime). Ends with framebuffer 0 bound, which is the binding
-- LOVE believes in between its passes.
function VRGL.blitToTexture(srcFBO, sw, sh, tex, tw, th)
  if not ready then return false end
  local ok = pcall(function()
    if not fbo then
      local out = ffi.new("unsigned int[1]")
      ext.glGenFramebuffers(1, out)
      fbo = out[0]
    end
    ext.glBindFramebuffer(GL.DRAW_FRAMEBUFFER, fbo)
    ext.glFramebufferTexture2D(GL.DRAW_FRAMEBUFFER, GL.COLOR_ATTACHMENT0,
                               GL.TEXTURE_2D, tex, 0)
    ext.glBindFramebuffer(GL.READ_FRAMEBUFFER, srcFBO)
    ext.glBlitFramebuffer(0, sh, sw, 0, 0, 0, tw, th,
                          GL.COLOR_BUFFER_BIT, GL.LINEAR)
    ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
  end)
  if not ok then pcall(function() ext.glBindFramebuffer(GL.FRAMEBUFFER, 0) end) end
  return ok
end

-- Copy the WINDOW's currently displayed image (the front buffer -- the
-- back buffer's contents are undefined after a swap) into a GL texture:
-- the UI quad the headset floats in front of the world. Restores the read
-- buffer to BACK, the default LOVE never changes.
function VRGL.copyFrontBuffer(tex, w, h)
  if not ready then return false end
  local ok = pcall(function()
    ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
    gl.glReadBuffer(GL.FRONT)
    gl.glBindTexture(GL.TEXTURE_2D, tex)
    gl.glCopyTexSubImage2D(GL.TEXTURE_2D, 0, 0, 0, 0, 0, w, h)
    gl.glBindTexture(GL.TEXTURE_2D, 0)
    gl.glReadBuffer(GL.BACK)
  end)
  if not ok then pcall(function() gl.glReadBuffer(GL.BACK) end) end
  return ok
end

-- Blit a REGION of the window's front buffer into a GL texture (an XR
-- swapchain image), SCALED to (dw, dh) at the texture's origin. This is
-- the panel's route: the whole-window copy above is pixel-for-pixel, so
-- a window larger than the swapchain image simply ran off its edges --
-- fullscreen cut the GB frame's own menu off the panel. A scaled blit
-- has no such cliff: the letterbox region lands whole at the texture's
-- own resolution whatever size the window is. Source coordinates are GL
-- window space, origin bottom-left; LINEAR, because the region rarely
-- matches the target size exactly and dropped rows read worse than a
-- soft one. Restores the read buffer and framebuffer LOVE believes in.
function VRGL.copyFrontRegionToTexture(tex, sx, sy, sw, sh, dw, dh)
  if not ready then return false end
  local ok = pcall(function()
    if not fbo then
      local out = ffi.new("unsigned int[1]")
      ext.glGenFramebuffers(1, out)
      fbo = out[0]
    end
    ext.glBindFramebuffer(GL.READ_FRAMEBUFFER, 0)
    gl.glReadBuffer(GL.FRONT)
    ext.glBindFramebuffer(GL.DRAW_FRAMEBUFFER, fbo)
    ext.glFramebufferTexture2D(GL.DRAW_FRAMEBUFFER, GL.COLOR_ATTACHMENT0,
                               GL.TEXTURE_2D, tex, 0)
    ext.glBlitFramebuffer(sx, sy, sx + sw, sy + sh, 0, 0, dw, dh,
                          GL.COLOR_BUFFER_BIT, GL.LINEAR)
    ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
    gl.glReadBuffer(GL.BACK)
  end)
  if not ok then
    pcall(function()
      ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
      gl.glReadBuffer(GL.BACK)
    end)
  end
  return ok
end

-- Copy the window's front buffer into a LOVE CANVAS (by its FBO id, from
-- canvasFBO), flipped so the canvas reads top-down exactly like the
-- window: what LOVE then draws from that canvas at (0,0) is the screen,
-- row for row. The battle's VR quad is the caller: it needs the screen as
-- something LOVE can CUT UP (scissored cutouts of the UI), not just as a
-- finished texture -- copyFrontBuffer above is for the finished case.
function VRGL.copyFrontToCanvas(dstFBO, w, h)
  if not ready then return false end
  local ok = pcall(function()
    ext.glBindFramebuffer(GL.READ_FRAMEBUFFER, 0)
    gl.glReadBuffer(GL.FRONT)
    ext.glBindFramebuffer(GL.DRAW_FRAMEBUFFER, dstFBO)
    ext.glBlitFramebuffer(0, 0, w, h, 0, h, w, 0,
                          GL.COLOR_BUFFER_BIT, GL.NEAREST)
    ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
    gl.glReadBuffer(GL.BACK)
  end)
  if not ok then
    pcall(function()
      ext.glBindFramebuffer(GL.FRAMEBUFFER, 0)
      gl.glReadBuffer(GL.BACK)
    end)
  end
  return ok
end

function VRGL.status()
  if ready then return "ok" end
  return reason or "not loaded"
end

return VRGL
