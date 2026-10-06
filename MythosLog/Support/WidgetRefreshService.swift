import BackgroundTasks
import Foundation
import OSLog
import SwiftData

@MainActor
enum WidgetRefreshService {
    static let taskIdentifier = "studio.curateddesign.MythosLog.widgetRefresh"
    private static let logger = Logger(subsystem: "studio.curateddesign.MythosLog", category: "WidgetRefresh")

    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            Task { @MainActor in
                handle(task)
            }
        }
        if !registered {
            logger.error("Could not register widget background refresh")
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // This is an earliest start time; iOS decides when the check runs.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.info("Widget background refresh scheduling unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    static func refresh() async throws {
        guard TrainingStore.persistentStoreError == nil else {
            throw CocoaError(.persistentStoreOpen)
        }
        try Task.checkCancellation()
        var healthError: Error?
        #if canImport(HealthKit)
        do {
            try await HealthImportService.syncForWidget()
        } catch {
            healthError = error
        }
        #endif
        try Task.checkCancellation()
        try refreshLocalProgress(context: ModelContext(TrainingStore.sharedModelContainer))
        if let healthError { throw healthError }
    }

    /// Rebuild time-dependent values and consume widget logs even if Health is
    /// disconnected or there are no new workouts.
    static func refreshLocalProgress(context: ModelContext, now: Date = .now) throws {
        guard try TrainingStore.fetchExistingSettings(context: context)?.hasCompletedOnboarding == true else { return }
        _ = try TrainingStore.reconcileSyncedData(context: context)
        try TrainingStore.synchronizeCatalog(context: context)
        _ = try TrainingStore.drainQuickLogQueue(context: context)
        try TrainingStore.refreshAllProgress(context: context, reason: .appRefresh, now: now)
        try TrainingStore.refreshWidgetSnapshot(context: context, now: now)
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let completion = WidgetRefreshTaskCompletion { success in
            task.setTaskCompleted(success: success)
        }
        let work = Task { @MainActor in
            do {
                try await refresh()
                completion.finish(success: true)
            } catch {
                logger.error("Widget background refresh failed: \(String(describing: error), privacy: .public)")
                completion.finish(success: false)
            }
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }
}

/// Expiration and normal completion can race on different queues. Tell iOS the
/// result exactly once, including when a Health query outlives the time budget.
nonisolated final class WidgetRefreshTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let complete: (Bool) -> Void

    init(complete: @escaping (Bool) -> Void) {
        self.complete = complete
    }

    func finish(success: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        complete(success)
    }
}
