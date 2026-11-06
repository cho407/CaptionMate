# 사용하지 않는 변수 및 설정 분석

이 문서는 CaptionMate에서 **실시간 전사(Real-time Streaming)** 기능을 사용하지 않기 때문에 실제로 적용되지 않거나 불필요한 변수들을 정리합니다.

## 📋 현재 앱의 동작 방식

- **파일 전사만 사용**: 사용자가 오디오 파일을 임포트하여 전사
- **실시간 전사 미사용**: 마이크로부터 실시간 녹음/전사 기능 없음

---

## ❌ 사용하지 않는 변수들

### 1. ContentViewModel (`@AppStorage` 설정)

#### ✅ **삭제 가능한 변수**

```swift
// 실시간 스트리밍 전용 - 파일 전사에는 적용되지 않음
@AppStorage("silenceThreshold") var silenceThreshold: Double = 0.3
@AppStorage("realtimeDelayInterval") var realtimeDelayInterval: Double = 1.0
@AppStorage("selectedAudioInput") var selectedAudioInput: String = "No Audio Input"
@AppStorage("tokenConfirmationsNeeded") var tokenConfirmationsNeeded: Double = 2.0
```

**설명:**
- `silenceThreshold`: VAD(Voice Activity Detection) 관련, DecodingOptions에 전달되지 않음
- `realtimeDelayInterval`: 실시간 스트리밍 루프 간 지연, 파일 전사에서 미사용
- `selectedAudioInput`: 마이크 입력 선택용, 실시간 녹음 기능 없음
- `tokenConfirmationsNeeded`: 실시간 스트리밍 토큰 확인용

#### ⚠️ **검토 필요한 변수**

```swift
@AppStorage("useVAD") var useVAD: Bool = true
@AppStorage("enableEagerDecoding") var enableEagerDecoding: Bool = false
```

**설명:**
- `useVAD`: chunkingStrategy와 중복될 수 있음 (chunkingStrategy.vad로 대체 가능)
- `enableEagerDecoding`: 코드 내에서 사용되는지 확인 필요

---

### 2. TranscriptionState (StateModels.swift)

#### ✅ **삭제 가능한 필드**

```swift
struct TranscriptionState {
    var lastBufferSize: Int = 0              // 실시간 버퍼 크기
    var bufferEnergy: [Float] = []           // 실시간 오디오 에너지
    var bufferSeconds: Double = 0             // 실시간 버퍼 시간
    var unconfirmedSegments: [TranscriptionSegment] = []  // 실시간 미확인 세그먼트
}
```

**설명:**
- 이 필드들은 실시간 스트리밍에서 버퍼 상태를 추적하는 용도
- 파일 전사에서는 사용되지 않음

#### ✅ **유지해야 할 필드** (파일 전사에서 사용)

```swift
struct TranscriptionState {
    var currentText: String = ""
    var currentChunks: [Int: (chunkText: [String], fallbacks: Int)] = [:]
    var tokensPerSecond: TimeInterval = 0
    var firstTokenTime: TimeInterval = 0
    var modelLoadingTime: TimeInterval = 0
    var pipelineStart: TimeInterval = 0
    var currentLag: TimeInterval = 0
    var currentFallbacks: Int = 0
    var currentEncodingLoops: Int = 0
    var currentDecodingLoops: Int = 0
    var lastConfirmedSegmentEndSeconds: Float = 0
    var confirmedSegments: [TranscriptionSegment] = []
    var effectiveRealTimeFactor: TimeInterval = 0
    var effectiveSpeedFactor: TimeInterval = 0
    var totalInferenceTime: TimeInterval = 0
}
```

---

### 3. ContentViewModel (메서드)

#### ⚠️ **검토 필요한 메서드**

```swift
// resetState() 내부의 실시간 관련 코드
func resetState() {
    whisperKit?.audioProcessor.stopRecording()  // ← 실시간 녹음 중지 (불필요할 수 있음)
    // ...
}
```

**설명:**
- `audioProcessor.stopRecording()`: 실시간 녹음이 없다면 불필요
- 하지만 안전을 위해 유지하는 것도 가능

---

## 🎯 SettingsView에서 제거 가능한 설정

현재 SettingsView에 표시되지만 실제로 적용되지 않는 설정들:

### 삭제 가능한 설정 UI

```swift
// 1. Silence Threshold (silenceThreshold)
VStack {
    Text("Silence Threshold")
    HStack {
        Slider(value: $viewModel.silenceThreshold, in: 0 ... 1, step: 0.05)
        Text(viewModel.silenceThreshold.formatted(.number))
            .frame(width: 30)
        InfoButton("info.silence_threshold")
    }
}

// 2. Realtime Delay Interval (realtimeDelayInterval)
VStack {
    Text("Realtime Delay Interval")
    HStack {
        Slider(value: $viewModel.realtimeDelayInterval, in: 0 ... 30, step: 1)
        Text(viewModel.realtimeDelayInterval.formatted(.number))
            .frame(width: 30)
        InfoButton("info.realtime_delay_interval")
    }
}
```

---

## 📊 사용 여부 요약표

| 변수/설정 | 위치 | 파일 전사 사용 | 실시간 전사 사용 | 권장 조치 |
|----------|------|--------------|----------------|-----------|
| `enableTimestamps` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `enableWordTimestamp` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `enableSpecialCharacters` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `enablePromptPrefill` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `enableCachePrefill` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `temperatureStart` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `fallbackCount` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `sampleLength` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `concurrentWorkerCount` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `chunkingStrategy` | ContentViewModel | ✅ 사용 | ✅ 사용 | **유지** |
| `frameRate` | ContentViewModel | ✅ 사용 (Export) | ❌ 미사용 | **유지** (Export용) |
| `enableDecoderPreview` | ContentViewModel | ✅ 사용 (UI) | ✅ 사용 (UI) | **유지** (UI용) |
| **`silenceThreshold`** | ContentViewModel | ❌ **미적용** | ⚠️ VAD용 | **삭제 검토** |
| **`realtimeDelayInterval`** | ContentViewModel | ❌ **미적용** | ✅ 사용 | **삭제 검토** |
| **`selectedAudioInput`** | ContentViewModel | ❌ **미사용** | ✅ 사용 | **삭제 가능** |
| **`tokenConfirmationsNeeded`** | ContentViewModel | ❌ **미사용** | ✅ 사용 | **삭제 가능** |
| **`useVAD`** | ContentViewModel | ❌ **미사용** | ⚠️ 중복? | **검토 필요** |
| **`enableEagerDecoding`** | ContentViewModel | ❌ **미사용** | ❌ 미사용 | **검토 필요** |
| `lastBufferSize` | TranscriptionState | ❌ **미사용** | ✅ 사용 | **삭제 가능** |
| `bufferEnergy` | TranscriptionState | ❌ **미사용** | ✅ 사용 | **삭제 가능** |
| `bufferSeconds` | TranscriptionState | ❌ **미사용** | ✅ 사용 | **삭제 가능** |
| `unconfirmedSegments` | TranscriptionState | ❌ **미사용** | ✅ 사용 | **삭제 가능** |

---

## 🔧 정리 작업 제안

### Phase 1: 확실히 삭제 가능한 것들

1. **ContentViewModel**:
   - `selectedAudioInput` 삭제
   - `tokenConfirmationsNeeded` 삭제
   - `silenceThreshold` 삭제 (또는 주석 처리)
   - `realtimeDelayInterval` 삭제 (또는 주석 처리)

2. **TranscriptionState**:
   - `lastBufferSize` 삭제
   - `bufferEnergy` 삭제
   - `bufferSeconds` 삭제
   - `unconfirmedSegments` 삭제

3. **SettingsView**:
   - "Silence Threshold" 섹션 제거
   - "Realtime Delay Interval" 섹션 제거

4. **Localizable.xcstrings**:
   - `info.silence_threshold` 삭제 (또는 유지)
   - `info.realtime_delay_interval` 삭제 (또는 유지)

### Phase 2: 검토 후 결정

1. **ContentViewModel**:
   - `useVAD`: chunkingStrategy와 중복 여부 확인
   - `enableEagerDecoding`: 실제 사용 여부 코드 검색

2. **resetState()**:
   - `audioProcessor.stopRecording()` 호출 필요성 검토

---

## ⚠️ 주의사항

1. **향후 실시간 전사 기능 추가 가능성**:
   - 나중에 실시간 전사 기능을 추가할 계획이 있다면, 관련 변수들을 주석 처리하고 유지하는 것이 좋습니다.

2. **WhisperKit 버전 호환성**:
   - WhisperKit 라이브러리 업데이트 시 일부 설정이 필요할 수 있으므로 주석으로 남겨두는 것도 방법입니다.

3. **단계적 제거**:
   - 한 번에 모두 제거하기보다는 Phase 1 → 테스트 → Phase 2 순서로 진행 권장

---

## 📝 결론

현재 CaptionMate는 **파일 전사만 사용**하므로:

- ✅ **즉시 삭제 가능**: `selectedAudioInput`, `tokenConfirmationsNeeded`, TranscriptionState의 버퍼 관련 필드들
- ⚠️ **검토 후 삭제**: `silenceThreshold`, `realtimeDelayInterval`, `useVAD`, `enableEagerDecoding`
- ✅ **유지 필요**: 나머지 모든 전사 관련 설정 (DecodingOptions에 전달됨)

정리 작업을 통해 코드 복잡도를 줄이고 유지보수성을 향상시킬 수 있습니다.
