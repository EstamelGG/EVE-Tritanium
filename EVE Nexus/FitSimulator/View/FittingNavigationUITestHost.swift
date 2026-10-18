#if DEBUG
    import SwiftUI

    /// Exercises the production catalog's nested navigation without accounts, files or ESI calls.
    struct FittingNavigationUITestHost: View {
        @State private var isDeleting = false
        private let localID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

        private var ships: [FittingShipNode] {
            [FittingShipNode(typeId: 1, shipInfo: FittingShipInfo(names: .filled(with: "Ship A"), iconFileName: "not_found"), fittings: [
                FittingItemNode(ref: .local(localID), name: "Local A", shipTypeId: 1),
                FittingItemNode(ref: .local(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!), name: "Local B", shipTypeId: 1),
            ]), FittingShipNode(typeId: 2, shipInfo: FittingShipInfo(names: .filled(with: "Ship B"), iconFileName: "not_found"), fittings: [
                FittingItemNode(ref: .online(123), name: "Online A", shipTypeId: 2),
            ])]
        }

        var body: some View {
            NavigationStack {
                List {
                    NavigationLink(value: FittingGroupNode(groupID: 1, groupName: "Frigates", firstIconFileName: nil, fittingCount: 3, children: ships)) {
                        Text("Frigates")
                    }
                    .accessibilityIdentifier("fixture.group")
                }
                .navigationTitle("Fittings")
                .navigationDestination(for: FittingGroupNode.self) { group in
                    FittingShipSectionsView(ships: group.children, source: .local, isDeleting: $isDeleting,
                                            onDelete: { _, _ in [] })
                    { item in
                        NavigationLink(value: item.ref) {
                            FittingCatalogRow(name: item.name, iconFileName: "not_found")
                        }
                        .accessibilityIdentifier("fixture.row.\(item.name)")
                    }
                    .navigationTitle(group.groupName)
                }
                .navigationDestination(for: FittingRef.self) { ref in
                    Text(ref.debugDescription)
                        .accessibilityIdentifier("fixture.detail")
                        .navigationTitle("Fitting Detail")
                }
            }
            .environment(\.locale, Locale(identifier: "en"))
        }
    }
#endif
