import Foundation
import AVFoundation
import CoreMedia
import CoreImage

public struct CaptureDeviceInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CameraAudioRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.displaystudio.cameraaudio.session", qos: .userInitiated)
    private let ciContext = CIContext()

    private var webcamWriter: AVAssetWriter?
    private var webcamWriterInput: AVAssetWriterInput?
    private var micWriter: AVAssetWriter?
    private var micWriterInput: AVAssetWriterInput?

    private var isWebcamSessionStarted = false
    private var isMicSessionStarted = false
    private var isPaused = false

    public var onWebcamFrame: ((CGImage) -> Void)?
    public var onMicrophoneLevel: ((Float) -> Void)?

    private var recordedMicPeakHistory: [Float] = []

    public override init() {
        super.init()
    }

    public static func availableCameras() -> [CaptureDeviceInfo] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    public static func availableMicrophones() -> [CaptureDeviceInfo] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func startRecording(
        cameraID: String?,
        microphoneID: String?,
        webcamOutputURL: URL?,
        micOutputURL: URL?
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.stopSessionInternal()
            self.recordedMicPeakHistory.removeAll()
            self.isPaused = false

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Add camera input if selected
            if let cameraID,
               let camDevice = AVCaptureDevice(uniqueID: cameraID),
               let camInput = try? AVCaptureDeviceInput(device: camDevice),
               self.session.canAddInput(camInput) {
                self.session.addInput(camInput)

                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                if self.session.canAddOutput(videoOutput) {
                    self.session.addOutput(videoOutput)
                }

                if let webcamOutputURL {
                    try? FileManager.default.removeItem(at: webcamOutputURL)
                    if let writer = try? AVAssetWriter(outputURL: webcamOutputURL, fileType: .mov) {
                        let settings: [String: Any] = [
                            AVVideoCodecKey: AVVideoCodecType.hevc,
                            AVVideoWidthKey: 1280,
                            AVVideoHeightKey: 720
                        ]
                        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                        input.expectsMediaDataInRealTime = true
                        if writer.canAdd(input) { writer.add(input) }
                        writer.startWriting()
                        self.webcamWriter = writer
                        self.webcamWriterInput = input
                        self.isWebcamSessionStarted = false
                    }
                }
            }

            // Add microphone input if selected
            if let microphoneID,
               let micDevice = AVCaptureDevice(uniqueID: microphoneID),
               let micInput = try? AVCaptureDeviceInput(device: micDevice),
               self.session.canAddInput(micInput) {
                self.session.addInput(micInput)

                let audioOutput = AVCaptureAudioDataOutput()
                audioOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                if self.session.canAddOutput(audioOutput) {
                    self.session.addOutput(audioOutput)
                }

                if let micOutputURL {
                    try? FileManager.default.removeItem(at: micOutputURL)
                    if let writer = try? AVAssetWriter(outputURL: micOutputURL, fileType: .caf) {
                        let settings: [String: Any] = [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: 48000,
                            AVNumberOfChannelsKey: 1,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false
                        ]
                        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                        input.expectsMediaDataInRealTime = true
                        if writer.canAdd(input) { writer.add(input) }
                        writer.startWriting()
                        self.micWriter = writer
                        self.micWriterInput = input
                        self.isMicSessionStarted = false
                    }
                }
            }

            self.session.commitConfiguration()
            if !self.session.inputs.isEmpty {
                self.session.startRunning()
            }
        }
    }

    public func setPaused(_ paused: Bool) {
        sessionQueue.async { [weak self] in
            self?.isPaused = paused
        }
    }

    public func stopRecording() async -> [Float] {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                self.stopSessionInternal()

                let finishGroup = DispatchGroup()
                if let wInput = self.webcamWriterInput, let wWriter = self.webcamWriter, wWriter.status == .writing {
                    finishGroup.enter()
                    wInput.markAsFinished()
                    wWriter.finishWriting { finishGroup.leave() }
                }
                self.webcamWriter = nil
                self.webcamWriterInput = nil

                if let mInput = self.micWriterInput, let mWriter = self.micWriter, mWriter.status == .writing {
                    finishGroup.enter()
                    mInput.markAsFinished()
                    mWriter.finishWriting { finishGroup.leave() }
                }
                self.micWriter = nil
                self.micWriterInput = nil

                let peaks = self.recordedMicPeakHistory
                finishGroup.notify(queue: self.sessionQueue) {
                    continuation.resume(returning: peaks)
                }
            }
        }
    }

    private func stopSessionInternal() {
        if session.isRunning {
            session.stopRunning()
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
    }

    // MARK: - Sample Buffer Delegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer), !isPaused else { return }

        if output is AVCaptureVideoDataOutput {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ciImg = CIImage(cvPixelBuffer: pixelBuffer)
                if let cgImg = ciContext.createCGImage(ciImg, from: ciImg.extent) {
                    onWebcamFrame?(cgImg)
                }
            }
            if let writer = webcamWriter, let input = webcamWriterInput {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !isWebcamSessionStarted {
                    writer.startSession(atSourceTime: pts)
                    isWebcamSessionStarted = true
                }
                if input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }
        } else if output is AVCaptureAudioDataOutput {
            let level = Self.computeAudioRMS(sampleBuffer)
            recordedMicPeakHistory.append(level)
            onMicrophoneLevel?(level)

            if let writer = micWriter, let input = micWriterInput {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !isMicSessionStarted {
                    writer.startSession(atSourceTime: pts)
                    isMicSessionStarted = true
                }
                if input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }
        }
    }

    private static func computeAudioRMS(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0.05 }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let ptr = dataPointer, length >= 2 else { return 0.05 }

        let sampleCount = min(256, length / 2)
        let int16Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Int16.self)
        var sumSquares: Float = 0
        for i in 0..<sampleCount {
            let norm = Float(int16Ptr[i]) / Float(Int16.max)
            sumSquares += norm * norm
        }
        let rms = sqrt(sumSquares / Float(max(1, sampleCount)))
        return min(1.0, max(0.02, rms * 3.2))
    }
}
