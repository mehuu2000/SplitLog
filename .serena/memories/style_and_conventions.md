# Style and conventions
- Code is organized by feature/layer with small SwiftUI component files under `Presentation/Views/SessionPopover/Components`.
- Naming uses clear Swift-style camelCase identifiers and explicit method names like `startSession`, `finishLap`, `updateLapMemo`, `restorePersistedState`.
- Models are mostly value types (`struct`, `enum`) with `Codable`, `Equatable`, `Sendable` where useful.
- State holders/stores are `@MainActor`-friendly observable classes using `@Published` (`StopwatchService`, `AppSettingsStore`).
- UI copy is Japanese. New user-facing strings should stay consistent with existing Japanese wording.
- The service layer favors guard-based control flow, explicit state transitions, and normalization on restore instead of implicit magic.
- Comments are sparse and only added around non-obvious behavior; follow that pattern.
- No project-local SwiftLint or SwiftFormat config was found, so preserve existing formatting style (4-space indentation, concise members, grouped computed properties/methods).