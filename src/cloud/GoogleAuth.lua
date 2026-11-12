-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SIGNING IN TO GOOGLE DRIVE, for cloud saves. One permission:
-- drive.file -- the app sees only the files it made itself.
--
--   desktop  the browser flow for installed apps: PKCE, the browser opens
--            Google's page, Google sends it back to http://127.0.0.1:<port>
--            where a one-shot listener (LOVE's luasocket) takes the code.
--   Android / iOS  the "TVs and Limited Input devices" flow: the launcher shows a
--            short code and google.com/device; the player enters it on any
--            device while the launcher polls. (Android pauses the launcher
--            while the browser is up, so a listener there would miss Google.)
--
-- The tokens live only on this device: cloud_google.lua in the save folder.
-- The access token is refreshed from the refresh token when it runs out.

local Http = require("src.cloud.Http")
local Clients = require("src.cloud.CloudClients")

local G = {}

G.SCOPE = "https://www.googleapis.com/auth/drive.file"
G.AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
G.TOKEN_URL = "https://oauth2.googleapis.com/token"
G.DEVICE_URL = "https://oauth2.googleapis.com/device/code"
G.REVOKE_URL = "https://oauth2.googleapis.com/revoke"
G.FILE = "cloud_google.lua"

local function isAndroid() return love and love.system and love.system.getOS() == "Android" end

-- which flow this device uses, and its client, or nil + why
function G.client()
  -- iOS too: Safari suspends the app, so the loopback listener the desktop
  -- flow waits on never hears Google either; the code popup is the way in
  if isAndroid() or (love and love.system and love.system.getOS() == "iOS") then
    local c = Clients.googleDevice()
    if c then return c, "device" end
    local why = Clients.why and Clients.why()
    return nil, "Google sign-in on phones needs the TV / limited-input client (cloud_clients.lua)"
      .. (why and (" -- " .. why) or "")
  end
  local c = Clients.googleDesktop()
  if c then return c, "browser" end
  c = Clients.googleDevice()
  if c then return c, "device" end
  return nil, "Google sign-in is not set up in this build (cloud_clients.lua)"
end

-- ------------------------------------------------------------- tokens

local function load()
  if love.filesystem.getInfo(G.FILE) then
    local ok, t = pcall(require("src.core.SaveSerializer").decode, love.filesystem.read(G.FILE) or "")
    if ok and type(t) == "table" then return t end
  end
  return nil
end

local function store(t)
  love.filesystem.write(G.FILE, require("src.core.SaveSerializer").encode(t))
end

function G.signedIn() local t = load(); return t ~= nil and t.refresh ~= nil end
function G.account() local t = load(); return t and t.email or nil end

local function took(tokens, doc, client)
  tokens = tokens or {}
  tokens.access = doc.access_token
  tokens.expires = os.time() + (tonumber(doc.expires_in) or 3600) - 60
  if doc.refresh_token then tokens.refresh = doc.refresh_token end
  tokens.client = client.id
  store(tokens)
  return tokens
end

-- a usable access token (refreshing it when needed), or nil + why
function G.accessToken()
  local t = load()
  if not (t and t.refresh) then return nil, "not signed in to Google" end
  if t.access and (t.expires or 0) > os.time() then return t.access end
  local client = G.client()
  if not client then return nil, "Google sign-in is not set up" end
  local status, doc = Http.json(Http.request("POST", G.TOKEN_URL, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = Http.form({ client_id = client.id, client_secret = client.secret or "",
                       refresh_token = t.refresh, grant_type = "refresh_token" }),
  }))
  if status == 200 and doc and doc.access_token then return took(t, doc, client).access end
  if doc and doc.error == "invalid_grant" then
    love.filesystem.remove(G.FILE)
    return nil, "Google sign-in expired -- sign in again"
  end
  return nil, ("could not refresh the Google sign-in (%s)"):format(tostring(doc and doc.error or status))
end

function G.signOut()
  local t = load()
  if t and t.refresh then
    pcall(Http.request, "POST", G.REVOKE_URL, {
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = Http.form({ token = t.refresh }),
    })
  end
  love.filesystem.remove(G.FILE)
end

-- the signed-in account's address (Drive's about.get), remembered for display
function G.fetchAccount()
  local token = G.accessToken()
  if not token then return nil end
  local status, doc = Http.json(Http.request("GET", "https://www.googleapis.com/drive/v3/about?fields=user",
    { headers = { Authorization = "Bearer " .. token } }))
  local email = status == 200 and doc and doc.user and (doc.user.emailAddress or doc.user.displayName)
  if email then
    local t = load()
    if t then t.email = email; store(t) end
  end
  return email
end

-- ------------------------------------------------------- the sign-in

local function randomString(n)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  local out = {}
  for i = 1, n do
    local k = love.math.random(1, #chars)
    out[i] = chars:sub(k, k)
  end
  return table.concat(out)
end

local function challenge(verifier)
  local raw = love.data.hash("sha256", verifier)
  local b64 = love.data.encode("string", "base64", raw)
  return (b64:gsub("%+", "-"):gsub("/", "_"):gsub("=", ""))
end

-- start signing in; returns a flow object to tick with G.poll, or nil + why.
-- flow.kind = "browser" (the page is open) or "device" (show flow.code and
-- flow.url to the player)
function G.begin()
  local client, kind = G.client()
  if not client then return nil, kind end
  if kind == "device" then
    local status, doc = Http.json(Http.request("POST", G.DEVICE_URL, {
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = Http.form({ client_id = client.id, scope = G.SCOPE }),
    }))
    if not status then return nil, "could not reach Google: " .. tostring(doc) end
    if status ~= 200 or not (type(doc) == "table" and type(doc.device_code) == "string" and doc.device_code ~= ""
      and type(doc.user_code) == "string" and doc.user_code ~= "") then
      return nil, ("Google refused the sign-in request (%s)"):format(tostring(doc and doc.error or status))
    end
    return {
      kind = "device", client = client, deviceCode = doc.device_code, code = doc.user_code,
      url = doc.verification_url or doc.verification_uri or "https://www.google.com/device",
      interval = tonumber(doc.interval) or 5, expires = os.time() + (tonumber(doc.expires_in) or 1800),
      nextPoll = os.time() + (tonumber(doc.interval) or 5),
    }
  end
  local ok, socket = pcall(require, "socket")
  if not ok then return nil, "no network sockets on this build" end
  local server = socket.bind("127.0.0.1", 0)
  if not server then return nil, "could not open a local port for the sign-in" end
  server:settimeout(0)
  local _, port = server:getsockname()
  local verifier, state = randomString(64), randomString(24)
  local redirect = ("http://127.0.0.1:%d"):format(port)
  local url = G.AUTH_URL .. "?" .. Http.form({
    client_id = client.id, redirect_uri = redirect, response_type = "code", scope = G.SCOPE,
    code_challenge = challenge(verifier), code_challenge_method = "S256", state = state,
    access_type = "offline", prompt = "consent",
  })
  love.system.openURL(url)
  return { kind = "browser", client = client, server = server, verifier = verifier, state = state,
           redirect = redirect, url = url, expires = os.time() + 180 }
end

local PAGE = [[HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Connection: close

<!doctype html><html><head><meta charset="utf-8"><title>RetroRecomped</title>
<style>body{font-family:system-ui,sans-serif;background:#0d0a1f;color:#f1eefc;display:grid;place-items:center;height:100vh;margin:0}
div{text-align:center}h1{color:#38e1ff}</style></head><body><div><h1>%s</h1><p>%s</p></div></body></html>]]

local function finishBrowser(flow, code)
  local client = flow.client
  local status, doc = Http.json(Http.request("POST", G.TOKEN_URL, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = Http.form({ code = code, client_id = client.id, client_secret = client.secret or "",
                       redirect_uri = flow.redirect, grant_type = "authorization_code",
                       code_verifier = flow.verifier }),
  }))
  if status == 200 and doc and doc.access_token and doc.refresh_token then
    took({}, doc, client)
    pcall(G.fetchAccount)
    return "done"
  end
  return "failed", ("Google did not finish the sign-in (%s)"):format(tostring(doc and (doc.error_description or doc.error) or status))
end

-- tick a sign-in: "waiting", "done", or "failed", why
function G.poll(flow)
  if not flow then return "failed", "no sign-in in progress" end
  if os.time() > flow.expires then G.cancel(flow); return "failed", "the sign-in timed out" end
  if flow.kind == "browser" then
    local client = flow.server:accept()
    if not client then return "waiting" end
    client:settimeout(2)
    local line = client:receive("*l") or ""
    local query = line:match("^GET%s+/%??([^%s]*)") or ""
    local params = {}
    for k, v in query:gmatch("([^&=]+)=([^&]*)") do
      params[k] = (v:gsub("%+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
    end
    if not params.code and not params.error then
      client:send(PAGE:format("RetroRecomped", "Waiting for Google..."))
      client:close()
      return "waiting"
    end
    local result, why
    if params.state ~= flow.state then result, why = "failed", "the sign-in reply did not match"
    elseif params.error then result, why = "failed", "Google sign-in was cancelled (" .. params.error .. ")"
    else result, why = finishBrowser(flow, params.code) end
    client:send(PAGE:format(result == "done" and "Signed in!" or "Sign-in failed",
      result == "done" and "You can close this tab and go back to RetroRecomped." or (why or "")))
    client:close()
    G.cancel(flow)
    return result, why
  end
  -- the device flow
  if os.time() < flow.nextPoll then return "waiting" end
  flow.nextPoll = os.time() + flow.interval
  local client = flow.client
  local status, doc = Http.json(Http.request("POST", G.TOKEN_URL, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = Http.form({ client_id = client.id, client_secret = client.secret or "",
                       device_code = flow.deviceCode,
                       grant_type = "urn:ietf:params:oauth:grant-type:device_code" }),
  }))
  if status == 200 and doc and doc.access_token then
    took({}, doc, client)
    pcall(G.fetchAccount)
    return "done"
  end
  local err = doc and doc.error
  if err == "authorization_pending" then return "waiting" end
  if err == "slow_down" then flow.interval = flow.interval + 5; return "waiting" end
  return "failed", ("Google sign-in failed (%s)"):format(tostring(err or status))
end

function G.cancel(flow)
  if flow and flow.server then pcall(flow.server.close, flow.server); flow.server = nil end
end

return G
