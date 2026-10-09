# tools/

| File | Purpose |
| --- | --- |
| `test.sh` | Builds `build/test.rbxl` from `test.project.json` and runs every spec with Lune. Exit code is non-zero on any failure. Optional arg filters spec names. |
| `run-tests.luau` | Lune harness: deserialises the Rojo-built place and executes ModuleScripts from their real instance tree with `script`, `require`, `game`, `task`, and Roblox datatypes injected. |
| `analyze.sh` | StyLua `--check`, Selene (`std = "roblox"`), and `luau-lsp analyze` in strict mode against Roblox API definitions (downloaded once into `.cache/`). |

Limitations: the Lune harness has no physics, characters, networking, or DataStores. Anything that
needs the engine is covered by the manual matrix in `docs/TEST_PLAN.md`.
