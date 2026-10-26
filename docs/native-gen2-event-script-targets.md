# Keep event-table pointers out of object bytecode

Crystal's unused Battle Tower hallway receptionist points at the start of
its own map-event table. The cartridge source declares that pointer in
[BattleTowerHallway.asm](https://github.com/pret/pokecrystal/blob/master/maps/BattleTowerHallway.asm).
The importer previously queued the event bytes as an NPC script, producing
a false script and an opcode desynchronisation.

Retain the event-table start alongside its bank in the internal event
reader. When an object's pointer identifies exactly that known table,
retain the object and omit its executable script binding. Other scene,
callback, coordinate, object and neighboring script targets keep their
normal decoder paths. No map-specific name or warning suppression is used.

A scoped stock-GSC cache revision rebuilds existing imports once; other
editions retain their previous marker.

The synthetic Gold/Silver/Crystal regression exercises the real event
reader and script extractor, plus the real cache-readiness gate: 55 checks, including valid code immediately
after the event table and an independent scene script.

An actual Crystal Rev0 before/after import into memory retains all 388 maps,
170 scenes, 103 callbacks, 114 coordinate scripts, 707 signs and 410 movement
definitions. Every one of the 5,038 retained scripts and all other map and
movement bindings compare identically. The one false script is excluded;
the reported desync count changes from one to zero.

This verifies import classification, not Battle Tower gameplay, complete
story support or GPU acceptance. No cartridge bytes, generated script
tables or private mod content are included in this contribution.
