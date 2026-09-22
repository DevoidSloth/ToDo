import Combine
import SwiftUI

/// Where a keyboard shortcut wants to put the cursor.
enum FocusTarget: Equatable {
    case bucket(Bucket)
    case longTerm
}

/// Carries "put the cursor in that field" from a menu command down to the view
/// that owns the field. Set it, the field claims focus, clears it.
final class FocusCoordinator: ObservableObject {
    @Published var target: FocusTarget?
}
