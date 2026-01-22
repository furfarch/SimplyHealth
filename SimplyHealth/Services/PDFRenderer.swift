import Foundation

enum PDFRenderer {
    enum RenderError: Error {
        case invalidBaseURL
        case webViewFailed
    }

    static func render(html: String, fileNameHint: String = "MedicalRecord") async throws -> Data {
        #if os(iOS)
        return try await iOSPDFRenderer.render(html: html)
        #elseif os(macOS)
        return try await macOSPDFRenderer.render(html: html)
        #else
        throw RenderError.webViewFailed
        #endif
    }
}
