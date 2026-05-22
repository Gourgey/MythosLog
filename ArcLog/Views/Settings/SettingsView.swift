import CloudKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum CloudSyncState: Equatable {
    case checking
    case active
    case signedOut
    case restricted
    case unavailable
    case unknown

    var title: String {
        switch self {
        case .checking:
            return "Checking..."
        case .active:
            return "iCloud sync active"
        case .signedOut:
            return "Sign in to iCloud"
        case .restricted:
            return "iCloud restricted"
        case .unavailable:
            return "iCloud unavailable"
        case .unknown:
            return "Sync status unknown"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "ArcLog is checking your iCloud account."
        case .active:
            return "ArcLog data syncs across devices on this iCloud account."
        case .signedOut:
            return "ArcLog saves locally and syncs when iCloud is available."
        case .restricted:
            return "ArcLog saves locally because this account cannot use iCloud sync."
        case .unavailable:
            return "ArcLog saves locally and will retry iCloud sync later."
        case .unknown:
            return "ArcLog saves locally while iCloud status cannot be confirmed."
        }
    }
}

enum CloudSyncStatusService {
    static func currentState() async -> CloudSyncState {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return .signedOut
        }
        guard TrainingStore.canAttemptCloudKitPersistence() else {
            return .unknown
        }

        let container = CKContainer(identifier: AppIdentity.iCloudContainerIdentifier)

        do {
            let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
                container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }

            switch status {
            case .available:
                return .active
            case .noAccount:
                return .signedOut
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .unavailable
            case .couldNotDetermine:
                return .unknown
            @unknown default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    static func accountStatusDescription() async -> String {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return "No ubiquity identity token"
        }

        let container = CKContainer(identifier: AppIdentity.iCloudContainerIdentifier)
        do {
            let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
                container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }

            switch status {
            case .available:
                return "available"
            case .noAccount:
                return "noAccount"
            case .restricted:
                return "restricted"
            case .temporarilyUnavailable:
                return "temporarilyUnavailable"
            case .couldNotDetermine:
                return "couldNotDetermine"
            @unknown default:
                return "unknown"
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
private struct SyncDiagnosticsSnapshot: Equatable {
    var storeURL: String
    var iCloudSignedInState: String
    var cloudKitAccountStatus: String
    var containerIdentifier: String
    var lastLocalWrite: String
    var lastCloudKitEvent: String
    var modelCounts: TrainingStore.ModelCounts

    static let empty = SyncDiagnosticsSnapshot(
        storeURL: "Checking...",
        iCloudSignedInState: "Checking...",
        cloudKitAccountStatus: "Checking...",
        containerIdentifier: AppIdentity.iCloudContainerIdentifier,
        lastLocalWrite: "None observed",
        lastCloudKitEvent: "None observed",
        modelCounts: TrainingStore.ModelCounts(stats: 0, habits: 0, logs: 0, weeklyResolutions: 0, settings: 0, healthImports: 0)
    )
}
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = TrainingExportDocument(bundle: .empty)
    @State private var healthStatusMessage: String?
    @State private var isSyncingHealth = false
    @State private var cloudSyncState: CloudSyncState = .checking
    #if DEBUG
    @State private var syncDiagnostics = SyncDiagnosticsSnapshot.empty
    #endif
    let onSettingsMutated: () -> Void

    private var settings: AppSettings? {
        settingsRecords.first
    }

    var body: some View {
        List {
            if let settings {
                Section("Progression") {
                    Picker("Strictness", selection: strictnessBinding) {
                        ForEach(ProgressionStrictness.allCases) { strictness in
                            Text(strictness.displayName).tag(strictness)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.progressionStrictness.detail)
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)

                    Toggle("Enable decay", isOn: binding(\.enableDecay))
                    Toggle("Week starts on Monday", isOn: binding(\.weekStartsOnMonday))
                    Toggle("Lock in weekly review", isOn: binding(\.lockInWeeklyReview))
                }

                Section {
                    Toggle("Show personal max in UI", isOn: binding(\.showPersonalMaxInUI))
                    Toggle("Goals can affect progression", isOn: binding(\.goalsCanAffectProgression))
                    Text("By default goals are tracking-only. Turn this on if you want missing aspirational goals to also affect Charge for goals that have ‘affects progression’ turned on.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                } header: {
                    Text("Calibration & Goals")
                }

                Section("Notifications") {
                    Toggle("Daily reminder", isOn: binding(\.dailyReminderEnabled))
                    Toggle("Evening unfinished reminder", isOn: binding(\.eveningReminderEnabled))
                    Toggle("Weekly review reminder", isOn: binding(\.weeklyReviewReminderEnabled))
                    Toggle("Goal at risk reminder", isOn: binding(\.goalAtRiskReminderEnabled))
                    Text("Notifies you mid-week if any active goal is at risk of being missed.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                    Button("Request notification access") {
                        Task { await NotificationService.requestAuthorization() }
                    }
                }

                Section("Experience") {
                    Toggle("Haptics", isOn: binding(\.hapticsEnabled))
                }

                #if canImport(HealthKit)
                Section("Apple Health") {
                    LabeledContent("Status", value: HealthImportService.authorizationState().title)
                    Toggle("Auto-import workouts", isOn: binding(\.healthAutoImportEnabled))

                    if let lastSync = settings.lastHealthSyncAt {
                        LabeledContent("Last sync") {
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    Button("Connect Apple Health") {
                        isSyncingHealth = true
                        Task {
                            let message = await HealthImportService.requestAuthorizationAndSync()
                            await MainActor.run {
                                healthStatusMessage = message
                                isSyncingHealth = false
                                onSettingsMutated()
                            }
                        }
                    }

                    Button(isSyncingHealth ? "Syncing…" : "Sync Now") {
                        guard !isSyncingHealth else { return }
                        isSyncingHealth = true
                        Task {
                            let message = (try? await HealthImportService.syncNow()) ?? "Apple Health sync could not complete."
                            await MainActor.run {
                                healthStatusMessage = message
                                isSyncingHealth = false
                                onSettingsMutated()
                            }
                        }
                    }
                    .disabled(isSyncingHealth)

                    if let healthStatusMessage {
                        Text(healthStatusMessage)
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }

                Section("Workout Types") {
                    Text("Choose which Apple Health workouts ArcLog imports. Disable a type to skip future workouts of that kind.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)

                    ForEach(SupportedWorkoutType.Category.allCases, id: \.self) { category in
                        DisclosureGroup(category.title) {
                            ForEach(SupportedWorkoutType.all.filter { $0.category == category }) { type in
                                Toggle(type.displayName, isOn: workoutTypeBinding(for: type.key))
                            }
                        }
                    }
                }
                #endif

                Section("Connect Apps") {
                    DisclosureGroup("Reading via iOS Shortcut") {
                        Text("ArcLog cannot read directly from Kindle. After a reading session, run an iOS Shortcut that opens the URL below to log against your Reading skill.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                        Text("arclog://log?stat=reading&value=30&note=Kindle")
                            .font(.caption.monospaced())
                            .foregroundStyle(TrainingTheme.textPrimary)
                            .textSelection(.enabled)
                    }

                    DisclosureGroup("Curiosity Tracker") {
                        Text("Your Curiosity Tracker app can mirror each research log into ArcLog using the deep-link below.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                        Text("arclog://log?stat=curiosity&value=1&note=Topic")
                            .font(.caption.monospaced())
                            .foregroundStyle(TrainingTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                }

                Section("Data") {
                    LabeledContent("iCloud Sync") {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(cloudSyncState.title)
                            Text(cloudSyncState.detail)
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    Button("Refresh iCloud Status") {
                        Task { await refreshCloudSyncStatus() }
                    }

                    Button("Export JSON") {
                        exportDocument = TrainingExportDocument(
                            bundle: (try? TrainingStore.exportBundle(context: modelContext)) ?? .empty
                        )
                        isExporting = true
                    }
                    Button("Import JSON") {
                        isImporting = true
                    }
                }

                Section("Debug Tools") {
                    Button("Sync Weekly Reports") {
                        _ = try? TrainingStore.resolvePendingWeek(context: modelContext)
                    }
                    ForEach(SampleProfile.allCases) { profile in
                        Button("Seed \(profile.displayName)") {
                            try? TrainingStore.seedSampleData(context: modelContext, profile: profile)
                            onSettingsMutated()
                        }
                    }
                    Button("Seed Sample Goals") {
                        try? TrainingStore.seedSampleGoals(context: modelContext)
                        onSettingsMutated()
                    }
                    Button("Clear All Data", role: .destructive) {
                        try? TrainingStore.clearAll(context: modelContext)
                        onSettingsMutated()
                    }
                    Button("Reset Default Profile") {
                        try? TrainingStore.clearAll(context: modelContext)
                        try? TrainingStore.seedDefaultProfile(context: modelContext, completeOnboarding: true)
                        onSettingsMutated()
                    }
                }

                #if DEBUG
                Section("Sync Diagnostics") {
                    LabeledContent("Store URL", value: syncDiagnostics.storeURL)
                    LabeledContent("iCloud Token", value: syncDiagnostics.iCloudSignedInState)
                    LabeledContent("CloudKit Account", value: syncDiagnostics.cloudKitAccountStatus)
                    LabeledContent("Container", value: syncDiagnostics.containerIdentifier)
                    LabeledContent("Last Local Write", value: syncDiagnostics.lastLocalWrite)
                    LabeledContent("Last Import/Export", value: syncDiagnostics.lastCloudKitEvent)
                    LabeledContent("Counts") {
                        Text("Stats \(syncDiagnostics.modelCounts.stats), habits \(syncDiagnostics.modelCounts.habits), logs \(syncDiagnostics.modelCounts.logs), settings \(syncDiagnostics.modelCounts.settings), resolutions \(syncDiagnostics.modelCounts.weeklyResolutions), health \(syncDiagnostics.modelCounts.healthImports)")
                            .multilineTextAlignment(.trailing)
                    }

                    Button("Refresh Sync Diagnostics") {
                        Task { await refreshSyncDiagnostics() }
                    }
                }
                #endif
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .task {
            _ = try? TrainingStore.fetchSettings(context: modelContext)
            await refreshCloudSyncStatus()
            #if DEBUG
            await refreshSyncDiagnostics()
            #endif
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "arclog-export"
        ) { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let bundle = try? decoder.decode(TrainingExportBundle.self, from: data) else { return }
            try? TrainingStore.importBundle(bundle, context: modelContext)
            onSettingsMutated()
        }
    }

    private var strictnessBinding: Binding<ProgressionStrictness> {
        Binding(
            get: { settings?.progressionStrictness ?? .balanced },
            set: {
                settings?.progressionStrictness = $0
                saveSettings()
            }
        )
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings![keyPath: keyPath] },
            set: {
                settings?[keyPath: keyPath] = $0
                saveSettings()
            }
        )
    }

    private func workoutTypeBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                guard let settings else { return true }
                return !settings.disabledHealthWorkoutTypeKeys.contains(key)
            },
            set: { enabled in
                guard let settings else { return }
                var disabled = settings.disabledHealthWorkoutTypeKeys
                if enabled {
                    disabled.remove(key)
                } else {
                    disabled.insert(key)
                }
                settings.disabledHealthWorkoutTypeKeys = disabled
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        settings?.updatedAt = .now
        try? modelContext.save()
        TrainingStore.recordLocalWrite(reason: "updated settings")
        if let settings {
            let atRisk = (try? TrainingStore.goalProgressSnapshots(context: modelContext)) ?? []
            let atRiskCount = atRisk.filter {
                $0.goal.status == .active && ($0.paceStatus == .atRisk || $0.paceStatus == .behind)
            }.count
            NotificationService.refreshNotifications(using: settings, goalsAtRiskCount: atRiskCount)
        }
        onSettingsMutated()
    }

    @MainActor
    private func refreshCloudSyncStatus() async {
        cloudSyncState = .checking
        cloudSyncState = await CloudSyncStatusService.currentState()
    }

    #if DEBUG
    @MainActor
    private func refreshSyncDiagnostics() async {
        let runtimeInfo = TrainingStore.runtimeStoreInfo
        let lastLocalWrite = TrainingStore.lastLocalWriteAt.map {
            let reason = TrainingStore.lastLocalWriteReason.map { " (\($0))" } ?? ""
            return $0.formatted(date: .abbreviated, time: .standard) + reason
        } ?? "None observed"
        let lastCloudKitEvent = TrainingStore.lastCloudKitEventSummary.map { summary in
            if let date = TrainingStore.lastCloudKitEventAt {
                return "\(summary) [observed \(date.formatted(date: .abbreviated, time: .standard))]"
            }
            return summary
        } ?? "None observed"

        syncDiagnostics = SyncDiagnosticsSnapshot(
            storeURL: runtimeInfo.storeURL?.path ?? (runtimeInfo.isInMemory ? "In-memory" : "Unknown"),
            iCloudSignedInState: FileManager.default.ubiquityIdentityToken == nil ? "missing" : "present",
            cloudKitAccountStatus: await CloudSyncStatusService.accountStatusDescription(),
            containerIdentifier: runtimeInfo.cloudKitContainerIdentifier ?? "\(AppIdentity.iCloudContainerIdentifier) (not selected by active store)",
            lastLocalWrite: lastLocalWrite,
            lastCloudKitEvent: lastCloudKitEvent,
            modelCounts: TrainingStore.modelCounts(context: modelContext)
        )
    }
    #endif
}
