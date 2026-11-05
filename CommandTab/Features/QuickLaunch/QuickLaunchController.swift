import AppKit
import CoreGraphics

enum QuickLaunchShortcutPolicy {
    private static let slotsByKeyCode: [UInt16: Int] = [
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
        22: 6,
        26: 7,
        28: 8,
        25: 9
    ]

    static func slot(forKeyCode keyCode: UInt16, flags: CGEventFlags, switcherActive: Bool) -> Int? {
        let meaningfulModifiers: CGEventFlags = [
            .maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn
        ]
        let normalized = flags.intersection(meaningfulModifiers)
        guard normalized == [.maskCommand], !switcherActive else { return nil }
        return slotsByKeyCode[keyCode]
    }
}

protocol QuickLaunchApplicationServing: AnyObject {
    func resolve(_ assignment: QuickLaunchAssignment) -> URL?
    func launchOrActivate(_ url: URL, assignment: QuickLaunchAssignment)
}

final class QuickLaunchController {
    private let settings: QuickLaunchAssignmentProviding
    private let applicationService: QuickLaunchApplicationServing
    private let failureFeedback: () -> Void

    init(
        settings: QuickLaunchAssignmentProviding,
        applicationService: QuickLaunchApplicationServing = QuickLaunchApplicationService(),
        failureFeedback: @escaping () -> Void = { DispatchQueue.main.async { NSSound.beep() } }
    ) {
        self.settings = settings
        self.applicationService = applicationService
        self.failureFeedback = failureFeedback
    }

    func handle(slot: Int, isRepeat: Bool) -> Bool {
        guard let assignment = settings.assignment(for: slot) else {
            guard settings.hasAssignment(for: slot) else { return false }
            if !isRepeat { reportUnresolvableAssignment(slot: slot) }
            return true
        }
        // An assigned slot owns the entire key press, including autorepeat.
        if isRepeat { return true }
        guard let resolvedURL = applicationService.resolve(assignment) else {
            reportUnresolvableAssignment(slot: slot)
            return true
        }
        applicationService.launchOrActivate(resolvedURL, assignment: assignment)
        return true
    }

    private func reportUnresolvableAssignment(slot: Int) {
        Log.input.error("Quick Launch slot \(slot) assignment could not be resolved")
        failureFeedback()
    }
}
