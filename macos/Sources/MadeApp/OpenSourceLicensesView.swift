import SwiftUI
import MadeCore

/// Displays the Open Source Licenses window with the `made` license, bundled dependencies, and source/build links.
struct OpenSourceLicensesView: View {
    static let windowID = "open-source-licenses"

    private let catalogResult: Result<LicenseCatalog, LicenseCatalogError>
    @State private var selectedEntryID: String?
    @State private var filterText = ""

    init() {
        do {
            let catalog = try LicenseCatalog.loadBundled()
            self.catalogResult = .success(catalog)
            self._selectedEntryID = State(initialValue: catalog.entries.first?.id)
        } catch let error as LicenseCatalogError {
            self.catalogResult = .failure(error)
            self._selectedEntryID = State(initialValue: nil)
        } catch {
            self.catalogResult = .failure(.invalidManifest(error.localizedDescription))
            self._selectedEntryID = State(initialValue: nil)
        }
    }

    var body: some View {
        switch catalogResult {
        case .success(let catalog):
            catalogContent(catalog)
        case .failure(let error):
            ContentUnavailableView(
                "Open Source Licenses Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error.description)
            )
            .frame(minWidth: 640, minHeight: 420)
        }
    }

    @ViewBuilder
    private func catalogContent(_ catalog: LicenseCatalog) -> some View {
        let filtered = catalog.entries(matching: filterText)
        let activeEntry = filtered.first(where: { $0.id == selectedEntryID }) ?? filtered.first

        NavigationSplitView {
            List(selection: $selectedEntryID) {
                let apps = filtered.filter { $0.kind == .application }
                if !apps.isEmpty {
                    Section("Application") {
                        ForEach(apps) { entry in
                            entryRow(entry).tag(entry.id)
                        }
                    }
                }

                let packages = filtered.filter { $0.kind == .package }
                if !packages.isEmpty {
                    Section("Libraries") {
                        ForEach(packages) { entry in
                            entryRow(entry).tag(entry.id)
                        }
                    }
                }

                let helpers = filtered.filter { $0.kind == .helper }
                if !helpers.isEmpty {
                    Section("Helper Programs") {
                        ForEach(helpers) { entry in
                            entryRow(entry).tag(entry.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: filterText)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    BarFilterField(text: $filterText)
                }
                .barControl()
                .padding(.horizontal, 10)
                .frame(height: BarMetrics.height)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                sourceLinksHeader(catalog)
                Divider()
                if let entry = activeEntry {
                    entryDetail(entry)
                } else {
                    ContentUnavailableView(
                        "No Component Selected",
                        systemImage: "doc.text",
                        description: Text("Select a component to read its license text.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 440, ideal: 560)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private func entryRow(_ entry: LicenseEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text("\(entry.version) · \(entry.spdxIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func sourceLinksHeader(_ catalog: LicenseCatalog) -> some View {
        HStack(spacing: 16) {
            Link(destination: catalog.sourceURL) {
                Label("Source Repository", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: catalog.buildFromSourceGuideURL) {
                Label("Build-from-Source Guide", systemImage: "hammer")
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func entryDetail(_ entry: LicenseEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.title2.bold())
                    Text("v\(entry.version)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                    Text(entry.spdxIdentifier)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    Link(destination: entry.homepageURL) {
                        Label("Homepage", systemImage: "arrow.up.right.square")
                            .font(.callout)
                    }
                }
                Text(entry.copyright)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(entry.licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}
