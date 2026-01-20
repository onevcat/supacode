import AppKit
import GhosttyKit

final class GhosttySurfaceView: NSView {
    private let runtime: GhosttyRuntime
    private(set) var surface: ghostty_surface_t?
    private let workingDirectoryCString: UnsafeMutablePointer<CChar>?
    private var trackingArea: NSTrackingArea?
    private var lastBackingSize: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    init(runtime: GhosttyRuntime, workingDirectory: URL?) {
        self.runtime = runtime
        if let workingDirectory {
            let path = workingDirectory.path(percentEncoded: false)
            workingDirectoryCString = path.withCString { strdup($0) }
        } else {
            workingDirectoryCString = nil
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true
        createSurface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        closeSurface()
        if let workingDirectoryCString {
            free(workingDirectoryCString)
        }
    }

    func closeSurface() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentScale()
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
        updateSurfaceSize()
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            setSurfaceFocus(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            setSurfaceFocus(false)
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        sendKey(event: event, action: action)
    }

    override func keyUp(with event: NSEvent) {
        sendKey(event: event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        let mods = ghosttyMods(event.modifierFlags)
        var action = GHOSTTY_ACTION_RELEASE
        if (mods.rawValue & mod) != 0 {
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default:
                sidePressed = true
            }
            if sidePressed {
                action = GHOSTTY_ACTION_PRESS
            }
        }
        sendKey(event: event, action: action)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func otherMouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, 0)
    }

    func updateSurfaceSize() {
        guard let surface else { return }
        let backingSize = convertToBacking(bounds.size)
        if backingSize == lastBackingSize {
            return
        }
        lastBackingSize = backingSize
        let width = UInt32(max(1, Int(backingSize.width.rounded(.down))))
        let height = UInt32(max(1, Int(backingSize.height.rounded(.down))))
        ghostty_surface_set_size(surface, width, height)
    }

    private func createSurface() {
        guard let app = runtime.app else { return }
        var config = ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = backingScaleFactor()
        config.working_directory = workingDirectoryCString.map { UnsafePointer($0) }
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        surface = ghostty_surface_new(app, &config)
        updateSurfaceSize()
    }

    private func updateContentScale() {
        guard let surface else { return }
        let scale = backingScaleFactor()
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    private func backingScaleFactor() -> Double {
        if let window {
            return window.backingScaleFactor
        }
        if let screen = NSScreen.main {
            return screen.backingScaleFactor
        }
        return 2.0
    }

    private func setSurfaceFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let surface else { return false }
        if window?.firstResponder !== self { return false }
        let (translationEvent, translationMods) = translationState(event, surface: surface)
        var key = ghosttyKeyEvent(translationEvent, action: GHOSTTY_ACTION_PRESS, translationMods: translationMods)
        let text = ghosttyCharacters(translationEvent) ?? ""
        if !text.isEmpty, let codepoint = text.utf8.first, codepoint >= 0x20 {
            let isBinding = text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key_is_binding(surface, key, nil)
            }
            if isBinding {
                return text.withCString { ptr in
                    key.text = ptr
                    return ghostty_surface_key(surface, key)
                }
            }
        } else {
            key.text = nil
            if ghostty_surface_key_is_binding(surface, key, nil) {
                return ghostty_surface_key(surface, key)
            }
        }

        if event.charactersIgnoringModifiers == "\r" {
            if !event.modifierFlags.contains(.control) {
                return false
            }
            if let finalEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) {
                sendKey(event: finalEvent, action: GHOSTTY_ACTION_PRESS)
                return true
            }
        }

        if event.charactersIgnoringModifiers == "/" {
            if !event.modifierFlags.contains(.control) ||
                !event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) {
                return false
            }
            if let finalEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: "_",
                charactersIgnoringModifiers: "_",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) {
                sendKey(event: finalEvent, action: GHOSTTY_ACTION_PRESS)
                return true
            }
        }

        return false
    }

    @IBAction func copy(_ sender: Any?) {
        performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        performBindingAction("paste_from_clipboard")
    }

    @IBAction func pasteSelection(_ sender: Any?) {
        performBindingAction("paste_from_selection")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        performBindingAction("select_all")
    }

    private func sendKey(event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }
        let (translationEvent, translationMods) = translationState(event, surface: surface)
        var key = ghosttyKeyEvent(translationEvent, action: action, translationMods: translationMods)
        if let text = ghosttyCharacters(translationEvent),
           !text.isEmpty,
           let codepoint = text.utf8.first,
           codepoint >= 0x20 {
            text.withCString { ptr in
                key.text = ptr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func performBindingAction(_ action: String) {
        guard let surface else { return }
        _ = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.lengthOfBytes(using: .utf8)))
        }
    }

    private func translationState(_ event: NSEvent, surface: ghostty_surface_t) -> (NSEvent, NSEvent.ModifierFlags) {
        let translatedModsGhostty = ghostty_surface_key_translation_mods(surface, ghosttyMods(event.modifierFlags))
        let translatedMods = appKitMods(translatedModsGhostty)
        var resolved = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translatedMods.contains(flag) {
                resolved.insert(flag)
            } else {
                resolved.remove(flag)
            }
        }
        if resolved == event.modifierFlags {
            return (event, resolved)
        }
        let translatedEvent = NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: resolved,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: resolved) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
        return (translatedEvent, resolved)
    }

    private func ghosttyKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags
    ) -> ghostty_input_key_s {
        var key_ev: ghostty_input_key_s = .init()
        key_ev.action = action
        key_ev.keycode = UInt32(event.keyCode)
        key_ev.text = nil
        key_ev.composing = false
        key_ev.mods = ghosttyMods(event.modifierFlags)
        key_ev.consumed_mods = ghosttyMods(translationMods.subtracting([.control, .command]))
        key_ev.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key_ev.unshifted_codepoint = codepoint.value
            }
        }
        return key_ev
    }

    private func ghosttyCharacters(_ event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let y = bounds.height - point.y
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, point.x, y, mods)
    }

    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, state, button, mods)
    }

    private func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        let rawFlags = flags.rawValue
        if (rawFlags & UInt(NX_DEVICERSHIFTKEYMASK)) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if (rawFlags & UInt(NX_DEVICERCTLKEYMASK)) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if (rawFlags & UInt(NX_DEVICERALTKEYMASK)) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if (rawFlags & UInt(NX_DEVICERCMDKEYMASK)) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }

    private func appKitMods(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue) != 0 { flags.insert(.shift) }
        if (mods.rawValue & GHOSTTY_MODS_CTRL.rawValue) != 0 { flags.insert(.control) }
        if (mods.rawValue & GHOSTTY_MODS_ALT.rawValue) != 0 { flags.insert(.option) }
        if (mods.rawValue & GHOSTTY_MODS_SUPER.rawValue) != 0 { flags.insert(.command) }
        if (mods.rawValue & GHOSTTY_MODS_CAPS.rawValue) != 0 { flags.insert(.capsLock) }
        return flags
    }

}
