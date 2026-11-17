import Foundation

/// Pure auto-archive logic: Done tasks completed more than `archiveAfterDays` ago get archived.
enum ArchiveSweeper {
    static func shouldArchive(_ task: TaskItem, now: Date, archiveAfterDays: Int) -> Bool {
        guard task.column == .done, task.archivedAt == nil, let completedAt = task.completedAt else {
            return false
        }
        let threshold = TimeInterval(archiveAfterDays) * 86_400
        return now.timeIntervalSince(completedAt) > threshold
    }

    /// Returns the swept task list and the IDs that were archived.
    static func sweep(
        _ tasks: [TaskItem], now: Date, archiveAfterDays: Int
    ) -> (tasks: [TaskItem], archived: [UUID]) {
        var archived: [UUID] = []
        let swept = tasks.map { task -> TaskItem in
            guard shouldArchive(task, now: now, archiveAfterDays: archiveAfterDays) else { return task }
            var task = task
            task.archivedAt = now
            archived.append(task.id)
            return task
        }
        return (swept, archived)
    }
}
