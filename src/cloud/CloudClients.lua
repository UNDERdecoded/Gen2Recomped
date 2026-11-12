-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- The cloud services' app credentials: cloud_clients.lua at the game's root
-- (git-ignored; cloud_clients.example.lua shows the shape; release builds
-- write it from repository secrets). Missing or empty means "not set up" and
-- the launcher says so rather than offering a sign-in that cannot work.

local C = {}
local cached
local why -- the last reason the file could not be read, for the error text

local FILE = "cloud_clients.lua"

-- Three ways in, because a phone reported "not set up" from a build that
-- carries the file: love.filesystem.load, then read + load(string), then
-- require.  Only a success is cached; a failure is retried next time.
local function readTable()
  local fs = love and love.filesystem
  if not fs then return nil, "no love.filesystem" end
  local errs = {}
  local ok, chunk, err = pcall(fs.load, FILE)
  if ok and chunk then
    local okR, t = pcall(chunk)
    if okR and type(t) == "table" then return t end
    errs[#errs + 1] = "load ran: " .. tostring(t)
  else
    errs[#errs + 1] = "load: " .. tostring(ok and err or chunk)
  end
  local okRead, text = pcall(fs.read, FILE)
  if okRead and type(text) == "string" and text ~= "" then
    local f, e = (loadstring or load)(text, "=" .. FILE)
    if f then
      local okR, t = pcall(f)
      if okR and type(t) == "table" then return t end
      errs[#errs + 1] = "read ran: " .. tostring(t)
    else
      errs[#errs + 1] = "read parse: " .. tostring(e)
    end
  else
    errs[#errs + 1] = "read: " .. (okRead and "empty or missing" or tostring(text))
  end
  local okReq, t = pcall(require, "cloud_clients")
  if okReq and type(t) == "table" then return t end
  errs[#errs + 1] = "require: " .. tostring(t):sub(1, 80)
  return nil, table.concat(errs, "; ")
end

function C.get()
  if cached then return cached end
  local t, e = readTable()
  if t then cached, why = t, nil else why = e end
  return cached
end

-- why the credentials could not be read (nil when they were)
function C.why() return why end

local function filled(c) return type(c) == "table" and type(c.id) == "string" and c.id ~= "" end

function C.googleDesktop() local t = C.get(); local g = t and t.google; return g and filled(g.desktop) and g.desktop or nil end
function C.googleDevice() local t = C.get(); local g = t and t.google; return g and filled(g.device) and g.device or nil end
function C.microsoft() local t = C.get(); return t and filled(t.microsoft) and t.microsoft or nil end

return C
