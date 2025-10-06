import SwiftUI
import SwiftData
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct MainContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var nodeTree = NodeTree()
    @State private var eventStore: EventStore?
    @State private var undoManager = UndoManager()
    @State private var voiceInputStore = VoiceInputStore()
    @State private var voiceCoordinator: VoiceInputCoordinator?
    @State private var llmService = LLMInferenceService()
    @State private var onboardingStore: OnboardingStore?

    @State private var undoFeedbackMessage: String?
    @State private var undoFeedbackDismissTask: Task<Void, Never>?
    @State private var selectedNodeContext: NodeContext?
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        Group {
            if let onboarding = onboardingStore, onboarding.state != .completed && !onboarding.hasCompletedOnboarding {
                OnboardingView(store: onboarding, onComplete: {
                    Task {
                        await loadDefaultModelIfNeeded()
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
    }

    private var mainContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Node list
                NodeListView(
                    nodeTree: nodeTree,
                    onToggleCollapse: handleToggleCollapse,
                    onLongPress: handleLongPress,
                    onDelete: handleDelete,
                    onEdit: handleEdit
                )

                // Microphone input bar with processing/undo feedback
                VStack(spacing: 0) {
                    // Processing indicator
                    if let coordinator = voiceCoordinator,
                       coordinator.isProcessing,
                       let transcript = coordinator.processingTranscript {
                        ProcessingPill(
                            transcript: transcript,
                            isError: coordinator.processingError != nil
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
                    if undoManager.canUndo() {
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
                    if undoManager.canUndo() {
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
                SettingsView()
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

        // Initialize event store
        let store = EventStore(modelContext: modelContext, nodeTree: nodeTree)
        eventStore = store

        // Load events and rebuild tree
        do {
            try store.initializeNodeTree()
            // Clear undo history - events loaded from disk are not undoable
            undoManager.clearHistory()
            AppLogger.ui().log(event: "app:initialized", data: [
                "nodeCount": nodeTree.allNodeCount()
            ])
        } catch {
            AppLogger.ui().logError(event: "app:initFailed", error: error)
        }

        // Initialize coordinator
        voiceCoordinator = VoiceInputCoordinator(
            eventStore: store,
            llmService: llmService,
            undoManager: undoManager
        )

        // Load default model if onboarding is complete
        if onboardingStore?.hasCompletedOnboarding == true {
            await loadDefaultModelIfNeeded()
        }
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
            undoManager.recordBatch(batchId)

            AppLogger.ui().log(event: "node:deleted", data: ["nodeId": nodeId])
        } catch {
            AppLogger.ui().logError(event: "node:deleteFailed", error: error)
        }
    }

    private func handleEdit(_ nodeId: String) {
        // TODO: Implement edit flow (voice rename)
        AppLogger.ui().log(event: "node:editTapped", data: ["nodeId": nodeId])
    }

    // MARK: - Voice Input

    private func handleMicrophonePress() {
        Task {
            await voiceInputStore.startRecording { transcript in
                Task {
                    guard let coordinator = voiceCoordinator else { return }

                    await coordinator.processTranscript(
                        transcript,
                        nodeContext: selectedNodeContext
                    )

                    selectedNodeContext = nil
                }
            }
        }
    }

    private func handleMicrophoneRelease() {
        Task {
            await voiceInputStore.finishRecording { transcript in
                Task {
                    guard let coordinator = voiceCoordinator else { return }

                    await coordinator.processTranscript(
                        transcript,
                        nodeContext: selectedNodeContext
                    )

                    selectedNodeContext = nil
                }
            }
        }
    }

    private func handleTextInput(_ text: String) {
        Task {
            guard let coordinator = voiceCoordinator else { return }

            await coordinator.processTranscript(
                text,
                nodeContext: selectedNodeContext
            )

            selectedNodeContext = nil
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
