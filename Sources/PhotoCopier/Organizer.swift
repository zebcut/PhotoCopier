import Foundation
import CryptoKit
import ImageIO
import AVFoundation

struct OrganizeStats {
    var copied = 0
    var skipped = 0
    var errors = 0
    var total = 0
}

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

enum Organizer {
    static func scanFiles(source: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                results.append(fileURL)
            }
        }
        return results
    }

    static func extensionKey(for url: URL) -> String {
        url.pathExtension.lowercased()
    }

    static func extensionCounts(for files: [URL]) -> [(ext: String, count: Int)] {
        var counts: [String: Int] = [:]
        for file in files {
            counts[extensionKey(for: file), default: 0] += 1
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (ext: $0.key, count: $0.value) }
    }

    static let unknownDateFolder = "dateUnknown"

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts", "3gp"]

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    // Reads the shooting date embedded in image metadata (EXIF DateTimeOriginal, falling back
    // to TIFF DateTime). Neither tag carries a timezone, so it's interpreted in the system's
    // current timezone — the same assumption cameras make when they stamp local wall-clock time.
    static func exifDate(of url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String

        guard let raw else { return nil }
        return exifDateFormatter.date(from: raw)
    }

    // Reads the capture date embedded in video container metadata (QuickTime/MP4 creation date).
    static func videoCreationDate(of url: URL) async -> Date? {
        guard let item = try? await AVURLAsset(url: url).load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    // Metadata embedded in the file itself (EXIF for photos, container metadata for videos) —
    // reflects the actual shooting date regardless of any later copy/export/sync that would
    // otherwise reset the filesystem creation date.
    static func capturedDate(of url: URL) async -> Date? {
        if videoExtensions.contains(extensionKey(for: url)) {
            return await videoCreationDate(of: url)
        }
        return exifDate(of: url)
    }

    // Filesystem date, used only when no embedded capture metadata is available. Modification
    // date is checked first: copy/export/sync tools conventionally preserve it, while the
    // creation date (st_birthtime) is usually reset to the moment of that copy — reading creation
    // date first previously misfiled photos under the export date instead of the shooting date.
    // Falls back to creation date, then nil if neither resource value is readable.
    static func fileSystemDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.contentModificationDate ?? values?.creationDate
    }

    // Best available date for sorting: embedded capture metadata first, filesystem date otherwise.
    static func resolvedDate(of url: URL) async -> Date? {
        if let captured = await capturedDate(of: url) {
            return captured
        }
        return fileSystemDate(of: url)
    }

    static func checksum(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func uniquePath(_ path: URL, fm: FileManager) -> URL {
        let ext = path.pathExtension
        let stem = path.deletingPathExtension().lastPathComponent
        let dir = path.deletingLastPathComponent()
        var counter = 1
        while true {
            let name = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    static func relativeDir(for date: Date) -> [String] {
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return [
            String(comps.year ?? 1970),
            String(format: "%02d", comps.month ?? 1),
            String(format: "%02d", comps.day ?? 1),
        ]
    }

    static func organize(
        files: [URL],
        destinationRoot: URL,
        isCancelled: @escaping () -> Bool,
        progress: @escaping (Int, Int, String) -> Void,
        log: @escaping (String) -> Void
    ) async -> OrganizeStats {
        var stats = OrganizeStats()
        let fm = FileManager.default
        stats.total = files.count
        log("\(files.count) fichier(s) à traiter.")

        for (index, fileURL) in files.enumerated() {
            if isCancelled() {
                log("⛔ Opération annulée.")
                break
            }
            progress(index, files.count, fileURL.lastPathComponent)

            let date = await resolvedDate(of: fileURL)
            var destDir = destinationRoot
            if let date {
                for component in relativeDir(for: date) {
                    destDir.appendPathComponent(component)
                }
            } else {
                destDir.appendPathComponent(unknownDateFolder)
            }
            var destFile = destDir.appendingPathComponent(fileURL.lastPathComponent)
            var renamed = false

            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                if fm.fileExists(atPath: destFile.path) {
                    if try checksum(of: fileURL) == checksum(of: destFile) {
                        stats.skipped += 1
                        log("⏭ Ignoré (identique) : \(fileURL.lastPathComponent)")
                        continue
                    }
                    destFile = uniquePath(destFile, fm: fm)
                    renamed = true
                }

                try fm.copyItem(at: fileURL, to: destFile)
                stats.copied += 1
                if renamed {
                    log("✓ Copié (renommé, doublon différent) : \(fileURL.lastPathComponent) → \(destFile.lastPathComponent)")
                } else {
                    log("✓ Copié : \(fileURL.lastPathComponent) → \(destDir.path)")
                }
            } catch {
                stats.errors += 1
                log("✗ Erreur (\(fileURL.lastPathComponent)) : \(error.localizedDescription)")
            }
        }

        progress(files.count, files.count, "Terminé")
        return stats
    }
}
