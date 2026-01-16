import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var record: MedicalRecord

    @State private var isEditing = false

    @State private var saveErrorMessage: String?

    @Environment(\.dismiss) private var dismiss

    /// Allow callers to request that the editor starts in editing mode.
    init(record: MedicalRecord, startEditing: Bool = false) {
        self._record = .init(wrappedValue: record)
        self._isEditing = State(initialValue: startEditing)
    }

    // Requested viewer order:
    // A) Personal
    // B) Emergency
    // C) Vet / Doctor
    // D) Weight (pets only)
    // E) Blood
    // F) Medications
    // G) Vaccinations
    // H) Allergies
    // I) Illnesses
    // J) Documents
    // K) History
    // L) Risks
    // M) Costs (pets only)
    // N) Record Details
    private var pagingSections: [RecordSection] {
        var sections: [RecordSection] = [
            .personal,
            .emergency
        ]

        if record.isPet {
            sections.append(.petVet)
            sections.append(.weight)
        } else {
            sections.append(.doctors)
        }

        sections.append(contentsOf: [
            .blood,
            .drugs,
            .vaccinations,
            .allergies,
            .illnesses,
            .medicalDocuments,
            .medicalHistory,
            .risks
        ])

        if record.isPet {
            sections.append(.petCosts)
        }

        sections.append(.details)
        return sections
    }

    var body: some View {
        Group {
            if isEditing {
                editList
            } else {
                viewPager
            }
        }
        .navigationTitle(record.displayName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(record.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Image(systemName: record.locationStatus.systemImageName)
                        .foregroundStyle(record.locationStatus.color)
                        .accessibilityLabel(record.locationStatus.accessibilityLabel)
                        .accessibilityIdentifier("recordLocationStatusIcon")
                }
            }

            toolbarContent
        }
        .alert("Save Error", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    private var editList: some View {
        List {
            RecordEditorSectionPersonal(record: record, onChange: touch)

            RecordEditorSectionEmergency(modelContext: modelContext, record: record, onChange: touch)

            if record.isPet {
                RecordEditorSectionPetVet(record: record, onChange: touch)
                RecordEditorSectionWeight(modelContext: modelContext, record: record, onChange: touch)
                RecordEditorSectionPetYearlyCosts(modelContext: modelContext, record: record, onChange: touch)
            } else {
                RecordEditorSectionDoctors(modelContext: modelContext, record: record, onChange: touch)
            }

            RecordEditorSectionBlood(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionDrugs(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionVaccinations(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionAllergies(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionIllnesses(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionMedicalDocuments(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionMedicalHistory(modelContext: modelContext, record: record, onChange: touch)
            RecordEditorSectionRisks(modelContext: modelContext, record: record, onChange: touch)
        }
    }

    private var viewPager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pagingSections) { section in
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
        case .petVet:
            RecordViewerSectionPetVet(record: record)
        case .doctors:
            RecordViewerSectionDoctors(record: record)
        case .weight:
            RecordViewerSectionEntries(
                title: "Weight",
                columns: ["Date", "Weight (kg)", "Comment"],
                rows: record.weights
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .map { entry in
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
        case .petCosts:
            RecordViewerSectionPetYearlyCosts(record: record)
        case .details:
            RecordViewerSectionDetails(record: record)
        }
    }

    private func touch() {
        record.updatedAt = Date()
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    record.updatedAt = Date()
                    Task { @MainActor in
                        do {
                            try modelContext.save()

                            if record.isCloudEnabled {
                                try await CloudSyncService.shared.syncIfNeeded(record: record)
                                try modelContext.save()
                            }

                            isEditing = false
                            dismiss()
                        } catch {
                            saveErrorMessage = "Save failed: \(error.localizedDescription)"
                        }
                    }
                } else {
                    isEditing = true
                }
            }
        }
    }
}
