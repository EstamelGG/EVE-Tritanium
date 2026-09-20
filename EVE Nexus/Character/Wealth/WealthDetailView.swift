import SwiftUI

struct WealthDetailView: View {
    let title: String
    let wealthType: WealthType
    @StateObject private var viewModel: CharacterWealthViewModel
    @State private var itemInfos: [[String: Any]] = []
    @State private var isLoading = true
    @State private var itemsWithoutPrice: [NoMarketPriceItem] = []
    @State private var hasInitialized = false // 追踪是否已执行初始化

    struct NoMarketPriceItem: Identifiable {
        let id: Int
        let typeId: Int
        let quantity: Int
        var name: String = ""
        var iconFileName: String = ""
    }

    init(
        title: String, valuedItems _: [ValuedItem], viewModel: CharacterWealthViewModel,
        wealthType: WealthType
    ) {
        self.title = title
        self.wealthType = wealthType
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var valuedItems: [ValuedItem] {
        switch wealthType {
        case .assets:
            return viewModel.valuedAssets
        case .implants:
            return viewModel.valuedImplants
        case .orders:
            return viewModel.valuedOrders
        case .contracts:
            return []
        case .wallet:
            return []
        }
    }

    private func getItemInfo(typeId: Int) -> (name: String, iconFileName: String)? {
        if let row = itemInfos.first(where: { ($0["type_id"] as? Int) == typeId }) {
            return (
                name: row["name"] as? String ?? "Unknown Item",
                iconFileName: row["icon_filename"] as? String ?? ""
            )
        }
        return nil
    }

    /// 初始化数据加载方法
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true

        // 根据不同类型加载数据
        switch wealthType {
        case .assets:
            await viewModel.loadAssetDetails()
        case .implants:
            await viewModel.loadImplantDetails()
        case .orders:
            await viewModel.loadOrderDetails()
        case .contracts:
            await viewModel.loadContractDetails()
        case .wallet:
            break
        }

        // 加载物品信息（合同详情按合同展示，无需物品信息）
        if wealthType != .contracts {
            let typeIds = valuedItems.map { $0.typeId }
            itemInfos = viewModel.getItemsInfo(typeIds: typeIds)
        }

        // 只在资产类型时加载无市场价格的物品
        if wealthType == .assets {
            itemsWithoutPrice = await viewModel.getItemsWithoutPrice()
        }

        isLoading = false
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(NSLocalizedString("Wealth_Detail_Loading", comment: ""))
                    Spacer()
                }
            } else if wealthType == .contracts {
                contractsSection
            } else {
                itemsSection
            }

            if wealthType == .assets && !itemsWithoutPrice.isEmpty {
                noPriceItemsSection
            }

            if shouldShowEmptyState {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Misc_No_Data", comment: ""))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle(
            String.localizedStringWithFormat(NSLocalizedString("Wealth_Detail_Title", comment: ""), title)
        )
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .refreshable {
            await loadData()
        }
    }

    private var shouldShowEmptyState: Bool {
        if isLoading {
            return false
        }
        switch wealthType {
        case .contracts:
            return viewModel.valuedContracts.isEmpty
        case .assets:
            return valuedItems.isEmpty && itemsWithoutPrice.isEmpty
        default:
            return valuedItems.isEmpty
        }
    }

    @ViewBuilder
    private var contractsSection: some View {
        if !viewModel.valuedContracts.isEmpty {
            Section(header: Text(NSLocalizedString("Wealth_Contracts_Top", comment: ""))) {
                ForEach(viewModel.valuedContracts) { valuedContract in
                    NavigationLink {
                        ContractDetailView(
                            characterId: viewModel.characterId,
                            contract: valuedContract.contract,
                            databaseManager: viewModel.databaseManager,
                            contractType: PersonalContractsViewModel.ContractType.personal
                        )
                    } label: {
                        HStack {
                            Image("contractitemexchange")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(valuedContract.itemsSummary)
                                    .lineLimit(1)
                                Text(valuedContract.titleSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(FormatUtil.formatISK(valuedContract.price))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = valuedContract.titleSubtitle
                            } label: {
                                Label(
                                    NSLocalizedString("Contract_Title", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if !valuedItems.isEmpty {
            Section(header: Text(NSLocalizedString("Wealth_Detail_HasPrice", comment: ""))) {
                ForEach(
                    valuedItems.sorted(by: {
                        if $0.totalValue != $1.totalValue {
                            return $0.totalValue > $1.totalValue
                        }
                        return $0.typeId < $1.typeId
                    }),
                    id: \.identifier
                ) { item in
                    if let itemInfo = getItemInfo(typeId: item.typeId) {
                        NavigationLink {
                            MarketItemDetailView(
                                databaseManager: DatabaseManager(), itemID: item.typeId
                            )
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: itemInfo.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(itemInfo.name)
                                    Text(
                                        "\(item.quantity) × \(FormatUtil.formatISK(item.value))"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(FormatUtil.formatISK(item.totalValue))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }.contextMenu {
                                Button {
                                    UIPasteboard.general.string = itemInfo.name
                                } label: {
                                    Label(
                                        NSLocalizedString(
                                            "Misc_Copy_Item_Name", comment: ""
                                        ),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    private var noPriceItemsSection: some View {
        Section(header: Text(NSLocalizedString("Wealth_Detail_NoPrice", comment: ""))) {
            ForEach(
                itemsWithoutPrice.sorted(by: {
                    if $0.quantity != $1.quantity {
                        return $0.quantity > $1.quantity
                    }
                    return $0.typeId < $1.typeId
                })
            ) { item in
                NavigationLink {
                    MarketItemDetailView(
                        databaseManager: DatabaseManager(), itemID: item.typeId
                    )
                } label: {
                    HStack {
                        IconManager.shared.loadImage(for: item.iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("\(item.quantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }.contextMenu {
                        Button {
                            UIPasteboard.general.string = item.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}
