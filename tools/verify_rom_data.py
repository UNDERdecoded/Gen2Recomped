#!/usr/bin/env python3
"""Compare ROM-backed core data with the existing source-backed extractors."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_rom_data  # noqa: E402
from extract import (battle_anims, constants, encounters, field, font,  # noqa: E402
                     icons, items, maps, moves, palettes, pokemon, sprites,
                     text, tilesets, trainers, type_chart)
from rom_data import RomImage, SymbolTable, load_manifest  # noqa: E402


GEN1_MANIFEST_KEYS = {
    "audio", "battleAnimations", "charmap", "constants", "dexEntryLabels",
    "dexOrder", "field", "fontCharmap", "format", "growthRates", "hms",
    "iconOrder", "items", "maps", "moveEffects", "numItems",
    "paletteOrder", "pokemonAssets", "romSha1", "sfxKeys", "sprites",
    "symbols", "text", "tileAnimations", "tilesets", "tmhmMoves", "tms",
    "trainerPartyOverrides", "trainerPics", "trainers", "typeNameLabels",
}


def _verify_gen2_scaffold_quality(actual):
    maps_data = actual.get("maps") or {}
    text_data = actual.get("text") or {}
    texts = text_data.get("texts") or {}
    pointers = text_data.get("pointers") or {}
    trainer_headers = text_data.get("trainerHeaders") or {}

    if not isinstance(maps_data, dict) or not maps_data:
        raise AssertionError("Gen2 scaffold quality: maps dataset is empty")

    required_map_keys = {
        "id", "index", "label", "source", "tileset", "width", "height",
        "blocks", "borderBlock", "connections", "warps", "signs", "objects",
    }
    sample_map_id, sample_map = next(iter(maps_data.items()))
    if not isinstance(sample_map, dict):
        raise AssertionError(
            f"Gen2 scaffold quality: map row {sample_map_id} is not a table")
    missing_map_keys = sorted(required_map_keys - set(sample_map.keys()))
    if missing_map_keys:
        raise AssertionError(
            "Gen2 scaffold quality: map rows missing required keys: "
            + ", ".join(missing_map_keys))

    warp_rows = 0
    sign_rows = 0
    object_rows = 0
    for map_id, row in maps_data.items():
        warps = row.get("warps", [])
        signs = row.get("signs", [])
        objects = row.get("objects", [])
        if not isinstance(warps, list) or not isinstance(signs, list) \
                or not isinstance(objects, list):
            raise AssertionError(
                f"Gen2 scaffold quality: map row {map_id} event lists malformed")
        warp_rows += len(warps)
        sign_rows += len(signs)
        object_rows += len(objects)

    if warp_rows < 300:
        raise AssertionError(
            "Gen2 scaffold quality: too few warp scaffold rows "
            f"({warp_rows})")
    if sign_rows < 200:
        raise AssertionError(
            "Gen2 scaffold quality: too few sign scaffold rows "
            f"({sign_rows})")
    if object_rows < 500:
        raise AssertionError(
            "Gen2 scaffold quality: too few object scaffold rows "
            f"({object_rows})")

    if not isinstance(pointers, dict):
        raise AssertionError("Gen2 scaffold quality: text pointers is not a table")

    map_count = len(maps_data)
    mapped_pointer_maps = 0
    pointer_rows = 0
    for per_map in pointers.values():
        if isinstance(per_map, dict) and per_map:
            mapped_pointer_maps += 1
            pointer_rows += len(per_map)

    coverage = mapped_pointer_maps / map_count if map_count else 0.0
    if coverage < 0.25:
        raise AssertionError(
            "Gen2 scaffold quality: low text pointer map coverage "
            f"({mapped_pointer_maps}/{map_count}={coverage:.1%})")

    if pointer_rows < 150:
        raise AssertionError(
            "Gen2 scaffold quality: too few text pointer rows "
            f"({pointer_rows})")

    if not isinstance(texts, dict):
        raise AssertionError("Gen2 scaffold quality: text dataset is not a table")

    bg_obj_rows = 0
    bg_rows = 0
    bg_sign_rows = 0
    obj_rows = 0
    obj_marked_rows = 0
    unresolved_bg_obj = []
    for map_id, per_map in pointers.items():
        if not isinstance(per_map, dict):
            continue
        for text_const, row in per_map.items():
            if "_BG_" not in text_const and "_OBJ_" not in text_const:
                continue
            bg_obj_rows += 1
            if not isinstance(row, dict):
                unresolved_bg_obj.append((map_id, text_const, "<not-table>"))
                continue
            if "_BG_" in text_const:
                bg_rows += 1
                if row.get("sign") is True:
                    bg_sign_rows += 1
            if "_OBJ_" in text_const:
                obj_rows += 1
                if row.get("objectEvent") is True:
                    obj_marked_rows += 1
            text_label = row.get("text")
            if not isinstance(text_label, str) or text_label not in texts:
                unresolved_bg_obj.append((map_id, text_const, text_label))

    if bg_obj_rows < 300:
        raise AssertionError(
            "Gen2 scaffold quality: too few BG/OBJ pointer rows "
            f"({bg_obj_rows})")

    if unresolved_bg_obj:
        preview = ", ".join(
            f"{map_id}:{const}->{label}"
            for map_id, const, label in unresolved_bg_obj[:5])
        raise AssertionError(
            "Gen2 scaffold quality: unresolved BG/OBJ text pointer links "
            f"({len(unresolved_bg_obj)}/{bg_obj_rows}); sample: {preview}")

    if bg_rows and bg_sign_rows / bg_rows < 0.90:
        raise AssertionError(
            "Gen2 scaffold quality: low BG sign-marker coverage "
            f"({bg_sign_rows}/{bg_rows})")

    if obj_rows and obj_marked_rows / obj_rows < 0.70:
        raise AssertionError(
            "Gen2 scaffold quality: low OBJ objectEvent-marker coverage "
            f"({obj_marked_rows}/{obj_rows})")

    trainer_header_maps = 0
    trainer_header_rows = 0
    if not isinstance(trainer_headers, dict):
        raise AssertionError(
            "Gen2 scaffold quality: trainer headers is not a table")
    for per_map in trainer_headers.values():
        if isinstance(per_map, dict) and per_map:
            trainer_header_maps += 1
            trainer_header_rows += len(per_map)

    if trainer_header_maps < 2:
        raise AssertionError(
            "Gen2 scaffold quality: too few maps with trainer headers "
            f"({trainer_header_maps})")

    if trainer_header_rows < 3:
        raise AssertionError(
            "Gen2 scaffold quality: too few trainer header rows "
            f"({trainer_header_rows})")

    sign_maps = 0
    sign_ready_maps = 0
    object_maps = 0
    object_ready_maps = 0
    weak_maps = []
    for map_id, map_row in maps_data.items():
        per_map = pointers.get(map_id, {})
        if not isinstance(per_map, dict):
            per_map = {}

        bg_rows_for_map = [
            row for key, row in per_map.items()
            if "_BG_" in key and isinstance(row, dict)
        ]
        obj_rows_for_map = [
            row for key, row in per_map.items()
            if "_OBJ_" in key and isinstance(row, dict)
        ]
        resolved_bg = sum(
            1 for row in bg_rows_for_map
            if isinstance(row.get("text"), str) and row["text"] in texts)
        resolved_obj = sum(
            1 for row in obj_rows_for_map
            if isinstance(row.get("text"), str) and row["text"] in texts)

        has_signs = bool(map_row.get("signs"))
        has_objects = bool(map_row.get("objects"))
        if has_signs:
            sign_maps += 1
            if resolved_bg > 0:
                sign_ready_maps += 1
            else:
                weak_maps.append(map_id)

        if has_objects:
            object_maps += 1
            if resolved_obj > 0:
                object_ready_maps += 1
            elif map_id not in weak_maps:
                weak_maps.append(map_id)

    print(
        "ok: Gen2 scaffold quality "
        f"(text pointer map coverage {mapped_pointer_maps}/{map_count}={coverage:.1%}, "
        f"rows={pointer_rows}; trainer header maps={trainer_header_maps}, "
        f"rows={trainer_header_rows}; bg/obj links={bg_obj_rows}; "
        f"bg sign markers={bg_sign_rows}/{bg_rows}; "
        f"obj markers={obj_marked_rows}/{obj_rows}; "
        f"map events warps={warp_rows}, "
        f"signs={sign_rows}, objects={object_rows})")
    weak_preview = ",".join(sorted(weak_maps)[:8]) if weak_maps else "none"
    print(
        "ok: Gen2 interaction readiness "
        f"(sign maps {sign_ready_maps}/{sign_maps}, "
        f"object maps {object_ready_maps}/{object_maps}, "
        f"weak maps={len(weak_maps)}, sample={weak_preview})")


def verify_gen2_phase2b(manifest, args):
    """Verify Gen2 Phase 2B manifests and currently supported datasets."""
    RomImage(args.rom, manifest["romSha1"])

    missing = sorted(GEN1_MANIFEST_KEYS - set(manifest.keys()))
    if missing:
        raise AssertionError(
            "Gen2 manifest is missing Gen1-compatible top-level keys: "
            + ", ".join(missing))

    symbols = manifest.get("symbols", {})
    if not symbols:
        raise AssertionError(
            "Gen2 manifest has no embedded symbols; run scripts/setup_gen2_symbols.ps1")

    if args.symbols:
        source_symbols = SymbolTable(args.symbols)
        for name, location in symbols.items():
            source_symbol = source_symbols.by_name.get(name)
            if source_symbol is None:
                raise AssertionError(f"source symbols missing embedded name: {name}")
            if location != [source_symbol.bank, source_symbol.address]:
                raise AssertionError(f"embedded symbol differs: {name}")

    with tempfile.TemporaryDirectory() as temp_dir:
        rom_assets = os.path.join(temp_dir, "rom-assets")
        rom_dir = os.path.join(temp_dir, "rom")
        os.makedirs(rom_assets, exist_ok=True)
        os.makedirs(rom_dir, exist_ok=True)

        supported = ("constants", "charmap", "moves", "items", "text", "maps")
        rom = RomImage(args.rom, manifest["romSha1"])
        embedded = SymbolTable(symbols)
        actual = build_rom_data.build(
            rom, embedded, manifest, rom_dir, rom_assets, supported)

        for name in supported:
            if name not in actual:
                raise AssertionError(f"missing generated dataset: {name}")
            out = os.path.join(rom_dir, f"{name}.lua")
            if not os.path.isfile(out):
                raise AssertionError(f"missing generated file: {out}")

        _verify_gen2_scaffold_quality(actual)

    print("ok: Gen2 Phase 2B manifest shape is compatible")
    print(f"ok: embedded symbols ({len(symbols)})")
    print("ok: generated datasets constants, charmap, moves, items, text, maps")
    return 0


def without_source(value):
    if isinstance(value, dict):
        return {
            key: without_source(item)
            for key, item in value.items()
            if key != "source"
        }
    if isinstance(value, list):
        return [without_source(item) for item in value]
    return value


def compare(name, expected, actual):
    expected = without_source(expected)
    actual = without_source(actual)
    if expected != actual:
        raise AssertionError(f"{name}: ROM output differs from source output")
    print(f"ok: {name}")


def compare_png_tree(name, expected_dir, actual_dir):
    def pngs(root):
        return sorted(
            os.path.relpath(os.path.join(parent, filename), root)
            for parent, _, filenames in os.walk(root)
            for filename in filenames
            if filename.endswith(".png")
        )

    expected_files = pngs(expected_dir)
    actual_files = pngs(actual_dir)
    if expected_files != actual_files:
        raise AssertionError(
            f"{name}: generated PNG file lists differ")
    for relative in expected_files:
        with Image.open(os.path.join(expected_dir, relative)) as expected, \
                Image.open(os.path.join(actual_dir, relative)) as actual:
            expected_rgba = expected.convert("RGBA")
            actual_rgba = actual.convert("RGBA")
            if expected_rgba.size != actual_rgba.size \
                    or expected_rgba.tobytes() != actual_rgba.tobytes():
                raise AssertionError(
                    f"{name}: pixels differ for {relative}")
    print(f"ok: {name} ({len(expected_files)} PNGs)")


def source_type_chart(pokered, temp_dir):
    matchups = type_chart.extract(pokered, temp_dir)
    names = []
    import re
    from extract.util import read_asm
    path = os.path.join(pokered, "data/types/names.asm")
    for _, line in read_asm(path):
        m = re.match(r'(?:\.\w+:\s*)?db\s+"([^"@]*)@?"', line.strip())
        if m:
            names.append(m.group(1))
    return {"matchups": matchups, "names": names}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", required=True)
    parser.add_argument("--symbols")
    parser.add_argument("--pokered")
    parser.add_argument(
        "--manifest",
        default=os.path.join(os.path.dirname(__file__), "rom_manifest.json"))
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)

    if manifest.get("generation") == 2 and manifest.get("stub"):
        return verify_gen2_phase2b(manifest, args)

    if not args.symbols or not args.pokered:
        raise SystemExit(
            "Gen1 verification requires --symbols and --pokered arguments")

    rom = RomImage(args.rom, manifest["romSha1"])
    source_symbols = SymbolTable(args.symbols)
    for name, location in manifest["symbols"].items():
        source_symbol = source_symbols[name]
        if location != [source_symbol.bank, source_symbol.address]:
            raise AssertionError(f"embedded symbol differs: {name}")
    symbols = SymbolTable(manifest["symbols"])
    with tempfile.TemporaryDirectory() as temp_dir:
        source_assets = os.path.join(temp_dir, "assets", "generated")
        rom_assets = os.path.join(temp_dir, "rom-assets")
        source_constants = constants.extract(args.pokered, temp_dir)
        source_tilesets = tilesets.extract(
            args.pokered, temp_dir, source_assets,
            source_constants["tilesetOrder"])
        source_maps = maps.extract(
            args.pokered, temp_dir, source_constants["maps"])
        source_font = font.extract(
            args.pokered, temp_dir, source_assets)
        source_sprites = sprites.extract(
            args.pokered, temp_dir, source_assets,
            source_constants["spriteOrder"])
        source_moves = moves.extract(
            args.pokered, temp_dir, source_constants["moveOrder"])
        source_battle_anims = battle_anims.extract(
            args.pokered, temp_dir, source_assets,
            source_constants["moveOrder"])
        source_items = items.extract(args.pokered, temp_dir)
        source_types = source_type_chart(args.pokered, temp_dir)
        source_palettes, source_mon_palettes = palettes.extract(
            args.pokered, temp_dir)
        source_icons_by_dex = icons.extract(
            args.pokered, temp_dir, source_assets)
        source_icons = {
            "byDex": source_icons_by_dex,
            "icons": {
                **icons.SPRITE_ICONS,
                **{
                    name: f"assets/generated/icons/{icons.SHEET_FILES[name]}.png"
                    for name in icons.SHEET_ICONS
                },
            },
        }
        source_palette_data = {
            "palettes": source_palettes,
            "order": manifest["paletteOrder"],
            "pokemon": source_mon_palettes,
        }
        source_pokemon = pokemon.extract(
            args.pokered, temp_dir, source_assets,
            source_constants["speciesOrder"])
        source_trainers = trainers.extract(
            args.pokered, temp_dir, source_assets)
        source_encounters = encounters.extract(
            args.pokered, temp_dir, source_constants["mapOrder"])
        source_texts, source_text_pointers = text.extract(
            args.pokered, temp_dir)
        source_text_values = {
            label: value["text"] for label, value in source_texts.items()
        }
        # This label intentionally falls through into _EndUsedMove1Text in
        # the ROM command stream.
        source_text_values["_MoveNameText"] += \
            source_text_values["_EndUsedMove1Text"]
        source_trainer_headers = text.parse_trainer_headers(args.pokered)
        source_field_dir = os.path.join(temp_dir, "data", "generated")
        os.makedirs(source_field_dir)
        source_field = field.extract(args.pokered, source_field_dir)

        rom_dir = os.path.join(temp_dir, "rom")
        os.makedirs(rom_dir)
        actual = build_rom_data.build(
            rom, symbols, manifest, rom_dir, rom_assets,
            build_rom_data.DATASETS)

        compare("constants", source_constants, actual["constants"])
        compare("tilesets", source_tilesets, actual["tilesets"])
        compare_png_tree(
            "tileset assets",
            os.path.join(source_assets, "tilesets"),
            os.path.join(rom_assets, "tilesets"))
        compare("maps", source_maps, actual["maps"])
        compare("font", source_font, actual["font"])
        compare_png_tree(
            "font assets",
            os.path.join(source_assets, "fonts"),
            os.path.join(rom_assets, "fonts"))
        compare("sprites", source_sprites, actual["sprites"])
        compare_png_tree(
            "sprite assets",
            os.path.join(source_assets, "sprites"),
            os.path.join(rom_assets, "sprites"))
        compare("moves", source_moves, actual["moves"])
        compare(
            "battle animations",
            source_battle_anims, actual["battle_anims"])
        compare("items", source_items, actual["items"])
        compare("type_chart", source_types, actual["type_chart"])
        compare("palettes", source_palette_data, actual["palettes"])
        compare("icons", source_icons, actual["icons"])
        compare_png_tree(
            "icon assets",
            os.path.join(source_assets, "icons"),
            os.path.join(rom_assets, "icons"))
        compare("pokemon", source_pokemon, actual["pokemon"])
        compare("trainers", source_trainers, actual["trainers"])
        compare_png_tree(
            "battle assets",
            os.path.join(source_assets, "battle"),
            os.path.join(rom_assets, "battle"))
        compare_png_tree(
            "trainer card assets",
            os.path.join(source_assets, "trainer_card"),
            os.path.join(rom_assets, "trainer_card"))
        compare("encounters", source_encounters, actual["encounters"])
        compare("text", source_text_values, actual["text"]["texts"])
        compare(
            "text pointers", source_text_pointers,
            actual["text"]["pointers"])
        compare(
            "trainer headers", source_trainer_headers,
            actual["text"]["trainerHeaders"])
        compare("field", source_field, actual["field"])
        compare_png_tree("all assets", source_assets, rom_assets)
    print("all implemented ROM datasets match the source-backed pipeline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
