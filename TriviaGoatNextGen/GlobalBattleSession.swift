//
//  GlobalBattleSession.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Global Battle session state manager.
//  - create / join lobby
//  - observe live runtime + answers
//  - host authority for lobby + match flow
//  - uses DailyPackStore for warmed daily questions
//  - falls back safely when daily packs are unavailable
//  - pauses after repeated no-answer rounds to avoid infinite autoplay
//  - HARDENED:
//    * deterministic reveal -> advance pipeline
//    * centralized post-reveal decision engine
//    * transition guard prevents double-advance / double-reveal
//    * selected-but-unlocked answers are auto-submitted before scoring
//    * only true no-selection cases count as missed
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class GlobalBattleSession: ObservableObject {

    enum Phase: Equatable {
        case idle
        case creating
        case joining
        case lobby
        case live
        case finished
        case failed(String)
    }

    enum RoundPhase: Equatable {
        case waiting
        case answering
        case revealed
        case finished
    }

    enum FinishOutcome: Equatable {
        case none
        case regulationWin(winnerUID: String)
        case tieBreakSpeedWin(winnerUID: String)
        case winByDisqualification(winnerUID: String, disqualifiedUID: String, duringTieBreak: Bool)
        case doubleDisqualification(disqualifiedUIDs: [String], duringTieBreak: Bool)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lobby: GlobalBattleLobby? = nil
    @Published private(set) var participants: [GlobalBattleParticipant] = []
    @Published private(set) var localLobbyID: String? = nil

    @Published private(set) var runtime: GlobalBattleRuntimeState? = nil
    @Published private(set) var liveQuestion: GlobalBattleLiveQuestion? = nil
    @Published private(set) var answers: [GlobalBattleAnswerSubmission] = []

    @Published var joinCodeInput: String = ""
    @Published var statusMessage: String = "Stand by."
    @Published var isBusy: Bool = false
    @Published private(set) var isGlobalBattleEnabled: Bool = true
    @Published private(set) var globalBattleConfigReady: Bool = false

    @Published var localSelectedChoiceIndex: Int? = nil
    @Published var localLockedChoiceIndex: Int? = nil

    @Published private(set) var didLoadRemoteQuestions: Bool = false
    @Published private(set) var extraTieBreakRounds: Int = 0
    @Published private(set) var finishOutcome: FinishOutcome = .none

    private var lobbyListener: ListenerRegistration?
    private var participantsListener: ListenerRegistration?
    private var runtimeListener: ListenerRegistration?
    private var answersListener: ListenerRegistration?
    private var globalBattleConfigListener: ListenerRegistration?

    private var lastObservedAnswerRoundIndex: Int?

    private var warmedDayKey: String = ""
    private var warmedTopic: String = ""

    private var matchQuestionDeck: [TriviaQuestion] = []
    private var usedQuestionIDs: Set<String> = []

    /// Once the match starts, the deck source is frozen.
    /// This prevents fallback -> daily switching mid-match.
    private var matchDeckLocked: Bool = false
    private var lockedDeckUsesRemoteQuestions: Bool = false

    private var missedAnswerCounts: [String: Int] = [:]
    private var noAnswerRoundStreak: Int = 0
    private let missedAnswerDisqualificationThreshold: Int = 3
    private var regulationEliminatedUIDs: Set<String> = []

    private var isAwaitingPresenceCheck: Bool = false
    private var isAwaitingNextQuestion: Bool = false
    private var currentRoundArmedAt: Date? = nil
    private var currentArmedQuestionKey: String = ""

    // MARK: - Tie-break enforcement

    private var tieBreakMissedAnswerCounts: [String: Int] = [:]
    private let tieBreakDisqualificationThreshold: Int = 3

    // MARK: - In-flight authority guards

    private var revealInFlightQuestionKey: String = ""
    private var processedRevealRoundKey: String = ""
    private var finishInFlightRoundIndex: Int? = nil

    // MARK: - Suspense / Reveal Safety

    private let minimumRevealArmingDelay: TimeInterval = 5.35
    private let answerSettleDelayNanoseconds: UInt64 = 800_000_000
    private let lateAnswerGraceNanoseconds: UInt64 = 650_000_000
    private let secondLateAnswerGraceNanoseconds: UInt64 = 450_000_000

    // MARK: - Match pacing

    private let firstRoundLeadInNanoseconds: UInt64 = 7_300_000_000
    private let standardRoundLeadInNanoseconds: UInt64 = 1_450_000_000

    private let finalRoundLeadInNanoseconds: UInt64 = 6_600_000_000
    private let revealHoldNanoseconds: UInt64 = 2_650_000_000
    private let betweenRoundsDelayNanoseconds: UInt64 = 2_450_000_000
    private let finalRevealHoldNanoseconds: UInt64 = 4_900_000_000
    private let tieBreakDelayNanoseconds: UInt64 = 3_000_000_000

    // MARK: - Tie-break fairness

    private let tieBreakFairnessWindow: TimeInterval = 0.45

    init() {
        startGlobalBattleAvailabilityListener()
    }

    deinit {
        lobbyListener?.remove()
        participantsListener?.remove()
        runtimeListener?.remove()
        answersListener?.remove()
        globalBattleConfigListener?.remove()
    }

    // MARK: - Public API

    func reset() {
        resetEntryState()

        joinCodeInput = ""
        localSelectedChoiceIndex = nil
        localLockedChoiceIndex = nil
        finishOutcome = .none

        isBusy = false
        phase = .idle
        statusMessage = "Stand by."
    }

    func createLobby(
        hostUID: String,
        displayName: String,
        topic: String,
        dayKey: String,
        maxPlayers: Int = 20,
        questionCount: Int = 10
    ) {
        guard !isBusy else { return }
        guard isGlobalBattleEnabled else {
            phase = .failed("Global Battle is currently disabled.")
            statusMessage = "Global Battle is currently disabled."
            return
        }

        let cleanedHostUID = hostUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHostUID.isEmpty else {
            phase = .failed("Missing host UID.")
            statusMessage = "Missing host UID."
            return
        }

        let cleanedName = sanitizedDisplayName(displayName)
        let cleanedTopic = sanitizedTopic(topic)
        let cleanedDayKey = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedDayKey.isEmpty else {
            phase = .failed("Missing day key.")
            statusMessage = "Missing day key."
            return
        }

        let battleCode = makeBattleCode()

        resetEntryState()
        warmedDayKey = cleanedDayKey
        warmedTopic = cleanedTopic
        finishOutcome = .none

        Task { [weak self] in
            guard let self else { return }
            await self.preheatQuestionsForLobby(
                dayKey: cleanedDayKey,
                topic: cleanedTopic,
                questionCount: questionCount,
                forceFetchIfInsufficient: true
            )
        }

        isBusy = true
        phase = .creating
        statusMessage = "Creating global lobby…"

        Task {
            do {
                let lobbyID = try await FirestoreService.shared.createGlobalBattleLobby(
                    code: battleCode,
                    hostUID: cleanedHostUID,
                    topic: cleanedTopic,
                    dayKey: cleanedDayKey,
                    maxPlayers: max(2, min(maxPlayers, 50)),
                    questionCount: max(1, min(questionCount, 50))
                )

                let hostParticipant = GlobalBattleParticipant(
                    id: cleanedHostUID,
                    uid: cleanedHostUID,
                    displayName: cleanedName,
                    score: 0,
                    isHost: true,
                    joinedAt: Date()
                )

                try await FirestoreService.shared.joinGlobalBattleLobby(
                    lobbyId: lobbyID,
                    participant: hostParticipant
                )

                localLobbyID = lobbyID
                joinCodeInput = battleCode
                extraTieBreakRounds = 0

                attachLobbyListener(lobbyId: lobbyID)
                attachParticipantsListener(lobbyId: lobbyID)
                attachRuntimeListener(lobbyId: lobbyID)

                isBusy = false
                phase = .lobby
                statusMessage = "Lobby created."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func joinLobby(
        code: String,
        uid: String,
        displayName: String
    ) {
        guard !isBusy else { return }
        guard isGlobalBattleEnabled else {
            phase = .failed("Global Battle is currently disabled.")
            statusMessage = "Global Battle is currently disabled."
            return
        }

        let cleanedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !cleanedCode.isEmpty else {
            phase = .failed("Enter a lobby code.")
            statusMessage = "Enter a lobby code."
            return
        }

        let cleanedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else {
            phase = .failed("Missing player UID.")
            statusMessage = "Missing player UID."
            return
        }

        resetEntryState()
        finishOutcome = .none

        isBusy = true
        phase = .joining
        statusMessage = "Joining lobby…"

        Task {
            do {
                guard
                    let foundLobby = try await FirestoreService.shared.fetchGlobalBattleLobby(code: cleanedCode),
                    let lobbyID = foundLobby.id,
                    !lobbyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    isBusy = false
                    phase = .failed("Lobby not found.")
                    statusMessage = "Lobby not found."
                    return
                }

                let lobbyStatus = foundLobby.status
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if lobbyStatus == "finished" {
                    isBusy = false
                    phase = .failed("Lobby has already finished.")
                    statusMessage = "Lobby unavailable."
                    return
                }

                let participant = GlobalBattleParticipant(
                    id: cleanedUID,
                    uid: cleanedUID,
                    displayName: sanitizedDisplayName(displayName),
                    score: 0,
                    isHost: false,
                    joinedAt: Date()
                )

                try await FirestoreService.shared.joinGlobalBattleLobby(
                    lobbyId: lobbyID,
                    participant: participant
                )

                localLobbyID = lobbyID
                joinCodeInput = cleanedCode
                extraTieBreakRounds = 0

                warmedDayKey = foundLobby.dayKey
                warmedTopic = foundLobby.topic

                Task {
                    await preheatQuestionsForLobby(
                        dayKey: foundLobby.dayKey,
                        topic: foundLobby.topic,
                        questionCount: foundLobby.questionCount,
                        forceFetchIfInsufficient: true
                    )
                }

                attachLobbyListener(lobbyId: lobbyID)
                attachParticipantsListener(lobbyId: lobbyID)
                attachRuntimeListener(lobbyId: lobbyID)

                isBusy = false

                if lobbyStatus == "live" {
                    phase = .live
                    statusMessage = "Match live."
                } else {
                    phase = .lobby
                    statusMessage = "Joined lobby."
                }
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func leaveLobby(currentUID: String?) {
        let uid = (currentUID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lobbyID = (localLobbyID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !uid.isEmpty, !lobbyID.isEmpty else {
            reset()
            statusMessage = "Left lobby."
            return
        }

        guard !isBusy else { return }

        isBusy = true
        statusMessage = "Leaving lobby…"

        Task {
            do {
                try await FirestoreService.shared.removeGlobalBattleParticipant(
                    lobbyId: lobbyID,
                    uid: uid
                )

                reset()
                statusMessage = "Left lobby."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func leaveMatch(currentUID: String?) {
        let uid = (currentUID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lobbyID = (localLobbyID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !uid.isEmpty, !lobbyID.isEmpty else {
            reset()
            statusMessage = "Left match."
            return
        }

        guard !isBusy else { return }

        isBusy = true
        statusMessage = "Leaving match…"

        Task {
            do {
                try await FirestoreService.shared.removeGlobalBattleParticipant(
                    lobbyId: lobbyID,
                    uid: uid
                )

                reset()
                statusMessage = "Left match."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func startMatchIfHost(currentUID: String) {
        guard !isBusy else { return }
        guard let lobby, let lobbyID = lobby.id, lobby.hostUID == currentUID else { return }

        guard roundPhase == .waiting || runtime == nil else {
            statusMessage = "Match already in progress."
            return
        }

        guard playerCount >= minimumPlayersToStart else {
            statusMessage = "Need at least \(minimumPlayersToStart) pilots to start."
            return
        }

        debugRuntimeSnapshot(prefix: "startMatchIfHost() BEFORE")

        isBusy = true
        phase = .live
        statusMessage = "Launching match…"

        localSelectedChoiceIndex = nil
        localLockedChoiceIndex = nil
        answers = []

        usedQuestionIDs = []
        extraTieBreakRounds = 0
        missedAnswerCounts = [:]
        noAnswerRoundStreak = 0
        isAwaitingPresenceCheck = false
        isAwaitingNextQuestion = false
        currentRoundArmedAt = nil
        currentArmedQuestionKey = ""
        revealInFlightQuestionKey = ""
        processedRevealRoundKey = ""
        finishInFlightRoundIndex = nil
        tieBreakMissedAnswerCounts = [:]
        finishOutcome = .none
        regulationEliminatedUIDs = []

        Task {
            await prepareLockedDeckIfNeeded(questionCount: lobby.questionCount)

            do {
                try await FirestoreService.shared.stageGlobalBattleRoundWaiting(
                    lobbyId: lobbyID,
                    roundIndex: 1,
                    extraTieBreakRounds: 0
                )

                debugRuntimeSnapshot(prefix: "startMatchIfHost() AFTER STAGE")

                phase = .live
                statusMessage = "Battle live."

                guard let firstQuestion = questionFor(round: 1) else {
                    isBusy = false
                    phase = .failed("No questions available.")
                    statusMessage = "No questions available."
                    return
                }

                try? await Task.sleep(nanoseconds: firstRoundLeadInNanoseconds)

                beginHostedRound(
                    currentUID: currentUID,
                    question: firstQuestion,
                    questionKey: questionKey(for: 1, tieBreak: false, question: firstQuestion),
                    durationSeconds: 14
                )
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func endMatchIfHost(currentUID: String) {
        guard !isBusy else { return }
        guard let lobby, let lobbyID = lobby.id, lobby.hostUID == currentUID else { return }

        isBusy = true
        statusMessage = "Closing match…"
        finishOutcome = .none

        Task {
            do {
                try await FirestoreService.shared.finishGlobalBattleRuntime(
                    lobbyId: lobbyID,
                    finish: GlobalBattleRuntimeFinishState(
                        type: "manual_close",
                        winnerUID: nil,
                        disqualifiedUID: nil,
                        disqualifiedUIDs: [],
                        duringTieBreak: false
                    )
                )
                try await FirestoreService.shared.updateGlobalBattleStatus(
                    lobbyId: lobbyID,
                    status: "finished",
                    roundIndex: lobby.roundIndex
                )

                isBusy = false
                phase = .finished
                statusMessage = "Match closed."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func resumeAfterPresenceCheckIfHost(currentUID: String) {
        guard isHost(currentUID: currentUID) else { return }
        guard isAwaitingPresenceCheck else { return }
        guard let runtime else { return }

        missedAnswerCounts = [:]
        noAnswerRoundStreak = 0
        isAwaitingPresenceCheck = false
        isAwaitingNextQuestion = false
        statusMessage = "Resuming match…"

        let nextRound = max(1, runtime.roundIndex + 1)

        Task {
            do {
                guard let lobbyID = localLobbyID else { return }

                try await FirestoreService.shared.stageGlobalBattleRoundWaiting(
                    lobbyId: lobbyID,
                    roundIndex: nextRound,
                    extraTieBreakRounds: extraTieBreakRounds
                )

                guard let nextQuestion = questionFor(round: nextRound) else {
                    phase = .finished
                    statusMessage = "Match ended."
                    isBusy = false
                    return
                }

                let isTieBreak = nextRound > baseQuestionCount
                let leadIn = (!isTieBreak && nextRound == baseQuestionCount)
                    ? finalRoundLeadInNanoseconds
                    : standardRoundLeadInNanoseconds

                try? await Task.sleep(nanoseconds: leadIn)

                beginHostedRound(
                    currentUID: currentUID,
                    question: nextQuestion,
                    questionKey: questionKey(
                        for: nextRound,
                        tieBreak: isTieBreak,
                        question: nextQuestion
                    ),
                    durationSeconds: isTieBreak ? 10 : 14
                )
            } catch {
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
                isBusy = false
            }
        }
    }

    func startGlobalBattleAvailabilityListener() {
        globalBattleConfigListener?.remove()

        globalBattleConfigReady = false
        isGlobalBattleEnabled = true

        globalBattleConfigListener = FirestoreService.shared.listenToPlatformConfigSnapshot { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let snapshot):
                    if let snapshot {
                        let enabled = snapshot.globalBattleEnabled
                        self.isGlobalBattleEnabled = enabled
                        self.globalBattleConfigReady = true
                        self.debugLog("platformSettings global_battle_live=\(enabled)")
                    } else {
                        self.isGlobalBattleEnabled = true
                        self.globalBattleConfigReady = true
                        self.debugLog("platformSettings missing -> default enabled")
                    }

                case .failure(let error):
                    self.isGlobalBattleEnabled = true
                    self.globalBattleConfigReady = true
                    self.debugLog("platformSettings listener failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Runtime / Match Helpers

    func submitAnswerIfPossible(
        currentUID: String,
        displayName: String,
        choiceIndex: Int
    ) {
        guard !currentUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let lobbyID = localLobbyID, !lobbyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let runtime else { return }
        guard roundPhase == .answering else { return }
        guard liveQuestion != nil else { return }
        guard localLockedChoiceIndex == nil else { return }
        guard !didSubmitAnswer(currentUID: currentUID) else { return }
        guard choiceIndex >= 0, choiceIndex < (liveQuestion?.choices.count ?? 0) else { return }

        localSelectedChoiceIndex = choiceIndex
        localLockedChoiceIndex = choiceIndex
        statusMessage = "Answer locked."

        let submission = GlobalBattleAnswerSubmission(
            id: currentUID,
            uid: currentUID,
            displayName: sanitizedDisplayName(displayName),
            roundIndex: max(1, runtime.roundIndex),
            choiceIndex: choiceIndex,
            isCorrect: nil,
            submittedAt: Date()
        )

        Task {
            do {
                try await FirestoreService.shared.submitGlobalBattleAnswer(
                    lobbyId: lobbyID,
                    submission: submission
                )
            } catch {
                self.phase = .failed(error.localizedDescription)
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func submitTieBreakTapIfPossible(
        currentUID: String,
        displayName: String,
        choiceIndex: Int
    ) {
        guard isTieBreakRound else { return }
        submitAnswerIfPossible(
            currentUID: currentUID,
            displayName: displayName,
            choiceIndex: choiceIndex
        )
    }

    private func autoSubmitSelectedAnswerIfNeeded(
        lobbyId: String,
        roundIndex: Int
    ) async -> GlobalBattleAnswerSubmission? {
        guard let runtime else { return nil }
        guard let liveQuestion else { return nil }

        let currentUID = Auth.auth().currentUser?.uid
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !currentUID.isEmpty else { return nil }
        guard let localLobbyID, localLobbyID == lobbyId else { return nil }
        guard max(1, runtime.roundIndex) == roundIndex else { return nil }
        guard roundPhase == .answering else { return nil }

        // 🔥 CRITICAL FIX:
        // Treat either localLockedChoiceIndex OR localSelectedChoiceIndex as answer intent.
        let intendedChoiceIndex = localLockedChoiceIndex ?? localSelectedChoiceIndex
        guard let intendedChoiceIndex else { return nil }

        guard intendedChoiceIndex >= 0, intendedChoiceIndex < liveQuestion.choices.count else { return nil }

        // If Firestore already has this player's answer, do not duplicate it.
        guard !didSubmitAnswer(currentUID: currentUID) else {
            return answers.first(where: { $0.uid == currentUID })
        }

        let displayName = participants.first(where: { $0.uid == currentUID })?.displayName
            ?? Auth.auth().currentUser?.displayName
            ?? "PILOT"

        let submission = GlobalBattleAnswerSubmission(
            id: currentUID,
            uid: currentUID,
            displayName: sanitizedDisplayName(displayName),
            roundIndex: roundIndex,
            choiceIndex: intendedChoiceIndex,
            isCorrect: nil,
            submittedAt: Date()
        )

        // Preserve the chosen answer as locked locally.
        localLockedChoiceIndex = intendedChoiceIndex
        statusMessage = "Answer auto-locked."

        debugLog("auto-submit fallback firing uid=\(currentUID) round=\(roundIndex) choice=\(intendedChoiceIndex)")

        do {
            try await FirestoreService.shared.submitGlobalBattleAnswer(
                lobbyId: lobbyId,
                submission: submission
            )
        } catch {
            // 🔥 IMPORTANT:
            // Even if network submit fails, we still return the local intended answer
            // so scoring + strike logic treats selected as answered.
            debugLog("auto-submit fallback submit failed, using local fallback for scoring: \(error.localizedDescription)")
        }

        return submission
    }

    func beginHostedRound(
        currentUID: String,
        question: TriviaQuestion,
        questionKey: String,
        durationSeconds: Int = 14
    ) {
        guard isHost(currentUID: currentUID) else { return }
        guard let lobbyID = localLobbyID else { return }
        guard let lobby else { return }
        guard !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !question.choices.isEmpty else { return }

        debugLog("beginHostedRound() requested")
        debugLog("hostUID: \(currentUID)")
        debugLog("questionKey: \(questionKey)")
        debugLog("questionPrompt: \(question.prompt)")
        debugLog("durationSeconds: \(durationSeconds)")
        debugRuntimeSnapshot(prefix: "beginHostedRound() BEFORE")

        isBusy = true
        statusMessage = "Publishing round…"

        markQuestionUsed(question)

        let payload = GlobalBattleLiveQuestion(
            key: questionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? UUID().uuidString
                : questionKey.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: question.prompt,
            choices: question.choices,
            correctIndex: question.correctIndex
        )

        let targetRound = max(1, lobby.roundIndex)
        localSelectedChoiceIndex = nil
        localLockedChoiceIndex = nil
        answers = []
        currentRoundArmedAt = nil
        currentArmedQuestionKey = ""
        revealInFlightQuestionKey = ""
        processedRevealRoundKey = ""
        isAwaitingNextQuestion = false

        Task {
            do {
                try await FirestoreService.shared.clearGlobalBattleAnswers(
                    lobbyId: lobbyID,
                    roundIndex: targetRound
                )

                try await FirestoreService.shared.publishGlobalBattleRound(
                    lobbyId: lobbyID,
                    roundIndex: targetRound,
                    question: payload,
                    roundDurationSeconds: durationSeconds,
                    extraTieBreakRounds: extraTieBreakRounds
                )

                try await FirestoreService.shared.markUsedQuestionKeys(
                    lobbyId: lobbyID,
                    keys: [payload.key]
                )

                debugRuntimeSnapshot(prefix: "beginHostedRound() AFTER")

                isBusy = false
                phase = .live
                statusMessage = "Round live."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func revealCurrentRoundIfHost(currentUID: String) -> Bool {
        guard isHost(currentUID: currentUID) else { return false }
        guard let lobbyID = localLobbyID else { return false }
        guard let runtime else { return false }
        guard !isAwaitingNextQuestion else {
            debugLog("reveal blocked: awaiting next question transition")
            return false
        }
        guard roundPhase == .answering else { return false }
        guard let correctIndex = runtime.question?.correctIndex ?? liveQuestion?.correctIndex else { return false }

        let activeQuestionKey = runtime.question?.key ?? liveQuestion?.key ?? ""
        let revealRoundKey = "\(runtime.roundIndex)|\(activeQuestionKey)"

        guard !activeQuestionKey.isEmpty else {
            debugLog("reveal blocked: missing active question key")
            return false
        }

        guard revealInFlightQuestionKey != activeQuestionKey else {
            debugLog("reveal blocked: already in flight for key \(activeQuestionKey)")
            return false
        }

        guard processedRevealRoundKey != revealRoundKey else {
            debugLog("reveal blocked: round already processed \(revealRoundKey)")
            return false
        }

        if currentArmedQuestionKey != activeQuestionKey {
            debugLog("⚠️ arming mismatch — recovering using runtime key")
            currentArmedQuestionKey = activeQuestionKey
            currentRoundArmedAt = currentRoundArmedAt ?? Date()
        }

        guard let armedAt = currentRoundArmedAt else {
            debugLog("reveal blocked: armedAt missing for key \(activeQuestionKey)")
            return false
        }

        let armedElapsed = Date().timeIntervalSince(armedAt)
        guard armedElapsed >= minimumRevealArmingDelay else {
            debugLog("reveal blocked: armed too recently (\(armedElapsed)s) for key \(activeQuestionKey)")
            return false
        }

        let currentRoster = participants
        let localUID = Auth.auth().currentUser?.uid
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localChoice = localLockedChoiceIndex ?? localSelectedChoiceIndex

        let answeredUIDs = Set(
            answers.map { $0.uid.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        var representedAnswerCount = answeredUIDs.count
        if !localUID.isEmpty,
           localChoice != nil,
           !answeredUIDs.contains(localUID) {
            representedAnswerCount += 1
        }

        let requiredAnswerCount = max(1, currentRoster.count)
        let deadlinePassed = (runtime.deadlineAt ?? deadlineAt ?? .distantPast) <= Date()

        if representedAnswerCount < requiredAnswerCount && !deadlinePassed {
            debugLog(
                "reveal blocked: waiting for all answers \(representedAnswerCount)/\(requiredAnswerCount)"
            )
            return false
        }

        revealInFlightQuestionKey = activeQuestionKey

        debugLog("revealCurrentRoundIfHost() requested by \(currentUID)")
        debugRuntimeSnapshot(prefix: "revealCurrentRoundIfHost() BEFORE")

        isBusy = true
        statusMessage = "Revealing answers…"

        Task {
            defer {
                if self.revealInFlightQuestionKey == activeQuestionKey {
                    self.revealInFlightQuestionKey = ""
                }
            }

            do {
                let currentRoster = participants
                let roundToScore = runtime.roundIndex
                let expectedCount = playerCount

                let localAutoLockedSubmission = await autoSubmitSelectedAnswerIfNeeded(
                    lobbyId: lobbyID,
                    roundIndex: roundToScore
                )

                let preRevealAnswers = try await fetchSettledAnswersForReveal(
                    lobbyId: lobbyID,
                    roundIndex: roundToScore,
                    expectedCount: expectedCount
                )

                debugLog(
                    "reveal scoring snapshot round=\(roundToScore) settledAnswers=\(preRevealAnswers.count)/\(expectedCount)"
                )

                try await FirestoreService.shared.revealGlobalBattleRound(
                    lobbyId: lobbyID,
                    roundIndex: roundToScore
                )

                self.processedRevealRoundKey = revealRoundKey

                let fetchedAnswers = try await fetchPostRevealGraceAnswers(
                    lobbyId: lobbyID,
                    roundIndex: roundToScore,
                    existing: preRevealAnswers
                )

                var effectiveAnswers = mergedUniqueAnswersByUID(
                    fetchedAnswers + [localAutoLockedSubmission].compactMap { $0 }
                )

                let localUID = Auth.auth().currentUser?.uid
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let localChoice = localLockedChoiceIndex ?? localSelectedChoiceIndex

                if !localUID.isEmpty,
                   let localChoice,
                   !effectiveAnswers.contains(where: { $0.uid == localUID }) {
                    let displayName = participants.first(where: { $0.uid == localUID })?.displayName
                        ?? Auth.auth().currentUser?.displayName
                        ?? "PILOT"

                    let forcedLocalAnswer = GlobalBattleAnswerSubmission(
                        id: localUID,
                        uid: localUID,
                        displayName: sanitizedDisplayName(displayName),
                        roundIndex: max(1, runtime.roundIndex),
                        choiceIndex: localChoice,
                        isCorrect: nil,
                        submittedAt: Date()
                    )

                    effectiveAnswers.append(forcedLocalAnswer)

                    debugLog("🔥 FORCED LOCAL ANSWER INTO REVEAL uid=\(localUID) choice=\(localChoice)")
                }

                effectiveAnswers = mergedUniqueAnswersByUID(effectiveAnswers)
                answers = effectiveAnswers

                let locallyRepresentedUID = Auth.auth().currentUser?.uid
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !locallyRepresentedUID.isEmpty,
                   let localAnswer = effectiveAnswers.first(where: { $0.uid == locallyRepresentedUID }) {
                    debugLog("local effective answer enforced uid=\(locallyRepresentedUID) choice=\(localAnswer.choiceIndex)")
                }

                let isTieBreakScoringRound = roundToScore > baseQuestionCount

                if isTieBreakScoringRound {
                    // Tie-break rounds must NOT mutate regulation strike state.
                    // Tie-break miss / DQ logic is handled later in advanceGameFlowAfterReveal().
                    noAnswerRoundStreak = 0
                } else {
                    let answeredUIDs = Set(effectiveAnswers.map(\.uid))
                    let trueNoAnswer = currentRoster.allSatisfy { !answeredUIDs.contains($0.uid) }

                    if trueNoAnswer {
                        noAnswerRoundStreak += 1
                        debugLog("no-answer round streak: \(noAnswerRoundStreak)")
                    } else {
                        noAnswerRoundStreak = 0
                    }

                    registerMissedAnswers(
                        roster: currentRoster,
                        answers: effectiveAnswers
                    )

                    // Local selected / forced-selected answer must never take a regulation miss strike.
                    if !localUID.isEmpty,
                       effectiveAnswers.contains(where: { $0.uid == localUID }) {
                        missedAnswerCounts[localUID] = 0
                        debugLog("local selection protected from strike uid=\(localUID)")
                    }
                }

                for answer in effectiveAnswers {
                    let ts = normalizedSubmittedAt(for: answer)?.timeIntervalSince1970 ?? 0
                    debugLog("answer uid=\(answer.uid) choice=\(answer.choiceIndex) submittedAt=\(ts)")
                }

                var scoredRoster: [GlobalBattleParticipant] = []

                for player in currentRoster {
                    let submitted = effectiveAnswers.first(where: { $0.uid == player.uid })
                    let isCorrect = submitted?.choiceIndex == correctIndex
                    let newScore = player.score + (isCorrect ? 10 : 0)

                    debugLog(
                        "score check uid=\(player.uid) submitted=\(submitted?.choiceIndex.description ?? "nil") correctIndex=\(correctIndex) oldScore=\(player.score) newScore=\(newScore)"
                    )

                    if isCorrect {
                        try await FirestoreService.shared.incrementGlobalBattleParticipantScore(
                            lobbyId: lobbyID,
                            uid: player.uid,
                            by: 10
                        )
                    }

                    var updated = player
                    updated.score = newScore
                    scoredRoster.append(updated)
                }

                try await advanceGameFlowAfterReveal(
                    lobbyId: lobbyID,
                    currentUID: currentUID,
                    roundToScore: roundToScore,
                    correctIndex: correctIndex,
                    rosterAtReveal: currentRoster,
                    currentAnswers: effectiveAnswers,
                    scoredRoster: scoredRoster
                )
            } catch {
                if self.processedRevealRoundKey == revealRoundKey {
                    self.processedRevealRoundKey = ""
                }
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }

        return true
    }

    func advanceToNextRoundIfHost(currentUID: String) {
        guard isHost(currentUID: currentUID) else { return }
        guard let lobby, let lobbyID = lobby.id else { return }

        let nextRound = max(1, (runtime?.roundIndex ?? lobby.roundIndex) + 1)

        debugLog("advanceToNextRoundIfHost() requested by \(currentUID)")
        debugRuntimeSnapshot(prefix: "advanceToNextRoundIfHost() BEFORE")

        isBusy = true
        statusMessage = "Advancing round…"

        localSelectedChoiceIndex = nil
        localLockedChoiceIndex = nil
        answers = []

        Task {
            do {
                try await FirestoreService.shared.stageGlobalBattleRoundWaiting(
                    lobbyId: lobbyID,
                    roundIndex: nextRound,
                    extraTieBreakRounds: extraTieBreakRounds
                )

                debugRuntimeSnapshot(prefix: "advanceToNextRoundIfHost() AFTER")

                isBusy = false
                statusMessage = "Ready for next round."
            } catch {
                isBusy = false
                phase = .failed(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Derived State

    var lobbyCode: String {
        lobby?.code ?? joinCodeInput
    }

    var shouldBlockGlobalBattleEntry: Bool {
        globalBattleConfigReady && !isGlobalBattleEnabled
    }

    var hostUID: String {
        lobby?.hostUID ?? ""
    }

    var playerCount: Int {
        participants.count
    }

    var maxPlayers: Int {
        max(2, lobby?.maxPlayers ?? 2)
    }

    var baseQuestionCount: Int {
        max(1, lobby?.questionCount ?? fallbackQuestionPack.count)
    }

    var displayedQuestionCount: Int {
        let liveRound = max(1, runtime?.roundIndex ?? lobby?.roundIndex ?? 1)
        return max(baseQuestionCount + extraTieBreakRounds, liveRound)
    }

    var currentRoundNumber: Int {
        max(1, runtime?.roundIndex ?? lobby?.roundIndex ?? 1)
    }

    var isFinalRegulationRound: Bool {
        currentRoundNumber == baseQuestionCount && !isTieBreakRound
    }

    var isPausedForPresenceCheck: Bool {
        isAwaitingPresenceCheck
    }

    var activeQuestionSourceLabel: String {
        if matchDeckLocked {
            return lockedDeckUsesRemoteQuestions ? "DAILY PACK" : "FALLBACK"
        }
        return didLoadRemoteQuestions ? "DAILY PACK" : "FALLBACK"
    }

    var isTieBreakRound: Bool {
        let round = max(1, runtime?.roundIndex ?? lobby?.roundIndex ?? 1)
        return round > baseQuestionCount
    }

    var finishedWinnerUID: String? {
        switch finishOutcome {
        case .regulationWin(let winnerUID):
            return winnerUID
        case .tieBreakSpeedWin(let winnerUID):
            return winnerUID
        case .winByDisqualification(let winnerUID, _, _):
            return winnerUID
        case .doubleDisqualification, .none:
            return nil
        }
    }

    var disqualifiedUIDs: [String] {
        switch finishOutcome {
        case .winByDisqualification(_, let disqualifiedUID, _):
            return [disqualifiedUID]
        case .doubleDisqualification(let disqualifiedUIDs, _):
            return disqualifiedUIDs
        case .regulationWin, .tieBreakSpeedWin, .none:
            return []
        }
    }

    var endedByDisqualification: Bool {
        switch finishOutcome {
        case .winByDisqualification, .doubleDisqualification:
            return true
        case .regulationWin, .tieBreakSpeedWin, .none:
            return false
        }
    }

    var endedByTieBreakSpeed: Bool {
        if case .tieBreakSpeedWin = finishOutcome { return true }
        return false
    }

    var isDoubleDisqualificationFinish: Bool {
        if case .doubleDisqualification = finishOutcome { return true }
        return false
    }

    var finishOccurredDuringTieBreak: Bool {
        switch finishOutcome {
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak
        case .doubleDisqualification(_, let duringTieBreak):
            return duringTieBreak
        case .tieBreakSpeedWin:
            return true
        case .regulationWin, .none:
            return false
        }
    }

    func displayName(for uid: String) -> String {
        participantDisplayName(for: uid, roster: participants)
    }

    func isHost(currentUID: String?) -> Bool {
        let cleanedUID = (currentUID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else { return false }

        if cleanedUID == hostUID { return true }
        if participants.contains(where: { $0.uid == cleanedUID && $0.isHost }) { return true }
        return false
    }

    var canStartMatch: Bool {
        guard let lobby else { return false }

        let status = lobby.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !runtimeIndicatesActiveMatch else { return false }
        return status == "lobby" || status == "waiting"
    }

    var isLobbyPhase: Bool {
        switch phase {
        case .lobby, .creating, .joining:
            return true
        default:
            return false
        }
    }

    var isLivePhase: Bool {
        if case .live = phase { return true }
        return false
    }

    var currentRoundIndexText: String {
        let idx = max(1, runtime?.roundIndex ?? lobby?.roundIndex ?? 1)
        return "QUESTION \(idx)"
    }

    var roundPhase: RoundPhase {
        let raw = runtime?.phase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "waiting"

        switch raw {
        case "answering":
            return .answering
        case "revealed":
            return .revealed
        case "finished":
            return .finished
        default:
            return .waiting
        }
    }

    var runtimeIndicatesActiveMatch: Bool {
        switch roundPhase {
        case .answering, .revealed, .finished:
            return true
        case .waiting:
            return false
        }
    }

    var roundDurationSeconds: Int {
        max(3, runtime?.roundDurationSeconds ?? 10)
    }

    var deadlineAt: Date? {
        runtime?.deadlineAt
    }

    var revealedAt: Date? {
        runtime?.revealedAt
    }

    var currentCorrectIndex: Int? {
        liveQuestion?.correctIndex
    }

    var hasLockedAnswer: Bool {
        localLockedChoiceIndex != nil
    }

    var minimumPlayersToStart: Int {
        2
    }

    var canHostStartMatch: Bool {
        guard canStartMatch else { return false }
        return playerCount >= minimumPlayersToStart
    }

    func didSubmitAnswer(currentUID: String?) -> Bool {
        guard let currentUID, !currentUID.isEmpty else { return false }
        return answers.contains(where: { $0.uid == currentUID })
    }

    func submittedChoiceIndex(for currentUID: String?) -> Int? {
        guard let currentUID, !currentUID.isEmpty else { return localLockedChoiceIndex }
        return answers.first(where: { $0.uid == currentUID })?.choiceIndex ?? localLockedChoiceIndex
    }

    func submittedAnswerCount() -> Int {
        answers.count
    }

    func missedAnswerStrikeCountForDisplay(uid: String) -> Int {
        let cleanedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else { return 0 }

        if isTieBreakRound {
            return tieBreakMissedAnswerCounts[cleanedUID] ?? 0
        }

        return missedAnswerCounts[cleanedUID] ?? 0
    }

    func isAtRiskOfDisqualification(uid: String) -> Bool {
        let strikes = missedAnswerStrikeCountForDisplay(uid: uid)
        let threshold = isTieBreakRound
            ? tieBreakDisqualificationThreshold
            : missedAnswerDisqualificationThreshold

        return strikes == max(0, threshold - 1)
    }

    private func resetEntryState() {
        stopListening()

        lobby = nil
        participants = []
        runtime = nil
        liveQuestion = nil
        answers = []
        localLobbyID = nil
        localSelectedChoiceIndex = nil
        localLockedChoiceIndex = nil
        lastObservedAnswerRoundIndex = nil

        didLoadRemoteQuestions = false
        extraTieBreakRounds = 0
        warmedDayKey = ""
        warmedTopic = ""

        matchQuestionDeck = []
        usedQuestionIDs = []
        matchDeckLocked = false
        lockedDeckUsesRemoteQuestions = false
        missedAnswerCounts = [:]
        noAnswerRoundStreak = 0
        isAwaitingPresenceCheck = false
        isAwaitingNextQuestion = false
        currentRoundArmedAt = nil
        currentArmedQuestionKey = ""
        revealInFlightQuestionKey = ""
        processedRevealRoundKey = ""
        regulationEliminatedUIDs = []
        finishInFlightRoundIndex = nil
        tieBreakMissedAnswerCounts = [:]
        finishOutcome = .none

        if globalBattleConfigListener == nil {
            startGlobalBattleAvailabilityListener()
        }
    }

    // MARK: - Private Helpers

    private func stopListening() {
        lobbyListener?.remove()
        lobbyListener = nil

        participantsListener?.remove()
        participantsListener = nil

        runtimeListener?.remove()
        runtimeListener = nil

        answersListener?.remove()
        answersListener = nil

        globalBattleConfigListener?.remove()
        globalBattleConfigListener = nil
    }

    private func attachLobbyListener(lobbyId: String) {
        lobbyListener?.remove()

        lobbyListener = FirestoreService.shared.listenToGlobalBattleLobby(lobbyId: lobbyId) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let updatedLobby):
                    self.lobby = updatedLobby

                    let status = updatedLobby.status
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    if self.warmedDayKey != updatedLobby.dayKey || self.warmedTopic != updatedLobby.topic {
                        self.warmedDayKey = updatedLobby.dayKey
                        self.warmedTopic = updatedLobby.topic

                        if !self.matchDeckLocked {
                            Task {
                                await self.preheatQuestionsForLobby(
                                    dayKey: updatedLobby.dayKey,
                                    topic: updatedLobby.topic,
                                    questionCount: updatedLobby.questionCount,
                                    forceFetchIfInsufficient: true
                                )
                            }
                        }
                    }

                    switch status {
                    case "live":
                        self.phase = .live

                        if self.roundPhase == .answering {
                            self.statusMessage = "Answer now."
                        } else if self.roundPhase == .revealed {
                            self.statusMessage = "Answers revealed."
                        } else if self.roundPhase == .finished {
                            self.statusMessage = "Match finished."
                        } else {
                            self.statusMessage = self.isAwaitingPresenceCheck
                                ? "Paused — are players still here?"
                                : "Waiting for host."
                        }

                    case "finished":
                        self.phase = .finished

                        if self.finishOutcome == .none {
                            self.rebuildFinishOutcomeFromCurrentState()
                        }

                        self.statusMessage = "Match finished."

                    case "lobby", "waiting":
                        if self.runtimeIndicatesActiveMatch {
                            break
                        }

                        self.phase = .lobby

                        if self.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            self.statusMessage == "Creating global lobby…" ||
                            self.statusMessage == "Joining lobby…" {
                            self.statusMessage = "Lobby ready."
                        }

                    default:
                        break
                    }

                case .failure(let error):
                    self.isBusy = false
                    self.phase = .failed(error.localizedDescription)
                    self.statusMessage = "Lobby listener failed."
                }
            }
        }
    }

    private func attachParticipantsListener(lobbyId: String) {
        participantsListener?.remove()

        participantsListener = FirestoreService.shared.listenToGlobalBattleParticipants(lobbyId: lobbyId) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let roster):
                    self.participants = roster

                    if self.phase == .finished && self.finishOutcome == .none {
                        self.applyBestAvailableFinishedOutcome()
                    }

                case .failure(let error):
                    self.isBusy = false
                    self.phase = .failed(error.localizedDescription)
                    self.statusMessage = "Roster listener failed."
                }
            }
        }
    }

    private func attachRuntimeListener(lobbyId: String) {
        runtimeListener?.remove()

        runtimeListener = FirestoreService.shared.listenToGlobalBattleRuntime(lobbyId: lobbyId) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let runtime):
                    self.runtime = runtime
                    self.liveQuestion = runtime.question
                    self.extraTieBreakRounds = max(0, runtime.extraTieBreakRounds)

                    let runtimePhaseNormalized = runtime.phase
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    let runtimeQuestionKey = runtime.question?.key ?? ""

                    if self.lastObservedAnswerRoundIndex != runtime.roundIndex {
                        self.lastObservedAnswerRoundIndex = runtime.roundIndex
                        self.localSelectedChoiceIndex = nil
                        self.localLockedChoiceIndex = nil
                        self.answers = []
                        self.revealInFlightQuestionKey = ""
                        self.processedRevealRoundKey = ""
                        self.finishInFlightRoundIndex = nil
                        self.currentRoundArmedAt = nil
                        self.currentArmedQuestionKey = ""
                        self.isAwaitingNextQuestion = false
                        self.debugLog("runtime round changed -> attaching answers listener for round \(runtime.roundIndex)")
                        self.attachAnswersListener(lobbyId: lobbyId, roundIndex: runtime.roundIndex)
                    }

                    if runtimePhaseNormalized == "answering", !runtimeQuestionKey.isEmpty {
                        if self.currentArmedQuestionKey != runtimeQuestionKey {
                            self.currentArmedQuestionKey = runtimeQuestionKey
                            self.currentRoundArmedAt = Date()
                            self.revealInFlightQuestionKey = ""
                            self.debugLog("round armed for key=\(runtimeQuestionKey)")
                        }
                    } else if runtimePhaseNormalized != "revealed" && runtimePhaseNormalized != "finished" {
                        self.currentRoundArmedAt = nil
                        self.currentArmedQuestionKey = ""
                        self.revealInFlightQuestionKey = ""
                    }

                    if runtimePhaseNormalized == "finished" {
                        self.finishInFlightRoundIndex = runtime.roundIndex
                        self.applyAuthoritativeFinishOutcome(from: runtime)
                    }

                    self.debugLog("runtime listener update")
                    self.debugLog(
                        "runtime.phase=\(runtime.phase) runtime.roundIndex=\(runtime.roundIndex) questionKey=\(runtime.question?.key ?? "nil") tieBreaks=\(runtime.extraTieBreakRounds)"
                    )

                    switch self.roundPhase {
                    case .waiting:
                        if self.phase == .live {
                            self.statusMessage = self.isAwaitingPresenceCheck
                                ? "Paused — are players still here?"
                                : "Waiting for host."
                        }
                    case .answering:
                        self.phase = .live
                        self.statusMessage = self.isTieBreakRound ? "Tie-break live." : "Answer now."
                    case .revealed:
                        self.phase = .live
                        self.statusMessage = self.isAwaitingPresenceCheck
                            ? "Paused — are players still here?"
                            : "Answers revealed."
                    case .finished:
                        self.phase = .finished
                        self.statusMessage = "Match finished."
                    }

                case .failure(let error):
                    self.isBusy = false
                    self.phase = .failed(error.localizedDescription)
                    self.statusMessage = "Runtime listener failed."
                }
            }
        }
    }

    private func attachAnswersListener(lobbyId: String, roundIndex: Int) {
        answersListener?.remove()

        answersListener = FirestoreService.shared.listenToGlobalBattleAnswers(
            lobbyId: lobbyId,
            roundIndex: roundIndex
        ) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let answers):
                    self.answers = answers
                    self.debugLog("answers listener update round=\(roundIndex) count=\(answers.count)")
                    for answer in answers {
                        self.debugLog("answer uid=\(answer.uid) choice=\(answer.choiceIndex) isCorrect=\(String(describing: answer.isCorrect))")
                    }

                case .failure(let error):
                    self.isBusy = false
                    self.phase = .failed(error.localizedDescription)
                    self.statusMessage = "Answers listener failed."
                }
            }
        }
    }

    private func fetchSettledAnswersForReveal(
        lobbyId: String,
        roundIndex: Int,
        expectedCount: Int
    ) async throws -> [GlobalBattleAnswerSubmission] {
        let targetCount = max(1, expectedCount)

        if answers.count < targetCount {
            try? await Task.sleep(nanoseconds: answerSettleDelayNanoseconds)
        }

        var latest = try await FirestoreService.shared.fetchGlobalBattleAnswers(
            lobbyId: lobbyId,
            roundIndex: roundIndex
        )

        answers = latest
        debugLog("fresh answer fetch round=\(roundIndex) count=\(latest.count)")
        for answer in latest {
            debugLog("fresh answer uid=\(answer.uid) choice=\(answer.choiceIndex)")
        }

        if latest.count < targetCount {
            try? await Task.sleep(nanoseconds: lateAnswerGraceNanoseconds)

            let retry = try await FirestoreService.shared.fetchGlobalBattleAnswers(
                lobbyId: lobbyId,
                roundIndex: roundIndex
            )

            if retry.count != latest.count {
                latest = retry
                answers = retry
                debugLog("late grace fetch +1 round=\(roundIndex) count=\(retry.count)")
                for answer in retry {
                    debugLog("late grace +1 uid=\(answer.uid) choice=\(answer.choiceIndex)")
                }
            }
        }

        if latest.count < targetCount {
            try? await Task.sleep(nanoseconds: secondLateAnswerGraceNanoseconds)

            let retry = try await FirestoreService.shared.fetchGlobalBattleAnswers(
                lobbyId: lobbyId,
                roundIndex: roundIndex
            )

            if retry.count != latest.count {
                latest = retry
                answers = retry
                debugLog("late grace fetch +2 round=\(roundIndex) count=\(retry.count)")
                for answer in retry {
                    debugLog("late grace +2 uid=\(answer.uid) choice=\(answer.choiceIndex)")
                }
            }
        }

        debugLog("settled reveal answers round=\(roundIndex) finalCount=\(latest.count)/\(targetCount)")
        return latest
    }

    private func mergedUniqueAnswersByUID(
        _ answers: [GlobalBattleAnswerSubmission]
    ) -> [GlobalBattleAnswerSubmission] {
        var bestByUID: [String: GlobalBattleAnswerSubmission] = [:]

        for answer in answers {
            let uid = answer.uid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { continue }

            if let existing = bestByUID[uid] {
                let existingTS = normalizedSubmittedAt(for: existing)
                let incomingTS = normalizedSubmittedAt(for: answer)

                switch (existingTS, incomingTS) {
                case let (lhs?, rhs?):
                    if rhs < lhs {
                        bestByUID[uid] = answer
                    }
                case (nil, .some):
                    bestByUID[uid] = answer
                case (nil, nil):
                    break
                case (.some, nil):
                    break
                }
            } else {
                bestByUID[uid] = answer
            }
        }

        return Array(bestByUID.values)
    }

    private func fetchPostRevealGraceAnswers(
        lobbyId: String,
        roundIndex: Int,
        existing: [GlobalBattleAnswerSubmission]
    ) async throws -> [GlobalBattleAnswerSubmission] {
        try? await Task.sleep(nanoseconds: secondLateAnswerGraceNanoseconds)

        let retry = try await FirestoreService.shared.fetchGlobalBattleAnswers(
            lobbyId: lobbyId,
            roundIndex: roundIndex
        )

        let merged = mergedUniqueAnswersByUID(existing + retry)
        answers = merged

        debugLog("post-reveal grace fetch round=\(roundIndex) mergedCount=\(merged.count)")
        for answer in merged {
            debugLog("post-reveal uid=\(answer.uid) choice=\(answer.choiceIndex)")
        }

        return merged
    }

    // MARK: - Post-reveal flow control

    private func holdReveal(for roundIndex: Int, tieBreak: Bool) async {
        let isFinalRegulationLanding = !tieBreak && roundIndex >= baseQuestionCount
        try? await Task.sleep(
            nanoseconds: isFinalRegulationLanding
                ? finalRevealHoldNanoseconds
                : revealHoldNanoseconds
        )
    }

    private func stageAndLaunchNextRound(
        lobbyId: String,
        currentUID: String,
        nextRound: Int,
        tieBreak: Bool,
        extraTieBreakRounds: Int,
        delayNanoseconds: UInt64,
        durationSeconds: Int
    ) async throws {
        try await FirestoreService.shared.stageGlobalBattleRoundWaiting(
            lobbyId: lobbyId,
            roundIndex: nextRound,
            extraTieBreakRounds: extraTieBreakRounds
        )

        try? await Task.sleep(nanoseconds: delayNanoseconds)

        guard let nextQuestion = questionFor(round: nextRound) else {
            if tieBreak {
                isBusy = false
                phase = .failed("Tie-break question pool exhausted.")
                statusMessage = "Tie-break question pool exhausted."
            } else {
                isBusy = false
                phase = .failed("No question available for next round.")
                statusMessage = "No question available for next round."
            }
            return
        }

        beginHostedRound(
            currentUID: currentUID,
            question: nextQuestion,
            questionKey: questionKey(for: nextRound, tieBreak: tieBreak, question: nextQuestion),
            durationSeconds: durationSeconds
        )
    }

    private func finishMatch(
        lobbyId: String,
        roundIndex: Int,
        outcome: FinishOutcome,
        finishState: GlobalBattleRuntimeFinishState,
        statusMessage message: String
    ) async throws {
        guard finishInFlightRoundIndex != roundIndex else {
            debugLog("finish blocked: already finalizing round \(roundIndex)")
            isBusy = false
            return
        }

        finishInFlightRoundIndex = roundIndex
        finishOutcome = outcome
        noAnswerRoundStreak = 0
        isAwaitingPresenceCheck = false

        try await FirestoreService.shared.finishGlobalBattleRuntime(
            lobbyId: lobbyId,
            finish: finishState
        )

        try await FirestoreService.shared.updateGlobalBattleStatus(
            lobbyId: lobbyId,
            status: "finished",
            roundIndex: roundIndex
        )

        isBusy = false
        phase = .finished
        statusMessage = message
    }

    private func advanceGameFlowAfterReveal(
        lobbyId: String,
        currentUID: String,
        roundToScore: Int,
        correctIndex: Int,
        rosterAtReveal currentRoster: [GlobalBattleParticipant],
        currentAnswers: [GlobalBattleAnswerSubmission],
        scoredRoster: [GlobalBattleParticipant]
    ) async throws {
        guard !isAwaitingNextQuestion else {
            debugLog("advance blocked: already awaiting next question")
            isBusy = false
            return
        }

        let currentRound = max(1, roundToScore)

        isAwaitingNextQuestion = true
        defer {
            isAwaitingNextQuestion = false
        }

        let isTieBreakScoringRound = currentRound > baseQuestionCount

        if isTieBreakScoringRound {
            registerTieBreakMisses(
                roster: currentRoster,
                answers: currentAnswers
            )

            await holdReveal(for: currentRound, tieBreak: true)

            let disqualified = disqualifiedTieBreakParticipants(roster: currentRoster)

            if disqualified.count >= 2 {
                let dqUIDs = disqualified.map(\.uid)

                try await finishMatch(
                    lobbyId: lobbyId,
                    roundIndex: currentRound,
                    outcome: .doubleDisqualification(
                        disqualifiedUIDs: dqUIDs,
                        duringTieBreak: true
                    ),
                    finishState: GlobalBattleRuntimeFinishState(
                        type: "double_disqualification",
                        winnerUID: nil,
                        disqualifiedUID: nil,
                        disqualifiedUIDs: dqUIDs,
                        duringTieBreak: true
                    ),
                    statusMessage: "Both pilots disqualified."
                )
                return
            }

            if disqualified.count == 1, let dq = disqualified.first {
                let survivingRoster = currentRoster.filter { $0.uid != dq.uid }
                let winnerUID = survivingRoster.first?.uid ?? ""
                let winnerName = participantDisplayName(for: winnerUID, roster: currentRoster)
                let dqName = participantDisplayName(for: dq.uid, roster: currentRoster)

                try await finishMatch(
                    lobbyId: lobbyId,
                    roundIndex: currentRound,
                    outcome: .winByDisqualification(
                        winnerUID: winnerUID,
                        disqualifiedUID: dq.uid,
                        duringTieBreak: true
                    ),
                    finishState: GlobalBattleRuntimeFinishState(
                        type: "win_by_disqualification",
                        winnerUID: winnerUID.isEmpty ? nil : winnerUID,
                        disqualifiedUID: dq.uid,
                        disqualifiedUIDs: [dq.uid],
                        duringTieBreak: true
                    ),
                    statusMessage: "\(winnerName) wins — \(dqName) disqualified."
                )
                return
            }

            let correctAnswers = validCorrectTieBreakAnswers(
                from: currentAnswers,
                correctIndex: correctIndex
            )

            if let winningAnswer = resolveTieBreakWinner(from: correctAnswers) {
                let winnerUID = winningAnswer.uid
                let winnerName = participantDisplayName(for: winnerUID, roster: currentRoster)

                try await finishMatch(
                    lobbyId: lobbyId,
                    roundIndex: currentRound,
                    outcome: .tieBreakSpeedWin(winnerUID: winnerUID),
                    finishState: GlobalBattleRuntimeFinishState(
                        type: "tiebreak_speed_win",
                        winnerUID: winnerUID,
                        disqualifiedUID: nil,
                        disqualifiedUIDs: [],
                        duringTieBreak: true
                    ),
                    statusMessage: "\(winnerName) wins!"
                )
                return
            }

            let nextRound = currentRound + 1
            let continuedTieBreakCount = max(extraTieBreakRounds + 1, nextRound - baseQuestionCount)
            extraTieBreakRounds = continuedTieBreakCount

            try await FirestoreService.shared.updateGlobalBattleTieBreakRounds(
                lobbyId: lobbyId,
                extraTieBreakRounds: continuedTieBreakCount
            )

            try await stageAndLaunchNextRound(
                lobbyId: lobbyId,
                currentUID: currentUID,
                nextRound: nextRound,
                tieBreak: true,
                extraTieBreakRounds: continuedTieBreakCount,
                delayNanoseconds: tieBreakDelayNanoseconds,
                durationSeconds: 10
            )
            return
        }

        await holdReveal(for: currentRound, tieBreak: false)

        let newlyDisqualified = newlyDisqualifiedRegulationParticipants(roster: currentRoster)
        if !newlyDisqualified.isEmpty {
            regulationEliminatedUIDs.formUnion(newlyDisqualified.map(\.uid))
        }

        let regulationDQSet = Set(
            disqualifiedMissedAnswerParticipants(roster: currentRoster).map(\.uid)
        )

        let stillActivePlayers = currentRoster.filter {
            !regulationDQSet.contains($0.uid)
        }

        if !regulationDQSet.isEmpty {
            debugLog("⚠️ REGULATION DQ triggered: \(regulationDQSet)")

            if stillActivePlayers.isEmpty {
                let dqList = Array(regulationDQSet)

                try await finishMatch(
                    lobbyId: lobbyId,
                    roundIndex: currentRound,
                    outcome: .doubleDisqualification(
                        disqualifiedUIDs: dqList,
                        duringTieBreak: false
                    ),
                    finishState: GlobalBattleRuntimeFinishState(
                        type: "double_disqualification",
                        winnerUID: nil,
                        disqualifiedUID: nil,
                        disqualifiedUIDs: dqList,
                        duringTieBreak: false
                    ),
                    statusMessage: "All players disqualified."
                )
                return
            }

            if stillActivePlayers.count == 1, let winner = stillActivePlayers.first {
                let dqList = Array(regulationDQSet)

                try await finishMatch(
                    lobbyId: lobbyId,
                    roundIndex: currentRound,
                    outcome: .winByDisqualification(
                        winnerUID: winner.uid,
                        disqualifiedUID: dqList.first ?? "",
                        duringTieBreak: false
                    ),
                    finishState: GlobalBattleRuntimeFinishState(
                        type: "win_by_disqualification",
                        winnerUID: winner.uid,
                        disqualifiedUID: dqList.first,
                        disqualifiedUIDs: dqList,
                        duringTieBreak: false
                    ),
                    statusMessage: "\(participantDisplayName(for: winner.uid, roster: currentRoster)) wins — others disqualified."
                )
                return
            }

            debugLog("continuing with active players only: \(stillActivePlayers.map(\.uid))")
        }

        let answeredUIDs = Set(currentAnswers.map(\.uid))
        let trueNoAnswer = currentRoster.allSatisfy { !answeredUIDs.contains($0.uid) }

        if trueNoAnswer && noAnswerRoundStreak >= 3 {
            isAwaitingPresenceCheck = true
            isBusy = false
            statusMessage = "Paused — are players still here?"
            return
        }

        isAwaitingPresenceCheck = false

        if currentRound < baseQuestionCount {
            let nextRound = currentRound + 1
            let nextRoundIsFinalRegulation = nextRound == baseQuestionCount

            try await stageAndLaunchNextRound(
                lobbyId: lobbyId,
                currentUID: currentUID,
                nextRound: nextRound,
                tieBreak: false,
                extraTieBreakRounds: extraTieBreakRounds,
                delayNanoseconds: nextRoundIsFinalRegulation
                    ? finalRoundLeadInNanoseconds
                    : betweenRoundsDelayNanoseconds,
                durationSeconds: 14
            )
            return
        }

        let survivingScoredRoster = scoredRoster.filter { !regulationDQSet.contains($0.uid) }

        guard !survivingScoredRoster.isEmpty else {
            let dqList = Array(regulationDQSet)

            try await finishMatch(
                lobbyId: lobbyId,
                roundIndex: currentRound,
                outcome: .doubleDisqualification(
                    disqualifiedUIDs: dqList,
                    duringTieBreak: false
                ),
                finishState: GlobalBattleRuntimeFinishState(
                    type: "double_disqualification",
                    winnerUID: nil,
                    disqualifiedUID: nil,
                    disqualifiedUIDs: dqList,
                    duringTieBreak: false
                ),
                statusMessage: "All players disqualified."
            )
            return
        }

        let leaders = leadingParticipants(from: survivingScoredRoster)

        if leaders.count > 1 {
            let newTieBreakCount = extraTieBreakRounds + 1
            extraTieBreakRounds = newTieBreakCount
            tieBreakMissedAnswerCounts = [:]
            noAnswerRoundStreak = 0

            try await FirestoreService.shared.updateGlobalBattleTieBreakRounds(
                lobbyId: lobbyId,
                extraTieBreakRounds: newTieBreakCount
            )

            let tieBreakRound = currentRound + 1

            try await stageAndLaunchNextRound(
                lobbyId: lobbyId,
                currentUID: currentUID,
                nextRound: tieBreakRound,
                tieBreak: true,
                extraTieBreakRounds: newTieBreakCount,
                delayNanoseconds: tieBreakDelayNanoseconds,
                durationSeconds: 10
            )
            return
        }

        let winnerUID = leaders.first?.uid ?? ""
        let winnerName = participantDisplayName(for: winnerUID, roster: survivingScoredRoster)

        try await finishMatch(
            lobbyId: lobbyId,
            roundIndex: currentRound,
            outcome: .regulationWin(winnerUID: winnerUID),
            finishState: GlobalBattleRuntimeFinishState(
                type: "regulation_win",
                winnerUID: winnerUID.isEmpty ? nil : winnerUID,
                disqualifiedUID: nil,
                disqualifiedUIDs: Array(regulationDQSet),
                duringTieBreak: false
            ),
            statusMessage: "\(winnerName) wins!"
        )
    }

    // MARK: - Tie-break helpers

    private func normalizedSubmittedAt(for answer: GlobalBattleAnswerSubmission) -> Date? {
        guard let submittedAt = answer.submittedAt else { return nil }
        if submittedAt.timeIntervalSince1970 < 1_000_000_000 { return nil }
        return submittedAt
    }

    private func validCorrectTieBreakAnswers(
        from answers: [GlobalBattleAnswerSubmission],
        correctIndex: Int
    ) -> [GlobalBattleAnswerSubmission] {
        let armedAt = currentRoundArmedAt ?? .distantPast
        let latestAllowed = Date().addingTimeInterval(1.25)

        return answers
            .filter { $0.choiceIndex == correctIndex }
            .filter { answer in
                guard let submittedAt = normalizedSubmittedAt(for: answer) else {
                    debugLog("tiebreak rejected invalid timestamp uid=\(answer.uid)")
                    return false
                }

                guard submittedAt >= armedAt.addingTimeInterval(-0.35) else {
                    debugLog("tiebreak rejected pre-armed timestamp uid=\(answer.uid)")
                    return false
                }

                guard submittedAt <= latestAllowed else {
                    debugLog("tiebreak rejected future timestamp uid=\(answer.uid)")
                    return false
                }

                return true
            }
            .sorted {
                let lhs = normalizedSubmittedAt(for: $0) ?? .distantFuture
                let rhs = normalizedSubmittedAt(for: $1) ?? .distantFuture

                if lhs == rhs {
                    return $0.uid < $1.uid
                }

                return lhs < rhs
            }
    }

    private func resolveTieBreakWinner(
        from correctAnswers: [GlobalBattleAnswerSubmission]
    ) -> GlobalBattleAnswerSubmission? {
        guard let fastest = correctAnswers.first,
              let fastestTime = normalizedSubmittedAt(for: fastest) else {
            debugLog("tiebreak winner unresolved: no correct submission")
            return nil
        }

        let contenders = correctAnswers.filter {
            guard let ts = normalizedSubmittedAt(for: $0) else { return false }
            return ts.timeIntervalSince(fastestTime) <= tieBreakFairnessWindow
        }

        if contenders.count == 1 {
            let ts = fastestTime.timeIntervalSince1970
            debugLog("tiebreak winner uid=\(fastest.uid) choice=\(fastest.choiceIndex) submittedAt=\(ts)")
            return fastest
        } else {
            debugLog("tiebreak photo finish: \(contenders.count) answers landed within \(tieBreakFairnessWindow)s")
            return nil
        }
    }

    private func registerTieBreakMisses(
        roster: [GlobalBattleParticipant],
        answers: [GlobalBattleAnswerSubmission]
    ) {
        let answeredUIDs = Set(answers.map(\.uid))

        for player in roster {
            if answeredUIDs.contains(player.uid) {
                tieBreakMissedAnswerCounts[player.uid] = 0
            } else {
                let next = (tieBreakMissedAnswerCounts[player.uid] ?? 0) + 1
                tieBreakMissedAnswerCounts[player.uid] = next
                debugLog("tiebreak strike uid=\(player.uid) strikes=\(next)")
            }
        }
    }

    private func registerMissedAnswers(
        roster: [GlobalBattleParticipant],
        answers: [GlobalBattleAnswerSubmission]
    ) {
        let answeredUIDs = Set(
            answers.map { $0.uid.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        for player in roster {
            let uid = player.uid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { continue }

            if answeredUIDs.contains(uid) {
                missedAnswerCounts[uid] = 0
                debugLog("miss streak reset uid=\(uid)")
            } else {
                let next = (missedAnswerCounts[uid] ?? 0) + 1
                missedAnswerCounts[uid] = next
                debugLog("miss streak uid=\(uid) streak=\(next)")
            }
        }
    }

    private func missedAnswerStrikeCount(for uid: String) -> Int {
        missedAnswerCounts[uid] ?? 0
    }

    private func disqualifiedMissedAnswerParticipants(
        roster: [GlobalBattleParticipant]
    ) -> [GlobalBattleParticipant] {
        roster.filter {
            missedAnswerStrikeCount(for: $0.uid) >= missedAnswerDisqualificationThreshold
        }
    }

    private func activeRegulationParticipants(
        roster: [GlobalBattleParticipant]
    ) -> [GlobalBattleParticipant] {
        roster.filter { !regulationEliminatedUIDs.contains($0.uid) }
    }

    private func newlyDisqualifiedRegulationParticipants(
        roster: [GlobalBattleParticipant]
    ) -> [GlobalBattleParticipant] {
        roster.filter {
            !regulationEliminatedUIDs.contains($0.uid) &&
            missedAnswerStrikeCount(for: $0.uid) >= missedAnswerDisqualificationThreshold
        }
    }

    private func tieBreakStrikeCount(for uid: String) -> Int {
        tieBreakMissedAnswerCounts[uid] ?? 0
    }

    private func disqualifiedTieBreakParticipants(
        roster: [GlobalBattleParticipant]
    ) -> [GlobalBattleParticipant] {
        roster.filter { tieBreakStrikeCount(for: $0.uid) >= tieBreakDisqualificationThreshold }
    }

    private func rebuildFinishOutcomeFromCurrentState() {
        let roster = participants
        guard !roster.isEmpty else {
            finishOutcome = .none
            return
        }

        let roundIndex = runtime?.roundIndex ?? 0
        let duringTieBreak = roundIndex > baseQuestionCount

        if duringTieBreak {
            let disqualified = disqualifiedTieBreakParticipants(roster: roster)

            if disqualified.count >= 2 {
                finishOutcome = .doubleDisqualification(
                    disqualifiedUIDs: disqualified.map(\.uid),
                    duringTieBreak: true
                )
                return
            }

            if disqualified.count == 1, let dq = disqualified.first {
                let survivors = roster.filter { $0.uid != dq.uid }
                if let winner = survivors.first {
                    finishOutcome = .winByDisqualification(
                        winnerUID: winner.uid,
                        disqualifiedUID: dq.uid,
                        duringTieBreak: true
                    )
                    return
                }
            }

            let leaders = leadingParticipants(from: roster)
            if leaders.count == 1, let winner = leaders.first {
                finishOutcome = .tieBreakSpeedWin(winnerUID: winner.uid)
            } else {
                finishOutcome = .none
            }
            return
        }

        let leaders = leadingParticipants(from: roster)
        if leaders.count == 1, let winner = leaders.first {
            finishOutcome = .regulationWin(winnerUID: winner.uid)
        } else {
            finishOutcome = .none
        }
    }

    private func applyBestAvailableFinishedOutcome() {
        if finishOutcome != .none { return }

        if let runtime {
            applyAuthoritativeFinishOutcome(from: runtime)
            return
        }

        rebuildFinishOutcomeFromCurrentState()
    }

    private func applyAuthoritativeFinishOutcome(from runtime: GlobalBattleRuntimeState) {
        if let finish = runtime.finish {
            let type = finish.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            switch type {
            case "win_by_disqualification":
                if let winnerUID = finish.winnerUID,
                   let disqualifiedUID = finish.disqualifiedUID {
                    finishOutcome = .winByDisqualification(
                        winnerUID: winnerUID,
                        disqualifiedUID: disqualifiedUID,
                        duringTieBreak: finish.duringTieBreak
                    )
                    return
                }

            case "double_disqualification":
                finishOutcome = .doubleDisqualification(
                    disqualifiedUIDs: finish.disqualifiedUIDs,
                    duringTieBreak: finish.duringTieBreak
                )
                return

            case "tiebreak_speed_win":
                if let winnerUID = finish.winnerUID {
                    finishOutcome = .tieBreakSpeedWin(winnerUID: winnerUID)
                    return
                }

            case "regulation_win":
                if let winnerUID = finish.winnerUID {
                    finishOutcome = .regulationWin(winnerUID: winnerUID)
                    return
                }

            default:
                break
            }
        }

        rebuildFinishOutcomeFromCurrentState()
    }

    // MARK: - Question Pool

    private func warmDailyPack(dayKey: String, topic: String, questionCount: Int) async {
        await preheatQuestionsForLobby(
            dayKey: dayKey,
            topic: topic,
            questionCount: questionCount,
            forceFetchIfInsufficient: true
        )
    }

    private func warmDailyPackBlocking(dayKey: String, topic: String, questionCount: Int) async {
        await preheatQuestionsForLobby(
            dayKey: dayKey,
            topic: topic,
            questionCount: questionCount,
            forceFetchIfInsufficient: true
        )
    }

    private func preheatQuestionsForLobby(
        dayKey: String,
        topic: String,
        questionCount: Int,
        forceFetchIfInsufficient: Bool
    ) async {
        if matchDeckLocked {
            debugLog("daily pack warm ignored: deck already locked")
            return
        }

        let minimumDeckSize = max(questionCount, 10)
        let desiredWarmCount = max(
            minimumDeckSize,
            min(questionCount + 20, DailyPackStore.shared.perTopicCount)
        )

        let warmed = await DailyPackStore.shared.preheatTopicIfNeeded(
            dayKey: dayKey,
            topic: topic,
            minimumCount: desiredWarmCount,
            forceFetchIfInsufficient: forceFetchIfInsufficient
        )

        let sanitized = dedupeQuestions(warmed)
        let randomized = sanitized.shuffled()

        if randomized.count >= minimumDeckSize {
            matchQuestionDeck = randomized
            didLoadRemoteQuestions = true
            debugLog("daily pack warmed: \(randomized.count) questions for \(topic)")
        } else {
            matchQuestionDeck = []
            didLoadRemoteQuestions = false
            debugLog("daily pack warm insufficient: \(randomized.count) questions for \(topic)")
        }
    }

    private func dedupeQuestions(_ input: [TriviaQuestion]) -> [TriviaQuestion] {
        var seen = Set<String>()
        var output: [TriviaQuestion] = []

        for question in input {
            let key = DailyPackStore.qid(question)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(question)
        }

        return output
    }

    private func prepareLockedDeckIfNeeded(questionCount: Int) async {
        guard !matchDeckLocked else { return }

        let minimumDeckSize = max(questionCount, 10)

        func isDeckUsable(_ deck: [TriviaQuestion]) -> Bool {
            let deduped = dedupeQuestions(deck)
            return deduped.count >= minimumDeckSize
        }

        if isDeckUsable(matchQuestionDeck) {
            matchQuestionDeck = dedupeQuestions(matchQuestionDeck)
            matchDeckLocked = true
            lockedDeckUsesRemoteQuestions = didLoadRemoteQuestions

            debugLog(
                "deck locked (prewarmed) source=\(lockedDeckUsesRemoteQuestions ? "daily" : "fallback") count=\(matchQuestionDeck.count)"
            )
            return
        }

        if let lobby {
            debugLog("deck insufficient -> forcing daily re-fetch")

            await preheatQuestionsForLobby(
                dayKey: lobby.dayKey,
                topic: lobby.topic,
                questionCount: lobby.questionCount,
                forceFetchIfInsufficient: true
            )
        }

        if isDeckUsable(matchQuestionDeck) {
            matchQuestionDeck = dedupeQuestions(matchQuestionDeck)
            didLoadRemoteQuestions = true
            matchDeckLocked = true
            lockedDeckUsesRemoteQuestions = true

            debugLog("deck locked AFTER FORCE FETCH source=daily count=\(matchQuestionDeck.count)")
            return
        }

        debugLog("⚠️ FALLBACK ENGAGED — daily pack unavailable")

        matchQuestionDeck = dedupeQuestions(fallbackQuestionPack.shuffled())
        didLoadRemoteQuestions = false
        matchDeckLocked = true
        lockedDeckUsesRemoteQuestions = false

        debugLog("deck locked source=fallback count=\(matchQuestionDeck.count)")
    }

    private func questionFor(round: Int) -> TriviaQuestion? {
        let primaryPool = matchQuestionDeck.isEmpty ? fallbackQuestionPack : matchQuestionDeck

        let availablePrimary = primaryPool.filter {
            !usedQuestionIDs.contains(DailyPackStore.qid($0))
        }

        if let next = availablePrimary.randomElement() {
            return next
        }

        if round <= baseQuestionCount {
            return nil
        }

        let unusedTiePool = fallbackQuestionPack.filter {
            !usedQuestionIDs.contains(DailyPackStore.qid($0))
        }

        if let next = unusedTiePool.randomElement() {
            return next
        }

        let recycledTiePool = fallbackQuestionPack.filter {
            questionKey(for: round, tieBreak: true, question: $0) != currentArmedQuestionKey
        }

        return recycledTiePool.randomElement() ?? fallbackQuestionPack.randomElement()
    }

    private func markQuestionUsed(_ question: TriviaQuestion) {
        usedQuestionIDs.insert(DailyPackStore.qid(question))
    }

    private func questionKey(for round: Int, tieBreak: Bool, question: TriviaQuestion) -> String {
        let slug = question.prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if tieBreak {
            return "global-tiebreak-\(round)-\(slug)"
        }

        let usesRemote = matchDeckLocked ? lockedDeckUsesRemoteQuestions : didLoadRemoteQuestions
        if usesRemote {
            return "global-daily-\(round)-\(slug)"
        }

        return "global-fallback-\(round)-\(slug)"
    }

    private func leadingParticipants(from roster: [GlobalBattleParticipant]) -> [GlobalBattleParticipant] {
        guard let topScore = roster.map(\.score).max() else { return [] }
        return roster.filter { $0.score == topScore }
    }

    private func participantDisplayName(for uid: String, roster: [GlobalBattleParticipant]) -> String {
        if let participant = roster.first(where: { $0.uid == uid }) {
            let cleaned = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "PILOT" : cleaned
        }
        return "PILOT"
    }

    private func winnerDisplayName(from roster: [GlobalBattleParticipant]) -> String {
        guard let winner = leadingParticipants(from: roster).first else {
            return "Winner"
        }

        let cleaned = winner.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "PILOT" : cleaned
    }

    // MARK: - Fallback Pack

    private var fallbackQuestionPack: [TriviaQuestion] {
        [
            TriviaQuestion(
                prompt: "Which planet is known as the Red Planet?",
                choices: ["Venus", "Mars", "Jupiter", "Mercury"],
                correctIndex: 1
            ),
            TriviaQuestion(
                prompt: "What does CPU stand for?",
                choices: [
                    "Central Processing Unit",
                    "Computer Personal Unit",
                    "Central Performance Utility",
                    "Core Process Unit"
                ],
                correctIndex: 0
            ),
            TriviaQuestion(
                prompt: "What is the largest ocean on Earth?",
                choices: ["Atlantic Ocean", "Indian Ocean", "Pacific Ocean", "Arctic Ocean"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "Which language is primarily used for iOS development?",
                choices: ["Swift", "Kotlin", "Java", "Ruby"],
                correctIndex: 0
            ),
            TriviaQuestion(
                prompt: "Which gas do plants absorb from the atmosphere?",
                choices: ["Oxygen", "Hydrogen", "Carbon Dioxide", "Nitrogen"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "What is the capital of Japan?",
                choices: ["Osaka", "Kyoto", "Tokyo", "Nagoya"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "How many sides does a hexagon have?",
                choices: ["5", "6", "7", "8"],
                correctIndex: 1
            ),
            TriviaQuestion(
                prompt: "What does HTTP stand for?",
                choices: [
                    "HyperText Transfer Protocol",
                    "HighText Transfer Protocol",
                    "Hyper Transfer Text Process",
                    "HyperText Transit Program"
                ],
                correctIndex: 0
            ),
            TriviaQuestion(
                prompt: "Which element has the symbol O?",
                choices: ["Gold", "Oxygen", "Silver", "Osmium"],
                correctIndex: 1
            ),
            TriviaQuestion(
                prompt: "How many continents are there?",
                choices: ["5", "6", "7", "8"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "What color do you get when you mix red and blue?",
                choices: ["Orange", "Purple", "Green", "Yellow"],
                correctIndex: 1
            ),
            TriviaQuestion(
                prompt: "Which planet has the most moons?",
                choices: ["Earth", "Mars", "Saturn", "Venus"],
                correctIndex: 2
            )
        ]
    }

    private func sanitizedDisplayName(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "PILOT" : cleaned
    }

    private func sanitizedTopic(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General Knowledge" : cleaned
    }

    private func makeBattleCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("🧠 [GlobalBattleSession] \(message)")
        #endif
    }

    private func debugRuntimeSnapshot(prefix: String) {
        #if DEBUG
        let lobbyID = localLobbyID ?? "nil"
        let lobbyRound = lobby?.roundIndex ?? -1
        let runtimeRound = runtime?.roundIndex ?? -1
        let runtimePhase = runtime?.phase ?? "nil"
        let questionKey = runtime?.question?.key ?? liveQuestion?.key ?? "nil"
        let locked = localLockedChoiceIndex.map(String.init) ?? "nil"

        print(
            """
            🧠 [GlobalBattleSession] \(prefix)
               lobbyID: \(lobbyID)
               phase: \(phase)
               lobbyRound: \(lobbyRound)
               runtimeRound: \(runtimeRound)
               runtimePhase: \(runtimePhase)
               questionKey: \(questionKey)
               answersCount: \(answers.count)
               localLockedChoiceIndex: \(locked)
               participants: \(participants.count)
               extraTieBreakRounds: \(extraTieBreakRounds)
            """
        )
        #endif
    }
}
