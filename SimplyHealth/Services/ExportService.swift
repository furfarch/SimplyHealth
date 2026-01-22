import Foundation

enum ExportService {
    enum ExportError: Error {
        case encodingFailed
    }

    static func makeJSONData(for record: MedicalRecord) throws -> Data {
        let export = MedicalRecordMapper.toExport(record: record)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(export)
    }

    static func makeHTMLString(for record: MedicalRecord) -> String {
        let export = MedicalRecordMapper.toExport(record: record)
        return HTMLTemplateRenderer.render(recordExport: export)
    }

    static func makePDFData(for record: MedicalRecord) async throws -> Data {
        let html = makeHTMLString(for: record)
        return try await PDFRenderer.render(html: html)
    }
}
