import SwiftUI

struct StatisticsPeriodPicker: View {
    @Binding var selection: StatisticsPeriod
    let label: Text
    var allowsAllTime = true

    var body: some View {
        Picker(selection: $selection) {
            ForEach(StatisticsPeriod.allCases.filter { allowsAllTime || $0 != .allTime }, id: \.self) { period in
                Text(period.title).tag(period)
            }
        } label: {
            label
        }
        .pickerStyle(.menu)
    }
}
