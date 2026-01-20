import AppKit

enum OpenWorktreeAction: CaseIterable, Identifiable {
    case finder
    case cursor
    case zed
    case ghostty
    case copyPath

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .finder:
            return "Open Finder"
        case .cursor:
            return "Cursor"
        case .zed:
            return "Zed"
        case .ghostty:
            return "Ghostty"
        case .copyPath:
            return "Copy Path"
        }
    }

    var systemImage: String {
        switch self {
        case .finder:
            return "folder"
        case .cursor:
            return "cursorarrow"
        case .zed:
            return "chevron.left.slash.chevron.right"
        case .ghostty:
            return "terminal"
        case .copyPath:
            return "doc.on.doc"
        }
    }

    var shortcut: AppShortcut? {
        switch self {
        case .finder:
            return AppShortcuts.openFinder
        case .copyPath:
            return AppShortcuts.copyPath
        case .cursor, .zed, .ghostty:
            return nil
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .cursor:
            return "com.todesktop.230313mzl4w4u92"
        case .zed:
            return "dev.zed.Zed"
        case .ghostty:
            return "com.mitchellh.ghostty"
        case .finder, .copyPath:
            return nil
        }
    }

    var helpText: String {
        if let shortcut {
            return "\(title) (\(shortcut.display))"
        }
        return title
    }

    func perform(with worktree: Worktree, onError: @escaping (OpenActionError) -> Void) {
        switch self {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
        case .copyPath:
            let path = worktree.workingDirectory.path(percentEncoded: false)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        case .cursor, .zed, .ghostty:
            guard let bundleIdentifier, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                onError(OpenActionError(
                    title: "\(title) not found",
                    message: "Install \(title) to open this worktree."
                ))
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([worktree.workingDirectory], withApplicationAt: appURL, configuration: configuration) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    onError(OpenActionError(
                        title: "Unable to open in \(self.title)",
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }
}
