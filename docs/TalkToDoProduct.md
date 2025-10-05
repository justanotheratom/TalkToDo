# TalkToDo — Product Document (Merged & Refocused)

_Last updated: October 2025_

> **Concept:** Voice Input ⇒ Structured Output. Speak naturally, release, and watch a clean, hierarchical to‑do list appear.

---

## 0) Overview & Purpose
TalkToDo is a **showcase app** for the **voice‑to‑structure** interaction category. It demonstrates how fluid and delightful it can feel when voice input is instantly translated into structured, hierarchical lists — all processed offline, entirely on device.

---

## 1) Core Principles
1. **Speak like a human, see structure like an outliner**
2. **Offline‑first and private by design** — no cloud inference, no streaming
3. **LLM‑first architecture** — no rules, no heuristics
4. **Simplicity** — everything is a node; editing happens through natural voice or quick actions
5. **Delight** — subtle sound, haptic, and animation feedback make every action feel magical

---

## 2) Technical Context
- **Speech Recognition:** Apple’s on‑device ASR
- **LLM:** Liquid.ai’s **LFM2** model (700M or 1.2B) via Leap SDK
- **Persistence:** **SwiftData** event log + **CloudKit Private Database** for seamless cross‑device sync
- **Sync note:** CloudKit syncs structured app data (not user files); this uses the default app container for per‑user data continuity.
- **Offline‑first:** Everything — ASR, inference, and storage — runs locally; no server dependency.

---

## 3) User Interaction Model
### Global Input
- **Long‑Press Mic (Bottom Bar):** Press and hold to speak; release to trigger inference. No live feedback during speech.
- **Post‑speech Animation:** Hierarchical structure fades in after processing.
- **Undo Pill:** Appears briefly to reverse the last operation.

### Node‑Level Actions
- **Tap Node:** Toggle collapse/expand of children. Collapsed nodes show a subtle chevron indicator.
- **Long‑Press on Node:** Speak a context‑aware command. The selected node's title and hierarchy position are passed as context to the LLM (e.g., "add subtasks," "rename this").
- **Swipe Left:** Reveal Edit and Delete actions.
- **No Inline Editing:** Titles cannot be edited directly; all edits go through voice or swipe actions.

### Feedback & Feel
- Light haptics when recording starts and ends.
- Glow animation when speech capture finishes.
- Gentle tick sound when structure appears.
- Springy, natural motion as list hierarchy settles.

---

## 4) System Architecture
### Event‑Sourced Model
- **Event Log:** Append‑only source of truth (InsertNode, MoveNode, RenameNode, etc.)
- **Snapshot:** In-memory structure always kept in sync with the event log. On app startup, the snapshot is regenerated from the event log, and thereafter every new event appended to the log also updates the snapshot.
- **Storage:** SwiftData local persistence, synced via CloudKit Private Database
- **Conflict Resolution:** Last-write-wins strategy for concurrent edits across devices

### LLM Processing
- **Input:** Complete ASR transcript (after release), plus optional node context for node-level commands
- **Output:** Structured Operation Plan (validated JSON schema)
- **Operations:** insert_node, insert_children, reparent_node, rename_node, delete_node, etc.
- **Validation:** Local schema check before applying to event reducer
- **System Prompt:** Instructs LFM2 to parse natural speech into hierarchical operations. The prompt emphasizes:
  - Extracting implicit hierarchy from pauses, transitions ("then," "also"), and semantic grouping
  - Generating valid JSON with explicit parent-child relationships
  - Handling ambiguity gracefully (e.g., flat lists when hierarchy is unclear)
  - For node-level commands: interpreting intent relative to the provided node context

---

## 5) Latency & Performance Goals
| Stage | Target | Notes |
|-------|---------|-------|
| ASR (Apple) | < 500 ms | after release |
| LLM Inference (LFM2‑700M) | < 1 s | for ~2 paragraphs |
| UI Commit + Animation | < 200 ms | hierarchy settle |
| **Total (End‑to‑UI)** | **≤ 1.7 s** | Ideal perception: instant clarity |

**Optimizations:**
- Warm‑load model at app start
- Reuse tokenizer state across interactions
- Lightweight JSON schema; no regex post‑processing

---

## 6) Example Flow
**User says:**  
> “Thanksgiving prep. Groceries… turkey, cranberries, sweet potatoes. House… clean guest room, put out linens.”

**Result:**  
- Thanksgiving prep
  - Groceries
    - turkey
    - cranberries
    - sweet potatoes
  - House
    - clean guest room
    - put out linens

**User long‑presses ‘Groceries’**  
> “Add sparkling water and stuffing.”

→ App animates new children under *Groceries*.

---

## 7) Design Focus — Delight & Intuition
- **Minimal UI:** white canvas, indented nodes, responsive mic pill.
- **Micro‑Delights:** haptic pop, glowing outline, kinetic drag handle.
- **Zero Clutter:** no tags, due dates, or status markers.
- **Hierarchy Visualization:** indentation and gentle fade motion reinforce structure.

### Empty State
On first launch or when all nodes are deleted, the app displays:
- **Visual:** A centered, pulsing mic icon with subtle shadow
- **Text:** "Hold the mic and speak your thoughts"
- **Subtext:** "Try: 'Weekend plans... hiking, groceries, call mom'"
- **Animation:** Gentle breathing motion to invite interaction

---

## 8) Developer Experience Tools
- **Latency Harness:** measures ASR + LLM + UI latency locally.
- **Inspector Mode:** reveals transcript, operations, and applied diffs for debugging.
- **Replay Log:** allows internal devs to validate event replay correctness.

---

## 9) Future Enhancements (Experimental)
- Structured streaming inference (if device models allow)
- Smart corrections via follow‑up voice
- Adaptive timing for animation based on confidence
- Edge quantized model for even faster local inference

---

## 10) Summary
TalkToDo demonstrates the future of **voice‑first structured thinking**:  
Hold, speak, release — and see thought become structure.  
No commands, no syntax, no typing. Just language, intention, and delight.

