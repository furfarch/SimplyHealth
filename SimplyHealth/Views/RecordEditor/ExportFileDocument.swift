import SwiftUI
import UniformTypeIdentifiers

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadNoPermission)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL)
    }
}
