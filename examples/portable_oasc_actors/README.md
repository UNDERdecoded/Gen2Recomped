# Portable actor billboard reference

Reusable public-only source for OASC consumers; not the private OASC mod and not
installed automatically. See [the contract and test guide](../../docs/gen3-actor-render-data-v1.md).

No terrain/world-pass dependency is required to use the actor handle. A combined
OASC world renderer additionally uses the terrain contract (#136) and portable
world-pass frame (#137). This example does not implement all actor effects,
native layer priorities or legacy animation-clock ownership.
