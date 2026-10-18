import SwiftUI

/// 配置列表视图
struct FittingMainView: View {
    @State private var sourceType: FittingSourceType = .local
    @State private var searchText = ""
    @State private var showShipSelector = false
    @State private var isShowingAddFittingDialog = false
    // 新建装配（sheet 选船后 push 新装配编辑器）
    @State private var selectedShip: DatabaseListItem? = nil
    @State private var navigateToShipFitting = false
    // 导入成功后自动进入装配详情
    @State private var importedFitting: LocalFitting?
    @State private var navigateToImportedFitting = false

    // 导入错误状态管理
    @State private var showingImportErrorAlert = false
    @State private var importErrorMessage = ""

    // 飞船选择状态管理
    @State private var showingShipSelectionAlert = false
    @State private var shipSelectionOptions: [(typeId: Int, name: String, iconFileName: String?)] =
        []
    @State private var pendingEftText = ""

    // 重命名状态管理
    @State private var isShowingRenameAlert = false
    @State private var renameFitting: FittingItemNode?
    @State private var renameFittingName = ""

    // 删除二次确认状态管理
    @State private var isShowingDeleteConfirmation = false
    @State private var deleteCandidate: FittingDeleteTarget?

    @State private var isBatchDeleting = false

    // 使用两个独立的视图模型
    @StateObject private var localViewModel: LocalFittingViewModel
    @StateObject private var onlineViewModel: OnlineFittingViewModel

    init(
        characterId: Int? = nil, databaseManager: DatabaseManager,
        fetchOnlineFittings: @escaping (Int, Bool) async throws -> [CharacterFitting] = {
            try await CharacterFittingAPI.getCharacterFittings(characterID: $0, forceRefresh: $1)
        }
    ) {
        _localViewModel = StateObject(wrappedValue: LocalFittingViewModel(databaseManager: databaseManager))
        _onlineViewModel = StateObject(wrappedValue: OnlineFittingViewModel(
            characterId: characterId, databaseManager: databaseManager, fetchFittings: fetchOnlineFittings
        ))
    }

    /// 当前来源下的导航树（唯一列表数据源，已分组、预排序）
    private var currentTree: [FittingGroupNode] {
        switch sourceType {
        case .local:
            return localViewModel.tree
        case .online:
            return onlineViewModel.tree
        }
    }

    /// 当前来源下的搜索结果
    private var searchMatches: [FittingItemNode] {
        switch sourceType {
        case .local:
            return localViewModel.searchMatches(query: searchText)
        case .online:
            return onlineViewModel.searchMatches(query: searchText)
        }
    }

    private func deleteFittings(source: FittingSourceType, refs: Set<FittingRef>) async -> Set<FittingRef> {
        switch source {
        case .local:
            let ids = Set(refs.compactMap { ref -> UUID? in
                if case let .local(id) = ref {
                    return id
                }
                return nil
            })
            return Set(localViewModel.deleteFittings(fittingIds: ids).map { FittingRef.local($0) })
        case .online:
            let ids = Set(refs.compactMap { ref -> Int? in
                if case let .online(id) = ref {
                    return id
                }
                return nil
            })
            let deleted = await onlineViewModel.deleteFittings(fittingIds: ids)
            return Set(deleted.map { FittingRef.online($0) })
        }
    }

    /// 添加一个计算属性检查是否正在加载
    private var isLoading: Bool {
        switch sourceType {
        case .local:
            return localViewModel.isLoading
        case .online:
            return onlineViewModel.isLoading
        }
    }

    /// 添加一个计算属性获取当前视图模型的飞船信息
    private var currentShipInfo: [Int: FittingShipInfo] {
        switch sourceType {
        case .local:
            return localViewModel.shipInfo
        case .online:
            return onlineViewModel.shipInfo
        }
    }

    /// 新建配置按钮（新建装配 / 从剪贴板导入），iOS 26 位于底部搜索栏右侧，旧系统位于右上角
    /// 注：iOS 26 下 bottomBar 中的 Menu 存在弹窗飞至屏幕顶部的系统 Bug，故改用 confirmationDialog
    private var addFittingMenu: some View {
        Button {
            isShowingAddFittingDialog = true
        } label: {
            Image(systemName: "plus")
        }
        .confirmationDialog(
            "",
            isPresented: $isShowingAddFittingDialog,
            titleVisibility: .hidden
        ) {
            Button(NSLocalizedString("Fitting_New_Fitting", comment: "")) {
                showShipSelector = true
            }

            Button(NSLocalizedString("Fitting_Import_From_Clipboard", comment: "")) {
                importFromClipboard()
            }

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {}
        }
    }

    /// 处理从剪贴板导入配置
    private func importFromClipboard() {
        Logger.info("从剪贴板导入配置功能被触发")

        // 获取剪贴板内容
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            Logger.warning("剪贴板为空或无文本内容")
            importErrorMessage = NSLocalizedString("Fitting_Import_Clipboard_Empty", comment: "")
            showingImportErrorAlert = true
            return
        }

        Logger.info("获取到剪贴板内容，长度: \(clipboardText.count) 字符")

        // 尝试解析EFT格式
        do {
            let localFitting = try FitConvert.eftToLocalFitting(
                eftText: clipboardText,
                databaseManager: localViewModel.databaseManager
            )

            Logger.info(
                "EFT格式解析成功 - 飞船ID: \(localFitting.ship_type_id), 配置名称: \(localFitting.name)"
            )

            // 导入只创建内存草稿，由编辑器的保存按钮写入本地。
            importedFitting = localFitting
            navigateToImportedFitting = true

        } catch let error as NSError {
            Logger.error("从剪贴板导入配置失败: \(error.localizedDescription)")

            // 检查是否是多个同名飞船的错误
            if error.code == 7,
               let shipOptions = error.userInfo["shipOptions"]
               as? [(typeId: Int, name: String, iconFileName: String?)]
            {
                // 显示飞船选择弹窗
                shipSelectionOptions = shipOptions
                pendingEftText = clipboardText
                showingShipSelectionAlert = true
                Logger.info("检测到多个同名飞船，显示选择弹窗，选项数量: \(shipOptions.count)")
            } else {
                // 显示普通错误提示
                importErrorMessage = String(
                    format: NSLocalizedString("Fitting_Import_Failed_Message", comment: "导入失败"),
                    error.localizedDescription
                )
                showingImportErrorAlert = true
            }
        }
    }

    /// 复制装配配置（仅本地配置）
    private func copyFitting(_ fitting: FittingItemNode) {
        guard sourceType == .local, case let .local(fittingId) = fitting.ref else { return }

        Task {
            do {
                let localFitting = try FitConvert.loadLocalFitting(fittingId: fittingId)
                let copyName = "\(fitting.name) \(NSLocalizedString("Fitting_Copy_Suffix", comment: "副本"))"
                let newId = UUID()
                let copiedFitting = localFitting.duplicated(newId: newId, name: copyName)
                try FitConvert.saveLocalFitting(copiedFitting)
                Logger.success("成功复制装配配置 - 原ID: \(fitting.ref.debugDescription), 新ID: \(newId)")
                await localViewModel.loadLocalFittings()
            } catch {
                Logger.error("复制装配配置失败: \(error)")
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                    showingImportErrorAlert = true
                }
            }
        }
    }

    /// 重命名装配配置（仅本地配置）
    private func renameFittingName(fitting: FittingItemNode, newName: String) {
        Logger.info("开始重命名装配配置 - ID: \(fitting.ref.debugDescription), 新名称: \(newName)")

        // 只处理本地配置
        guard sourceType == .local, case let .local(fittingId) = fitting.ref else {
            Logger.warning("尝试重命名在线配置，此操作不被支持")
            return
        }

        Task {
            do {
                // 加载配置并重命名
                let localFitting = try FitConvert.loadLocalFitting(fittingId: fittingId)
                    .renamed(newName)

                // 保存配置
                try FitConvert.saveLocalFitting(localFitting)
                Logger.success("成功重命名本地装配配置 - ID: \(fitting.ref.debugDescription)")

                // 刷新列表
                await localViewModel.loadLocalFittings()
            } catch {
                Logger.error("重命名本地装配配置失败: \(error)")
                await MainActor.run {
                    importErrorMessage = String(
                        format: NSLocalizedString("Fitting_Import_Failed_Message", comment: "导入失败"),
                        error.localizedDescription
                    )
                    showingImportErrorAlert = true
                }
            }
        }
    }

    /// 重命名弹窗内容（目录与搜索结果共用）
    @ViewBuilder
    private func renameAlertContent() -> some View {
        TextField(NSLocalizedString("Misc_Name", comment: ""), text: $renameFittingName)

        Button(NSLocalizedString("Misc_Done", comment: "")) {
            if let fitting = renameFitting, !renameFittingName.isEmpty {
                renameFittingName(fitting: fitting, newName: renameFittingName)
            }
            renameFitting = nil
            renameFittingName = ""
        }
        .disabled(renameFittingName.isEmpty)

        Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
            renameFitting = nil
            renameFittingName = ""
        }
    }

    /// 执行删除确认
    private func performDeleteConfirmation() {
        guard let target = deleteCandidate else { return }
        switch target {
        case let .fitting(item):
            switch item.ref {
            case let .online(fittingId):
                onlineViewModel.deleteFitting(fittingId: fittingId)
            case let .local(fittingId):
                localViewModel.deleteFitting(fittingId: fittingId)
            }
        case let .unreadable(item):
            localViewModel.deleteUnreadableFitting(fileName: item.fileName)
        case .allUnreadable:
            localViewModel.deleteAllUnreadableFittings()
        }
        deleteCandidate = nil
    }

    /// 删除确认弹窗消息（目录与搜索结果共用）
    private func deleteConfirmMessage() -> String {
        switch deleteCandidate {
        case let .fitting(item):
            return String(
                format: NSLocalizedString("Fitting_Delete_Confirm_Message", comment: ""),
                item.name.isEmpty ? NSLocalizedString("Unnamed", comment: "") : item.name
            )
        case let .unreadable(item):
            return String(
                format: NSLocalizedString("Fitting_Delete_Confirm_Message", comment: ""),
                item.displayName
            )
        case .allUnreadable:
            return NSLocalizedString("Fitting_Unreadable_Clear_All_Confirm", comment: "")
        case nil:
            return ""
        }
    }

    /// 处理用户选择的飞船并重新导入
    private func importWithSelectedShip(selectedShipTypeId: Int) {
        Logger.info("用户选择了飞船ID: \(selectedShipTypeId)，重新导入配置")

        do {
            let localFitting = try FitConvert.eftToLocalFitting(
                eftText: pendingEftText,
                databaseManager: localViewModel.databaseManager,
                selectedShipTypeId: selectedShipTypeId
            )

            Logger.info(
                "使用选定飞船重新解析成功 - 飞船ID: \(localFitting.ship_type_id), 配置名称: \(localFitting.name)"
            )

            // 导入只创建内存草稿，由编辑器的保存按钮写入本地。
            importedFitting = localFitting
            navigateToImportedFitting = true

        } catch {
            Logger.error("使用选定飞船重新导入失败: \(error.localizedDescription)")

            // 显示错误提示
            importErrorMessage = String(
                format: NSLocalizedString("Fitting_Import_Failed_Message", comment: "导入失败"),
                error.localizedDescription
            )
            showingImportErrorAlert = true
        }

        // 清理状态
        pendingEftText = ""
        shipSelectionOptions = []
    }

    // MARK: - 分组与飞船装配目录（树驱动）

    /// 主页：组列表
    private var hierarchyListContent: some View {
        Section(header: Text(NSLocalizedString("Fitting_Section_Groups", comment: ""))) {
            ForEach(currentTree) { node in
                groupRowView(node)
            }
        }
    }

    // MARK: - 无法解析的装配（仅提醒 + 删除）

    /// 无法解析装配 Section：红色标签提醒，仅允许删除（左滑单个 / header 一键全部清除）
    private var unreadableFittingsSection: some View {
        Section {
            ForEach(localViewModel.unreadableFittings) { item in
                unreadableRowView(item)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Fitting_Unreadable", comment: ""))
                Spacer(minLength: 8)
                Button {
                    deleteCandidate = .allUnreadable
                    isShowingDeleteConfirmation = true
                } label: {
                    Text(NSLocalizedString("Fitting_Unreadable_Clear_All", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// 无法解析装配行：图标 + 名称 + 飞船信息 + 红色“无法解析”标签
    private func unreadableRowView(_ item: UnreadableFitting) -> some View {
        HStack(spacing: 12) {
            Image(
                uiImage: IconManager.shared.loadUIImage(
                    for: item.shipTypeId.flatMap { currentShipInfo[$0]?.iconFileName } ?? "not_found"
                )
            )
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(unreadableShipText(item))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(NSLocalizedString("Fitting_Unreadable", comment: ""))
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red))
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // 仅允许删除（无重命名/复制）
            Button(role: .destructive) {
                deleteCandidate = .unreadable(item)
                isShowingDeleteConfirmation = true
            } label: {
                Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
            }
        }
    }

    /// 无法解析装配的飞船副文本：SDE 可查用名称，否则显示 typeID
    private func unreadableShipText(_ item: UnreadableFitting) -> String {
        if let typeId = item.shipTypeId, let info = currentShipInfo[typeId] {
            return info.name
        }
        if let typeId = item.shipTypeId {
            return "TypeID: \(typeId)"
        }
        return NSLocalizedString("Unknown", comment: "")
    }

    /// 组行：图标 + 组名 + 组内装配总数，点击进入组页
    private func groupRowView(_ node: FittingGroupNode) -> some View {
        NavigationLink(value: node) {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: node.firstIconFileName ?? "not_found"))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                Text(node.groupName)
                    .foregroundColor(.primary)

                Spacer()

                Text(String(node.fittingCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
        .accessibilityIdentifier("fitting.group.\(node.groupID)")
    }

    /// 第二层目录：每艘飞船独立 section，在当前页面直接编辑选择。
    private func groupPage(groupID: Int) -> some View {
        let node = currentTree.first { $0.groupID == groupID }

        return FittingShipSectionsView(
            ships: node?.children ?? [], source: sourceType,
            isDeleting: $isBatchDeleting, onDelete: deleteFittings
        ) { item in
            fittingRowView(item)
        }
        .navigationTitle(node?.groupName ?? "")
        .navigationBarTitleDisplayMode(.large)
        .modifier(EmptyFittingGroupDismissal(isEmpty: (node?.fittingCount ?? 0) == 0,
                                             isLoading: isLoading || isBatchDeleting))
        .onAppear {
            Task {
                switch sourceType {
                case .local:
                    await localViewModel.loadLocalFittings()
                case .online:
                    onlineViewModel.refreshDisplayedFittings()
                }
            }
        }
        .alert(
            NSLocalizedString("Misc_Rename", comment: ""),
            isPresented: $isShowingRenameAlert
        ) {
            renameAlertContent()
        }
        .fittingDeleteConfirmation(
            message: deleteConfirmMessage(),
            isPresented: $isShowingDeleteConfirmation,
            onConfirm: performDeleteConfirmation,
            onCancel: { deleteCandidate = nil }
        )
    }

    // MARK: - 搜索结果

    /// 搜索结果视图：平铺显示命中的装配
    @ViewBuilder
    private var searchResultsSection: some View {
        if searchMatches.isEmpty {
            NoDataSection(icon: "magnifyingglass")
        } else {
            Section {
                ForEach(searchMatches) { fitting in
                    fittingRowView(fitting)
                }
            }
        }
    }

    /// 添加一个视图来显示空状态
    private var emptyStateView: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: sourceType == .local ? "archivebox" : "network")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text(
                        sourceType == .local
                            ? NSLocalizedString("Fitting_No_Local_Fitting", comment: "")
                            : NSLocalizedString("Fitting_Online_No_Data", comment: "")
                    )
                    .foregroundColor(.gray)
                }
                .padding()
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    /// 装配行：飞船图标与装配名称，点击进入详情。
    private func fittingRowView(_ item: FittingItemNode) -> some View {
        NavigationLink(value: item.ref) {
            FittingCatalogRow(name: item.name, iconFileName: shipIconFileName(item.shipTypeId))
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 删除按钮（先添加，会在右边）
            Button(role: .destructive) {
                deleteCandidate = .fitting(item)
                isShowingDeleteConfirmation = true
            } label: {
                Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
            }

            // 复制 / 重命名按钮 - 仅本地配置
            if sourceType == .local {
                Button {
                    copyFitting(item)
                } label: {
                    Label(NSLocalizedString("Fitting_Copy", comment: "复制"), systemImage: "doc.on.doc")
                }
                .tint(.green)

                Button {
                    renameFitting = item
                    renameFittingName = item.name
                    isShowingRenameAlert = true
                } label: {
                    Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            // 复制 / 重命名选项 - 仅本地配置
            if sourceType == .local {
                Button {
                    copyFitting(item)
                } label: {
                    Label(NSLocalizedString("Fitting_Copy", comment: "复制"), systemImage: "doc.on.doc")
                }

                Button {
                    renameFitting = item
                    renameFittingName = item.name
                    isShowingRenameAlert = true
                } label: {
                    Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                }
            }

            // 删除选项
            Button(role: .destructive) {
                deleteCandidate = .fitting(item)
                isShowingDeleteConfirmation = true
            } label: {
                Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
            }
        }
    }

    /// 装配详情：本地按 UUID 直开；在线从全量字典直取（零二次请求）。
    /// .id() 保证不同装配 = 不同视图身份，避免复用旧装配的 @State
    @ViewBuilder
    private func fittingDetail(ref: FittingRef) -> some View {
        switch ref {
        case let .local(fittingId):
            ShipFittingView(
                fittingId: fittingId,
                databaseManager: localViewModel.databaseManager
            )
            .id(fittingId)
            .onAppear { Logger.info("打开本地装配详情 - UUID: \(fittingId)") }
        case let .online(fittingId):
            if let onlineFitting = onlineViewModel.fittingsByID[fittingId] {
                ShipFittingView(
                    onlineFitting: onlineFitting,
                    databaseManager: onlineViewModel.databaseManager
                )
                .id(fittingId)
                .onAppear { Logger.info("打开在线装配详情 - ESI ID: \(fittingId)") }
            }
        }
    }

    /// 查询飞船图标文件名
    private func shipIconFileName(_ typeId: Int) -> String {
        currentShipInfo[typeId]?.iconFileName ?? "not_found"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                List {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List {
                    // 搜索时显示专门的搜索结果视图
                    if !searchText.isEmpty {
                        searchResultsSection
                    } else if currentTree.isEmpty && (sourceType == .online || localViewModel.unreadableFittings.isEmpty) {
                        emptyStateView
                    } else {
                        // 一级飞船分组目录
                        hierarchyListContent

                        // 无法解析的装配（仅提醒，不可点击）
                        if sourceType == .local && !localViewModel.unreadableFittings.isEmpty {
                            unreadableFittingsSection
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    switch sourceType {
                    case .local:
                        await localViewModel.loadLocalFittings()
                    case .online:
                        await onlineViewModel.loadOnlineFittings(forceRefresh: true)
                    }
                }
                .alert(
                    NSLocalizedString("Misc_Rename", comment: ""),
                    isPresented: $isShowingRenameAlert
                ) {
                    renameAlertContent()
                }
                .fittingDeleteConfirmation(
                    message: deleteConfirmMessage(),
                    isPresented: $isShowingDeleteConfirmation,
                    onConfirm: performDeleteConfirmation,
                    onCancel: { deleteCandidate = nil }
                )
            }
        }
        .navigationTitle(NSLocalizedString("Main_Fitting", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 添加Picker到toolbar中
            ToolbarItem(placement: .principal) {
                // 自定义 Binding：切换时包裹 withAnimation，使底部 + 按钮/搜索框宽度获得过渡动画
                Picker(
                    "Fitting Source",
                    selection: Binding(
                        get: { sourceType },
                        set: { newValue in
                            withAnimation(.snappy) { sourceType = newValue }
                        }
                    )
                ) {
                    Text(NSLocalizedString("Fitting_Local", comment: ""))
                        .tag(FittingSourceType.local)
                    Text(NSLocalizedString("Fitting_Online", comment: ""))
                        .tag(FittingSourceType.online)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("fitting.source")
                .frame(width: 200)
                .disabled(onlineViewModel.characterId == nil || isBatchDeleting)
            }

            if #available(iOS 26.0, *) {
                // iOS 26：搜索框常驻底部（避免切换本地/在线时重建），本地模式下与 + 按钮共处同一 Liquid Glass 行
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                if sourceType == .local {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        addFittingMenu
                    }
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if sourceType == .local {
                        addFittingMenu
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "搜索飞船名称...")
        )
        .sheet(isPresented: $showShipSelector) {
            NavigationStack {
                FittingShipSelectorView(databaseManager: localViewModel.databaseManager) {
                    selectedItem in
                    selectedShip = selectedItem
                    showShipSelector = false
                    navigateToShipFitting = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateToShipFitting) {
            if let ship = selectedShip {
                ShipFittingView(
                    shipTypeId: ship.id,
                    shipInfo: (name: ship.name, iconFileName: ship.iconFileName),
                    databaseManager: localViewModel.databaseManager
                )
            }
        }
        // 导入成功后自动进入装配详情
        .navigationDestination(isPresented: $navigateToImportedFitting) {
            if let importedFitting {
                ShipFittingView(temporaryFitting: importedFitting, databaseManager: localViewModel.databaseManager)
            }
        }
        // 组页按飞船分 section，装配行直接导航到详情
        .navigationDestination(for: FittingGroupNode.self) { node in
            groupPage(groupID: node.groupID)
        }
        .navigationDestination(for: FittingRef.self) { ref in
            fittingDetail(ref: ref)
        }
        .onChange(of: sourceType) { _, newValue in
            Logger.info("[装配列表] 来源切换：\(newValue)，在线模型=\(ObjectIdentifier(onlineViewModel))")
            // 如果没有角色但尝试切换到线上，切换回本地
            if newValue == .online && onlineViewModel.characterId == nil {
                sourceType = .local
                return
            }
            Task {
                switch newValue {
                case .local:
                    await localViewModel.loadLocalFittings()
                case .online:
                    await onlineViewModel.loadOnlineFittings()
                }
            }
        }
        .onAppear {
            Logger.info("[装配列表] 页面出现：\(sourceType)，在线模型=\(ObjectIdentifier(onlineViewModel))")
            Task {
                if sourceType == .local {
                    await localViewModel.loadLocalFittings()
                }
                // 与旧版一致，在本地目录可见时准备线上数据；模型安装后才启动预加载。
                if onlineViewModel.characterId != nil {
                    await onlineViewModel.loadOnlineFittings()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("RefreshOnlineFittings"))
        ) { notification in
            // 当收到刷新在线配置的通知时，刷新在线配置列表
            if let userInfo = notification.userInfo,
               let notificationCharacterId = userInfo["characterId"] as? Int,
               notificationCharacterId == onlineViewModel.characterId
            {
                Logger.info("收到刷新在线配置通知，开始刷新配置列表")

                // 只有当前显示在线配置时才刷新
                if sourceType == .online {
                    // 使用OnlineFittingViewModel的刷新方法
                    onlineViewModel.refreshDisplayedFittings()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("RefreshLocalFittings"))
        ) { _ in
            // 从配置详情返回时刷新本地配置列表（设置 sheet 里改名 / 详情内删除后立即反映新名称）
            guard sourceType == .local else { return }
            Task {
                await localViewModel.loadLocalFittings()
            }
        }
        .alert(
            NSLocalizedString("Fitting_Import_Failed_Title", comment: "导入失败"),
            isPresented: $showingImportErrorAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) {}
        } message: {
            Text(importErrorMessage)
        }
        .sheet(
            item: Binding<ShipSelectionItem?>(
                get: {
                    showingShipSelectionAlert
                        ? ShipSelectionItem(options: shipSelectionOptions, eftText: pendingEftText)
                        : nil
                },
                set: { _ in
                    showingShipSelectionAlert = false
                    pendingEftText = ""
                    shipSelectionOptions = []
                }
            )
        ) { item in
            ShipSelectionView(
                shipOptions: item.options,
                onShipSelected: { selectedShipTypeId in
                    showingShipSelectionAlert = false
                    importWithSelectedShip(selectedShipTypeId: selectedShipTypeId)
                },
                onCancel: {
                    showingShipSelectionAlert = false
                    pendingEftText = ""
                    shipSelectionOptions = []
                }
            )
        }
    }
}

/// 飞船选择项模型
struct ShipSelectionItem: Identifiable {
    let id = UUID()
    let options: [(typeId: Int, name: String, iconFileName: String?)]
    let eftText: String
}

/// 删除二次确认的目标类型
private enum FittingDeleteTarget {
    case fitting(FittingItemNode)
    case unreadable(UnreadableFitting)
    case allUnreadable
}

/// 飞船选择弹窗视图
struct ShipSelectionView: View {
    let shipOptions: [(typeId: Int, name: String, iconFileName: String?)]
    let onShipSelected: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(shipOptions, id: \.typeId) { option in
                        HStack(spacing: 12) {
                            // 飞船图标
                            Image(
                                uiImage: IconManager.shared.loadUIImage(
                                    for: option.iconFileName ?? ""
                                )
                            )
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("ID: \(option.typeId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onShipSelected(option.typeId)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Fitting_Import_Multiple_Ships_Header", comment: "选择飞船"))
                        .font(.headline)
                }
            }
            .navigationTitle(
                NSLocalizedString("Fitting_Import_Ship_Selection_Title", comment: "选择飞船")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Common_Cancel", comment: "取消")) {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Read dismiss inside the destination, and avoid popping while its fitting editor is on top.
private struct EmptyFittingGroupDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var isVisible = false
    let isEmpty: Bool
    let isLoading: Bool

    private var shouldDismiss: Bool {
        isEmpty && !isLoading
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                if shouldDismiss {
                    dismiss()
                }
            }
            .onDisappear { isVisible = false }
            .onChange(of: shouldDismiss) { _, empty in
                if empty && isVisible {
                    dismiss()
                }
            }
    }
}
