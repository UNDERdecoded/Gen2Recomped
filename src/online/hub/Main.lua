-- Command line for the hub (shared by main.lua under LOVE and run.lua under
-- plain LuaJIT):
--
--   [--config FILE]           default: $POKEPORT_HUB_CONFIG, then
--                             <hub dir>/hub_config.lua, then built-in defaults
--   [--port N] [--data DIR]   override the file
--   --check                   load the config (and game data), print, exit
--   --selftest                run the in-process self test, exit
--   --admin CMD [ARG]         send an admin command to the hub running on
--                             this machine (key: --key, $POKEPORT_HUB_ADMIN_KEY,
--                             or the config file's admin.key)
--   --print-world-code        print the world code of the configured hub

local Main = {}

function Main.parseArgs(args)
  local o = { rest = {} }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--config" or a == "-c" then o.config = args[i + 1]; i = i + 1
    elseif a == "--port" then o.port = tonumber(args[i + 1]); i = i + 1
    elseif a == "--data" then o.dataDir = args[i + 1]; i = i + 1
    elseif a == "--key" then o.key = args[i + 1]; i = i + 1
    elseif a == "--check" then o.check = true
    elseif a == "--selftest" then o.selftest = true
    elseif a == "--print-world-code" then o.printWorldCode = true
    elseif a == "--admin" then
      o.admin = { cmd = args[i + 1], arg = args[i + 2] }
      i = i + 2
    elseif a == "--help" or a == "-h" then o.help = true
    else o.rest[#o.rest + 1] = a end
    i = i + 1
  end
  return o
end

local function exists(p)
  local f = p and io.open(p, "rb")
  if f then f:close() return true end
  return false
end

function Main.configPath(o, hubDir)
  if o.config then return o.config end
  local env = os.getenv("POKEPORT_HUB_CONFIG")
  if env and env ~= "" then return env end
  local here = hubDir and (hubDir .. "/hub_config.lua")
  if exists(here) then return here end
  return nil
end

local USAGE = [[
Link Hub -- a self-hosted rendezvous / relay / GTS / world server.
  love tools/online-hub [--config FILE] [--port N] [--data DIR]
  love tools/online-hub --check | --selftest | --print-world-code
  love tools/online-hub --admin status|rooms|world|kick N|worldban N|ban IP|unban IP|log|stop
(or `luajit tools/online-hub/run.lua ...` where lua-enet and luasocket are installed)
See tools/online-hub/README.md.]]

local function printJson(v)
  local Json = require("src.link.Json")
  local ok, s = pcall(Json.encode, v)
  print(ok and s or tostring(v))
end

-- one admin command against the hub on this machine (TCP, 127.0.0.1)
function Main.adminClient(cfg, cmd, arg, key)
  local socket = require("socket")
  local Json = require("src.link.Json")
  local tcp = (socket.tcp4 or socket.tcp)()
  tcp:settimeout(5)
  local ok, err = tcp:connect("127.0.0.1", cfg.port)
  if not ok then
    print(("can't reach the hub on 127.0.0.1:%d (%s)"):format(cfg.port, tostring(err)))
    return 2
  end
  tcp:send(Json.encode({ type = "hub_admin", key = key, cmd = cmd, arg = arg }) .. "\n")
  local line = tcp:receive("*l")
  tcp:close()
  if not line then print("no answer") return 2 end
  local reply = Json.decode(line)
  if type(reply) ~= "table" then print(line) return 2 end
  if type(reply.result) == "table" then
    if cmd == "log" then
      for _, l in ipairs(reply.result) do print(l) end
    else
      printJson(reply.result)
    end
  else
    print(tostring(reply.result))
  end
  return reply.ok and 0 or 1
end

-- returns an exit code.  platform = { sleep = fn(seconds) }
function Main.main(args, platform, hubDir)
  platform = platform or {}
  local o = Main.parseArgs(args or {})
  if o.help then print(USAGE) return 0 end
  if o.selftest then
    HUB_SELFTEST_AS_MODULE = true
    local test = dofile((hubDir or "tools/online-hub") .. "/selftest.lua")
    return test.run() and 0 or 1
  end
  local Config = require("src.online.hub.Config")
  local path = Main.configPath(o, hubDir)
  local overrides = {}
  if o.port then overrides.port = o.port end
  if o.dataDir then overrides.dataDir = o.dataDir end
  local cfg, problems = Config.load(path, overrides)
  if not cfg then
    print("Link Hub: the configuration has problems:")
    for _, p in ipairs(problems or {}) do print("  - " .. tostring(p)) end
    return 2
  end
  if o.admin then
    local key = o.key or os.getenv("POKEPORT_HUB_ADMIN_KEY") or cfg.admin.key
    return Main.adminClient(cfg, o.admin.cmd or "status", o.admin.arg, key)
  end
  if o.printWorldCode then
    local f = io.open(cfg.dataDir .. "/world_code.txt", "rb")
    if not f then print("(no world code yet: start the hub with world.enabled = true)") return 1 end
    io.write(f:read("*a"))
    f:close()
    return 0
  end
  local Log = require("src.online.hub.Log")
  local log = Log.new({ dir = cfg.dataDir .. "/logs", level = cfg.log.level, file = cfg.log.file,
                        keepDays = cfg.log.keepDays, addresses = cfg.log.addresses })
  log:info("config: %s", path or "(built-in defaults)")
  local Hub = require("src.online.hub.Hub")
  local hub = Hub.new(cfg, { log = log, noListen = o.check })
  if o.check then
    -- load the game data and check the stores without opening any port
    local wantWorld = cfg.world.enabled
    cfg.world.enabled = false
    local ok, err = hub:start()
    if not ok then print("Link Hub: " .. tostring(err)) return 2 end
    printJson(hub:status())
    if wantWorld then print("(the world's data is loaded when the hub runs)") end
    hub:stop("check")
    return 0
  end
  local ok, err = hub:start()
  if not ok then
    log:error("can't start: %s", tostring(err))
    hub:stop("start failed")
    return 2
  end
  log:info("running; services: %s", table.concat(hub:services(), ", "))
  hub:run(platform.sleep)
  return 0
end

return Main
