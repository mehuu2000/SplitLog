# Task completion checklist
- Prefer validating behavior with `xcodebuild ... test` when changes affect stopwatch logic, persistence, settings, or UI bindings.
- If tests are too expensive for a tiny UI-only tweak, at least verify impacted code paths and mention test status explicitly.
- For persistence-related changes, check both normal save/load flow and restore normalization assumptions.
- Keep `README.md` and especially `SplitLog/memo.md` in sync when functionality meaningfully changes, because `memo.md` can lag behind the actual implementation.