// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let store = GRStepJournalStore(root)
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else { fatalError(message) }
}
func refused(_ message: String, _ operation: () throws -> Void) {
    checks += 1
    do { try operation(); fatalError(message) } catch {}
}
let legacy = Data("{\"steps\":17,\"from\":\"1970-01-01T00:00:00.000Z\"}".utf8)
try legacy.write(to: root.appendingPathComponent("steps_pending.json"))
let first = try store.load(fallbackAnchor: 1000)
try check((first["total"] as? Int64) == 17, "legacy backlog migrates")
try store.commit(first, steps: 75_000, anchor: 2000)
let committed = try store.load(fallbackAnchor: 0)
try check((committed["total"] as? NSNumber)?.int64Value == 75_017, "complete backlog retained")
try check((committed["anchor"] as? Double) == 2000, "anchor and total committed together")
try check((committed["epoch"] as? String) == (first["epoch"] as? String), "epoch stable")
try check(Data(contentsOf: root.appendingPathComponent("steps_pending.json")) == legacy, "legacy source untouched")
try store.commit(committed, steps: 0, anchor: 2100)
let zero = try store.load(fallbackAnchor: 0)
try check((zero["anchor"] as? Double) == 2100, "empty windows still advance atomically")
try check((zero["total"] as? NSNumber)?.int64Value == 75_017, "empty windows do not invent steps")
let path = root.appendingPathComponent(GRStepJournalStore.name)
let before = try Data(contentsOf: path)
refused("negative steps refused") { try store.commit(zero, steps: -1, anchor: 2200) }
var overflow = zero; overflow["total"] = GRStepJournalStore.maximum
refused("overflow refused") { try store.commit(overflow, steps: 1, anchor: 2200) }
refused("nonfinite anchor refused") { try store.commit(zero, steps: 1, anchor: Double.nan) }
try check(Data(contentsOf: path) == before, "rejected transactions preserve bytes and anchor")
try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
refused("write failure is observable") { try store.commit(zero, steps: 10, anchor: 2300) }
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
try check(Data(contentsOf: path) == before, "failed atomic publication preserves prior snapshot")
try Data("{unfinished".utf8).write(to: path)
refused("corruption is not silently reset") { _ = try store.load(fallbackAnchor: 0) }
try Data(repeating: 32, count: 8193).write(to: path)
refused("oversized state refused") { _ = try store.load(fallbackAnchor: 0) }
try before.write(to: path)
for key in ["version", "anchor", "total"] {
    var invalid = zero; invalid[key] = true
    try JSONSerialization.data(withJSONObject: invalid).write(to: path)
    refused("boolean numeric journal fields refused") { _ = try store.load(fallbackAnchor: 0) }
}
try before.write(to: path)
try store.commit(zero, steps: 10, anchor: 2300)
let retried = try store.load(fallbackAnchor: 0)
try check((retried["total"] as? NSNumber)?.int64Value == 75_027, "retry commits exactly the missed delta")
try check((retried["anchor"] as? Double) == 2300, "retry commits its matching anchor")
print("Native steps Swift: \(checks) PASS")
