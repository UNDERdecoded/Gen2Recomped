-- Optional desktop acquisition. Only an explicitly opened browser starts a worker.
local Json = require("src.link.Json")
local Browser = {}
Browser.__index = Browser
local serial = 0
local jobs = setmetatable({}, { __mode = "k" })
function Browser.shutdown()
  for job in pairs(jobs) do
    job:cancel()
  end
end
local function clean(s)
  return tostring(s or "Shader import failed"):gsub("[^ -~]", " "):sub(1, 240)
end
function Browser.validate(directory)
  serial = serial + 1
  local result, why
  local mount = "shader-validation-" .. serial
  local mounted = require("src.import.CacheFs").withMounted(directory, mount, function()
    local function path(p)
      local name = assert(p:match("^shader%-presets/([%w_-]+%.[%w]+)$"), "invalid staged resource")
      return mount .. "/" .. name
    end
    local fs = {
      getDirectoryItems = function()
        return { "prepared.json" }
      end,
      getInfo = function(p)
        return love.filesystem.getInfo(path(p))
      end,
      read = function(p, n)
        return love.filesystem.read(path(p), n)
      end,
    }
    local candidate = require("src.render.ShaderPresets").new({ fs = fs })
    local ok, value, err = pcall(candidate.activate, candidate, "local:prepared")
    candidate:off()
    if ok then
      result, why = value, err
    else
      result, why = nil, clean(value)
    end
    return true
  end)
  if not mounted then
    return nil, "Cannot open prepared shader files"
  end
  return result, why
end
function Browser.new(opts)
  opts = opts or {}
  return setmetatable({ options = opts, installed = {} }, Browser)
end
function Browser:available()
  local opts = self.options
  if opts.available then
    return opts.available()
  end
  if not (love and love.thread and love.thread.newThread and love.system) then
    return nil, "Shader importer unavailable in this build"
  end
  local os = love.system.getOS()
  if os ~= "OS X" and os ~= "Windows" and os ~= "Linux" then
    return nil, "Import shaders on a desktop build first"
  end
  self.helper = opts.helper
    or (
      love.filesystem.getSourceBaseDirectory()
      .. "/shader-tools/gen2-slang-import"
      .. (os == "Windows" and ".exe" or "")
    )
  local f = io.open(self.helper, "rb")
  if not f then
    return nil, "Shader importer missing from this build"
  end
  f:close()
  return true
end
function Browser:start(op, path)
  if self.busy then
    return nil, "Shader browser is busy"
  end
  local available, why = self:available()
  if not available then
    self.error = why
    return nil, why
  end
  local opts = self.options
  local fs = opts.fs or require("src.import.CacheFs").dataFs()
  local root = opts.root or require("src.import.CacheFs").root()
  if not root then
    return nil, "Shader data folder unavailable"
  end
  serial = serial + 1
  local clock = love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
  local id = ("job-%.0f-%d"):format(clock * 1000000, serial)
  local rel = ".shader-jobs/" .. id
  if fs.getInfo(rel) then
    return nil, "Shader job folder already exists"
  end
  local ok, err = fs.createDirectory(rel)
  if not ok then
    return nil, clean(err)
  end
  local request = { op = op, path = path, destination = root .. "/shader-presets" }
  ok, err = fs.write(rel .. "/request.json", Json.encode(request))
  if not ok then
    return nil, clean(err)
  end
  local channel, thread
  local success, startError = pcall(function()
    if opts.start then
      channel, thread = opts.start({ helper = self.helper, relative = rel, root = root, request = request })
    else
      local key = "shader.browser." .. id
      channel = love.thread.getChannel(key)
      channel:clear()
      thread = love.thread.newThread("src/render/shader_browser_worker.lua")
      thread:start(Json.encode({ helper = self.helper, relative = rel, root = root, channel = key }))
    end
  end)
  if not success or not channel then
    fs.remove(rel .. "/request.json")
    fs.remove(rel)
    return nil, clean(startError)
  end
  self.fs, self.relative, self.directory = fs, rel, root .. "/" .. rel
  self.channel, self.thread, self.busy, self.path = channel, thread, true, path
  jobs[self] = true
  self.cancelled = nil
  self.error, self.result, self.message = nil, nil, "Loading shader catalog"
  return true
end
function Browser:cancel()
  jobs[self] = nil
  if self.busy then
    self.fs.write(self.relative .. "/cancel", "cancel")
    self.busy = false
    self.cancelled = true
    self.message = "Cancelled"
  end
end
function Browser:poll()
  if not self.busy then
    return
  end
  for _ = 1, 32 do
    local encoded = self.channel:pop()
    if not encoded then
      break
    end
    local event = type(encoded) == "string" and #encoded <= 262144 and Json.decode(encoded)
    if type(event) ~= "table" then
      self.error = "Invalid shader worker response"
      self:cancel()
      return
    end
    if event.kind == "status" then
      self.message = clean(event.message)
    elseif event.kind == "catalog" then
      local records = {}
      if type(event.entries) ~= "table" or #event.entries > 512 then
        self.error = "Invalid shader catalog"
        self:cancel()
        return
      end
      for _, e in ipairs(event.entries) do
        if
          type(e) ~= "table"
          or type(e.path) ~= "string"
          or #e.path > 240
          or not e.path:match("^handheld/[%w_./ +()%[%]-]+%.slangp$")
          or e.path:find("..", 1, true)
          or type(e.name) ~= "string"
          or #e.name > 80
          or e.name:find("[^ -~]")
        then
          self.error = "Invalid shader catalog entry"
          self:cancel()
          return
        end
        records[#records + 1] = { path = e.path, name = e.name }
      end
      self.entries, self.result, self.busy = records, "catalog", false
    elseif event.kind == "ready" then
      self.message = "Checking shader"
      local ok, result, why = pcall(self.options.validate or Browser.validate, self.directory .. "/prepared")
      if ok and result then
        local written, err = self.fs.write(self.relative .. "/approve", "validated on current GPU")
        if not written then
          self.error = clean(err)
          self:cancel()
          return
        end
        self.message = "Installing shader"
      else
        self.error = clean(ok and why or result)
        self:cancel()
        return
      end
    elseif event.kind == "installed" then
      if
        type(event.id) ~= "string"
        or not event.id:match(
          "^local:slang%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
        )
      then
        self.error = "Invalid installed preset"
        self:cancel()
        return
      end
      self.installed[self.path], self.result, self.busy = event.id, "installed", false
      self.message = "Installed - select to activate"
    elseif event.kind == "error" then
      self.error = clean(event.message)
      self.busy = false
      self.result = "error"
    end
  end
  if not self.busy then
    jobs[self] = nil
  end
  if self.busy and self.thread and self.thread.getError then
    local error = self.thread:getError()
    if error then
      self.error = clean(error)
      self:cancel()
    end
  end
end
return Browser
