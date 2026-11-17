import Observation

/// Calls `apply` now and again whenever any observable property it reads changes.
/// Used by AppKit controllers (status item badge, panel width) that aren't SwiftUI views.
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeContinuously(apply) }
    }
}
