import FoundationModels
import Foundation

// MARK: Arguments
//
// The `@Generable`/`@Guide` macros need a compiler plugin that only ships inside
// Xcode.app, and Halo is built with the Command Line Tools alone — so these
// conform to `Generable` by hand instead of with the macro. `GenerationSchema`
// and `GeneratedContent` both have plain, documented initialisers for exactly
// this: nothing here is unsupported or fragile, just spelled out.

/// For tools that take no argument.
struct HaloEmptyArgs: Generable {
    init() {}
    init(_ content: GeneratedContent) throws {}
    var generatedContent: GeneratedContent { GeneratedContent(properties: [:]) }
    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, description: "No arguments", properties: [])
    }
}

/// For tools that take a single number (minutes, for the timer).
struct HaloMinutesArgs: Generable {
    var minutes: Int
    init(minutes: Int) { self.minutes = minutes }
    init(_ content: GeneratedContent) throws {
        minutes = try content.value(Int.self, forProperty: "minutes")
    }
    var generatedContent: GeneratedContent { GeneratedContent(properties: ["minutes": minutes]) }
    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, properties: [
            GenerationSchema.Property(name: "minutes", description: "How many minutes", type: Int.self),
        ])
    }
}

/// For tools that take a single line of text (a reminder's title, a note).
struct HaloTextArgs: Generable {
    var text: String
    init(text: String) { self.text = text }
    init(_ content: GeneratedContent) throws {
        text = try content.value(String.self, forProperty: "text")
    }
    var generatedContent: GeneratedContent { GeneratedContent(properties: ["text": text]) }
    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, properties: [
            GenerationSchema.Property(name: "text", description: "The text", type: String.self),
        ])
    }
}

// MARK: Toolbox
//
// One place that holds the model reference and records what just happened, so
// the island can show a small confirmation ("Timer set for 10 min") alongside
// whatever the model says. Tools are lightweight value types that just forward
// into here — all on the main actor, the same as a button click would.

@MainActor
final class HaloToolbox {
    unowned let model: IslandModel
    private(set) var lastAction: (label: String, symbol: String)?

    init(model: IslandModel) {
        self.model = model
    }

    func record(_ label: String, symbol: String) {
        lastAction = (label, symbol)
    }

    /// Every tool Halo Intelligence can use. Destructive actions (clearing caches,
    /// force quitting, emptying the Trash) only ever open Halo's existing confirmation
    /// dialog — the model can surface it, but a human still has to click.
    var tools: [any Tool] {
        [
            HaloWeatherTool(box: self), HaloBatteryTool(box: self), HaloSystemInfoTool(box: self),
            HaloFocusStatusTool(box: self), HaloSystemStatusTool(box: self),
            HaloClipboardTool(box: self), HaloRemindersTool(box: self),
            HaloNextEventTool(box: self), HaloDateTimeTool(box: self),
            HaloStartTimerTool(box: self), HaloStartStopwatchTool(box: self), HaloStartPomodoroTool(box: self),
            HaloStopTimerTool(box: self),
            HaloToggleFocusTool(box: self), HaloToggleDarkModeTool(box: self), HaloToggleNightShiftTool(box: self),
            HaloToggleKeepAwakeTool(box: self), HaloToggleMuteTool(box: self),
            HaloAddReminderTool(box: self), HaloWriteNoteTool(box: self),
            HaloLockScreenTool(box: self), HaloSleepDisplayTool(box: self),
            HaloClearCachesTool(box: self), HaloForceQuitTool(box: self), HaloEmptyTrashTool(box: self),
        ]
    }

    static let instructions = """
    You are Halo Intelligence, built into a Dynamic Island for the Mac notch called Halo. \
    You run entirely on this Mac; nothing you're asked or told leaves the device. \
    Answer in at most two short sentences — you're read in a small strip below the notch, not a chat window. \
    Use a tool whenever the request needs one; don't guess at facts a tool can look up (weather, battery, \
    the time, what's copied, reminders, the next event). \
    To find out whether Dark Mode, Night Shift, Keep Awake or sound is on, call getSystemStatus — never call \
    a toggle tool just to check something, since calling it changes it. Only call a toggle tool when the \
    user actually asks to turn something on, off, or to toggle, mute or switch it. \
    For clearing caches, force quitting apps or \
    emptying the Trash: calling the tool only opens Halo's own confirmation dialog, it does not finish the \
    action by itself, so say that a confirmation is on screen rather than saying it's done. \
    Never claim to have done something a tool didn't report back as done.
    """
}

// MARK: Read-only tools

struct HaloWeatherTool: Tool {
    let box: HaloToolbox
    let name = "getWeather"
    let description = "The current weather and today's forecast for where the user is."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            guard let conditions = box.model.weather.conditions else {
                return "Weather isn't switched on, or hasn't loaded yet."
            }
            let temp = WeatherFormat.degrees(conditions.temperature)
            let feels = WeatherFormat.degrees(conditions.feelsLike)
            let high = WeatherFormat.degrees(conditions.high)
            let low = WeatherFormat.degrees(conditions.low)
            return "\(WeatherLook.describe(conditions.code)), \(temp) (feels like \(feels)) in \(conditions.place). " +
                "High \(high), low \(low)."
        }
    }
}

struct HaloBatteryTool: Tool {
    let box: HaloToolbox
    let name = "getBattery"
    let description = "The Mac's battery percentage, whether it's charging, and time remaining."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            guard let snapshot = box.model.batterySnapshot() else { return "Battery information isn't available." }
            var text = "\(snapshot.percent)% battery"
            if snapshot.isCharging { text += ", charging" }
            else if snapshot.onAC { text += ", plugged in" }
            if let minutes = snapshot.minutesRemaining {
                let hours = minutes / 60
                let mins = minutes % 60
                let time = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
                text += snapshot.isCharging ? ", \(time) until full" : ", \(time) left"
            }
            return text
        }
    }
}

struct HaloSystemInfoTool: Tool {
    let box: HaloToolbox
    let name = "getSystemInfo"
    let description = "CPU load, memory used, free storage and uptime for this Mac right now."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            box.model.stats.startWatching()
            defer { box.model.stats.stopWatching() }
            let snapshot = box.model.stats.snapshot
            let memory = "\(SystemStats.gigabytes(snapshot.memoryUsed)) of \(SystemStats.gigabytes(snapshot.memoryTotal)) memory used"
            let disk = "\(SystemStats.bytes(snapshot.diskFree)) free"
            let uptime = SystemStats.uptime(snapshot.uptime)
            var text = "\(memory), \(disk), up \(uptime)."
            if let health = snapshot.batteryHealth { text += " Battery health \(health)%." }
            return text
        }
    }
}

struct HaloFocusStatusTool: Tool {
    let box: HaloToolbox
    let name = "getFocusStatus"
    let description = "Whether a Focus (like Do Not Disturb) is currently on."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            guard box.model.focus.isOn, let active = box.model.focus.activeFocus else { return "No Focus is on right now." }
            return "\(active) is on."
        }
    }
}

struct HaloSystemStatusTool: Tool {
    let box: HaloToolbox
    let name = "getSystemStatus"
    let description = "Whether Dark Mode, Night Shift, Keep Awake and sound are currently on — read-only, " +
        "changes nothing. Always use this to check a status instead of a toggle tool."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            // A fresh, side-effect-free read of each setting (no Bluetooth — reading that
            // needs its own permission prompt, so it's left to the Bluetooth toggle itself).
            box.model.toggles.refresh()
            var parts = [
                "Dark Mode is \(box.model.toggles.darkMode ? "on" : "off")",
                "Night Shift is \(box.model.toggles.nightShift ? "on" : "off")",
                "Keep Awake is \(box.model.toggles.keepAwake ? "on" : "off")",
                "sound is \(box.model.volumeMuted ? "muted" : "on")",
            ]
            if box.model.toggles.canUseNightShift == false { parts[1] = "Night Shift isn't available on this Mac" }
            return parts.joined(separator: ", ") + "."
        }
    }
}

struct HaloClipboardTool: Tool {
    let box: HaloToolbox
    let name = "getClipboard"
    let description = "The most recent things copied to the clipboard, newest first."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            let items = box.model.clipboard.items.prefix(5)
            guard !items.isEmpty else { return "The clipboard is empty." }
            return items.enumerated().map { index, item in
                let text = item.title.count > 120 ? String(item.title.prefix(120)) + "…" : item.title
                return "\(index + 1). \(text)"
            }.joined(separator: "\n")
        }
    }
}

struct HaloRemindersTool: Tool {
    let box: HaloToolbox
    let name = "getReminders"
    let description = "The user's unfinished reminders, soonest due first."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            switch box.model.reminders.access {
            case .denied: return "Reminders access is off for Halo, so I can't see them."
            case .unknown: return "Halo hasn't been given Reminders access yet — open the Reminders page in Halo to allow it."
            case .granted: break
            }
            let items = box.model.reminders.items.prefix(6)
            guard !items.isEmpty else { return "There are no open reminders." }
            return items.map { item in
                guard let due = item.due else { return item.title }
                return "\(item.title) (due \(RemindersMonitor.due(due)))"
            }.joined(separator: "\n")
        }
    }
}

struct HaloNextEventTool: Tool {
    let box: HaloToolbox
    let name = "getNextEvent"
    let description = "The next event on the user's calendar, if calendar events are switched on."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            guard let event = box.model.calendar.next else { return "There's nothing coming up, or calendar events are off." }
            var text = "\(event.title), \(CalendarFormat.range(event))"
            if let location = event.location, !location.isEmpty { text += " at \(location)" }
            if event.joinURL != nil { text += " (has a video call link)" }
            return text
        }
    }
}

struct HaloDateTimeTool: Tool {
    let box: HaloToolbox
    let name = "getDateTime"
    let description = "The current date and time. Use this rather than guessing."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
    }
}

// MARK: Timer

struct HaloStartTimerTool: Tool {
    let box: HaloToolbox
    let name = "startTimer"
    let description = "Starts a countdown timer for a number of minutes."

    func call(arguments: HaloMinutesArgs) async throws -> String {
        await MainActor.run {
            let minutes = max(1, min(180, arguments.minutes))
            box.model.timer.startCountdown(minutes: Double(minutes))
            box.record("Timer set for \(minutes) min", symbol: "timer")
        }
        return "Timer started for \(max(1, min(180, arguments.minutes))) minutes."
    }
}

struct HaloStartStopwatchTool: Tool {
    let box: HaloToolbox
    let name = "startStopwatch"
    let description = "Starts the stopwatch, counting up from zero."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            box.model.timer.startStopwatch()
            box.record("Stopwatch started", symbol: "stopwatch")
        }
        return "Stopwatch started."
    }
}

struct HaloStartPomodoroTool: Tool {
    let box: HaloToolbox
    let name = "startPomodoro"
    let description = "Starts a Pomodoro focus cycle: 25 minutes of focus, then a break."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            box.model.timer.startPomodoro()
            box.record("Pomodoro started", symbol: "brain.head.profile")
        }
        return "Pomodoro started — 25 minutes of focus, then a break."
    }
}

struct HaloStopTimerTool: Tool {
    let box: HaloToolbox
    let name = "stopTimer"
    let description = "Stops the running timer, stopwatch or Pomodoro."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        let wasActive = await MainActor.run { () -> Bool in
            let active = box.model.timer.isActive
            box.model.timer.stop()
            if active { box.record("Timer stopped", symbol: "timer") }
            return active
        }
        return wasActive ? "Timer stopped." : "Nothing was running."
    }
}

// MARK: Toggles

struct HaloToggleFocusTool: Tool {
    let box: HaloToolbox
    let name = "toggleFocus"
    let description = "Turns the user's Focus (Do Not Disturb) on if it's off, or off if it's on."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                box.model.focus.toggle { text, worked in
                    if worked { box.record(text, symbol: "moon.fill") }
                    continuation.resume(returning: text)
                }
            }
        }
    }
}

struct HaloToggleDarkModeTool: Tool {
    let box: HaloToolbox
    let name = "toggleDarkMode"
    let description = "Switches the Mac between Dark Mode and Light Mode."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                box.model.toggles.toggleDarkMode { worked in
                    if worked {
                        let on = box.model.toggles.darkMode
                        box.record(on ? "Dark Mode on" : "Dark Mode off", symbol: "circle.lefthalf.filled")
                        continuation.resume(returning: on ? "Dark Mode is now on." : "Dark Mode is now off.")
                    } else {
                        continuation.resume(returning: "Halo needs permission to control System Events for this — " +
                                            "allow it the next time macOS asks.")
                    }
                }
            }
        }
    }
}

struct HaloToggleNightShiftTool: Tool {
    let box: HaloToolbox
    let name = "toggleNightShift"
    let description = "Turns Night Shift (the warmer display colour) on or off."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            guard box.model.toggles.canUseNightShift else { return "Night Shift isn't available on this Mac." }
            box.model.toggles.toggleNightShift()
            let on = box.model.toggles.nightShift
            box.record(on ? "Night Shift on" : "Night Shift off", symbol: "sun.horizon.fill")
            return on ? "Night Shift is now on." : "Night Shift is now off."
        }
    }
}

struct HaloToggleKeepAwakeTool: Tool {
    let box: HaloToolbox
    let name = "toggleKeepAwake"
    let description = "Stops the Mac and its display from sleeping, or turns that back off."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            box.model.toggles.toggleKeepAwake()
            let on = box.model.toggles.keepAwake
            box.record(on ? "Keep Awake on" : "Keep Awake off", symbol: "cup.and.saucer.fill")
            return on ? "This Mac will stay awake until you turn that off." : "Keep Awake is now off."
        }
    }
}

struct HaloToggleMuteTool: Tool {
    let box: HaloToolbox
    let name = "toggleMute"
    let description = "Mutes or unmutes the Mac's sound."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            box.model.toggleMute()
            let muted = box.model.volumeMuted
            box.record(muted ? "Muted" : "Unmuted", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            return muted ? "Sound is muted." : "Sound is back on."
        }
    }
}

// MARK: Notes and reminders

struct HaloAddReminderTool: Tool {
    let box: HaloToolbox
    let name = "addReminder"
    let description = "Adds a new reminder with the given title to the user's default reminder list."

    func call(arguments: HaloTextArgs) async throws -> String {
        await MainActor.run {
            guard box.model.reminders.access == .granted else {
                return "Halo doesn't have Reminders access yet — open the Reminders page in Halo and allow it, then ask again."
            }
            guard box.model.reminders.add(arguments.text) else { return "That reminder couldn't be added." }
            box.record("Added “\(arguments.text)”", symbol: "checklist")
            return "Added the reminder: \(arguments.text)."
        }
    }
}

struct HaloWriteNoteTool: Tool {
    let box: HaloToolbox
    let name = "writeNote"
    let description = "Adds a line to Halo's Quick Note (it doesn't erase what's already there)."

    func call(arguments: HaloTextArgs) async throws -> String {
        await MainActor.run {
            let defaults = UserDefaults.standard
            let existing = defaults.string(forKey: QuickNote.key) ?? ""
            let updated = existing.isEmpty ? arguments.text : existing + "\n" + arguments.text
            defaults.set(updated, forKey: QuickNote.key)
            box.record("Added to Quick Note", symbol: "note.text")
            return "Added to your Quick Note."
        }
    }
}

// MARK: Screen and power

struct HaloLockScreenTool: Tool {
    let box: HaloToolbox
    let name = "lockScreen"
    let description = "Locks the screen immediately."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run { QuickAction.lockScreen() }
        return "Locking the screen."
    }
}

struct HaloSleepDisplayTool: Tool {
    let box: HaloToolbox
    let name = "sleepDisplay"
    let description = "Puts the display to sleep, without sleeping the whole Mac."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run { QuickAction.sleepDisplay() }
        return "Putting the display to sleep."
    }
}

// MARK: Destructive — these only ever open Halo's own confirmation dialog.
// A human has to click Clear / Force Quit / Empty Trash for anything to happen.

struct HaloClearCachesTool: Tool {
    let box: HaloToolbox
    let name = "clearCaches"
    let description = "Opens Halo's confirmation for clearing app caches to free up storage. Does not clear anything by itself."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            DispatchQueue.main.async { box.model.clearCaches() }
            box.record("Confirmation opened", symbol: "sparkles")
        }
        return "I've opened the confirmation for clearing caches — take a look and confirm or cancel."
    }
}

struct HaloForceQuitTool: Tool {
    let box: HaloToolbox
    let name = "forceQuitApps"
    let description = "Opens Halo's confirmation for force quitting every open app. Does not quit anything by itself."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            DispatchQueue.main.async { box.model.forceQuitAllApps() }
            box.record("Confirmation opened", symbol: "xmark")
        }
        return "I've opened the confirmation for force quitting apps — unsaved work would be lost, so take a look first."
    }
}

struct HaloEmptyTrashTool: Tool {
    let box: HaloToolbox
    let name = "emptyTrash"
    let description = "Opens the confirmation for emptying the Trash for good. Does not empty it by itself."

    func call(arguments: HaloEmptyArgs) async throws -> String {
        await MainActor.run {
            DispatchQueue.main.async { box.model.emptyTrash() }
            box.record("Confirmation opened", symbol: "trash")
        }
        return "I've opened the confirmation for emptying the Trash — that can't be undone, so take a look first."
    }
}

// MARK: Controller

/// Drives a single Halo Intelligence exchange: one question, an on-device answer,
/// and whatever it did along the way. A fresh session each time — this is a quick
/// command, like asking Siri, not an ongoing conversation.
@MainActor
final class HaloIntelligenceController: ObservableObject {
    enum Phase: Equatable {
        case idle, thinking, answered, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var question = ""
    @Published private(set) var answerText = ""
    @Published private(set) var actionLabel: String?
    @Published private(set) var actionSymbol: String?

    weak var model: IslandModel?
    /// Called every time the streamed answer updates, so the island can stay open.
    var onUpdate: (() -> Void)?

    private var task: Task<Void, Never>?

    static var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }
    static var isAvailable: Bool { availability == .available }

    static var unavailableReason: String {
        switch availability {
        case .available: return ""
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible: return "This Mac can't run Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."
            case .modelNotReady: return "Apple Intelligence is still getting ready — try again shortly."
            @unknown default: return "Halo Intelligence isn't available right now."
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        question = ""
        answerText = ""
        actionLabel = nil
        actionSymbol = nil
    }

    func ask(_ text: String) {
        guard let model else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard Self.isAvailable else {
            question = trimmed
            phase = .failed
            answerText = Self.unavailableReason
            return
        }

        task?.cancel()
        question = trimmed
        answerText = ""
        actionLabel = nil
        actionSymbol = nil
        phase = .thinking
        // Tool calls (checking the weather, the battery…) round-trip before any text
        // streams in, so the card needs a generous hold from the very first moment —
        // not just once tokens start arriving.
        model.keepIntelligenceOpen(delay: 20)

        task = Task { [weak self] in
            let toolbox = HaloToolbox(model: model)
            let session = LanguageModelSession(tools: toolbox.tools, instructions: HaloToolbox.instructions)
            do {
                let stream = session.streamResponse(to: trimmed)
                for try await snapshot in stream {
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard let self else { return }
                        self.answerText = snapshot.content
                        self.phase = .answered
                        if let action = toolbox.lastAction {
                            self.actionLabel = action.label
                            self.actionSymbol = action.symbol
                        }
                        self.onUpdate?()
                    }
                }
            } catch is CancellationError {
                // A new question came in, or the island closed; nothing to show.
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.phase = .failed
                    self.answerText = Self.message(for: error)
                    self.onUpdate?()
                }
            }
        }
    }

    private static func message(for error: Error) -> String {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return "I couldn't work that out."
        }
        switch generationError {
        case .guardrailViolation: return "I can't help with that one."
        case .exceededContextWindowSize: return "That's too much for me to take in at once."
        case .rateLimited, .concurrentRequests: return "Give it a moment and try again."
        case .unsupportedLanguageOrLocale: return "I don't understand that language yet."
        default: return "I couldn't work that out."
        }
    }
}
