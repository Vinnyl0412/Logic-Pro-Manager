import Foundation

enum ScoreFormat: String, Codable, CaseIterable, Identifiable {
    case logic = "Logic Pro"
    var id: String { rawValue }
    var extensions: [String] { ["logicx"] }
}

struct ScoreFile: Identifiable, Hashable {
    let url: URL
    let format: ScoreFormat
    let created: Date
    let modified: Date
    let bytes: Int64
    var id: String { url.standardizedFileURL.path }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

struct ScoreMetadata: Codable, Equatable {
    var genre = "Uncategorized"
    var category = "Uncategorized"
    var instrumentation = ""
    var composer = ""
    var status = "In Progress"
    var keywords = ""
    var notes = ""
    var favorite = false
    var colorTagIDs: [UUID] = []
    var collectionIDs: [UUID] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case genre, category, instrumentation, composer, status, keywords, notes, favorite, colorTagIDs, collectionIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        genre = try values.decodeIfPresent(String.self, forKey: .genre) ?? "Uncategorized"
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "Uncategorized"
        instrumentation = try values.decodeIfPresent(String.self, forKey: .instrumentation) ?? ""
        composer = try values.decodeIfPresent(String.self, forKey: .composer) ?? ""
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "In Progress"
        keywords = try values.decodeIfPresent(String.self, forKey: .keywords) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        colorTagIDs = try values.decodeIfPresent([UUID].self, forKey: .colorTagIDs) ?? []
        collectionIDs = try values.decodeIfPresent([UUID].self, forKey: .collectionIDs) ?? []
    }
}

enum ScoreSort: String, CaseIterable, Identifiable {
    case modified = "Last edited"
    case created = "Date created"
    case title = "Title"
    case size = "File size"
    case genre = "Genre"
    var id: String { rawValue }
}

struct ColorTag: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var hex: String
}

struct ScoreCollection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String = "folder"
    var hex: String = "#8B5CF6"

    private enum CodingKeys: String, CodingKey { case id, name, symbol, hex }
    init(id: UUID = UUID(), name: String, symbol: String = "folder", hex: String = "#8B5CF6") {
        self.id = id; self.name = name; self.symbol = symbol; self.hex = hex
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "folder"
        hex = try c.decodeIfPresent(String.self, forKey: .hex) ?? "#8B5CF6"
    }
}
