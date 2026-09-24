import SwiftUI

// MARK: - Shared scaffold

/// Quiz frame: back button + progress, centered title, options, pinned "Continue".
private struct QuizScaffold<Options: View>: View {
    var title: String
    var progress: Double
    var previousProgress: Double
    var stepLabel: String
    var onBack: () -> Void
    var onContinue: () -> Void
    @ViewBuilder var options: () -> Options

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(title)
                    .textStyle(.display)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.text)
                    .padding(.top, 76)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .enterUp(0.3)
                VStack(spacing: DS.Space.stack) {
                    options()
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) {
            HeaderBar(leading: {
                GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back", action: onBack)
            }, center: {
                HStack(spacing: 12) {
                    ProgressCapsule(value: progress, initialValue: previousProgress)
                    Text(stepLabel)
                        .font(DreamerFont.fixed(12))
                        .foregroundStyle(DS.Palette.white)
                        .skyTextShadow()
                }
                .padding(.leading, DS.Size.iconButton + 16)
                .padding(.trailing, DS.Size.iconButton + 8)
            })
            .enterUp(0.1)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: "Continue", action: onContinue)
                .padding(.horizontal, DS.Space.cta)
                .padding(.bottom, 8)
                .enterUp(0.9)
        }
    }
}

// MARK: - 04 Goal

struct QuizGoalView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        QuizScaffold(
            title: "What brings you to Dreamer?",
            progress: 0.5,
            previousProgress: 0,
            stepLabel: "1 of 2",
            onBack: { viewModel.back() },
            onContinue: { viewModel.next() }
        ) {
            ForEach(Array(Goal.allCases.enumerated()), id: \.element) { index, goal in
                RadioOptionCard(title: goal.title, glyph: goal.glyph, isSelected: viewModel.goal == goal) {
                    viewModel.goal = goal
                }
                .enterUp(0.45 + Double(index) * 0.15)
            }
        }
    }
}

// MARK: - 05 Lens

struct QuizLensView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        QuizScaffold(
            title: "Which lens feels closer to you?",
            progress: 1,
            previousProgress: 0.5,
            stepLabel: "2 of 2",
            onBack: { viewModel.back() },
            onContinue: { viewModel.next() }
        ) {
            ForEach(Array(Lens.allCases.enumerated()), id: \.element) { index, lens in
                RadioOptionCard(title: lens.title, subtitle: lens.summary, isSelected: viewModel.lens == lens) {
                    viewModel.lens = lens
                }
                .enterUp(0.45 + Double(index) * 0.15)
            }
        }
    }
}

#Preview("Quiz goal") {
    ZStack {
        SkyBackground(kind: .top)
        QuizGoalView(viewModel: OnboardingViewModel(appState: .preview(onboardingCompleted: false), step: .quizGoal))
    }
}
