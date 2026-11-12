-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CLOUD-SAVE HTTP ON XBOX (UWP). A UWP app cannot start curl and the bundled
-- LOVE 11.5 has no lua-https, so ports/uwp/app/main.cpp makes the request
-- with Windows.Web.Http and the two sides talk through files in LocalState
-- (the parent of the save directory), like the Xbox ROM picker:
--
--   gr_http_ready      the package has the bridge
--   gr_http/<id>.req   GRHTTP1\n METHOD\n URL\n <n>\n n x "Name: value\n"
--                      <body bytes>\n <body>      (written as .tmp, renamed)
--   gr_http/<id>.res   <status>\n <body>          (status 0 = error text)
--
-- Plain io/os only, so it works from the cloud worker thread too.

local X = {}

X.TIMEOUT = 120 -- seconds, as curl's --max-time

local function parentOf(path)
  return (tostring(path):match("^(.*)[/\\][^/\\]+[/\\]?$"))
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local rootCache
local function root()
  if rootCache ~= nil then return rootCache or nil end
  rootCache = false
  local fs = love and love.filesystem
  if fs and fs.getSaveDirectory then
    local ok, dir = pcall(fs.getSaveDirectory)
    local r = ok and parentOf(dir)
    if r and exists(r .. "/gr_http_ready") then rootCache = r end
  end
  return rootCache or nil
end

-- for tests: point at a fake LocalState
function X._setRoot(r) rootCache = r or nil end

function X.isUWP()
  local sys = love and love.system
  return sys and sys.getOS and sys.getOS() == "UWP" or false
end

function X.available() return root() ~= nil end

local seq = 0
local function newId()
  seq = seq + 1
  return ("r%d_%d_%d"):format(os.time(), seq, math.random(1, 1e9))
end

local function sleep(s)
  if love and love.timer and love.timer.sleep then love.timer.sleep(s) end
end

local function clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function X.request(method, url, opts)
  opts = opts or {}
  local r = root()
  if not r then return nil, "the Xbox network bridge is not in this package" end
  local dir = r .. "/gr_http"
  local id = newId()
  local names = {}
  for k in pairs(opts.headers or {}) do names[#names + 1] = k end
  table.sort(names)
  local body = opts.body or ""
  local parts = { "GRHTTP1\n", method, "\n", url, "\n", tostring(#names), "\n" }
  for _, k in ipairs(names) do
    local v = tostring(opts.headers[k]):gsub("[\r\n]", " ")
    parts[#parts + 1] = k .. ": " .. v .. "\n"
  end
  parts[#parts + 1] = tostring(#body) .. "\n"
  parts[#parts + 1] = body
  local tmp, req = dir .. "/" .. id .. ".tmp", dir .. "/" .. id .. ".req"
  local f = io.open(tmp, "wb")
  if not f then return nil, "could not write the network request" end
  f:write(table.concat(parts))
  f:close()
  if not os.rename(tmp, req) then
    os.remove(tmp)
    return nil, "could not queue the network request"
  end
  local res = dir .. "/" .. id .. ".res"
  local deadline = clock() + X.TIMEOUT
  while clock() < deadline do
    local rf = io.open(res, "rb")
    if rf then
      local text = rf:read("*a") or ""
      rf:close()
      os.remove(res)
      local status, reply = text:match("^(%d+)\r?\n(.*)$")
      status = tonumber(status)
      if not status then return nil, "bad reply from the Xbox network bridge" end
      if status == 0 then return nil, "network error: " .. reply end
      return status, reply
    end
    sleep(0.02)
  end
  os.remove(req)
  return nil, "the network request timed out"
end

return X
