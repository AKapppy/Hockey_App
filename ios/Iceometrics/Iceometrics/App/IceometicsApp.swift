import SwiftUI

@main
struct IceometicsApp: App {
    @StateObject private var homeViewModel = HomeViewModel(
        repository: AppEnvironment.makeRepository()
    )

    var body: some Scene {
        WindowGroup {
            RootView(homeViewModel: homeViewModel)
        }
    }
}
