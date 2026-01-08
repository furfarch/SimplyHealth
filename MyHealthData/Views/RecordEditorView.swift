import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var record: MedicalRecord

    @State private var isEditing = false
    @State private var selectedSection: RecordSection = .personal

    @State private var exportErrorMessage: String?
    @State private var exportURL: URL?

    @Environment(\.dismiss) private var dismiss

    /// Allow callers to request that the editor starts in editing mode.
    init(record: MedicalRecord, startEditing: Bool = false) {
        self._record = .init(wrappedValue: record)
        self._isEditing = State(initialValue: startEditing)
    }

    var body: some View {
        Group {
            if isEditing {
                editList
            } else {
                viewPager
            }
        }
        .navigationTitle(displayName)
        .toolbar { toolbarContent }
        .fileExporter(
            isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } }),
            document: exportURL.map { ExportFileDocument(fileURL: $0) },
            contentType: .data,
            defaultFilename: exportURL?.lastPathComponent ?? "export"
        ) { _ in
            // handled by system
        }
    }

    private var editList: some View {
        List {
            RecordEditorSectionPersonal(record: record, onChange: touch)
            RecordEditorSectionEmergency(record: record, onChange: touch)

            RecordEditorSectionBlood(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionDrugs(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionVaccinations(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionAllergies(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionIllnesses(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionMedicalDocuments(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionMedicalHistory(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionRisks(modelContext: modelContext, record: record, onChange: touch)

            if let exportErrorMessage {
                Section {
                    Text(exportErrorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var viewPager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(RecordSection.allCases) { section in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                RecordSectionHeaderView(section: section)

                                VStack(alignment: .leading, spacing: 0) {
                                    viewerContent(for: section)
                                }
                                .background(.background)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal)

                                Spacer(minLength: 24)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(section)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func viewerContent(for section: RecordSection) -> some View {
        switch section {
        case .personal:
            RecordViewerSectionPersonal(record: record)
        case .emergency:
            RecordViewerSectionEmergency(record: record)
        case .weight:
            RecordViewerSectionEntries(
                title: "Weight",
                columns: ["Date", "Weight (kg)", "Comment"],
                rows: record.weights.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        String(format: "%.1f", entry.weightKg),
                        entry.comment
                    ]
                }
            )
        case .blood:
            RecordViewerSectionEntries(
                title: "Blood Values",
                columns: ["Date", "Value", "Comment"],
                rows: record.blood.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.comment
                    ]
                }
            )
        case .drugs:
            RecordViewerSectionEntries(
                title: "Medications",
                columns: ["Date", "Name & Dosage", "Comment"],
                rows: record.drugs.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.nameAndDosage,
                        entry.comment
                    ]
                }
            )
        case .vaccinations:
            RecordViewerSectionEntries(
                title: "Vaccinations",
                columns: ["Date", "Name", "Info", "Place", "Comment"],
                rows: record.vaccinations.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.information,
                        entry.place,
                        entry.comment
                    ]
                }
            )
        case .allergies:
            RecordViewerSectionEntries(
                title: "Allergies & Intolerances",
                columns: ["Date", "Name", "Info", "Comment"],
                rows: record.allergy.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.information,
                        entry.comment
                    ]
                }
            )
        case .illnesses:
            RecordViewerSectionEntries(
                title: "Illnesses & Incidents",
                columns: ["Date", "Name", "Info / Comment"],
                rows: record.illness.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.informationOrComment
                    ]
                }
            )
        case .medicalDocuments:
            RecordViewerSectionEntries(
                title: "Relevant Medical Documents",
                columns: ["Date", "Title", "Note"],
                rows: record.medicaldocument.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.note
                    ]
                }
            )
        case .medicalHistory:
            RecordViewerSectionEntries(
                title: "Relevant Medical History",
                columns: ["Date", "Name", "Contact", "Info / Comment"],
                rows: record.medicalhistory.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.contact,
                        entry.informationOrComment
                    ]
                }
            )
        case .risks:
            RecordViewerSectionEntries(
                title: "Riskfactors",
                columns: ["Date", "Name", "Description / Comment"],
                rows: record.risks.map { entry in
                    [
                        entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                        entry.name,
                        entry.descriptionOrComment
                    ]
                }
            )
        }
    }

    private func viewPage<Content: View>(_ section: RecordSection, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RecordSectionHeaderView(section: section)

                // Read-only content (no Section titles here; titles are shown in the header above)
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
        }
        .tag(section)
    }

    private var displayName: String {
        let family = record.personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = record.personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
        if family.isEmpty && given.isEmpty {
            return "Medical Record"
        }
        return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func touch() {
        record.updatedAt = Date()
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    // Finish editing: update timestamp, ensure the record is in the context, persist, then dismiss.
                    record.updatedAt = Date()
                    // Ensure the record is part of the modelContext. Inserting an object that's already
                    // in the context is a no-op, so this is safe and ensures detached objects get saved.
                    modelContext.insert(record)
                    do {
                        try modelContext.save()
                    } catch {
                        // intentionally silent (no logging)
                    }
                    dismiss()
                } else {
                    // Enter editing mode
                    isEditing = true
                }
            }

            Menu {
                Button("Export JSON") { Task { await exportJSON() } }
                Button("Export HTML") { Task { await exportHTML() } }
                Button("Export PDF") { Task { await exportPDF() } }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Export

    private func exportJSON() async {
        await export(type: "json") {
            try ExportService.makeJSONData(for: record)
        }
    }

    private func exportHTML() async {
        await export(type: "html") {
            Data(ExportService.makeHTMLString(for: record).utf8)
        }
    }

    private func exportPDF() async {
        exportErrorMessage = nil
        do {
            let data = try await ExportService.makePDFData(for: record)
            try await writeExport(data: data, type: "pdf")
        } catch {
            exportErrorMessage = "Export PDF failed: \(error.localizedDescription)"
        }
    }

    private func export(type: String, makeData: () throws -> Data) async {
        exportErrorMessage = nil
        do {
            let data = try makeData()
            try await writeExport(data: data, type: type)
        } catch {
            exportErrorMessage = "Export \(type.uppercased()) failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func writeExport(data: Data, type: String) async throws {
        let safeName = displayName.replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeName.isEmpty ? "MedicalRecord" : safeName).\(type)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])

        // Exports should be unencrypted (no file protection).
        // This does NOT affect the app's internal database.
        try? AppFileProtection.apply(to: url, protection: .none)

        exportURL = url
    }
}
