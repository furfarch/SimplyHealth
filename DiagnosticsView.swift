import SwiftUI
import CloudKit
import SwiftData

struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var logLines: [String] = []
    @State private var sharedZonesCount: Int? = nil
    @State private var foundSharedUUIDs: [String] = []
    @State private var manualURL: String = ""
    @State private var manualImportStatus: String = ""
    @State private var isRunning: Bool = false

    private let containerID = AppConfig.CloudKit.containerID

    var body: some View {
        List {
            Section("Actions") {
                Button(action: { Task { await runOwnerAndSharedChecks() } }) {
                    if isRunning { ProgressView() } else { Text("Run Cloud Diagnostics") }
                }
                .disabled(isRunning)

                VStack(alignment: .leading) {
                    Text("Manual Share URL Import")
                    TextField("cloudkit://share/…", text: $manualURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Import From URL") { Task { await importFromURL() } }
                    if !manualImportStatus.isEmpty {
                        Text(manualImportStatus)
                            .font(.footnote)
                            .foregroundColor(manualImportStatus.starts(with: "Import failed") ? .red : .green)
                            .padding(.top, 2)
                    }
                }
            }

            Section("Shared Zones") {
                if let count = sharedZonesCount {
                    Text("Shared zones: \(count)")
                } else {
                    Text("Shared zones: (unknown)")
                }
                if !foundSharedUUIDs.isEmpty {
                    Text("Found shared UUIDs: \(foundSharedUUIDs.joined(separator: ", "))")
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            Section("Recent Logs (DEBUG builds)") {
                ForEach(logLines, id: \.self) { Text($0).font(.footnote).textSelection(.enabled) }
            }
        }
        .navigationTitle("Diagnostics")
        .task { refreshLogs() }
    }

    private func refreshLogs() {
        #if DEBUG
        logLines = ShareDebugStore.shared.logs.suffix(200).reversed()
        #else
        logLines = ["Logs are limited in TestFlight builds."]
        #endif
    }

    @MainActor
    private func runOwnerAndSharedChecks() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let container = CKContainer(identifier: containerID)
            let sharedDB = container.sharedCloudDatabase

            // Enumerate shared zones
            let zones: [CKRecordZone] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecordZone], Error>) in
                sharedDB.fetchAllRecordZones { zones, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: zones ?? [])
                }
            }
            sharedZonesCount = zones.count

            // Query for all shared MedicalRecord uuids across zones
            var found: [String] = []
            for zone in zones {
                let query = CKQuery(recordType: "MedicalRecord", predicate: NSPredicate(value: true))
                let op = CKQueryOperation(query: query)
                op.zoneID = zone.zoneID
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result, let uuid = rec["uuid"] as? String { found.append(uuid) }
                }
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    op.queryResultBlock = { result in
                        switch result { case .success: cont.resume(); case .failure(let err): cont.resume(throwing: err) }
                    }
                    sharedDB.add(op)
                }
            }
            foundSharedUUIDs = Array(Set(found)).sorted()
            refreshLogs()
        } catch {
            logLines.insert("Diagnostics error: \(error.localizedDescription)", at: 0)
        }
    }

    @MainActor
    private func importFromURL() async {
        manualImportStatus = ""
        guard let url = URL(string: manualURL), !manualURL.isEmpty else {
            manualImportStatus = "Invalid URL"
            return
        }

        await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
        // Force a full shared import immediately after manual acceptance
        let sharedFetcher = CloudKitSharedZoneMedicalRecordFetcher(containerIdentifier: AppConfig.CloudKit.containerID, modelContext: modelContext)
        _ = try? await sharedFetcher.fetchAllSharedAcrossZonesAsync()
        manualImportStatus = "Import triggered"
        refreshLogs()
    }
}
