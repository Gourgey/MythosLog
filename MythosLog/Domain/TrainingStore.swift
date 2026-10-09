import Foundation
import CoreData
import CloudKit
import OSLog
import SwiftData

// TrainingStore (core): ModelContainer creation with CloudKit/App Group
// fallback, sync diagnostics, fetch helpers, catalog synchronization, and the
// primary log/delete mutations. Sliced by concern into the TrainingStore+*.swift
// files alongside this one; everything remains @MainActor statics on the
// TrainingStore namespace.

@MainActor
enum TrainingStore {
    nonisolated static let didRecordLocalWriteNotification = Notification.Name("TrainingStore.didRecordLocalWrite")
    private static let syncLogger = Logger(subsystem: "studio.curateddesign.MythosLog", category: "SwiftDataCloudKit")
    private static let lastLocalWriteDefaultsKey = "mythoslog.syncDiagnostics.lastLocalWriteAt"
    private static let lastLocalWriteReasonDefaultsKey = "mythoslog.syncDiagnostics.lastLocalWriteReason"
    private static let lastCloudKitEventDefaultsKey = "mythoslog.syncDiagnostics.lastCloudKitEvent"
    private static let lastCloudKitEventDateDefaultsKey = "mythoslog.syncDiagnostics.lastCloudKitEventDate"
    private static var cloudKitEventObserver: NSObjectProtocol?
    private static var cloudKitReconciliationTask: Task<Void, Never>?
    private static let storeLocationDefaultsKey = "mythoslog.persistence.selectedLocation.v1"
    private(set) static var persistentStoreError: String?

    private struct PersistentStoreCandidate {
        let configurations: [ModelConfiguration]
        /// The synced store; diagnostics report this one.
        let storeURL: URL?
        let localOnlyStoreURL: URL?
        let usesCloudKit: Bool
        let usesAppGroup: Bool
        let isInMemory: Bool
        let allowsStoreReset: Bool
    }

    struct RuntimeStoreInfo: Equatable {
        var storeURL: URL?
        var cloudKitContainerIdentifier: String?
        var usesCloudKit: Bool
        var usesAppGroup: Bool
        var isInMemory: Bool
        var allowsStoreReset: Bool
        var createdAt: Date
        var fallbackReason: String?
    }

    struct ModelCounts: Equatable {
        var stats: Int
        var habits: Int
        var logs: Int
        var weeklyResolutions: Int
        var settings: Int
        var healthImports: Int
        var goals: Int = 0
    }

    private(set) static var runtimeStoreInfo = RuntimeStoreInfo(
        storeURL: nil,
        cloudKitContainerIdentifier: nil,
        usesCloudKit: false,
        usesAppGroup: false,
        isInMemory: false,
        allowsStoreReset: false,
        createdAt: .now,
        fallbackReason: "ModelContainer has not been created yet."
    )

    /// Models mirrored to the user's private CloudKit database. The original
    /// Health entity is retained only to migrate and remove pre-upgrade rows.
    static let syncedModelTypes: [any PersistentModel.Type] = [
        StatDomain.self,
        Habit.self,
        HabitLog.self,
        WeeklyResolution.self,
        AppSettings.self,
        Goal.self,
        HealthImportedWorkout.self, // legacy entity; drained to local storage
        DismissedHealthWorkout.self
    ]

    /// Models that never leave the device. Workout details read from HealthKit
    /// stay here: App Review guideline 5.1.3(ii) bars health data in iCloud.
    static let localOnlyModelTypes: [any PersistentModel.Type] = [
        LocalHealthImportedWorkout.self
    ]

    static let schema = Schema(syncedModelTypes + localOnlyModelTypes)
    private static let syncedSchema = Schema(syncedModelTypes)
    private static let localOnlySchema = Schema(localOnlyModelTypes)

    static let sharedModelContainer = makeModelContainer()

    #if DEBUG
    /// Pushes every record type and field in `schema` to the CloudKit
    /// Development environment, ready for "Deploy Schema Changes" in the
    /// CloudKit Console. CloudKit only creates a field when a record carrying
    /// a value for it syncs, so optional fields can otherwise be missing from
    /// the deployed schema. Run once on a signed-in device with the
    /// `-InitializeCloudKitSchema` launch argument. Uses a throwaway store, so
    /// no user data is touched.
    static func initializeCloudKitSchema() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSchemaInit-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: AppIdentity.iCloudContainerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: syncedModelTypes) else {
            syncLogger.error("CloudKit schema init: could not build a managed object model")
            return
        }

        let container = NSPersistentCloudKitContainer(name: AppIdentity.internalProjectName, managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            syncLogger.error("CloudKit schema init: store failed to load: \(String(describing: loadError), privacy: .public)")
            return
        }

        do {
            try container.initializeCloudKitSchema()
            syncLogger.info("CloudKit schema init: Development schema is up to date. Deploy it to Production in the CloudKit Console.")
        } catch {
            syncLogger.error("CloudKit schema init failed: \(String(describing: error), privacy: .public)")
        }

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: storeURL)
    }
    #endif

    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let fileManager = FileManager.default
        let canUseAppGroup = !inMemory && fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier
        ) != nil

        let savedLocation = diagnosticDefaults.string(forKey: storeLocationDefaultsKey)
        let useAppGroup = !inMemory && selectedStoreUsesAppGroup(
            canUseAppGroup: canUseAppGroup,
            appLocalStoreExists: fileManager.fileExists(atPath: persistentStoreURL(useAppGroup: false).path),
            savedLocation: savedLocation
        )
        let candidate = makeConfigurationCandidate(
            inMemory: inMemory, useAppGroup: useAppGroup,
            useCloudKit: !inMemory && canAttemptCloudKitPersistence(), allowsStoreReset: false
        )
        logStoreCandidate(candidate)
        do {
            if !inMemory, savedLocation == "shared", !canUseAppGroup {
                throw CocoaError(.fileReadNoPermission)
            }
            if !inMemory, savedLocation != nil, let url = candidate.storeURL,
               !fileManager.fileExists(atPath: url.path) {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let container = try openStore(candidate)
            recordRuntimeStoreInfo(candidate: candidate, fallbackReason: nil)
            if !inMemory {
                persistentStoreError = nil
                diagnosticDefaults.set(useAppGroup ? "shared" : "app-local", forKey: storeLocationDefaultsKey)
                logICloudAccountState()
            }
            return container
        } catch {
            logStoreCandidateFailure(candidate, error: error)
            if !inMemory { persistentStoreError = String(describing: error) }
        }

        // The memory container supports the startup error screen only. Normal
        // UI and background writes are disabled: never present an empty profile
        // as if it were the user's saved data, or reset/switch stores on failure.
        let message = persistentStoreError ?? "Unable to open the data store."
        let emergency = makeConfigurationCandidate(inMemory: true, useAppGroup: false, useCloudKit: false, allowsStoreReset: false)
        if let container = try? ModelContainer(for: schema, configurations: emergency.configurations) {
            recordRuntimeStoreInfo(candidate: emergency, fallbackReason: "Saved store could not be opened; normal UI and writes are paused. Error: \(message)")
            return container
        }
        fatalError("Unable to create ModelContainer. \(message)")
    }

    static func selectedStoreUsesAppGroup(canUseAppGroup: Bool, appLocalStoreExists: Bool, savedLocation: String?) -> Bool {
        guard canUseAppGroup else { return false }
        if let savedLocation { return savedLocation == "shared" }
        // Earlier builds could silently fall back to app-local storage. Keep
        // that installation's latest edits; the old shared store stays intact.
        return !appLocalStoreExists
    }

    /// Also used by on-disk upgrade regression tests with isolated URLs.
    static func makePersistentContainer(at storeURL: URL) throws -> ModelContainer {
        try openStore(makeConfigurationCandidate(
            inMemory: false, useAppGroup: false, useCloudKit: false,
            allowsStoreReset: false, explicitStoreURL: storeURL
        ))
    }

    private static func openStore(_ candidate: PersistentStoreCandidate) throws -> ModelContainer {
        if let storeURL = candidate.storeURL {
            try backupBeforeSchemaChange(at: storeURL)
        }
        let container = try ModelContainer(for: schema, configurations: candidate.configurations)
        if let storeURL = candidate.storeURL {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try importPreviousLocalHealthStore(beside: storeURL, context: context)
            try moveLegacyHealthImportsToLocalStore(context: context)
        }
        return container
    }

    nonisolated static func canAttemptCloudKitPersistence() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }

        return true
    }

    private static func makeConfigurationCandidate(
        inMemory: Bool,
        useAppGroup: Bool,
        useCloudKit: Bool,
        allowsStoreReset: Bool,
        explicitStoreURL: URL? = nil
    ) -> PersistentStoreCandidate {
        if inMemory {
            return PersistentStoreCandidate(
                configurations: [
                    ModelConfiguration(
                        AppIdentity.displayName,
                        schema: syncedSchema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    ),
                    ModelConfiguration(
                        localOnlyConfigurationName,
                        schema: localOnlySchema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    )
                ],
                storeURL: nil,
                localOnlyStoreURL: nil,
                usesCloudKit: false,
                usesAppGroup: false,
                isInMemory: true,
                allowsStoreReset: allowsStoreReset
            )
        }

        let storeURL = explicitStoreURL ?? persistentStoreURL(useAppGroup: useAppGroup)
        let localOnlyStoreURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(AppIdentity.internalProjectName)-HealthLocal-v2.store")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        return PersistentStoreCandidate(
            configurations: [
                ModelConfiguration(
                    AppIdentity.displayName,
                    schema: syncedSchema,
                    url: storeURL,
                    cloudKitDatabase: useCloudKit ? .private(AppIdentity.iCloudContainerIdentifier) : .none
                ),
                ModelConfiguration(
                    localOnlyConfigurationName,
                    schema: localOnlySchema,
                    url: localOnlyStoreURL,
                    cloudKitDatabase: .none
                )
            ],
            storeURL: storeURL,
            localOnlyStoreURL: localOnlyStoreURL,
            usesCloudKit: useCloudKit,
            usesAppGroup: useAppGroup,
            isInMemory: false,
            allowsStoreReset: allowsStoreReset
        )
    }

    private static let localOnlyConfigurationName = "LocalOnly"

    private static func recordRuntimeStoreInfo(candidate: PersistentStoreCandidate, fallbackReason: String?) {
        runtimeStoreInfo = RuntimeStoreInfo(
            storeURL: candidate.storeURL,
            cloudKitContainerIdentifier: candidate.usesCloudKit ? AppIdentity.iCloudContainerIdentifier : nil,
            usesCloudKit: candidate.usesCloudKit,
            usesAppGroup: candidate.usesAppGroup,
            isInMemory: candidate.isInMemory,
            allowsStoreReset: candidate.allowsStoreReset,
            createdAt: .now,
            fallbackReason: fallbackReason
        )

        #if DEBUG
        syncLogger.info("""
        ModelContainer created. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        appGroup=\(candidate.usesAppGroup) resetAllowed=\(candidate.allowsStoreReset) \
        ubiquityTokenPresent=\(FileManager.default.ubiquityIdentityToken != nil)
        """)
        if let fallbackReason {
            syncLogger.error("\(fallbackReason, privacy: .public)")
        }
        #endif
    }

    private static func logStoreCandidate(_ candidate: PersistentStoreCandidate) {
        #if DEBUG
        syncLogger.info("""
        Trying ModelContainer candidate. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        appGroup=\(candidate.usesAppGroup) inMemory=\(candidate.isInMemory)
        """)
        #endif
    }

    private static func logStoreCandidateFailure(_ candidate: PersistentStoreCandidate, error: Error) {
        #if DEBUG
        syncLogger.error("""
        ModelContainer candidate failed. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        error=\(String(describing: error), privacy: .public)
        """)
        #endif
    }

    private static func logICloudAccountState() {
        #if DEBUG
        guard canAttemptCloudKitPersistence(), runtimeStoreInfo.usesCloudKit else { return }
        syncLogger.info("ubiquityIdentityToken present: \(FileManager.default.ubiquityIdentityToken != nil)")
        CKContainer(identifier: AppIdentity.iCloudContainerIdentifier).accountStatus { status, error in
            Task { @MainActor in
                if let error {
                    syncLogger.error("CloudKit accountStatus error: \(String(describing: error), privacy: .public)")
                    return
                }
                syncLogger.info("CloudKit accountStatus for \(AppIdentity.iCloudContainerIdentifier, privacy: .public): \(String(describing: status), privacy: .public)")
            }
        }
        #endif
    }

    static func startCloudKitEventObserver() {
        guard cloudKitEventObserver == nil else { return }
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            Task { @MainActor in
                recordCloudKitEvent(event)
                guard event.type == .import, event.endDate != nil, event.succeeded else { return }
                guard persistentStoreError == nil else { return }
                // Coalesce a burst of completed imports, then reconcile even
                // when the user keeps the dashboard open throughout the sync.
                cloudKitReconciliationTask?.cancel()
                cloudKitReconciliationTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                        try Task.checkCancellation()
                        let context = ModelContext(sharedModelContainer)
                        _ = try reconcileSyncedData(context: context)
                        // Publish the imported state. Replaying progression or
                        // rewriting the catalog on each import can provoke a
                        // new export/import cycle while sync is still settling.
                        try refreshWidgetSnapshot(context: context)
                    } catch is CancellationError {
                        // A newer import will perform the refresh.
                    } catch {
                        logRefreshFailure("CloudKit import reconciliation", error)
                    }
                }
            }
        }
    }

    private static func recordCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let type: String
        switch event.type {
        case .setup:
            type = "setup"
        case .import:
            type = "import"
        case .export:
            type = "export"
        @unknown default:
            type = "unknown"
        }

        var summary = event.endDate == nil ? "\(type) started" : "\(type) \(event.succeeded ? "succeeded" : "failed")"
        if let endDate = event.endDate {
            summary += " at \(endDate.formatted(date: .abbreviated, time: .standard))"
        }
        if let error = event.error {
            summary += " error=\(error.localizedDescription)"
        }

        diagnosticDefaults.set(summary, forKey: lastCloudKitEventDefaultsKey)
        diagnosticDefaults.set(Date(), forKey: lastCloudKitEventDateDefaultsKey)

        #if DEBUG
        syncLogger.info("CloudKit event: \(summary, privacy: .public)")
        #endif
    }

    static func recordLocalWrite(reason: String) {
        diagnosticDefaults.set(Date(), forKey: lastLocalWriteDefaultsKey)
        diagnosticDefaults.set(reason, forKey: lastLocalWriteReasonDefaultsKey)
        NotificationCenter.default.post(name: didRecordLocalWriteNotification, object: nil)

        #if DEBUG
        syncLogger.info("Local SwiftData write: \(reason, privacy: .public)")
        #endif
    }

    static var lastLocalWriteAt: Date? {
        diagnosticDefaults.object(forKey: lastLocalWriteDefaultsKey) as? Date
    }

    static var lastLocalWriteReason: String? {
        diagnosticDefaults.string(forKey: lastLocalWriteReasonDefaultsKey)
    }

    static var lastCloudKitEventSummary: String? {
        diagnosticDefaults.string(forKey: lastCloudKitEventDefaultsKey)
    }

    static var lastCloudKitEventAt: Date? {
        diagnosticDefaults.object(forKey: lastCloudKitEventDateDefaultsKey) as? Date
    }

    private static var diagnosticDefaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
    }

    private static func persistentStoreURL(useAppGroup: Bool) -> URL {
        let baseDirectory: URL

        if useAppGroup,
           let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier
           ) {
            baseDirectory = appGroupURL.appendingPathComponent("Application Support", isDirectory: true)
        } else {
            baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(AppIdentity.internalProjectName, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(AppIdentity.internalProjectName, isDirectory: true)
        }

        return baseDirectory.appendingPathComponent("\(AppIdentity.internalProjectName).store")
    }

    static func backupBeforeSchemaChange(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true]
        )
        // SwiftData stores the complete container model in each configured
        // store's metadata, even though its rows are partitioned by schema.
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: syncedModelTypes + localOnlyModelTypes) else {
            throw CocoaError(.persistentStoreInvalidType)
        }
        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }
        let backupDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("StoreBackups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        var excludedDirectory = backupDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        // Core Data copies the complete store, including uncheckpointed WAL
        // data and CloudKit metadata. Never copy just the SQLite main file.
        try copyPersistentStore(from: storeURL, to: backupDirectory.appendingPathComponent(storeURL.lastPathComponent))
    }

    static func copyPersistentStore(from sourceURL: URL, to destinationURL: URL) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: syncedModelTypes) else {
            throw CocoaError(.persistentStoreInvalidType)
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.replacePersistentStore(
            at: destinationURL,
            destinationOptions: nil, withPersistentStoreFrom: sourceURL,
            sourceOptions: [NSReadOnlyPersistentStoreOption: true], ofType: NSSQLiteStoreType
        )
    }

    static func refreshAppState() {
        guard persistentStoreError == nil else { return }
        let context = ModelContext(sharedModelContainer)
        do { _ = try reconcileSyncedData(context: context) } catch { logRefreshFailure("reconcileSyncedData", error) }
        do { try synchronizeCatalog(context: context) } catch { logRefreshFailure("synchronizeCatalog", error) }
        do { _ = try drainQuickLogQueue(context: context) } catch { logRefreshFailure("drainQuickLogQueue", error) }
        do { try refreshAllProgress(context: context, reason: .appRefresh) } catch { logRefreshFailure("refreshAllProgress", error) }
        do { try refreshWidgetSnapshot(context: context) } catch { logRefreshFailure("refreshWidgetSnapshot", error) }
        refreshHomeScreenQuickActions()
    }

    private static func logRefreshFailure(_ step: String, _ error: Error) {
        syncLogger.error("refreshAppState step \(step, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }

    /// Applies any quick logs queued by the interactive widget. Runs synchronously
    /// on the main actor so two drain points (cold launch + foreground) can't
    /// double-apply: the first call persists and clears, the second sees an empty
    /// queue. Boolean-session habits get one log per counted session.
    @discardableResult
    static func drainQuickLogQueue(context: ModelContext) throws -> Int {
        let pending = QuickLogQueue.pending()
        guard !pending.isEmpty else { return 0 }

        let habits = try fetchActiveHabits(context: context)
        var appliedCount = 0

        for (habitIDString, amount) in pending {
            guard
                amount > 0,
                let habitID = UUID(uuidString: habitIDString),
                let habit = habits.first(where: { $0.id == habitID })
            else {
                continue
            }

            if habit.measurementType == .booleanSession {
                let sessions = max(1, Int(amount.rounded()))
                for _ in 0..<sessions {
                    _ = try log(habit: habit, value: 1, date: .now, note: "Quick log", source: .widget, refreshProgressAfterSave: false, context: context)
                }
            } else {
                _ = try log(habit: habit, value: amount, date: .now, note: "Quick log", source: .widget, refreshProgressAfterSave: false, context: context)
            }
            appliedCount += 1
        }

        QuickLogQueue.clear()
        if appliedCount > 0 {
            try refreshAllProgress(context: context, reason: .logMutation)
            try? refreshWidgetSnapshot(context: context)
        }
        return appliedCount
    }

    static func fetchSettings(context: ModelContext) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let settings = try context.fetch(descriptor).first {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        recordLocalWrite(reason: "created default AppSettings")
        return settings
    }

    static func fetchExistingSettings(context: ModelContext) throws -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    static func fetchStats(context: ModelContext) throws -> [StatDomain] {
        let descriptor = FetchDescriptor<StatDomain>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    static func fetchActiveStats(context: ModelContext) throws -> [StatDomain] {
        canonicalStats(try fetchStats(context: context)).filter { $0.isActive }
    }

    /// All non-archived but disabled, plus archived, skills — i.e. everything that
    /// could be turned on from the Skill Library.
    static func fetchArchivedStats(context: ModelContext) throws -> [StatDomain] {
        try fetchStats(context: context).filter { !$0.isActive }
    }

    static func fetchHabits(context: ModelContext) throws -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    static func fetchActiveHabits(context: ModelContext) throws -> [Habit] {
        try fetchHabits(context: context).filter(\.active)
    }

    static func fetchLogs(context: ModelContext) throws -> [HabitLog] {
        let descriptor = FetchDescriptor<HabitLog>(sortBy: [SortDescriptor(\.date, order: .forward)])
        return try context.fetch(descriptor)
    }

    static func fetchResolutions(context: ModelContext) throws -> [WeeklyResolution] {
        let descriptor = FetchDescriptor<WeeklyResolution>(sortBy: [SortDescriptor(\.weekStartDate, order: .forward)])
        return try context.fetch(descriptor)
    }

    static func fetchImportedHealthWorkouts(context: ModelContext) throws -> [LocalHealthImportedWorkout] {
        let descriptor = FetchDescriptor<LocalHealthImportedWorkout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try context.fetch(descriptor)
    }

    static func fetchDismissedHealthWorkoutIDs(context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<DismissedHealthWorkout>()).map(\.workoutUUID))
    }

    /// Health-sourced logs keyed by workout UUID. Logs sync across devices, so
    /// this is how a device learns a workout was already imported elsewhere.
    static func fetchHealthLogsByWorkoutID(context: ModelContext) throws -> [String: HabitLog] {
        var logsByWorkoutID: [String: HabitLog] = [:]
        for log in try fetchLogs(context: context) where log.sourceType == .health {
            guard let workoutID = log.healthWorkoutUUID, logsByWorkoutID[workoutID] == nil else { continue }
            logsByWorkoutID[workoutID] = log
        }
        return logsByWorkoutID
    }

    /// Records that the user removed or ignored a Health workout so no device
    /// imports it again. Inserts only; the caller saves.
    static func dismissHealthWorkout(uuid workoutUUID: String, context: ModelContext) {
        let descriptor = FetchDescriptor<DismissedHealthWorkout>(
            predicate: #Predicate { $0.workoutUUID == workoutUUID }
        )
        guard ((try? context.fetchCount(descriptor)) ?? 0) == 0 else { return }
        context.insert(DismissedHealthWorkout(workoutUUID: workoutUUID))
    }

    static func awaitingAttributionStatKeys(context: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<LocalHealthImportedWorkout>(
            predicate: #Predicate { record in
                record.awaitingHabitAssignment == true && record.isDuplicate == false
            }
        )
        let records = try context.fetch(descriptor)
        return Set(records.map(\.statKeyRaw))
    }

    static func unmatchedWorkoutCount(forStatKey statKey: String, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<LocalHealthImportedWorkout>(
            predicate: #Predicate { record in
                record.statKeyRaw == statKey &&
                record.awaitingHabitAssignment == true &&
                record.isDuplicate == false
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func fetchGoals(context: ModelContext) throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [
            SortDescriptor(\.statusRaw),
            SortDescriptor(\.createdAt, order: .reverse)
        ])
        return try context.fetch(descriptor)
    }

    static func fetchActiveGoals(context: ModelContext) throws -> [Goal] {
        try fetchGoals(context: context).filter { $0.status == .active }
    }

    static func fetchGoals(for statKey: StatKey, context: ModelContext) throws -> [Goal] {
        try fetchGoals(context: context).filter { $0.linkedStatKey == statKey }
    }

    static func modelCounts(context: ModelContext) -> ModelCounts {
        ModelCounts(
            stats: ((try? context.fetch(FetchDescriptor<StatDomain>())) ?? []).count,
            habits: ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).count,
            logs: ((try? context.fetch(FetchDescriptor<HabitLog>())) ?? []).count,
            weeklyResolutions: ((try? context.fetch(FetchDescriptor<WeeklyResolution>())) ?? []).count,
            settings: ((try? context.fetch(FetchDescriptor<AppSettings>())) ?? []).count,
            healthImports: ((try? context.fetch(FetchDescriptor<LocalHealthImportedWorkout>())) ?? []).count,
            goals: ((try? context.fetch(FetchDescriptor<Goal>())) ?? []).count
        )
    }

    static func seedDefaultProfile(
        context: ModelContext,
        baselines: [StatKey: Int] = [:],
        selectedSkillKeys: Set<StatKey>? = nil,
        completeOnboarding: Bool = true
    ) throws {
        // nil keeps the catalog default: core skills on, optional skills off.
        let activeKeys = selectedSkillKeys ?? TrainingArcConfig.coreSkillKeys

        let existingStats = try fetchStats(context: context)
        guard existingStats.isEmpty else {
            try synchronizeCatalog(context: context)
            if selectedSkillKeys != nil {
                for stat in existingStats {
                    guard let key = stat.statKey else { continue }
                    applyOnboardingActivation(activeKeys.contains(key), to: stat, context: context)
                }
            }
            let settings = try fetchSettings(context: context)
            settings.hasCompletedOnboarding = completeOnboarding
            settings.updatedAt = .now
            try context.save()
            recordLocalWrite(reason: "updated existing default profile during onboarding")
            try refreshWidgetSnapshot(context: context)
            return
        }

        var statIndex: [StatKey: StatDomain] = [:]
        for (offset, template) in TrainingArcConfig.statTemplates.enumerated() {
            let baseline = max(TrainingArcConfig.minimumBaseline, baselines[template.key] ?? template.defaultBaseline)
            let startingLevel = TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(baseline))
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                sortOrder: offset,
                currentLevel: startingLevel,
                currentTierName: TrainingArcConfig.rankTitle(for: template.key, level: startingLevel),
                startingBaseline: baseline,
                currentBaseline: baseline,
                storedCharges: 0,
                bankedProgressUnits: 0,
                lastAcknowledgedLevel: startingLevel,
                isArchived: !activeKeys.contains(template.key),
                isCore: template.isCore,
                isEnabled: activeKeys.contains(template.key),
                parentSkillKeyRaw: template.parentKey?.rawValue
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statIndex[template.key] = stat
        }

        // Only skills chosen during onboarding get a starter habit. The rest
        // start archived; enabling one later creates its habit (see enableSkill).
        for (offset, template) in TrainingArcConfig.defaultHabitTemplates.enumerated()
        where activeKeys.contains(template.statKey) {
            let habit = Habit(
                systemKey: template.systemKey,
                name: template.name,
                notes: template.notes,
                measurementType: template.measurementType,
                unitLabel: template.unitLabel,
                scheduleType: template.scheduleType,
                targetPerPeriod: template.targetPerPeriod,
                active: true,
                sortOrder: offset,
                statDomain: statIndex[template.statKey]
            )
            context.insert(habit)
        }

        markSkillActivationMigrated()

        let settings = try fetchSettings(context: context)
        settings.hasCompletedOnboarding = completeOnboarding
        settings.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "seeded default onboarding profile")
        try refreshAllProgress(context: context, reason: .onboarding)
        try refreshWidgetSnapshot(context: context)
    }

    /// Matches an existing skill to the onboarding choice without touching its
    /// logs or history.
    private static func applyOnboardingActivation(_ isActive: Bool, to stat: StatDomain, context: ModelContext) {
        guard stat.isActive != isActive else { return }
        stat.isEnabled = isActive
        stat.isArchived = !isActive
        if isActive {
            ensureStarterHabit(for: stat, context: context)
        }
        stat.updatedAt = .now
    }

    static func clearAll(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<HealthImportedWorkout>()) { context.delete(item) }
        for item in try fetchImportedHealthWorkouts(context: context) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DismissedHealthWorkout>()) { context.delete(item) }
        for item in try fetchLogs(context: context) { context.delete(item) }
        for item in try fetchResolutions(context: context) { context.delete(item) }
        for item in try fetchGoals(context: context) { context.delete(item) }
        for item in try fetchHabits(context: context) { context.delete(item) }
        for item in try fetchStats(context: context) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(item) }
        try context.save()
        recordLocalWrite(reason: "cleared all local SwiftData records")
        let defaults = UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
        defaults.removeObject(forKey: AppIdentity.healthWorkoutAnchorKey)
        defaults.removeObject(forKey: AppIdentity.healthLastYearBackfillKey)
        try refreshWidgetSnapshot(context: context)
    }

    static func updateDerivedFields(for stat: StatDomain) {
        guard let key = stat.statKey else { return }
        let resolvedLevel = TrainingArcConfig.clampedRankLevel(stat.currentLevel)
        let resolvedTitle = TrainingArcConfig.rankTitle(for: key, level: resolvedLevel)
        let resolvedDescriptor = TrainingArcConfig.overview(for: key)
        let didMutate =
            stat.currentLevel != resolvedLevel ||
            stat.currentTierName != resolvedTitle ||
            stat.descriptor != resolvedDescriptor

        stat.rankLevel = resolvedLevel
        stat.rankTitle = resolvedTitle
        stat.descriptor = resolvedDescriptor
        stat.acknowledgedRankLevel = max(stat.acknowledgedRankLevel, TrainingArcConfig.minimumRankLevel)

        if didMutate {
            stat.updatedAt = .now
        }
    }

    static func synchronizeCatalog(context: ModelContext) throws {
        let existingStats = canonicalStats(try fetchStats(context: context))
        guard !existingStats.isEmpty else { return }

        var didMutate = false
        var statLookup = Dictionary(uniqueKeysWithValues: existingStats.compactMap { stat -> (StatKey, StatDomain)? in
            guard let key = stat.statKey else { return nil }
            return (key, stat)
        })

        for template in TrainingArcConfig.statTemplates {
            if let existing = statLookup[template.key] {
                let parentRaw = template.parentKey?.rawValue
                let didChange =
                    existing.name != template.key.displayName ||
                    existing.iconName != template.iconName ||
                    existing.colorToken != template.colorToken ||
                    existing.isCore != template.isCore ||
                    existing.parentSkillKeyRaw != parentRaw
                existing.name = template.key.displayName
                existing.iconName = template.iconName
                existing.colorToken = template.colorToken
                existing.isCore = template.isCore
                existing.parentSkillKeyRaw = parentRaw
                updateDerivedFields(for: existing)
                didMutate = didMutate || didChange
                continue
            }

            let nextSortOrder = (statLookup.values.map(\.sortOrder).max() ?? -1) + 1
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                sortOrder: nextSortOrder,
                currentLevel: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline)),
                currentTierName: TrainingArcConfig.rankTitle(
                    for: template.key,
                    level: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline))
                ),
                startingBaseline: template.defaultBaseline,
                currentBaseline: template.defaultBaseline,
                storedCharges: 0,
                bankedProgressUnits: 0,
                lastAcknowledgedLevel: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline)),
                isArchived: !template.isCore,
                isCore: template.isCore,
                isEnabled: template.isCore,
                parentSkillKeyRaw: template.parentKey?.rawValue
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statLookup[template.key] = stat
            didMutate = true

            // Optional skills are created archived with no habit; enabling one
            // later creates its starter habit on demand.
            if template.isCore {
                insertStarterHabit(for: template.key, stat: stat, context: context)
            }
        }

        if didMutate {
            try context.save()
            recordLocalWrite(reason: "synchronized catalog")
            try refreshAllProgress(context: context, reason: .appRefresh)
        }
    }

    /// Pass `refreshProgressAfterSave: false` when logging a batch (Health
    /// import, widget queue drain) and run one refreshAllProgress at the end;
    /// each per-log refresh replays every completed week for the skill.
    @discardableResult
    static func log(
        habit: Habit,
        value: Double,
        date: Date,
        sessionType: String? = nil,
        note: String,
        source: LogSourceType,
        healthWorkoutUUID: String? = nil,
        refreshProgressAfterSave: Bool = true,
        context: ModelContext
    ) throws -> HabitLog {
        let numericValue = habit.measurementType == .booleanSession ? 1 : max(0, value)
        let log = HabitLog(
            date: date,
            numericValue: numericValue,
            sessionType: normalizedSessionType(sessionType),
            note: note,
            sourceType: source,
            healthWorkoutUUID: healthWorkoutUUID,
            habit: habit
        )
        habit.updatedAt = .now
        context.insert(log)
        try context.save()
        recordLocalWrite(reason: "logged habit entry")
        if refreshProgressAfterSave {
            if let stat = habit.statDomain {
                try refreshProgress(for: stat, context: context, reason: .logMutation, now: max(date, .now))
            }
            try? refreshWidgetSnapshot(context: context)
        }
        return log
    }

    static func delete(_ log: HabitLog, context: ModelContext) throws {
        let stat = log.habit?.statDomain
        let affectedDate = log.date
        if log.sourceType == .health, let workoutUUID = log.healthWorkoutUUID {
            dismissHealthWorkout(uuid: workoutUUID, context: context)
        }
        context.delete(log)
        try context.save()
        recordLocalWrite(reason: "deleted habit entry")
        if let stat {
            try refreshProgress(for: stat, context: context, reason: .deleteMutation, now: max(affectedDate, .now))
        }
        try? refreshWidgetSnapshot(context: context)
    }

    static func total(for habit: Habit, in interval: DateInterval) -> Double {
        (habit.logs ?? [])
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.numericValue }
    }

    static func total(for stat: StatDomain, in interval: DateInterval) -> Double {
        (stat.habits ?? [])
            .filter(\.active)
            .reduce(0) { total, habit in
                total + self.total(for: habit, in: interval)
            }
    }

    static func activeHabits(for stat: StatDomain) -> [Habit] {
        (stat.habits ?? [])
            .filter(\.active)
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func primaryHabit(for stat: StatDomain) -> Habit? {
        activeHabits(for: stat).first
    }

    static func recentLogs(for stat: StatDomain) -> [HabitLog] {
        activeHabits(for: stat)
            .flatMap { $0.logs ?? [] }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }
    }

    static func progressionCalendar() -> Calendar {
        WeekMath.calendar(weekStartsOnMonday: true)
    }

    static func progressionWeek(containing date: Date) -> WeekRange {
        WeekMath.weekRange(containing: date, weekStartsOnMonday: true)
    }

    static func progressionWeekInterval(containing date: Date) -> DateInterval {
        WeekMath.dateInterval(for: progressionWeek(containing: date), calendar: progressionCalendar())
    }

    static func currentWeekInterval(settings: AppSettings?, now: Date = .now) -> DateInterval {
        progressionWeekInterval(containing: now)
    }

    static func currentWeekTotal(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        total(for: stat, in: currentWeekInterval(settings: settings, now: now))
    }

    static func currentCharge(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Int {
        stat.chargeValue
    }

    static func currentChargeProgress(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        guard let key = stat.statKey else { return 0 }
        return TrainingArcConfig.chargeProgress(for: key, bankedUnits: stat.bankedProgressUnits, level: stat.rankLevel)
    }

    /// Converts a workout duration into the logged value for a habit's
    /// measurement type (sessions and counts log 1; minutes log the duration).
    static func loggedValue(durationMinutes: Double, habit: Habit) -> Double {
        switch habit.measurementType {
        case .booleanSession: return 1
        case .minutes: return max(1, durationMinutes.rounded())
        case .count, .customNumber, .pages: return 1
        }
    }

    static func normalizedSessionType(_ sessionType: String?) -> String? {
        guard let trimmed = sessionType?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func setDashboardLayoutMode(_ mode: DashboardLayoutMode, context: ModelContext) throws {
        let settings = try fetchSettings(context: context)
        guard settings.dashboardLayoutMode != mode else { return }
        settings.dashboardLayoutMode = mode
        settings.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "updated dashboard layout mode")
        refreshHomeScreenQuickActions()
    }

    static func setSkillOrder(_ orderedStatIDs: [UUID], context: ModelContext) throws {
        let activeStats = try fetchActiveStats(context: context)
        let statsByID = Dictionary(uniqueKeysWithValues: activeStats.map { ($0.id, $0) })
        let orderedIDs = orderedStatIDs.filter { statsByID[$0] != nil }
        let remainingIDs = activeStats.map(\.id).filter { !orderedIDs.contains($0) }

        for (offset, id) in (orderedIDs + remainingIDs).enumerated() {
            guard let stat = statsByID[id] else { continue }
            if stat.sortOrder != offset {
                stat.sortOrder = offset
                stat.updatedAt = .now
            }
        }

        try context.save()
        recordLocalWrite(reason: "updated skill order")
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    // MARK: - Skill activation management

    /// Ensures an archived/optional skill has its starter habit (optional skills
    /// are created without one). No-op if any habit already exists.
    private static func ensureStarterHabit(for stat: StatDomain, context: ModelContext) {
        guard let key = stat.statKey else { return }
        guard (stat.habits ?? []).isEmpty else { return }
        insertStarterHabit(for: key, stat: stat, context: context)
    }

    /// Inserts the catalog starter habit for a skill (used when a skill is
    /// created or enabled without any habit of its own).
    private static func insertStarterHabit(for key: StatKey, stat: StatDomain, context: ModelContext) {
        let starter = TrainingArcConfig.definition(for: key).starterHabit
        let habit = Habit(
            systemKey: starter.systemKey,
            name: starter.name,
            notes: starter.notes,
            measurementType: starter.measurementType,
            unitLabel: starter.unitLabel,
            scheduleType: starter.scheduleType,
            targetPerPeriod: starter.targetPerPeriod,
            active: true,
            sortOrder: (try? fetchHabits(context: context).count) ?? 0,
            statDomain: stat
        )
        context.insert(habit)
    }

    /// Turns a skill on: enabled, not archived, with a starter habit if it had
    /// none. Appends it to the end of the active order. Data is never deleted.
    static func enableSkill(_ stat: StatDomain, context: ModelContext) throws {
        stat.isEnabled = true
        stat.isArchived = false
        ensureStarterHabit(for: stat, context: context)
        let maxOrder = (try fetchStats(context: context).map(\.sortOrder).max()) ?? 0
        stat.sortOrder = maxOrder + 1
        stat.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "enabled skill \(stat.key)")
        try refreshAllProgress(context: context, reason: .appRefresh)
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    /// Hides a skill from the active experience while keeping all logs, goals, and
    /// history intact. Fully reversible via `restoreSkill`.
    static func archiveSkill(_ stat: StatDomain, context: ModelContext) throws {
        stat.isArchived = true
        stat.isEnabled = false
        stat.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "archived skill \(stat.key)")
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    /// Brings an archived skill back into the active set. Identical to enabling.
    static func restoreSkill(_ stat: StatDomain, context: ModelContext) throws {
        try enableSkill(stat, context: context)
    }

    static func refreshHomeScreenQuickActions() {
        #if canImport(UIKit)
        HomeScreenQuickActionService.refresh(using: sharedModelContainer)
        #endif
    }
}
