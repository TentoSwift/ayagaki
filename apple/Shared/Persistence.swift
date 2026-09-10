import CoreData

/// Core Data + CloudKit（iCloud 同期）。モデルはコードで定義する。
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    /// このプロセスの書き込み識別子（GUI / stdio MCP を区別）
    private static let author =
        ProcessInfo.processInfo.arguments.contains("--mcp") ? "mcp-stdio" : "app"

    private var historyContext: NSManagedObjectContext?
    private var historyToken: NSPersistentHistoryToken?
    private var remoteChangeObserver: NSObjectProtocol?

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
            // 組み方（"yasuda" / "korai"）。既存データは既定値 "yasuda" で軽量マイグレーションされる
            attr("braidType", .stringAttributeType, defaultValue: BraidType.yasuda.rawValue),
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
            // 属性追加は軽量マイグレーションで吸収する（既存データを壊さない）
            desc.shouldMigrateStoreAutomatically = true
            desc.shouldInferMappingModelAutomatically = true
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
        container.viewContext.transactionAuthor = Self.author

        // 別プロセス（stdio MCP / GUI）や CloudKit の変更を Persistent History でマージする
        let coordinator = container.persistentStoreCoordinator
        historyToken = coordinator.currentPersistentHistoryToken(fromStores: coordinator.persistentStores)
        historyContext = container.newBackgroundContext()
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: nil
        ) { [weak self] _ in
            self?.mergeRemoteChanges()
        }
    }

    /// 他プロセスのトランザクションを viewContext に取り込み、開いている画面へ通知する
    private func mergeRemoteChanges() {
        guard let historyContext else { return }
        historyContext.perform { [weak self] in
            guard let self else { return }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.historyToken)
            guard let result = try? historyContext.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }
            self.historyToken = transactions.last?.token ?? self.historyToken

            // 自プロセスの保存は viewContext に反映済みなので除外
            let foreign = transactions.filter { $0.author != Self.author }
            guard !foreign.isEmpty else { return }
            let changedIDs = Set(foreign.flatMap { $0.changes ?? [] }.map(\.changedObjectID))

            DispatchQueue.main.async {
                for tx in foreign {
                    self.container.viewContext.mergeChanges(fromContextDidSave: tx.objectIDNotification())
                }
                for objectID in changedIDs {
                    NotificationCenter.default.post(name: BraidSpec.externalChangeNotification,
                                                    object: objectID)
                }
            }
        }
    }
}
