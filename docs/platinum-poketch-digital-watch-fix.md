# Platinum Pokétch digital watch

The digital clock's numeral map refers to generic solid-color tiles 1 and 2. It was composed against watch-decoration tiles, producing fragments instead of numerals. The 320x72 resource also stores two compact blocks: eight digits in a 32-column block and two digits in an 8-column block, each nine rows high. Treating it as a 40-column row-major image scrambled the digit shapes.

Import now normalizes this specific map and composes it with the generic tile bank. The general screen recipe and dedicated Pokétch art agree. New ink records mark the normalized layout so it is not converted twice. Runtime drawing normalizes old cached ink without mutating it and uses the existing generic tile sheet; current caches do not need reimporting.

The digits keep their ROM size (4x9 tiles), placement (columns 3, 8, 15, 20; row 7), palette, and background colon. A visual preview using the existing cache showed clean 10:42 numerals. `tools/gen4_poketch_clock_check.lua` passes 26,380 checks, including all 1,440 times with old and fresh ink, numeral masks from the actual ROM, and importer recipes. The 49 Pokétch ROM checks, app checks, and Android touch checks pass as well.
