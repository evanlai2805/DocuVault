import Foundation
import SwiftData
import DocuVaultCore

/// Runs on foreground: deletes documents whose client retention has passed, leaving a tombstone.
/// Also lists documents inside the warning window for the Vault's red card.
@MainActor
enum RetentionManager {

    struct Warning: Identifiable {
        let doc: StoredDocument
        let daysLeft: Int
        var id: UUID { doc.id }
    }

    static func sweep(context: ModelContext, now: Date = Date()) {
        let all = (try? context.fetch(FetchDescriptor<StoredDocument>())) ?? []
        var changed = false
        for doc in all where Retention.status(expiresAt: doc.expiresAt, now: now) == .due {
            let owner = doc.person?.name ?? "—"
            let days = doc.person?.retentionDays ?? RetentionPolicy.clientDefaultDays
            context.insert(StoredTombstone(line: Retention.tombstoneLine(title: doc.title, type: doc.type, owner: owner, deletedAt: now, retentionDays: days), deletedAt: now))
            delete(doc, context: context)
            changed = true
        }
        if changed { try? context.save() }
    }

    static func warnings(in docs: [StoredDocument], now: Date = Date()) -> [Warning] {
        docs.compactMap { d in
            if case .warning(let left) = Retention.status(expiresAt: d.expiresAt, now: now) { return Warning(doc: d, daysLeft: left) }
            return nil
        }
        .sorted { $0.daysLeft < $1.daysLeft }
    }

    static func apply(_ action: Retention.Action, to doc: StoredDocument, context: ModelContext, now: Date = Date()) {
        switch Retention.apply(action, currentExpiry: doc.expiresAt, now: now) {
        case .newExpiry(let d): doc.expiresAt = d
        case .delete:
            let owner = doc.person?.name ?? "—"
            context.insert(StoredTombstone(line: Retention.tombstoneLine(title: doc.title, type: doc.type, owner: owner, deletedAt: now, retentionDays: 0)
                .replacingOccurrences(of: "after 0 d", with: "by hand"), deletedAt: now))
            delete(doc, context: context)
        }
        try? context.save()
    }

    static func delete(_ doc: StoredDocument, context: ModelContext) {
        for p in doc.pages { PageStore.delete(p.imageFileName) }
        context.delete(doc)
    }
}
