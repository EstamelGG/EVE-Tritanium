import Foundation
import SwiftUI

struct MarketQuickbarView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var quickbars: [MarketQuickbar] = []
    @State private var isShowingAddAlert = false
    @State private var newQuickbarName = ""
    @State private var searchText = ""
    @State private var isShowingRenameAlert = false
    @State private var renameQuickbar: MarketQuickbar?
    @State private var renameQuickbarName = ""
    @State private var quickbarToDelete: MarketQuickbar?
    /// 新建列表后自动导航进入该列表（非 nil 时触发 push 详情页）
    @State private var autoNavigateQuickbarID: UUID?

    private var filteredQuickbars: [MarketQuickbar] {
        if searchText.isEmpty {
            return quickbars
        } else {
            return quickbars.filter { quickbar in
                quickbar.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        quickbarList
            .searchable(
                text: $searchText,
                prompt: NSLocalizedString("Main_Database_Search", comment: "")
            )
            .navigationDestination(item: $autoNavigateQuickbarID) { id in
                if let quickbar = quickbars.first(where: { $0.id == id }) {
                    MarketQuickbarDetailView(
                        databaseManager: databaseManager,
                        quickbar: quickbar
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Main_Market_Watch_List", comment: ""))
            .toolbar {
                if #available(iOS 26.0, *) {
                    // iOS 26：搜索框与添加按钮共处底部同一 Liquid Glass 行（搜索框左、+ 右）
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        addQuickbarButton
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        addQuickbarButton
                    }
                }
            }
            .alert(
                NSLocalizedString("Main_Market_Watch_List_Add", comment: ""),
                isPresented: $isShowingAddAlert
            ) {
                TextField(
                    NSLocalizedString("Main_Market_Watch_List_Name", comment: ""),
                    text: $newQuickbarName
                )

                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    if !newQuickbarName.isEmpty {
                        let newQuickbar = MarketQuickbar(
                            name: newQuickbarName,
                            items: []
                        )
                        quickbars.append(newQuickbar)
                        MarketQuickbarManager.shared.saveQuickbar(newQuickbar)
                        newQuickbarName = ""
                        // 新建成功后自动进入该列表
                        autoNavigateQuickbarID = newQuickbar.id
                    }
                }
                .disabled(newQuickbarName.isEmpty)

                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    newQuickbarName = ""
                }
            }
            .alert(NSLocalizedString("Misc_Rename", comment: ""), isPresented: $isShowingRenameAlert) {
                TextField(NSLocalizedString("Misc_Name", comment: ""), text: $renameQuickbarName)

                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    if let quickbar = renameQuickbar, !renameQuickbarName.isEmpty {
                        if let index = quickbars.firstIndex(where: { $0.id == quickbar.id }) {
                            quickbars[index].name = renameQuickbarName
                            MarketQuickbarManager.shared.saveQuickbar(quickbars[index])
                        }
                    }
                    renameQuickbar = nil
                    renameQuickbarName = ""
                }
                .disabled(renameQuickbarName.isEmpty)

                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    renameQuickbar = nil
                    renameQuickbarName = ""
                }
            }
            .alert(
                NSLocalizedString("Misc_Delete", comment: ""),
                isPresented: Binding(
                    get: { quickbarToDelete != nil },
                    set: { if !$0 { quickbarToDelete = nil } }
                ),
                presenting: quickbarToDelete
            ) { quickbar in
                Button(NSLocalizedString("Misc_Delete", comment: ""), role: .destructive) {
                    deleteQuickbar(quickbar)
                    quickbarToDelete = nil
                }
                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    quickbarToDelete = nil
                }
            } message: { quickbar in
                Text(
                    String(
                        format: NSLocalizedString("Main_Market_Watch_List_Delete_Confirm", comment: ""),
                        quickbar.name
                    )
                )
            }
            .task {
                quickbars = MarketQuickbarManager.shared.loadQuickbars()
            }
    }

    /// 列表主体：长按拖动排序（onMove），导航/滑动/长按菜单
    private var quickbarList: some View {
        List {
            if quickbars.isEmpty {
                Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                    .foregroundColor(.secondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else if filteredQuickbars.isEmpty {
                Text(NSLocalizedString("Main_EVE_Mail_No_Results", comment: ""))
                    .foregroundColor(.secondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else {
                ForEach(filteredQuickbars) { quickbar in
                    NavigationLink {
                        MarketQuickbarDetailView(
                            databaseManager: databaseManager,
                            quickbar: quickbar
                        )
                    } label: {
                        quickbarRowView(quickbar)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            quickbarToDelete = quickbar
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }

                        Button {
                            renameQuickbar = quickbar
                            renameQuickbarName = quickbar.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            renameQuickbar = quickbar
                            renameQuickbarName = quickbar.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            quickbarToDelete = quickbar
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .onMove(perform: moveQuickbars)
            }
        }
    }

    /// 添加关注列表按钮（iOS 26 位于底部搜索栏右侧，旧系统位于右上角）
    private var addQuickbarButton: some View {
        Button {
            newQuickbarName = ""
            isShowingAddAlert = true
        } label: {
            Image(systemName: "plus")
        }
    }

    private func quickbarRowView(_ quickbar: MarketQuickbar) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 显示列表图标（优先选择第一个飞船的图标）
            if let iconTypeID = getPreferredIconTypeID(for: quickbar) {
                let icon = getItemIcon(typeID: iconTypeID)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(quickbar.name)
                    .lineLimit(1)

                Text(getMarketName(for: quickbar))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(
                String(
                    format: NSLocalizedString("Main_Market_Watch_List_Items", comment: ""),
                    quickbar.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 获取用于显示列表图标的 typeID，优先选择第一个飞船 (categoryID == 6)
    private func getPreferredIconTypeID(for quickbar: MarketQuickbar) -> Int? {
        for item in quickbar.items where SDEMemoryStore.type(for: item.typeID)?.categoryID == 6 {
            return item.typeID
        }
        return quickbar.items.first?.typeID
    }

    /// 获取物品图标的辅助函数
    private func getItemIcon(typeID: Int) -> UIImage {
        let iconFileName = ItemInfoMap.iconFilename(for: typeID)
        return IconManager.shared.loadUIImage(for: iconFileName)
    }

    /// 获取市场名称的辅助函数
    private func getMarketName(for quickbar: MarketQuickbar) -> String {
        MarketLocationType.from(id: quickbar.locationID)?.displayName ?? "Unknown"
    }

    private func deleteQuickbar(_ quickbar: MarketQuickbar) {
        MarketQuickbarManager.shared.deleteQuickbar(quickbar)
        quickbars.removeAll { $0.id == quickbar.id }
    }

    /// 拖动排序：先在（可能被搜索过滤的）显示数组内移动，再映射回全量数组；未过滤时等价于直接移动
    private func moveQuickbars(from source: IndexSet, to destination: Int) {
        let filtered = filteredQuickbars
        guard !filtered.isEmpty else { return }

        var newFiltered = filtered
        newFiltered.move(fromOffsets: source, toOffset: destination)

        var filteredIterator = newFiltered.makeIterator()
        let filteredIDs = Set(filtered.map(\.id))
        var reordered: [MarketQuickbar] = []
        reordered.reserveCapacity(quickbars.count)
        for quickbar in quickbars {
            if filteredIDs.contains(quickbar.id), let moved = filteredIterator.next() {
                reordered.append(moved)
            } else {
                reordered.append(quickbar)
            }
        }

        quickbars = reordered
        MarketQuickbarManager.shared.saveManualOrder(quickbars)
    }
}
