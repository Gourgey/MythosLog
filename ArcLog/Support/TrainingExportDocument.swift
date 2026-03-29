import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TrainingExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var bundle: TrainingExportBundle

    init(bundle: TrainingExportBundle) {
        self.bundle = bundle
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.bundle = try JSONDecoder().decode(TrainingExportBundle.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        return .init(regularFileWithContents: data)
    }
}
