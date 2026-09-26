import SwiftUI

/// 11 Interpretation: one scroll view with a fixed header of glass buttons.
struct InterpretationView: View {
    @State private var viewModel: InterpretationViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: InterpretationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                DS.Palette.background.ignoresSafeArea()
                if let dream = viewModel.dream {
                    content(dream: dream, topInset: geo.safeAreaInsets.top)
                } else if viewModel.isLoadingDream {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    missingDream
                }
                header
            }
        }
        .toast($viewModel.toastMessage)
        .sheet(item: $viewModel.shareItem) { item in
            ActivityView(items: [item.image]) { activity, completed in
                viewModel.shareSheetClosed(activity: activity, completed: completed)
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .task { await viewModel.refreshDream() }
        .task(id: viewModel.imageRequest) { await viewModel.loadImage() }
        .task(id: viewModel.mainLens) { viewModel.prepareVoice() }
        .onDisappear {
            viewModel.stopPlayback()
            Task { await viewModel.flushNotes() }
        }
    }

    // MARK: Header

    private var header: some View {
        HeaderBar {
            GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
        } center: {
            EmptyView()
        } trailing: {
            if viewModel.dream != nil, viewModel.support == nil {
                HStack(spacing: 10) {
                    GlassIconButton(systemImage: "arrow.down.to.line", accessibilityLabel: "Save image") {
                        Task { await viewModel.saveImage() }
                    }
                    .disabled(viewModel.isSavingImage)
                    GlassIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {
                        Task { await viewModel.share() }
                    }
                    .disabled(viewModel.isPreparingShare)
                }
            }
        }
        .enterUp(0.1)
    }


    // MARK: Content

    private func content(dream: Dream, topInset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.section) {
                DreamHero(dream: dream, dateText: viewModel.dateText, topInset: topInset,
                          showsImageBadge: viewModel.support == nil,
                          loadedImage: viewModel.loadedImage,
                          phase: viewModel.support == nil ? viewModel.imagePhase : .asset,
                          canRegenerate: viewModel.canRegenerateImage,
                          onRegenerate: { Task { await viewModel.regenerateImage() } })
                if let support = viewModel.support {
                    Group {
                        SupportCard(content: support).enterUp(0.5)
                        thoughts
                        disclaimer
                    }
                    .padding(.horizontal, DS.Space.screen)
                } else {
                    reading(dream)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private func reading(_ dream: Dream) -> some View {
        if !dream.symbols.isEmpty {
            keySymbols(dream.symbols).enterUp(0.5)
        }
        Group {
            mainInterpretation.enterUp(0.65)
            otherPerspectives.enterUp(0.8)
            if let forYou = viewModel.forYou {
                InsightCard(overline: "For you, right now", text: forYou)
            }
            thoughts
            VStack(spacing: 12) {
                PrimaryButton(title: "Share my dream image", systemImage: "square.and.arrow.up",
                              isLoading: viewModel.isPreparingShare) {
                    Task { await viewModel.share() }
                }
                if viewModel.canShareToStories {
                    PillButton(title: "Share to Instagram Stories") {
                        Task { await viewModel.shareToStories() }
                    }
                }
            }
            disclaimer
        }
        .padding(.horizontal, DS.Space.screen)
    }

    private var disclaimer: some View {
        Text("Dreamer offers reflection, not medical advice.")
            .textStyle(.label, color: DS.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func keySymbols(_ symbols: [DreamSymbol]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Key symbols").padding(.horizontal, DS.Space.screen)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(symbols) { symbol in
                        SymbolCard(title: symbol.title, meaning: symbol.meaning, glyph: symbol.glyph)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, -14)
        }
    }

    // MARK: Main lens

    private var mainInterpretation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Overline(text: "Your interpretation")
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Circle().fill(DS.Palette.peach).frame(width: 6, height: 6)
                    Text(viewModel.mainLens.title)
                        .font(DreamerFont.fixed(13))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(DS.Palette.surface.opacity(0.9)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lens: \(viewModel.mainLens.title)")
            }
            VoicePlayer(state: playerState,
                        progress: viewModel.readAloud.progress,
                        durationText: viewModel.durationText,
                        onToggle: viewModel.togglePlayback)
            Text(viewModel.text(for: viewModel.mainLens))
                .textStyle(.bodyLong)
                .fixedSize(horizontal: false, vertical: true)
                .id(viewModel.mainLens)
                .transition(.opacity)
        }
        .padding(DS.Space.cardPaddingLarge)
        .glassCard(radius: DS.Radius.cardLarge)
        .animation(.soft(0.5), value: viewModel.mainLens)
    }

    private var playerState: VoicePlayer.State {
        switch viewModel.readAloud.state {
        case .idle: .idle
        case .loading: .loading
        case .playing: .playing
        case .paused: .paused
        }
    }

    // MARK: Alternatives

    private var otherPerspectives: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Other perspectives", trailing: "\(viewModel.alternativeLenses.count) more lenses")
            ForEach(viewModel.alternativeLenses) { lens in
                AlternativeLensCard(
                    lens: lens,
                    text: viewModel.text(for: lens),
                    isExpanded: viewModel.isExpanded(lens),
                    onToggle: { viewModel.toggleExpanded(lens) },
                    onPromote: { viewModel.promote(lens) }
                )
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: viewModel.mainLens)
    }

    // MARK: Notes

    private var thoughts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your thoughts").textStyle(.bodyStrong)
            GlassTextEditor(placeholder: "Only you can see this", text: $viewModel.notes)
        }
    }

    private var missingDream: some View {
        VStack(spacing: 12) {
            Text("This dream is no longer here").textStyle(.heading)
            Text("It may have been deleted.").textStyle(.secondary, color: DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hero

/// 380 pt dream image revealed from blur, fading into the background, with date, title and emotions.
private struct DreamHero: View {
    var dream: Dream
    var dateText: String
    var topInset: CGFloat
    var showsImageBadge = true
    var loadedImage: UIImage?
    var phase: InterpretationViewModel.ImagePhase = .asset
    var canRegenerate = false
    var onRegenerate: () -> Void = {}

    /// "AI dream image" on a shown image; while painting, what is happening; after a failure, a retry.
    @ViewBuilder private var imageBadge: some View {
        Group {
            switch phase {
            case .asset, .ready:
                badgeCapsule { Text("AI dream image") }
            case .generating, .loading:
                badgeCapsule {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(DS.Palette.textPrimary)
                        Text(phase == .generating ? "Painting your dream…" : "Loading image…")
                    }
                }
                .accessibilityElement(children: .combine)
            case .failed:
                if canRegenerate {
                    PillButton(title: "Try a new image", action: onRegenerate)
                }
            }
        }
        .padding(.top, topInset + DS.Space.headerTop + DS.Size.iconButton + 14)
        .padding(.trailing, DS.Space.screen)
        .enterUp(0.3)
        .animation(.soft(0.4), value: phase)
    }

    private func badgeCapsule(@ViewBuilder _ label: () -> some View) -> some View {
        label()
            .font(DreamerFont.fixed(11))
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .glassCapsule()
    }

    private var heroImage: Image {
        loadedImage.map(Image.init(uiImage:)) ?? DreamImage.image(named: dream.imageName)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                heroImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
                    .blur(radius: revealed || reduceMotion ? 0 : 14, opaque: true)
                    .scaleEffect(revealed || reduceMotion ? 1 : 1.05)
                    .clipped()
            }
            .accessibilityHidden(true)
            .contextMenu {
                if canRegenerate {
                    Button("Create a new image", systemImage: "sparkles", action: onRegenerate)
                }
            }

            LinearGradient(colors: [DS.Palette.background.opacity(0), DS.Palette.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: DS.Size.heroFade)

            VStack(alignment: .leading, spacing: 10) {
                Text(dateText).textStyle(.secondary, color: DS.Palette.textTertiary)
                Text(dream.title)
                    .textStyle(.display)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !dream.emotions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(dream.emotions) { emotion in
                            EmotionTag(title: emotion.title, color: emotion.color, size: .medium)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.screen)
            .enterUp(0.35)
        }
        .frame(height: DS.Size.heroHeight)
        .overlay(alignment: .topTrailing) {
            if showsImageBadge { imageBadge }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) { revealed = true }
        }
        .onChange(of: loadedImage) { _, image in
            // A painted image arrives after the screen opened: the same reveal from blur.
            guard image != nil else { return }
            revealed = false
            withAnimation(.easeOut(duration: 1.6)) { revealed = true }
        }
    }
}

// MARK: - Alternative lens card

private struct AlternativeLensCard: View {
    var lens: Lens
    var text: String
    var isExpanded: Bool
    var onToggle: () -> Void
    var onPromote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(lens.title).textStyle(.bodyStrong)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DS.Palette.icon)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    Text(text)
                        .font(DreamerFont.ui(14, relativeTo: .callout))
                        .lineSpacing(4)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapses the text" : "Shows the full text")

            if isExpanded {
                HStack {
                    Spacer()
                    PillButton(title: "Make this my main lens", action: onPromote)
                }
                .transition(.opacity.animation(.soft(0.4)))
            }
        }
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: DS.Radius.card)
        .animation(.soft(0.35), value: isExpanded)
        .sensoryFeedback(.selection, trigger: isExpanded)
    }
}

#Preview {
    let store = InMemoryDreamStore()
    NavigationStack {
        InterpretationView(viewModel: InterpretationViewModel(
            dreamID: store.dreams[0].id, store: store, appState: .preview(),
            readAloud: MockReadAloudService(), imageSaver: MockImageSaver()))
    }
}
