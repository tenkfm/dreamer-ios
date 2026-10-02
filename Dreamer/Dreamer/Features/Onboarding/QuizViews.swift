import SwiftUI

// MARK: - Shared layout

/// Quiz question content: centered title and the options. Back, the progress and "Continue" belong
/// to the flow (OnboardingPagesView), so only this changes between the questions.
private struct QuizContentLayout<Options: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var options: () -> Options

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(title)
                    .textStyle(.display)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.text)
                    .padding(.top, 56)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: DS.Space.stack) {
                    options()
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

// MARK: - 04 Goal

struct QuizGoalContent: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        QuizContentLayout(title: "What brings you to Dreamer?") {
            ForEach(Array(Goal.allCases.enumerated()), id: \.element) { index, goal in
                RadioOptionCard(title: goal.title, glyph: goal.glyph, isSelected: viewModel.goal == goal) {
                    viewModel.goal = goal
                }
            }
        }
    }
}

// MARK: - 05 Lens

struct QuizLensContent: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        QuizContentLayout(title: "Which lens feels closer to you?") {
            ForEach(Array(Lens.allCases.enumerated()), id: \.element) { index, lens in
                RadioOptionCard(title: lens.title, subtitle: lens.summary, isSelected: viewModel.lens == lens) {
                    viewModel.lens = lens
                }
            }
        }
    }
}

#Preview("Quiz goal") {
    ZStack {
        SkyBackground(kind: .top)
        QuizGoalContent(viewModel: OnboardingViewModel(appState: .preview(onboardingCompleted: false), step: .quizGoal))
    }
}
