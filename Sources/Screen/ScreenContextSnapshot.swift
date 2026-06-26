import CoreGraphics
import Foundation

struct ScreenContextSnapshot: @unchecked Sendable {
    let text: String
    let image: CGImage?

    static let empty = ScreenContextSnapshot(text: "", image: nil)
}
