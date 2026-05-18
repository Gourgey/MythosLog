# ArcLog CloudKit Sync Debugging

ArcLog's production SwiftData store should be created by `TrainingStore.makeModelContainer()` with:

```swift
cloudKitDatabase: .private("iCloud.studio.curateddesign.ArcLog")
```

In Debug, the shared `ArcLog` scheme enables:

```text
-com.apple.CoreData.CloudKitDebug 1
-com.apple.CoreData.Logging.stderr 1
```

Run both the physical iPhone and the Simulator from Xcode with the `ArcLog` scheme. Filter the console for `SwiftDataCloudKit`, `CloudKit`, or `CoreData`.

What to check:

- `ModelContainer created` should say `cloudKit=private(iCloud.studio.curateddesign.ArcLog)`.
- If it says `cloudKit=none`, the app is using local-only persistence and will not sync.
- `ubiquityIdentityToken present: true` confirms the OS sees an iCloud identity.
- `CloudKit accountStatus ... available` confirms the selected CloudKit container can see an available account.
- `CloudKit event: import/export succeeded` confirms Core Data/CloudKit mirroring is moving data.

In the app, open Settings in a Debug build and use `Sync Diagnostics`. The useful rows are:

- `Store URL`: verifies both launches are using a stable on-disk store path.
- `Container`: shows whether the active store actually selected the CloudKit container.
- `Last Local Write`: confirms the app recorded a local mutation after a log, seed, import, or settings change.
- `Last Import/Export`: shows the last Core Data CloudKit mirroring event if the framework posts one.
- `Counts`: quick sanity check for imported records after waiting on sync.

Fresh install retest:

1. Install on the first device, complete onboarding, add a uniquely named log.
2. Launch the second device and wait at least 60 seconds before completing onboarding.
3. Check Settings > Sync Diagnostics. The second device should eventually show `Container` as `iCloud.studio.curateddesign.ArcLog` and record counts should rise without reseeding local defaults first.
4. Add a log on the second device, leave both apps foregrounded or background/foreground them, then watch for export/import events in the Xcode console.
