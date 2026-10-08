"""Build Polished's voxel index profile from locally extracted comparison data.

Input directory: polished.json/crystal.json (tilesets), profile.json (the
authored mod profile), maps.json (Polished maps), output/assets from the native
extractor. Crystal's assets live at --crystal. No ROM artwork is emitted.
"""
import argparse
import copy
import json
from pathlib import Path
from PIL import Image


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(int(k) if str(k).isdigit() else k) + ']=' + lua(v)
                              for k, v in sorted(value.items(), key=lambda pair: str(pair[0]))) + '}'
    if isinstance(value, list):
        return '{' + ','.join(map(lua, value)) + '}'
    if isinstance(value, str):
        return json.dumps(value)
    if value is True: return 'true'
    if value is False: return 'false'
    if value is None: return 'nil'
    return str(value)


def build(prepared, crystal, target):
    def read(n): return json.loads((prepared / (n + '.json')).read_text())
    polished, original, profile, maps = map(read, ['polished', 'crystal', 'profile', 'maps'])
    def art(root, ts):
        im = Image.open(root / ts['image']).convert('RGBA')
        return [im.crop((x, y, x + 8, y + 8)).tobytes()
                for y in range(0, im.height, 8) for x in range(0, im.width, 8)]
    sources = {k: art(crystal, v) for k, v in original.items() if k in profile['tilesets']}
    family = {
        **{f'TilesetJohto{i}': ['TilesetJohto', 'TilesetJohtoModern'] for i in range(1, 6)},
        **{f'TilesetKanto{i}': ['TilesetKanto'] for i in [1, 2]},
        'TilesetHouse1': ['TilesetPlayersRoom', 'TilesetPlayersHouse', 'TilesetHouse'],
        'TilesetHouse2': ['TilesetHouse', 'TilesetPlayersHouse'],
        'TilesetHouse3': ['HOUSE'], 'TilesetGym1': ['TilesetEliteFourRoom'],
        'TilesetAlph': ['TilesetRuinsOfAlph'], 'TilesetRuins': ['TilesetRuinsOfAlph'],
        'TilesetPokeCenter': ['TilesetPokecenter'], 'TilesetPokecenter': ['TilesetPokecenter'],
        'TilesetPokeCom': ['TilesetPokecenter'],
    }
    scalar = {'heights', 'planter_spray', 'bookcase_relief', 'bookcase_backfill', 'hop_lips',
              'can_cap', 'can_base', 'can_height', 'can_well', 'can_taper', 'stump_cap'}
    special = {'when_above', 'when_below', 'when_cell', 'prop_bg', 'figures', 'mounted'}
    result = {'tilesets': {}, 'buildings': {}}
    reused = buildings = 0
    for name, ts in sorted(polished.items()):
        if not name.startswith('Tileset'): continue
        try: pixels = art(prepared / 'output', ts)
        except FileNotFoundError: continue
        # Empty entries matter: shared family names (Cave/Mart/Lab) must not
        # accidentally retain Crystal's old tile indices.
        entry, candidates, rules = {}, {}, {}
        templates = []
        choices = family.get(name, [name] if name in sources else [])
        for donor in choices:
            old = profile['tilesets'][donor]
            atlas = sources[donor]
            remap = {}
            for index, graphic in enumerate(atlas):
                matches = [i for i, drawing in enumerate(pixels) if drawing == graphic]
                # Uniform padding tiles are not scenery. Keep only a matching
                # slot; never spread a ground/void pin over all blank padding.
                shades = {graphic[i:i+4] for i in range(0, len(graphic), 4)}
                if len(shades) <= 1: matches = [index] if index in matches else []
                if matches: remap[index] = matches
            if name.startswith(('TilesetJohto', 'TilesetKanto')) and donor.startswith(('TilesetJohto', 'TilesetKanto')):
                # Both ROM loaders reserve VRAM 10..18 for map-group roofs;
                # their atlas placeholder shades differ before that overlay.
                for index in range(10, 19):
                    remap[index] = [index] + [int(tile) for tile,variant in ts.get('tileVariants',{}).items() if variant['base']==index]
            def ids(values):
                return sorted({n for v in values for n in remap.get(v, [])})
            for kind, value in old.items():
                if kind in scalar:
                    entry.setdefault(kind, copy.deepcopy(value))
                elif kind in special:
                    if kind.startswith('when_'):
                        for tile, rows in value.items():
                            for new_tile in remap.get(int(tile), []):
                                for row in rows:
                                    r = copy.deepcopy(row)
                                    side = kind[5:]
                                    if side != 'cell':
                                        r[side] = ids(row[side])
                                        if not r[side]: continue
                                    rules.setdefault(kind, {}).setdefault(new_tile, []).append(r)
                    elif kind == 'prop_bg':
                        for row in value:
                            r = copy.deepcopy(row); r['tiles'] = ids(row['tiles'])
                            if r['tiles']: entry.setdefault(kind, []).append(r)
                    # Pixel masks cannot be moved without verifying their full
                    # replacement drawing. No GSC donors here require masks.
                elif isinstance(value, list):
                    for tile in ids(value): candidates.setdefault(tile, set()).add(kind)
            # Discover actual grids in Polished's maps, so repeated/relocated
            # artwork uses the exact destination IDs, not a guessed alias.
            for template in profile['buildings'].get(donor, []):
                grid = template['tiles']; h, w = len(grid), len(grid[0])
                if any(v not in remap for row in grid for v in row): continue
                seen = set()
                for m in maps.values():
                    if m.get('tileset') != name: continue
                    mw, mh = m['width'] * 4, m['height'] * 4
                    blocks = ts.get('blocks', [])
                    def at(x, y):
                        b = m['blocks'][(y // 4) * m['width'] + x // 4]
                        if b >= len(blocks): return -1
                        return blocks[b][(y % 4) * 4 + x % 4]
                    for y in range(mh - h + 1):
                        for x in range(mw - w + 1):
                            if at(x, y) not in remap[grid[0][0]]: continue
                            if not all(at(x+c, y+r) in remap[v]
                                       for r, row in enumerate(grid) for c, v in enumerate(row)): continue
                            actual = tuple(tuple(at(x+c, y+r) for c in range(w)) for r in range(h))
                            if actual in seen: continue
                            seen.add(actual)
                            t = copy.deepcopy(template); t['tiles'] = [list(row) for row in actual]
                            if t.get('topRows'):
                                if any(v not in remap for row in t['topRows'] for v in row): continue
                                t['topRows'] = [[remap[v][0] for v in row] for row in t['topRows']]
                            t['id'] = 'polished_' + t['id'] + '_' + str(len(templates))
                            templates.append(t)
        if name.startswith(('TilesetJohto', 'TilesetKanto')):
            # Polished redraws windows, doors and siding. Its roof loader still
            # uses the same nine reserved tiles. Author the actual facade grid
            # under each complete rectangular roof instead of substituting old
            # Crystal windows. Roof height comes from its measured band count.
            seen = {tuple(tuple(row) for row in t['tiles']) for t in templates}
            for m in maps.values():
                if m.get('tileset') != name: continue
                mw, mh = m['width'] * 4, m['height'] * 4
                def at(x, y):
                    b = m['blocks'][(y // 4) * m['width'] + x // 4]
                    return ts['blocks'][b][(y % 4) * 4 + x % 4]
                def canonical(x,y):
                    tile=at(x,y)
                    return ts.get('tileVariants',{}).get(str(tile),{}).get('base',tile)
                for y in range(mh - 5):
                    for x in range(mw - 3):
                        bands = {16:(17,18,13,10,12),170:(171,172,186,202,204)}
                        band = bands.get(canonical(x,y))
                        if not band: continue
                        middle, right, side, foot, foot_right = band
                        end = x + 1
                        while end < mw and canonical(end, y) == middle: end += 1
                        if end >= mw or canonical(end, y) != right: continue
                        bottom = y + 1
                        while bottom < mh and canonical(x, bottom) == side: bottom += 1
                        if bottom + 2 >= mh or canonical(x, bottom) != foot or canonical(end, bottom) != foot_right: continue
                        width, roof = end - x + 1, bottom - y + 1
                        if width < 4 or roof not in (2, 4): continue
                        # Reject clipped facades, floor gaps or unrelated scenery.
                        facade = 2 if canonical(x,bottom+2)==0x36 and canonical(end,bottom+2)==0x36 else 4
                        if bottom+facade>=mh: continue
                        if any(canonical(x, bottom+r) != 0x26 or canonical(end, bottom+r) != 0x26 for r in range(1,facade)): continue
                        if canonical(x, bottom+facade) != 0x36 or canonical(end, bottom+facade) != 0x36: continue
                        grid = tuple(tuple(at(x+c,y+r) for c in range(width)) for r in range(roof+facade))
                        if grid in seen: continue
                        seen.add(grid)
                        templates.append({'id': 'polished_facade_' + str(len(templates)),
                                          'tiles': [list(row) for row in grid], 'roofRows': roof*8,
                                          'roofBack': 2, 'roofFront': 4, 'roofCycle': [2, roof*8-5],
                                          'slab': 4, 'frontEave': 4})
        # Complete modified civic roofs and landmarks from their actual ROM
        # grids. Exact art matching cannot transfer a redrawn emblem or door.
        if name.startswith('TilesetJohto'):
            def grid_at(m, x, y, w, h):
                def cell(c, r):
                    block=m['blocks'][(r//4)*m['width']+c//4]
                    return ts['blocks'][block][r%4*4+c%4]
                return [[cell(x+c,y+r) for c in range(w)] for r in range(h)]
            def add_grid(label, m, x, y, w, h, roof=32, extra=None):
                assert m['tileset']==name, (label,m['tileset'],name)
                if x<0 or y<0 or x+w>m['width']*4 or y+h>m['height']*4: return
                grid=grid_at(m,x,y,w,h)
                for t in templates:
                    if t['tiles']==grid:
                        t.setdefault('roles',[]).append('polished_'+label)
                        return
                row={'id':'polished_'+label,'tiles':grid,'roofRows':roof,
                     'roofBack':2,'roofFront':4,'roofCycle':[2,roof-5],
                     'slab':4,'frontEave':4,'seal':'s'}
                if extra: row.update(extra)
                templates.insert(0,row)
            for mapid,m in maps.items():
                if m.get('tileset')!=name: continue
                for n,warp in enumerate(m.get('warps',[])):
                    dest=warp.get('destMap','')
                    if ('POKE_CENTER1_F' in dest or dest.endswith('_MART')):
                        add_grid(mapid+'_civic_'+str(n),m,warp['x']*2-2,warp['y']*2-6,8,8,40)
            if name=='TilesetJohto2':
                add_grid('radio_west',maps['GOLDENROD_CITY'],16,8,4,24,16)
                add_grid('radio_east',maps['GOLDENROD_CITY'],20,20,4,12,16)
                add_grid('lighthouse',maps['OLIVINE_CITY'],64,16,8,24,32,{'roofFront':8})
                city=maps['GOLDENROD_CITY']
                for label,x,y,w,h in [('dept_store',52,40,12,16),('game_corner',32,36,12,8),
                                      ('pokecom',32,48,12,8),('museum',56,24,12,8),
                                      ('train_station',24,20,12,8),('gym',52,8,12,8),
                                      ('bike_shop',64,52,8,8)]:
                    add_grid('goldenrod_'+label,city,x,y,w,h)
                harbor=maps['GOLDENROD_HARBOR']
                for n,x in enumerate([28,40,52]):
                    add_grid('harbor_tent_'+str(n),harbor,x,24,8,8,16)
            if name=='TilesetJohto1':
                m=maps['VIOLET_CITY']; base=grid_at(m,44,0,8,4)
                # The map clips Sprout Tower at its northern edge. Restore the
                # roof and upper storeys above the matched four-row footprint.
                roof=grid_at(m,4,26,8,4)
                add_grid('sprout_tower',m,44,0,8,4,32,{'topRows':roof+base[:2]*6})
                city=maps['ECRUTEAK_CITY']
                for n,(x,y,w,h,roof) in enumerate([(8,30,8,6,32),(24,30,8,6,32),
                    (44,18,8,6,32),(24,50,8,6,32),(56,50,8,6,32),
                    (44,36,8,8,48),(8,4,8,8,48)]):
                    add_grid('ecruteak_pagoda_'+str(n),city,x,y,w,h,roof)
            if name=='TilesetJohto3':
                add_grid('azalea_kiln',maps['AZALEA_TOWN'],40,24,8,4,16)
                ruins=maps['RUINS_OF_ALPH_OUTSIDE']
                for n,(x,y,w,h) in enumerate([(16,12,12,8),(28,20,12,8),
                    (16,32,16,8),(4,40,20,8),(4,64,12,8),(32,72,12,8)]):
                    add_grid('alph_chamber_'+str(n),ruins,x,y,w,h,48)
            # The six-tile tree drawing and the four-tile sign are shared by
            # all five Johto families, even where their surrounding art differs.
            for tile in [30,31,46,47,62,63]: candidates[tile]={'cylinder'}
            for tile in [70,71,86,87]: candidates[tile]={'signpost'}
            rules.pop('when_below',None)
        if name=='TilesetKanto1':
            # Celadon's store and civic blocks use their own complete facade
            # drawings rather than Johto's interchangeable roof band.
            m=maps['CELADON_CITY']
            for label,x,y,w,h in [('dept_store',12,4,12,16),('decor_store',24,8,8,12),
                                  ('mansion',36,8,12,12),('game_corner',40,32,12,8),
                                  ('prize_room',52,32,8,8),('university',4,52,16,8),
                                  ('hotel',68,52,12,8),('center',64,12,8,8)]:
                grid=[]
                for r in range(h):
                    row=[]
                    for c in range(w):
                        xx,yy=x+c,y+r
                        block=m['blocks'][(yy//4)*m['width']+xx//4]
                        row.append(ts['blocks'][block][yy%4*4+xx%4])
                    grid.append(row)
                templates.insert(0,{'id':'polished_celadon_'+label,'tiles':grid,
                    'roofRows':32,'roofBack':2,'roofFront':4,'roofCycle':[2,27],
                    'slab':4,'frontEave':4})
        for tile, kinds in candidates.items():
            if len(kinds) == 1:
                entry.setdefault(next(iter(kinds)), []).append(tile); reused += 1
        for k, v in rules.items(): entry[k] = v
        for k,v in entry.items():
            if isinstance(v,list) and all(isinstance(n,int) for n in v): v.sort()
        result['tilesets'][name] = entry
        result['buildings'][name] = templates
        buildings += len(templates)
    sections = []
    for kind, roster in result.items():
        sections.append('  ' + kind + ' = {\n' + ''.join('    [' + lua(k) + '] = ' + lua(v) + ',\n'
                        for k,v in sorted(roster.items())) + '  },\n')
    target.write_text('-- Polished Crystal 3.2.3: verified matching artwork indices and map grids.\n'
                      '-- Generated by tools/ds_polished_profile.py; contains no artwork.\n'
                      'return {\n' + ''.join(sections) + '}\n')
    print(f'{len(result["tilesets"])} tilesets, {reused} pins, {buildings} building variants')


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('prepared', type=Path)
    p.add_argument('--crystal', required=True, type=Path); p.add_argument('--output', required=True, type=Path)
    args = p.parse_args(); build(args.prepared, args.crystal, args.output)
