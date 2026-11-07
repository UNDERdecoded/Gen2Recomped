# Playing online

How to link with friends. Nothing here needs an account or a company's server:
one player's game (or their Link Hub) is the server.

Every game has **LINK** in its START menu (Gen 1 to Gen 5). The Pokémon Centers'
own counters work too: the Cable Club, Trade Center and Colosseum, the Union
Room, the Wi-Fi Club, and the Global Terminal.

## Trade or battle with one friend

1. One player picks **START → LINK → HOST**. The game shows a code like
   `XXXX-XXXX-XXXX-XXXX-X`. Copy it or read it out.
2. The other picks **START → LINK → JOIN**. Games on the same network are listed;
   otherwise choose **ENTER A CODE** and type or paste it.
3. The host picks **TRADE** or **BATTLE**.

Codes have no 0, O, 1, I or L, so read-aloud mistakes are rare, and a typo is
caught as soon as it is entered.

**A code contains the host's internet address.** Share it only with people you
trust. For a code that works on your own network only, turn **ROUTER** and
**ADDR FINDER** off in Online settings and leave **MY ADDRESS** empty.

If a join fails, the screen offers **SWAP: I'LL HOST** (only the host has to be
reachable, so the other way round often works) and **BOTH ENTER CODES** (both
games call each other at once, which gets through many routers).

**Different games:** matching games link fully. Two games of one family
(Emerald and FireRed, Platinum and HeartGold) can battle, and trade what both
games have. Gen 1 and Gen 2 use the Time Capsule. Gen 3 → 4 and Gen 4 → 5 are a
one-way gift, under the Pal Park and Poké Transfer rules.

**Mods:** online needs an unmodded game on both sides, unless both have the same
mods. The game offers to turn them off and restart.

## The link rooms

Talk to the receptionist as on the cartridge, then HOST or JOIN at the prompt.

* **Trade Center and Colosseum** (Gen 2, Gen 3, Platinum, HeartGold, SoulSilver):
  you walk in and can see your friend walking around. Go to your seat or spot to
  start. When it is over you stay in the room: **step off the spot and back on
  (or use the console again) for another battle or trade.** Leave through the
  door when you are done; that ends the link for both of you.
* **Union Room:** the players of your world who are in a Union Room too. Pick one
  to trade or battle, or use **LINK CODE**. **MULTI: LEAD** and **MULTI: JOIN**
  start a four-player multi battle (Gen 3 to Gen 5).
* **Direct Corner and Colosseum multi:** four players, two against two. The
  leader gets a code and sets the teams.
* **Battle Subway Multi and Super Multi** (Black and White, "with a friend"):
  two players against the Subway, each with two Pokémon at level 50. Each player
  keeps their own streak and Battle Points. The leader can rest between cars; the
  train carries on another time only with the same friend.

## Worlds

A world is a small shared overworld: everyone stays in their own game and save,
and sees the others walking on the same maps.

* **START → LINK → WORLDS → HOST A WORLD** gives you a code to share. Up to 8
  players by default, 16 at most (**WORLD PLAYERS** in Online settings).
* **Walk up to a player and press A** to trade or battle. There is chat and
  emotes, and the host can kick or ban.
* The world stays on the host's disk; open it again any time.

## GTS

The Global Trade Station: leave a Pokémon for someone else's offer, even when they
aren't online. Open it at the Global Terminal or **START → LINK → GTS**.

It runs in a world you're in (the world's host holds it) or on a Link Hub. The row
appears once you have one. Your Pokémon are in the host's care while listed: only
list on a world or hub you trust.

## The Link Hub

The hub is the game's own little server. It introduces friends so they can connect
directly, and also runs a relay for short codes, tournaments, a GTS and a
permanent world.

**In the launcher:** open **Online Hub → HOST WITH FRIENDS**. Share the code or the
QR. Friends open **Online Hub → JOIN FRIEND** and paste it (or enter it in a game's
**LINK → JOIN**).

The code carries your LAN address and, when your router opened the port, your
internet address, so friends on the same Wi-Fi and friends elsewhere can both use
one code.

**The app can't use the camera.** To use a QR, scan it with your phone's camera or
a QR app, copy the code it shows, then paste it.

**On a server:** see `tools/online-hub/README.md`. Set **LINK HUB** in Online settings
to `name:port` so your games use it.

## Connection test

**OPTIONS → ONLINE → CONNECTION TEST** tells you your LAN address, whether your
router opened the port (and which outside port it chose), the public address your
router reports, and whether friends should be able to reach you. It talks to your
router only, and nothing else. It can't prove the last step: only a friend's game
can do that.

## Troubleshooting

| What you see | What to do |
|---|---|
| **Friend on the same Wi-Fi can't join** | Check the firewall (below), and that you're not on a guest network, which blocks devices from each other. |
| **Friend elsewhere can't join** | Run CONNECTION TEST. If it says they probably can't reach you, use **SWAP** so they host, try **BOTH ENTER CODES**, use a Link Hub, or forward the UDP port on your router and fill in **MY ADDRESS**. |
| **"Your router's own address isn't public"** | Your provider shares one address between customers (carrier NAT), or there are two routers. A friend hosting, a Link Hub on a server, or a short code all work. |
| **Windows asks about the firewall** | Choose **Allow** on Private networks. If you pressed Cancel: Windows Security → Firewall → Allow an app, tick Private for the game. |
| **Mobile data** | Friends usually can't reach a phone on mobile data. Let them host, or use a hub. |
| **iPhone or iPad** | Allow *Local Network* when iOS asks. Nearby games aren't listed (Apple restricts broadcasts): enter the code. |
| **Android: nearby games not listed** | Enter the code. Listing needs a build with the multicast lock. |
| **Switch** | Untested, and going online with homebrew can get a console banned by Nintendo. The game asks you first. |
| **"Made by a newer version of the game"** | Update the game to match your friend's. |
| **"Check your mods" / "Can't link"** | Your games differ. The screen says how. |
| **The other player disappeared** | The link ended. A trade only completes when both games have confirmed it; your Pokémon are safe. |
