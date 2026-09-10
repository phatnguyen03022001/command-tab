import Foundation
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

    init(
        settings: QuickLaunchAssignmentProviding,
        applicationService: QuickLaunchApplicationServing = QuickLaunchApplicationService()
    ) {
        self.settings = settings
        self.applicationService = applicationService
    }

    func handle(slot: Int, isRepeat: Bool) -> Bool {
        guard let assignment = settings.assignment(for: slot) else { return false }
        guard let resolvedURL = applicationService.resolve(assignment) else {
            Log.input.error("Quick Launch slot \(slot) assignment could not be resolved")
            return false
        }
        if isRepeat {
            return true
        }
        applicationService.launchOrActivate(resolvedURL, assignment: assignment)
        return true
    }
}
