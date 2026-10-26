-- Recovery for macOS OpenGL contexts whose system framebuffer is undefined.
-- The game still renders with OpenGL; only the finished RGBA image is handed
-- to Core Animation. Never selects another application's window or context.
local M = {}
local native
local function api()
  if native then return native end
  local ffi = require("ffi")
  ffi.cdef[[
    typedef struct { double x,y; } G2SurfacePoint;
    typedef struct { double width,height; } G2SurfaceSize;
    typedef struct { G2SurfacePoint origin; G2SurfaceSize size; } G2SurfaceRect;
    void *objc_getClass(const char*); void *sel_registerName(const char*);
    void objc_msgSend(void);
    void glGetIntegerv(unsigned int,int*);
    unsigned int glCheckFramebufferStatus(unsigned int);
    const void *CFDataCreate(const void*,const unsigned char*,long);
    void CFRelease(const void*);
    const unsigned char *CFDataGetBytePtr(const void*);
    int memcmp(const void*,const void*,unsigned long);
    void *CGColorSpaceCreateDeviceRGB(void); void CGColorSpaceRelease(void*);
    void *CGDataProviderCreateWithCFData(const void*); void CGDataProviderRelease(void*);
    void *CGImageCreate(unsigned long,unsigned long,unsigned long,unsigned long,
      unsigned long,void*,unsigned int,void*,const double*,bool,int);
    void CGImageRelease(void*);
    typedef struct { void* data; unsigned long height,width,rowBytes; } G2SurfaceImageBuffer;
    long vImagePermuteChannels_ARGB8888(const G2SurfaceImageBuffer*,const G2SurfaceImageBuffer*,const unsigned char*,unsigned int);

  ]]
  local objc=ffi.load("/usr/lib/libobjc.A.dylib")
  -- Anonymous function-pointer declarations create fresh LuaJIT CTypes on
  -- every cast. These types are never collected: casting in present() would
  -- exhaust the type table during a long OpenGL session. Bind each ABI once.
  local send=ffi.cast("void*(*)(void*,void*)",objc.objc_msgSend)
  local sendArg=ffi.cast("void(*)(void*,void*,void*)",objc.objc_msgSend)
  local sendRect=ffi.cast("void(*)(void*,void*,G2SurfaceRect)",objc.objc_msgSend)
  local sendBool=ffi.cast("void(*)(void*,void*,bool)",objc.objc_msgSend)
  local number=ffi.cast("long(*)(void*,void*)",objc.objc_msgSend)
  local at=ffi.cast("void*(*)(void*,void*,unsigned long)",objc.objc_msgSend)
  local string=ffi.cast("void*(*)(void*,void*,const char*)",objc.objc_msgSend)
  local function msg(object,selector) return send(object,objc.sel_registerName(selector)) end
  local function arg(object,selector,value)
    sendArg(object,objc.sel_registerName(selector),value)
  end
  local function rect(object,w,h)
    sendRect(object,
      objc.sel_registerName("setFrame:"),ffi.new("G2SurfaceRect",{{0,0},{w,h}}))
  end
  native={accelerate=ffi.load("/System/Library/Frameworks/Accelerate.framework/Accelerate"),
    memcmp=ffi.C.memcmp,permutation=ffi.new("unsigned char[4]",{2,1,0,3}),ffi=ffi,objc=objc,msg=msg,arg=arg,rect=rect,sendBool=sendBool,
    number=number,at=at,string=string,
    cg=ffi.load("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"),
    cf=ffi.load("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"),
    quartz=ffi.load("/System/Library/Frameworks/QuartzCore.framework/QuartzCore"),
    gl=ffi.load("/System/Library/Frameworks/OpenGL.framework/OpenGL")}
  return native
end

function M.windowNumber()
  local a=api()
  local context=a.msg(a.objc.objc_getClass("NSOpenGLContext"),"currentContext")
  local window=a.msg(a.msg(context,"view"),"window")
  local app=a.msg(a.objc.objc_getClass("NSApplication"),"sharedApplication")
  if window==nil then window=a.msg(app,"keyWindow") end
  if window==nil then window=a.msg(app,"mainWindow") end
  if window==nil then
    -- NSApplication.windows contains this process's windows only. SDL need
    -- not designate a main/key window when the test runs in the background.
    local windows=a.msg(app,"windows")
    local number=a.number
    local count=tonumber(number(windows,a.objc.sel_registerName("count")))
    local at=a.at
    for i=0,count-1 do
      local candidate=at(windows,a.objc.sel_registerName("objectAtIndex:"),i)
      if number(candidate,a.objc.sel_registerName("isVisible"))~=0 then window=candidate;break end
    end
  end
  if window==nil then return nil end
  return tonumber(a.number(window,
    a.objc.sel_registerName("windowNumber")))
end

function M.createIfUndefined()
  local a=api()
  local binding=a.ffi.new("int[1]")
  a.gl.glGetIntegerv(0x8CA6,binding) -- GL_DRAW_FRAMEBUFFER_BINDING
  if binding[0]~=0 or a.gl.glCheckFramebufferStatus(0x8D40)~=0x8219 then return nil end
  local self={reason="GL_FRAMEBUFFER_UNDEFINED",layer=nil,view=nil}
  function self:close()
    if self.lastData then a.cf.CFRelease(self.lastData);self.lastData=nil end
    self.frameWidth,self.frameHeight,self.windowWidth,self.windowHeight=nil,nil,nil,nil
    if self.pixels then self.pixels:release();self.pixels=nil end
    if self.layer~=nil then
      a.msg(self.layer,"removeFromSuperlayer");a.msg(self.layer,"release")
      self.layer,self.view=nil,nil
    end
  end
  function self:present(data,ww,wh)
    local context=a.msg(a.objc.objc_getClass("NSOpenGLContext"),"currentContext")
    local view=a.msg(context,"view")
    assert(view~=nil,"OpenGL recovery has no owning view")
    if self.view~=view then
      self:close()
      self.view=view
      self.layer=a.msg(a.msg(a.objc.objc_getClass("CALayer"),"layer"),"retain")
      local string=a.string
      local nearest=string(a.objc.objc_getClass("NSString"),
        a.objc.sel_registerName("stringWithUTF8String:"),"nearest")
      a.arg(self.layer,"setMagnificationFilter:",nearest)
      a.arg(self.layer,"setMinificationFilter:",nearest)
      a.arg(a.msg(view,"layer"),"addSublayer:",self.layer)
    end
    local width,height=data:getDimensions()
    local size=data:getSize()
    assert(data:getFormat()=="rgba8" and size==width*height*4,"OpenGL recovery requires RGBA8")
    -- Core Animation's RGBA CGImage commit performs expensive conversion.
    -- Permute exact bytes into native premultiplied BGRA (32-bit little-endian)
    -- with vImage, leaving the RGBA readback/capture untouched. One scratch
    -- buffer is reused; CFData still owns an immutable copy for async display.
    local pointer=data:getFFIPointer()
    if not self.pixels or self.pixels:getSize()~=size then
      local pixels=love.data.newByteData(size)
      if self.pixels then self.pixels:release() end
      self.pixels=pixels
    end
    local input=a.ffi.new("G2SurfaceImageBuffer",{pointer,height,width,width*4})
    local output=a.ffi.new("G2SurfaceImageBuffer",{self.pixels:getFFIPointer(),height,width,width*4})
    -- kvImageDoNotTile: avoid worker scheduling for this memory-only shuffle.
    assert(a.accelerate.vImagePermuteChannels_ARGB8888(input,output,a.permutation,16)==0,
      "OpenGL recovery could not convert frame to BGRA")
    -- The complete readback and conversion still run. Only byte-identical
    -- images with unchanged geometry may reuse the already displayed image.
    if self.lastData and self.frameWidth==width and self.frameHeight==height
      and self.windowWidth==ww and self.windowHeight==wh
      and a.memcmp(output.data,a.cf.CFDataGetBytePtr(self.lastData),size)==0 then return end
    local cfdata=a.cf.CFDataCreate(nil,output.data,size)
    assert(cfdata~=nil,"OpenGL recovery could not allocate frame data")
    local provider=a.cg.CGDataProviderCreateWithCFData(cfdata)
    local space=a.cg.CGColorSpaceCreateDeviceRGB()
    local image=provider~=nil and space~=nil
      and a.cg.CGImageCreate(width,height,8,32,width*4,space,0x2002,provider,nil,false,0) or nil
    if image~=nil then
      local transaction=a.objc.objc_getClass("CATransaction")
      a.msg(transaction,"begin")
      a.sendBool(transaction,
        a.objc.sel_registerName("setDisableActions:"),true)
      a.rect(self.layer,ww,wh)
      a.arg(self.layer,"setContents:",image)
      a.msg(transaction,"commit");a.msg(transaction,"flush")
      a.cg.CGImageRelease(image)
      if self.lastData then a.cf.CFRelease(self.lastData) end
      self.lastData=cfdata
      self.frameWidth,self.frameHeight,self.windowWidth,self.windowHeight=width,height,ww,wh
    end
    if space~=nil then a.cg.CGColorSpaceRelease(space) end
    if provider~=nil then a.cg.CGDataProviderRelease(provider) end
    if image==nil then a.cf.CFRelease(cfdata) end
    assert(image~=nil,"OpenGL recovery could not create the window image")
  end
  return self
end
return M
