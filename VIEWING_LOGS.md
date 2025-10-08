# How to View TalkToDo Logs

## Method 1: Xcode Console (When Running from Xcode)

1. **Run the app from Xcode** (⌘+R)
2. **Open the Console panel** at the bottom of Xcode (⌘+Shift+Y)
3. **Filter logs** using the search box:
   - Type `gemini:` to see all Gemini API logs
   - Type `voice:` to see voice input logs
   - Type `llm:` to see LLM-related logs
   - Type `node:` to see node operation logs

### Key Log Events to Monitor:

**Gemini API Performance:**
- `gemini:requestStart` - Shows request size and context info
- `gemini:llmResponse` - Full LLM response (raw and parsed JSON)
- `gemini:requestSuccess` - **Latency and token statistics**
- `gemini:requestFailed` - API errors

**Voice Processing:**
- `voice:recordingStarted` - When recording begins
- `voice:transcriptReceived` - Final transcript
- `voiceCoordinator:processSuccess` - Full processing pipeline success

## Method 2: Console.app (macOS Native App)

1. **Open Console.app** (⌘+Space, type "Console")
2. **Select your device** in the sidebar (iPhone/iPad/Simulator)
3. **Filter by Process**:
   - Type `TalkToDo` in the search box
4. **Add subsystem filter**:
   - Click "Action" → "Include Info Messages"
   - Filter by subsystem: `com.talktodo`

### Advanced Filters:
```
subsystem:com.talktodo AND category:llm
subsystem:com.talktodo AND category:voice
subsystem:com.talktodo AND eventMessage CONTAINS "gemini:"
```

## Method 3: Command Line (Terminal)

### Real-time streaming logs:
```bash
# All TalkToDo logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.talktodo"'

# Only LLM/Gemini logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.talktodo" AND category == "llm"'

# Only voice logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.talktodo" AND category == "voice"'

# Gemini-specific events
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.talktodo"' | grep "gemini:"
```

### View recent logs:
```bash
# Last 5 minutes of logs
xcrun simctl spawn booted log show --last 5m --predicate 'subsystem == "com.talktodo"'

# Export to file
xcrun simctl spawn booted log show --last 1h --predicate 'subsystem == "com.talktodo"' > talktodo_logs.txt
```

## Method 4: Export Logs from Device

### From Xcode:
1. **Window** → **Devices and Simulators**
2. Select your device/simulator
3. Click **View Device Logs**
4. Search for `TalkToDo` or filter by date
5. Right-click a log → **Export**

## What to Look For

### Performance Issues:

**Latency Metrics** (in `gemini:requestSuccess`):
- `totalLatencyMs` - Total request time (should be < 2000ms)
- `networkLatencyMs` - Network roundtrip time
- `promptTokens` - Input tokens (check if this is unusually high)
- `completionTokens` - Output tokens
- `requestSizeBytes` - Request payload size

**Example Good Performance:**
```
gemini:requestSuccess | totalLatencyMs=1234, promptTokens=150, completionTokens=45
```

**Example Slow Performance:**
```
gemini:requestSuccess | totalLatencyMs=5678, promptTokens=850, completionTokens=120
```

### Debugging Context Issues:

Look for `hasNodeContext=true` in `gemini:requestStart` and `gemini:requestSuccess` to verify node context is being sent when you long-press a node.

### LLM Response Quality:

Check `gemini:llmResponse` to see:
- `rawResponse` - Full text from Gemini
- `extractedJSON` - Parsed operations
- `operationCount` - Number of operations generated

## Quick Debug Command

Copy this for quick debugging:
```bash
# Stream all TalkToDo logs with timestamps
xcrun simctl spawn booted log stream --style compact --predicate 'subsystem == "com.talktodo"' | grep -E "gemini:|voice:|node:"
```

## Performance Baseline

**Expected latencies:**
- Local voice recording: < 100ms to start
- Gemini API (no audio): 800-1500ms
- Gemini API (with audio): 1500-3000ms
- Token usage (typical): 100-300 prompt tokens, 20-100 completion tokens

If you see significantly higher numbers, investigate network issues or check if the prompt has grown too large.
