"""Exact-ROM symbol profiles for the two field-move tilemaps.

Primary declarations: pret/{pokefirered,pokeemerald,pokeruby}/src/field_effect.c.
Offsets are identified file positions, never a cross-edition relocation guess.
"""
ROWS = {
    '41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc': ('pokefirered', (0x3CB5F0, 0x3CB7F0, 0x3CB810), (0x3CBA90, 0x3CBB10, 0x3CBB30)),
    '574fa542ffebb14be69902d1d36f1ec0a4afd71e': ('pokefirered', (0x3CB42C, 0x3CB62C, 0x3CB64C), (0x3CB8CC, 0x3CB94C, 0x3CB96C)),
    'f3ae088181bf583e55daf962a92bb46f4f1d07b7': ('pokeemerald', (0x55AE50, 0x55B050, 0x55B070), (0x55B2F0, 0x55B370, 0x55B390)),
    'f28b6ffc97847e94a6c21a63cacf633ee5c8df1e': ('pokeruby', (0x39E914, 0x39EB14, 0x39EB34), (0x39EDB4, 0x39EE34, 0x39EE54)),
    '3ccbbd45f8553c36463f13b938e833f652b793e4': ('pokeruby', (0x39E75C, 0x39E95C, 0x39E97C), (0x39EBFC, 0x39EC7C, 0x39EC9C)),
}


def field_move_profile(sha1):
    row = ROWS.get(sha1)
    if row is None:
        return None
    return {
        'schema': 1, 'romSha1': sha1,
        'source': f'https://github.com/pret/{row[0]}/blob/master/src/field_effect.c',
        'strips': {
            name: dict(zip(('tiles', 'palette', 'tilemap', 'tileCount'), (*offsets, count)))
            for name, offsets, count in (('outdoors', row[1], 16), ('indoors', row[2], 4))
        },
    }
