import Foundation
import AppKit

@MainActor
final class OrganizerViewModel: ObservableObject {
    @Published var sourcePath: String = ""
    @Published var destinationPath: String = ""
    @Published var isRunning = false
    @Published var isScanning = false
    @Published var progressCurrent = 0
    @Published var progressTotal = 0
    @Published var currentFileName = ""
    @Published var logLines: [String] = []
    @Published var summary = ""

    @Published private(set) var scannedFiles: [URL] = []
    @Published private(set) var extensionCounts: [(ext: String, count: Int)] = []
    @Published var selectedExtensions: Set<String> = []

    var canStart: Bool {
        !sourcePath.isEmpty && !destinationPath.isEmpty && !isScanning
            && !isRunning && !selectedExtensions.isEmpty
    }

    private var cancelToken: CancelToken?
    private var scanToken = UUID()

    func pickSource() {
        if let url = Self.pickFolder(title: "Sélectionner la source (carte mémoire)") {
            sourcePath = url.path
            scanSource()
        }
    }

    func pickDestination() {
        if let url = Self.pickFolder(title: "Sélectionner la destination") {
            destinationPath = url.path
        }
    }

    func setExtension(_ ext: String, selected: Bool) {
        if selected {
            selectedExtensions.insert(ext)
        } else {
            selectedExtensions.remove(ext)
        }
    }

    private func scanSource() {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        scannedFiles = []
        extensionCounts = []
        selectedExtensions = []

        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let thisScan = UUID()
        scanToken = thisScan
        isScanning = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let files = Organizer.scanFiles(source: sourceURL)
            let counts = Organizer.extensionCounts(for: files)
            await MainActor.run { [weak self] in
                guard let self, self.scanToken == thisScan else { return }
                self.scannedFiles = files
                self.extensionCounts = counts
                self.selectedExtensions = Set(counts.map(\.ext))
                self.isScanning = false
            }
        }
    }

    func start() {
        guard !sourcePath.isEmpty, !destinationPath.isEmpty else {
            logLines.append("⚠️ Veuillez sélectionner une source et une destination.")
            return
        }
        guard !selectedExtensions.isEmpty else {
            logLines.append("⚠️ Veuillez sélectionner au moins un type de fichier.")
            return
        }

        let destURL = URL(fileURLWithPath: destinationPath)
        let filesToCopy = scannedFiles.filter { selectedExtensions.contains(Organizer.extensionKey(for: $0)) }

        logLines.removeAll()
        summary = ""
        progressCurrent = 0
        progressTotal = 0
        currentFileName = ""
        isRunning = true

        let token = CancelToken()
        cancelToken = token

        Task.detached(priority: .userInitiated) { [weak self] in
            let stats = await Organizer.organize(
                files: filesToCopy,
                destinationRoot: destURL,
                isCancelled: { token.isCancelled },
                progress: { current, total, name in
                    Task { @MainActor in
                        self?.progressCurrent = current
                        self?.progressTotal = total
                        self?.currentFileName = name
                    }
                },
                log: { message in
                    Task { @MainActor in
                        self?.logLines.append(message)
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.summary = "Terminé — \(stats.copied) copié(s), \(stats.skipped) ignoré(s), \(stats.errors) erreur(s)"
            }
        }
    }

    func cancel() {
        cancelToken?.cancel()
    }

    func clearLog() {
        logLines.removeAll()
        summary = ""
        progressCurrent = 0
        progressTotal = 0
        currentFileName = ""
    }

    private static func pickFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
