import AppKit
import GhosttyKit
import UniformTypeIdentifiers

final class GhosttyRuntime {
    private var config: ghostty_config_t?
    private(set) var app: ghostty_app_t?
    private var observers: [NSObjectProtocol] = []

    init() {
        guard let config = ghostty_config_new() else {
            preconditionFailure("ghostty_config_new failed")
        }
        self.config = config
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in GhosttyRuntime.wakeup(userdata) },
            action_cb: { app, target, action in
                guard let app else { return false }
                return GhosttyRuntime.action(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, loc, state in GhosttyRuntime.readClipboard(userdata, location: loc, state: state) },
            confirm_read_clipboard_cb: { userdata, str, state, request in
                GhosttyRuntime.confirmReadClipboard(userdata, string: str, state: state, request: request)
            },
            write_clipboard_cb: { userdata, loc, content, len, confirm in
                GhosttyRuntime.writeClipboard(userdata, location: loc, content: content, len: len, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in GhosttyRuntime.closeSurface(userdata, processAlive: processAlive) }
        )

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            preconditionFailure("ghostty_app_new failed")
        }
        self.app = app

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAppFocus(true)
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAppFocus(false)
        })
    }

    deinit {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    func setAppFocus(_ focused: Bool) {
        if let app {
            ghostty_app_set_focus(app, focused)
        }
    }

    func tick() {
        if let app {
            ghostty_app_tick(app)
        }
    }

    private static func runtime(from userdata: UnsafeMutableRawPointer?) -> GhosttyRuntime? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func surfaceView(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let runtime = runtime(from: userdata) else { return }
        Task { @MainActor in
            runtime.tick()
        }
    }

    private static func action(_ app: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        return false
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let surfaceView = surfaceView(from: userdata), let surface = surfaceView.surface else { return }
        let value = NSPasteboard.ghostty(location)?.getOpinionatedStringContents() ?? ""
        Task { @MainActor in
            value.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }
    }

    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let surfaceView = surfaceView(from: userdata), let surface = surfaceView.surface else { return }
        guard let string else { return }
        let value = String(cString: string)
        Task { @MainActor in
            value.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
            }
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }
        var items: [(mime: String, data: String)] = []
        items.reserveCapacity(len)
        for i in 0..<len {
            let item = content.advanced(by: i).pointee
            guard let mimePtr = item.mime, let dataPtr = item.data else { continue }
            items.append((mime: String(cString: mimePtr), data: String(cString: dataPtr)))
        }
        guard !items.isEmpty else { return }
        Task { @MainActor in
            guard let pasteboard = NSPasteboard.ghostty(location) else { return }
            let types = items.compactMap { NSPasteboard.PasteboardType(mimeType: $0.mime) }
            if !types.isEmpty {
                pasteboard.declareTypes(types, owner: nil)
            }
            for item in items {
                guard let type = NSPasteboard.PasteboardType(mimeType: item.mime) else { continue }
                pasteboard.setString(item.data, forType: type)
            }
        }
    }

    private static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        guard let surfaceView = surfaceView(from: userdata) else { return }
        surfaceView.closeSurface()
    }
}

extension NSPasteboard.PasteboardType {
    init?(mimeType: String) {
        switch mimeType {
        case "text/plain":
            self = .string
            return
        default:
            break
        }
        guard let utType = UTType(mimeType: mimeType) else {
            self.init(mimeType)
            return
        }
        self.init(utType.identifier)
    }
}

extension NSPasteboard {
    private static let ghosttyEscapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    private static func ghosttyEscape(_ str: String) -> String {
        var result = str
        for char in ghosttyEscapeCharacters {
            result = result.replacing(String(char), with: "\\\(char)")
        }
        return result
    }

    static var ghosttySelection: NSPasteboard = {
        NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    }()

    func getOpinionatedStringContents() -> String? {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL],
           urls.count > 0 {
            return urls
                .map { $0.isFileURL ? Self.ghosttyEscape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }
        return string(forType: .string)
    }

    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return Self.general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return Self.ghosttySelection
        default:
            return nil
        }
    }
}
