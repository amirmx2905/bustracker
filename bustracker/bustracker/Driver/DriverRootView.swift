import SwiftUI

struct DriverRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            Tab("Trip", systemImage: "bus.fill") {
                DriverHomeView(profile: profile)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                DriverHistoryTabView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                DriverSettingsTabView(profile: profile)
            }
        }
        .tint(.neonBlue)
    }
}
