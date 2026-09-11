import SwiftUI

/// 飞船选择器
struct FittingShipSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showSelected = false
    @Environment(\.dismiss) private var dismiss

    /// Ships 市场分组根（选择器会自动下钻到其子分组）
    private static let shipMarketGroupID: Set<Int> = [4]

    let onSelect: (DatabaseListItem) -> Void

    init(databaseManager: DatabaseManager, onSelect: @escaping (DatabaseListItem) -> Void) {
        self.databaseManager = databaseManager
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Fitting_Select_Ship", comment: "选择舰船"),
                allowedMarketGroups: Self.shipMarketGroupID,
                allowTypeIDs: [],
                existingItems: Set<Int>(),
                onItemSelected: { ship in
                    dismiss()
                    onSelect(ship)
                },
                onItemDeselected: { _ in },
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
            .interactiveDismissDisabled()
        }
    }
}
