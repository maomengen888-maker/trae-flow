import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class DynamicQuickRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = DynamicQuickRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var latestTranscript = ""
    @Published private(set) var latestSummary = ""
    @Published private(set) var latestAudioURL: URL?
    @Published private(set) var statusText = "点击开始快速录音"

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartedAt: Date?

    private static var recordingsDirectoryURL: URL {
        DynamicUserStoragePaths.recordingsURL
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestPermissionsAndStart()
        }
    }

    func requestPermissionsAndStart() {
        statusText = "正在请求麦克风与语音识别权限"
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] audioGranted in
            guard audioGranted else {
                Task { @MainActor in self?.statusText = "未获得麦克风权限" }
                return
            }
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                Task { @MainActor in
                    guard speechStatus == .authorized else {
                        self?.statusText = "未获得语音识别权限"
                        return
                    }
                    self?.startRecording()
                }
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        recordingStartedAt = nil
        isRecording = false
        statusText = "正在生成本地转写"
        guard let url = latestAudioURL else { return }
        transcribe(url: url)
    }

    func convertLatestTranscriptToNote() {
        guard !latestTranscript.isEmpty else { return }
        _ = DynamicPersonalWorkspaceStore.shared.addNote(markdown: latestTranscript)
        statusText = "已保存为随笔"
    }

    func convertLatestTranscriptToTask() {
        guard !latestTranscript.isEmpty else { return }
        _ = DynamicPersonalWorkspaceStore.shared.addTask(
            title: Self.summaryTitle(from: latestTranscript),
            detail: latestTranscript
        )
        statusText = "已创建待办"
    }

    private func startRecording() {
        do {
            try DynamicUserStoragePaths.prepareDirectories()
            try FileManager.default.createDirectory(
                at: Self.recordingsDirectoryURL,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = Self.recordingsDirectoryURL.appendingPathComponent(
                "recording-\(formatter.string(from: Date())).m4a"
            )
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            guard recorder.record() else {
                statusText = "无法开始录音"
                return
            }
            self.recorder = recorder
            latestAudioURL = url
            latestTranscript = ""
            latestSummary = ""
            elapsed = 0
            recordingStartedAt = Date()
            isRecording = true
            statusText = "正在录音"
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.recordingStartedAt else { return }
                    self.elapsed = Date().timeIntervalSince(started)
                }
            }
        } catch {
            statusText = "录音失败：\(error.localizedDescription)"
        }
    }

    private func transcribe(url: URL) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            statusText = "本地语音识别当前不可用，音频已保存"
            return
        }
        isTranscribing = true
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    self.latestTranscript = text
                    self.latestSummary = Self.makeSummary(from: text)
                    self.isTranscribing = false
                    self.statusText = text.isEmpty ? "没有识别到语音，音频已保存" : "转写完成"
                } else if let error {
                    self.isTranscribing = false
                    self.statusText = "转写失败，音频已保存：\(error.localizedDescription)"
                }
            }
        }
    }

    private static func makeSummary(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let sentences = cleaned.components(separatedBy: CharacterSet(charactersIn: "。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sentences.prefix(2).joined(separator: "；")
    }

    private static func summaryTitle(from text: String) -> String {
        String(makeSummary(from: text).prefix(24))
    }
}
