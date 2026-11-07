# Link Hub

The Link Hub is an optional server that a player or a community can run for
the game's online features. Nothing in the game needs one: direct codes
(LAN, router mapping, forwarded port, hole punch) work without any server.
A hub adds the things a direct code can't do:

| Service | What it does | Port |
|---|---|---|
| Short codes | Six-character room codes (SHORT CODE in the LINK menu). The hub relays the pair's messages, so it works even when both players are behind carrier-grade NAT (mobile data). | TCP `port` |
| Tournaments | The TOURNAMENT screen's brackets and spectating. | TCP `port` |
| 0.7.x clients | Older builds pointed at the hub with `POKEPORT_RELAY_ADDR=host:port` keep working: the TCP port speaks the old relay protocol. | TCP `port` |
| Rendezvous | Hub invite codes: the hub tells two players each other's address and they connect **directly** (the hub carries no game traffic). | UDP `udpPort` |
| GTS (optional) | An always-on GTS for your group, one pool per game family. Every deposit is checked against real game data. | UDP `udpPort` |
| World (optional) | An always-on world players can join any time (WORLDS → JOIN A WORLD). It can offer the hub's GTS inside it. | UDP `world.port` |

Players point their game at a hub in **OPTIONS → ONLINE → LINK HUB**
(`hubAddress`, for example `hub.example.org:7778`). Short codes and hub
codes then use your hub instead of the default relay.

The hub runs the game's own Lua code (its modules live in `src/online/hub/`) (the same GTS, world and validation
modules), so it needs the game's `src/` folder next to it. It does **not**
ship any game data. The GTS and the world load data from imported game
caches that you point them at.

## Running it

### Inside the game's launcher (easiest)

The game ships the hub (`src/online/hub/`). In the launcher, open
**Online Hub** in the sidebar and press **HOST WITH FRIENDS** (or **START
HUB**). The hub runs in a background thread for as long as the app is open,
including while you play a game started from the launcher. Every setting
below has a row under **HUB SETTINGS** there, saved to
`online_hub/config.json` in the game's save folder; the hub's data (GTS,
world, logs) goes to `online_hub/data/`. The launcher's hub listens on port
7780 by default (7777 and 7778 are the games' own ports) and asks the router
to open its ports. Friends paste its one code (or scan its QR) in **JOIN
FRIEND**. See docs/launcher.md, "Online Hub".

The rest of this page is for running the same hub headless on a PC, a
Raspberry Pi or a VPS.

### Windows / macOS / Linux PC with LÖVE

1. Install [LÖVE 11.5](https://love2d.org/).
2. Write a config file (see Configuration below), for example
   `tools/online-hub/hub_config.lua`, which is picked up automatically, or any
   path passed with `--config`. Keep `dataDir` outside the game folder if you
   update the game with git.
3. From the game's folder (the one that contains `src/` and `tools/`):

   ```
   lovec tools/online-hub                    (Windows: console build)
   love tools/online-hub                     (macOS / Linux)
   love tools/online-hub --config my_hub.lua
   ```

The hub has no window. It logs to the console and to `<dataDir>/logs/`.
Stop it with Ctrl+C, or with `--admin stop` (see Admin). The GTS store
is crash-safe, so an abrupt stop loses nothing that was acknowledged.

Other commands:

```
love tools/online-hub --check               load the config and game data, print status, exit
love tools/online-hub --selftest            in-process self test (no network)
love tools/online-hub --print-world-code    the world's invite code
love tools/online-hub --help
```

### Raspberry Pi or VPS (no display)

LÖVE also runs headless on Linux (`sudo apt install love`). It needs no
X server, because the hub turns the window module off. If you would
rather not install LÖVE, plain LuaJIT works too, with two C modules:

```
sudo apt install luajit lua-socket luarocks
sudo luarocks --lua-version=5.1 install enet       # lua-enet (needs libenet-dev)
luajit tools/online-hub/run.lua --config /etc/linkhub/hub_config.lua
```

If `src/` is not two folders above the hub folder, set
`POKEPORT_HUB_ROOT=/path/to/game`.

The hub needs very little CPU. Link traffic is a few KB/s per pair, and
the relay caps each pair at `relay.bytesPerSecond`. Memory is mostly the
game data loaded for the GTS and the world. The world loads its game in
full (maps included), so on a small Pi start with the GTS only. To see
what a config costs, run `--check`.

A systemd unit:

```
[Unit]
Description=Link Hub
After=network-online.target

[Service]
User=linkhub
WorkingDirectory=/opt/gen2recomped
ExecStart=/usr/bin/love tools/online-hub --config /etc/linkhub/hub_config.lua
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Run it as its own unprivileged user, never as root. The default ports are
above 1024, so no privileges are needed.

## Configuration

The config file is Lua table syntax. It is read as **data**: it runs in an
empty environment and can't call functions or touch files. Every key is
optional, and the defaults are shown here.

```lua
-- hub_config.lua
name = "MY LINK HUB"
bind = "*"                 -- "127.0.0.1" = this PC only (testing)
port = 7778                -- TCP: short codes, tournaments, 0.7.x clients
-- udpPort = 7778          -- UDP: rendezvous, GTS (defaults to `port`)
-- publicAddress = "203.0.113.5"   -- printed in the world code (IPv4)
-- lanAddress = "192.168.1.20"     -- also printed (detected if unset)
dataDir = "hub-data"       -- relative to this file; GTS store, world, logs, bans

relay = { enabled = true, bytesPerSecond = 65536, burstBytes = 262144,
          queueBytes = 1048576, roomTtl = 1800, maxRooms = 500 }
rendezvous = { enabled = true, maxTickets = 2000, ticketTtl = 7200,
               ticketsPerIp = 8, introductionsPerTicket = 64 }
tournaments = { enabled = true, max = 32, maxPlayers = 32, resultTimeout = 90,
                lobbyTtl = 3600 }

gts = {
  enabled = false,
  -- one entry per pool, each game -> its imported cache (<install>/data/generated)
  pools = {
    dppt = { platinum  = "/srv/games/platinum/data/generated",
             heartgold = "/srv/games/heartgold/data/generated" },
    bw   = { black     = "/srv/games/black/data/generated" },
    -- port-extension pools: rby, gsc, rse (Ruby/Sapphire/Emerald/FireRed/LeafGreen),
    -- prism, polishedcrystal
  },
  dataMode = "lean",       -- "lean": keep only species/moves/items after loading
  expireDays = 30,         -- unclaimed deposits go back to their owner (0 = never)
  maxDeposits = 500,       -- per pool
}

world = {
  enabled = false,
  port = 7779,             -- its own UDP port
  name = "HUB WORLD",
  game = "platinum",       -- one game per world (maps must match the members')
  data = "/srv/games/platinum/data/generated",
  cap = 16,                -- 2..16
  public = true,           -- unmodded games only, chat filter on
  gts = true,              -- members can open the hub GTS from inside the world
}

caps = { tcpConnections = 512, enetPeers = 256, perIp = 16,
         messagesPerSecond = 30, messageBurst = 120, idleSeconds = 60 }
admin = { key = "", localOnly = true }   -- key: 12+ characters; empty = admin off
log = { level = "info", file = true, keepDays = 14, addresses = false }
statusSeconds = 30         -- <dataDir>/status.json refresh
```

A GTS pool serves the games its cartridges trade with: `dppt` is
Diamond/Pearl/Platinum/HeartGold/SoulSilver, and `bw` is Black/White. The
Gen 1–3 pools are a port extension. A pool can only take deposits from
games you gave it data for. The hub refuses a GTS with no data rather than
trusting what clients send. Data must come from **your own** imported
caches. Never share the cache files.

The world is a WS8 world with no player of its own at the hub. Its code
is printed at start and written to `<dataDir>/world_code.txt`. The world
keeps its id and code across restarts (`<dataDir>/world/identity.json`),
so the code you post stays valid. Delete that file to get a new code.

## Ports and port forwarding

| Port | Protocol | Needed for |
|---|---|---|
| `port` (7778) | **TCP** | short codes, tournaments, 0.7.x clients |
| `udpPort` (7778) | **UDP** | hub codes (rendezvous), GTS |
| `world.port` (7779) | **UDP** | the world |

- **VPS:** open these in the provider's firewall (for example
  `ufw allow 7778`, `ufw allow 7779/udp`).
- **Home PC or Pi:** forward the same ports on your router to the hub
  machine's LAN address, and give that machine a fixed LAN address (a DHCP
  reservation). Allow the hub through the OS firewall. Windows asks the
  first time LÖVE listens.
- **Rendezvous** needs players to reach the hub over UDP, and the hub must
  see their real public address. Don't put it behind a UDP proxy.
- A hub at home behind carrier-grade NAT (many mobile and some fibre ISPs)
  can't be reached from outside. Use a cheap VPS instead.
- Set `publicAddress` so the world code carries the address players can
  reach. A DNS name works for `hubAddress`. The world code holds an IPv4
  address.

## Admin

Set `admin.key` (12 characters or more), then from the same machine:

```
love tools/online-hub --config hub_config.lua --admin status
love tools/online-hub --admin rooms               open relay rooms and tournaments
love tools/online-hub --admin world               the world's roster (player numbers)
love tools/online-hub --admin kick 3              remove world player 3
love tools/online-hub --admin worldban 3          ...and ban their identity from the world
love tools/online-hub --admin ban 198.51.100.7    refuse an address (saved in <dataDir>/bans.json)
love tools/online-hub --admin unban 198.51.100.7
love tools/online-hub --admin log                 the last 50 log lines
love tools/online-hub --admin stop
```

The key can also come from `--key` or `POKEPORT_HUB_ADMIN_KEY`. With
`admin.localOnly = true` (the default), admin commands are only accepted
from 127.0.0.1. Five wrong keys lock an address out for 10 minutes.
`<dataDir>/status.json` is rewritten every `statusSeconds` for monitoring.

## Security and privacy

- **Nothing is encrypted.** ENet and the TCP protocol are plain text.
  Only game data crosses the wire (Pokémon records, trainer names, chat,
  battle moves), and never a save, ROM data, passwords or file paths. Tell
  your players not to put anything private in chat.
- **The hub sees IP addresses.** Rendezvous has to, because it tells each
  player the other's address. That is how a direct connection is made, so
  the two players also learn each other's address. Short codes go through
  the relay, and their players see only the hub.
- **Logs** keep only the first three octets of an address by default
  (`log.addresses = false`). Turn full addresses on only if you need them
  for bans, and say so in your community's rules. Logs are deleted after
  `log.keepDays`.
- **Abuse limits:** connections per address, a per-connection message rate,
  a byte budget per relayed pair, room, ticket and tournament caps, and
  every message is size-, depth- and type-checked before it is read. A
  flood gets rate limited or cut. It can't exhaust the hub.
- **Cheating:** the GTS validates every deposit against real game data
  (species, moves, levels, IVs/EVs, items) and holds deposits in escrow, so
  no Pokémon can end up in two places. The world refuses modded games when
  `public = true` and checks every Pokémon a trade in the world sends. A
  modified game can still lie about its own save. It can't corrupt anyone
  else's.
- **Run it unprivileged,** keep the game folder read-only for the hub's
  user, and give it write access only to `dataDir`. The config file is
  data, not code.
- The admin port is the TCP port. Keep `admin.localOnly` on unless you
  tunnel in (for example `ssh -L 7778:127.0.0.1:7778`), and pick a long key.

## Protocols (for developers)

- TCP: newline-delimited JSON, the pokeserver protocol (`src/link/Net.lua`
  and `src/link/Tournament.lua` are the clients). See the headers of
  `src/online/hub/Relay.lua` and `src/online/hub/Tournaments.lua`.
- UDP: ENet through WS1's `Transport` (`src/online/net/`). Rendezvous
  messages are `hub_register`, `hub_registered`, `hub_join`,
  `hub_introduce` and `hub_error`, as in the header of
  `src/online/net/Connector.lua`. The relay rooms also accept
  `host`/`join` over ENet. GTS messages are `gts_*` (WS7). `hub_ping` →
  `hub_pong` names the services, GTS pools and world code.
- Test knob: `test = { simulateBlockedPunch = true }` makes introductions
  lead nowhere, as if both players were behind carrier-grade NAT. Use it
  in test harnesses only.
