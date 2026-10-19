# Temporal expansion release checklist

Checked entries have current automated evidence; unchecked entries require live verification.

- [x] Lune unit/integration regression, including twenty five-player model matches
- [x] StyLua formatting, Selene lint and Luau strict analysis
- [x] Production/test Rojo builds and production artifact isolation/compilation check
- [x] All four map contracts, closed-gate access and temporary-fracture routes
- [x] Versioned profile migration and stale-session/duplicate-reward regression tests
- [x] Explicit production LoadStringEnabled=false; no Tests/E2EClient in production
- [ ] Run the new Studio expansion suite with two and five clients; save fresh logs
- [ ] Run legacy solo/two-player/squad regressions on the updated build
- [ ] Walk all maps from all four Infiltrator spawns and the Keeper spawn
- [ ] Review cameras, signals, signage, portals, fractures and hit feedback in player view
- [ ] Phone landscape/portrait, tablet, physical phone, gamepad and accessibility passes
- [ ] Published test universe: real DataStore round trip, v2→v3 migration, session conflict,
      rapid reconnect, shutdown, throttling, lock-loss UI and duplicate calendar rewards
- [ ] Twenty engine matches: stable runtime/connection/attachment counts and memory after warm-up
- [ ] Measure five-player server/client/network performance against the documented targets
- [ ] Review movement tolerance under latency, slowing, dashes, low gravity and portals
- [ ] Confirm separate test universe, max players 5, correct DataStore name and owner-approved settings
- [ ] Record release commit and previous place version; review schema-v3 rollback consequences
- [ ] Obtain explicit authorization before publishing, changing live settings or spending Robux

Procedures and unresolved limits: [EXPANSION_RELEASE](EXPANSION_RELEASE.md).
