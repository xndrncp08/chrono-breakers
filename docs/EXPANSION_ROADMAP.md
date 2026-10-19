# Temporal expansion implementation roadmap

Baseline: clean main a0a4b47; 148 Lune tests, formatting, lint and strict analysis pass. No runtime packages. Historical Studio evidence covers solo, two and three players; it does not validate the expansion.

1. Authored map catalogue, contract validation, participant-only voting, lifecycle-safe world and marker replacement.
2. Free Infiltrator classes, fixed match loadouts, class skills and trade-offs; cooperative hacking, server-issued interactive challenges and Keeper counterplay.
3. Bounded, telegraphed temporal events with replicated deadlines, navigation and environmental changes, cleanup and accessible feedback.
4. Versioned XP, mastery, calendar challenges and cosmetic milestones inside the existing idempotent reward transaction.
5. Deployment/career dashboards, modernized shared surfaces, responsive HUD, cinematics and readable cross-device controls.
6. Regression and integration coverage, production builds, remote audit and release/rollback runbooks.

Each group is verified before commit and merged into integration/temporal-expansion. Final validated integration merges to main and is pushed. No publishing, experience-setting changes or Robux spending.

Scope reaches server pure rules, adapters/bootstrap, shared configs/contracts/types, client state/controllers/screens, test fixtures/harnesses and release docs. Preserve profile data and legitimate Git authorship. Schema migrations are forward-only; real DataStores and physical-device testing remain release gates until actually run.
