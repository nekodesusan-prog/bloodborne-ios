// bloodborne-ios: the JIT helper, PlugIns/BloodborneJITHelper.appex. The app starts it at Play
// (app/jit_builtin.m) because a process cannot attach a debugger to itself. One request: the
// app's process ID and the player's pairing file; the helper runs StikJIT
// (github.com/StikDebug/StikJIT, MPL-2.0) with its universal script, which bbcpu's breakpoint
// calls drive on devices with TXM, and answers when StikJIT returns: at once without TXM, once
// the script has detached with it.
import Foundation
import StikJIT

@objc(BloodborneJITHelper)
final class BloodborneJITHelper: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "bloodborne.jit-helper")

    func beginRequest(with context: NSExtensionContext) {
        let input = (context.inputItems.first as? NSExtensionItem)?.userInfo?["BBJITRequest"] as? Data
        Self.queue.async {
            let answer = Self.enable(input)
            NSLog("[BloodborneJIT] ok=%d %@", answer["ok"] as? Bool == true ? 1 : 0,
                  answer["message"] as? String ?? "")
            let item = NSExtensionItem()
            item.userInfo = ["BBJITResponse": (try? JSONSerialization.data(withJSONObject: answer)) ?? Data()]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }

    private static func enable(_ input: Data?) -> [String: Any] {
        let txm = StikJIT.isTXMPresent.map { $0 ? "1" : "0" } ?? "?"
        guard let input,
              let request = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let pid = (request["pid"] as? NSNumber)?.int32Value,
              let pairing = (request["pairing"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
            return ["ok": false, "message": "The app sent no process ID or pairing file.", "txm": txm]
        }
        let manager = FileManager.default
        let root = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true)
        let pairingURL = root.appendingPathComponent("pairing-\(UUID().uuidString).plist")
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try pairing.write(to: pairingURL, options: .atomic)
            defer { try? manager.removeItem(at: pairingURL) }
            try StikJIT.enableJIT(targetPID: pid,
                                  pairingFile: pairingURL,
                                  ddiPaths: DDIPaths.default(in: root),
                                  script: .universal,
                                  preparationProgress: { NSLog("[BloodborneJIT] %@", String(describing: $0)) },
                                  progress: { NSLog("[BloodborneJIT] %@", $0) })
            return ["ok": true, "message": "JIT enabled; the debugger detached.", "txm": txm]
        } catch {
            return ["ok": false, "message": error.localizedDescription, "txm": txm]
        }
    }
}
