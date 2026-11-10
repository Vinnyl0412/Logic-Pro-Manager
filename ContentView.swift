import SwiftUI



private enum LibrarySection: String, CaseIterable, Identifiable {

    case all = "All Projects", favorites = "Favorites"

    var id: String { rawValue }

    var symbol: String {

        switch self { case .all: return "square.stack"; case .favorites: return "star" }

    }

}



struct ContentView: View {

    @EnvironmentObject private var store: ScoreStore

    @State private var section: LibrarySection = .all

    @State private var selectedID: String?

    @State private var selectedFolder: URL?

    @State private var selectedCollection: UUID?

    @State private var tagFilter: UUID?

    @State private var showManager = false

    @State private var query = ""

    @State private var genreFilter = "All"

    @State private var categoryFilter = "All"

    @State private var statusFilter = "All"

    @State private var sort: ScoreSort = .modified

    @State private var ascending = false

    @State private var dateFrom: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

    @State private var dateTo = Date()

    @State private var dateFilter = false

    @State private var dateField = "Modified"

    @State private var showAdvanced = true



    private var genres: [String] { ["All"] + Array(Set(store.files.map { store.info($0).genre })).sorted() }

    private var categories: [String] { ["All"] + Array(Set(store.files.map { store.info($0).category })).sorted() }

    private var statuses: [String] { ["All"] + Array(Set(store.files.map { store.info($0).status })).sorted() }



    private var results: [ScoreFile] {

        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return store.files.filter { file in

            let meta = store.info(file)

            if let selectedFolder {

                let folderPath = selectedFolder.standardizedFileURL.path

                if file.url.deletingLastPathComponent().standardizedFileURL.path != folderPath &&

                   !file.url.standardizedFileURL.path.hasPrefix(folderPath + "/") { return false }

            }

            if let selectedCollection, !meta.collectionIDs.contains(selectedCollection) { return false }

            if let tagFilter, !meta.colorTagIDs.contains(tagFilter) { return false }



            if section == .favorites && !meta.favorite { return false }

            if genreFilter != "All" && meta.genre != genreFilter { return false }

            if categoryFilter != "All" && meta.category != categoryFilter { return false }

            if statusFilter != "All" && meta.status != statusFilter { return false }

            if dateFilter {

                let date = dateField == "Created" ? file.created : file.modified

                let start = Calendar.current.startOfDay(for: dateFrom)

                let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo)) ?? dateTo

                if date < start || date >= end { return false }

            }

            let haystack = [file.title, file.url.path, file.fileExtension, file.format.rawValue, meta.genre, meta.category, meta.instrumentation, meta.composer, meta.status, meta.keywords, meta.notes,

                store.colorTags.filter { meta.colorTagIDs.contains($0.id) }.map(\.name).joined(separator: " "),

                store.collections.filter { meta.collectionIDs.contains($0.id) }.map(\.name).joined(separator: " ")].joined(separator: " ").lowercased()

            return terms.allSatisfy { haystack.contains($0) }

        }.sorted { a, b in

            let result: Bool

            switch sort {

            case .modified: result = a.modified < b.modified

            case .created: result = a.created < b.created

            case .title: result = a.title.localizedStandardCompare(b.title) == .orderedAscending

            case .size: result = a.bytes < b.bytes

            case .genre: result = store.info(a).genre.localizedStandardCompare(store.info(b).genre) == .orderedAscending

            }

            if a.id == b.id { return false }

            let reverse: Bool

            switch sort {

            case .modified: reverse = a.modified > b.modified

            case .created: reverse = a.created > b.created

            case .title: reverse = a.title.localizedStandardCompare(b.title) == .orderedDescending

            case .size: reverse = a.bytes > b.bytes

            case .genre: reverse = store.info(a).genre.localizedStandardCompare(store.info(b).genre) == .orderedDescending

            }

            return ascending ? result : reverse

        }

    }



    private var selected: ScoreFile? { store.files.first { $0.id == selectedID } }



    var body: some View {
        NavigationSplitView {
            sidebarContent
        } content: {
            browserContent
        } detail: {
            inspectorContent
        }
        .sheet(isPresented: $showManager) {
            OrganizationManager().environmentObject(store)
        }
        .alert("File operation failed", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var sidebarContent: some View {


            List(selection: $section) {

                Section("Libraries") {

                    ForEach(LibrarySection.allCases) { item in

                        Label(item.rawValue, systemImage: item.symbol)

                            .tag(item)

                            .onTapGesture { selectedCollection = nil }

                    }

                }

                Section("My Collections") {

                    ForEach(store.collections) { collection in

                        HStack {

                            Image(systemName: "folder.fill").foregroundStyle(Color(hex: collection.hex))

                            Text(collection.name).lineLimit(1)

                            Spacer()

                            if selectedCollection == collection.id { Image(systemName: "checkmark") }

                        }

                        .contentShape(Rectangle())

                        .onTapGesture { selectedCollection = collection.id; selectedFolder = nil; section = .all }

                        .contextMenu {

                            Button("Remove collection", role: .destructive) { store.deleteCollection(collection.id); if selectedCollection == collection.id { selectedCollection = nil } }

                        }

                    }

                    Button { showManager = true } label: { Label("Manage collections & tags", systemImage: "plus.circle") }

                        .buttonStyle(.borderless)

                }

                Section("Indexed folders") {

                    ForEach(store.folders, id: \.self) { folder in

                        HStack {

                            Image(systemName: "folder")

                            Text(folder.lastPathComponent).lineLimit(1)

                            Spacer()

                            if selectedFolder == folder { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }

                            Button { store.removeFolder(folder) } label: { Image(systemName: "minus.circle") }

                                .buttonStyle(.borderless).help("Remove from index (does not delete files)")

                        }

                        .contentShape(Rectangle())

                        .onTapGesture { selectedFolder = folder; selectedCollection = nil; section = .all }

                        .help("Show only projects under " + folder.path)

                    }

                }

            }

            .navigationTitle("Logic Project Library")

            .toolbar {

                Button { store.addFolders() } label: { Label("Add Folder", systemImage: "folder.badge.plus") }

                Button { showManager = true } label: { Label("Organize", systemImage: "tag") }

            }

    }

    private var browserContent: some View {


            VStack(spacing: 0) {

                VStack(alignment: .leading, spacing: 10) {

                    HStack {

                        TextField("Search title, composer, instrument, genre, tags, notes, path…", text: $query)

                            .textFieldStyle(.roundedBorder)

                        Button { showAdvanced.toggle() } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }

                        Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }

                            .help("Rescan folders")

                    }

                    if showAdvanced {

                        HStack {

                            Picker("Genre", selection: $genreFilter) { ForEach(genres, id: \.self) { Text($0) } }

                            Picker("Category", selection: $categoryFilter) { ForEach(categories, id: \.self) { Text($0) } }

                            Picker("Status", selection: $statusFilter) { ForEach(statuses, id: \.self) { Text($0) } }

                        }

                        HStack {

                            Picker("Color tag", selection: $tagFilter) {

                                Text("All tags").tag(nil as UUID?)

                                ForEach(store.colorTags) { tag in Text(tag.name).tag(Optional(tag.id)) }

                            }

                            if selectedCollection != nil {

                                Button("All collections") { selectedCollection = nil }

                            }

                            if let selectedFolder {

                                Text("Folder: " + selectedFolder.lastPathComponent).font(.caption)

                                Button("Clear folder") { self.selectedFolder = nil }

                            }

                        }

                        HStack {

                            Picker("Sort", selection: $sort) { ForEach(ScoreSort.allCases) { Text($0.rawValue).tag($0) } }

                            Toggle("Ascending", isOn: $ascending)

                            Spacer()

                            Toggle("Date range", isOn: $dateFilter)

                        }

                        if dateFilter {

                            HStack {

                                Picker("Date field", selection: $dateField) { Text("Modified").tag("Modified"); Text("Created").tag("Created") }

                                DatePicker("From", selection: $dateFrom, displayedComponents: .date)

                                DatePicker("To", selection: $dateTo, displayedComponents: .date)

                            }

                        }

                    }

                }.padding(12)

                Divider()

                HStack {

                    Text("\(results.count) projects").font(.caption).foregroundStyle(.secondary)

                    if store.scanning { ProgressView().controlSize(.small); Text("Scanning…").font(.caption) }

                    Spacer()

                    Button("Reset filters") { query = ""; genreFilter = "All"; categoryFilter = "All"; statusFilter = "All"; dateFilter = false; tagFilter = nil; selectedCollection = nil; selectedFolder = nil }

                        .buttonStyle(.link)

                }.padding(.horizontal, 12).padding(.vertical, 7)

                List(selection: $selectedID) {

                    ForEach(results) { file in

                        ScoreListRow(file: file)
                        .environmentObject(store)
                    .padding(.vertical, 5)

                        .tag(file.id)

                        .contextMenu {

                            Button("Open Project") { store.open(file) }

                            Button("Reveal in Finder") { store.reveal(file) }

                            Button("Duplicate Project") { store.duplicate(file) }

                            Divider()

                            Button("Move to Folder…") { store.moveToFolder(file) }

                        }

                    }

                }

                .overlay {

                    if results.isEmpty && !store.scanning {

                        ContentUnavailableView("No matching projects", systemImage: "doc.text.magnifyingglass", description: Text("Add a folder or change your search filters."))

                    }

                }

            }

            .navigationTitle(section.rawValue)

    }

    @ViewBuilder
    private var inspectorContent: some View {


            if let file = selected {

                ScoreInspector(file: file)

                    .id(file.id)

            } else {

                ContentUnavailableView("Select a project", systemImage: "music.note.list", description: Text("Select a Logic Pro project to view details and edit library tags."))

            }

    }
}



private struct ScoreListRow: View {
    @EnvironmentObject private var store: ScoreStore
    let file: ScoreFile

    var body: some View {
                    HStack(spacing: 12) {

                            Image(systemName: "waveform")

                                .font(.title2).foregroundStyle(Color.purple)

                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {

                                Text(file.title).fontWeight(.medium).lineLimit(1)

                                Text("\(file.format.rawValue) · \(store.info(file).genre) · \(store.info(file).category)")

                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)

                            }

                            HStack(spacing: 4) {

                                ForEach(store.colorTags.filter { store.info(file).colorTagIDs.contains($0.id) }) { tag in

                                    Circle().fill(Color(hex: tag.hex)).frame(width: 10, height: 10).help(tag.name)

                                }

                            }

                            Spacer()

                            if store.info(file).favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }

                            VStack(alignment: .trailing, spacing: 3) {

                                Text(file.modified, style: .date)

                                Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))

                                    .foregroundStyle(.secondary)

                            }.font(.caption)

                        }

        }
}

private struct ScoreInspector: View {

    @EnvironmentObject private var store: ScoreStore

    let file: ScoreFile

    @State private var draft = ScoreMetadata()

    @State private var newFileName = ""



    var body: some View {
        Form {
            scoreSection
            audioSection
            metadataSection
            colorTagsSection
            collectionsSection
            fileManagementSection
        }
        .formStyle(.grouped)
        .navigationTitle("Details")
        .onAppear {
            draft = store.info(file)
            newFileName = file.title
        }
        .onChange(of: draft) { _, newValue in
            store.update(file, newValue)
        }
    }

    private var scoreSection: some View {
            Section("Logic project") {

                Text(file.title).font(.headline).textSelection(.enabled)

                LabeledContent("Format", value: "\(file.format.rawValue) (.\(file.fileExtension))")

                LabeledContent("Created") { Text(file.created, style: .date) }

                LabeledContent("Last edited") { Text(file.modified, style: .date) }

                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))

                Text(file.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

            }

    }

    private var audioSection: some View {
        AudioPreviewSection(file: file)
    }

    private var metadataSection: some View {
            Section("Library metadata") {

                TextField("Genre", text: $draft.genre)

                TextField("Category (e.g. Film Score)", text: $draft.category)

                TextField("Composer", text: $draft.composer)

                TextField("Instrumentation", text: $draft.instrumentation)

                Picker("Status", selection: $draft.status) {

                    ForEach(["Idea", "In Progress", "Revision", "Completed", "Archived"], id: \.self) { Text($0) }

                }

                TextField("Tags (comma separated)", text: $draft.keywords)

                Toggle("Favorite", isOn: $draft.favorite)

                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...5)

            }

    }

    private var colorTagsSection: some View {
            Section("Color tags") {

                if store.colorTags.isEmpty { Text("Create tags using Organize in the sidebar.").foregroundStyle(.secondary) }

                ForEach(store.colorTags) { tag in

                    Toggle(isOn: Binding(

                        get: { draft.colorTagIDs.contains(tag.id) },

                        set: { enabled in

                            if enabled && !draft.colorTagIDs.contains(tag.id) { draft.colorTagIDs.append(tag.id) }

                            if !enabled { draft.colorTagIDs.removeAll { $0 == tag.id } }

                        }

                    )) {

                        HStack { Circle().fill(Color(hex: tag.hex)).frame(width: 12, height: 12); Text(tag.name) }

                    }

                }

            }

    }

    private var collectionsSection: some View {
            Section("My collections") {

                if store.collections.isEmpty { Text("Create collections using Organize in the sidebar.").foregroundStyle(.secondary) }

                ForEach(store.collections) { collection in

                    Toggle(collection.name, isOn: Binding(

                        get: { draft.collectionIDs.contains(collection.id) },

                        set: { enabled in

                            if enabled && !draft.collectionIDs.contains(collection.id) { draft.collectionIDs.append(collection.id) }

                            if !enabled { draft.collectionIDs.removeAll { $0 == collection.id } }

                        }

                    ))

                }

            }

    }

    private var fileManagementSection: some View {
            Section("File management") {

                HStack {

                    TextField("New file name", text: $newFileName)

                    Button("Rename on Disk") { store.rename(file, to: newFileName) }

                        .disabled(newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newFileName == file.title)

                }

                Button("Move to Another Folder…") { store.moveToFolder(file) }

                Text("Rename and move affect the real score file; confirmation is required. The project's metadata follows it.")

                    .font(.caption).foregroundStyle(.secondary)

                HStack {

                    Button("Open in Default App") { store.open(file) }

                    Button("Reveal in Finder") { store.reveal(file) }

                    Button("Duplicate") { store.duplicate(file) }

                }

            }

    }

}





extension Color {

    init(hex: String) {

        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8B5CF6

        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,

                  green: Double((value >> 8) & 255) / 255,

                  blue: Double(value & 255) / 255, opacity: 1)

    }

}



private struct OrganizationManager: View {

    @EnvironmentObject private var store: ScoreStore

    @Environment(\.dismiss) private var dismiss

    @State private var newCollection = ""

    @State private var collectionColor = "#8B5CF6"

    @State private var newTag = ""

    @State private var chosenColor = "#8B5CF6"

    @State private var editingCollection: UUID?

    @State private var editingTag: UUID?

    @State private var editedName = ""

    @State private var editedColor = "#8B5CF6"

    private let palette = ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899", "#64748B"]



    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            HStack {

                Text("Manage Organization").font(.title2.bold())

                Spacer()

                Button("Done") { dismiss() }

            }

            TabView {

                VStack(alignment: .leading, spacing: 12) {

                    HStack {

                        TextField("New collection name", text: $newCollection)

                        Button("Create") { store.createCollection(name: newCollection, hex: collectionColor); newCollection = "" }

                            .disabled(newCollection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    }

                    HStack(spacing: 8) {

                        Text("Collection color")

                        ForEach(palette, id: \.self) { hex in

                            Button { collectionColor = hex } label: {

                                Circle().fill(Color(hex: hex)).frame(width: 19, height: 19)

                                    .overlay { if collectionColor == hex { Image(systemName: "checkmark").font(.caption2).foregroundStyle(.white) } }

                            }.buttonStyle(.plain)

                        }

                    }

                    List {

                        ForEach(store.collections) { collection in

                            HStack {

                                Image(systemName: "folder.fill").foregroundStyle(Color(hex: collection.hex))

                                if editingCollection == collection.id {

                                    TextField("Name", text: $editedName)

                                    Picker("Color", selection: $editedColor) {

                                        ForEach(palette, id: \.self) { hex in Text(hex).tag(hex) }

                                    }.frame(width: 125)

                                    Button("Save") { store.renameCollection(collection.id, name: editedName, hex: editedColor); editingCollection = nil }

                                } else {

                                    Text(collection.name)

                                    Spacer()

                                    Button("Rename") { editingCollection = collection.id; editedName = collection.name; editedColor = collection.hex }

                                }

                                Button(role: .destructive) { store.deleteCollection(collection.id) } label: { Image(systemName: "trash") }

                            }

                        }

                    }

                    Text("Collections are virtual. A project can belong to multiple collections without moving its file.")

                        .font(.caption).foregroundStyle(.secondary)

                }.padding().tabItem { Label("Collections", systemImage: "folder") }

                VStack(alignment: .leading, spacing: 12) {

                    HStack {

                        TextField("New color tag", text: $newTag)

                        Button("Create") { store.createTag(name: newTag, hex: chosenColor); newTag = "" }

                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    }

                    HStack(spacing: 9) {

                        ForEach(palette, id: \.self) { hex in

                            Button { chosenColor = hex } label: {

                                Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)

                                    .overlay { if chosenColor == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }

                            }.buttonStyle(.plain).help(hex)

                        }

                    }

                    List {

                        ForEach(store.colorTags) { tag in

                            HStack {

                                Circle().fill(Color(hex: tag.hex)).frame(width: 14, height: 14)

                                if editingTag == tag.id {

                                    TextField("Name", text: $editedName)

                                    Picker("Color", selection: $editedColor) {

                                        ForEach(palette, id: \.self) { hex in Text(hex).tag(hex) }

                                    }.frame(width: 125)

                                    Button("Save") { store.renameTag(tag.id, name: editedName, hex: editedColor); editingTag = nil }

                                } else {

                                    Text(tag.name)

                                    Spacer()

                                    Button("Edit") { editingTag = tag.id; editedName = tag.name; editedColor = tag.hex }

                                }

                                Button(role: .destructive) { store.deleteTag(tag.id) } label: { Image(systemName: "trash") }

                            }

                        }

                    }

                }.padding().tabItem { Label("Color Tags", systemImage: "tag") }

            }

        }

        .padding(16)

        .frame(minWidth: 620, minHeight: 450)

    }

}
