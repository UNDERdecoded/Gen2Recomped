#!/usr/bin/env python3
"""Build initial Gen2 (Gold/Silver) ROM metadata manifests.

Phase 2B scope:
- Validate ROM identity (SHA-1 + header bytes).
- Emit deterministic placeholder constants for Gen2-sized tables.
- Keep manifest marked as stub so build_rom_data.py fails clearly until
  Gen2 extraction logic is implemented.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re

from rom_data import CANONICAL_GOLD_SHA1, CANONICAL_SILVER_SHA1, SymbolTable


ROM_HEADER_BASE = 0x100
TITLE_START = 0x134
TITLE_END_EXCLUSIVE = 0x144
CGB_FLAG = 0x143
SGB_FLAG = 0x146
CART_TYPE = 0x147
ROM_SIZE = 0x148
RAM_SIZE = 0x149
DESTINATION = 0x14A
OLD_LICENSEE = 0x14B
MASK_ROM_VERSION = 0x14C
HEADER_CHECKSUM = 0x14D

GEN2_SPECIES_COUNT = 251
GEN2_MOVE_COUNT = 251
GEN2_ITEM_COUNT = 249
GEN2_TRAINER_CLASS_COUNT = 80

EXPECTED_SHA1 = {
    "gold": CANONICAL_GOLD_SHA1,
    "silver": CANONICAL_SILVER_SHA1,
}


GEN2_MAP_DIMENSIONS = {
    "PLAYERS_HOUSE1_F": (5, 4),
    "PLAYERS_HOUSE2_F": (4, 3),
    "PLAYERS_NEIGHBORS_HOUSE": (4, 4),
    "ELMS_LAB": (5, 6),
}


def gen2_seed_charmap():
    """Return a practical Gen2 text map with explicit byte fallbacks.

    This is a Phase 2B seed for tooling/bootstrap output, not final parity.
    Unknown bytes remain self-describing tokens so text decode stays stable.
    """
    out = {str(i): f"{{BYTE:{i:02X}}}" for i in range(256)}

    # Core control bytes used by both Gen1/Gen2 text pipelines.
    out[str(0x50)] = ""
    out[str(0x4E)] = "\n"
    out[str(0x4F)] = "\f"
    out[str(0x57)] = "#"
    out[str(0x75)] = "…"
    out[str(0x7F)] = " "

    # Uppercase A-Z at 0x80..0x99.
    for offset, letter in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        out[str(0x80 + offset)] = letter

    # Lowercase a-z at 0xA0..0xB9.
    for offset, letter in enumerate("abcdefghijklmnopqrstuvwxyz"):
        out[str(0xA0 + offset)] = letter

    # Common punctuation and symbols.
    out[str(0xE6)] = "?"
    out[str(0xE7)] = "!"
    out[str(0xE8)] = "."
    out[str(0xE9)] = "&"
    out[str(0xEA)] = "é"
    out[str(0xF0)] = "¥"
    out[str(0xF1)] = "×"
    out[str(0xF2)] = "."
    out[str(0xF3)] = "/"
    out[str(0xF4)] = ","
    out[str(0xF5)] = "♀"

    # Digits 0-9 at 0xF6..0xFF.
    for offset, digit in enumerate("0123456789"):
        out[str(0xF6 + offset)] = digit

    return out


def sha1_file(path):
    hasher = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def read_rom(path):
    with open(path, "rb") as f:
        return f.read()


def parse_header(rom):
    raw_title = rom[TITLE_START:TITLE_END_EXCLUSIVE]
    title = raw_title.split(b"\x00", 1)[0].decode("ascii", errors="replace").strip()
    return {
        "title": title,
        "cgbFlag": rom[CGB_FLAG],
        "sgbFlag": rom[SGB_FLAG],
        "cartridgeType": rom[CART_TYPE],
        "romSizeCode": rom[ROM_SIZE],
        "ramSizeCode": rom[RAM_SIZE],
        "destinationCode": rom[DESTINATION],
        "oldLicenseeCode": rom[OLD_LICENSEE],
        "maskRomVersion": rom[MASK_ROM_VERSION],
        "headerChecksum": rom[HEADER_CHECKSUM],
    }


def synthetic_order(prefix, count):
    return [f"{prefix}_{index:03d}" for index in range(1, count + 1)]


def gen2_type_table():
    names = [
        "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK",
        "BUG", "GHOST", "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC",
        "PSYCHIC", "ICE", "DRAGON", "DARK",
    ]
    return {name: idx for idx, name in enumerate(names)}


def load_embedded_symbols(symbols_path):
    if not symbols_path:
        return {}
    table = SymbolTable(symbols_path)
    return {
        name: [symbol.bank, symbol.address]
        for name, symbol in sorted(table.by_name.items())
    }


def camel_to_upper_snake(name):
    token = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    token = token.replace("__", "_")
    return token.upper()


def derive_maps_from_symbols(embedded_symbols):
    """Build a deterministic map scaffold from embedded MapAttributes labels."""
    rows = []
    for name, location in embedded_symbols.items():
        if not name.endswith("_MapAttributes"):
            continue
        base = name[:-len("_MapAttributes")]
        map_id = camel_to_upper_snake(base)
        rows.append((int(location[0]), int(location[1]), name, map_id, base))
    rows.sort()

    map_order = []
    map_dims = {}
    maps_meta = {}
    for _, _, label, map_id, base in rows:
        if map_id in map_dims:
            continue
        map_order.append(map_id)
        width, height = GEN2_MAP_DIMENSIONS.get(map_id, (1, 1))
        map_dims[map_id] = {"width": width, "height": height}
        maps_meta[map_id] = {
            "label": base,
            "source": f"SYMBOL:{label}",
            "signTexts": [],
            "objects": [],
        }
    return map_order, map_dims, maps_meta


def placeholder_field_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
        "presetNames": {
            "customOption": "NEW NAME",
            "player": ["CHRIS", "ALEX", "KAI"],
            "rival": ["SILVER", "RIVAL", "???"],
        },
    }


def placeholder_audio_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
        "musicHeaders": {},
        "cries": {},
        "sfx": {},
    }


def placeholder_battle_anims(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
        "baseCoordCount": 0,
        "frameBlockCount": 0,
        "subanimCount": 0,
        "moveCount": GEN2_MOVE_COUNT,
        "miscAnimations": [],
        "subanimTypes": [],
        "firstSpecialEffect": 0,
        "specialEffects": {},
        "tilesheets": [],
    }


def placeholder_map_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
    }


def placeholder_tileset_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
    }


def placeholder_sprite_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
    }


def placeholder_text_data(version):
    return {
        "source": f"Phase 2B placeholder ({version})",
    }


def placeholder_growth_rates():
    return {
        "MEDIUM_FAST": [0, 0, 0, 1],
    }


def placeholder_trainer_pics(trainers):
    return {
        trainer: {
            "path": f"assets/generated/battle/trainers/{trainer.lower()}.png",
            "source": "Phase 2B placeholder",
            "width": 7,
            "height": 7,
        }
        for trainer in trainers
    }


def placeholder_pokemon_assets(species_order):
    out = {}
    for species in species_order:
        out[species] = {
            "front": species.lower(),
            "back": species.lower() + "b",
            "frontLabel": None,
            "backLabel": None,
        }
    return out


def build_manifest(version, rom_path, symbols_path=None):
    expected = EXPECTED_SHA1[version]
    actual = sha1_file(rom_path)
    if actual != expected:
        raise SystemExit(
            f"{version} ROM hash mismatch: got {actual}, expected {expected}")

    rom = read_rom(rom_path)
    if len(rom) < 1024 * 1024:
        raise SystemExit(
            f"{version} ROM is too small ({len(rom)} bytes); expected at least 1 MiB")

    species_order = synthetic_order("SPECIES", GEN2_SPECIES_COUNT)
    move_order = synthetic_order("MOVE", GEN2_MOVE_COUNT)
    item_order = synthetic_order("ITEM", GEN2_ITEM_COUNT)
    trainer_order = synthetic_order("TRAINER", GEN2_TRAINER_CLASS_COUNT)
    icon_order = [f"ICON_{i:02d}" for i in range(10)]
    embedded_symbols = load_embedded_symbols(symbols_path)

    notes = (
        "Phase 2B initial manifest. Identity and high-level constants are "
        "present, plus a seeded charmap. Symbol maps and most extractable "
        "data sections are still pending."
    )
    if embedded_symbols:
        notes += " Embedded symbol addresses were loaded from a .sym file."

    map_order, map_dims, maps_meta = derive_maps_from_symbols(embedded_symbols)
    if map_order:
        notes += " Map scaffold was derived from *_MapAttributes symbols."

    tileset_order = [
        "TilesetJohto",
        "TilesetJohtoModern",
        "TilesetKanto",
        "TilesetHouse",
        "TilesetLab",
        "TilesetMart",
        "TilesetGate",
        "TilesetPokecenter",
        "TilesetPlayersHouse",
        "TilesetPlayersRoom",
        "TilesetPort",
        "TilesetTower",
        "TilesetLighthouse",
        "TilesetForest",
        "TilesetCave",
        "TilesetDarkCave",
        "TilesetGameCorner",
        "TilesetTrainStation",
        "TilesetRadioTower",
        "TilesetRuinsOfAlph",
        "TilesetPark",
        "TilesetFacility",
        "TilesetMansion",
        "TilesetUnderground",
        "TilesetIcePath",
        "TilesetChampionsRoom",
    ]

    tilesets = {}
    for name in tileset_order:
        family = name.removeprefix("Tileset")
        tilesets[name] = {
            "id": name,
            "source": "Phase 2B synthetic scaffold",
            "imageBase": family.lower(),
            "imageWidth": 128,
            "imageHeight": 128,
            "blockCount": 0x80,
        }

    return {
        "format": 3,
        "generation": 2,
        "phase": "2b-initial",
        "version": version,
        "romSha1": actual,
        "romHeader": parse_header(rom),
        "stub": True,
        "notes": notes,
        "constants": {
            "source": "Phase 2B synthetic scaffold",
            "speciesOrder": species_order,
            "moveOrder": move_order,
            "itemOrder": item_order,
            "types": gen2_type_table(),
            "mapOrder": map_order,
            "maps": map_dims,
            "tilesetOrder": tileset_order,
            "spriteOrder": [],
        },
        "moveEffects": ["UNUSED"] * (GEN2_MOVE_COUNT + 1),
        "items": item_order,
        "numItems": GEN2_ITEM_COUNT,
        "hms": [],
        "tms": [],
        "trainers": trainer_order,
        "trainerPics": placeholder_trainer_pics(trainer_order),
        "trainerPartyOverrides": {},
        "dexOrder": species_order,
        "pokemonAssets": placeholder_pokemon_assets(species_order),
        "growthRates": placeholder_growth_rates(),
        "tmhmMoves": [],
        "paletteOrder": [],
        "iconOrder": icon_order,
        "maps": maps_meta if maps_meta else placeholder_map_data(version),
        "tilesets": tilesets,
        "tileAnimations": [],
        "sprites": placeholder_sprite_data(version),
        "fontCharmap": {},
        "sfxKeys": {},
        "typeNameLabels": [],
        "dexEntryLabels": {},
        "text": placeholder_text_data(version),
        "field": placeholder_field_data(version),
        "audio": placeholder_audio_data(version),
        "battleAnimations": placeholder_battle_anims(version),
        "charmap": gen2_seed_charmap(),
        "symbols": embedded_symbols,
    }


def write_manifest(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gold-rom", required=True)
    parser.add_argument("--silver-rom", required=True)
    parser.add_argument(
        "--gold-symbols",
        default=None,
        help="optional RGBDS .sym file for Gold; embeds symbols into manifest")
    parser.add_argument(
        "--silver-symbols",
        default=None,
        help="optional RGBDS .sym file for Silver; embeds symbols into manifest")
    parser.add_argument("--out-dir", default=os.path.dirname(__file__))
    args = parser.parse_args()

    out_dir = os.path.abspath(args.out_dir)

    gold_symbols = os.path.abspath(args.gold_symbols) if args.gold_symbols else None
    silver_symbols = (
        os.path.abspath(args.silver_symbols) if args.silver_symbols else None)

    if gold_symbols and not os.path.isfile(gold_symbols):
        raise SystemExit(f"gold symbols file not found: {gold_symbols}")
    if silver_symbols and not os.path.isfile(silver_symbols):
        raise SystemExit(f"silver symbols file not found: {silver_symbols}")

    gold = build_manifest(
        "gold", os.path.abspath(args.gold_rom), gold_symbols)
    silver = build_manifest(
        "silver", os.path.abspath(args.silver_rom), silver_symbols)

    gold_path = os.path.join(out_dir, "rom_manifest_gold.json")
    silver_path = os.path.join(out_dir, "rom_manifest_silver.json")

    write_manifest(gold_path, gold)
    write_manifest(silver_path, silver)

    print(f"wrote {gold_path}")
    print(f"wrote {silver_path}")


if __name__ == "__main__":
    main()
