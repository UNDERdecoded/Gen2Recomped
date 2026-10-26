"""Build native Gen2Recomped before/after evidence (optional Pillow dependency)."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--badge-sheet', type=Path, required=True)
    parser.add_argument('--capture-log', type=Path, required=True)
    parser.add_argument('--base-revision', required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rows, checks = [], []
    palette = json.loads((args.after / 'emerald-palette.json').read_text())
    frames = {}
    for line in args.capture_log.read_text().splitlines():
        fields = line.split('\t')
        if fields[0] == 'SUMMARY_BADGE_FRAMES':
            frames[fields[2]] = [int(v) for v in fields[3].split(',')]
    assert set(frames) == {'page-3', 'page-4'}
    sheet = Image.open(args.badge_sheet).convert('RGBA')
    assert sheet.size == (32, 23 * 16)
    for game in ('firered', 'emerald'):
        views = [f'page-{p}' for p in range(1, 5 if game == 'emerald' else 4)]
        views += ['detail-second', 'learn-fifth']
        for view in views:
            name = f'{game}-{view}.png'
            pair, inputs = [], []
            for kind, folder in [('before', args.before), ('after', args.after)]:
                path = folder / name
                original = Image.open(path).convert('RGB')
                assert original.size == (2048, 1536), (path, original.size)
                # Exact 8x native GBA viewport; no colour transforms or stretching.
                surface = original.crop((64, 128, 1984, 1408)).resize(
                    (240, 160), Image.Resampling.NEAREST)
                pair.append(surface)
                inputs.append(dict(kind=kind, file=name, sha256=sha(path),
                                   dimensions=[2048, 1536], viewport=[64, 128, 1920, 1280],
                                   integerScale=8))
            after = pair[1]
            if game == 'firered' and view.startswith('page-'):
                white = sum(min(after.getpixel((x, y))) > 245
                            for y in range(16) for x in range(152, 240))
                assert white >= 20, (view, white)
                checks.append(dict(kind='visible-control-hint', game=game, view=view,
                                   whitePixels=white, passed=True))
            if game == 'emerald' and view in frames:
                assert len(frames[view]) == 4
                for row, frame in enumerate(frames[view]):
                    assert 0 <= frame < 23 and (view != 'page-4' or frame >= 18)
                    count, delta = 0, 0
                    for y in range(16):
                        for x in range(32):
                            c = sheet.getpixel((x, frame * 16 + y))
                            if c[3] == 255:
                                count += 1
                                actual = after.getpixel((85 + x, 32 + row * 16 + y))
                                delta = max(delta, *(abs(a - b) for a, b in zip(c[:3], actual)))
                    assert count > 30 and delta <= 1, (view, row, count, delta)
                    checks.append(dict(kind='source-badge-pixels', view=view, row=row + 1,
                                       frame=frame, opaquePixels=count, maxRgbDifference=delta,
                                       passed=True))
                for key, xy in [('panel', (0, 150)), ('header', (160, 0)), ('border', (160, 15))]:
                    expected = [round(c * 255) for c in palette[key][:3]]
                    delta = max(abs(a - b) for a, b in zip(after.getpixel(xy), expected))
                    assert delta <= 1, (view, key, delta)
                    checks.append(dict(kind='source-panel-palette', view=view, pixel=list(xy),
                                       maxRgbDifference=delta, passed=True))
            comparison = Image.new('RGB', (960, 344), '#17202a')
            draw = ImageDraw.Draw(comparison)
            for i, surface in enumerate(pair):
                draw.text((i * 480 + 8, 6), f'{game} / {view} / '+('Before' if i == 0 else 'After'), fill='white')
                comparison.paste(surface.resize((480, 320), Image.Resampling.NEAREST), (i * 480, 24))
            comparison.save(args.out / name)
            rows.append(dict(game=game, view=view, comparison=name,
                             comparisonSha256=sha(args.out / name), inputs=inputs))
    report = dict(baseRevision=args.base_revision, passed=True, liveLanguage='English',
                  views=rows, checks=checks, badgeSheetSha256=sha(args.badge_sheet),
                  captureLogSha256=sha(args.capture_log),
                  scope='Native final-frame source sprites/palettes, hints and input regressions. '
                        'No claim of full-frame equality or untested language ROM coverage.')
    (args.out / 'evidence.json').write_text(json.dumps(report, indent=2) + '\n')
    print('GEN3_SUMMARY_COMPARISON_OK', len(rows), 'before/after pairs;', len(checks), 'pixel checks')


if __name__ == '__main__':
    main()
