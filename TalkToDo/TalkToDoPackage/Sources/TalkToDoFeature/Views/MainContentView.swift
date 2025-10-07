import SwiftUI
import SwiftData
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct MainContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var nodeTree = NodeTree()
    @State private var eventStore: EventStore?
    @State private var changeTracker = ChangeTracker()
    @State private var undoManager: UndoManager?
    @State private var voiceInputStore = VoiceInputStore()
    @State private var voiceCoordinator: VoiceInputCoordinator?
    @State private var textCoordinator: TextInputCoordinator?
    @State private var llmService = LLMInferenceService()
    @State private var onboardingStore: OnboardingStore?
    @State private var processingSettings = VoiceProcessingSettingsStore()
    @State private var pipelineFactory: VoiceProcessingPipelineFactory?

    @State private var undoFeedbackMessage: String?
    @State private var undoFeedbackDismissTask: Task<Void, Never>?
    @State private var selectedNodeContext: NodeContext?
    @State private var showSettings = false
    @State private var nodeListStore = NodeListStore()

    public init() {}

    public var body: some View {
        Group {
            if let onboarding = onboardingStore, onboarding.state != .completed && !onboarding.hasCompletedOnboarding {
                OnboardingView(store: onboarding, onComplete: {
                    Task {
                        await synchronizeOnDeviceModel(for: processingSettings.mode)
                    }
                })
            } else {
                mainContent
            }
        }
        .environment(\.eventStore, eventStore)
        .environment(\.undoManager, undoManager)
        .task {
            await initializeApp()
        }
        .onChange(of: changeTracker.highlightedNodes) { _, newHighlights in
            nodeListStore.highlightedNodes = newHighlights
        }
        .onChange(of: processingSettings.mode) { oldMode, newMode in
            updateProcessingPipeline(for: newMode, previousMode: oldMode)
        }
        .onChange(of: processingSettings.remoteAPIKey) { _, _ in
            updateProcessingPipeline(for: processingSettings.mode, previousMode: processingSettings.mode)
        }
    }

    private var mainContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Node list
                NodeListView(
                    nodeTree: nodeTree,
                    store: nodeListStore,
                    onToggleCollapse: handleToggleCollapse,
                    onLongPress: handleLongPress,
                    onDelete: handleDelete,
                    onEdit: handleEdit,
                    onCheckboxToggle: handleCheckboxToggle
                )

                // Microphone input bar with processing/undo feedback
                VStack(spacing: 0) {
                    // Processing indicator
                    if let info = activeProcessingInfo {
                        ProcessingPill(
                            transcript: info.text,
                            isError: info.isError
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // Undo feedback overlay above microphone
                    else if let message = undoFeedbackMessage {
                        HStack {
                            Spacer()
                            Text(message)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.75))
                                )
                                .padding(.bottom, 4)
                            Spacer()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    MicrophoneInputBar(
                        status: voiceInputStore.status,
                        isEnabled: voiceInputStore.isEnabled,
                        liveTranscript: voiceInputStore.liveTranscript,
                        onPressDown: handleMicrophonePress,
                        onPressUp: handleMicrophoneRelease,
                        onSendText: handleTextInput
                    )
                    #if os(iOS)
                    .background(Color(uiColor: .systemBackground))
                    #else
                    .background(Color(.windowBackgroundColor))
                    #endif
                }
            }
            .navigationTitle("TalkToDo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    if undoManager?.canUndo() == true {
                        Button(action: handleUndo) {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    if undoManager?.canUndo() == true {
                        Button(action: handleUndo) {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsStore: processingSettings)
            }
        }
    }

    // MARK: - Initialization

    private func initializeApp() async {
        // Initialize onboarding store
        onboardingStore = OnboardingStore(
            voiceInputStore: voiceInputStore,
            llmService: llmService
        )

        // Initialize event store and undo manager
        let store = EventStore(modelContext: modelContext, nodeTree: nodeTree)
        eventStore = store

        let undo = UndoManager(changeTracker: changeTracker)
        undoManager = undo

        // Load events and rebuild tree
        do {
            try store.initializeNodeTree()
            // Clear undo history - events loaded from disk are not undoable
            undo.clearHistory()
            AppLogger.ui().log(event: "app:initialized", data: [
                "nodeCount": nodeTree.allNodeCount()
            ])
        } catch {
            AppLogger.ui().logError(event: "app:initFailed", error: error)
        }

        // Initialize coordinators
        let factory = VoiceProcessingPipelineFactory(
            settingsStore: processingSettings,
            llmService: llmService
        )
        pipelineFactory = factory

        let voicePipeline = factory.currentPipeline()
        voiceCoordinator = VoiceInputCoordinator(
            eventStore: store,
            pipeline: voicePipeline,
            mode: processingSettings.mode,
            undoManager: undo,
            changeTracker: changeTracker
        )

        let textPipeline = factory.currentTextPipeline()
        textCoordinator = TextInputCoordinator(
            eventStore: store,
            pipeline: textPipeline,
            mode: processingSettings.mode,
            undoManager: undo,
            changeTracker: changeTracker
        )

        AppLogger.ui().log(event: "app:pipelineInitialized", data: [
            "mode": processingSettings.mode.rawValue
        ])

        // Align on-device model state with the selected processing mode
        if onboardingStore?.hasCompletedOnboarding == true {
            await synchronizeOnDeviceModel(for: processingSettings.mode)
        }

        await voiceInputStore.prepareForRecording()
    }

    private func loadDefaultModelIfNeeded() async {
        let storage = ModelStorageService()
        let defaultModel = ModelCatalog.defaultModel

        guard storage.isDownloaded(entry: defaultModel) else {
            AppLogger.ui().log(event: "app:modelNotDownloaded", data: ["slug": defaultModel.slug])
            return
        }

        do {
            let url = try storage.expectedResourceURL(for: defaultModel)
            try await llmService.loadModel(at: url)
            AppLogger.ui().log(event: "app:modelLoaded", data: ["slug": defaultModel.slug])
        } catch {
            AppLogger.ui().logError(event: "app:modelLoadFailed", error: error)
        }
    }

    private var activeProcessingInfo: (text: String, isError: Bool)? {
        if let coordinator = voiceCoordinator,
           coordinator.isProcessing,
           let transcript = coordinator.processingTranscript {
            return (transcript, coordinator.processingError != nil)
        }

        if let coordinator = textCoordinator,
           coordinator.isProcessing,
           let text = coordinator.processingText {
            return (text, coordinator.processingError != nil)
        }

        return nil
    }

    // MARK: - Node Actions

    private func handleToggleCollapse(_ nodeId: String) {
        guard let store = eventStore else { return }

        let batchId = NodeID.generateBatchID()
        let payload = ToggleCollapsePayload(nodeId: nodeId)

        do {
            let payloadData = try JSONEncoder().encode(payload)
            let event = NodeEvent(
                type: .toggleCollapse,
                payload: payloadData,
                batchId: batchId
            )
            try store.appendEvent(event)

            AppLogger.ui().log(event: "node:toggleCollapse", data: ["nodeId": nodeId])
        } catch {
            AppLogger.ui().logError(event: "node:toggleCollapseFailed", error: error)
        }
    }

    private func handleLongPress(_ node: Node) {
        selectedNodeContext = NodeContext(
            nodeId: node.id,
            title: node.title,
            depth: 0  // TODO: Calculate actual depth
        )

        AppLogger.ui().log(event: "node:longPress", data: ["nodeId": node.id])
    }

    private func handleDelete(_ nodeId: String) {
        guard let store = eventStore else { return }

        let batchId = NodeID.generateBatchID()
        let payload = DeleteNodePayload(nodeId: nodeId)

        do {
            let payloadData = try JSONEncoder().encode(payload)
            let event = NodeEvent(
                type: .deleteNode,
                payload: payloadData,
                batchId: batchId
            )
            try store.appendEvent(event)
            undoManager?.recordBatch(batchId)

            AppLogger.ui().log(event: "node:deleted", data: ["nodeId": nodeId])
        } catch {
            AppLogger.ui().logError(event: "node:deleteFailed", error: error)
        }
    }

    private func handleEdit(_ nodeId: String) {
        // TODO: Implement edit flow (voice rename)
        AppLogger.ui().log(event: "node:editTapped", data: ["nodeId": nodeId])
    }

    private func handleCheckboxToggle(_ nodeId: String) {
        guard let store = eventStore, let node = nodeTree.findNode(id: nodeId) else { return }

        let batchId = NodeID.generateBatchID()
        let newCompletionState = !node.isCompleted
        let payload = ToggleCompletePayload(nodeId: nodeId, isCompleted: newCompletionState)

        do {
            let payloadData = try JSONEncoder().encode(payload)
            let event = NodeEvent(
                type: .toggleComplete,
                payload: payloadData,
                batchId: batchId
            )
            try store.appendEvent(event)
            undoManager?.recordBatch(batchId)

            AppLogger.ui().log(event: "node:toggleComplete", data: ["nodeId": nodeId, "isCompleted": newCompletionState])
        } catch {
            AppLogger.ui().logError(event: "node:toggleCompleteFailed", error: error)
        }
    }

    // MARK: - Voice Input

    private func handleMicrophonePress() {
        logMicEvent("voice:micPressDown")
        Task {
            await voiceInputStore.startRecording { metadata in
                Task {
                    guard let coordinator = voiceCoordinator else { return }

                    await coordinator.processRecording(
                        metadata: metadata,
                        nodeContext: selectedNodeContext
                    )

                    selectedNodeContext = nil
                }
            }
        }
    }

    private func handleMicrophoneRelease() {
        logMicEvent("voice:micPressUp")
        Task {
            await voiceInputStore.finishRecording()
            selectedNodeContext = nil
        }
    }

    private func handleTextInput(_ text: String) {
        Task {
            guard let coordinator = textCoordinator else { return }

            await coordinator.processText(
                text,
                nodeContext: selectedNodeContext
            )

            selectedNodeContext = nil
        }
    }

    private func updateProcessingPipeline(for mode: ProcessingMode, previousMode _: ProcessingMode) {
        guard let factory = pipelineFactory else { return }

        if let voice = voiceCoordinator {
            let voicePipeline = factory.pipeline(for: mode)
            voice.updatePipeline(voicePipeline, mode: mode)
        }

        if let text = textCoordinator {
            let textPipeline = factory.textPipeline(for: mode)
            text.updatePipeline(textPipeline, mode: mode)
        }

        Task {
            await synchronizeOnDeviceModel(for: mode)
        }
    }

    private func logMicEvent(_ name: String, extra: [String: Any] = [:]) {
        var payload = extra
        payload["timestamp"] = MainContentView.isoFormatter.string(from: Date())
        AppLogger.speech().log(event: name, data: payload)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @MainActor
    private func synchronizeOnDeviceModel(for mode: ProcessingMode) async {
        switch mode {
        case .onDevice:
            await loadDefaultModelIfNeeded()
        case .remoteGemini:
            AppLogger.ui().log(event: "app:modelSync:unloadForRemote", data: [
                "mode": mode.rawValue
            ])
            await llmService.unloadModel()
        }
    }

    // MARK: - Undo

    private func handleUndo() {
        Task {
            let undone = await voiceCoordinator?.undo() ?? false
            if undone {
                showUndoFeedback("Undone")
            }
        }
    }

    private func showUndoFeedback(_ message: String) {
        undoFeedbackDismissTask?.cancel()

        withAnimation {
            undoFeedbackMessage = message
        }

        undoFeedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation {
                    undoFeedbackMessage = nil
                }
            }
        }
    }
}

#Preview {
    MainContentView()
        .modelContainer(for: [NodeEvent.self], inMemory: true)
}
