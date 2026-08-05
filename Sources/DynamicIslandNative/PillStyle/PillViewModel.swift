import SwiftUI

@MainActor
final class PillViewModel: ObservableObject {
    @Published private(set) var isExpanded: Bool = false

    private var collapseWorkItem: DispatchWorkItem?

    func hoverChanged(_ hovering: Bool) {
        collapseWorkItem?.cancel()

        if hovering {
            setExpanded(true)
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.setExpanded(false)
            }
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isExpanded = expanded
        }
    }
}
