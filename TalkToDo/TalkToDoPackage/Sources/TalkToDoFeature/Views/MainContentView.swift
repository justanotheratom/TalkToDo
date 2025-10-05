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

    @State private var showUndoPill = false
    @State private var undoPillDismissTask: Task<Void, Never>?
    @State private var selectedNodeContext: NodeContext?
    @State private var showSettings = false
    @State private var showOnboarding = false

    public init() {}

    public var body: some View {
        Group {
            if let onboarding = onboardingStore, !onboarding.hasCompletedOnboarding {
                OnboardingView(store: onboarding, onComplete: {
                    showOnboarding = false
                })
            } else {
                mainContent
            }
        }
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

                // Undo pill (top-center overlay)
                VStack {
                    UndoPill(isVisible: showUndoPill, onTap: handleUndo)
                        .padding(.top, 8)
                    Spacer()
                }

                // Microphone input bar
                VStack {
                    Spacer()
                    MicrophoneInputBar(
                        status: voiceInputStore.status,
                        isEnabled: voiceInputStore.isEnabled,
                        onPressDown: handleMicrophonePress,
                        onPressUp: handleMicrophoneRelease
                    )
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle("TalkToDo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
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
            showUndoPillBriefly()

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

                    if coordinator.canUndo() {
                        showUndoPillBriefly()
                    }
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

                    if coordinator.canUndo() {
                        showUndoPillBriefly()
                    }
                }
            }
        }
    }

    // MARK: - Undo

    private func handleUndo() {
        Task {
            await voiceCoordinator?.undo()
            hideUndoPill()
        }
    }

    private func showUndoPillBriefly() {
        undoPillDismissTask?.cancel()

        withAnimation {
            showUndoPill = true
        }

        undoPillDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation {
                    showUndoPill = false
                }
            }
        }
    }

    private func hideUndoPill() {
        undoPillDismissTask?.cancel()
        withAnimation {
            showUndoPill = false
        }
    }
}

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

extension Color {
    init(uiColor: PlatformColor) {
        #if os(iOS)
        self.init(uiColor: uiColor)
        #else
        self.init(nsColor: uiColor)
        #endif
    }
}

#Preview {
    MainContentView()
        .modelContainer(for: [NodeEvent.self], inMemory: true)
}
