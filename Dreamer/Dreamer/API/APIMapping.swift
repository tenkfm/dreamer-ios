import Foundation

// Generated contract types -> domain models (and back for request bodies). Kept in one file so a
// contract change shows up here as a compile error, never deeper in the app.

// MARK: - Shared enums

extension Lens {
    init(_ value: Components.Schemas.Lens) {
        switch value {
        case .psychology: self = .psychology
        case .spiritual: self = .spiritual
        case .dreamBook: self = .dreamBook
        }
    }

    var contract: Components.Schemas.Lens {
        switch self {
        case .psychology: .psychology
        case .spiritual: .spiritual
        case .dreamBook: .dreamBook
        }
    }
}

extension Emotion {
    init(_ value: Components.Schemas.Emotion) {
        switch value {
        case .fear: self = .fear
        case .joy: self = .joy
        case .anxiety: self = .anxiety
        case .calm: self = .calm
        case .confusion: self = .confusion
        }
    }

    var contract: Components.Schemas.Emotion {
        switch self {
        case .fear: .fear
        case .joy: .joy
        case .anxiety: .anxiety
        case .calm: .calm
        case .confusion: .confusion
        }
    }
}

extension Recurrence {
    init(_ value: Components.Schemas.Recurrence) {
        switch value {
        case .never: self = .never
        case .sometimes: self = .sometimes
        case .often: self = .often
        }
    }

    var contract: Components.Schemas.Recurrence {
        switch self {
        case .never: .never
        case .sometimes: .sometimes
        case .often: .often
        }
    }
}

extension Goal {
    init(_ value: Components.Schemas.Goal) {
        switch value {
        case .understand: self = .understand
        case .recurring: self = .recurring
        case .someone: self = .someone
        case .remember: self = .remember
        }
    }

    var contract: Components.Schemas.Goal {
        switch self {
        case .understand: .understand
        case .recurring: .recurring
        case .someone: .someone
        case .remember: .remember
        }
    }
}

extension Glyph {
    init(_ value: Components.Schemas.Glyph) {
        self = Glyph(rawValue: value.rawValue) ?? .sparkle
    }
}

extension DreamStatus {
    init(_ value: Components.Schemas.DreamStatus) {
        switch value {
        case .analyzing: self = .analyzing
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

extension MediaStatus {
    init(_ value: Components.Schemas.MediaStatus) {
        switch value {
        case .pending: self = .pending
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

extension APIErrorCode {
    init(_ value: Components.Schemas.ApiErrorCode) {
        self = APIErrorCode(contractValue: value.rawValue)
    }
}

extension SymbolCategory {
    init(_ value: Components.Schemas.LibraryCategory) {
        self = SymbolCategory(rawValue: value.rawValue) ?? .popular
    }
}

private func makeURL(_ string: String?) -> URL? {
    string.flatMap(URL.init(string:))
}

private func uuid(_ string: String) throws(APIError) -> UUID {
    guard let value = UUID(uuidString: string) else { throw APIError.invalidResponse(status: nil) }
    return value
}

// MARK: - Session and profile

extension AuthSession {
    init(_ tokens: Components.Schemas.AuthTokens) {
        self.init(accessToken: tokens.accessToken,
                  accessExpiresAt: tokens.accessExpiresAt,
                  refreshToken: tokens.refreshToken,
                  refreshExpiresAt: tokens.refreshExpiresAt,
                  userID: tokens.user.id,
                  isNewUser: tokens.user.isNew)
    }
}

extension UserProfile {
    init(_ profile: Components.Schemas.Profile) {
        self.init(id: profile.id,
                  email: profile.email,
                  name: profile.name,
                  goal: profile.goal.map(Goal.init),
                  preferredLens: Lens(profile.preferredLens),
                  reminder: Reminder(enabled: profile.reminder.enabled, time: profile.reminder.time),
                  timezone: profile.timezone,
                  nightMode: profile.nightMode,
                  voice: profile.voice,
                  createdAt: profile.createdAt)
    }
}

extension ProfileUpdate {
    var contract: Components.Schemas.UpdateProfile {
        let reminder: Components.Schemas.UpdateProfile.ReminderPayload? =
            reminderEnabled == nil && reminderTime == nil
                ? nil
                : .init(enabled: reminderEnabled, time: reminderTime)
        return Components.Schemas.UpdateProfile(
            name: name,
            goal: goal?.contract,
            preferredLens: preferredLens?.contract,
            reminder: reminder,
            timezone: timezone,
            nightMode: nightMode,
            voice: voice
        )
    }
}

// MARK: - Dreams

extension DreamSubmission {
    var contract: Components.Schemas.CreateDream {
        Components.Schemas.CreateDream(
            clientId: clientId,
            text: text,
            details: details.map {
                .init(emotions: $0.emotions.map(\.contract),
                      recurrence: $0.recurrence.contract,
                      someoneSpecific: $0.someoneSpecific)
            },
            recordedAt: recordedAt,
            recordingId: recordingId
        )
    }
}

extension DreamAudio {
    init(_ audio: Components.Schemas.DreamAudio) {
        self.init(lens: Lens(audio.lens),
                  status: MediaStatus(audio.status),
                  url: makeURL(audio.url),
                  duration: audio.durationSec,
                  wordTimings: audio.wordTimings.map { WordTiming(word: $0.word, start: $0.startSec, end: $0.endSec) })
    }
}

extension Dream {
    init(_ detail: Components.Schemas.DreamDetail) throws(APIError) {
        let mainLens = Lens(detail.mainLens)
        let interpretation = detail.interpretation.map { payload -> Interpretation in
            let texts: [Lens: String] = [
                .psychology: payload.lenses.psychology,
                .spiritual: payload.lenses.spiritual,
                .dreamBook: payload.lenses.dreamBook
            ]
            var durations: [Lens: TimeInterval] = [:]
            for (lens, audio) in Dream.audio(detail.audio) {
                if let seconds = audio.duration { durations[lens] = seconds }
            }
            return Interpretation(texts: texts, forYou: payload.forYou, readDurations: durations,
                                  safetyFlag: payload.safetyFlag)
        }
        let symbols = detail.interpretation?.symbols.map {
            DreamSymbol(title: $0.name, meaning: $0.meaning, keyword: $0.keyword, glyph: Glyph($0.icon))
        } ?? []

        self.init(id: try uuid(detail.id),
                  createdAt: detail.createdAt,
                  title: detail.title ?? "",
                  transcript: detail.text,
                  emotions: detail.emotions.map(Emotion.init),
                  recurrence: detail.recurrence.map(Recurrence.init) ?? .never,
                  someoneSpecific: detail.someoneSpecific ?? false,
                  symbols: symbols,
                  interpretation: interpretation,
                  notes: detail.notes)
        clientId = detail.clientId
        status = DreamStatus(detail.status)
        analysisStep = detail.analysisStep
        errorCode = detail.errorCode.map(APIErrorCode.init)
        self.mainLens = mainLens
        image = detail.image.map {
            DreamImageInfo(status: MediaStatus($0.status), url: makeURL($0.url), previewURL: makeURL($0.previewUrl),
                           thumbnailURL: makeURL($0.thumbnailUrl), width: $0.width, height: $0.height, version: $0.version)
        }
        audio = Dictionary(uniqueKeysWithValues: Dream.audio(detail.audio).map { entry in (entry.lens, entry.audio) })
        video = detail.video.map {
            DreamVideo(status: MediaStatus($0.status), url: makeURL($0.url), duration: $0.durationSec,
                       lens: $0.lens.map(Lens.init), width: $0.width, height: $0.height)
        }
        updatedAt = detail.updatedAt
    }

    /// The dream's voice-overs. Word timings are not part of the dream: `GET .../audio` has them.
    private static func audio(_ payload: Components.Schemas.DreamDetail.AudioPayload) -> [(lens: Lens, audio: DreamAudio)] {
        func make(_ lens: Lens, _ status: Components.Schemas.MediaStatus, _ url: String?, _ duration: Double?)
        -> (lens: Lens, audio: DreamAudio) {
            (lens, DreamAudio(lens: lens, status: MediaStatus(status), url: makeURL(url), duration: duration, wordTimings: []))
        }
        var result: [(lens: Lens, audio: DreamAudio)] = []
        if let a = payload.psychology { result.append(make(.psychology, a.status, a.url, a.durationSec)) }
        if let a = payload.spiritual { result.append(make(.spiritual, a.status, a.url, a.durationSec)) }
        if let a = payload.dreamBook { result.append(make(.dreamBook, a.status, a.url, a.durationSec)) }
        return result
    }
}

extension DreamSummary {
    init(_ item: Components.Schemas.DreamList.ItemsPayloadPayload) throws(APIError) {
        guard let weekOf = APIDates.parseDay(item.weekOf) else { throw APIError.invalidResponse(status: nil) }
        self.init(id: try uuid(item.id),
                  createdAt: item.createdAt,
                  weekOf: weekOf,
                  title: item.title,
                  status: DreamStatus(item.status),
                  emotions: item.emotions.map(Emotion.init),
                  thumbnailURL: makeURL(item.thumbnailUrl),
                  symbols: item.symbols,
                  snippet: item.snippet)
    }
}

extension DreamProgress {
    init(_ status: Components.Schemas.DreamStatusResponse) throws(APIError) {
        self.init(id: try uuid(status.id),
                  status: DreamStatus(status.status),
                  analysisStep: status.analysisStep,
                  title: status.title,
                  errorCode: status.errorCode.map(APIErrorCode.init))
    }
}

// MARK: - Insights

extension WeekInsight {
    init(_ week: Components.Schemas.WeekInsight) {
        self.init(days: week.days.map {
            Day(date: APIDates.parseDay($0.date) ?? .distantPast, letter: $0.letter, caught: $0.caught, isToday: $0.isToday)
        }, count: week.count)
    }
}

extension VoiceList {
    init(_ list: Components.Schemas.VoiceList) {
        self.init(items: list.items.map {
            Voice(id: $0.id, name: $0.name, gender: Voice.Gender(rawValue: $0.gender.rawValue) ?? .neutral,
                  accent: $0.accent, description: $0.description, previewURL: makeURL($0.previewUrl), isDefault: $0.isDefault)
        }, defaultVoiceID: list.defaultVoiceId)
    }
}

extension HomeCard {
    init(_ card: Components.Schemas.HomeCards.CardsPayloadPayload) {
        self.init(id: card.id, kind: card.kind, overline: card.overline, title: card.title, text: card.text,
                  imageURL: makeURL(card.imageUrl),
                  action: card.action.flatMap { action in
                      Destination(target: action.target, dreamID: action.dreamId, slug: action.slug, url: action.url)
                          .map { Action(label: action.label, destination: $0) }
                  })
    }
}

extension HomeCard.Destination {
    /// Nil for a target this build does not know, or one without what it needs to open.
    init?(target: String, dreamID: String?, slug: String?, url: String?) {
        switch target {
        case "journal": self = .journal
        case "record": self = .record
        case "dream":
            guard let id = dreamID.flatMap(UUID.init(uuidString:)) else { return nil }
            self = .dream(id)
        case "library_symbol":
            guard let slug, !slug.isEmpty else { return nil }
            self = .librarySymbol(slug: slug)
        case "article":
            // Only the web: the in-app browser opens nothing else.
            guard let url = makeURL(url), url.scheme == "https" else { return nil }
            self = .article(url)
        default: return nil
        }
    }
}

extension MonthInsight {
    init(_ month: Components.Schemas.MonthInsight) {
        self.init(month: month.month,
                  monthName: month.monthName,
                  dreamCount: month.dreamCount,
                  nightsSoFar: month.nightsSoFar,
                  topSymbol: month.topSymbol,
                  emotions: month.emotions.map { EmotionShare(emotion: Emotion($0.emotion), share: $0.share) },
                  recurringSymbols: month.recurringSymbols.map { RecurringSymbol(keyword: $0.keyword, count: $0.count) })
    }
}

// MARK: - Library

extension LibrarySymbol {
    init(_ item: Components.Schemas.LibrarySymbolList.ItemsPayloadPayload) {
        self.init(id: item.slug, title: item.title, meaning: item.meaning, detail: "",
                  categories: Set(item.categories.map(SymbolCategory.init)), imageName: Dream.placeholderImageName,
                  glyph: Glyph(item.icon), imageURL: makeURL(item.imageUrl))
    }

    init(_ symbol: Components.Schemas.LibrarySymbol) {
        self.init(id: symbol.slug, title: symbol.title, meaning: symbol.meaning, detail: symbol.description,
                  categories: Set(symbol.categories.map(SymbolCategory.init)), imageName: Dream.placeholderImageName,
                  glyph: Glyph(symbol.icon), imageURL: makeURL(symbol.imageUrl), question: symbol.question,
                  lenses: [.psychology: symbol.lenses.psychology, .spiritual: symbol.lenses.spiritual,
                           .dreamBook: symbol.lenses.dreamBook],
                  related: symbol.related)
    }
}

// MARK: - Subscription

extension SubscriptionInfo {
    init(_ subscription: Components.Schemas.Subscription) {
        self.init(state: SubscriptionState(rawValue: subscription.status.rawValue) ?? .none,
                  isPremium: subscription.isPremium,
                  plan: subscription.plan.flatMap { Plan(rawValue: $0.rawValue) },
                  store: subscription.store?.rawValue,
                  expiresAt: subscription.expiresAt,
                  willRenew: subscription.willRenew,
                  freeInterpretationsLeft: subscription.freeInterpretationsLeft,
                  paywallVariant: PaywallVariant(rawValue: subscription.paywallVariant.rawValue) ?? .hard)
    }
}
