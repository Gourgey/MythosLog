import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = TrainingExportDocument(bundle: .empty)
    @State private var healthStatusMessage: String?
    @State private var isSyncingHealth = false
    let onSettingsMutated: () -> Void

    private var settings: AppSettings? {
        settingsRecords.first
    }

    var body: some View {
        List {
            if let settings {
                Section("Progression") {
                    Toggle("Enable decay", isOn: binding(\.enableDecay))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decay sensitivity")
                        Slider(value: binding(\.decaySensitivity), in: 0.6...1.4, step: 0.1)
                        Text(String(format: "%.1fx", settings.decaySensitivity))
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                    Toggle("Week starts on Monday", isOn: binding(\.weekStartsOnMonday))
                    Toggle("Lock in weekly review", isOn: binding(\.lockInWeeklyReview))
                }

                Section("Notifications") {
                    Toggle("Daily reminder", isOn: binding(\.dailyReminderEnabled))
                    Toggle("Evening unfinished reminder", isOn: binding(\.eveningReminderEnabled))
                    Toggle("Weekly review reminder", isOn: binding(\.weeklyReviewReminderEnabled))
                    Button("Request notification access") {
                        Task { await NotificationService.requestAuthorization() }
                    }
                }

                Section("Experience") {
                    Toggle("Haptics", isOn: binding(\.hapticsEnabled))
                    Picker("Theme", selection: Binding(
                        get: { settings.themePreference },
                        set: {
                            settings.themePreference = $0
                            saveSettings()
                        }
                    )) {
                        ForEach(ThemePreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
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
                #endif

                Section("Data") {
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
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .task {
            _ = try? TrainingStore.fetchSettings(context: modelContext)
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

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings![keyPath: keyPath] },
            set: {
                settings?[keyPath: keyPath] = $0
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        settings?.updatedAt = .now
        try? modelContext.save()
        if let settings {
            NotificationService.refreshNotifications(using: settings)
        }
        onSettingsMutated()
    }
}
