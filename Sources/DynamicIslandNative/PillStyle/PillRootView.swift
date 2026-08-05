import SwiftUI

/// Ported from `notch-limits`' `NotchRootView` — the pill/card shell shape
/// plus the collapsed-to-expanded layout, unchanged from the original.
struct PillRootView: View {
    @ObservedObject var viewModel: PillViewModel
    @ObservedObject var usage: UsageService
    let layout: PillNotchLayout
    let onOpenSettings: () -> Void

    private var currentWidth: CGFloat {
        viewModel.isExpanded ? layout.expandedSize.width : layout.collapsedSize.width
    }

    private var currentHeight: CGFloat {
        viewModel.isExpanded ? layout.expandedSize.height : layout.collapsedSize.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            shell

            VStack(spacing: 0) {
                PillIndicatorView(
                    viewModel: viewModel,
                    snapshots: PillUsageAdapter.snapshots(from: usage),
                    layout: layout,
                    onOpenSettings: onOpenSettings
                )
                .frame(width: currentWidth, height: viewModel.isExpanded ? 44 : layout.collapsedSize.height)

                if viewModel.isExpanded {
                    PillExpandedContent(usage: usage, onOpenSettings: onOpenSettings)
                        .frame(
                            width: layout.expandedSize.width,
                            height: layout.expandedSize.height - 44,
                            alignment: .top
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var shell: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: viewModel.isExpanded ? PillTheme.cardCornerRadius : PillTheme.pillCornerRadius,
                bottomTrailing: viewModel.isExpanded ? PillTheme.cardCornerRadius : PillTheme.pillCornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
        .fill(PillTheme.panelBackground)
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: viewModel.isExpanded ? PillTheme.cardCornerRadius : PillTheme.pillCornerRadius,
                    bottomTrailing: viewModel.isExpanded ? PillTheme.cardCornerRadius : PillTheme.pillCornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .stroke(Color.white.opacity(viewModel.isExpanded ? 0.1 : 0), lineWidth: 0.5)
        }
        .frame(width: currentWidth, height: currentHeight)
        .shadow(color: .black.opacity(viewModel.isExpanded ? 0.5 : 0), radius: 18, y: 8)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.isExpanded)
    }
}
