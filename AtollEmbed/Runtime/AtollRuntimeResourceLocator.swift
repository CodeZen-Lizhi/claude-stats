import Foundation

struct AtollRuntimeBundleLayout {
    let bundleURL: URL
    let resourceURL: URL
    let privateFrameworksURL: URL?

    init(bundle: Bundle = .main) {
        self.bundleURL = bundle.bundleURL
        self.resourceURL = bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources")
        self.privateFrameworksURL = bundle.privateFrameworksURL
    }

    init(bundleURL: URL, resourceURL: URL, privateFrameworksURL: URL?) {
        self.bundleURL = bundleURL
        self.resourceURL = resourceURL
        self.privateFrameworksURL = privateFrameworksURL
    }

    var helpersURL: URL {
        bundleURL.appendingPathComponent("Contents/Helpers")
    }

    var defaultFrameworksURL: URL {
        bundleURL.appendingPathComponent("Contents/Frameworks")
    }
}

struct AtollRuntimeResourceLocator {
    struct MediaRemoteAdapter: Equatable {
        let scriptURL: URL
        let frameworkURL: URL

        var frameworkPath: String {
            frameworkURL.path
        }
    }

    static var main: AtollRuntimeResourceLocator {
        AtollRuntimeResourceLocator(layout: AtollRuntimeBundleLayout())
    }

    let layout: AtollRuntimeBundleLayout
    let fileManager: FileManager

    init(layout: AtollRuntimeBundleLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    func mediaRemoteAdapter() -> MediaRemoteAdapter? {
        let scriptURL = layout.resourceURL.appendingPathComponent("mediaremote-adapter.pl")

        guard fileManager.fileExists(atPath: scriptURL.path),
              let frameworkURL = mediaRemoteFrameworkURL()
        else {
            return nil
        }

        return MediaRemoteAdapter(scriptURL: scriptURL, frameworkURL: frameworkURL)
    }

    func nowPlayingTestClientPath() -> String? {
        let helperURL = layout.helpersURL.appendingPathComponent("NowPlayingTestClient")

        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            return nil
        }

        return helperURL.path
    }

    private func mediaRemoteFrameworkURL() -> URL? {
        frameworkCandidates.first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private var frameworkCandidates: [URL] {
        var urls: [URL] = []

        if let privateFrameworksURL = layout.privateFrameworksURL {
            urls.append(privateFrameworksURL.appendingPathComponent("MediaRemoteAdapter.framework"))
        }

        urls.append(layout.defaultFrameworksURL.appendingPathComponent("MediaRemoteAdapter.framework"))
        urls.append(layout.resourceURL.appendingPathComponent("MediaRemoteAdapter.framework"))

        return urls.removingDuplicatesByPath()
    }
}

private extension Array where Element == URL {
    func removingDuplicatesByPath() -> [URL] {
        var seen: Set<String> = []
        return filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
