# Gen2 registry contracts

The `apricorns`, `decorations`, `landmarks`, `phone_contacts` and
`radio_channels` record descriptors match the pinned `535a5ec` Gen2 contract.
Their native adapters, imported built-ins, merge ownership and rollback already
exist; this change aligns the remaining descriptor bounds without replacing
those implementations. Gen3 decoration and landmark adapters are outside this
Gen2 contract.

Record validation and native execution have separate constraints. Native phone
indices remain 1..255 with original rows and holes reserved; landmark indices
remain bytes. Native apricorn event operands and decoration ownership events
remain 0..65534; 65535 has a variable-operand meaning in native scripts.
Apricorn ordering indices remain 1..65535. The adapters reject these unsupported
values before recording the contribution, so errors remain attributable and
earlier writes by the same failed owner roll back. Finite-value, reference,
collision and canonical-ID checks remain in place.

Landmark coordinates retain their existing native OAM units. This change does
not reinterpret previously authored records. Public record fields, merge
semantics and existing valid registrations keep their behavior.

Run `tools/check_gen2_registry_contract.py --reference <clean pinned checkout>
--lua <luajit> --report <qa path>/fields.json` to compare the complete Gen2
field descriptors, including optionality, bounds and referenced registries.
The same owned inspector runs unchanged in both checkouts. Native content
suites separately exercise the real Loader, merge targets and consumers.

This is load-time validation. It adds no per-frame operation or performance
flag. ARM performance has not been measured.
