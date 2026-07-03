import CoreData

/// Core Data + CloudKit（iCloud 同期）。モデルはコードで定義する。
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Design"
        entity.managedObjectClassName = "Design"

        func attr(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true  // CloudKit 同期の要件に合わせ全て optional
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        let cells = attr("cellsData", .binaryDataAttributeType)
        cells.allowsExternalBinaryDataStorage = true

        entity.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("tama", .integer16AttributeType, defaultValue: 60),
            attr("rows", .integer16AttributeType, defaultValue: BraidSpec.defaultRows),
            attr("readDir", .stringAttributeType),
            attr("paletteJSON", .stringAttributeType),
            cells,
            attr("createdAt", .dateAttributeType),
            attr("updatedAt", .dateAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Ayagaki", managedObjectModel: Self.makeModel())

        if let desc = container.persistentStoreDescriptions.first {
            if inMemory { desc.url = URL(fileURLWithPath: "/dev/null") }
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            desc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.tento.ayagaki")
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        // iCloud 未設定・未サインインなどで失敗した場合はローカルのみで再試行
        if loadError != nil, let desc = container.persistentStoreDescriptions.first {
            NSLog("Ayagaki: CloudKit ストアの読み込みに失敗、ローカルのみで続行: \(loadError!.localizedDescription)")
            desc.cloudKitContainerOptions = nil
            container.loadPersistentStores { _, error in
                if let error { NSLog("Ayagaki: ローカルストアも失敗: \(error.localizedDescription)") }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
