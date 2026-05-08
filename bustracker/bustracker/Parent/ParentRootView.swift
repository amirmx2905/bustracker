import SwiftUI

struct ParentRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            Tab("Students", systemImage: "person.2.fill") {
                StudentsTabView(profile: profile)
            }
            Tab("Map", systemImage: "map.fill") {
                ParentMapTabView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                ParentHistoryTabView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                ParentSettingsTabView(profile: profile)
            }
        }
        .tint(.neonBlue)
    }
}
