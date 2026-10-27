import AppKit
import Foundation
import Darwin

// A named, local app owns the narrow Documents-folder permission. Child
// Python inherits this app's identity; no Full Disk Access is requested.
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let statusDirectory = home.appendingPathComponent(".cache/origami-qa-storage/maintenance")
            try? FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
            func record(_ code: Int, _ message: String) {
                let value: [String: Any] = ["time": Date().timeIntervalSince1970, "exit_code": code, "message": message]
                if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) {
                    try? data.write(to: statusDirectory.appendingPathComponent("wrapper-status.json"), options: .atomic)
                }
            }
            do {
                // Trigger the normal macOS Documents request under this app's
                // visible identity before starting any cleanup.
                _ = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Documents").path)
                let arguments = Array(CommandLine.arguments.dropFirst())
                guard let script = arguments.first, script.hasSuffix("/qa_maintenance.py") else {
                    record(2, "Missing installed maintenance entry point")
                    exit(2)
                }
                let child = Process()
                child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                child.arguments = arguments
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                try child.run()
                child.waitUntilExit()
                record(Int(child.terminationStatus), "Maintenance finished")
                exit(child.terminationStatus)
            } catch {
                record(1, error.localizedDescription)
                exit(1)
            }
        }
    }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
