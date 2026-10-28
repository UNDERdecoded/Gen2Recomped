# Cartridge-native ball send-out import

FireRed and LeafGreen imported ball art but no send-out timing: the default
operand profile read Emerald instruction addresses. Real scene `a221bb6033`
confirmed both native send-out requests refused despite valid battler sprite
geometry. The scene completed, but its empty ball observations were explicitly
rejected as flight acceptance.

Use one detached, SHA-1-selected FR/LG instruction profile, checked against
matching pret/pokefirered ELFs at ce6406d8c2eaf46d543c8a2606de0c3cb1951982.
The existing native decoder still validates each instruction and matching target
offsets. Explicit caller and manifest profiles keep precedence; unknown hashes
cannot borrow this profile. Read the actual normal hand (48,70) and tutorial
hand (32,64), selecting the latter only for the actual player tutorial send-out.
The existing ball clock, queue wait, catch math and native renderer stay intact.
Only generated FR/LG import caches receive a revision marker; save formats do
not change. No private controller implementation is included.

Local validation:

- `native_ball_sendout_import.lua`:142 checks, including opcode refusal,
  detached profile isolation, tutorial selection and edition-scoped cache
  upgrades. Synthetic image centres qualify factory/queue ownership, not art.
- Frozen current-main composition `1ce0584258`:180 CPU groups pass on main
  `c548cd16`. Focused run `fabe63d246`:10 groups pass.
- Actual cartridge/ELF audit and native operand import `e4c340227f`:55 checks
  pass across five GBA editions. FR/LG change from missing to valid send-out;
  Emerald/Ruby/Sapphire before/after timing is identical. Image writing was
  disabled in this operand-only test; it is not rendered-pixel acceptance.
- Older-public composition `e2cbe1b740`:68 groups pass, including142 new checks.
  It retains the previously offered cartridge/art/stage prerequisites and old
  native controller bodies. The raw older branch lacks the complete LeafGreen
  manifest and RS art prerequisites; full cartridge integration needs those
  separately offered components.
- Real Metal FireRed run `b3d97aa123`, unchanged private consumer `bddb5181`:
  both native send-outs are accepted, with69 native clock/position/draw rows,
  and no loader errors. Frame captures expose a second issue: the source
  renderer paints its fitted ball and its opening-effect call also paints the
  complete native ball. This import change does not solve that duplicate or
  constitute final visual flight/size acceptance. Earlier failed probes and
  their receipts remain preserved.

Hosted CI is separate. Tests use owned copies/profiles with a20GiB free-space
floor. Private mod files and player saves/profiles remain untouched.
