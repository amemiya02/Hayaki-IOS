import AnkiCore
import AnkiProto
import Foundation

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
    /// Reads Android's revlog aggregate using the core's existing SQLite connection.
    public func recentReviewTiming(since cutoffMillis: Int64) async -> RecentReviewTiming? {
        let query = ReviewTimingQuery(args: [cutoffMillis])
        guard let input = try? JSONEncoder().encode(query),
              let result = try? await core.runDbCommandProto(.with { $0.json = input }),
              let fields = result.result.rows.first?.fields, fields.count == 5 else { return nil }

        return RecentReviewTiming(
            new: .init(time: fields[0].doubleValue, rate: 1),
            learning: .init(time: fields[1].doubleValue, rate: fields[2].doubleValue),
            review: .init(time: fields[3].doubleValue, rate: fields[4].doubleValue)
        )
    }
}

private struct ReviewTimingQuery: Encodable {
    let kind = "query"
    let sql = """
        SELECT avg(CASE WHEN type = 0 THEN time END),
               avg(CASE WHEN type IN (1, 3) THEN time END),
               avg(CASE WHEN type IN (1, 3) THEN ease > 1 END),
               avg(CASE WHEN type = 2 THEN time END),
               avg(CASE WHEN type = 2 THEN ease > 1 END)
        FROM revlog WHERE id > ?
        """
    let args: [Int64]
    let firstRowOnly = true

    private enum CodingKeys: String, CodingKey {
        case kind, sql, args
        case firstRowOnly = "first_row_only"
    }
}
