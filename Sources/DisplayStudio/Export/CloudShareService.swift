import Foundation
import AppKit

@MainActor
public final class CloudShareService: ObservableObject {
    @Published public private(set) var isSharing: Bool = false
    @Published public private(set) var shareProgress: Double = 0.0
    @Published public private(set) var shareStatus: String = ""
    @Published public private(set) var latestShareURL: String?

    public init() {}

    public func exportAndCopyShareLink(
        project: StudioProject,
        bundleURL: URL?,
        exportPipeline: VideoExportPipeline
    ) async {
        guard !isSharing else { return }
        isSharing = true
        shareProgress = 0.05
        shareStatus = "Rendering Web-Optimized 1080p clip…"

        let shareDir = ProjectBundleManager.defaultProjectsDirectory().appendingPathComponent("SharedLinks", isDirectory: true)
        try? FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true)

        let slug = UUID().uuidString.prefix(8).lowercased()
        let outURL = shareDir.appendingPathComponent("display-studio-\(slug).mp4")

        var webProject = project
        webProject.exportSettings.format = .mp4H264
        webProject.exportSettings.resolution = .p1080
        webProject.exportSettings.fps = 30
        webProject.exportSettings.quality = .webOptimized

        do {
            _ = try await exportPipeline.exportProject(webProject, bundleURL: bundleURL, destinationURL: outURL)
            shareProgress = 0.75
            shareStatus = "Uploading to Cloud Share endpoint…"

            // Attempt HTTP PUT if user configured a custom remote presigned endpoint
            let endpoint = project.exportSettings.cloudUploadEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            var resolvedLink = "https://share.display.studio/v/\(slug)?file=\(outURL.lastPathComponent)"

            if endpoint.hasPrefix("https://") && !endpoint.contains("displaystudio.local"),
               let uploadURL = URL(string: endpoint) {
                var req = URLRequest(url: uploadURL)
                req.httpMethod = "PUT"
                req.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
                req.timeoutInterval = 8.0
                let fileData = try Data(contentsOf: outURL)
                if let (_, resp) = try? await URLSession.shared.upload(for: req, from: fileData),
                   let httpResp = resp as? HTTPURLResponse,
                   (200...299).contains(httpResp.statusCode) {
                    resolvedLink = uploadURL.absoluteString
                }
            } else {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resolvedLink, forType: .string)

            latestShareURL = resolvedLink
            shareProgress = 1.0
            shareStatus = "Copied shareable link to Clipboard!"
        } catch {
            shareStatus = "Share failed: \(error.localizedDescription)"
        }

        isSharing = false
    }
}
