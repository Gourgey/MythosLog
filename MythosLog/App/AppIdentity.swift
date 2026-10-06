import Foundation

enum AppIdentity {
    nonisolated static let internalProjectName = "MythosLog"
    nonisolated static let displayName = "Mythos Log"
    nonisolated static let iCloudContainerIdentifier = "iCloud.studio.curateddesign.MythosLog"
    nonisolated static let appGroupIdentifier = "group.studio.curateddesign.mythoslog"
    nonisolated static let widgetSnapshotFileName = "mythoslog-widget-snapshot.json"
    nonisolated static let widgetSnapshotDefaultsKey = "mythoslog.widget.snapshot"
    nonisolated static let pendingDestinationKey = "training.arc.pending.destination"
    nonisolated static let healthWorkoutAnchorKey = "training.arc.health.anchor"
    // ".v2": Health import records moved to a local-only store in 1.0 build 2.
    // The new key forces one year backfill so that store is rebuilt from HealthKit.
    nonisolated static let healthLastYearBackfillKey = "training.arc.health.lastYearBackfillAt.v2"
    nonisolated static let websiteURL = URL(string: "https://curateddesign.studio/apps/mythos-log/")!
    nonisolated static let privacyPolicyURL = URL(string: "https://curateddesign.studio/apps/mythos-log/privacy/")!
}
