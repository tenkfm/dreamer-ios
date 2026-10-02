import SwiftUI

/// 09 Details: bottom sheet over the dimmed sky, transcript preview at the top.
struct DetailsView: View {
    @Bindable var viewModel: DetailsViewModel
    var onInterpret: () -> Void
    var onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheetShown = false

    var body: some View {
        VStack(spacing: 0) {
            // 90 pt in the design; gives way on small screens (iPhone SE) before the sheet does.
            Spacer(minLength: 40)
                .frame(maxHeight: 90)
            Text(viewModel.transcript)
                .textStyle(.lead, color: DS.Palette.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .skyTextShadow()
                .padding(.horizontal, DS.Space.text - 4)
            Spacer(minLength: 24)
            BottomSheetContainer {
                ViewThatFits(in: .vertical) {
                    sheetContent
                    ScrollView { sheetContent }.scrollIndicators(.hidden)
                }
            }
            // Measured first, so it falls back to scrolling when the screen is too short.
            .layoutPriority(1)
            .offset(y: sheetShown || reduceMotion ? 0 : 700)
        }
        .onAppear {
            withAnimation(.soft(0.7)) { sheetShown = true }
        }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A few details")
                    .font(DreamerFont.ui(24, .medium, relativeTo: .title2))
                    .tracking(-0.2)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("They make your interpretation more personal.")
                    .textStyle(.secondary, color: DS.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How did it feel?").textStyle(.bodyStrong)
                FlowLayout(spacing: 8, lineSpacing: 2) {
                    ForEach(Emotion.allCases) { emotion in
                        Chip(title: emotion.title, isOn: viewModel.isSelected(emotion), onColor: emotion.color) {
                            viewModel.toggle(emotion)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Have you had this dream before?").textStyle(.bodyStrong)
                DreamerSegmented(options: Recurrence.allCases, selection: $viewModel.recurrence) { $0.title }
            }

            Toggle(isOn: $viewModel.someoneSpecific) {
                HStack(spacing: 14) {
                    Image(systemName: "person")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(DS.Palette.icon)
                    Text("Someone specific was in it").textStyle(.body)
                }
            }
            .toggleStyle(.dreamer)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .glassCard(radius: DS.Radius.option, style: .selected)

            VStack(spacing: 4) {
                PrimaryButton(title: "Interpret my dream", systemImage: "sparkle", action: onInterpret)
                TextLinkButton(title: "Skip", action: onSkip)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.bottom, 8)
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full).blur(radius: 6)
        DetailsView(viewModel: DetailsViewModel(transcript: MockData.transcript), onInterpret: {}, onSkip: {})
    }
}
