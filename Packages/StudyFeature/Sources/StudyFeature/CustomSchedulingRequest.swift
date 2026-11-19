import AnkiProto
import Foundation

/// A single invocation of the collection's optional custom scheduling program.
struct CustomSchedulingRequest: Equatable, Sendable, Identifiable {
    let id = UUID()
    let cardID: Int64
    let statesJSON: String
    let contextJSON: String
    private let program: String

    init(program: String, queued: Anki_Scheduler_QueuedCards.QueuedCard) throws {
        self.program = program
        cardID = queued.card.id
        var states = queued.states
        states.current.customData = queued.card.customData
        statesJSON = try states.jsonString()
        contextJSON = try queued.context.jsonString()
    }

    /// The upstream API exposes proto JSON and a separate custom-data object for
    /// each grade. SwiftProtobuf omits scalar defaults, so restore their keys
    /// before invoking the program.
    var javascript: String {
        #"""
        const states = JSON.parse(statesJSON);
        const ctx = JSON.parse(contextJSON);
        ctx.deckName ??= "";
        ctx.seed = BigInt(ctx.seed ?? 0);
        const review = {scheduledDays: 0, elapsedDays: 0, easeFactor: 0, lapses: 0, leeched: false};
        const learning = {remainingSteps: 0, scheduledSecs: 0, elapsedSecs: 0};
        function defaults(normal) {
            if (!normal) return;
            if (normal.new) normal.new = {position: 0, ...normal.new};
            if (normal.learning) normal.learning = {...learning, ...normal.learning};
            if (normal.review) normal.review = {...review, ...normal.review};
            if (normal.relearning?.review) {
                normal.relearning.review = {...review, ...normal.relearning.review};
            }
            if (normal.relearning?.learning) {
                normal.relearning.learning = {...learning, ...normal.relearning.learning};
            }
        }
        const grades = ["again", "hard", "good", "easy"];
        for (const key of ["current", ...grades]) {
            const state = states[key];
            if (!state) continue;
            defaults(state.normal);
            defaults(state.filtered?.rescheduling?.originalState);
            if (state.filtered?.preview) {
                state.filtered.preview = {scheduledSecs: 0, finished: false, ...state.filtered.preview};
            }
        }
        function readCustomData() {
            try { return JSON.parse(states.current.customData); }
            catch (_) { return {}; }
        }
        const customData = Object.fromEntries(grades.map(grade => [grade, readCustomData()]));
        await (async (states, customData, ctx) => {
            \#(program)
        })(states, customData, ctx);
        for (const grade of grades) states[grade].customData = JSON.stringify(customData[grade]);
        return JSON.stringify(states);
        """#
    }
}
