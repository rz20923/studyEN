import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]

    @State private var kind: ChunkKind = .phrasal
    @State private var search = ""

    private var progressByID: [String: ChunkProgress] {
        Dictionary(progresses.map { ($0.chunkID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let map = progressByID
        NavigationStack {
            List {
                Picker("类型", selection: $kind) {
                    ForEach(ChunkKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(library.scenes(of: kind), id: \.self) { scene in
                    let items = filtered(scene: scene)
                    if !items.isEmpty {
                        Section(scene) {
                            ForEach(items) { chunk in
                                NavigationLink(value: chunk) {
                                    row(chunk, progress: map[chunk.id])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("语块库")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink("发音") { PronGuideListView() }
                    NavigationLink("语序") { WordOrderRulesView() }
                }
            }
            .searchable(text: $search, prompt: "搜英文、中文或被替代的大词")
            .navigationDestination(for: Chunk.self) { ChunkDetailView(chunk: $0) }
        }
    }

    private func filtered(scene: String) -> [Chunk] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return library.chunks.filter { chunk in
            guard chunk.kind == kind, chunk.scene == scene else { return false }
            guard !q.isEmpty else { return true }
            return chunk.phrase.lowercased().contains(q)
                || chunk.meaning.contains(q)
                || (chunk.replaces?.lowercased().contains(q) ?? false)
        }
    }

    private func row(_ chunk: Chunk, progress: ChunkProgress?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chunk.phrase).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(chunk.meaning)
                    if let word = chunk.replaces {
                        Text(word).strikethrough()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(progress: progress)
        }
    }
}

struct StatusBadge: View {
    let progress: ChunkProgress?

    var body: some View {
        let (text, color): (String, Color) = {
            guard let p = progress else { return ("未学", .gray) }
            return p.isMastered ? ("已掌握", .green) : ("学习中", .orange)
        }()
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ChunkDetailView: View {
    let chunk: Chunk

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chunk.phrase).font(.title.bold())
                        Text(chunk.meaning).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpeakButton(text: chunk.phrase)
                }
                if let word = chunk.replaces {
                    LabeledContent("替代书面词", value: word)
                }
                LabeledContent("场景", value: chunk.scene)
            }
            Section("例句") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chunk.example).font(.body.weight(.medium))
                    Text(chunk.exampleZh).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    SpeakButton(text: chunk.example)
                    SpeakButton(text: chunk.example, slow: true)
                }
            }
            Section("怎么读（点单词看嘴型）") {
                PronLineView(key: chunk.id + ":p", showNotes: false)
                PronLineView(key: chunk.id)
            }
            if let tip = chunk.tip {
                Section("用法提示") { Text(tip) }
            }
        }
        .navigationTitle(chunk.phrase)
        .navigationBarTitleDisplayMode(.inline)
    }
}
