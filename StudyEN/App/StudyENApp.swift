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

/// 四个标签：训练（打开即练）/ 词组闯关 / 课题 / 我的
struct RootView: View {
    @AppStorage(UserName.key) private var name = ""
    @State private var askName = false

    var body: some View {
        TabView {
            TrainGate()
                .tabItem { Label("训练", systemImage: "square.stack.3d.up.fill") }
            PhraseHubView()
                .tabItem { Label("词组", systemImage: "gamecontroller.fill") }
            TopicsView()
                .tabItem { Label("课题", systemImage: "square.grid.2x2") }
            MeView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Theme.ink)
        .onAppear { askName = name.trimmingCharacters(in: .whitespaces).isEmpty }
        .fullScreenCover(isPresented: $askName) { NameOnboardingView() }
    }
}
