import Foundation

/// Schema migration scaffolding. Only schema v1 exists today; add a `case` to
/// `migrate(_:from:)` for each future version bump.
enum Migrations {
    enum MigrationError: Error, Equatable, LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "The data file uses schema version \(version), which this version of OnIt does not understand."
            }
        }
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    static func decodeSnapshot(from data: Data) throws -> Snapshot {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        let migrated = try migrate(data, from: probe.schemaVersion ?? 1)
        var snapshot = try Snapshot.makeDecoder().decode(Snapshot.self, from: migrated)
        snapshot.schemaVersion = Snapshot.currentSchemaVersion
        return snapshot
    }

    /// Upgrades raw JSON one version at a time until it reaches `Snapshot.currentSchemaVersion`.
    static func migrate(_ data: Data, from version: Int) throws -> Data {
        switch version {
        case Snapshot.currentSchemaVersion:
            return data
        // When v2 exists:
        // case 1:
        //     return try migrate(migrateV1toV2(data), from: 2)
        default:
            throw MigrationError.unsupportedVersion(version)
        }
    }
}
