import SwiftUI

/// How the Statistics section appears in the tab bar and sidebar.
public enum StatisticsSection {
    public static var title: Text { Text("Statistics", bundle: .module) }
    public static let systemImage = "chart.bar"
}
