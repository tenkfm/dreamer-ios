# 04 - Navigation, state, data

## Flow

```
First launch:
Welcome -> Onboarding-Record -> Onboarding-Understand -> Quiz-Goal -> Quiz-Lens -> Paywall -> Main
   |            |  Skip ------------------^                                             |
   +-- "I already have an account" (any onboarding screen) ------------------------> Main

Main = TabView-like custom container with floating TabBar:
  Today (Home) | Journal | Library

Home:
  settings button -> Settings (push)
  mic orb        -> Record (fullScreenCover) -> Details -> Analysis -> Interpretation
                    (on finish the cover dismisses and Interpretation is pushed on Home's stack,
                     so Back from Interpretation returns to Home)
  "See the pattern" -> Journal tab
  "See all" / thumbs -> Library tab
Journal row -> Interpretation (push)
Library tile -> Symbol detail (push)
```

Next launches: if `AppState.onboardingCompleted` -> Main, else Welcome.
Hard paywall: if onboarding is complete but `subscription == .none`, show Paywall before Main
(phase 1: flag in a debug menu to bypass).

## Routes

```swift
enum OnboardingStep: Hashable { case welcome, record, understand, quizGoal, quizLens, paywall }
enum Tab: Hashable { case today, journal, library }
enum Route: Hashable {
    case settings
    case interpretation(Dream.ID)
    case symbol(Symbol.ID)
}
```

- Onboarding: a single `OnboardingFlowView` with a `step` state and horizontal transitions
  (the sky stays still, content crossfades and slides - see doc 05), not a NavigationStack.
- Main: custom container keeps one `NavigationStack(path:)` per tab so each tab keeps its stack.
  The custom TabBar hides on pushed screens (Settings, Interpretation, Symbol).
- Record flow: `fullScreenCover` hosting `RecordFlowView` with its own step state
  (record -> details -> analysis). On completion: dismiss, then append `.interpretation(id)` to the Today path.

## App state

```swift
@Observable final class AppState {
    var onboardingCompleted: Bool          // persisted (AppStorage/UserDefaults)
    var userName: String = "Anna"          // mock
    var goal: Goal?                        // Quiz 1
    var preferredLens: Lens = .psychology  // Quiz 2, Settings -> Default lens
    var subscription: SubscriptionStatus = .none
    var selectedTab: Tab = .today
    var paths: [Tab: NavigationPath]
}
```

## Models

```swift
enum Lens: String, CaseIterable, Codable { case psychology, spiritual, dreamBook }   // titles: Psychology, Spiritual, Dream book
enum Emotion: String, CaseIterable, Codable { case fear, joy, anxiety, calm, confusion }
enum Recurrence: Int, Codable { case never, sometimes, often }
enum Goal: String, Codable { case understand, recurring, someone, remember }

struct DreamSymbol: Identifiable, Codable { let id: UUID; var title: String; var meaning: String; var systemImage: String }

struct Interpretation: Codable {
    var texts: [Lens: String]          // all three lenses come back at once
    var forYou: String
    var readDurations: [Lens: TimeInterval]
}

struct Dream: Identifiable, Codable {
    let id: UUID
    var createdAt: Date
    var title: String
    var transcript: String
    var emotions: [Emotion]
    var recurrence: Recurrence
    var someoneSpecific: Bool
    var symbols: [DreamSymbol]
    var interpretation: Interpretation?
    var imageName: String?             // asset name in phase 1, URL later
    var notes: String
}
```

Main-lens rule (Interpretation screen): `mainLens = screenOverride ?? appState.preferredLens`;
the other two lenses, in `Lens.allCases` order, are the alternatives.

## Services (protocols + mocks)

```swift
protocol SpeechService    { func start() -> AsyncStream<String>; func stop() }       // mock: types the sample transcript
protocol DreamAnalysisService { func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error> } // mock: 4 steps x 1.3 s, then result
protocol DreamStore       { var dreams: [Dream] { get }; func save(_ d: Dream) }     // mock: in-memory seeded with the 5 Journal dreams
protocol PurchaseService  { func purchase(_ plan: Plan) async throws; func restore() async throws } // mock: success after 0.8 s
protocol ReadAloudService { func play(_ text: String); func pause(); func stop(); var progress: Double { get } } // AVSpeechSynthesizer
```

Inject via the SwiftUI environment. All sample content (texts, symbols, journal entries,
library tiles) is listed in doc 03 - put it in `MockData.swift`.
