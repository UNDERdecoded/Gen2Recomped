# Reuse dynamic shader programs at interpolation endpoints

Keep a qualified scalar float dynamic after a successful native write has
actually supplied a value strictly between 0 and 1. Later endpoints reuse that
runtime branch instead of compiling another endpoint-specialized program.
Independent bool flags still specialize. Original uniforms, arithmetic, native
send returns, texture ownership, graphics stacks and release remain intact.
Integer-valued modes outside the interval keep their prior treatment.

Qualification:

- The fork and actually offered public component each pass 118 real Metal
  checks on LOVE12/Apple M3. These include exact reference pixels across
  0 -> .25 -> 1 -> 0, an independent bool toggle, matrix/array updates,
  texture Lua release, native C stack lifetime, cutouts and macro shadows.
- The exact earlier native compiler policy in an owned control host produces
  the expected additional program at the endpoint. Its pixel comparisons
  pass; this counterexample concerns extra compilation, not incorrect pixels.
- The unchanged private consumer bddb51819c uses 8 observed continuous uniforms.
  In its real High Third-Person/rain view, the adapter retains 14 variants
  throughout 120 sampled plus 120 unprofiled warm frames. Its recorded compiler
  time stays 1.808914 seconds throughout those windows. The preceding policy
  grows from 15 to 21 variants and 5.527151 to 7.259581 recorded compiler seconds.
- In the matched sampled window the maximum drops from 3133.971 to 137.913 ms.
  Unprofiled warm mean is 56.532 ms (~17.7 FPS), draw 49.565 ms, update 5.151 ms;
  all 120 rows have distinct consecutive renderer ticks. The preceding warm
  mean is 59.712 ms. There are still 5368 indexed native draws and 9 mirror
  planes at 512x3456; reflection coverage remains 436255 pixels. This remains
  a throughput blocker. Startup/map-change stalls outside these windows
  require separate qualification; 60 FPS and OS-window acceptance remain open.
- Source 15dc92fc was used for that real consumer comparison. Current fork
  source 42abe561 includes main 1658cb05 with unchanged shader files and passes
  eight focused groups, including the new native RS option contracts 38/148.
  The preceding main a8833b35 combination passed all 252 native CPU groups.

Receipts: root Metal 5259b88625, offered Metal 9781e462f1, old-policy
counterexample 0f517b41cc, real consumer 40b62271cc, combined-main CPU 3683346023.
Quality and private source remain unchanged; only owned QA profiles are used.
The broader dead-body and argument-admission experiments are excluded.

Contributions by Roxas2712 under LICENSE-ROXAS2712.md; existing upstream and
third-party licences and rights remain intact.

Depends on the offered compiler/depth/macro stack (#337, #388, #389). Current
upstream-main composition and complete release qualification remain open.
