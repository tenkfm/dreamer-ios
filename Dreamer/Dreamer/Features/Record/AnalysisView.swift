import SwiftUI

/// 10 Analysis: breathing sparkle orb and a checklist that fills in step by step.
struct AnalysisView: View {
    var viewModel: AnalysisViewModel
    var onContinue: () -> Void
    var onClose: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var isPaywallPresented = false

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                ZStack {
                    FloatingSparkles()
                    OrbView(glyph: .sparkle, size: .analysis)
                }
                .padding(.top, 70)
                .accessibilityHidden(true)

                Text("Reading your dream")
                    .textStyle(.display)
                    .padding(.top, 40)
                    .accessibilityAddTraits(.isHeader)

                stepsCard
                    .padding(.top, 34)
                    .padding(.horizontal, 40 - DS.Space.screen)

                if showsWrittenText {
                    // The newest lines of the main lens while it is being written.
                    Text(viewModel.writtenText)
                        .textStyle(.secondary, color: DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .truncationMode(.head)
                        .padding(.top, 20)
                        .padding(.horizontal, 40 - DS.Space.screen + 8)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                if viewModel.isSavedOffline {
                    VStack(spacing: 4) {
                        Text("Saved on your iPhone").textStyle(.bodyStrong)
                        Text("You’re offline. We’ll read your dream as soon as you’re back online.")
                            .textStyle(.secondary, color: DS.Palette.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                } else if let state = viewModel.errorState {
                    VStack(spacing: 4) {
                        Text(state.title).textStyle(.bodyStrong)
                        Text(state.message).textStyle(.secondary, color: DS.Palette.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .textStyle(.secondary, color: DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)

                if viewModel.isSavedOffline {
                    PrimaryButton(title: "Back to Home", action: onClose)
                        .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                        .padding(.bottom, 8)
                } else if viewModel.isFinished {
                    PrimaryButton(title: "See my interpretation", action: onContinue)
                        .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .offset(y: 18)))
                } else if viewModel.errorState?.action == .openPaywall {
                    // PREMIUM_REQUIRED: the dream waits in the draft queue and is read as soon as
                    // there is a plan, so leaving loses nothing.
                    Text("Your dream is saved. We’ll read it as soon as you start your plan.")
                        .textStyle(.secondary, color: DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 14)
                    VStack(spacing: 4) {
                        PrimaryButton(title: "See plans", systemImage: "sparkle") { isPaywallPresented = true }
                        TextLinkButton(title: "Back to Home", action: onClose)
                    }
                    .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                    .padding(.bottom, 8)
                } else if viewModel.errorMessage != nil {
                    // Every failure has a way out: without one the screen was a dead end.
                    VStack(spacing: 4) {
                        if viewModel.canRetry {
                            PrimaryButton(title: "Try again") { Task { await viewModel.run() } }
                            TextLinkButton(title: "Back to Home", action: onClose)
                        } else {
                            PrimaryButton(title: "Back to Home", action: onClose)
                        }
                    }
                    .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, DS.Space.screen)
        }
        .animation(.soft(0.6), value: viewModel.isFinished)
        .animation(.soft(0.6), value: showsWrittenText)
        .task { await viewModel.run() }
        .fullScreenCover(isPresented: $isPaywallPresented) {
            PaywallSheet(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState,
                                                     placement: .analysis, analytics: dependencies.analytics) {
                isPaywallPresented = false
            })
        }
        .onChange(of: appState.subscription) { _, subscription in
            if subscription != .none, viewModel.errorState?.action == .openPaywall {
                Task { await viewModel.run() }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.isFinished) { _, finished in finished }
    }

    private var showsWrittenText: Bool {
        !viewModel.writtenText.isEmpty && viewModel.errorMessage == nil && !viewModel.isSavedOffline
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(viewModel.steps, id: \.self) { step in
                let status = viewModel.status(of: step)
                HStack(spacing: 14) {
                    StepIndicator(status: status)
                    Text(step.title)
                        .font(DreamerFont.ui(15, relativeTo: .body))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .opacity(status == .pending ? 0.5 : 1)
                        .animation(.soft(0.5), value: status)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(status.accessibilityValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .glassCard(radius: DS.Radius.cardLarge)
    }
}

private extension AnalysisViewModel.StepStatus {
    var accessibilityValue: String {
        switch self {
        case .done: "Done"
        case .active: "In progress"
        case .pending: "Waiting"
        }
    }
}

/// Done = white circle with a popping check, active = spinning ring, pending = dashed ring.
private struct StepIndicator: View {
    var status: AnalysisViewModel.StepStatus

    var body: some View {
        ZStack {
            switch status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.icon)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.Palette.surface))
                    .shadow(color: DS.Palette.shadow.opacity(0.18), radius: 5, x: 0, y: 3)
                    .transition(.scale(scale: 0.4).combined(with: .opacity).animation(.pop))
            case .active:
                LoopingView { time in
                    ZStack {
                        Circle().stroke(DS.Palette.track, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: 0.28)
                            .stroke(DS.Palette.icon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(360 * Loop.linear(time, period: 1)))
                    }
                }
                .frame(width: 24, height: 24)
            case .pending:
                Circle()
                    .stroke(DS.Palette.line.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 24, height: 24)
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// Small white sparkles twinkling around the orb.
private struct FloatingSparkles: View {
    private let positions: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (-118, -38, 12), (112, -66, 9), (142, 44, 9), (-130, 66, 7), (96, 124, 12), (-78, 146, 9)
    ]

    var body: some View {
        ZStack {
            ForEach(positions.indices, id: \.self) { index in
                let position = positions[index]
                TwinklingSparkle(size: position.size, color: DS.Palette.white)
                    .offset(x: position.x, y: position.y)
            }
        }
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        AnalysisView(viewModel: AnalysisViewModel(draft: DreamDraft(transcript: MockData.transcript),
                                                  service: MockDreamAnalysisService(), store: InMemoryDreamStore()),
                     onContinue: {})
    }
}
