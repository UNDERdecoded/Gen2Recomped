-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ONE HTTP REQUEST, ANY METHOD, for the cloud services (Google Drive,
-- OneDrive): request(method, url, { headers = {...}, body = "..." }) returns
-- status, body (or nil, why).
--
--   desktop  curl (HostShell's transport): the body goes through a temp file
--            (--data-binary @file), the response into another, the status
--            from -w -- so nothing is ever put on a command line but names.
--   Android  love.system.httpRequest(json) -> GameActivity.httpRequest, which
--            answers {"status": n, "body": "..."} (HttpURLConnection).
--   iOS      LOVE 12's built-in lua-https (require "https"), also the
--            fallback wherever curl cannot be run.
--   Xbox     (UWP) the package's native Windows.Web.Http bridge, through
--            files in LocalState (src/cloud/XboxHttp.lua, ports/uwp/app/main.cpp).
--
-- Bodies here are text (JSON, form data, Lua save files); nothing binary.

local H = {}
H.async=setmetatable({},{__mode='k'})

local function tmpPath(tag)
  local dir = love.filesystem.getSaveDirectory()
  local name = ("http_%s_%d_%d.tmp"):format(tag, os.time(), math.random(1, 1e6))
  return dir .. "/" .. name, name
end

local function viaCurl(method, url, opts)
  local HostShell = require("src.core.HostShell")
  local q = HostShell.quote
  local args = { "curl -sS -L --connect-timeout 15 --max-time 120", "-X " .. method }
  for k, v in pairs(opts.headers or {}) do
    args[#args + 1] = "-H " .. q(k .. ": " .. v)
  end
  local bodyAbs, bodyRel
  if opts.body then
    bodyAbs, bodyRel = tmpPath("req")
    love.filesystem.write(bodyRel, opts.body)
    args[#args + 1] = "--data-binary " .. q("@" .. bodyAbs)
  end
  local outAbs, outRel = tmpPath("res")
  args[#args + 1] = "-o " .. q(outAbs)
  args[#args + 1] = "-w " .. q("%{http_code}")
  args[#args + 1] = q(url)
  local pipe = HostShell.popen(table.concat(args, " ") .. " 2>&1")
  if not pipe then
    if bodyRel then love.filesystem.remove(bodyRel) end
    return nil, "could not run curl"
  end
  local out = pipe:read("*a") or ""
  pipe:close()
  local body = love.filesystem.read(outRel) or ""
  love.filesystem.remove(outRel)
  if bodyRel then love.filesystem.remove(bodyRel) end
  local status = tonumber(out:match("(%d%d%d)%s*$"))
  if not status or status == 0 then return nil, "network error: " .. out:gsub("%s+$", "") end
  return status, body
end

local function viaBridge(method, url, opts)
  local Json = require("src.link.Json")
  local ok, res = pcall(love.system.httpRequest, Json.encode({
    method = method, url = url, headers = opts.headers or {}, body = opts.body,
  }))
  if not ok or type(res) ~= "string" or res == "" then return nil, "the Android network bridge failed" end
  local okD, doc = pcall(Json.decode, res)
  if not (okD and type(doc) == "table") then return nil, "bad bridge reply" end
  if doc.error then return nil, tostring(doc.error) end
  return tonumber(doc.status), doc.body or ""
end

-- iOS (and any LOVE 12 build): the engine's own lua-https module. iOS has no
-- curl to spawn and no httpRequest bridge, so without this every Google
-- Drive / OneDrive request there failed before the code popup could open.
local httpsMod
local function luaHttps()
  if httpsMod == nil then
    local ok, m = pcall(require, "https")
    httpsMod = (ok and type(m) == "table" and type(m.request) == "function") and m or false
  end
  return httpsMod or nil
end

local function viaLuaHttps(method, url, opts)
  local https = luaHttps()
  local ok, code, body = pcall(https.request, url, {
    method = method, headers = opts.headers or {}, data = opts.body,
  })
  if not ok then return nil, "network error: " .. tostring(code) end
  code = tonumber(code)
  if not code or code == 0 then return nil, "network error: no response" end
  return code, body or ""
end

local function isIOS() return love and love.system and love.system.getOS and love.system.getOS() == "iOS" end

-- Xbox (UWP): no curl, no lua-https; the package's native bridge does it
local XboxHttp = require("src.cloud.XboxHttp")

function H.available()
  if love and love.system and type(love.system.httpRequest) == "function" then return true end
  if XboxHttp.isUWP() then return XboxHttp.available() end
  if isIOS() and luaHttps() then return true end
  local ok, HostShell = pcall(require, "src.core.HostShell")
  return ok and HostShell.haveCurl and HostShell.haveCurl() or false
end

function H.request(method, url, opts)
  opts = opts or {}
  local co=coroutine.running()
  if co and H.async[co] then
    return coroutine.yield({kind='http',method=method,url=url,opts=opts})
  end
  if love and love.system and type(love.system.httpRequest) == "function" then
    return viaBridge(method, url, opts)
  end
  if isIOS() and luaHttps() then return viaLuaHttps(method, url, opts) end
  if XboxHttp.isUWP() then
    if XboxHttp.available() then return XboxHttp.request(method, url, opts) end
    if luaHttps() then return viaLuaHttps(method, url, opts) end
    return nil, "cloud saves need a newer Xbox package (no network bridge in this one)"
  end
  local status, body = viaCurl(method, url, opts)
  if not status and luaHttps() then return viaLuaHttps(method, url, opts) end
  return status, body
end

-- application/x-www-form-urlencoded
function H.form(t)
  local parts = {}
  for k, v in pairs(t) do
    parts[#parts + 1] = H.escape(k) .. "=" .. H.escape(v)
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

function H.escape(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function H.json(status, body)
  if not status then return nil, body end
  local ok, doc = pcall(require("src.link.Json").decode, body or "")
  if not ok then doc = nil end
  return status, doc, body
end

return H
