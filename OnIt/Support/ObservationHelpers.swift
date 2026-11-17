import Observation

/// Calls `apply` now and whenever an observable value it read changes (for AppKit controllers).
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) { Task { @MainActor in observeContinuously(apply) } }
}
