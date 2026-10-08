import SwiftUI
import SwiftData

@main
struct StudyENApp: App {
    @State private var library = ChunkLibrary.load()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        .modelContainer(for: [ChunkProgress.self, StudyDay.self, PhaseExam.self, DrillProgress.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今天", systemImage: "sun.max") }
            LibraryView()
                .tabItem { Label("语块库", systemImage: "square.stack.3d.up") }
            StatsView()
                .tabItem { Label("进度", systemImage: "chart.bar") }
        }
    }
}
