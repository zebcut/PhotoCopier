import SwiftUI

struct ContentView: View {
    @StateObject private var vm = OrganizerViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 640)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PhotoCopier")
                    .font(.title2).bold()
                Text("Classe vos photos par date de création")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("SOURCE (carte mémoire)")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                HStack {
                    Text(vm.sourcePath.isEmpty ? "Aucun dossier sélectionné" : vm.sourcePath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(vm.sourcePath.isEmpty ? .secondary : .primary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                Button("Parcourir la source…") { vm.pickSource() }
                    .frame(maxWidth: .infinity)
            }

            extensionSection

            VStack(alignment: .leading, spacing: 6) {
                Text("DESTINATION")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                HStack {
                    Text(vm.destinationPath.isEmpty ? "Aucun dossier sélectionné" : vm.destinationPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(vm.destinationPath.isEmpty ? .secondary : .primary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                Button("Parcourir la destination…") { vm.pickDestination() }
                    .frame(maxWidth: .infinity)
            }

            Text("Arborescence créée : AAAA / MM / JJ")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if vm.isRunning {
                Button("⏹  Annuler") { vm.cancel() }
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .tint(.red)
            } else {
                Button("▶  Démarrer") { vm.start() }
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canStart)
            }
        }
        .padding(20)
    }

    // MARK: - File type checkboxes

    private var extensionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TYPES DE FICHIERS")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.isScanning {
                    ProgressView().controlSize(.mini)
                } else if !vm.extensionCounts.isEmpty {
                    Text("\(vm.selectedExtensions.count)/\(vm.extensionCounts.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.isScanning {
                Text("Analyse du dossier source…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.extensionCounts.isEmpty {
                Text("Sélectionnez une source pour lister les types de fichiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.extensionCounts, id: \.ext) { item in
                            Toggle(isOn: Binding(
                                get: { vm.selectedExtensions.contains(item.ext) },
                                set: { vm.setExtension(item.ext, selected: $0) }
                            )) {
                                Text("\(displayExtension(item.ext))  (\(item.count))")
                                    .font(.caption)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private func displayExtension(_ ext: String) -> String {
        ext.isEmpty ? "(sans extension)" : "." + ext.uppercased()
    }

    // MARK: - Main area

    private var mainArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progression").font(.headline)
                ProgressView(
                    value: Double(vm.progressCurrent),
                    total: Double(max(vm.progressTotal, 1))
                )
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Journal d'activité").font(.headline)
                    Spacer()
                    Button("Effacer") { vm.clearLog() }
                }
                .padding(12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(vm.logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .id(index)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: vm.logLines.count) { _, _ in
                        if let last = vm.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxHeight: .infinity)
        }
        .padding(16)
    }

    private var progressLabel: String {
        if !vm.summary.isEmpty { return vm.summary }
        if vm.progressTotal == 0 { return "En attente…" }
        let pct = Int(Double(vm.progressCurrent) / Double(vm.progressTotal) * 100)
        return "\(vm.currentFileName) — \(vm.progressCurrent)/\(vm.progressTotal) (\(pct)%)"
    }
}
