import Foundation

/// Sample content from the designs (docs/03-screens.md). Copy is final - keep it verbatim.
enum MockData {
    // MARK: Transcript

    static let transcript = "I was back in my grandmother’s house, but the hallway kept getting longer. Every door opened onto another staircase going down, and someone was calling my name from below."

    static let onboardingQuote = "“I was back in my grandmother’s house, and the hallway kept getting longer…”"

    // MARK: Symbols

    static let staircase = DreamSymbol(title: "Staircase down", meaning: "Progress you can’t see yet", keyword: "stairs", glyph: .stairs)
    static let grandmothersHouse = DreamSymbol(title: "Grandmother’s house", meaning: "Roots and safety", keyword: "house", glyph: .house)
    static let callingVoice = DreamSymbol(title: "A voice calling", meaning: "A part of you asking for attention", keyword: "voice", glyph: .person)

    // MARK: The house with endless stairs

    static let houseInterpretation = Interpretation(
        texts: [
            .psychology: "Endless stairs in a familiar house often appear when you are working through something slowly, one step at a time, without seeing where it ends. Your grandmother’s house points to roots and safety. The voice calling from below is a part of you asking for attention - a feeling or a decision you keep postponing.",
            .spiritual: "Going down stairs is a classic image of a journey inward, toward memory and intuition. A house that keeps growing suggests your inner world is larger than you let yourself explore. The calling voice is often read as guidance: something from your past holds wisdom for your present.",
            .dreamBook: "Stairs going down: a time of reflection before a change. An old family house: news from family, or a return to an old question. Hearing your name called: an important message is near, so listen to the people close to you this week."
        ],
        forYou: "You mentioned stress at work. Dreams like this often come when a decision feels unfinished. What is the one step you keep putting off?",
        readDurations: [.psychology: 72, .spiritual: 64, .dreamBook: 48]
    )

    /// The dream produced by the mock analysis for any draft.
    static func analyzedDream(from draft: DreamDraft, at date: Date) -> Dream {
        Dream(
            createdAt: date,
            title: "The house with endless stairs",
            transcript: draft.transcript.isEmpty ? transcript : draft.transcript,
            emotions: draft.emotions,
            recurrence: draft.recurrence ?? .never,
            someoneSpecific: draft.someoneSpecific ?? false,
            symbols: [staircase, grandmothersHouse, callingVoice],
            interpretation: houseInterpretation,
            imageName: Dream.placeholderImageName
        )
    }

    // MARK: Journal seed

    /// The five Journal dreams from the design plus older September entries.
    static func seedDreams(now: Date = .now, calendar: Calendar = .current) -> [Dream] {
        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let lake = DreamSymbol(title: "A frozen lake", meaning: "Feelings on pause", keyword: "lake", glyph: .water)
        let flying = DreamSymbol(title: "Flying", meaning: "Freedom and perspective", keyword: "flying", glyph: .bird)
        let exam = DreamSymbol(title: "An exam", meaning: "Fear of being judged", keyword: "exam", glyph: .eye)
        let dog = DreamSymbol(title: "Your old dog", meaning: "Loyalty and comfort", keyword: "dog", glyph: .heart)
        let market = DreamSymbol(title: "A night market", meaning: "Too many choices", keyword: "market", glyph: .house)
        let chase = DreamSymbol(title: "Being chased", meaning: "Avoiding something", keyword: "chase", glyph: .person)
        let steps = DreamSymbol(title: "Stone steps", meaning: "A slow way forward", keyword: "stairs", glyph: .stairs)

        var dreams: [Dream] = [
            Dream(createdAt: date(daysAgo: 1, hour: 7, minute: 12), title: "The house with endless stairs",
                  transcript: transcript, emotions: [.anxiety, .confusion], recurrence: .sometimes, someoneSpecific: true,
                  symbols: [staircase, grandmothersHouse, callingVoice], interpretation: houseInterpretation, imageName: "DreamThumb1"),
            Dream(createdAt: date(daysAgo: 3, hour: 6, minute: 48), title: "Flying over a frozen lake",
                  transcript: "I was flying low over a frozen lake, then climbing stone steps into the sky. The ice was glowing.",
                  emotions: [.joy], symbols: [flying, lake, steps],
                  interpretation: tailored(
                      psychology: "Flying over ice suggests you are rising above feelings you have put on hold. The lift you felt points to a new sense of control, and the steps say you are getting there one move at a time.",
                      spiritual: "Frozen water is emotion waiting to thaw. Seeing it from above is a sign of clarity arriving: you can now look at what was hidden under the surface.",
                      dreamBook: "Flying: success in a plan you care about. A frozen lake: a calm period before good news. Steps upward: steady progress."),
                  imageName: "DreamThumb2"),
            Dream(createdAt: date(daysAgo: 4, hour: 7, minute: 30), title: "Late for an exam I never took",
                  transcript: "I ran up the school stairs for an exam I never studied for, and the room kept moving.",
                  emotions: [.anxiety], symbols: [exam, steps],
                  interpretation: tailored(
                      psychology: "Exam dreams often show up when you feel measured by others. Being late for a test you never took hints at pressure you put on yourself rather than a real deadline.",
                      spiritual: "An unexpected test is a call to trust what you already know. The moving room asks you to stop chasing and let the answer come to you.",
                      dreamBook: "An exam: a situation where you will be noticed. Being late: rushing a decision. Stairs: an effort that pays off later."),
                  imageName: "DreamThumb3"),
            Dream(createdAt: date(daysAgo: 8, hour: 8, minute: 5), title: "My old dog came back",
                  transcript: "My old dog was waiting at the door like nothing had happened, and we walked together for a long time.",
                  emotions: [.calm], symbols: [dog],
                  interpretation: tailored(
                      psychology: "Pets from the past often return when you need comfort and unconditional support. The calm walk suggests you are ready to make peace with a loss.",
                      spiritual: "A beloved animal returning is read as a visit of love and protection. You are being reminded that you are not alone right now.",
                      dreamBook: "A faithful dog: a loyal friend will help you soon. Walking together: harmony at home."),
                  imageName: "DreamThumb4"),
            Dream(createdAt: date(daysAgo: 10, hour: 6, minute: 55), title: "Chased through a night market",
                  transcript: "Someone was following me through a crowded night market and I could not find the exit.",
                  emotions: [.fear], symbols: [chase, market],
                  interpretation: tailored(
                      psychology: "Being chased is one of the most common ways the mind shows avoidance. The crowded market mirrors a busy mind - too many options, no clear exit.",
                      spiritual: "What chases us in dreams is often a part of ourselves we have not yet welcomed. Turning to face it is the invitation.",
                      dreamBook: "Being chased: a worry you can solve if you stop running. A market at night: choices to be made carefully."),
                  imageName: "DreamThumb2")
        ]

        let older: [(Int, String, [Emotion], DreamSymbol, String)] = [
            (12, "A door that would not close", [.anxiety], DreamSymbol(title: "An open door", meaning: "A chance you are unsure about", keyword: "door", glyph: .house), "DreamThumb3"),
            (13, "Swimming with my sister", [.calm], DreamSymbol(title: "Water", meaning: "Emotions rising", keyword: "water", glyph: .water), "DreamThumb1"),
            (15, "The garden full of light", [.joy], DreamSymbol(title: "A garden", meaning: "Growth and care", keyword: "garden", glyph: .leaf), "DreamThumb4"),
            (16, "Stairs under the sea", [.confusion], steps, "DreamThumb2"),
            (18, "Lost in my old school", [.anxiety], exam, "DreamThumb3"),
            (20, "A stranger at the window", [.fear], DreamSymbol(title: "A stranger", meaning: "A hidden side of you", keyword: "stranger", glyph: .eye), "DreamThumb1"),
            (22, "Dancing at a wedding", [.joy, .calm], DreamSymbol(title: "A wedding", meaning: "Commitment and new roles", keyword: "wedding", glyph: .heart), "DreamThumb4")
        ]
        dreams += older.map { daysAgo, title, emotions, symbol, image in
            Dream(createdAt: date(daysAgo: daysAgo, hour: 7, minute: 0), title: title, transcript: title + ".",
                  emotions: emotions, symbols: [symbol], interpretation: generic(for: symbol), imageName: image)
        }
        return dreams
    }

    private static func tailored(psychology: String, spiritual: String, dreamBook: String) -> Interpretation {
        Interpretation(
            texts: [.psychology: psychology, .spiritual: spiritual, .dreamBook: dreamBook],
            forYou: "Take one quiet minute today to notice where this feeling shows up in your waking life.",
            readDurations: [.psychology: 40, .spiritual: 36, .dreamBook: 28]
        )
    }

    private static func generic(for symbol: DreamSymbol) -> Interpretation {
        let meaning = symbol.meaning.prefix(1).lowercased() + symbol.meaning.dropFirst()
        return tailored(
            psychology: "\(symbol.title) in a dream often reflects \(meaning). Notice what in your waking life feels similar right now.",
            spiritual: "\(symbol.title) can be read as a quiet message about \(meaning). Give it a moment of attention today.",
            dreamBook: "\(symbol.title): \(meaning). Good things come to those who pay attention to this sign."
        )
    }

    // MARK: Library

    static let librarySymbols: [LibrarySymbol] = [
        LibrarySymbol(id: "teeth", title: "Teeth falling out", meaning: "Control and self-image",
                      detail: "One of the most common dreams. It tends to appear when you worry about how others see you or feel you are losing grip on a situation.",
                      categories: [.popular, .fear], imageName: "DreamThumb1", glyph: .person),
        LibrarySymbol(id: "falling", title: "Falling", meaning: "Losing your footing",
                      detail: "Falling often shows up in times of change, when something that felt stable starts to move. It asks where you need more support.",
                      categories: [.popular, .fear], imageName: "DreamThumb2", glyph: .stairs),
        LibrarySymbol(id: "ex", title: "Your ex", meaning: "Unfinished feelings",
                      detail: "Dreaming of an ex is rarely about the person. It usually points to a feeling or a lesson from that time that is still asking to be closed.",
                      categories: [.popular, .love, .people], imageName: "DreamThumb3", glyph: .heart),
        LibrarySymbol(id: "chased", title: "Being chased", meaning: "Avoiding something",
                      detail: "What chases you is often something you avoid while awake - a conversation, a decision, a feeling. Turning around is the way through.",
                      categories: [.popular, .fear, .people], imageName: "DreamThumb4", glyph: .person),
        LibrarySymbol(id: "water", title: "Water", meaning: "Emotions rising",
                      detail: "Water mirrors your emotional state: calm water for peace, rising or rough water for feelings that want space.",
                      categories: [.popular, .places], imageName: "DreamThumb3", glyph: .water),
        LibrarySymbol(id: "flying", title: "Flying", meaning: "Freedom and perspective",
                      detail: "Flying dreams come with a sense of lightness. They often appear when you rise above a problem or long for more freedom.",
                      categories: [.popular, .places], imageName: "DreamThumb1", glyph: .bird),
        LibrarySymbol(id: "snakes", title: "Snakes", meaning: "Hidden fear or healing",
                      detail: "Snakes carry two meanings: a fear you have not named yet, or transformation and healing, like a skin being shed.",
                      categories: [.popular, .animals, .fear], imageName: "DreamThumb2", glyph: .leaf),
        LibrarySymbol(id: "pregnancy", title: "Pregnancy", meaning: "Something new growing",
                      detail: "Pregnancy in a dream usually stands for a project, idea or part of you that is quietly growing and getting ready to be born.",
                      categories: [.popular, .love], imageName: "DreamThumb4", glyph: .sparkle),
        LibrarySymbol(id: "wedding", title: "A wedding", meaning: "Commitment and new roles",
                      detail: "Weddings point to joining two parts of your life, or to a commitment you are considering.",
                      categories: [.love, .people], imageName: "DreamThumb1", glyph: .heart),
        LibrarySymbol(id: "house", title: "A house", meaning: "Your inner self",
                      detail: "Houses often stand for the self. New rooms suggest parts of you still to explore; an old family house points to roots.",
                      categories: [.places], imageName: "DreamThumb2", glyph: .house),
        LibrarySymbol(id: "dog", title: "Dogs", meaning: "Loyalty and friendship",
                      detail: "A friendly dog reflects trust and companionship; an angry one, a relationship that feels tense.",
                      categories: [.animals], imageName: "DreamThumb3", glyph: .heart),
        LibrarySymbol(id: "stranger", title: "A stranger", meaning: "A hidden side of you",
                      detail: "Strangers often embody qualities you have not yet recognised in yourself.",
                      categories: [.people], imageName: "DreamThumb4", glyph: .eye)
    ]
}
