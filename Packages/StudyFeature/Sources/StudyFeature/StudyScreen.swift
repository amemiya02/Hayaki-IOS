import AnkiCore
import CollectionStore
import HayakiAppearance
import SwiftUI

/// A deck the learner chose to study.
public struct StudyDeck: Identifiable, Hashable, Sendable {
    public let id: Int64
    /// The deck's own name, shown at the top of the study screen.
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

extension View {
    /// Supplies the sheet the reviewer opens when the learner edits a note.
    public func studyNoteEditor<Editor: View>(
        @ViewBuilder _ editor: @escaping @MainActor @Sendable (Int64) -> Editor
    ) -> some View {
        environment(\.studyNoteEditor) { cardID in AnyView(editor(cardID)) }
    }

    /// Presents a full-screen study session over `deck` while it is set,
    /// and sets it back to nil when the learner closes the session.
    public func studySession(of deck: Binding<StudyDeck?>, store: CollectionStore) -> some View {
        #if os(iOS)
        fullScreenCover(item: deck) { deck in
            StudyScreen(store: store, deck: deck)
        }
        #else
        sheet(item: deck) { deck in
            StudyScreen(store: store, deck: deck)
        }
        #endif
    }
}

/// The study screen: the card fills the screen, with the counts above it and
/// Show Answer or the four rating buttons at the bottom, within thumb reach.
public struct StudyScreen: View {
    @State private var model: StudySessionModel
    /// What the learner typed on a card that asks for typing.
    @State private var typedAnswer = ""
    @State private var editedCard: EditedCard?
    @State private var editedNoteTags: EditedNoteTags?
    @State private var preferences = ReviewerPreferences.load()
    @State private var webCommand: ReviewerWebCommand?
    @State private var pendingTap: Task<Void, Never>?
    @FocusState private var reviewerFocused: Bool
    @State private var showingSettings = false
    @State private var requestedAction: ReviewerCommand?
    @State private var route: ReviewerDestination?
    @State private var nextStudy: StudyDeck?
    #if os(iOS)
    @State private var cardHostUnavailable = false
    @State private var cardHostRevision = 0
    #endif
    @State private var autoAdvance = false
    @State private var timebox: StudyTimebox?
    @State private var feedback: ReviewFeedback?
    @State private var templateFullscreen: TemplateFullscreen = .standard
    @State private var templateMenu: TemplateMenu?
    @State private var initialCount = 0
    @Environment(\.reviewerDestination) private var destinations
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.studyNoteEditor) private var noteEditor
    #if os(iOS)
    @State private var audio = CardAudioPlayer()
    @State private var templateSpeech = TemplateSpeech()
    @State private var templateRecognition = TemplateRecognition()
    @State private var templateNetwork = TemplateNetworkStatus()
    @AppStorage(CardTemplatePreference.microphone) private var allowsTemplateMicrophone = false
    @AppStorage(CardTemplatePreference.collectionAccess) private var allowsTemplateCollectionAccess = false
    @State private var recorder = AudioRecorder()
    @State private var drawing = ReviewerDrawing()
    @State private var isErasing = false
    @State private var deckTools: ReviewerDeckTools
    #endif
    private let store: CollectionStore
    @State private var deckName: String
    private let profileFolder: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hayakiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(store: CollectionStore, deck: StudyDeck) {
        self.store = store
        _model = State(initialValue: StudySessionModel(store: store, deckID: deck.id))
        _deckName = State(initialValue: deck.name)
        profileFolder = store.location.folder
        #if os(iOS)
        _deckTools = State(initialValue: ReviewerDeckTools.load(profile: store.location.folder, deckID: deck.id))
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            if templateFullscreen.showsTopBar || model.state.card == nil {
                topBar
            }
            content
            if templateFullscreen.showsActions, preferences.toolbarPosition == .bottom || !templateFullscreen.showsTopBar {
                reviewerActions
            }
        }
        .background(theme.background.ignoresSafeArea())
        .task(id: ObjectIdentifier(model)) { await model.run() }
        .task(id: autoAdvanceTask) { await runAutoAdvance() }
        .task(id: feedback) {
            guard feedback != nil else { return }
            let duration = feedback?.duration ?? .seconds(2)
            try? await Task.sleep(for: duration)
            if !Task.isCancelled { feedback = nil }
        }
        .onChange(of: model.presentationNumber) {
            if initialCount == 0, model.state.card != nil {
                initialCount = model.counts.new + model.counts.learning + model.counts.due
            }
        }
        .onChange(of: model.reviewedCount) {
            if model.state.card != nil, let progress = model.timeboxProgress() { timebox = progress }
        }
        .overlay(alignment: .top) {
            if let feedback {
                feedback.label
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 60)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .modifier(TemplateMenuPresentation(selection: $templateMenu, dispatch: dispatch, onSettings: { showingSettings = true }))
        .overlay(alignment: .topLeading) {
            if !templateFullscreen.showsTopBar, model.state.card != nil {
                Button {
                    templateFullscreen = .standard
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel(Text("Leave Full Screen", bundle: .module))
                .padding(8)
            }
        }
        .modifier(ReviewerActionDialogs(model: model, requestedAction: $requestedAction))
        .sheet(item: $route, onDismiss: returnFromDestination) { route in
            destinations?(route) { nextStudy = $0 }
        }
        .alert(reviewerLocalized("Timebox Reached"), isPresented: Binding(
            get: { timebox != nil },
            set: { if !$0 { timebox = nil } }
        )) {
            Button(reviewerLocalized("Continue")) {
                model.restartTimebox()
                timebox = nil
            }
            Button(reviewerLocalized("Finish")) { dismiss() }
        } message: {
            if let timebox {
                Text("You reviewed \(timebox.reviewed) cards in \(timebox.limit.components.seconds / 60) minutes.", bundle: .module)
            }
        }
        .focusable()
        .focused($reviewerFocused)
        .onAppear { reviewerFocused = true }
        .onKeyPress { press in
            guard press.phase == .down else { return .ignored }
            return dispatchInput(.keyboard(ReviewerKey(press))) ? .handled : .ignored
        }
        #if os(iOS)
        .task(id: model.customSchedulingRequest?.id) {
            guard let work = model.customSchedulingRequest else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { await model.applyCustomSchedule(requestID: work.id, json: nil) }
        }
        .statusBarHidden(preferences.hideStatusBar || !templateFullscreen.showsTopBar)
        .persistentSystemOverlays(preferences.hideHomeIndicator ? .hidden : .automatic)
        .modifier(ReviewerIdleTimer(enabled: preferences.keepScreenOn || autoAdvance))
        .modifier(ReviewerController { _ = dispatchInput($0) })
        .modifier(ReviewerShake(
            enabled: side.flatMap { preferences.command(for: .gesture(.shake), on: $0) } != nil
        ) { _ = dispatchInput(.gesture(.shake)) })
        .onChange(of: deckTools) { _, value in
            value.save(profile: profileFolder, deckID: model.deckID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { templateRecognition.stop() }
        }
        .onDisappear {
            recorder.discard()
            audio.stop()
        }
        .alert(reviewerLocalized("Recording"), isPresented: Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.clearError() } }
        )) {
            if recorder.permissionDenied {
                Button(reviewerLocalized("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(reviewerLocalized("OK"), role: .cancel) { recorder.clearError() }
        } message: {
            Text(verbatim: recorder.errorMessage ?? "")
        }
        #endif
        .onDisappear {
            pendingTap?.cancel()
            pendingTap = nil
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            preferences = ReviewerPreferences.load()
            Task { await model.refreshReviewerPreferences() }
        }) {
            NavigationStack {
                ReviewerSettingsScreen(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(reviewerLocalized("Done")) { showingSettings = false }
                        }
                    }
            }
        }
        .sheet(item: $editedNoteTags) { note in
            ReviewerTagsSheet(model: model, noteID: note.id)
        }
        .sheet(item: $editedCard) { card in
            noteEditor?(card.id)
        }
        .alert(
            Text("Study Action Failed", bundle: .module),
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.clearActionError() } }
            )
        ) {
            Button { model.clearActionError() } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: model.actionError ?? "")
        }
    }

    private func returnFromDestination() {
        let requested = nextStudy
        nextStudy = nil
        guard let requested, requested.id != model.deckID else {
            Task { await model.refreshAfterExternalChanges() }
            return
        }
        deckName = requested.name
        typedAnswer = ""
        initialCount = 0
        autoAdvance = false
        templateFullscreen = .standard
        templateMenu = nil
        timebox = nil
        #if os(iOS)
        recorder.discard()
        deckTools = ReviewerDeckTools.load(profile: profileFolder, deckID: requested.id)
        drawing.clear()
        #endif
        model = StudySessionModel(store: store, deckID: requested.id)
    }

    private var side: ReviewerSide? {
        if model.state.answer != nil { return .answer }
        return model.state.question == nil ? nil : .question
    }

    private var keySignatures: [String] {
        preferences.bindings.compactMap { binding in
            guard binding.side == side, case .keyboard(let key) = binding.input else { return nil }
            return ([key.name] + key.modifiers.map(\.rawValue).sorted()).joined(separator: "+")
        }
    }

    private func dispatchInput(_ input: ReviewerInput) -> Bool {
        guard editedCard == nil, editedNoteTags == nil, !showingSettings, requestedAction == nil,
              route == nil, timebox == nil, !model.isBusy, let side,
              let command = preferences.command(for: input, on: side) else { return false }
        dispatch(command)
        return true
    }

    func dispatch(_ command: ReviewerCommand) {
        guard !model.isBusy else { return }
        switch command {
        case .exit: dismiss()
        case .edit:
            if let id = model.state.card?.id, noteEditor != nil { editedCard = EditedCard(id: id) }
        case .editTags:
            if let noteID = model.state.card?.noteID { editedNoteTags = EditedNoteTags(id: noteID) }
        case .deleteNote, .setDueDate, .resetProgress: requestedAction = command
        case .toggleAutoAdvance:
            autoAdvance.toggle()
            feedback = ReviewFeedback(label: autoAdvance
                ? Text("Auto Advance Enabled", bundle: .module)
                : Text("Auto Advance Disabled", bundle: .module))
        case .browse:
            guard destinations != nil else { return }
            Task {
                let search = try? await store.core.buildSearchString(.with { $0.deck = deckName }).val
                route = .browse(search: search ?? "")
            }
        case .statistics: route = .statistics(deckID: model.deckID)
        case .deckOptions: route = .deckOptions(deckID: model.state.card?.homeDeckID ?? model.deckID)
        case .cardInfo:
            if let id = model.state.card?.id { route = .cardInfo(cardID: id) }
        case .previousCardInfo:
            if let id = model.previousCardID { route = .cardInfo(cardID: id) }
        case .addNote: route = .addNote(homeDeckID: model.state.card?.homeDeckID)
        case .showHint:
            webCommand = ReviewerWebCommand(javascript: """
            if (window.ankidroid?.showHint) {
                window.ankidroid.showHint();
            } else {
                document.querySelector('a.hint:not([style*=none])')?.click();
            }
            """)
        case .showAllHints:
            webCommand = ReviewerWebCommand(javascript: """
            if (window.ankidroid?.showAllHints) {
                window.ankidroid.showAllHints();
            } else {
                document.querySelectorAll('a.hint:not([style*=none])').forEach(a => a.click());
            }
            """)
        case .pageUp:
            webCommand = ReviewerWebCommand(javascript: "window.scrollBy({top: -window.innerHeight})")
        case .pageDown:
            webCommand = ReviewerWebCommand(javascript: "window.scrollBy({top: window.innerHeight})")
        case .replayMedia:
            #if os(iOS)
            if recorder.state == .recording || recorder.state == .paused { recorder.stopRecording() }
            recorder.stopPlayback()
            audio.play(model.soundsToReplay())
            #endif
        case .toggleWhiteboard:
            #if os(iOS)
            deckTools.whiteboardEnabled.toggle()
            #endif
        case .recordVoice:
            #if os(iOS)
            deckTools.recorderShown.toggle()
            if !deckTools.recorderShown { recorder.discard() }
            #endif
        case .replayVoice:
            #if os(iOS)
            if recorder.file != nil {
                deckTools.recorderShown = true
                audio.stop()
                recorder.play()
            }
            #endif
        default:
            if let number = command.userActionNumber {
                webCommand = ReviewerWebCommand(javascript: "window.ankidroid?.userAction?.(\(number))")
            } else {
                let typed = typedAnswer
                Task {
                    if await model.perform(command, typed: typed), preferences.showFeedback, let rating = command.rating {
                        feedback = ReviewFeedback(label: rating.title)
                    }
                }
            }
        }
    }

    private func handleWebInput(_ input: ReviewerWebInput) {
        guard let side, let cardID = model.state.card?.id else { return }
        switch input {
        case .input(let input): _ = dispatchInput(input)
        case .swipe(let dx, let dy, let time):
            let scale = 100 / Double(max(preferences.swipeSensitivity, 1))
            guard hypot(dx, dy) >= 44 * scale, hypot(dx, dy) / max(1, time) >= 0.2 * scale else { return }
            let gesture: ReviewerGesture = abs(dx) > abs(dy)
                ? (dx < 0 ? .swipeLeft : .swipeRight)
                : (dy < 0 ? .swipeUp : .swipeDown)
            _ = dispatchInput(.gesture(gesture))
        case .tap(let x, let y):
            let zone = preferences.tapZones.gesture(x: x, y: y)
            if preferences.doubleTapMilliseconds > 0, preferences.command(for: .gesture(.doubleTap), on: side) != nil {
                if let pendingTap {
                    pendingTap.cancel()
                    self.pendingTap = nil
                    _ = dispatchInput(.gesture(.doubleTap))
                } else {
                    pendingTap = Task {
                        try? await Task.sleep(for: .milliseconds(preferences.doubleTapMilliseconds))
                        guard !Task.isCancelled else { return }
                        pendingTap = nil
                        guard self.side == side, model.state.card?.id == cardID else { return }
                        _ = dispatchInput(.gesture(zone))
                    }
                }
            } else {
                _ = dispatchInput(.gesture(zone))
            }
        }
    }

    private var autoAdvanceTask: AutoAdvanceTask? {
        guard autoAdvance, let side, let plan = model.autoAdvancePlan,
              scenePhase == .active, !showingSettings, editedCard == nil, editedNoteTags == nil,
              requestedAction == nil, route == nil, timebox == nil else { return nil }
        #if os(iOS)
        guard recorder.state != .recording, recorder.state != .paused else { return nil }
        #endif
        return AutoAdvanceTask(presentation: model.presentationNumber, side: side, plan: plan)
    }

    private func runAutoAdvance() async {
        guard let task = autoAdvanceTask else { return }
        #if os(iOS)
        if task.plan.waitForAudio {
            await Task.yield()
            await audio.waitForCompletion()
        }
        #endif
        do {
            try await Task.sleep(for: task.plan.delay)
        } catch { return }
        guard autoAdvanceTask == task else { return }
        if let command = task.plan.command {
            dispatch(command)
        } else {
            feedback = ReviewFeedback(label: task.side == .question
                ? Text("Question Time Elapsed", bundle: .module)
                : Text("Answer Time Elapsed", bundle: .module))
        }
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(preferences.showDeckTitle && !model.currentDeckName.isEmpty ? model.currentDeckName : deckName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if model.state.card != nil {
                    HStack {
                        if model.showsRemainingCounts { StudyCountsView(counts: model.counts) }
                        if model.showsAnswerTimer {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(model.answerTimer().formatted(.time(pattern: .minuteSecond)))
                                    .monospacedDigit()
                                    .accessibilityLabel(reviewerLocalized("Answer Timer"))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 64)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityLabel(Text("Close", bundle: .module))
                .keyboardShortcut(.cancelAction)
                Spacer()
                if preferences.toolbarPosition == .hidden {
                    Button(reviewerLocalized("Reviewer Settings"), systemImage: "gear") { showingSettings = true }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                } else if preferences.toolbarPosition == .top {
                    reviewerActions
                        .frame(maxWidth: 188, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .overlay(alignment: .bottom) {
            if preferences.showProgress, initialCount > 0 {
                ProgressView(value: Double(min(model.reviewedCount, initialCount)), total: Double(initialCount))
                    .labelsHidden()
                    .accessibilityLabel(reviewerLocalized("Study Progress"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // One view for both sides of every card, so the card's web view and
        // its page stay loaded for the whole session.
        if let card = model.state.card {
            studying(card, showingAnswer: model.state.answer != nil)
        } else {
            noCard
        }
    }

    @ViewBuilder
    private var noCard: some View {
        switch model.state {
        case .loading, .question, .answer:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished(let summary):
            FinishedView(
                summary: summary,
                onUnbury: { Task { await model.unburyDeck() } },
                onRebuild: { Task { await model.rebuildFinishedFilteredDeck() } },
                onOptions: destinations == nil || summary.isFiltered ? nil : { route = .deckOptions(deckID: model.deckID) },
                onCustomStudy: destinations == nil || summary.isFiltered ? nil : { route = .customStudy(deckID: model.deckID) },
                onDone: { dismiss() }
            )
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Continue Studying", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            } actions: {
                Button {
                    dismiss()
                } label: {
                    Text("Close", bundle: .module)
                }
            }
        }
    }

    private func studying(_ card: StudyCard, showingAnswer: Bool) -> some View {
        VStack(spacing: 0) {
            cardView(CardDisplay(card, isAnswer: showingAnswer, presentation: model.presentationNumber))
                // On an iPad, a readable column rather than a stretched line.
                .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(preferences.cardFrame ? 8 : 0)
                .background(preferences.cardFrame ? theme.surface : Color.clear)
                .clipShape(.rect(cornerRadius: preferences.cardFrame ? 18 : 0))
                .overlay {
                    if preferences.cardFrame {
                        RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary.opacity(0.2))
                            .allowsHitTesting(false)
                    }
                }
                #if os(iOS)
                .overlay {
                    if deckTools.whiteboardEnabled && deckTools.drawingShown {
                        ReviewerWhiteboard(drawing: drawing, tools: deckTools, isErasing: isErasing)
                    }
                }
                .overlay(alignment: whiteboardAlignment) {
                    if deckTools.whiteboardEnabled {
                        ReviewerWhiteboardTools(drawing: drawing, options: $deckTools, isErasing: $isErasing)
                            .padding(8)
                    }
                }
                #endif
            Divider()
            #if os(iOS)
            if deckTools.recorderShown {
                HStack {
                    Spacer()
                    ReviewerVoiceControls(recorder: recorder, stopCardAudio: audio.stop)
                    Spacer()
                    Button(reviewerLocalized("Hide Recorder"), systemImage: "xmark.circle") {
                        recorder.discard()
                        deckTools.recorderShown = false
                    }
                    .labelStyle(.iconOnly)
                    .padding(.trailing, 12)
                }
            }
            #endif
            if preferences.showAnswerButtons, templateFullscreen.showsAnswer {
                AnswerBar(
                    card: card, showingAnswer: showingAnswer, isAnswering: model.isBusy,
                    minimumPress: Double(preferences.minimumPressMilliseconds) / 1000,
                    cooldown: .milliseconds(preferences.doubleTapMilliseconds),
                    buttonHeight: Double(preferences.answerButtonSize) * 0.52,
                    hideHardAndEasy: preferences.hideHardAndEasy, showsIntervals: model.showsRatingIntervals
                ) {
                    dispatch(.showAnswer)
                } onShortPress: {
                    feedback = ReviewFeedback(label: Text("Hold Show Answer to reveal the card.", bundle: .module))
                } onRate: { rating in
                    dispatch(rating.reviewerCommand)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    #if os(iOS)
    private var whiteboardAlignment: Alignment {
        switch deckTools.toolbarAlignment ?? .bottom {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        }
    }
    #endif

    @ViewBuilder
    private func cardView(_ display: CardDisplay) -> some View {
        #if os(iOS)
        CardWebView(
            display: display, mediaFolder: model.mediaFolder,
            zoom: dynamicTypeSize.cardZoom * Double(preferences.cardZoom) / 100,
            reviewer: ReviewerWebOptions(
                keySignatures: keySignatures, imageZoom: Double(preferences.imageZoom) / 100,
                centerVertically: preferences.centerVertically, hidesAudioButtons: model.hidesAudioButtons,
                reducedMotion: preferences.reducedMotion, command: webCommand
            ),
            onTemplateRequest: handleTemplateRequest,
            customScheduling: model.customSchedulingRequest,
            onCustomSchedule: { id, json in
                Task { await model.applyCustomSchedule(requestID: id, json: json) }
            }
        ) { event in
            switch event {
            case .tap: break
            case .rendered: cardHostUnavailable = false
            case .unavailable: cardHostUnavailable = true
            case .submitTypedAnswer: dispatch(.showAnswer)
            case .reviewer(let input): handleWebInput(input)
            case .play(let id):
                if recorder.state == .recording || recorder.state == .paused { recorder.stopRecording() }
                recorder.stopPlayback()
                if let sound = model.sound(forPlayButton: id) { audio.play([sound]) }
            case .typed(let text): typedAnswer = text
            }
        }
        .id(cardHostRevision)
        .overlay {
            if cardHostUnavailable {
                CardHostFailure {
                    cardHostUnavailable = false
                    cardHostRevision += 1
                }
            }
        }
        // VoiceOver reads the card's own content inside the web view.
        .accessibilityIdentifier("card")
        // Each side's audio plays when it appears.
        .onChange(of: SideShown(display, presentation: model.presentationNumber), initial: true) {
            if !display.isAnswer { drawing.clear() }
            if recorder.state == .recording || recorder.state == .paused { recorder.stopRecording() }
            recorder.stopPlayback()
            pendingTap?.cancel()
            pendingTap = nil
            typedAnswer = display.isAnswer ? typedAnswer : ""
            templateRecognition.stop()
            audio.play(
                model.soundsToAutoplay(),
                afterCurrent: display.isAnswer && !model.interruptsAudioWhenAnswering
            )
        }
        .onDisappear {
            audio.stop()
            templateSpeech.stop()
            templateRecognition.stop()
        }
        #else
        Text(verbatim: display.html)
        #endif
    }

    #if os(iOS)
    private func handleTemplateRequest(_ request: TemplateRequest, context: CardTemplateContext) async -> TemplateReply {
        guard context.isCurrent(), store.allowsNewProfileWork, timebox == nil,
              model.state.card?.id == context.cardID else { return .unavailable }
        switch request.command {
        case "isInNightMode": return .value(.boolean(theme != .light))
        case "isInFullscreen": return .value(.boolean(!templateFullscreen.showsTopBar))
        case "isTopbarShown": return .value(.boolean(templateFullscreen.showsTopBar))
        case "setFullscreenButtonsAndMenu": templateFullscreen = .buttonsAndMenu
        case "setFullscreenButtonsOnly": templateFullscreen = .buttonsOnly
        case "setFullscreenAllGone": templateFullscreen = .hidden
        case "showNavigationDrawer": templateMenu = .navigation
        case "showOptionsMenu": templateMenu = .options
        case "addTagToCard": dispatch(.editTags)
        case "searchCard":
            guard destinations != nil, let query = request.data else { return .unavailable }
            route = .browse(search: query)
        case "showToast":
            guard let toast = request.decoded(TemplateToast.self) else { return .unavailable }
            feedback = ReviewFeedback(
                label: Text(verbatim: toast.decodedText),
                duration: .seconds(toast.shortLength ? 2 : 4)
            )
        case "isActiveNetworkMetered":
            return .value(.boolean(await templateNetwork.isMetered()))
        default:
            if let response = templateSpeech.handle(request, prepareAudio: {
                audio.stop()
                templateRecognition.stop()
                if recorder.state == .recording || recorder.state == .paused { recorder.stopRecording() }
                recorder.stopPlayback()
            }) {
                return response
            }
            if let response = await templateRecognition.handle(
                request, context: context, allowed: allowsTemplateMicrophone,
                prepareAudio: {
                    audio.stop()
                    templateSpeech.stop()
                    if recorder.state == .recording || recorder.state == .paused { recorder.stopRecording() }
                    recorder.stopPlayback()
                }
            ) {
                return response
            }
            return await model.handleTemplate(
                request, cardID: context.cardID, isAnswer: context.isAnswer, typedAnswer: typedAnswer,
                allowsCollectionAccess: allowsTemplateCollectionAccess
            )
        }
        return .accepted
    }
    #endif

    private var reviewerActions: some View {
        ReviewerToolbar(
            model: model, preferences: preferences, showsEditNote: noteEditor != nil,
            onSettings: { showingSettings = true }, dispatch: dispatch
        )
    }
}

private struct EditedNoteTags: Identifiable {
    let id: Int64
}

private struct EditedCard: Identifiable {
    let id: Int64
}

private struct StudyNoteEditorKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (Int64) -> AnyView)? = nil
}

private extension EnvironmentValues {
    var studyNoteEditor: (@MainActor @Sendable (Int64) -> AnyView)? {
        get { self[StudyNoteEditorKey.self] }
        set { self[StudyNoteEditorKey.self] = newValue }
    }
}

/// Which side of which card is shown, to play its audio once when it appears.
private struct SideShown: Equatable {
    let cardID: Int64
    let isAnswer: Bool
    let presentation: Int

    init(_ display: CardDisplay, presentation: Int) {
        cardID = display.cardID
        isAnswer = display.isAnswer
        self.presentation = presentation
    }
}

/// The new, learning and due counts left today, in Anki's blue, red and green.
private struct StudyCountsView: View {
    let counts: StudyCounts
    @Environment(\.hayakiTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Text(counts.new, format: .number).foregroundStyle(theme.color(for: .new))
            Text(counts.learning, format: .number).foregroundStyle(theme.color(for: .learning))
            Text(counts.due, format: .number).foregroundStyle(theme.color(for: .due))
        }
        .font(.subheadline.monospacedDigit().weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(counts.new) new, \(counts.learning) learning, \(counts.due) due left",
            bundle: .module
        ))
        .accessibilityIdentifier("study-counts")
    }
}

/// Show Answer, or once the answer shows, the four ratings with the interval
/// each would give. Both fill the same strip at the bottom, so the learner's
/// thumb stays in one place.
private struct AnswerBar: View {
    let card: StudyCard
    let showingAnswer: Bool
    let isAnswering: Bool
    let minimumPress: Double
    let cooldown: Duration
    let buttonHeight: Double
    let hideHardAndEasy: Bool
    let showsIntervals: Bool
    let onShowAnswer: () -> Void
    let onShortPress: () -> Void
    let onRate: (Rating) -> Void
    @State private var lastPress: ContinuousClock.Instant?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if showingAnswer {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ratingButtons
                        }
                    } else {
                        HStack(spacing: 8) { ratingButtons }
                    }
                }
                .disabled(isAnswering)
            } else {
                ReviewerPressButton(
                    minimumPress: minimumPress,
                    action: { guarded(onShowAnswer) },
                    onShortPress: onShortPress
                ) {
                    Text("Show Answer", bundle: .module)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnswering)
                .accessibilityIdentifier("show-answer")
            }
        }
        .frame(minHeight: 60)
    }

    private var ratingButtons: some View {
        ForEach(hideHardAndEasy ? [.again, .good] : Rating.allCases, id: \.self) { rating in
            RatingButton(
                rating: rating, interval: showsIntervals ? card.intervals[rating] : nil, buttonHeight: buttonHeight
            ) {
                guarded { onRate(rating) }
            }
        }
    }

    private func guarded(_ action: () -> Void) {
        let now = ContinuousClock.now
        guard lastPress.map({ now - $0 >= cooldown }) != false else { return }
        lastPress = now
        action()
    }
}

private struct RatingButton: View {
    let rating: Rating
    let interval: String?
    let buttonHeight: Double
    let action: () -> Void
    @Environment(\.hayakiTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let interval {
                    Text(interval).font(.caption.monospacedDigit().weight(.medium))
                }
                rating.title
                    .font(.subheadline.weight(.semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
        }
        .buttonStyle(.bordered)
        .tint(theme.color(for: rating.semanticColor))
        .accessibilityLabel(rating.title)
        .accessibilityValue(Text(interval ?? ""))
        .accessibilityIdentifier("rating-\(rating)")
    }
}

private struct ReviewerPressButton<Label: View>: View {
    let minimumPress: Double
    let action: () -> Void
    let onShortPress: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var held = false

    var body: some View {
        if minimumPress == 0 {
            Button(action: action, label: label)
        } else {
            Button {
                if held { held = false } else { onShortPress() }
            } label: {
                label()
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: minimumPress).onEnded { _ in
                held = true
                action()
            })
                .accessibilityAction { action() }
        }
    }
}

/// The end of the session, or a deck with nothing left today.
private struct FinishedView: View {
    let summary: SessionSummary
    let onUnbury: () -> Void
    let onRebuild: () -> Void
    let onOptions: (() -> Void)?
    let onCustomStudy: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                switch summary.reason {
                case .dailyLimit: Text("Daily Limit Reached", bundle: .module)
                case .learningLater: Text("More Cards Later Today", bundle: .module)
                case .buried: Text("Cards Buried for Today", bundle: .module)
                case .done: Text("All Done for Today", bundle: .module)
                }
            } icon: {
                Image(systemName: summary.reason == .done ? "checkmark.circle" : "clock")
                    .foregroundStyle(summary.reason == .done ? Color.green : Color.secondary)
            }
        } description: {
            VStack(spacing: 8) {
                if summary.reviewed > 0 {
                    Text("You reviewed \(summary.reviewed) cards in this session.", bundle: .module)
                } else if summary.reason == .done {
                    if summary.isFiltered {
                        Text("This filtered deck is finished. Rebuild it to look for more cards.", bundle: .module)
                    } else {
                        Text("This deck has nothing left to study today.", bundle: .module)
                    }
                }
                if let nextLearningAt = summary.nextLearningAt {
                    let nextTime = nextLearningAt.formatted(date: .omitted, time: .shortened)
                    Text("\(summary.learningLaterToday) learning cards come due later today.", bundle: .module)
                    Text("Next learning card at \(nextTime).", bundle: .module)
                }
                if summary.dailyLimitReached || summary.hasBuried {
                    let resetTime = summary.nextDayStartsAt.formatted(date: .abbreviated, time: .shortened)
                    Text("The next study day starts at \(resetTime).", bundle: .module)
                }
                if summary.reviewed > 0, !summary.studiedToday.isEmpty {
                    Text(summary.studiedToday.replacingOccurrences(of: "\n", with: " "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            if summary.isFiltered {
                Button(action: onRebuild) {
                    Text("Rebuild Filtered Deck", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
            if summary.hasBuried {
                Button(action: onUnbury) {
                    Text("Unbury Cards", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
            if let onOptions {
                Button(action: onOptions) { Text("Deck Options", bundle: .module) }
                    .buttonStyle(.bordered)
            }
            if let onCustomStudy {
                Button(action: onCustomStudy) { Text("Custom Study", bundle: .module) }
                    .buttonStyle(.bordered)
            }
            Button(action: onDone) {
                Text("Done", bundle: .module)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

extension Rating {
    var title: Text {
        switch self {
        case .again: Text("Again", bundle: .module, comment: "Rating: the learner did not recall the card.")
        case .hard: Text("Hard", bundle: .module, comment: "Rating: recalled with serious difficulty.")
        case .good: Text("Good", bundle: .module, comment: "Rating: recalled after some thought.")
        case .easy: Text("Easy", bundle: .module, comment: "Rating: recalled at once.")
        }
    }

    /// Anki's colours for the ratings.
    var semanticColor: SemanticColor {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }

    /// As in Anki, 1 to 4 rate from the keyboard.
    var key: KeyEquivalent {
        switch self {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }
}

extension DynamicTypeSize {
    /// How much larger or smaller than at the default text size the card is
    /// drawn, so cards follow the learner's text size like the rest of the app.
    var cardZoom: CGFloat {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.36
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.6
        case .accessibility5: 3
        @unknown default: 1
        }
    }
}


private struct AutoAdvanceTask: Equatable {
    let presentation: Int
    let side: ReviewerSide
    let plan: AutoAdvancePlan
}

private struct ReviewFeedback: Equatable {
    let id = UUID()
    let label: Text
    var duration: Duration = .seconds(2)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private extension Rating {
    var reviewerCommand: ReviewerCommand {
        switch self {
        case .again: .rateAgain
        case .hard: .rateHard
        case .good: .rateGood
        case .easy: .rateEasy
        }
    }
}

#if os(iOS)
private struct ReviewerIdleTimer: ViewModifier {
    let enabled: Bool
    @State private var previous: Bool?

    func body(content: Content) -> some View {
        content
            .onChange(of: enabled, initial: true) { _, enabled in
                if previous == nil { previous = UIApplication.shared.isIdleTimerDisabled }
                UIApplication.shared.isIdleTimerDisabled = enabled || (previous ?? false)
            }
            .onDisappear {
                if let previous { UIApplication.shared.isIdleTimerDisabled = previous }
                previous = nil
            }
    }
}
#endif
