// iOS native step journal. Existing HealthKit consent remains user controlled.
// Original journal additions: Copyright (c) 2026 Roxas2712.
// See LICENSE-ROXAS2712.md; existing contribution grants remain effective.
import Foundation
import CoreFoundation

// Foundation-only storage is also exercised by the desktop fault tests.
final class GRStepJournalStore {
    static let name = "steps_journal.json"
    static let maximum: Int64 = 9_007_199_254_740_991
    enum Failure: Error { case invalidJournal, oversized, publication }
    let directory: URL
    init(_ directory: URL) { self.directory = directory }
    private func validText(_ value: String) -> Bool {
        value.utf8.count <= 64 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private func read(_ url: URL) throws -> [String: Any] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8192 else { throw Failure.oversized }
        let data = try Data(contentsOf: url)
        guard data.count <= 8192,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.invalidJournal }
        return value
    }
    func load(fallbackAnchor: Double) throws -> [String: Any] {
        let url = directory.appendingPathComponent(Self.name)
        if FileManager.default.fileExists(atPath: url.path) {
            let state = try read(url)
            guard let version = state["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
                  (state["source"] as? String) == "healthkit",
                  let epoch = state["epoch"] as? String,
                  epoch.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil,
                  let total = state["total"] as? NSNumber,
                  CFGetTypeID(total) != CFBooleanGetTypeID(),
                  total.doubleValue.isFinite, total.doubleValue >= 0,
                  total.doubleValue <= Double(Self.maximum), total.doubleValue.rounded(.down) == total.doubleValue,
                  let rawAnchor = state["anchor"] as? NSNumber,
                  CFGetTypeID(rawAnchor) != CFBooleanGetTypeID(),
                  rawAnchor.doubleValue.isFinite, rawAnchor.doubleValue >= 0,
                  let from = state["from"] as? String, validText(from),
                  let to = state["to"] as? String, validText(to)
            else { throw Failure.invalidJournal }
            return state
        }
        var total: Int64 = 0
        var from = Self.iso(Date(timeIntervalSince1970: fallbackAnchor))
        let legacy = directory.appendingPathComponent("steps_pending.json")
        if FileManager.default.fileExists(atPath: legacy.path) {
            let pending = try read(legacy)
            guard let count = pending["steps"] as? NSNumber,
                  CFGetTypeID(count) != CFBooleanGetTypeID(),
                  count.doubleValue.isFinite, count.doubleValue >= 0,
                  count.doubleValue <= Double(Self.maximum), count.doubleValue.rounded(.down) == count.doubleValue
            else { throw Failure.invalidJournal }
            total = count.int64Value
            if let first = pending["from"] as? String, validText(first) { from = first }
        }
        return ["version": 1, "source": "healthkit",
                "epoch": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                "total": total, "anchor": fallbackAnchor, "from": from, "to": from]
    }
    func commit(_ previous: [String: Any], steps: Int64, anchor: Double) throws {
        guard steps >= 0, let old = previous["total"] as? NSNumber,
              steps <= Self.maximum - old.int64Value, anchor.isFinite, anchor >= 0
        else { throw Failure.invalidJournal }
        var state = previous
        state["total"] = old.int64Value + steps
        state["anchor"] = anchor
        state["to"] = Self.iso(Date(timeIntervalSince1970: anchor))
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        guard data.count <= 8192 else { throw Failure.oversized }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.name)
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else { throw Failure.publication }
    }
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

#if os(iOS)
import HealthKit
@objc(GRHealthBridge)
public final class GRHealthBridge: NSObject {
    private static let store = HKHealthStore()
    private static let gate = NSLock()
    private static var activeDirectory: String?
    private static let anchorKey = "GRHealthLastSyncDate"
    private static func finish() { gate.lock(); activeDirectory = nil; gate.unlock() }

    @objc(syncStepsWithCommand:saveDir:)
    public static func syncSteps(command: UnsafePointer<CChar>?, saveDir: UnsafePointer<CChar>?) -> Bool {
        guard let dir = saveDir.map({ String(cString: $0) }), !dir.isEmpty else { return false }
        gate.lock()
        if let active = activeDirectory { gate.unlock(); return active == dir }
        activeDirectory = dir
        gate.unlock()
        guard prepareJournal(dir: dir), HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { finish(); return false }
        store.requestAuthorization(toShare: nil, read: [stepType]) { _, error in
            if let error = error { NSLog("GRHealthBridge: authorization error: \(error)"); finish(); return }
            runQuery(stepType: stepType, dir: dir)
        }
        return true
    }
    private static func prepareJournal(dir: String) -> Bool {
        let defaults = UserDefaults.standard
        let journal = GRStepJournalStore(URL(fileURLWithPath: dir, isDirectory: true))
        let exists = FileManager.default.fileExists(atPath: journal.directory.appendingPathComponent(GRStepJournalStore.name).path)
        let marker = "GRStepJournalInitialized:" + dir
        if defaults.bool(forKey: marker) && !exists {
            NSLog("GRHealthBridge: initialized journal missing; anchor preserved")
            return false
        }
        do {
            let fallback = (defaults.object(forKey: anchorKey) as? Date) ?? Calendar.current.startOfDay(for: Date())
            let previous = try journal.load(fallbackAnchor: fallback.timeIntervalSince1970)
            if !exists { try journal.commit(previous, steps: 0, anchor: previous["anchor"] as! Double) }
            defaults.set(true, forKey: marker)
            return true
        } catch { NSLog("GRHealthBridge: journal initialization error: \(error)"); return false }
    }
    private static func runQuery(stepType: HKQuantityType, dir: String) {
        let defaults = UserDefaults.standard
        let journal = GRStepJournalStore(URL(fileURLWithPath: dir, isDirectory: true))
        let marker = "GRStepJournalInitialized:" + dir
        if defaults.bool(forKey: marker) && !FileManager.default.fileExists(
            atPath: journal.directory.appendingPathComponent(GRStepJournalStore.name).path) {
            NSLog("GRHealthBridge: initialized journal is missing; anchor preserved")
            finish(); return
        }
        let previous: [String: Any]
        do {
            let fallback = (defaults.object(forKey: anchorKey) as? Date) ?? Calendar.current.startOfDay(for: Date())
            previous = try journal.load(fallbackAnchor: fallback.timeIntervalSince1970)
        } catch { NSLog("GRHealthBridge: journal read error: \(error)"); finish(); return }
        let now = Date()
        let anchor = Date(timeIntervalSince1970: previous["anchor"] as! Double)
        guard anchor < now else { finish(); return }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, error in
            defer { finish() }
            if let error = error { NSLog("GRHealthBridge: step query error: \(error)"); return }
            let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            guard count.isFinite, count >= 0, count <= Double(GRStepJournalStore.maximum) else { return }
            do {
                try journal.commit(previous, steps: Int64(count.rounded(.down)), anchor: now.timeIntervalSince1970)
                defaults.set(true, forKey: marker)
            } catch { NSLog("GRHealthBridge: journal write error: \(error)") }
        }
        store.execute(query)
    }
}
#endif
