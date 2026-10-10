import SwiftUI
import SwiftData

@main
struct StudyENApp: App {
    @State private var library = ChunkLibrary.load()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [ChunkProgress.self, StudyDay.self, PhaseExam.self, DrillProgress.self, EnduranceSet.self, StuckNote.self, TopicProgress.self])
    }
}

/// 三个标签：训练（打开即练）/ 课题 / 我的
struct RootView: View {
    var body: some View {
        TabView {
            TrainView()
                .tabItem { Label("训练", systemImage: "square.stack.3d.up.fill") }
            TopicsView()
                .tabItem { Label("课题", systemImage: "square.grid.2x2") }
            MeView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Theme.ink)
    }
}
