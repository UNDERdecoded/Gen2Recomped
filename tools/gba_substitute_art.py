"""Locate the native Substitute loader's literal pool and validate its art."""
import struct


def discover(rom, decompress):
    data = rom.d
    # The loader copies 0x200 words to OBJ VRAM through DMA3. Its literal
    # pool also names the shared mon graphics buffer and all three LZ blobs.
    anchor = struct.pack("<II", 0x040000D4, 0x84000200)
    candidates = []
    start = 0
    while True:
        at = data.find(anchor, start)
        if at < 0:
            break
        start = at + 1
        if at < 0x5C or at % 4:
            continue
        word = lambda delta: struct.unpack_from("<I", data, at + delta)[0]
        buffer = word(-8)
        if buffer != word(-0x58) or not 0x02000000 <= buffer < 0x02040000:
            continue
        offsets = {"front": word(-0x5C) - 0x08000000,
                   "back": word(-12) - 0x08000000,
                   "palette": word(-4) - 0x08000000}
        blobs = {}
        for name, off in offsets.items():
            size = 32 if name == "palette" else 2048
            if not 0 <= off <= len(data) - 4:
                break
            if data[off] != 0x10 or int.from_bytes(data[off + 1:off + 4], "little") != size:
                break
            try:
                raw = decompress(rom, off)
            except (IndexError, ValueError, AssertionError):
                break
            if raw is None or len(raw) != size or len(set(raw)) < 2:
                break
            blobs[name] = raw
        if len(blobs) != 3 or blobs["front"] == blobs["back"]:
            continue
        if any(blobs["palette"][i] & 0x80 for i in range(1, 32, 2)):
            continue
        candidates.append({**offsets, "loaderPool": at})
    if len(candidates) != 1:
        raise ValueError(f"expected one verified Substitute loader, found {len(candidates)}")
    return candidates[0]
