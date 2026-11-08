"""tools/trailer/capture_online.py -- record the online trailer shots.

    python tools/trailer/capture_online.py world room trade battle gts multi
    python tools/trailer/capture_online.py host_code
    python tools/trailer/capture_online.py --cut-only trade --cut press_a:2.0:6.5

Each shot is one run: the recording client is the real game (love.exe with
POKEPORT_DRIVER=tools/trailer/capture_online.lua, 1920x1080), the friends
are headless tools/trailer/online_peer processes. host_code is the launcher
(tools/trailer/online_launcher). Everything is on 127.0.0.1: worlds are
direct codes, the launcher's Link Hub binds 127.0.0.1, no router mapping,
no STUN, no beacon, no relay, launcher news/update fetches stubbed.

The recorder writes a raw take (<run>/raw.mp4, 30 fps) and event markers
(<run>/events.txt); the clip <out>/online_<shot>.mp4 is cut from it at
CUTS[shot] = (event, offset seconds, duration seconds), overridable with
--cut event:offset:duration.

Scratch (runs, saves, LOVE identities via APPDATA) lives under
G:/Gen2Recomped/scratch_claude/trailer_online; footage goes to --out.
Every process started here is tracked by PID and killed at the end.
"""
import argparse, ctypes, os, shutil, subprocess, sys, time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRATCH = "G:/Gen2Recomped/scratch_claude/trailer_online"
LOVE = r"C:\Program Files\LOVE\love.exe"
LOVEC = r"C:\Program Files\LOVE\lovec.exe"
FFMPEG = r"G:\Tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe"
CACHES = "G:/Gen2Recomped"

# shot -> (game, peers, (event, offset s, duration s))
SHOTS = {
    "world": ("platinum", 3, ("go", 1.5, 6.5)),
    "room": ("platinum", 3, ("go", 1.5, 6.5)),
    "trade": ("platinum", 1, ("rec", 14.5, 7.0)),
    "battle": ("platinum", 1, ("battle", 3.0, 7.0)),
    "gts": ("platinum", 3, ("deposit", 0.3, 7.0)),
    "multi": ("platinum", 3, ("battle", 0.8, 7.0)),
    "host_code": (None, 0, ("rec", 0.5, 6.0)),
}
NAMES = ["ALICE", "BOB", "CAROL"]


def syntax_check(files):
    lua = ctypes.CDLL(r"C:\Program Files\LOVE\lua51.dll")
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    bad = 0
    for f in files:
        L = lua.luaL_newstate()
        if lua.luaL_loadfile(L, f.encode()):
            bad += 1
            print("SYNTAX", lua.lua_tolstring(L, -1, None).decode(errors="replace"))
    if bad:
        sys.exit(1)


def base_env():
    env = dict(os.environ)
    tmp = "G:/Gen2Recomped/scratch_claude/tmp"
    os.makedirs(tmp, exist_ok=True)
    appdata = SCRATCH + "/appdata"
    os.makedirs(appdata + "/LOVE", exist_ok=True)
    env.update(TMP=tmp, TEMP=tmp, APPDATA=appdata, REPO=REPO.replace("\\", "/"))
    for k in ("POKEPORT_DRIVER", "POKEPORT_AUTOPILOT", "POKEPORT_SPEED"):
        env.pop(k, None)
    return env


def ensure_identity(identity):
    d = SCRATCH + "/appdata/LOVE/" + identity
    os.makedirs(d, exist_ok=True)
    opt = d + "/options.lua"
    with open(opt, "w") as f:
        f.write('return {\n  dataDir = "%s",\n  secondScreenMode = "off",\n  musicVol = 0,\n'
                '  sfxVol = 0,\n  pikaVol = 0,\n  tutorials = {},\n  zoom = 0,\n}\n' % CACHES)


def kill(procs):
    for p in procs:
        if p.poll() is None:
            p.kill()
    for p in procs:
        try:
            p.wait(5)
        except Exception:
            pass


def read_events(run):
    ev = []
    path = run + "/events.txt"
    if os.path.exists(path):
        for line in open(path):
            n, _, name = line.strip().partition(" ")
            if n.isdigit():
                ev.append((int(n), name))
    return ev


def cut(shot, run, out, spec):
    raw = run + "/raw.mp4"
    if not os.path.exists(raw):
        print("no raw take for", shot)
        return False
    evname, off, dur = spec
    frames = None
    for n, name in read_events(run):
        if name == evname or name.startswith(evname + " "):
            frames = n
            break
    if frames is None:
        print("no event %s in %s; cutting from 0" % (evname, shot))
        frames = 0
    start = max(0.0, frames / 30.0 + off)
    dst = os.path.join(out, "online_%s.mp4" % shot)
    cmd = [FFMPEG, "-y", "-loglevel", "error", "-ss", "%.3f" % start, "-i", raw, "-t", "%.3f" % dur,
           "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-r", "30",
           "-an", "-movflags", "+faststart", dst]
    subprocess.run(cmd, check=True)
    print("cut %s: %s @ %.2fs for %.2fs -> %s" % (shot, evname, start, dur, dst))
    return True


def record_game_shot(shot, game, peers, run):
    env = base_env()
    identity = "trailer_online_" + shot
    ensure_identity(identity)
    rec_env = dict(env)
    rec_env.update(POKEPORT_IDENTITY=identity, POKEPORT_VERSION=game, POKEPORT_NO_MODS="1",
                   POKEPORT_DRIVER="tools/trailer/capture_online.lua", SHOT=shot, RUN=run,
                   FFMPEG=FFMPEG, PEERS=str(peers))
    procs = []
    logs = []
    try:
        lf = open(run + "/recorder.log", "w")
        logs.append(lf)
        rec = subprocess.Popen([LOVE, "."], cwd=REPO, env=rec_env, stdout=lf, stderr=subprocess.STDOUT)
        procs.append(rec)
        print("recorder pid", rec.pid)
        for i in range(peers):
            name = NAMES[i] if shot != "trade" and shot != "battle" else "BOB"
            penv = dict(env)
            penv.update(PEER_FPS=os.environ.get("PEER_FPS", "60"), SHOT=shot, PEER_NAME=name, PEER_IDX=str(i + 1), RUN=run,
                        INSTALL=CACHES + "/" + game, VERSION=game)
            pf = open(run + "/peer_%s.log" % name, "w")
            logs.append(pf)
            p = subprocess.Popen([LOVEC, "tools/trailer/online_peer"], cwd=REPO, env=penv, stdout=pf,
                                 stderr=subprocess.STDOUT, creationflags=0x08000000)
            procs.append(p)
            print("peer", name, "pid", p.pid)
            time.sleep(1.0)
        try:
            rec.wait(timeout=900)
        except subprocess.TimeoutExpired:
            print("recorder timed out")
        # let the peers see "stop" and leave
        t0 = time.time()
        while time.time() - t0 < 10 and any(p.poll() is None for p in procs[1:]):
            time.sleep(0.2)
    finally:
        kill(procs)
        for f in logs:
            f.close()
    print("recorder exit", procs[0].returncode)
    return os.path.exists(run + "/recorder_ok")


def record_launcher(run):
    env = base_env()
    ensure_identity("trailer_online_launcher")
    env.update(RUN=run, FFMPEG=FFMPEG, IDENTITY="trailer_online_launcher",
               ROOT=REPO.replace("\\", "/"),
               POKEPORT_HUB_GAMES_ROOT=CACHES, POKEPORT_HUB_NO_PORTMAP="1", POKEPORT_HUB_BIND="127.0.0.1",
               POKEPORT_HUB_LAN="127.0.0.1", POKEPORT_HUB_BEACON_TARGETS="127.0.0.1",
               POKEPORT_HUB_BEACON_PORT="47992")
    procs = []
    with open(run + "/launcher.log", "w") as lf:
        try:
            p = subprocess.Popen([LOVE, "tools/trailer/online_launcher"], cwd=REPO, env=env, stdout=lf,
                                 stderr=subprocess.STDOUT)
            procs.append(p)
            print("launcher pid", p.pid)
            try:
                p.wait(timeout=300)
            except subprocess.TimeoutExpired:
                print("launcher timed out")
        finally:
            kill(procs)
    return os.path.exists(run + "/recorder_ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", nargs="+")
    ap.add_argument("--out", default="G:/Gen2Recomped/trailer_footage")
    ap.add_argument("--cut", default=None, help="event:offset:duration (one shot)")
    ap.add_argument("--cut-only", action="store_true")
    ap.add_argument("--game", default=None)
    a = ap.parse_args()
    syntax_check([os.path.join(REPO, p) for p in (
        "tools/trailer/capture_online.lua", "tools/trailer/online_peer/main.lua",
        "tools/trailer/online_peer/conf.lua", "tools/trailer/online_launcher/main.lua",
        "tools/trailer/online_launcher/conf.lua")])
    os.makedirs(a.out, exist_ok=True)
    for shot in a.shots:
        game, peers, spec = SHOTS[shot]
        if a.game and game:
            game = a.game
        if a.cut:
            e, o, d = a.cut.split(":")
            spec = (e, float(o), float(d))
        run = SCRATCH + "/run/" + shot
        if not a.cut_only:
            if os.path.isdir(run):
                shutil.rmtree(run)
            os.makedirs(run)
            print("=== %s (%s, %d peers)" % (shot, game or "launcher", peers))
            ok = record_launcher(run) if shot == "host_code" else record_game_shot(shot, game, peers, run)
            print("recorded" if ok else "RECORDING FAILED", shot)
            if not ok:
                continue
        cut(shot, run, a.out, spec)


if __name__ == "__main__":
    main()
