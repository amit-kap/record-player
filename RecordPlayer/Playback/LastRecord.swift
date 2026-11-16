import Foundation

/// Remembers which record was on the platter, so the app starts with it there.
enum LastRecord {
    private static let key = "lastRecord"
    /// Stored when the platter was left empty.
    private static let empty = "none"

    /// The record to start with: `preferred` when given, otherwise the saved one, otherwise the first record. A saved
    /// empty platter stays empty. With `--empty` (debug) the platter starts empty for that launch only.
    static func initial(from records: [Record], preferred: Record? = nil) -> Record? {
        #if DEBUG
        if CommandLine.arguments.contains("--empty") { return nil }
        #endif
        if let preferred { return preferred }
        guard let saved = UserDefaults.standard.string(forKey: key) else { return records.first }
        if saved == empty { return nil }
        return records.first { $0.id == saved } ?? records.first
    }

    /// Call when the user loads a record, or empties the platter with nil.
    static func save(_ record: Record?) {
        UserDefaults.standard.set(record?.id ?? empty, forKey: key)
    }
}
