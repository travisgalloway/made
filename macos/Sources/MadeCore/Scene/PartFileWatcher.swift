import Foundation
import Darwin

/// Immutable byte-level snapshot of a `.part.ts` or `.part.js` file and any transitive relative modules it references inside its directory (#427).
public struct PartDependencySnapshot: Sendable, Equatable {
    public struct FileEntry: Sendable, Equatable {
        public let path: String
        public let exists: Bool
        public let contents: Data

        public init(path: String, exists: Bool, contents: Data) {
            self.path = path
            self.exists = exists
            self.contents = contents
        }
    }

    public let rootFileURL: URL
    public let entries: [FileEntry]
    public let watchedFileURLs: Set<URL>
    public let watchedDirectoryURLs: Set<URL>

    /// Captures the current contents and existence of `rootFileURL`, any `additionalFilePaths`,
    /// and any transitive relative imports (`./...` or `../...`) inside the part's directory.
    public static func capture(
        rootFileURL: URL,
        additionalFilePaths: Set<String> = []
    ) -> PartDependencySnapshot {
        let canonicalRootFile = Self.canonicalURL(for: rootFileURL)
        let rootDirURL = canonicalRootFile.deletingLastPathComponent()
        let rootDirPath = rootDirURL.path.hasSuffix("/") ? rootDirURL.path : rootDirURL.path + "/"
        let rootDirWithoutSlash = String(rootDirPath.dropLast())

        var worklist: [URL] = [canonicalRootFile]
        for extraPath in additionalFilePaths.sorted() {
            let extraURL = Self.canonicalURL(for: URL(fileURLWithPath: extraPath))
            if extraURL.path == rootDirWithoutSlash || extraURL.path.hasPrefix(rootDirPath) {
                worklist.append(extraURL)
            }
        }

        var visitedFiles: Set<String> = []
        var entriesByPath: [String: FileEntry] = [:]
        var watchedFiles: Set<URL> = [canonicalRootFile]
        var watchedDirs: Set<URL> = [rootDirURL]

        let candidateSuffixes = ["", ".part.ts", ".ts", ".part.js", ".js"]
        let fm = FileManager.default

        var index = 0
        while index < worklist.count {
            let currentURL = worklist[index]
            index += 1

            let path = currentURL.path
            guard visitedFiles.insert(path).inserted else { continue }

            watchedFiles.insert(currentURL)
            watchedDirs.insert(currentURL.deletingLastPathComponent())

            let data = try? Data(contentsOf: currentURL)
            entriesByPath[path] = FileEntry(
                path: path,
                exists: data != nil,
                contents: data ?? Data()
            )

            guard let data, let sourceText = String(data: data, encoding: .utf8) else {
                continue
            }

            let baseDir = currentURL.deletingLastPathComponent()
            for specifier in Self.extractRelativeImportSpecifiers(from: sourceText) {
                let rawTarget = URL(fileURLWithPath: specifier, relativeTo: baseDir).standardizedFileURL
                let rawPath = rawTarget.path
                guard rawPath == rootDirWithoutSlash || rawPath.hasPrefix(rootDirPath) else {
                    continue
                }

                let parentDir = rawTarget.deletingLastPathComponent()
                if parentDir.path == rootDirWithoutSlash || parentDir.path.hasPrefix(rootDirPath) {
                    watchedDirs.insert(parentDir)
                }

                var matchedFileURL: URL? = nil
                for suffix in candidateSuffixes {
                    let candidate = suffix.isEmpty
                        ? rawTarget
                        : URL(fileURLWithPath: rawTarget.path + suffix)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
                        if resolved.path.hasPrefix(rootDirPath) {
                            matchedFileURL = resolved
                            break
                        }
                    }
                }

                if let matchedFileURL {
                    if !visitedFiles.contains(matchedFileURL.path) {
                        worklist.append(matchedFileURL)
                    }
                } else {
                    // Record the missing import target so creating it later changes the snapshot.
                    let missingKey = rawTarget.path
                    if entriesByPath[missingKey] == nil {
                        entriesByPath[missingKey] = FileEntry(path: missingKey, exists: false, contents: Data())
                    }
                }
            }
        }

        let sortedEntries = entriesByPath.keys.sorted().compactMap { entriesByPath[$0] }
        return PartDependencySnapshot(
            rootFileURL: canonicalRootFile,
            entries: sortedEntries,
            watchedFileURLs: watchedFiles,
            watchedDirectoryURLs: watchedDirs
        )
    }

    private static func canonicalURL(for url: URL) -> URL {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath()
        }
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(standardized.lastPathComponent, isDirectory: false)
    }

    /// Extracts relative module specifiers (`./...` or `../...`) from ES `import` / `export ... from` statements.
    private static func extractRelativeImportSpecifiers(from source: String) -> [String] {
        let pattern = #/(?:from|import)\s*['"](\.\.?/[^'"]+)['"]/#
        var results: [String] = []
        for match in source.matches(of: pattern) {
            results.append(String(match.1))
        }
        return results
    }
}

/// Watches a part source file, its imported helper files, and their containing directories using `DispatchSourceFileSystemObject` (`EVFILT_VNODE`).
/// Handles both in-place writes and atomic temp-file rename saves (`write(to:atomically:true)`).
public final class PartFileWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let onEvent: @Sendable () -> Void
    private var isStopped = false

    private var desiredFilePaths: Set<String> = []
    private var desiredDirectoryPaths: Set<String> = []
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]

    public init(
        fileURL: URL,
        additionalFileURLs: Set<URL> = [],
        additionalDirectoryURLs: Set<URL> = [],
        onEvent: @escaping @Sendable () -> Void
    ) {
        self.queue = DispatchQueue(label: "com.made.part-file-watcher.\(UUID().uuidString)", qos: .userInitiated)
        self.onEvent = onEvent

        let snapshot = PartDependencySnapshot.capture(
            rootFileURL: fileURL,
            additionalFilePaths: Set(additionalFileURLs.map(\.path))
        )
        let files = snapshot.watchedFileURLs.union(additionalFileURLs)
        let dirs = snapshot.watchedDirectoryURLs.union(additionalDirectoryURLs)

        lock.withLock {
            self.desiredFilePaths = Set(files.map(\.path))
            self.desiredDirectoryPaths = Set(dirs.map(\.path))
            self.syncSourcesLocked()
        }
    }

    deinit {
        stop()
    }

    /// Updates the set of watched file and directory URLs (for example when a part adds or removes a relative import).
    public func updateWatchedTargets(fileURLs: Set<URL>, directoryURLs: Set<URL>) {
        lock.withLock {
            guard !isStopped else { return }
            self.desiredFilePaths = Set(fileURLs.map(\.path))
            self.desiredDirectoryPaths = Set(directoryURLs.map(\.path))
            self.syncSourcesLocked()
        }
    }

    /// Cancels all active `DispatchSource` descriptors and stops emitting events.
    public func stop() {
        let toCancel: [DispatchSourceFileSystemObject] = lock.withLock {
            guard !isStopped else { return [] }
            isStopped = true
            let all = Array(fileSources.values) + Array(directorySources.values)
            fileSources.removeAll()
            directorySources.removeAll()
            desiredFilePaths.removeAll()
            desiredDirectoryPaths.removeAll()
            return all
        }
        for source in toCancel {
            source.cancel()
        }
    }

    // MARK: - Internal Descriptor Management

    private func syncSourcesLocked() {
        guard !isStopped else { return }

        // Remove stale file sources
        for (path, source) in Array(fileSources) where !desiredFilePaths.contains(path) {
            fileSources.removeValue(forKey: path)
            source.cancel()
        }

        // Remove stale directory sources
        for (path, source) in Array(directorySources) where !desiredDirectoryPaths.contains(path) {
            directorySources.removeValue(forKey: path)
            source.cancel()
        }

        // Attach directory sources first so atomic renames and file creations in those directories are always observed
        for dirPath in desiredDirectoryPaths where directorySources[dirPath] == nil {
            if let source = makeDirectorySourceLocked(path: dirPath) {
                directorySources[dirPath] = source
            }
        }

        // Attach file sources for every desired file that currently exists on disk
        for filePath in desiredFilePaths where fileSources[filePath] == nil {
            if let source = makeFileSourceLocked(path: filePath) {
                fileSources[filePath] = source
            }
        }
    }

    private func makeFileSourceLocked(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        source.setCancelHandler {
            close(fd)
        }
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            let flags = source?.data ?? []
            self.handleFileDescriptorEvent(path: path, flags: flags)
        }
        source.resume()
        return source
    }

    private func makeDirectorySourceLocked(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: queue
        )
        source.setCancelHandler {
            close(fd)
        }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.handleDirectoryDescriptorEvent()
        }
        source.resume()
        return source
    }

    private func handleFileDescriptorEvent(path: String, flags: DispatchSource.FileSystemEvent) {
        let shouldNotify: Bool = lock.withLock {
            guard !isStopped else { return false }
            // When an editor or agent saves atomically (write temp + rename), the old inode gets .delete or .rename.
            // Cancel the old descriptor and re-open at the path if the new inode is in place.
            if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
                if let old = fileSources.removeValue(forKey: path) {
                    old.cancel()
                }
                if desiredFilePaths.contains(path), let replacement = makeFileSourceLocked(path: path) {
                    fileSources[path] = replacement
                }
            }
            return true
        }
        if shouldNotify {
            onEvent()
        }
    }

    private func handleDirectoryDescriptorEvent() {
        let shouldNotify: Bool = lock.withLock {
            guard !isStopped else { return false }
            // Re-attach file sources for any watched files that were recreated or atomically replaced.
            for filePath in desiredFilePaths where fileSources[filePath] == nil {
                if let source = makeFileSourceLocked(path: filePath) {
                    fileSources[filePath] = source
                }
            }
            return true
        }
        if shouldNotify {
            onEvent()
        }
    }
}
