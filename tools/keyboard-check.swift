// Drives a built Encore with real key presses and checks what actually happened: the
// pasteboard changed, the popover closed, the search took the typing. Run it through
// tools/keyboard-check.sh.
//
// It is one process on purpose. Shelling out to osascript for every key press costs a
// process launch each time, and fixed sleeps have to assume the worst; here the keys are
// CGEvents, the pasteboard and the window list are read directly, and every step waits
// for the condition it actually needs — so the run takes seconds, and a slow machine
// makes it wait longer rather than fail.

import AppKit
import CoreGraphics

// MARK: - Keys

enum Key: CGKeyCode {
    case escape = 53, `return` = 36, down = 125, up = 126, one = 18, v = 9, z = 6
}

let encoreBundleID = "io.github.sudonicolas.encore"

var encorePID: pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: encoreBundleID).first?
        .processIdentifier
}

/// Sends a key to Encore itself, by pid, rather than to whichever app is in front.
///
/// A menu bar app launched from a terminal does not reliably win activation from the
/// terminal or editor that started it, and a key posted to the system then lands in that
/// app instead of the popover — which looks exactly like the popover ignoring the
/// keyboard. Addressing the process directly takes activation out of the picture, so what
/// is left under test is the popover's key handling.
func press(_ key: Key, flags: CGEventFlags = [], global: Bool = false) {
    let source = CGEventSource(stateID: .hidSystemState)
    for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: isDown)
        event?.flags = flags
        if global || encorePID == nil {
            // The global hotkey is registered system-wide, so it has to go to the system.
            event?.post(tap: .cghidEventTap)
        } else {
            event?.postToPid(encorePID!)
        }
    }
    // Long enough for the key to be delivered and for SwiftUI to settle on the result
    // before the next one arrives — faster than a person types, slow enough to be fair.
    usleep(160_000)
}

// MARK: - Observing the app

/// Encore's on-screen windows, ignoring the status item. A menu bar app's popover is not
/// an Accessibility window, so the window server is asked directly.
func encoreWindows() -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return list.compactMap { window in
        guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "Encore",
              let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
        let number = { (key: String) in (bounds[key] as? NSNumber)?.doubleValue ?? 0 }
        let rect = CGRect(x: number("X"), y: number("Y"), width: number("Width"), height: number("Height"))
        guard rect.width > 100, rect.height > 100 else { return nil }
        return rect
    }
}

var isPopoverOpen: Bool { !encoreWindows().isEmpty }

/// Waits for a condition instead of sleeping for a guess. Returns false on timeout.
@discardableResult
func wait(upTo seconds: Double = 2.5, for condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(40_000)
    }
    return condition()
}

let pasteboard = NSPasteboard.general

/// A marker on the pasteboard, so "copied nothing" can't be mistaken for "copied the
/// same thing again".
func writeSentinel() -> Int {
    pasteboard.clearContents()
    pasteboard.setString("encore-keyboard-check-\(Int.random(in: 100000...999999))", forType: .string)
    return pasteboard.changeCount
}

func waitForCopy(after changeCount: Int) -> Bool {
    wait { pasteboard.changeCount != changeCount }
}

// MARK: - Popover state

/// True once Encore is the app the keyboard is talking to. Opening the popover activates
/// Encore, but activation lands a moment after the window appears — and a key posted in
/// that gap goes to whatever app was in front before, not to the popover. A person cannot
/// type that fast; this driver can, so it waits.
func openPopover() -> Bool {
    guard closePopover() else { return false }
    press(.v, flags: [.maskShift, .maskCommand], global: true)
    guard wait(for: { isPopoverOpen }) else { return false }
    // The search field takes focus a turn after the popover is up.
    usleep(300_000)
    return true
}

func mouse(_ type: CGEventType, at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
}

/// Closes it however it happens to be open, so the next check starts level. Waits for the
/// close animation to finish: toggling the hotkey at a popover that is still animating out
/// reopens it, which would show up as the next check's failure rather than this one's.
@discardableResult
func closePopover() -> Bool {
    for _ in 0..<2 {
        guard isPopoverOpen else { break }
        press(.escape)
        _ = wait(upTo: 1.4) { !isPopoverOpen }
    }
    if isPopoverOpen {
        // Escape is what is under test, so fall back to the hotkey rather than giving up.
        press(.v, flags: [.maskShift, .maskCommand], global: true)
        _ = wait(upTo: 1.6) { !isPopoverOpen }
    }
    // Let the close settle, and the focus handoff it triggers run.
    usleep(400_000)
    return !isPopoverOpen
}

/// Parks the pointer away from the popover, so a hover preview left over from one check
/// cannot change what the next one sees.
func parkPointer() {
    mouse(.mouseMoved, at: CGPoint(x: 5, y: 5))
}

/// A point on a row, a little below the search field.
func rowPoint() -> CGPoint? {
    guard let window = encoreWindows().min(by: { $0.minY < $1.minY }) else { return nil }
    return CGPoint(x: window.midX, y: window.minY + 110)
}

// MARK: - Checks

var results: [(name: String, passed: Bool, detail: String)] = []

func check(_ name: String, _ body: () -> (Bool, String)) {
    let (passed, detail) = body()
    results.append((name, passed, detail))
    FileHandle.standardError.write("  \(passed ? "pass" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")\n"
        .data(using: .utf8)!)
}

/// Opens the popover and fails the check cleanly if it won't open.
func withFreshPopover(_ body: () -> (Bool, String)) -> (Bool, String) {
    guard openPopover() else { return (false, "popover did not open") }
    defer { closePopover() }
    return body()
}

guard AXIsProcessTrusted() else {
    print("""
    BLOCKED: no Accessibility permission, so synthetic key presses go nowhere.

    Grant it to whatever runs this (Terminal, iTerm, your editor) in
    System Settings → Privacy & Security → Accessibility, then run it again.
    """)
    exit(2)
}

// 1. A row is highlighted by default, so Return copies with no arrowing first.
check("Return copies right after opening") {
    let mark = writeSentinel()
    return withFreshPopover {
        press(.return)
        return (waitForCopy(after: mark), waitForCopy(after: mark) ? "" : "pasteboard unchanged")
    }
}

// 2. The plainest case, and the one that was broken.
check("Escape closes right after opening") {
    guard openPopover() else { return (false, "popover did not open") }
    press(.escape)
    let closed = wait { !isPopoverOpen }
    if !closed { closePopover() }
    return (closed, closed ? "" : "still open")
}

// 3. Copying used to drop the search field's focus, and with it every popover key.
check("Escape closes after a copy") {
    _ = writeSentinel()
    guard openPopover() else { return (false, "popover did not open") }
    press(.down)
    press(.return)
    _ = wait(upTo: 1.2) { false }
    press(.escape)
    let closed = wait { !isPopoverOpen }
    if !closed { closePopover() }
    return (closed, closed ? "" : "still open")
}

// 4. The arrows really move the highlight: a different row ends up on the pasteboard.
check("Down arrow moves the highlight") {
    var mark = writeSentinel()
    guard openPopover() else { return (false, "popover did not open") }
    press(.return)
    guard waitForCopy(after: mark) else { closePopover(); return (false, "the top row did not copy") }
    let first = pasteboard.string(forType: .string) ?? ""
    closePopover()
    mark = writeSentinel()
    guard openPopover() else { return (false, "popover did not reopen") }
    press(.down)
    press(.down)
    press(.return)
    guard waitForCopy(after: mark) else { closePopover(); return (false, "nothing copied after two Downs") }
    let other = pasteboard.string(forType: .string) ?? ""
    closePopover()
    return (first != other, first == other ? "the same row copied both times" : "")
}

// 5. Escape peels one layer at a time: the search clears before the popover closes.
check("Escape clears the search, then closes") {
    guard openPopover() else { return (false, "popover did not open") }
    press(.z); press(.z)
    _ = wait(upTo: 0.8) { false }
    press(.escape)
    guard wait(upTo: 1.0, for: { !isPopoverOpen }) == false else {
        return (false, "the first Escape closed it outright")
    }
    press(.escape)
    let closed = wait { !isPopoverOpen }
    if !closed { closePopover() }
    return (closed, closed ? "" : "the second Escape left it open")
}

// 6. A letter is typing, not a command: it must neither copy nor close.
check("A letter types instead of acting") {
    let mark = writeSentinel()
    guard openPopover() else { return (false, "popover did not open") }
    press(.z)
    let stillOpen = !wait(upTo: 0.8) { !isPopoverOpen }
    let copied = pasteboard.changeCount != mark
    closePopover()
    if !stillOpen { return (false, "it closed the popover") }
    return (!copied, copied ? "it copied something" : "")
}

// 7. A click on a row moves focus in AppKit; the keys must not care.
check("Keys work after clicking a row") {
    guard openPopover() else { return (false, "popover did not open") }
    if let point = rowPoint() {
        mouse(.mouseMoved, at: point)
        mouse(.leftMouseDown, at: point)
        mouse(.leftMouseUp, at: point)
        _ = wait(upTo: 1.0) { false }
    }
    parkPointer()
    press(.escape)
    var closed = wait(upTo: 1.2) { !isPopoverOpen }
    if !closed {
        // A click opens the clipping, so the first Escape goes back to the list.
        press(.escape)
        closed = wait { !isPopoverOpen }
    }
    if !closed { closePopover() }
    return (closed, closed ? "" : "Escape never closed it")
}

// 8. The hover preview is a second window; it must not take the keyboard with it.
check("Keys work while the hover preview is up") {
    guard openPopover() else { return (false, "popover did not open") }
    if let point = rowPoint() {
        mouse(.mouseMoved, at: point)
        // The preview appears after the pointer rests for a moment.
        _ = wait(upTo: 1.2) { encoreWindows().count > 1 }
    }
    press(.escape)
    defer { parkPointer() }
    let closed = wait { !isPopoverOpen }
    if !closed { closePopover() }
    return (closed, closed ? "" : "Escape left it open")
}

// 9. Command-Down opens a clipping; Escape comes back, and only then closes.
check("Command-Down opens detail, Escape backs out") {
    guard openPopover() else { return (false, "popover did not open") }
    press(.down, flags: .maskCommand)
    _ = wait(upTo: 1.0) { false }
    press(.escape)
    guard wait(upTo: 1.0, for: { !isPopoverOpen }) == false else {
        return (false, "Escape closed the popover instead of going back")
    }
    press(.escape)
    let closed = wait { !isPopoverOpen }
    if !closed { closePopover() }
    return (closed, closed ? "" : "the second Escape left it open")
}

// 10. Option+1 copies the first row outright.
check("Option+1 copies the first row") {
    let mark = writeSentinel()
    return withFreshPopover {
        press(.one, flags: .maskAlternate)
        let copied = waitForCopy(after: mark)
        return (copied, copied ? "" : "pasteboard unchanged")
    }
}

// 11. The tenth open behaves like the first: nothing wedges over a session. This is the
// shape of the original bug — a fresh view every open, racing the focus it depended on.
check("Escape closes on ten consecutive opens") {
    var failures: [Int] = []
    for attempt in 1...10 {
        guard openPopover() else { failures.append(attempt); continue }
        press(.escape)
        if !wait(upTo: 1.2, for: { !isPopoverOpen }) {
            failures.append(attempt)
            closePopover()
        }
    }
    return (failures.isEmpty, failures.isEmpty ? "" : "failed on open \(failures.map(String.init).joined(separator: ", "))")
}

// MARK: - Report

print("")
let width = results.map(\.name.count).max() ?? 40
for result in results {
    let detail = result.detail.isEmpty ? "" : "  (\(result.detail))"
    print("\(result.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(result.passed ? "PASS" : "FAIL")\(detail)")
}
let failed = results.filter { !$0.passed }.count
print("\n\(results.count - failed) passed, \(failed) failed.")
exit(failed == 0 ? 0 : 1)
