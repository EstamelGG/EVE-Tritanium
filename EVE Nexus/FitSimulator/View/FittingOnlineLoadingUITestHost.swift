#if DEBUG
    import SwiftUI
    import Zip

    /// Exercises the production page against bundled SDE and a deterministic network/cache boundary.
    @MainActor
    private final class OnlineFittingUIFixture: ObservableObject {
        @Published var ready = false
        @Published var error: String?
        @Published var requests = 0
        @Published var networkRequests = 0
        @Published var cache: [CharacterFitting]?

        func prepare() async {
            do {
                try await Task.detached {
                    let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("sde")
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    guard let zip = Bundle.main.url(forResource: "sde", withExtension: "zip") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try Zip.unzipFile(zip, destination: destination, overwrite: true, password: nil)
                    DatabaseManager.shared.loadDatabase()
                }.value
                ready = true
            } catch {
                self.error = error.localizedDescription
            }
        }

        func fetch(characterID _: Int, forceRefresh: Bool) async throws -> [CharacterFitting] {
            requests += 1
            if !forceRefresh, let cache {
                return cache
            }
            networkRequests += 1
            try await Task.sleep(for: .milliseconds(400))
            let fittings = [CharacterFitting(description: "", fitting_id: 123, items: [], name: "UI online fit", ship_type_id: 587)]
            cache = fittings
            return fittings
        }
    }

    struct FittingOnlineLoadingUITestHost: View {
        @StateObject private var fixture = OnlineFittingUIFixture()

        var body: some View {
            NavigationStack {
                List {
                    if fixture.ready {
                        NavigationLink {
                            FittingMainView(characterId: 9_999_010, databaseManager: .shared, fetchOnlineFittings: fixture.fetch)
                        } label: {
                            Text(verbatim: "Open fittings")
                        }
                        .accessibilityIdentifier("fixture.openFittings")
                    } else if let error = fixture.error {
                        Text(error)
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle(Text(verbatim: "Fixture home"))
            }
            .overlay(alignment: .bottom) {
                Text(verbatim: "requests=\(fixture.requests) network=\(fixture.networkRequests) cached=\(fixture.cache != nil)")
                    .font(.caption)
                    .accessibilityIdentifier("fixture.loading.status")
                    .allowsHitTesting(false)
            }
            .environment(\.locale, Locale(identifier: "en"))
            .task { await fixture.prepare() }
        }
    }
#endif
