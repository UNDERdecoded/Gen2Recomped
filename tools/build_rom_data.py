#!/usr/bin/env python3
"""Build game data directly from a canonical Pokemon Red/Blue/Yellow ROM.

It accepts one user-provided, canonical US Gen-1 ROM. Symbol addresses and
assembly-erased names are bundled as non-ROM metadata, so no pret checkout,
RGBDS build, or external .sym file is required for the public ROM path.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import shutil
import sys
from collections import deque

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import util  # noqa: E402
from rom_data import (  # noqa: E402
    CANONICAL_BLUE_SHA1, CANONICAL_GOLD_SHA1, CANONICAL_RED_SHA1,
    CANONICAL_SILVER_SHA1, CANONICAL_YELLOW_SHA1,
    RomImage, SymbolTable, bcd, decode_text, decompress_pic, load_manifest,
    read_string,
)


DATASETS = (
    "constants", "charmap", "tilesets", "maps", "font", "sprites", "moves", "items",
    "type_chart", "palettes", "icons", "pokemon", "trainers", "encounters",
    "text", "field", "battle_anims",
)

_TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
VERSION_MANIFESTS = {
    "red": os.path.join(_TOOLS_DIR, "rom_manifest.json"),
    "blue": os.path.join(_TOOLS_DIR, "rom_manifest_blue.json"),
    "yellow": os.path.join(_TOOLS_DIR, "rom_manifest_yellow.json"),
    "gold": os.path.join(_TOOLS_DIR, "rom_manifest_gold.json"),
    "silver": os.path.join(_TOOLS_DIR, "rom_manifest_silver.json"),
}
VERSION_SHA1 = {
    "red": CANONICAL_RED_SHA1,
    "blue": CANONICAL_BLUE_SHA1,
    "yellow": CANONICAL_YELLOW_SHA1,
}
VERSION_SHA1["gold"] = CANONICAL_GOLD_SHA1
VERSION_SHA1["silver"] = CANONICAL_SILVER_SHA1
SHA1_TO_VERSION = {sha1: version for version, sha1 in VERSION_SHA1.items()}

GB_SHADES = (
    (255, 255, 255, 255),
    (170, 170, 170, 255),
    (85, 85, 85, 255),
    (0, 0, 0, 255),
)


def _symbol(symbols, name):
    try:
        return symbols[name]
    except KeyError as exc:
        raise ValueError(f"required symbol {name!r} is missing") from exc


def _has_symbol(symbols, name):
    return name in symbols.by_name


def _next_symbol_address(symbols, bank, address):
    next_addresses = [
        symbol.address
        for symbol in symbols.by_name.values()
        if symbol.bank == bank and symbol.address > address
    ]
    if not next_addresses:
        return None
    return min(next_addresses)


def resolve_manifest_path(version, manifest_arg):
    """Pick the shipped manifest for --version, or an explicit --manifest path."""
    if manifest_arg is not None:
        return manifest_arg
    path = VERSION_MANIFESTS[version]
    if not os.path.isfile(path):
        raise ValueError(
            f"manifest for version {version!r} is missing: {path} "
            f"(generate it before extracting)")
    return path


def version_for_manifest(manifest, requested_version=None, manifest_explicit=False):
    """Resolve game version from an explicit flag or the manifest romSha1."""
    rom_sha1 = manifest.get("romSha1")
    detected = SHA1_TO_VERSION.get(rom_sha1)
    if manifest_explicit:
        # Explicit --manifest wins: hash/version come from the file itself.
        return detected or requested_version or "red"
    if requested_version and detected and requested_version != detected:
        raise ValueError(
            f"--version {requested_version} does not match manifest romSha1 "
            f"{rom_sha1} ({detected})")
    return detected or requested_version or "red"


def ensure_supported_manifest(manifest, version, manifest_path, datasets):
    if manifest.get("stub") and manifest.get("generation") == 2:
        allowed = {"constants", "charmap", "moves", "items", "text", "maps", "tilesets"}
        if set(datasets).issubset(allowed):
            if ("text" in datasets or "maps" in datasets or "tilesets" in datasets) and not manifest.get("symbols"):
                raise ValueError(
                    "Gen2 stub text/maps/tilesets extraction requires embedded symbols. "
                    "Run scripts/setup_gen2_symbols.ps1 first.")
            return
        raise ValueError(
            "Gen2 manifest is a Phase 2 stub and cannot be extracted yet: "
            f"{manifest_path}. Rebuild it with tools/make_gen2_manifest.py "
            "for Phase 2B identity/constants scaffolding. Only "
            "--only constants/--only charmap/--only moves/--only items/--only text/--only maps/--only tilesets are "
            "supported on stub Gen2 manifests; implement "
            "Gen2 extractor mappings before decoding other datasets.")


def extract_constants(manifest, out_dir):
    data = manifest["constants"]
    util.write_lua(
        os.path.join(out_dir, "constants.lua"), data,
        header="Source: ROM metadata manifest")
    return data


def extract_charmap(manifest, out_dir):
    data = manifest["charmap"]
    util.write_lua(
        os.path.join(out_dir, "charmap.lua"), data,
        header="Source: ROM metadata manifest charmap")
    return data


def _read_terminated(rom, bank, address, terminator, limit=256):
    out = []
    for offset in range(limit):
        value = rom.byte(bank, address + offset)
        if value == terminator:
            return out
        out.append(value)
    raise ValueError(
        f"unterminated byte list at {bank:02x}:{address:04x}")


def _decode_2bpp(raw, width, height, transparent_color0=False):
    if width % 8 or height % 8:
        raise ValueError(f"2bpp dimensions must be tile-aligned: {width}x{height}")
    tile_count = width // 8 * (height // 8)
    if len(raw) != tile_count * 16:
        raise ValueError(
            f"2bpp payload is {len(raw)} bytes, expected {tile_count * 16}")

    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    tiles_per_row = width // 8
    for tile in range(tile_count):
        tile_x = (tile % tiles_per_row) * 8
        tile_y = (tile // tiles_per_row) * 8
        for y in range(8):
            low = raw[tile * 16 + y * 2]
            high = raw[tile * 16 + y * 2 + 1]
            for x in range(8):
                bit = 7 - x
                shade = ((high >> bit) & 1) * 2 + ((low >> bit) & 1)
                color = GB_SHADES[shade]
                if transparent_color0 and shade == 0:
                    color = (255, 255, 255, 0)
                pixels[tile_x + x, tile_y + y] = color
    return image


def _decode_1bpp(raw, width, height, transparent_color0=False):
    if width % 8 or height % 8:
        raise ValueError(f"1bpp dimensions must be tile-aligned: {width}x{height}")
    tile_count = width // 8 * (height // 8)
    if len(raw) != tile_count * 8:
        raise ValueError(
            f"1bpp payload is {len(raw)} bytes, expected {tile_count * 8}")

    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    tiles_per_row = width // 8
    for tile in range(tile_count):
        tile_x = (tile % tiles_per_row) * 8
        tile_y = (tile // tiles_per_row) * 8
        for y in range(8):
            row = raw[tile * 8 + y]
            for x in range(8):
                filled = bool(row & (1 << (7 - x)))
                if filled:
                    color = (0, 0, 0, 255)
                elif transparent_color0:
                    color = (255, 255, 255, 0)
                else:
                    color = (255, 255, 255, 255)
                pixels[tile_x + x, tile_y + y] = color
    return image


def _columns_to_rows(raw, tiles_wide, tiles_high, bytes_per_tile=16):
    out = bytearray(len(raw))
    for y in range(tiles_high):
        for x in range(tiles_wide):
            source = (x * tiles_high + y) * bytes_per_tile
            target = (y * tiles_wide + x) * bytes_per_tile
            out[target:target + bytes_per_tile] = \
                raw[source:source + bytes_per_tile]
    return bytes(out)


def _save_png(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, optimize=True)


def _matte_color0(image):
    pixels = image.load()
    width, height = image.size
    queue = deque()
    seen = set()

    def add(x, y):
        if (x, y) not in seen and pixels[x, y] == (255, 255, 255, 255):
            seen.add((x, y))
            queue.append((x, y))

    for x in range(width):
        add(x, 0)
        add(x, height - 1)
    for y in range(height):
        add(0, y)
        add(width - 1, y)
    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (255, 255, 255, 0)
        for next_x, next_y in (
                (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                add(next_x, next_y)
    return image


def _write_2bpp_png(
        raw, width, height, path, transparent_color0=False):
    _save_png(
        _decode_2bpp(raw, width, height, transparent_color0),
        path)


def _lz3_flip(byte):
    value = 0
    for bit in range(8):
        value |= ((byte >> bit) & 1) << (7 - bit)
    return value


def _decompress_lz3(raw):
    out = bytearray()
    index = 0
    while index < len(raw):
        byte = raw[index]
        index += 1
        if byte == 0xFF:
            break

        command = byte >> 5
        length_code = byte & 0x1F
        length = length_code + 1
        if command == 7:
            if index >= len(raw):
                raise ValueError("incomplete Gen2 lz3 long command")
            command = length_code >> 2
            length = ((length_code & 0x03) << 8) | raw[index]
            index += 1
            length += 1

        if command == 0:
            if index + length > len(raw):
                raise ValueError("incomplete Gen2 lz3 literal command")
            out.extend(raw[index:index + length])
            index += length
        elif command == 1:
            if index >= len(raw):
                raise ValueError("incomplete Gen2 lz3 iterate command")
            out.extend([raw[index]] * length)
            index += 1
        elif command == 2:
            if index + 2 > len(raw):
                raise ValueError("incomplete Gen2 lz3 alternate command")
            first = raw[index]
            second = raw[index + 1]
            index += 2
            for offset in range(length):
                out.append(first if offset % 2 == 0 else second)
        elif command == 3:
            out.extend([0] * length)
        elif command in (4, 5, 6):
            if index >= len(raw):
                raise ValueError("incomplete Gen2 lz3 rewrite command")
            offset_byte = raw[index]
            index += 1
            if offset_byte & 0x80:
                base = len(out) - ((offset_byte & 0x7F) + 1)
            else:
                if index >= len(raw):
                    raise ValueError("incomplete Gen2 lz3 rewrite command")
                base = (offset_byte << 8) | raw[index]
                index += 1
            if base < 0 or base >= len(out):
                raise ValueError("Gen2 lz3 rewrite offset out of range")
            for delta in range(length):
                source_index = base + delta if command in (4, 5) else base - delta
                if source_index < 0 or source_index >= len(out):
                    raise ValueError("Gen2 lz3 rewrite source out of range")
                value = out[source_index]
                if command == 5:
                    value = _lz3_flip(value)
                out.append(value)
        else:
            raise ValueError(f"unsupported Gen2 lz3 command {command}")

    return bytes(out)


def _write_compressed_pic(rom, symbols, label, path):
    symbol = _symbol(symbols, label)
    compressed = rom.bytes(
        symbol.bank, symbol.address, 0x8000 - symbol.address)
    raw, width = decompress_pic(compressed)
    image = _matte_color0(
        _decode_2bpp(raw, width * 8, width * 8))
    _save_png(image, path)
    return width


def extract_tilesets(rom, symbols, manifest, out_dir, assets_dir):
    order = manifest["constants"]["tilesetOrder"]
    metadata = manifest["tilesets"]
    animations = manifest["tileAnimations"]
    if not animations:
        animations = [{}]
    stub_mode = _is_gen2_stub_manifest(manifest)
    if stub_mode and not order:
        rows = _gen2_tileset_rows(manifest)
        order = [f"Tileset{family}" for _, _, family, _ in rows]
        metadata = [
            {
                "id": f"Tileset{family}",
                "imageWidth": 128,
                "imageHeight": 128,
                "blockCount": 0x80,
                "imageBase": family.lower(),
            }
            for _, _, family, _ in rows
        ]
        if not order:
            raise ValueError("Gen2 tileset scaffold has no inferred tileset families")
    elif len(metadata) != len(order):
        raise ValueError("tileset metadata count does not match constants")
    warp_pointers = symbols.by_name.get("WarpTileIDPointers")
    door_pointers = symbols.by_name.get("DoorTileIDPointers")

    doors = {}
    if door_pointers is not None:
        address = door_pointers.address
        while True:
            tileset_id = rom.byte(door_pointers.bank, address)
            if tileset_id == 0xFF:
                break
            pointer = _normalize_banked_address(
                door_pointers.bank,
                rom.word(door_pointers.bank, address + 1))
            door_bank = _bank_for_address(pointer, door_pointers.bank)
            try:
                doors[tileset_id] = _read_terminated(
                    rom, door_bank, pointer, 0)
            except Exception:
                doors[tileset_id] = []
            address += 3

    out = {}
    written_images = set()
    for index, (const_name, spec) in enumerate(zip(order, metadata)):
        if isinstance(spec, str):
            spec = metadata[index] if isinstance(metadata, list) else None
        if not isinstance(spec, dict):
            raise ValueError(f"tileset metadata for {const_name} is malformed")
        if spec["id"] != const_name:
            raise ValueError(
                f"tileset metadata {spec['id']} is out of order at {const_name}")
        if stub_mode:
            base_name = spec.get("imageBase") or const_name.removeprefix("Tileset")
            gfx_symbol = _symbol(symbols, f"{const_name}GFX")
            block_symbol = _symbol(symbols, f"{const_name}Meta")
            coll_symbol = _symbol(symbols, f"{const_name}Coll")
            gfx_bank = gfx_symbol.bank
            counters = []
            grass = 0xFF
            animation_id = 0
            blocks_raw = rom.bytes(
                block_symbol.bank, block_symbol.address, spec["blockCount"] * 16)
        else:
            row_address = headers.address + index * 12
            gfx_bank = rom.byte(headers.bank, row_address)
            block_pointer = _normalize_banked_address(
                gfx_bank, rom.word(headers.bank, row_address + 1))
            gfx_pointer = _normalize_banked_address(
                gfx_bank, rom.word(headers.bank, row_address + 3))
            collision_pointer = _normalize_banked_address(
                gfx_bank, rom.word(headers.bank, row_address + 5))
            block_bank = _bank_for_address(block_pointer, gfx_bank)
            gfx_data_bank = _bank_for_address(gfx_pointer, gfx_bank)
            collision_bank = _bank_for_address(collision_pointer, gfx_bank)
            counters = list(rom.bytes(headers.bank, row_address + 7, 3))
            grass = rom.byte(headers.bank, row_address + 10)
            animation_id = rom.byte(headers.bank, row_address + 11)
            if animation_id >= len(animations):
                animation_id = 0

            blocks_raw = rom.bytes(
                block_bank, block_pointer, spec["blockCount"] * 16)
        blocks = [
            list(blocks_raw[offset:offset + 16])
            for offset in range(0, len(blocks_raw), 16)
        ]
        walkable = []
        if stub_mode:
            try:
                walkable = sorted(_read_terminated(
                    rom, coll_symbol.bank, coll_symbol.address, 0xFF))
            except Exception:
                walkable = list(rom.bytes(
                    coll_symbol.bank, coll_symbol.address, 256))
        else:
            try:
                walkable = sorted(_read_terminated(
                    rom, collision_bank, collision_pointer, 0xFF))
            except Exception:
                try:
                    walkable = list(rom.bytes(
                        collision_bank, collision_pointer, 256))
                except Exception:
                    walkable = []
        warp_tiles = []
        if warp_pointers is not None:
            try:
                warp_pointer = _normalize_banked_address(
                    warp_pointers.bank,
                    rom.word(warp_pointers.bank, warp_pointers.address + index * 2))
                if warp_pointer >= 0x4000:
                    warp_bank = warp_pointers.bank
                    warp_tiles = sorted(set(_read_terminated(
                        rom, warp_bank, warp_pointer, 0xFF)))
            except Exception:
                warp_tiles = []

        base = spec.get("imageBase") or const_name.lower()
        image_path = os.path.join(assets_dir, "tilesets", base + ".png")
        if base not in written_images:
            if stub_mode:
                next_address = _next_symbol_address(
                    symbols, gfx_symbol.bank, gfx_symbol.address)
                if next_address is None:
                    next_address = 0x8000
                compressed = rom.bytes(
                    gfx_bank, gfx_symbol.address,
                    max(0, 0x8000 - gfx_symbol.address))
                pixels = _decompress_lz3(compressed)
                width, height = _infer_tileset_dimensions(len(pixels))
            else:
                byte_length = spec["imageWidth"] * spec["imageHeight"] // 4
                stored_length = block_pointer - gfx_pointer
                if stored_length < 0 or stored_length > byte_length \
                        or stored_length % 16:
                    width, height = _infer_tileset_dimensions(byte_length)
                    stored_length = byte_length
                else:
                    width, height = spec["imageWidth"], spec["imageHeight"]
                pixels = rom.bytes(gfx_data_bank, gfx_pointer, stored_length)
                if len(pixels) < byte_length:
                    pixels += bytes(byte_length - len(pixels))
            _write_2bpp_png(
                pixels,
                width, height, image_path)
            written_images.add(base)

        out[const_name] = {
            "id": const_name,
            "source": f"ROM:Tilesets[{index}]",
            "image": f"assets/generated/tilesets/{base}.png",
            "imageWidth": spec["imageWidth"],
            "imageHeight": spec["imageHeight"],
            "tilesPerRow": spec["imageWidth"] // 8,
            "blocks": blocks,
            "walkable": walkable,
            "counterTiles": [value for value in counters if value != 0xFF],
            "grassTile": None if grass == 0xFF else grass,
            "doorTiles": sorted(doors.get(index, [])),
            "warpTiles": warp_tiles,
            "animation": animations[animation_id] if not stub_mode else {},
        }
        if stub_mode and rom is not None:
            pal_map = _gen2_read_palmap(rom, symbols, const_name)
            if pal_map:
                pal_set_idx = _gen2_palette_set_index(const_name)
                pal_colors = _gen2_read_palette_set(rom, pal_set_idx)
                out[const_name]["palMap"] = pal_map
                out[const_name]["palColors"] = pal_colors

    if not stub_mode:
        for number in (1, 2, 3):
            symbol = _symbol(symbols, f"FlowerTile{number}")
            _write_2bpp_png(
                rom.bytes(symbol.bank, symbol.address, 16), 8, 8,
                os.path.join(assets_dir, "tilesets", f"flower{number}.png"))
        spinner = _symbol(symbols, "SpinnerArrowAnimTiles")
        _write_2bpp_png(
            rom.bytes(spinner.bank, spinner.address, 64), 32, 8,
            os.path.join(assets_dir, "tilesets", "spinners.png"))

    util.write_lua(
        os.path.join(out_dir, "tilesets.lua"), out,
        header="Source: canonical Pokemon Red ROM (Tilesets, blocksets,\n"
               "tile graphics, collision/warp/door lists)")
    return out


def extract_font(rom, symbols, manifest, out_dir, assets_dir):
    fonts_dir = os.path.join(assets_dir, "fonts")
    main_symbol = _symbol(symbols, "FontGraphics")
    main_raw = rom.bytes(main_symbol.bank, main_symbol.address, 128 * 8)
    main = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
    pixels = main.load()
    for tile in range(128):
        tile_x = (tile % 16) * 8
        tile_y = (tile // 16) * 8
        for y in range(8):
            row = main_raw[tile * 8 + y]
            for x in range(8):
                if row & (1 << (7 - x)):
                    pixels[tile_x + x, tile_y + y] = (0, 0, 0, 255)
    _save_png(main, os.path.join(fonts_dir, "font.png"))

    extra_symbol = _symbol(symbols, "TextBoxGraphics")
    extra_raw = rom.bytes(extra_symbol.bank, extra_symbol.address, 32 * 16)
    extra_shaded = _decode_2bpp(extra_raw, 128, 16)
    extra = Image.new("RGBA", extra_shaded.size, (0, 0, 0, 0))
    source_pixels = extra_shaded.load()
    target_pixels = extra.load()
    for y in range(extra.height):
        for x in range(extra.width):
            if source_pixels[x, y][0] < 128:
                target_pixels[x, y] = (0, 0, 0, 255)

    pokedex = _symbol(symbols, "PokedexTileGraphics")
    dex_tiles = _decode_2bpp(
        rom.bytes(pokedex.bank, pokedex.address, 32), 16, 8)
    dex_pixels = dex_tiles.load()
    for y in range(8):
        for x in range(16):
            extra.putpixel(
                (x, y),
                (0, 0, 0, 255) if dex_pixels[x, y][0] < 128
                else (0, 0, 0, 0))
    _save_png(extra, os.path.join(fonts_dir, "font_extra.png"))

    data = {
        "source": "ROM:FontGraphics, TextBoxGraphics, PokedexTileGraphics",
        "image": "assets/generated/fonts/font.png",
        "imageExtra": "assets/generated/fonts/font_extra.png",
        "mainBase": 0x80,
        "extraBase": 0x60,
        "glyphsPerRow": 16,
        "charmap": manifest["fontCharmap"],
    }
    util.write_lua(
        os.path.join(out_dir, "font.lua"), data,
        header="Source: canonical Pokemon Red ROM font graphics;\n"
               "symbolic charmap comes from the metadata manifest")
    return data


def extract_sprites(rom, symbols, manifest, out_dir, assets_dir):
    order = manifest["constants"]["spriteOrder"]
    metadata = manifest["sprites"]["order"]
    table = _symbol(symbols, "SpriteSheetPointerTable")
    if len(metadata) != len(order):
        raise ValueError("sprite metadata count does not match constants")

    out = {}
    written = set()
    for index, (const_name, spec) in enumerate(zip(order, metadata)):
        if spec["id"] != const_name:
            raise ValueError(
                f"sprite metadata {spec['id']} is out of order at {const_name}")
        address = table.address + index * 4
        pointer = rom.word(table.bank, address)
        first_half_length = rom.byte(table.bank, address + 2)
        bank = rom.byte(table.bank, address + 3)
        width = spec["imageWidth"]
        height = spec["imageHeight"]
        byte_length = width * height // 4
        frames = height // 16
        expected_length = first_half_length * (2 if frames >= 6 else 1)
        if byte_length != expected_length:
            # Commercial ROM sheet length wins over pret PNG atlases (Yellow's
            # nurse.png is 16x64 but SpriteSheetPointerTable still stores 12
            # tiles / 192 bytes).
            byte_length = expected_length
            if byte_length * 4 % width:
                raise ValueError(
                    f"{const_name}: ROM sprite length {byte_length} is not "
                    f"tile-aligned for width {width}")
            height = byte_length * 4 // width
            frames = height // 16
            expected_length = first_half_length * (2 if frames >= 6 else 1)
            if byte_length != expected_length:
                raise ValueError(
                    f"{const_name}: ROM sprite length {expected_length} does not "
                    f"match atlas length {width * spec['imageHeight'] // 4}")

        base = spec["imageBase"]
        if base not in written:
            _write_2bpp_png(
                rom.bytes(bank, pointer, byte_length),
                width, height,
                os.path.join(assets_dir, "sprites", base + ".png"),
                transparent_color0=True)
            written.add(base)
        out[const_name] = {
            "id": const_name,
            "source": f"ROM:SpriteSheetPointerTable[{index}]",
            "image": f"assets/generated/sprites/{base}.png",
            "frames": frames,
            "walker": frames >= 6,
        }

    bike = manifest["sprites"]["bike"]
    bike_symbol = _symbol(symbols, bike["label"])
    bike_length = bike["imageWidth"] * bike["imageHeight"] // 4
    _write_2bpp_png(
        rom.bytes(bike_symbol.bank, bike_symbol.address, bike_length),
        bike["imageWidth"], bike["imageHeight"],
        os.path.join(assets_dir, "sprites", bike["imageBase"] + ".png"),
        transparent_color0=True)
    bike_frames = bike["imageHeight"] // 16
    out["SPRITE_RED_BIKE"] = {
        "id": "SPRITE_RED_BIKE",
        "source": "ROM:RedBikeSprite",
        "image": "assets/generated/sprites/red_bike.png",
        "frames": bike_frames,
        "walker": bike_frames >= 6,
    }

    # Yellow-only: the surfing-Pikachu overworld ride sheet, loaded
    # outside SpriteSheetPointerTable (LoadSurfingPlayerSpriteGraphics2) --
    # same extra extract as RedBikeSprite. (RFC 0001)
    surf = manifest["sprites"].get("surfPikachu")
    if surf and _has_symbol(symbols, surf["label"]):
        surf_symbol = _symbol(symbols, surf["label"])
        surf_length = surf["imageWidth"] * surf["imageHeight"] // 4
        _write_2bpp_png(
            rom.bytes(surf_symbol.bank, surf_symbol.address, surf_length),
            surf["imageWidth"], surf["imageHeight"],
            os.path.join(assets_dir, "sprites", surf["imageBase"] + ".png"),
            transparent_color0=True)
        surf_frames = surf["imageHeight"] // 16
        out["SPRITE_SURFING_PIKACHU"] = {
            "id": "SPRITE_SURFING_PIKACHU",
            "source": f"ROM:{surf['label']}",
            "image": f"assets/generated/sprites/{surf['imageBase']}.png",
            "frames": surf_frames,
            "walker": surf_frames >= 6,
        }

    util.write_lua(
        os.path.join(out_dir, "sprites.lua"), out,
        header="Source: canonical Pokemon Red ROM (overworld sprite sheets)")
    return out


def _signed_byte(value):
    return value - 0x100 if value & 0x80 else value


def _map_id(order, value):
    if value == 0xFF:
        return "LAST_MAP"
    if value >= len(order):
        raise ValueError(f"unknown map id ${value:02X}")
    return order[value]


def extract_maps(rom, symbols, manifest, out_dir):
    if _is_gen2_stub_manifest(manifest):
        return _extract_maps_from_stub_manifest(manifest, out_dir, rom=rom)

    map_order = manifest["constants"]["mapOrder"]
    dimensions = manifest["constants"]["maps"]
    metadata = manifest["maps"]
    tilesets = manifest["constants"]["tilesetOrder"]
    sprites = manifest["constants"]["spriteOrder"]
    movement_names = {0xFE: "WALK", 0xFF: "STAY"}
    range_names = {
        0x00: "ANY_DIR",
        0x01: "UP_DOWN",
        0x02: "LEFT_RIGHT",
        0x10: "BOULDER_MOVEMENT_BYTE_2",
        0xD0: "DOWN",
        0xD1: "UP",
        0xD2: "LEFT",
        0xD3: "RIGHT",
        0xFF: "NONE",
    }
    directions = (
        ("north", 0x08),
        ("south", 0x04),
        ("west", 0x02),
        ("east", 0x01),
    )

    out = {}
    for const_name, spec in metadata.items():
        dims = dimensions[const_name]
        label = spec["label"]
        header = _symbol(symbols, label + "_h")
        address = header.address
        tileset_id = rom.byte(header.bank, address)
        height = rom.byte(header.bank, address + 1)
        width = rom.byte(header.bank, address + 2)
        if (width, height) != (dims["width"], dims["height"]):
            raise ValueError(
                f"{const_name}: ROM dimensions {width}x{height} do not match "
                f"manifest {dims['width']}x{dims['height']}")
        if tileset_id >= len(tilesets):
            raise ValueError(f"{const_name}: unknown tileset id {tileset_id}")
        block_pointer = rom.word(header.bank, address + 3)
        connection_flags = rom.byte(header.bank, address + 9)

        connections = {}
        for direction, bit in directions:
            if not connection_flags & bit:
                continue
            target_id = rom.byte(header.bank, address)
            y_offset = _signed_byte(rom.byte(header.bank, address + 7))
            x_offset = _signed_byte(rom.byte(header.bank, address + 8))
            encoded_offset = x_offset if direction in ("north", "south") \
                else y_offset
            if encoded_offset % 2:
                raise ValueError(
                    f"{const_name}: odd {direction} connection offset")
            connections[direction] = {
                "map": _map_id(map_order, target_id),
                "offset": -encoded_offset // 2,
            }
            address += 11
        if connection_flags & ~0x0F:
            raise ValueError(
                f"{const_name}: unknown connection flags ${connection_flags:02X}")
        object_pointer = rom.word(header.bank, address)

        object_address = object_pointer
        border_block = rom.byte(header.bank, object_address)
        object_address += 1

        warp_count = rom.byte(header.bank, object_address)
        object_address += 1
        warps = []
        for _ in range(warp_count):
            y, x, dest_warp, dest_map = rom.bytes(
                header.bank, object_address, 4)
            warps.append({
                "x": x,
                "y": y,
                "destMap": _map_id(map_order, dest_map),
                "destWarp": dest_warp + 1,
            })
            object_address += 4

        sign_count = rom.byte(header.bank, object_address)
        object_address += 1
        if sign_count != len(spec["signTexts"]):
            raise ValueError(
                f"{const_name}: ROM has {sign_count} signs, metadata has "
                f"{len(spec['signTexts'])}")
        signs = []
        for sign_text in spec["signTexts"]:
            y, x, _text_id = rom.bytes(header.bank, object_address, 3)
            signs.append({"x": x, "y": y, "text": sign_text})
            object_address += 3

        object_count = rom.byte(header.bank, object_address)
        object_address += 1
        if object_count != len(spec["objects"]):
            raise ValueError(
                f"{const_name}: ROM has {object_count} objects, metadata has "
                f"{len(spec['objects'])}")
        objects = []
        for index, object_spec in enumerate(spec["objects"], start=1):
            sprite_id, y, x, movement_id, range_id, text_id = rom.bytes(
                header.bank, object_address, 6)
            if not 1 <= sprite_id <= len(sprites):
                raise ValueError(
                    f"{const_name} object {index}: unknown sprite {sprite_id}")
            if movement_id not in movement_names or range_id not in range_names:
                raise ValueError(
                    f"{const_name} object {index}: unknown movement encoding")
            obj = {
                "index": index,
                "x": x - 4,
                "y": y - 4,
                "sprite": sprites[sprite_id - 1],
                "movement": movement_names[movement_id],
                "range": range_names[range_id],
                "text": object_spec["text"],
            }
            object_address += 6

            if text_id & 0x80:
                if "item" not in object_spec:
                    raise ValueError(
                        f"{const_name} object {index}: unexpected item payload")
                obj["item"] = object_spec["item"]
                object_address += 1
            elif text_id & 0x40:
                extra, level_or_party = rom.bytes(
                    header.bank, object_address, 2)
                object_address += 2
                if "trainerClass" in object_spec:
                    obj["trainerClass"] = object_spec["trainerClass"]
                    party = object_spec.get("trainerParty")
                    obj["trainerParty"] = (
                        party if isinstance(party, str) else level_or_party)
                elif "pokemon" in object_spec:
                    obj["pokemon"] = object_spec["pokemon"]
                    obj["level"] = level_or_party
                else:
                    raise ValueError(
                        f"{const_name} object {index}: unexpected trainer "
                        "or static Pokemon payload")
                _ = extra
            elif any(key in object_spec for key in (
                    "item", "trainerClass", "pokemon")):
                raise ValueError(
                    f"{const_name} object {index}: missing extra payload")

            for key in ("name", "hidden"):
                if key in object_spec:
                    obj[key] = object_spec[key]
            objects.append(obj)

        expected_blocks = width * height
        block_length = spec["blockLength"]
        if block_length > expected_blocks:
            raise ValueError(
                f"{const_name}: block payload is longer than map dimensions")
        blocks = list(rom.bytes(
            header.bank, block_pointer, block_length))
        blocks.extend([border_block] * (expected_blocks - block_length))

        out[const_name] = {
            "id": const_name,
            "label": label,
            "index": dims["index"],
            "source": f"ROM:{header.bank:02X}:{header.address:04X}",
            "tileset": tilesets[tileset_id],
            "width": width,
            "height": height,
            "blocks": blocks,
            "borderBlock": border_block,
            "connections": connections,
            "warps": warps,
            "signs": signs,
            "objects": objects,
        }

    util.write_lua(
        os.path.join(out_dir, "maps.lua"), out,
        header="Source: canonical Pokemon Red ROM (map headers, block maps,\n"
               "connections, warps, signs, and object events)")
    return out


def _animation_flags(rom, symbols, count):
    table = _symbol(symbols, "AttackAnimationPointers")
    flags = []
    for index in range(count):
        address = rom.word(table.bank, table.address + index * 2)
        shake = False
        flash = False
        for _ in range(256):
            first = rom.byte(table.bank, address)
            if first == 0xFF:
                break
            if first >= 0xD8:
                shake = shake or first == 0xFB
                flash = flash or first in (0xF8, 0xFE)
                address += 2
            else:
                address += 3
        else:
            raise ValueError(f"unterminated move animation {index + 1}")
        flags.append((shake, flash))
    return flags


def _is_gen2_stub_manifest(manifest):
    return manifest.get("stub") and manifest.get("generation") == 2


def _display_name_from_id(value):
    return value.replace("_", " ").title()


# Standard Gen2 text encoding (Gold/Silver/Crystal)
_GEN2_CHARMAP = {}
for _i in range(26):
    _GEN2_CHARMAP[0x80 + _i] = chr(ord("A") + _i)
    _GEN2_CHARMAP[0xA0 + _i] = chr(ord("a") + _i)
for _i in range(10):
    _GEN2_CHARMAP[0xF6 + _i] = str(_i)
_GEN2_CHARMAP.update({
    0x54: "POK\xe9",  # combined POKé glyph used in item names
    0x7F: " ", 0xBA: "\xe9", 0xBB: "\u2019d", 0xBC: "\u2019l",
    0xBD: "\u2019s", 0xBE: "\u2019t", 0xBF: "\u2019v",
    0xE0: "'", 0xE3: "-", 0xE8: ".", 0xEB: "!", 0xEF: ",",
    0xF2: "?", 0xF3: "/", 0xF4: ",", 0xF5: ".",
})


def _gen2_decode_string(data, max_len=14):
    out = []
    for b in data[:max_len]:
        if b == 0x50:
            break
        c = _GEN2_CHARMAP.get(b, "")
        if c:
            out.append(c)
    s = "".join(out).strip()
    return s if s else None


def _gen2_read_var_names(rom, sym, count):
    """Read Gen2 variable-length string table; returns {1-based-index: name}."""
    if rom is None or sym is None:
        return {}
    names = {}
    bank = sym.bank
    addr = sym.address
    for i in range(1, count + 1):
        try:
            chunk = list(rom.bytes(bank, addr, 16))
        except Exception:
            break
        end = next((j for j, b in enumerate(chunk) if b == 0x50), len(chunk))
        name = _gen2_decode_string(chunk[:end], max_len=end)
        if name:
            names[i] = name
        addr += end + 1
        if addr >= 0x8000:          # handle bank boundary
            bank += 1
            addr -= 0x4000
    return names


def _gen2_read_fixed_names(rom, sym, count, entry_size=10):
    """Read Gen2 fixed-size name table (e.g. Pokemon names)."""
    if rom is None or sym is None:
        return {}
    names = {}
    for i in range(1, count + 1):
        try:
            raw = list(rom.bytes(sym.bank, sym.address + (i - 1) * entry_size, entry_size))
        except Exception:
            break
        name = _gen2_decode_string(raw, entry_size)
        if name:
            names[i] = name
    return names


# Maps ROM sprite index (1-based from OverworldSprites at 05:47de) to SPRITE_ constant names.
_GEN2_SPRITE_INDEX_TO_NAME = {
    1: "SPRITE_RED",           2: "SPRITE_RED_BIKE",      3: "SPRITE_GAMEBOY_KID",
    4: "SPRITE_RIVAL",         5: "SPRITE_OAK",           6: "SPRITE_RED_KANTO",
    7: "SPRITE_BLUE",          8: "SPRITE_BILL",          9: "SPRITE_ELDER",
   10: "SPRITE_JANINE",       11: "SPRITE_KURT",         12: "SPRITE_MOM",
   13: "SPRITE_BLAINE",       14: "SPRITE_REDS_MOM",     15: "SPRITE_DAISY",
   16: "SPRITE_ELM",          17: "SPRITE_WILL",         18: "SPRITE_FALKNER",
   19: "SPRITE_WHITNEY",      20: "SPRITE_BUGSY",        21: "SPRITE_MORTY",
   22: "SPRITE_CHUCK",        23: "SPRITE_JASMINE",      24: "SPRITE_PRYCE",
   25: "SPRITE_CLAIR",        26: "SPRITE_BROCK",        27: "SPRITE_KAREN",
   28: "SPRITE_BRUNO",        29: "SPRITE_MISTY",        30: "SPRITE_LANCE",
   31: "SPRITE_SURGE",        32: "SPRITE_ERIKA",        33: "SPRITE_KOGA",
   34: "SPRITE_SABRINA",      35: "SPRITE_COOLTRAINER_M", 36: "SPRITE_COOLTRAINER_F",
   37: "SPRITE_BUG_CATCHER",  38: "SPRITE_TWIN",         39: "SPRITE_YOUNGSTER",
   40: "SPRITE_LASS",         41: "SPRITE_TEACHER",      42: "SPRITE_BEAUTY",
   43: "SPRITE_SUPER_NERD",   44: "SPRITE_ROCKER",       45: "SPRITE_POKEFAN_M",
   46: "SPRITE_POKEFAN_F",    47: "SPRITE_GRAMPS",       48: "SPRITE_GRANNY",
   49: "SPRITE_SWIMMER_M",    50: "SPRITE_SWIMMER_F",    51: "SPRITE_SNORLAX",
   52: "SPRITE_SURFING_PIKACHU", 53: "SPRITE_ROCKET",    54: "SPRITE_ROCKET_F",
   55: "SPRITE_NURSE",        56: "SPRITE_RECEPTIONIST", 57: "SPRITE_CLERK",
   58: "SPRITE_FISHER",       59: "SPRITE_FISHING_GURU",
}

# -------------------------------------------------------------------------
# Gen2 GBC palette extraction
# -------------------------------------------------------------------------

# TilesetBGPalette at ROM bank 02, address 0x775e.
# Layout: 6 environment sets × 7 palettes × 4 BGR555 colors × 2 bytes = 56 bytes/set.
_GEN2_BG_PALETTE_BANK = 2
_GEN2_BG_PALETTE_ADDR = 0x775e
_GEN2_PALETTES_PER_SET = 7
_GEN2_COLORS_PER_PALETTE = 4
_GEN2_BYTES_PER_PALETTE_SET = _GEN2_PALETTES_PER_SET * _GEN2_COLORS_PER_PALETTE * 2  # 56

# Which of the 6 environment palette sets each tileset family uses.
_GEN2_OUTDOOR_FAMILIES = {"JOHTO", "KANTO", "JOHTOMODERN", "PLATEAU", "PARK"}
_GEN2_CAVE_FAMILIES = {"CAVERN", "RUIN", "DUNGEON", "WHIRLPOOL", "ICEROOM", "FACILITY"}


def _gen2_palette_set_index(tileset_id):
    family = tileset_id.removeprefix("Tileset").upper()
    if family in _GEN2_OUTDOOR_FAMILIES:
        return 0   # outdoor day (grass=green, water=blue, path=tan)
    if family in _GEN2_CAVE_FAMILIES:
        return 2   # cave/dark (purple tones)
    return 4       # indoor (warm beige tones)


def _gen2_read_palette_set(rom, set_idx):
    """Returns list of _GEN2_PALETTES_PER_SET palettes, each a list of 4 [r,g,b]."""
    bank = _GEN2_BG_PALETTE_BANK
    addr = _GEN2_BG_PALETTE_ADDR + set_idx * _GEN2_BYTES_PER_PALETTE_SET
    raw = list(rom.bytes(bank, addr, _GEN2_BYTES_PER_PALETTE_SET))
    palettes = []
    for p in range(_GEN2_PALETTES_PER_SET):
        colors = []
        for c in range(_GEN2_COLORS_PER_PALETTE):
            lo = raw[p * _GEN2_COLORS_PER_PALETTE * 2 + c * 2]
            hi = raw[p * _GEN2_COLORS_PER_PALETTE * 2 + c * 2 + 1]
            val = lo | (hi << 8)
            r = ((val & 0x1F) * 255) // 31
            g = (((val >> 5) & 0x1F) * 255) // 31
            b = (((val >> 10) & 0x1F) * 255) // 31
            colors.append([r, g, b])
        palettes.append(colors)
    return palettes


def _gen2_read_palmap(rom, symbols, tileset_id):
    """Returns list of 96 palette indices (one per tile), or empty list."""
    sym = symbols.by_name.get(tileset_id + "PalMap")
    if not sym:
        return []
    try:
        raw = list(rom.bytes(sym.bank, sym.address, 48))
    except Exception:
        return []
    result = []
    for byte in raw:
        result.append(byte & 0xF)
        result.append((byte >> 4) & 0xF)
    return result


def _gen2_stub_map_events(manifest, rom):
    events = {}
    if rom is None:
        return events

    symbols = manifest.get("symbols") or {}
    maps_meta = manifest.get("maps") or {}
    sprite_order = manifest.get("constants", {}).get("spriteOrder") or []
    default_sprite = sprite_order[0] if sprite_order else "SPRITE_RED"

    for map_id, spec in maps_meta.items():
        if not isinstance(spec, dict):
            continue
        label = spec.get("label")
        if not label:
            continue
        location = symbols.get(label + "_MapEvents")
        if not location:
            continue

        warps = []
        signs = []
        objects = []
        bank = int(location[0])
        address = int(location[1])
        try:
            # poke{gold,silver} map event table:
            # db filler[2], warpCount + 5*count,
            # coordCount + 8*count, bgCount + 5*count,
            # objectCount + 13*count
            warp_count = rom.byte(bank, address + 2)
            cursor = address + 3
            for _ in range(warp_count):
                y, x, dest_warp, dest_group, dest_number = rom.bytes(
                    bank, cursor, 5)
                warps.append({
                    "x": x,
                    "y": y,
                    "destMap": f"MAP_G{dest_group:02X}_N{dest_number:02X}",
                    "destWarp": max(1, int(dest_warp)),
                })
                cursor += 5

            coord_count = rom.byte(bank, cursor)
            cursor += 1 + coord_count * 8

            bg_count = rom.byte(bank, cursor)
            cursor += 1
            for index_bg in range(bg_count):
                y, x, kind, ptr_lo, ptr_hi = rom.bytes(bank, cursor, 5)
                signs.append({
                    "x": x,
                    "y": y,
                    "text": f"TEXT_{map_id}_BG_{index_bg + 1:03d}",
                    "source":
                        f"ROM_BG_EVENT:{bank:02X}:{cursor:04X}:"
                        f"{kind:02X}:{ptr_hi:02X}{ptr_lo:02X}",
                })
                cursor += 5

            object_count = rom.byte(bank, cursor)
            cursor += 1
            for index_obj in range(object_count):
                row = rom.bytes(bank, cursor, 13)
                sprite_idx = int(row[0])
                sprite_name = _GEN2_SPRITE_INDEX_TO_NAME.get(
                    sprite_idx, default_sprite)
                y = int(row[1])
                x = int(row[2])
                objects.append({
                    "index": index_obj + 1,
                    "x": max(0, x - 4),
                    "y": max(0, y - 4),
                    "sprite": sprite_name,
                    "movement": "STAY",
                    "range": "ANY_DIR",
                    "text": f"TEXT_{map_id}_OBJ_{index_obj + 1:03d}",
                    "hidden": True,
                    "source": f"ROM_OBJECT_EVENT:{bank:02X}:{cursor:04X}",
                })
                cursor += 13
        except Exception:
            continue

        events[map_id] = {
            "warps": warps,
            "signs": signs,
            "objects": objects,
        }

    return events


def _gen2_tileset_rows(manifest):
    symbols = manifest.get("symbols") or {}
    rows = []
    for name, location in symbols.items():
        if not (name.startswith("Tileset") and name.endswith("Meta")):
            continue
        family = name[len("Tileset"):-len("Meta")]
        if not family or family.startswith("Unused"):
            continue
        rows.append((int(location[0]), int(location[1]), family, name))
    rows.sort()
    return rows


def _gen2_tileset_key(map_id, label):
    name = (map_id or label or "").upper()
    if any(token in name for token in (
            "PLAYERSHOUSE2F", "PLAYERS_HOUSE2_F", "PLAYERS_HOUSE2F")):
        return "PLAYERS_ROOM"
    if any(token in name for token in (
            "PLAYERS_HOUSE", "ELMS_LAB", "OAKS_LAB", "LAB")):
        return "LAB" if "LAB" in name else "PLAYERS_HOUSE"
    if any(token in name for token in (
            "POKECENTER", "MART", "GATE", "HOUSE", "MANSION", "CAFE",
            "TOWER", "Lighthouse".upper(), "TRAIN_STATION", "UNDERGROUND",
            "GAME_CORNER", "RADIO_TOWER", "RUINS_OF_ALPH", "ICE_PATH",
            "FACILITY", "PARK", "FOREST", "PORT", "CHAMPIONS_ROOM",
            "ELITE_FOUR_ROOM")):
        if "POKECENTER" in name:
            return "POKECENTER"
        if "MART" in name:
            return "MART"
        if "GATE" in name:
            return "GATE"
        if "MANSION" in name:
            return "MANSION"
        if "CAFE" in name:
            return "HOUSE"
        if "TRAIN_STATION" in name or "MAGNET_TRAIN" in name:
            return "TRAIN_STATION"
        if "UNDERGROUND" in name:
            return "UNDERGROUND"
        if "GAME_CORNER" in name:
            return "GAME_CORNER"
        if "RADIO_TOWER" in name:
            return "RADIO_TOWER"
        if "RUINS_OF_ALPH" in name:
            return "RUINS_OF_ALPH"
        if "ICE_PATH" in name:
            return "ICE_PATH"
        if "FACILITY" in name:
            return "FACILITY"
        if "PARK" in name:
            return "PARK"
        if "FOREST" in name:
            return "FOREST"
        if "PORT" in name:
            return "PORT"
        if "CHAMPIONS_ROOM" in name:
            return "CHAMPIONS_ROOM"
        if "ELITE_FOUR_ROOM" in name:
            return "ELITE_FOUR_ROOM"
        if "TOWER" in name:
            return "TOWER"
        if "HOUSE" in name:
            return "HOUSE"
    if any(token in name for token in (
            "PALLET", "VIRIDIAN", "PEWTER", "CERULEAN", "VERMILION",
            "LAVENDER", "FUCHSIA", "SAFFRON", "CELADON", "CINNABAR",
            "INDIGO", "ROCKET", "BILLS", "COPYCATS", "POWER_PLANT",
            "POKEMON_TOWER", "VICTORY_ROAD", "SAFARI", "ROUTE1",
            "ROUTE2", "ROUTE3", "ROUTE4", "ROUTE5", "ROUTE6", "ROUTE7",
            "ROUTE8", "ROUTE9", "ROUTE10", "ROUTE11", "ROUTE12",
            "ROUTE13", "ROUTE14", "ROUTE15", "ROUTE16", "ROUTE17",
            "ROUTE18", "ROUTE19", "ROUTE20", "ROUTE21", "ROUTE22",
            "ROUTE23", "ROUTE24", "ROUTE25", "ROUTE26", "ROUTE27",
            "ROUTE28")):
        return "KANTO"
    return "JOHTO"


_GEN2_TILESET_IDS = {
    "JOHTO": "TilesetJohto",
    "KANTO": "TilesetKanto",
    "HOUSE": "TilesetHouse",
    "LAB": "TilesetLab",
    "MART": "TilesetMart",
    "GATE": "TilesetGate",
    "POKECENTER": "TilesetPokecenter",
    "PLAYERS_HOUSE": "HOUSE",
    "PLAYERS_ROOM": "TilesetPlayersRoom",
    "PORT": "TilesetPort",
    "TOWER": "TilesetTower",
    "LIGHTHOUSE": "TilesetLighthouse",
    "FOREST": "TilesetForest",
    "CAVE": "TilesetCave",
    "DARK_CAVE": "TilesetDarkCave",
    "GAME_CORNER": "TilesetGameCorner",
    "TRAIN_STATION": "TilesetTrainStation",
    "RADIO_TOWER": "TilesetRadioTower",
    "RUINS_OF_ALPH": "TilesetRuinsOfAlph",
    "PARK": "TilesetPark",
    "FACILITY": "TilesetFacility",
    "MANSION": "TilesetMansion",
    "UNDERGROUND": "TilesetUnderground",
    "ICE_PATH": "TilesetIcePath",
    "CHAMPIONS_ROOM": "TilesetChampionsRoom",
}


_GEN2_MAP_DIMENSIONS = {
    "PLAYERS_HOUSE1_F": (5, 4),
    "PLAYERS_HOUSE2_F": (4, 3),
    "PLAYERS_NEIGHBORS_HOUSE": (4, 4),
    "ELMS_LAB": (5, 6),
}


def _gen2_tileset_id(map_id, label):
    return _GEN2_TILESET_IDS.get(
        _gen2_tileset_key(map_id, label), "TilesetJohto")


def _infer_tileset_dimensions(stored_length):
    for width in (128, 64, 32, 16):
        if stored_length % (width // 4) == 0:
            height = stored_length * 4 // width
            if height > 0 and height % 8 == 0:
                return width, height
    return 128, max(8, stored_length * 4 // 128)


def _normalize_banked_address(bank, address):
    if bank != 0 and address < 0x4000:
        return address + 0x4000
    return address


def _bank_for_address(address, fallback_bank=0):
    return fallback_bank if address < 0x4000 else 1


def _extract_moves_from_stub_manifest(manifest, out_dir, rom=None, symbols=None):
    order = manifest["constants"]["moveOrder"]
    effects = manifest.get("moveEffects") or []
    type_names = sorted(
        manifest["constants"]["types"].keys(),
        key=lambda n: int(manifest["constants"]["types"][n]))
    fallback_type = type_names[0] if type_names else "NORMAL"

    # `rom` is accepted but deliberately unread: this file is committed, so it
    # must stay free of cart content.  RomExtractorGen2:extractMoves rebuilds
    # every field off the cart at import.
    out = {}
    for index, move_id in enumerate(order, start=1):
        effect = effects[index] if index < len(effects) else "UNUSED"
        out[move_id] = {
            "id": move_id,
            "index": index,
            "name": _display_name_from_id(move_id),
            "source": f"MANIFEST:moveOrder[{index}]",
            "effect": effect,
            "power": 0,
            "type": fallback_type,
            "accuracy": 100,
            "pp": 0,
            "anim": {"sound": "SFX_00", "pitch": 0, "tempo": 0},
        }

    util.write_lua(
        os.path.join(out_dir, "moves.lua"), out,
        header="Source: Gen2 Phase 2B stub manifest (moveOrder placeholders)")
    return out


def _extract_maps_from_stub_manifest(manifest, out_dir, rom=None):
    order = manifest.get("constants", {}).get("mapOrder", [])
    dims = manifest.get("constants", {}).get("maps", {})
    metadata = manifest.get("maps", {})
    symbols = manifest.get("symbols") or {}
    # Passing None keeps warp/sign/object coordinates -- cart content -- out of
    # this committed file; RomExtractorGen2:extractMaps reads them at import.
    events_by_map = _gen2_stub_map_events(manifest, None)

    out = {}
    for index, map_id in enumerate(order, start=1):
        dims_info = dims.get(map_id, {})
        spec = metadata.get(map_id, {}) if isinstance(metadata, dict) else {}
        label = spec.get("label", map_id)
        width = int(dims_info.get("width", 1))
        height = int(dims_info.get("height", 1))
        # Dimensions and the block grid are cart content, so they stay at the
        # manifest placeholder; RomExtractorGen2:extractMaps reads the real map
        # attributes and tilemap off the cart at import.
        border_block = 0
        blocks = [0] * max(1, width * height)

        if (width, height) == (1, 1):
            override = _GEN2_MAP_DIMENSIONS.get(map_id)
            if override:
                width, height = override

        block_count = max(1, width * height)
        if len(blocks) != block_count:
            blocks = [0] * block_count
        event_spec = events_by_map.get(map_id, {})
        warps = event_spec.get("warps", [])
        signs = event_spec.get("signs", [])
        objects = event_spec.get("objects", [])
        tileset = spec.get("tileset")
        if not isinstance(tileset, str) or not tileset:
            tileset = _gen2_tileset_id(map_id, label)

        out[map_id] = {
            "id": map_id,
            "index": index,
            "label": label,
            "width": width,
            "height": height,
            "source": spec.get("source", f"MANIFEST:mapOrder[{index}]"),
            "tileset": tileset,
            "blocks": blocks,
            "borderBlock": border_block,
            "connections": {},
            "warps": warps,
            "signs": signs,
            "objects": objects,
        }

    util.write_lua(
        os.path.join(out_dir, "maps.lua"), out,
        header="Source: Gen2 Phase 2B stub manifest (map scaffold placeholders)")
    return out


def extract_moves(rom, symbols, manifest, out_dir):
    if _is_gen2_stub_manifest(manifest):
        return _extract_moves_from_stub_manifest(manifest, out_dir, rom=rom, symbols=symbols)

    order = manifest["constants"]["moveOrder"]
    type_by_id = {
        int(value): name
        for name, value in manifest["constants"]["types"].items()
    }
    effects = manifest["moveEffects"]
    charmap = manifest["charmap"]
    sfx_keys = manifest["sfxKeys"]

    moves = _symbol(symbols, "Moves")
    names = _symbol(symbols, "MoveNames")
    sounds = _symbol(symbols, "MoveSoundTable")
    flags = _animation_flags(rom, symbols, len(order))

    decoded_names = []
    address = names.address
    for _ in order:
        value, consumed = read_string(
            rom, names.bank, address, charmap, max_length=32)
        decoded_names.append(value)
        address += consumed

    out = {}
    for index, move_id in enumerate(order):
        row = rom.bytes(moves.bank, moves.address + index * 6, 6)
        if row[0] != index + 1:
            raise ValueError(
                f"Moves row {index + 1} stores animation id {row[0]}")
        effect = effects[row[1]] if row[1] < len(effects) else f"EFFECT_{row[1]:02X}"
        type_name = type_by_id.get(row[3], f"TYPE_{row[3]:02X}")
        sound_id, pitch, tempo = rom.bytes(
            sounds.bank, sounds.address + index * 3, 3)
        anim = {
            "sound": sfx_keys.get(str(sound_id), f"SFX_{sound_id:02X}"),
            "pitch": pitch,
            "tempo": tempo,
        }
        shake, flash = flags[index]
        if shake:
            anim["shake"] = True
        if flash:
            anim["flash"] = True
        out[move_id] = {
            "id": move_id,
            "index": index + 1,
            "name": decoded_names[index],
            "source": f"ROM:Moves[{index + 1}]",
            "effect": effect,
            "power": row[2],
            "type": type_name,
            "accuracy": round(row[4] * 100 / 255),
            "pp": row[5],
            "anim": anim,
        }

    util.write_lua(
        os.path.join(out_dir, "moves.lua"), out,
        header="Source: canonical Pokemon Red ROM (Moves, MoveNames,\n"
               "MoveSoundTable, AttackAnimationPointers)")
    return out


def extract_battle_anims(
        rom, symbols, manifest, out_dir, assets_dir):
    metadata = manifest["battleAnimations"]
    move_order = manifest["constants"]["moveOrder"]
    if len(move_order) != metadata["moveCount"]:
        raise ValueError("battle animation move count does not match constants")

    coords_symbol = _symbol(symbols, "FrameBlockBaseCoords")
    base_coords = {}
    for index in range(metadata["baseCoordCount"]):
        y, x = rom.bytes(
            coords_symbol.bank, coords_symbol.address + index * 2, 2)
        base_coords[index] = {"y": y, "x": x}

    blocks_symbol = _symbol(symbols, "FrameBlockPointers")
    frame_blocks = {}
    for index in range(metadata["frameBlockCount"]):
        address = rom.word(
            blocks_symbol.bank, blocks_symbol.address + index * 2)
        count = rom.byte(blocks_symbol.bank, address)
        address += 1
        entries = []
        for _ in range(count):
            y, x, tile, attrs = rom.bytes(
                blocks_symbol.bank, address, 4)
            entry = {
                "y": y,
                "x": x,
                "tile": tile,
                "xflip": bool(attrs & 0x20),
                "yflip": bool(attrs & 0x40),
            }
            if attrs & 0x80:
                entry["prio"] = True
            if attrs & 0x10:
                entry["pal1"] = True
            entries.append(entry)
            address += 4
        frame_blocks[index] = entries

    subanim_symbol = _symbol(symbols, "SubanimationPointers")
    subanims = {}
    type_names = metadata["subanimTypes"]
    for index in range(metadata["subanimCount"]):
        address = rom.word(
            subanim_symbol.bank, subanim_symbol.address + index * 2)
        packed = rom.byte(subanim_symbol.bank, address)
        type_id, count = packed >> 5, packed & 0x1F
        if type_id >= len(type_names):
            raise ValueError(
                f"subanimation {index} has unknown type {type_id}")
        address += 1
        entries = []
        for _ in range(count):
            block, coord, mode = rom.bytes(
                subanim_symbol.bank, address, 3)
            if block >= metadata["frameBlockCount"]:
                raise ValueError(
                    f"subanimation {index} has invalid frame block {block}")
            if coord >= metadata["baseCoordCount"]:
                raise ValueError(
                    f"subanimation {index} has invalid base coord {coord}")
            entries.append({
                "block": block, "coord": coord, "mode": mode})
            address += 3
        subanims[index] = {
            "type": type_names[type_id],
            "blocks": entries,
        }

    tiles_table = _symbol(symbols, "MoveAnimationTilesPointers")
    tile_rows = []
    tile_specs = metadata["tilesheets"]
    if len(tile_specs) != 3:
        raise ValueError("expected three battle animation tilesheets")
    for index, spec in enumerate(tile_specs):
        count, low, high, padding = rom.bytes(
            tiles_table.bank, tiles_table.address + index * 4, 4)
        if padding != 0xFF:
            raise ValueError(
                f"battle animation tilesheet {index} has invalid padding")
        pointer = low | high << 8
        expected = _symbol(symbols, f"MoveAnimationTiles{index}")
        if expected.bank != tiles_table.bank or expected.address != pointer:
            raise ValueError(
                f"battle animation tilesheet {index} pointer differs")
        tile_rows.append({
            "count": count, "pointer": pointer, "spec": spec})

    image_payloads = {}
    for row in tile_rows:
        path = row["spec"]["path"]
        existing = image_payloads.get(path)
        if existing and existing["pointer"] != row["pointer"]:
            raise ValueError(
                f"shared battle animation atlas {path} has two pointers")
        if not existing:
            existing = {"pointer": row["pointer"], "tiles": 0,
                        "spec": row["spec"]}
            image_payloads[path] = existing
        existing["tiles"] = max(existing["tiles"], row["count"])

    for path, payload in image_payloads.items():
        spec = payload["spec"]
        byte_length = spec["width"] * spec["height"] // 4
        stored_length = payload["tiles"] * 16
        if stored_length > byte_length:
            raise ValueError(f"{path}: battle animation atlas is too large")
        raw = rom.bytes(
            tiles_table.bank, payload["pointer"], stored_length)
        raw += bytes(byte_length - stored_length)
        prefix = "assets/generated/"
        if not path.startswith(prefix):
            raise ValueError(f"invalid generated asset path {path!r}")
        _write_2bpp_png(
            raw, spec["width"], spec["height"],
            os.path.join(assets_dir, path[len(prefix):]),
            transparent_color0=True)

    tilesheets = {}
    for index, row in enumerate(tile_rows):
        spec = row["spec"]
        tilesheets[index] = {
            "path": spec["path"],
            "width": spec["width"],
            "height": spec["height"],
            "tiles": row["count"],
            "source": spec["source"],
        }

    move_names = move_order + metadata["miscAnimations"]
    pointer_table = _symbol(symbols, "AttackAnimationPointers")
    first_special = metadata["firstSpecialEffect"]
    special_effects = metadata["specialEffects"]
    move_anims = {}
    for index, name in enumerate(move_names):
        address = rom.word(
            pointer_table.bank, pointer_table.address + index * 2)
        sequence = []
        for _ in range(256):
            first = rom.byte(pointer_table.bank, address)
            if first == 0xFF:
                break
            sound = rom.byte(pointer_table.bank, address + 1)
            if first >= first_special:
                effect = special_effects.get(str(first))
                if not effect:
                    raise ValueError(
                        f"{name}: unknown special effect ${first:02X}")
                row = {"effect": effect}
                address += 2
            else:
                subanim = rom.byte(pointer_table.bank, address + 2)
                delay = first & 0x3F
                tileset = first >> 6
                if not delay:
                    raise ValueError(f"{name}: zero animation delay")
                if subanim >= metadata["subanimCount"]:
                    raise ValueError(
                        f"{name}: unknown subanimation {subanim}")
                if tileset not in tilesheets:
                    raise ValueError(
                        f"{name}: unknown animation tileset {tileset}")
                row = {
                    "subanim": subanim,
                    "tileset": tileset,
                    "delay": delay,
                }
                address += 3
            if sound != 0xFF:
                if sound >= len(move_order):
                    raise ValueError(
                        f"{name}: unknown animation sound {sound}")
                row["sound"] = move_order[sound]
            sequence.append(row)
        else:
            raise ValueError(f"{name}: unterminated battle animation")
        move_anims[name] = {
            "source": f"ROM:AttackAnimationPointers[{index}]",
            "seq": sequence,
        }

    for name, anim in move_anims.items():
        for row in anim["seq"]:
            if "subanim" not in row:
                continue
            sheet = tilesheets[row["tileset"]]
            for block_ref in subanims[row["subanim"]]["blocks"]:
                for tile in frame_blocks[block_ref["block"]]:
                    if tile["tile"] >= sheet["tiles"]:
                        raise ValueError(
                            f"{name}: tile {tile['tile']} is out of range "
                            f"for tileset {row['tileset']}")

    out = {
        "tilesheets": tilesheets,
        "baseCoords": base_coords,
        "frameBlocks": frame_blocks,
        "subanims": subanims,
        "moveAnims": move_anims,
    }
    util.write_lua(
        os.path.join(out_dir, "battle_anims.lua"), out,
        header="Source: canonical Pokemon Red ROM battle animation tables,\n"
               "frame geometry, coordinates, and OAM tile graphics")
    return out


def _nybbles(raw, count):
    out = []
    for value in raw:
        out.extend((value >> 4, value & 0x0F))
    return out[:count]


def extract_items(rom, symbols, manifest, out_dir):
    if _is_gen2_stub_manifest(manifest):
        # Names and prices stay placeholders here; this file is committed and
        # RomExtractorGen2 reads ItemNames/ItemPrices off the cart at import.
        order = manifest["items"]
        out = {}
        for index, item_id in enumerate(order, start=1):
            out[item_id] = {
                "id": item_id,
                "index": index,
                "name": _display_name_from_id(item_id),
                "price": 0,
                "source": f"MANIFEST:items[{index}]",
            }
        util.write_lua(
            os.path.join(out_dir, "items.lua"), out,
            header="Source: Gen2 Phase 2B stub manifest (items placeholders)")
        return out

    order = manifest["items"]
    charmap = manifest["charmap"]
    names = _symbol(symbols, "ItemNames")
    prices = _symbol(symbols, "ItemPrices")
    key_flags = _symbol(symbols, "KeyItemFlags")
    tm_prices = _symbol(symbols, "TechnicalMachinePrices")

    decoded_names = []
    address = names.address
    for _ in order:
        value, consumed = read_string(
            rom, names.bank, address, charmap, max_length=32)
        decoded_names.append(value)
        address += consumed

    num_items = manifest["numItems"]
    flags = rom.bytes(key_flags.bank, key_flags.address, (num_items + 7) // 8)
    out = {}
    for index, item_id in enumerate(order):
        entry = {
            "id": item_id,
            "index": index + 1,
            "name": decoded_names[index],
            "price": bcd(rom.bytes(
                prices.bank, prices.address + index * 3, 3)),
            "source": f"ROM:ItemNames[{index + 1}]",
        }
        if index < num_items and flags[index // 8] & (1 << (index % 8)):
            entry["keyItem"] = True
        out[item_id] = entry

    for number, move in enumerate(manifest["hms"], start=1):
        item_id = "HM_" + move
        out[item_id] = {
            "id": item_id,
            "name": f"HM{number:02d}",
            "price": 0,
            "machine": {"kind": "HM", "number": number, "move": move},
            "source": "ROM metadata manifest (HM mapping)",
        }

    tms = manifest["tms"]
    packed = rom.bytes(
        tm_prices.bank, tm_prices.address, (len(tms) + 1) // 2)
    prices_by_tm = _nybbles(packed, len(tms))
    for number, move in enumerate(tms, start=1):
        item_id = "TM_" + move
        out[item_id] = {
            "id": item_id,
            "name": f"TM{number:02d}",
            "price": prices_by_tm[number - 1] * 1000,
            "machine": {"kind": "TM", "number": number, "move": move},
            "source": f"ROM:TechnicalMachinePrices[{number}]",
        }

    util.write_lua(
        os.path.join(out_dir, "items.lua"), out,
        header="Source: canonical Pokemon Red ROM (ItemNames, ItemPrices,\n"
               "KeyItemFlags, TechnicalMachinePrices)")
    return out


def extract_type_chart(rom, symbols, manifest, out_dir):
    type_by_id = {
        int(value): name
        for name, value in manifest["constants"]["types"].items()
    }
    effects = _symbol(symbols, "TypeEffects")
    address = effects.address
    matchups = []
    while rom.byte(effects.bank, address) != 0xFF:
        attacker, defender, multiplier = rom.bytes(
            effects.bank, address, 3)
        matchups.append({
            "attacker": type_by_id.get(attacker, f"TYPE_{attacker:02X}"),
            "defender": type_by_id.get(defender, f"TYPE_{defender:02X}"),
            "multiplier": multiplier,
        })
        address += 3

    names = []
    seen = set()
    for label in manifest["typeNameLabels"]:
        symbol = _symbol(symbols, label)
        if (symbol.bank, symbol.address) in seen:
            continue
        seen.add((symbol.bank, symbol.address))
        name, _ = read_string(
            rom, symbol.bank, symbol.address, manifest["charmap"],
            max_length=16)
        names.append(name)

    data = {
        "source": "ROM:TypeEffects + TypeNames",
        "matchups": matchups,
        "names": names,
    }
    util.write_lua(
        os.path.join(out_dir, "type_chart.lua"), data,
        header="Source: canonical Pokemon Red ROM; multipliers are x10")
    return data


def _scale5(value):
    return round(value * 255 / 31)


def extract_palettes(rom, symbols, manifest, out_dir):
    order = manifest["paletteOrder"]
    table = _symbol(symbols, "SuperPalettes")
    palettes = {}
    for index, name in enumerate(order):
        colors = []
        for color in range(4):
            value = rom.word(
                table.bank, table.address + index * 8 + color * 2)
            colors.append([
                _scale5(value & 0x1F),
                _scale5((value >> 5) & 0x1F),
                _scale5((value >> 10) & 0x1F),
            ])
        palettes[name] = colors

    mon_table = _symbol(symbols, "MonsterPalettes")
    mon_pals = {}
    for index, species in enumerate(manifest["dexOrder"], start=1):
        palette_id = rom.byte(mon_table.bank, mon_table.address + index)
        mon_pals[species] = order[palette_id]

    data = {
        "source": "ROM:SuperPalettes + MonsterPalettes",
        "palettes": palettes,
        "order": order,
        "pokemon": mon_pals,
    }
    if _has_symbol(symbols, "CGBBasePalettes"):
        cgb_table = _symbol(symbols, "CGBBasePalettes")
        cgb = {}
        for index, name in enumerate(order):
            colors = []
            for color in range(4):
                value = rom.word(
                    cgb_table.bank, cgb_table.address + index * 8 + color * 2)
                colors.append([
                    _scale5(value & 0x1F),
                    _scale5((value >> 5) & 0x1F),
                    _scale5((value >> 10) & 0x1F),
                ])
            cgb[name] = colors
        data["cgbBase"] = cgb
        data["source"] = data["source"] + " + CGBBasePalettes"
    util.write_lua(
        os.path.join(out_dir, "palettes.lua"), data,
        header="Source: canonical Gen-1 ROM; 4 RGB colors per palette")
    return data


def extract_icons(rom, symbols, manifest, out_dir, assets_dir):
    table = _symbol(symbols, "MonPartyData")
    count = len(manifest["dexOrder"])
    packed = rom.bytes(table.bank, table.address, (count + 1) // 2)
    values = _nybbles(packed, count)
    by_dex = [
        manifest["iconOrder"][value]
        if value < len(manifest["iconOrder"]) else f"ICON_{value:X}"
        for value in values
    ]
    icons = {
        "MON": "assets/generated/sprites/monster.png",
        "BALL": "assets/generated/sprites/poke_ball.png",
        "HELIX": "assets/generated/sprites/fossil.png",
        "FAIRY": "assets/generated/sprites/fairy.png",
        "BIRD": "assets/generated/sprites/bird.png",
        "WATER": "assets/generated/sprites/seel.png",
        "BUG": "assets/generated/icons/bug.png",
        "GRASS": "assets/generated/icons/plant.png",
        "SNAKE": "assets/generated/icons/snake.png",
        "QUADRUPED": "assets/generated/icons/quadruped.png",
    }
    icon_frames = {
        "bug": ("BugIconFrame1", "BugIconFrame2"),
        "plant": ("PlantIconFrame1", "PlantIconFrame2"),
        "snake": ("SnakeIconFrame1", "SnakeIconFrame2"),
        "quadruped": ("QuadrupedIconFrame1", "QuadrupedIconFrame2"),
    }
    for filename, labels in icon_frames.items():
        raw = bytearray()
        for label in labels:
            symbol = _symbol(symbols, label)
            raw.extend(rom.bytes(symbol.bank, symbol.address, 32))
        half = _decode_2bpp(bytes(raw), 8, 32, transparent_color0=True)
        image = Image.new("RGBA", (16, 32), (255, 255, 255, 0))
        for frame in range(2):
            crop = half.crop((0, frame * 16, 8, frame * 16 + 16))
            image.paste(crop, (0, frame * 16))
            image.paste(
                crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                (8, frame * 16))
        _save_png(
            image, os.path.join(assets_dir, "icons", filename + ".png"))

    data = {
        "source": "ROM:MonPartyData",
        "byDex": by_dex,
        "icons": icons,
    }
    util.write_lua(
        os.path.join(out_dir, "icons.lua"), data,
        header="Source: canonical Pokemon Red ROM (MonPartyData)")
    return data


def _species(manifest, value):
    order = manifest["constants"]["speciesOrder"]
    if not 1 <= value <= len(order):
        return f"SPECIES_{value:02X}"
    return order[value - 1]


def _item(manifest, value):
    order = manifest["items"]
    if not 1 <= value <= len(order):
        return f"ITEM_{value:02X}"
    return order[value - 1]


def _move(manifest, value):
    order = manifest["constants"]["moveOrder"]
    if value == 0:
        return None
    if not 1 <= value <= len(order):
        return f"MOVE_{value:02X}"
    return order[value - 1]


def _types_by_id(manifest):
    return {
        int(value): name
        for name, value in manifest["constants"]["types"].items()
    }


def _decode_evos_moves(rom, symbols, manifest, index):
    table = _symbol(symbols, "EvosMovesPointerTable")
    address = rom.word(table.bank, table.address + index * 2)
    evolutions = []
    while True:
        method = rom.byte(table.bank, address)
        address += 1
        if method == 0:
            break
        if method == 1:
            level, species = rom.bytes(table.bank, address, 2)
            address += 2
            evolutions.append({
                "method": "LEVEL",
                "level": level,
                "species": _species(manifest, species),
            })
        elif method == 2:
            item, level, species = rom.bytes(table.bank, address, 3)
            address += 3
            evolutions.append({
                "method": "ITEM",
                "item": _item(manifest, item),
                "level": level,
                "species": _species(manifest, species),
            })
        elif method == 3:
            level, species = rom.bytes(table.bank, address, 2)
            address += 2
            evolutions.append({
                "method": "TRADE",
                "level": level,
                "species": _species(manifest, species),
            })
        else:
            raise ValueError(
                f"unknown evolution method {method} for species index {index + 1}")

    learnset = []
    while True:
        level = rom.byte(table.bank, address)
        address += 1
        if level == 0:
            break
        move = rom.byte(table.bank, address)
        address += 1
        learnset.append({"level": level, "move": _move(manifest, move)})
    return evolutions, learnset


def _dex_entry(rom, symbols, manifest, index, species):
    table = _symbol(symbols, "PokedexEntryPointers")
    address = rom.word(table.bank, table.address + index * 2)
    kind, consumed = read_string(
        rom, table.bank, address, manifest["charmap"], max_length=32)
    address += consumed
    height_ft, height_in = rom.bytes(table.bank, address, 2)
    weight = rom.word(table.bank, address + 2)
    address += 4
    if rom.byte(table.bank, address) != 0x17:
        raise ValueError(
            f"dex entry {index + 1} has no TX_FAR command")
    text_address = rom.word(table.bank, address + 1)
    text_bank = rom.byte(table.bank, address + 3)
    text_label = manifest["dexEntryLabels"].get(species)
    if text_label is None:
        text_label = f"_DexEntry_{text_bank:02X}_{text_address:04X}"
    return {
        "kind": kind,
        "heightFt": height_ft,
        "heightIn": height_in,
        "weight": weight,
        "text": text_label,
    }


def extract_pokemon(rom, symbols, manifest, out_dir, assets_dir):
    species_order = manifest["constants"]["speciesOrder"]
    dex_order = manifest["dexOrder"]
    dex_by_species = {
        species: index for index, species in enumerate(dex_order, start=1)
    }
    type_by_id = _types_by_id(manifest)
    names = _symbol(symbols, "MonsterNames")
    base_stats = _symbol(symbols, "BaseStats")
    # Red/Blue keep Mew outside BaseStats at MewBaseStats; Yellow folds Mew
    # into BaseStats at dex 151 (pret/pokeyellow), so the symbol is optional.
    mew_stats = symbols.by_name.get("MewBaseStats")

    decoded_names = []
    for index in range(len(species_order)):
        raw = rom.bytes(names.bank, names.address + index * 10, 10)
        decoded_names.append(
            decode_text(raw, manifest["charmap"]))

    out = {}
    written_front = set()
    written_back = set()
    for index, species in enumerate(species_order):
        if species.startswith(
                ("MISSINGNO", "UNUSED", "FOSSIL_", "MON_GHOST")):
            continue
        dex = dex_by_species[species]
        if species == "MEW" and mew_stats is not None:
            row = rom.bytes(mew_stats.bank, mew_stats.address, 28)
        else:
            row = rom.bytes(
                base_stats.bank, base_stats.address + (dex - 1) * 28, 28)
        if row[0] != dex:
            raise ValueError(
                f"{species} base stats store dex number {row[0]}, expected {dex}")

        level1_moves = [
            _move(manifest, value) for value in row[15:19] if value
        ]
        tmhm = []
        for bit, move in enumerate(manifest["tmhmMoves"]):
            if row[20 + bit // 8] & (1 << (bit % 8)):
                tmhm.append(move)
        evolutions, learnset = _decode_evos_moves(
            rom, symbols, manifest, index)
        asset = manifest["pokemonAssets"][species]
        front = asset["front"]
        back = asset["back"]
        if front and front not in written_front:
            decoded_size = _write_compressed_pic(
                rom, symbols, asset["frontLabel"],
                os.path.join(
                    assets_dir, "battle", "front", front + ".png"))
            if decoded_size != row[10] >> 4:
                raise ValueError(
                    f"{species}: front picture size {decoded_size} does not "
                    f"match base stats {row[10] >> 4}")
            written_front.add(front)
        if back and back not in written_back:
            _write_compressed_pic(
                rom, symbols, asset["backLabel"],
                os.path.join(
                    assets_dir, "battle", "back", back + ".png"))
            written_back.add(back)
        out[species] = {
            "id": species,
            "index": index + 1,
            "dex": dex,
            "name": decoded_names[index],
            "source": f"ROM:BaseStats[{dex}]",
            "types": list(dict.fromkeys(
                type_by_id.get(value, f"TYPE_{value:02X}")
                for value in row[6:8])),
            "baseStats": {
                "hp": row[1],
                "attack": row[2],
                "defense": row[3],
                "speed": row[4],
                "special": row[5],
            },
            "catchRate": row[8],
            "baseExp": row[9],
            "level1Moves": level1_moves,
            "growthRate": manifest["growthRates"][row[19]],
            "tmhm": tmhm,
            "learnset": learnset,
            "evolutions": evolutions,
            "spriteFront": (
                f"assets/generated/battle/front/{front}.png"
                if front else None),
            "spriteBack": (
                f"assets/generated/battle/back/{back}.png"
                if back else None),
            "frontSize": row[10] >> 4,
            "dexEntry": _dex_entry(
                rom, symbols, manifest, index, species),
        }

    for label, filename in (
            ("FossilAerodactylPic", "fossilaerodactyl"),
            ("FossilKabutopsPic", "fossilkabutops"),
            ("GhostPic", "ghost")):
        _write_compressed_pic(
            rom, symbols, label,
            os.path.join(
                assets_dir, "battle", "front", filename + ".png"))
    for label, filename in (
            ("RedPicBack", "redb"),
            ("OldManPicBack", "oldmanb")):
        _write_compressed_pic(
            rom, symbols, label,
            os.path.join(assets_dir, "battle", filename + ".png"))

    balls = _symbol(symbols, "PokeballTileGraphics")
    _write_2bpp_png(
        rom.bytes(balls.bank, balls.address, 64), 32, 8,
        os.path.join(assets_dir, "battle", "balls.png"),
        transparent_color0=True)

    trainer_card = (
        ("TrainerInfoTextBoxTileGraphics", "trainer_info.png", 24, 24, False),
        ("GymLeaderFaceAndBadgeTileGraphics", "badges.png", 16, 256, True),
        ("BadgeNumbersTileGraphics", "badge_numbers.png", 16, 32, True),
        ("CircleTile", "circle_tile.png", 8, 8, True),
    )
    for label, filename, width, height, transparent in trainer_card:
        symbol = _symbol(symbols, label)
        length = width * height // 4
        _write_2bpp_png(
            rom.bytes(symbol.bank, symbol.address, length), width, height,
            os.path.join(assets_dir, "trainer_card", filename),
            transparent_color0=transparent)
    _write_compressed_pic(
        rom, symbols, "RedPicFront",
        os.path.join(assets_dir, "trainer_card", "red.png"))

    util.write_lua(
        os.path.join(out_dir, "pokemon.lua"), out,
        header="Source: canonical Pokemon Red ROM (BaseStats, MonsterNames,\n"
               "EvosMovesPointerTable, PokedexEntryPointers)")
    return out


def _trainer_parties(rom, bank, start, end, manifest):
    parties = []
    address = start
    while address < end:
        first = rom.byte(bank, address)
        address += 1
        party = []
        if first == 0xFF:
            while True:
                level = rom.byte(bank, address)
                address += 1
                if level == 0:
                    break
                species = rom.byte(bank, address)
                address += 1
                party.append({
                    "level": level,
                    "species": _species(manifest, species),
                })
        else:
            level = first
            while True:
                species = rom.byte(bank, address)
                address += 1
                if species == 0:
                    break
                party.append({
                    "level": level,
                    "species": _species(manifest, species),
                })
        parties.append(party)
    if address != end:
        raise ValueError(
            f"trainer party data overran {bank:02X}:{end:04X}")
    return parties


def extract_trainers(rom, symbols, manifest, out_dir, assets_dir):
    order = manifest["trainers"]
    charmap = manifest["charmap"]
    names = _symbol(symbols, "TrainerNames")
    pointers = _symbol(symbols, "TrainerDataPointers")
    money = _symbol(symbols, "TrainerPicAndMoneyPointers")
    choices = _symbol(symbols, "TrainerClassMoveChoiceModifications")

    decoded_names = []
    address = names.address
    for _ in order:
        name, consumed = read_string(
            rom, names.bank, address, charmap, max_length=32)
        decoded_names.append(name)
        address += consumed

    ai_mods = []
    address = choices.address
    for _ in order:
        mods = []
        while True:
            value = rom.byte(choices.bank, address)
            address += 1
            if value == 0:
                break
            mods.append(value)
        ai_mods.append(mods)

    party_starts = [
        rom.word(pointers.bank, pointers.address + index * 2)
        for index in range(len(order))
    ]
    party_ends = party_starts[1:] + [_symbol(symbols, "TrainerAI").address]

    out = {}
    written_pics = set()
    for index, label in enumerate(order):
        trainer_id = "OPP_" + label
        raw_money = rom.bytes(
            money.bank, money.address + index * 5 + 2, 3)
        pic = manifest["trainerPics"][index]
        if pic and pic["imageBase"] not in written_pics:
            _write_compressed_pic(
                rom, symbols, pic["label"],
                os.path.join(
                    assets_dir, "battle", "trainers",
                    pic["imageBase"] + ".png"))
            written_pics.add(pic["imageBase"])
        out[trainer_id] = {
            "id": trainer_id,
            "index": index + 1,
            "name": decoded_names[index],
            "source": "ROM:TrainerDataPointers",
            "pic": pic["path"] if pic else None,
            "baseMoney": bcd(raw_money) // 100,
            "aiMods": ai_mods[index],
            "parties": _trainer_parties(
                rom, pointers.bank, party_starts[index],
                party_ends[index], manifest),
        }

    util.write_lua(
        os.path.join(out_dir, "trainers.lua"), out,
        header="Source: canonical Pokemon Red ROM (TrainerDataPointers,\n"
               "TrainerNames, TrainerPicAndMoneyPointers)")
    return out


def _wild_table(rom, bank, address, manifest):
    grass_rate = rom.byte(bank, address)
    address += 1
    grass = {"rate": grass_rate, "slots": []}
    if grass_rate:
        for _ in range(10):
            level, species = rom.bytes(bank, address, 2)
            grass["slots"].append({
                "level": level,
                "species": _species(manifest, species),
            })
            address += 2

    water_rate = rom.byte(bank, address)
    address += 1
    water = {"rate": water_rate, "slots": []}
    if water_rate:
        for _ in range(10):
            level, species = rom.bytes(bank, address, 2)
            water["slots"].append({
                "level": level,
                "species": _species(manifest, species),
            })
            address += 2
    return grass, water


def extract_encounters(rom, symbols, manifest, out_dir):
    maps = manifest["constants"]["mapOrder"]
    pointers = _symbol(symbols, "WildDataPointers")
    nothing = _symbol(symbols, "NothingWildMons")
    out = {}
    for index, map_id in enumerate(maps):
        address = rom.word(
            pointers.bank, pointers.address + index * 2)
        if address == nothing.address:
            continue
        grass, water = _wild_table(
            rom, pointers.bank, address, manifest)
        entry = {"source": f"ROM:{pointers.bank:02X}:{address:04X}"}
        if grass["rate"] or grass["slots"]:
            entry["grass"] = grass
        if water["rate"] or water["slots"]:
            entry["water"] = water
        out[map_id] = entry

    util.write_lua(
        os.path.join(out_dir, "encounters.lua"), out,
        header="Source: canonical Pokemon Red ROM (WildDataPointers)")
    return out


TEXT_GLYPH_OVERRIDES = {
    0x4B: "{_CONT}",
    0x4C: "{SCROLL}",
    0x6D: "{COLON}",
    0xF0: "¥",
}


def _text_glyph(value, charmap):
    if value in TEXT_GLYPH_OVERRIDES:
        return TEXT_GLYPH_OVERRIDES[value]
    glyph = charmap.get(str(value), f"{{BYTE:{value:02X}}}")
    if glyph.startswith("<") and glyph.endswith(">"):
        return "{" + glyph[1:-1] + "}"
    return glyph


def _decode_text_commands(rom, symbol, charmap, substitutions):
    address = symbol.address
    pending = deque(substitutions)
    out = []
    for _ in range(4096):
        command = rom.byte(symbol.bank, address)
        address += 1
        if command == 0x50:
            if pending:
                raise ValueError(
                    f"{symbol.name}: unused dynamic text substitutions")
            return "".join(out)
        if command == 0:
            while True:
                value = rom.byte(symbol.bank, address)
                address += 1
                if value == 0x50:
                    break
                if value in (0x57, 0x58, 0x5F):
                    if pending:
                        raise ValueError(
                            f"{symbol.name}: unused dynamic text substitutions")
                    return "".join(out)
                out.append(_text_glyph(value, charmap))
            continue
        if command in (1, 2, 9):
            if not pending:
                raise ValueError(
                    f"{symbol.name}: missing substitution for command "
                    f"${command:02X}")
            expected, token = pending.popleft()
            if command != expected:
                raise ValueError(
                    f"{symbol.name}: expected command ${expected:02X}, "
                    f"found ${command:02X}")
            out.append(token)
            address += 2 if command == 1 else 3
            continue
        raise ValueError(
            f"{symbol.name}: unsupported text command ${command:02X}")
    raise ValueError(f"{symbol.name}: text command stream is too long")


def _extract_text_from_stub_manifest(manifest, out_dir, rom=None, assets_dir=None):
    symbols = manifest.get("symbols") or {}
    maps_meta = manifest.get("maps") or {}
    charmap = manifest.get("charmap") or {}
    events_by_map = _gen2_stub_map_events(manifest, rom)
    label_index = []
    for map_id, spec in maps_meta.items():
        label = spec.get("label") if isinstance(spec, dict) else None
        if isinstance(label, str) and label:
            label_index.append((map_id, label))
    # Longest prefix wins so Route30 maps to Route30 before Route3.
    label_index.sort(key=lambda row: len(row[1]), reverse=True)

    def map_for_symbol(name):
        for map_id, label in label_index:
            if name.startswith(label):
                return map_id
        return None

    def marker_flags(name):
        lower = name.lower()
        flags = {}
        if "nurse" in lower:
            flags["nurse"] = True
        if "cableclub" in lower or "cable_club" in lower:
            flags["cableClub"] = True
        # Keep PC detection conservative to avoid matching unrelated words.
        if "pctext" in lower or "pokemoncenterpc" in lower or "pokecenterpc" in lower:
            flags["pc"] = True
        # Optional semantic hints for future interaction routing.
        if "sign" in lower:
            flags["sign"] = True
        if "board" in lower or "blackboard" in lower:
            flags["board"] = True
        if "poster" in lower:
            flags["poster"] = True
        return flags

    def map_object_counts():
        counts = {}
        if rom is None:
            return counts
        for map_id, spec in maps_meta.items():
            label = spec.get("label") if isinstance(spec, dict) else None
            if not label:
                continue
            sym = symbols.get(label + "_MapEvents")
            if not sym:
                continue
            try:
                bank = int(sym[0])
                address = int(sym[1])
                # poke{gold,silver}:
                # db filler[2], warpCount + 5*count,
                # coordCount + 8*count, bgCount + 5*count, objectCount
                warp_count = rom.byte(bank, address + 2)
                offset = address + 3 + warp_count * 5
                coord_count = rom.byte(bank, offset)
                offset += 1 + coord_count * 8
                bg_count = rom.byte(bank, offset)
                offset += 1 + bg_count * 5
                object_count = rom.byte(bank, offset)
                if 0 <= object_count < 0x80:
                    counts[map_id] = object_count
            except Exception:
                # Leave map count unset if symbol data is malformed.
                continue
        return counts

    object_counts = map_object_counts()

    def _is_sign_like_label(name):
        lower = name.lower()
        tokens = (
            "sign", "poster", "directory", "blackboard", "bookshelf",
            "statue", "maptext", "radio", "adtext",
        )
        return any(token in lower for token in tokens)

    def _is_trainer_like_label(name):
        lower = name.lower()
        tokens = (
            "seentext", "beatentext", "afterbattletext", "beforetext",
            "battletext", "defeatedtext", "wintext", "winlosstext",
            "trainer", "rival", "rocket",
        )
        return any(token in lower for token in tokens)

    # Keep this broad so both labels like "FooText" and nested symbols such as
    # "AcademyBlackboard.Text" are captured.
    rows = [
        (name, location)
        for name, location in symbols.items()
        if "Text" in name
    ]
    rows.sort(key=lambda row: (int(row[1][0]), int(row[1][1]), row[0]))

    # Emit references, never decoded strings.  The only charmap available here
    # is the stub manifest's, which spells every non-alphanumeric code back as
    # its own "{BYTE:xx}" placeholder -- and Data.lua *strips* those, so eager
    # decoding here silently deletes every apostrophe, hyphen and POKe glyph
    # ("DAY-CARE" -> "DAYCARE").  RomExtractorGen2 resolves these refs off the
    # cart with the real charmap, so leave the text to it.
    texts = {}
    for name, location in rows:
        bank = int(location[0])
        address = int(location[1])
        texts[name] = f"{{GEN2_TEXT:{bank:02X}:{address:04X}:{name}}}"

    if assets_dir and rom is not None:
        trainer_dir = os.path.join(assets_dir, "battle", "trainers")
        os.makedirs(trainer_dir, exist_ok=True)

        def try_write_pic(symbol_name, relpath):
            try:
                _write_compressed_pic(
                    rom, SymbolTable(symbols), symbol_name,
                    os.path.join(assets_dir, relpath))
                return True
            except Exception:
                return False

        def try_write_raw_7x7(symbol_name, relpath):
            try:
                location = symbols.get(symbol_name)
                if not location:
                    return False
                bank = int(location[0])
                address = int(location[1])
                raw = rom.bytes(bank, address, 56 * 56 // 4)
                _write_2bpp_png(raw, 56, 56, os.path.join(assets_dir, relpath),
                                transparent_color0=True)
                return True
            except Exception:
                return False

        if not (try_write_pic("OakSpriteGFX", os.path.join("battle", "trainers", "prof_oak.png"))
                or try_write_raw_7x7("OakSpriteGFX", os.path.join("battle", "trainers", "prof_oak.png"))):
            pass
        if not (try_write_pic("BluePic", os.path.join("battle", "trainers", "rival1.png"))
                or try_write_raw_7x7("BluePic", os.path.join("battle", "trainers", "rival1.png"))):
            pass
        if not (try_write_pic("ChrisPicAndTrainerCardGFX", os.path.join("battle", "trainers", "player_intro.png"))
                or try_write_pic("RedPic", os.path.join("battle", "trainers", "player_intro.png"))
                or try_write_raw_7x7("ChrisPicAndTrainerCardGFX", os.path.join("battle", "trainers", "player_intro.png"))
                or try_write_raw_7x7("RedPic", os.path.join("battle", "trainers", "player_intro.png"))):
            pass

    pointers = {}
    pointer_counts = {}
    text_labels_by_map = {}
    trainer_groups = {}
    for name, location in rows:
        bank = int(location[0])
        address = int(location[1])
        map_id = map_for_symbol(name)
        if map_id:
            pointer_counts[map_id] = pointer_counts.get(map_id, 0) + 1
            text_const = f"TEXT_{map_id}_{pointer_counts[map_id]:03d}"
            row = {
                "text": name,
                "label": name,
            }
            row.update(marker_flags(name))
            pointers.setdefault(map_id, {})[text_const] = row
            text_labels_by_map.setdefault(map_id, []).append(name)

        role = None
        root = None
        priority = 0
        if name.endswith("SeenText"):
            role, root, priority = "battle", name[:-len("SeenText")], 4
        elif name.endswith("BeforeText"):
            role, root, priority = "battle", name[:-len("BeforeText")], 3
        elif name.endswith("BattleText"):
            role, root, priority = "battle", name[:-len("BattleText")], 2
        elif name.endswith("BeatenText"):
            role, root, priority = "won", name[:-len("BeatenText")], 5
        elif name.endswith("DefeatedText"):
            role, root, priority = "won", name[:-len("DefeatedText")], 4
        elif name.endswith("WinLossText"):
            role, root, priority = "won", name[:-len("WinLossText")], 3
        elif name.endswith("WinText"):
            role, root, priority = "won", name[:-len("WinText")], 2
        elif name.endswith("AfterBattleText"):
            role, root, priority = "after", name[:-len("AfterBattleText")], 3
        elif name.endswith("AfterText"):
            role, root, priority = "after", name[:-len("AfterText")], 2

        if map_id and role and root:
            key = (map_id, root)
            group = trainer_groups.setdefault(key, {})
            previous = group.get(role)
            if not previous or priority > previous[1]:
                group[role] = (name, priority)

    for map_id, event_spec in events_by_map.items():
        pool = text_labels_by_map.get(map_id, [])
        sign_pool = [name for name in pool if _is_sign_like_label(name)]
        trainer_pool = [name for name in pool if _is_trainer_like_label(name)]
        npc_pool = [
            name for name in pool
            if not _is_sign_like_label(name) and not _is_trainer_like_label(name)
        ]
        all_index = 0
        bucket_indexes = {
            "sign": 0,
            "trainer": 0,
            "npc": 0,
        }

        def pick_label(kind, fallback_key):
            nonlocal all_index
            candidates = {
                "sign": sign_pool,
                "trainer": trainer_pool,
                "npc": npc_pool,
            }.get(kind, [])
            if candidates:
                index = bucket_indexes[kind] % len(candidates)
                bucket_indexes[kind] += 1
                return candidates[index]
            if pool:
                label = pool[all_index % len(pool)]
                all_index += 1
                return label
            texts.setdefault(
                fallback_key,
                f"{{GEN2_TEXT_STUB:{map_id}:{fallback_key}}}")
            return fallback_key

        per_map = pointers.setdefault(map_id, {})
        for sign in event_spec.get("signs", []):
            key = sign.get("text")
            if not key or key in per_map:
                continue
            label = pick_label("sign", key)
            row = {"text": label, "label": label}
            row.update(marker_flags(label))
            row.setdefault("sign", True)
            per_map[key] = row

        for obj in event_spec.get("objects", []):
            key = obj.get("text")
            if not key or key in per_map:
                continue
            preferred = "trainer" if trainer_pool else "npc"
            label = pick_label(preferred, key)
            row = {"text": label, "label": label}
            row.update(marker_flags(label))
            row.setdefault("objectEvent", True)
            per_map[key] = row

    trainer_headers = {}
    per_map_groups = {}
    for (map_id, root), header in trainer_groups.items():
        if "battle" in header and "won" in header:
            resolved = {
                "battle": header["battle"][0],
                "won": header["won"][0],
            }
            if "after" in header:
                resolved["after"] = header["after"][0]
            per_map_groups.setdefault(map_id, []).append((root, resolved))
    for map_id, grouped in per_map_groups.items():
        grouped.sort(key=lambda row: row[0])
        object_limit = object_counts.get(map_id)
        rows_for_map = {}
        for index, (_, header) in enumerate(grouped, start=1):
            if object_limit is not None and index > object_limit:
                break
            row = {
                "range": 0,
                "battle": header["battle"],
                "won": header["won"],
            }
            if "after" in header:
                row["after"] = header["after"]
            rows_for_map[index] = row
        trainer_headers[map_id] = rows_for_map

    util.write_lua(
        os.path.join(out_dir, "text.lua"), texts,
        header="Source: Gen2 Phase 2B stub manifest symbol index (text labels)")
    util.write_lua(
        os.path.join(out_dir, "text_pointers.lua"), pointers,
        header="Source: Gen2 Phase 2B stub manifest map-label text scaffold")
    util.write_lua(
        os.path.join(out_dir, "trainer_headers.lua"), trainer_headers,
        header="Source: Gen2 Phase 2B symbol-derived trainer text scaffold")

    return {
        "texts": texts,
        "pointers": pointers,
        "trainerHeaders": trainer_headers,
    }


def extract_text(rom, symbols, manifest, out_dir, assets_dir=None):
    if _is_gen2_stub_manifest(manifest):
        return _extract_text_from_stub_manifest(
            manifest, out_dir, rom=rom, assets_dir=assets_dir)

    metadata = manifest["text"]
    charmap = manifest["charmap"]
    dynamic = metadata["dynamic"]
    trainer_headers = {
        map_label: {
            int(index): header for index, header in headers.items()
        }
        for map_label, headers in metadata["trainerHeaders"].items()
    }
    texts = {}
    for label in metadata["labels"]:
        texts[label] = _decode_text_commands(
            rom, _symbol(symbols, label), charmap, dynamic.get(label, []))

    util.write_lua(
        os.path.join(out_dir, "text.lua"), texts,
        header="Source: canonical Pokemon Red ROM text command streams")
    util.write_lua(
        os.path.join(out_dir, "text_pointers.lua"), metadata["pointers"],
        header="Map text integration metadata; dialogue is decoded from ROM")
    util.write_lua(
        os.path.join(out_dir, "trainer_headers.lua"),
        trainer_headers,
        header="Trainer integration metadata; dialogue is decoded from ROM")
    return {
        "texts": texts,
        "pointers": metadata["pointers"],
        "trainerHeaders": trainer_headers,
    }


def extract_field(rom, symbols, manifest, out_dir, assets_dir):
    def raw_2bpp(
            label, width, height, relative, transparent=False, matte=False,
            columns=False, stored_length=None):
        expected = width * height // 4
        length = expected if stored_length is None else stored_length
        symbol = _symbol(symbols, label)
        raw = rom.bytes(symbol.bank, symbol.address, length)
        if len(raw) < expected:
            raw += bytes(expected - len(raw))
        if columns:
            raw = _columns_to_rows(raw, width // 8, height // 8)
        image = _decode_2bpp(raw, width, height, transparent)
        if matte:
            image = _matte_color0(image)
        _save_png(image, os.path.join(assets_dir, relative))
        return image

    def raw_1bpp(label, width, height, relative, transparent=False):
        symbol = _symbol(symbols, label)
        raw = rom.bytes(symbol.bank, symbol.address, width * height // 8)
        image = _decode_1bpp(raw, width, height, transparent)
        _save_png(image, os.path.join(assets_dir, relative))
        return image

    raw_2bpp(
        "PokemonLogoGraphics", 128, 56, "title/pokemon_logo.png")
    raw_1bpp("Version_GFX", 80, 8, "title/red_version.png")
    raw_2bpp(
        "PlayerCharacterTitleGraphics", 40, 56, "title/player.png",
        matte=True)
    raw_2bpp(
        "NintendoCopyrightLogoGraphics", 152, 8,
        "title/copyright.png")
    raw_2bpp(
        "GameFreakLogoGraphics", 72, 8, "title/gamefreak_inc.png")

    # Yellow fixed Pikachu title (pret/pokeyellow title_yellow.asm): tilemap
    # composition over both tile banks -- PokemonLogoGraphics in vChars2
    # (BG ids $00-$7F), TitlePikachuBGGraphics in vChars1 (ids $80-$EF),
    # TitlePikachuOBGraphics at vChars1 tile $70 (ids $F0-$FC, also the eye
    # OAM tiles), PokemonLogoCornerGraphics at vChars1 tile $7D ($FD-$FF).
    # Mirrors RomExtractor:extractYellowTitleArt.
    if _has_symbol(symbols, "TitlePikachuBGGraphics"):
        raw_2bpp(
            "TitlePikachuBGGraphics", 128, 32, "title/pikachu_bg.png",
            transparent=True)
        raw_2bpp(
            "TitlePikachuOBGraphics", 96, 8, "title/pikachu_ob.png",
            transparent=True)

        def sheet_tiles(label, count, transparent=False):
            symbol = _symbol(symbols, label)
            raw = rom.bytes(symbol.bank, symbol.address, count * 16)
            return [
                _decode_2bpp(raw[index:index + 16], 8, 8, transparent)
                for index in range(0, len(raw), 16)
            ]

        # tile counts = Graphics..GraphicsEnd symbol gaps in pokeyellow.sym
        logo_tiles = sheet_tiles("PokemonLogoGraphics", 115)
        corner_tiles = sheet_tiles("PokemonLogoCornerGraphics", 3)
        bg_tiles = sheet_tiles("TitlePikachuBGGraphics", 64)
        ob_tiles = sheet_tiles("TitlePikachuOBGraphics", 12)
        ob_clear = sheet_tiles("TitlePikachuOBGraphics", 12, True)

        def tile_for(tid):
            if tid < 0x80:
                return logo_tiles[tid]
            if tid < 0xF0:
                return bg_tiles[tid - 0x80]
            if tid < 0xFD:
                return ob_tiles[tid - 0xF0]
            return corner_tiles[tid - 0xFD]

        def matte_color0(pose):
            from collections import deque
            w, h = pose.size
            seen = set()
            q = deque()

            def add(x, y):
                if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
                    return
                if pose.getpixel((x, y)) == (255, 255, 255, 255):
                    seen.add((x, y))
                    q.append((x, y))
            for x in range(w):
                add(x, 0); add(x, h - 1)
            for y in range(h):
                add(0, y); add(w - 1, y)
            while q:
                x, y = q.popleft()
                pose.putpixel((x, y), (255, 255, 255, 0))
                add(x - 1, y); add(x + 1, y); add(x, y - 1); add(x, y + 1)
            return pose

        def compose(cols, rows, cells):
            pose = Image.new("RGBA", (cols * 8, rows * 8), (255, 255, 255, 0))
            for tid, cx, cy in cells:
                pose.paste(tile_for(tid), (cx * 8, cy * 8))
            return pose

        def map_cells(label, cols, rows):
            loc = _symbol(symbols, label)
            ids = list(rom.bytes(loc.bank, loc.address, cols * rows))
            return [
                (tid, index % cols, index // cols)
                for index, tid in enumerate(ids)
            ]

        # 16x7 logo box at (2,1); overwrites the scrambled sequential rip
        # above (Yellow's logo sheet is deduplicated, Red's is not)
        _save_png(
            compose(16, 7, map_cells("TitleScreenPokemonLogoTilemap", 16, 7)),
            os.path.join(assets_dir, "title/pokemon_logo.png"))

        # 7x4 bubble at (6,4) + the two tail tiles poked at (9,8)
        bubble_cells = map_cells("TitleScreenPikaBubbleTilemap", 7, 4)
        bubble_cells += [(0x64, 3, 4), (0x65, 4, 4)]
        _save_png(
            matte_color0(compose(7, 5, bubble_cells)),
            os.path.join(assets_dir, "title/pika_bubble.png"))

        # 12x9 Pikachu at (4,8) + right-ear edge tiles down column 16 and
        # the baked OAM eyes (TitleScreenPikachuEyesOAMData, left eye
        # x-flipped, attr $22)
        pika_cells = map_cells("TitleScreenPikachuTilemap", 12, 9)
        pika_cells += [(0x96, 12, 2), (0x9d, 12, 3),
                       (0xa7, 12, 4), (0xb1, 12, 5)]
        pikachu = matte_color0(compose(13, 9, pika_cells))
        for ob_index, px, py, flip in (
                (1, 24, 16, True), (0, 32, 16, True),
                (3, 24, 24, True), (2, 32, 24, True),
                (0, 56, 16, False), (1, 64, 16, False),
                (2, 56, 24, False), (3, 64, 24, False)):
            eye = ob_clear[ob_index]
            if flip:
                eye = eye.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            pikachu.paste(eye, (px, py), eye)
        _save_png(pikachu, os.path.join(assets_dir, "title/pikachu.png"))

    falling_star = raw_2bpp(
        "FallingStar", 8, 8, "intro/falling_star.png",
        transparent=True)
    blink = Image.new("RGBA", falling_star.size, (255, 255, 255, 0))
    for y in range(falling_star.height):
        for x in range(falling_star.width):
            pixel = falling_star.getpixel((x, y))
            if pixel[3] and pixel[0] == 170:
                blink.putpixel((x, y), pixel)
    _save_png(blink, os.path.join(
        assets_dir, "intro/falling_star_blink.png"))

    gamefreak = _symbol(symbols, "GameFreakIntro")
    presents_raw = rom.bytes(
        gamefreak.bank, gamefreak.address, 104 * 8 // 4)
    presents = _decode_2bpp(
        presents_raw, 104, 8, transparent_color0=True)
    _save_png(
        presents, os.path.join(
            assets_dir, "intro/gamefreak_presents.png"))
    logo_raw = rom.bytes(
        gamefreak.bank, gamefreak.address + len(presents_raw),
        16 * 24 // 4)
    _save_png(
        _decode_2bpp(logo_raw, 16, 24, transparent_color0=True),
        os.path.join(assets_dir, "intro/gamefreak_logo.png"))

    text_image = Image.new("RGBA", (80, 8), (255, 255, 255, 0))
    for index, tile in enumerate((0, 1, 2, 3, None, 4, 5, 3, 1, 6)):
        if tile is not None:
            text_image.paste(
                presents.crop((tile * 8, 0, tile * 8 + 8, 8)),
                (index * 8, 0))
    _save_png(
        text_image,
        os.path.join(assets_dir, "intro/gamefreak_text.png"))

    move_tiles = _symbol(symbols, "MoveAnimationTiles1")
    star = Image.new("RGBA", (16, 16), (255, 255, 255, 0))
    for row, tile in ((0, 3), (1, 19)):
        tile_raw = rom.bytes(
            move_tiles.bank, move_tiles.address + tile * 16, 16)
        image = _decode_2bpp(
            tile_raw, 8, 8, transparent_color0=True)
        star.paste(image, (0, row * 8))
        star.paste(
            image.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
            (8, row * 8))
    _save_png(star, os.path.join(assets_dir, "intro/big_star.png"))

    # Yellow replaces the Gengar/Nidorino fight intro (no FightIntro* symbols).
    # Still emit the Red/Blue asset paths so Title/Intro loaders stay happy.
    if _has_symbol(symbols, "FightIntroBackMon"):
        gengar = _symbol(symbols, "FightIntroBackMon")
        gengar_raw = rom.bytes(gengar.bank, gengar.address, 96 * 16)
        gengar_tiles = [
            _decode_2bpp(gengar_raw[index:index + 16], 8, 8)
            for index in range(0, len(gengar_raw), 16)
        ]
        for number in (1, 2, 3):
            tilemap = _symbol(symbols, f"GengarIntroTiles{number}")
            tile_ids = rom.bytes(tilemap.bank, tilemap.address, 49)
            pose = Image.new("RGBA", (56, 56))
            for index, tile_id in enumerate(tile_ids):
                pose.paste(
                    gengar_tiles[tile_id],
                    ((index % 7) * 8, (index // 7) * 8))
            pose = _matte_color0(pose)
            _save_png(
                pose, os.path.join(
                    assets_dir, "intro", f"gengar_{number}.png"))
    else:
        blank = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
        for number in (1, 2, 3):
            _save_png(
                blank, os.path.join(
                    assets_dir, "intro", f"gengar_{number}.png"))

    if _has_symbol(symbols, "FightIntroFrontMon"):
        for number, label in enumerate((
                "FightIntroFrontMon", "FightIntroFrontMon2",
                "FightIntroFrontMon3"), start=1):
            raw_2bpp(
                label, 48, 48, f"intro/red_nidorino_{number}.png",
                transparent=True, columns=True)
    else:
        blank = Image.new("RGBA", (48, 48), (255, 255, 255, 0))
        for number in (1, 2, 3):
            _save_png(
                blank, os.path.join(
                    assets_dir, "intro", f"red_nidorino_{number}.png"))

    for number in (1, 2):
        _write_compressed_pic(
            rom, symbols, f"ShrinkPic{number}",
            os.path.join(assets_dir, "intro", f"shrink{number}.png"))

    raw_2bpp(
        "SlotMachineTiles1", 128, 24, "slots/red_slots_1.png",
        stored_length=0x250)
    slot_sheet = raw_2bpp(
        "SlotMachineTiles2", 32, 48, "slots/red_slots_2.png")
    transparent_slots = slot_sheet.copy()
    for y in range(transparent_slots.height):
        for x in range(transparent_slots.width):
            if transparent_slots.getpixel((x, y)) == (255, 255, 255, 255):
                transparent_slots.putpixel((x, y), (255, 255, 255, 0))
    slot_order = manifest["field"]["slotSymbols"]["order"]
    symbol_sheet = Image.new(
        "RGBA", (16 * len(slot_order), 16), (255, 255, 255, 0))
    for index, name in enumerate(slot_order):
        value = manifest["field"]["slotSymbols"]["symbols"][name]["tiles"]
        high, low = value >> 8, value & 0xFF
        for row, tile in ((0, high), (1, low)):
            x = (tile % 4) * 8
            y = (tile // 4) * 8
            symbol_sheet.paste(
                transparent_slots.crop((x, y, x + 16, y + 8)),
                (index * 16, row * 8))
    _save_png(
        symbol_sheet, os.path.join(assets_dir, "slots/symbols.png"))

    emotes = Image.new("RGBA", (48, 16), (255, 255, 255, 0))
    for index, label in enumerate(
            ("ShockEmote", "QuestionEmote", "HappyEmote")):
        symbol = _symbol(symbols, label)
        image = _decode_2bpp(
            rom.bytes(symbol.bank, symbol.address, 64), 16, 16,
            transparent_color0=True)
        emotes.paste(image, (index * 16, 0))
    _save_png(emotes, os.path.join(assets_dir, "emotes.png"))

    raw_1bpp(
        "LedgeHoppingShadow", 8, 8, "fx/shadow.png",
        transparent=True)
    for label, width, height, filename in (
            ("RedFishingRodTiles", 8, 24, "fishing_rod.png"),
            ("RedFishingTilesSide", 16, 8, "red_fish_side.png"),
            ("RedFishingTilesFront", 16, 8, "red_fish_front.png"),
            ("RedFishingTilesBack", 16, 8, "red_fish_back.png"),
            ("PokeCenterFlashingMonitorAndHealBall", 8, 16,
             "heal_machine.png"),
            ("SSAnneSmokePuffTile", 8, 8, "smoke.png")):
        raw_2bpp(
            label, width, height, "fx/" + filename,
            transparent=True)
    raw_2bpp(
        "BattleTransitionTile", 8, 8, "fx/battle_transition.png")
    raw_2bpp(
        "PokedexTileGraphics", 24, 48, "fx/pokedex.png")

    raw_2bpp(
        "HpBarAndStatusGraphics", 120, 16,
        "battle/font_battle_extra.png", transparent=True)
    for number, label in enumerate(
            ("BattleHudTiles1", "BattleHudTiles2", "BattleHudTiles3"),
            start=1):
        raw_1bpp(
            label, 24, 8, f"battle/battle_hud_{number}.png",
            transparent=True)

    the_end = _symbol(symbols, "TheEndGfx")
    interleaved = rom.bytes(the_end.bank, the_end.address, 160)
    reordered = bytearray(160)
    for column in range(5):
        reordered[column * 16:(column + 1) * 16] = \
            interleaved[column * 32:column * 32 + 16]
        reordered[(column + 5) * 16:(column + 6) * 16] = \
            interleaved[column * 32 + 16:column * 32 + 32]
    _save_png(
        _decode_2bpp(bytes(reordered), 40, 16),
        os.path.join(assets_dir, "credits/the_end.png"))

    raw_2bpp(
        "WorldMapTileGraphics", 32, 32, "townmap/tiles.png")
    raw_1bpp(
        "TownMapCursor", 16, 16, "townmap/cursor.png",
        transparent=True)

    data = copy.deepcopy(manifest["field"])
    adjacency = data["hiddenExtras"]["trashCans"]["adjacent"]
    data["hiddenExtras"]["trashCans"]["adjacent"] = {
        int(index): values for index, values in adjacency.items()
    }
    data["source"] = "canonical Pokemon Red ROM + bundled port metadata"
    util.write_lua(
        os.path.join(out_dir, "field.lua"), data,
        header="Field integration metadata; all referenced artwork is "
               "decoded from ROM")
    return data


def build(rom, symbols, manifest, out_dir, assets_dir, datasets):
    results = {}
    if "constants" in datasets:
        results["constants"] = extract_constants(manifest, out_dir)
    if "charmap" in datasets:
        results["charmap"] = extract_charmap(manifest, out_dir)
    if "tilesets" in datasets:
        results["tilesets"] = extract_tilesets(
            rom, symbols, manifest, out_dir, assets_dir)
    if "maps" in datasets:
        results["maps"] = extract_maps(
            rom, symbols, manifest, out_dir)
    if "font" in datasets:
        results["font"] = extract_font(
            rom, symbols, manifest, out_dir, assets_dir)
    if "sprites" in datasets:
        results["sprites"] = extract_sprites(
            rom, symbols, manifest, out_dir, assets_dir)
    if "moves" in datasets:
        results["moves"] = extract_moves(
            rom, symbols, manifest, out_dir)
    if "battle_anims" in datasets:
        results["battle_anims"] = extract_battle_anims(
            rom, symbols, manifest, out_dir, assets_dir)
    if "items" in datasets:
        results["items"] = extract_items(
            rom, symbols, manifest, out_dir)
    if "type_chart" in datasets:
        results["type_chart"] = extract_type_chart(
            rom, symbols, manifest, out_dir)
    if "palettes" in datasets:
        results["palettes"] = extract_palettes(
            rom, symbols, manifest, out_dir)
    if "icons" in datasets:
        results["icons"] = extract_icons(
            rom, symbols, manifest, out_dir, assets_dir)
    if "pokemon" in datasets:
        results["pokemon"] = extract_pokemon(
            rom, symbols, manifest, out_dir, assets_dir)
    if "trainers" in datasets:
        results["trainers"] = extract_trainers(
            rom, symbols, manifest, out_dir, assets_dir)
    if "encounters" in datasets:
        results["encounters"] = extract_encounters(
            rom, symbols, manifest, out_dir)
    if "text" in datasets:
        results["text"] = extract_text(
            rom, symbols, manifest, out_dir, assets_dir)
    if "field" in datasets:
        results["field"] = extract_field(
            rom, symbols, manifest, out_dir, assets_dir)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rom", required=True,
        help="canonical US Pokemon Red/Blue/Yellow/Gold/Silver ROM")
    parser.add_argument(
        "--version", choices=sorted(VERSION_MANIFESTS), default="red",
        help="select the shipped manifest for this version (default: red)")
    parser.add_argument(
        "--manifest", default=None,
        help="explicit manifest path (overrides --version default path; "
             "RomImage hash still comes from the file's romSha1)")
    parser.add_argument("--out", default="data/generated")
    parser.add_argument("--assets", default="assets/generated")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument(
        "--only", action="append", choices=DATASETS,
        help="build one dataset (repeatable); default builds all implemented")
    args = parser.parse_args()
    datasets = tuple(args.only) if args.only else DATASETS

    try:
        manifest_explicit = args.manifest is not None
        manifest_path = resolve_manifest_path(args.version, args.manifest)
        manifest = load_manifest(manifest_path)
        version = version_for_manifest(
            manifest, args.version, manifest_explicit=manifest_explicit)
        ensure_supported_manifest(manifest, version, manifest_path, datasets)
        expected_sha1 = manifest.get("romSha1") or VERSION_SHA1[version]
        rom = RomImage(args.rom, expected_sha1)
        symbols = SymbolTable(manifest["symbols"])
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.clean:
        for path in (args.out, args.assets):
            if os.path.isdir(path):
                shutil.rmtree(path)
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(args.assets, exist_ok=True)
    try:
        build(rom, symbols, manifest, args.out, args.assets, datasets)
    except (ValueError, KeyError, IndexError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(
        f"\ndone: decoded {', '.join(datasets)} from {version} ROM {rom.sha1}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
