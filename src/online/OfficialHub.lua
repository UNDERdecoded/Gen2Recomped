-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OFFICIAL LINK HUB: the project's own server (tools/online-hub on a
-- VPS).  Every player uses it without typing anything:
--   * LinkState.settings: the hubAddress when the save has none (HOST gets a
--     hub ticket -> hole punch through the hub; short codes and tournaments
--     relay through it)
--   * Net.DEFAULT_RELAY_ADDRESS: the old relay protocol on the same TCP port
--   * the game's LINK > JOIN list and the launcher's JOIN FRIEND page list
--     it as OFFICIAL SERVER (the hub-door flow: ping, then its world / HOST)
-- A save's own hub, the launcher's running hub or a friend's hub still win.
-- POKEPORT_NO_OFFICIAL_HUB=1 turns it off (tests, private builds).

local O = {}

O.IP = "157.173.197.32"
O.PORT = 7778
O.ADDRESS = O.IP .. ":" .. O.PORT
O.NAME = "OFFICIAL SERVER"

function O.enabled()
  local v = os.getenv("POKEPORT_NO_OFFICIAL_HUB")
  return not (v and v ~= "" and v ~= "0")
end

-- the address to fall back on, or nil when turned off
function O.address()
  if not O.enabled() then return nil end
  return O.ADDRESS
end

-- the hub-door invite LinkState / LauncherHub probe (InviteCode kind "hub",
-- ticket 0: "a hub to visit", not a session)
function O.invite()
  return {
    type = "direct", kind = "hub", ticket = 0, nonce = 0,
    hub = { ip = O.IP, port = O.PORT },
    endpoints = { { ip = O.IP, port = O.PORT, path = "hub" } },
    display = O.NAME, official = true,
  }
end

function O.isOfficial(address)
  return type(address) == "string" and (address == O.ADDRESS or address == O.IP)
end

-- THE SERVER'S ADDRESS IS NEVER SHOWN (the user's decision): any text on
-- its way to the screen has "157.173.197.32[:port]" replaced by the name
local IP_PAT = O.IP:gsub("%.", "%%.") .. "[:%d]*"
function O.mask(text)
  if type(text) ~= "string" then return text end
  return (text:gsub(IP_PAT, O.NAME))
end

return O
