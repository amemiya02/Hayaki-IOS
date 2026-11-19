import Foundation
import SQLite3

public struct RecentReviewTiming: Sendable {
    public struct Queue: Sendable {
        public let answerTimeMilliseconds: Double
        public let successRate: Double

        fileprivate init(time: Double, rate: Double) {
            answerTimeMilliseconds = time == 0 ? 20_000 : time
            successRate = rate == 0 ? 1 : rate
        }
    }

    public let new: Queue
    public let learning: Queue
    public let review: Queue
}

extension CollectionStore {
    /// Reads the revlog aggregate Android uses to estimate the time remaining.
    /// A read-only connection keeps the scheduler's mutable collection on its core worker.
    @concurrent
    public func recentReviewTiming(since cutoffMillis: Int64) async -> RecentReviewTiming? {
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(location.collectionFile.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard opened == SQLITE_OK else { return nil }

        let query = """
            SELECT avg(CASE WHEN type = 0 THEN time END),
                   avg(CASE WHEN type IN (1, 3) THEN time END),
                   avg(CASE WHEN type IN (1, 3) THEN ease > 1 END),
                   avg(CASE WHEN type = 2 THEN time END),
                   avg(CASE WHEN type = 2 THEN ease > 1 END)
            FROM revlog WHERE id > ?
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK,
              sqlite3_bind_int64(statement, 1, cutoffMillis) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return RecentReviewTiming(
            new: .init(time: sqlite3_column_double(statement, 0), rate: 1),
            learning: .init(time: sqlite3_column_double(statement, 1), rate: sqlite3_column_double(statement, 2)),
            review: .init(time: sqlite3_column_double(statement, 3), rate: sqlite3_column_double(statement, 4))
        )
    }
}
