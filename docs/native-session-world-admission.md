# Persistent native world admission

Native session observations resolve an explicit entry-world scope first,
then a world stored in the physical state list, then that stack's admitted
`worldState`. A persistent world is independent of the overlay list; an empty
list or a covering menu does not remove its map/player observations.

Input still belongs to the native stack's active state. An uncovered
persistent world accepts input; a covering menu keeps it, including when
that menu is hidden only for rendering. Dataset/map identity checks remain
required. A modern empty stack cannot revive an unadmitted `game.overworld`
pointer. Legacy tool hosts without a physical state list keep their explicit
world fallback.

The initial five-edition regression reproduced 50 failed assertions. The
expanded suite passes 150 checks. It uses the actual native StateStack and player
with synthetic map data, including native field-move entry/retirement over a
persistent world, covering UI, stale datasets and failed entry scopes. This
does not establish original mod initialization, full rendering or gameplay.

The manual `tools/session-runtime/persistent-world-check.lua` requires the
native persistent-world StateStack protocol, the session fixture and native
field-move presentation. The current upstream API-2 prerequisite composition
does not yet provide that StateStack protocol. Its ordinary physical-stack
path is qualified separately; the 150 persistent-world checks above refer
to the composed native fork, not that older host.
