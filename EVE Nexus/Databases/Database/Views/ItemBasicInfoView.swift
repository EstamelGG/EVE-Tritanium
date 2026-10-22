import SwiftUI

struct ItemBasicInfoView: View {
    private enum WidthClass {
        case narrow, wide, extraWide
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let itemDetails: ItemDetails
    @ObservedObject var databaseManager: DatabaseManager
    let modifiedAttributes: [Int: Double]?

    @StateObject private var skillsManager = SharedSkillsManager.shared
    @State private var renderImage: UIImage?
    @State private var widthClass: WidthClass = .narrow
    @State private var marketPath: String = ""
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var isModelAvailable = false
    @State private var itemNameShowsEnglish = false
    @State private var showMasteryDetail = false

    private let cornerRadius: CGFloat = 10
    private let standardPadding: CGFloat = 16
    private let rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

    /// 拥有 3D 渲染图的物品 categoryID 白名单
    private static let renderImageCategories: Set<Int> = [
        2, 3, 6, 11, 18, 22, 23, 40, 41, 46, 65, 87, 91,
    ]

    /// Use the list row's width, including when its navigation column is resized.
    private var shouldUseCompactLayout: Bool {
        widthClass != .narrow
    }

    private var imageSize: CGFloat {
        widthClass == .extraWide ? 256 : 128
    }

    private var itemNameCanToggleEnglish: Bool {
        guard let en = itemDetails.en_name, !en.isEmpty else { return false }
        return en != itemDetails.name
    }

    private var itemTitleDisplayName: String {
        if itemNameCanToggleEnglish, itemNameShowsEnglish, let en = itemDetails.en_name {
            return en
        }
        return itemDetails.name
    }

    private var itemTitleAlternateName: String? {
        guard itemNameCanToggleEnglish, let en = itemDetails.en_name else { return nil }
        return itemNameShowsEnglish ? itemDetails.name : en
    }

    private static let itemNameToggleAnimation = Animation.spring(
        response: 0.38,
        dampingFraction: 0.82
    )

    private var categoryGroupIDText: String {
        "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
    }

    private var hasBasicStats: Bool {
        itemDetails.volume != nil
            || itemDetails.capacity != nil
            || itemDetails.mass != nil
            || itemDetails.repackagedVolume != nil
    }

    // MARK: - Mastery

    /// 专精显示状态（共享 helper 计算；未登录/加载中/无数据时为 nil）
    private var masteryDisplayState: MasteryLevelState? {
        MasteryDisplayHelper.state(
            typeID: itemDetails.typeId,
            databaseManager: databaseManager,
            skillsManager: skillsManager
        )
    }

    /// 文字块右侧的专精图标（64pt，与名称+目录左右布局）；点击跳转专精详情页
    /// 用状态 + navigationDestination 解耦导航与布局，避免 NavigationLink 影响行内排版
    @ViewBuilder
    private func masteryTrailingIcon(state: MasteryLevelState?) -> some View {
        if let state {
            Image(MasteryDisplayHelper.iconName(for: state))
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .onTapGesture { showMasteryDetail = true }
                .navigationDestination(isPresented: $showMasteryDetail) {
                    ShipMasteryDetailView(
                        typeID: itemDetails.typeId,
                        databaseManager: databaseManager
                    )
                }
        }
    }

    /// 渲染图文遮罩右端的专精背景色（与左侧半透明黑做横向渐变）；无专精状态时为 nil
    private func masteryBackdropColor(for state: MasteryLevelState?) -> Color? {
        state.map { MasteryDisplayHelper.backdropColor(for: $0) }
    }

    var body: some View {
        // 专精状态使用内存索引，单次渲染只求值一次。
        bodyContent(masteryState: masteryDisplayState)
    }

    private func bodyContent(masteryState: MasteryLevelState?) -> some View {
        Group {
            Section {
                Group {
                    if let renderImage {
                        if shouldUseCompactLayout {
                            compactLayoutView(renderImage: renderImage, masteryState: masteryState)
                        } else {
                            renderImageLayoutView(renderImage: renderImage, masteryState: masteryState)
                        }
                    } else {
                        originalLayoutView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: WidthClass.self) { geometry in
                    let width = geometry.size.width
                    return width >= 700 ? .extraWide : (width >= 560 ? .wide : .narrow)
                } action: { newClass in
                    widthClass = newClass
                }
                // Set insets on the actual list row, outside the geometry wrapper.
                // Both render layouts share one border instead of stacking row and image padding.
                .listRowInsets(
                    renderImage != nil
                        ? EdgeInsets(
                            top: standardPadding, leading: standardPadding,
                            bottom: standardPadding, trailing: standardPadding
                        )
                        : rowInsets
                )

                if !itemDetails.description.isEmpty {
                    RichTextView(text: itemDetails.description, databaseManager: databaseManager)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .onAppear {
                loadRenderImage(for: itemDetails.typeId)
                skillsManager.preloadSkills()
                Logger.debug(
                    "物品 \(itemDetails.name) 的 marketGroupID: \(String(describing: itemDetails.marketGroupID))"
                )
                if let marketGroupID = itemDetails.marketGroupID {
                    Logger.debug("显示市场按钮，marketGroupID: \(marketGroupID)")
                    if shouldUseCompactLayout {
                        fetchMarketPath(for: marketGroupID)
                    }
                }
                checkModelAvailability()
            }
            .alert(
                NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                isPresented: $showSaveSuccess
            ) {
                Button("OK") {}
            } message: {
                Text(NSLocalizedString("Misc_Save_Render_Image_Success", comment: ""))
            }
            .alert(
                NSLocalizedString("Misc_Save_Render_Image_Error_Title", comment: ""),
                isPresented: $showSaveError
            ) {
                Button("OK") {}
            } message: {
                Text(NSLocalizedString("Misc_Save_Render_Image_Error", comment: ""))
            }
            .onChange(of: shouldUseCompactLayout) { _, newValue in
                if newValue && marketPath.isEmpty && itemDetails.marketGroupID != nil {
                    fetchMarketPath(for: itemDetails.marketGroupID)
                }
            }

            if itemDetails.marketGroupID != nil || isModelAvailable || masteryState != nil {
                Section {
                    if itemDetails.marketGroupID != nil {
                        NavigationLink {
                            MarketItemDetailView(
                                databaseManager: databaseManager,
                                itemID: itemDetails.typeId
                            )
                        } label: {
                            iconTitleRow(
                                icon: "isk",
                                title: NSLocalizedString("Main_Market", comment: "")
                            )
                        }

                        NavigationLink {
                            MarketQuickbarDestinationPickerView(
                                databaseManager: databaseManager,
                                typeID: itemDetails.typeId
                            )
                        } label: {
                            HStack(alignment: .center) {
                                Image("searchmarket")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(
                                    NSLocalizedString(
                                        "Main_Market_Add_To_Watchlist_Button", comment: ""
                                    )
                                )
                                .foregroundColor(.primary)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }

                    if itemDetails.categoryID == 6 {
                        NavigationLink {
                            ShipInsuranceView(
                                typeId: itemDetails.typeId,
                                typeName: itemDetails.name
                            )
                        } label: {
                            iconTitleRow(
                                icon: "insurance",
                                title: NSLocalizedString("Insurance_Title", comment: "保险")
                            )
                        }
                    }

                    if isModelAvailable {
                        Button {
                            if let url = URL(
                                string:
                                "https://estamelgg.github.io/EVE_Model_Gallery/#typeid=\(itemDetails.typeId)&tiny"
                            ) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            iconTitleRow(
                                icon: "ISIS",
                                title: NSLocalizedString("Item_View_Model", comment: "查看模型")
                            )
                        }
                    }

                    if let masteryState {
                        NavigationLink {
                            ShipMasteryDetailView(
                                typeID: itemDetails.typeId,
                                databaseManager: databaseManager
                            )
                        } label: {
                            masteryRow(for: masteryState)
                        }
                    }
                }
                .listRowInsets(rowInsets)
            }

            if hasBasicStats {
                Section(
                    header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline)
                ) {
                    if let volume = itemDetails.volume {
                        basicStatRow(
                            icon: "structure",
                            title: NSLocalizedString("Item_Volume", comment: ""),
                            value: "\(FormatUtil.format(Double(volume))) m3"
                        )
                    }
                    if let repackagedVolume = itemDetails.repackagedVolume {
                        basicStatRow(
                            icon: "packages",
                            title: NSLocalizedString("Item_RepackagesVolume", comment: ""),
                            value: "\(FormatUtil.format(Double(repackagedVolume))) m3"
                        )
                    }
                    if let capacity = itemDetails.capacity {
                        let original = Double(capacity)
                        let final =
                            getAttributeValue(attributeId: 38, originalValue: original) ?? original
                        basicStatRow(
                            icon: "cargo_fit",
                            title: NSLocalizedString("Item_Capacity", comment: ""),
                            value: "\(FormatUtil.format(final)) m3",
                            valueColor: getAttributeColor(attributeId: 38, originalValue: original)
                        )
                        .attributeInfluences([38])
                    }
                    if let mass = itemDetails.mass {
                        let original = Double(mass)
                        let final =
                            getAttributeValue(attributeId: 4, originalValue: original) ?? original
                        basicStatRow(
                            icon: "hull",
                            title: NSLocalizedString("Item_Mass", comment: ""),
                            value: "\(FormatUtil.format(final)) Kg",
                            valueColor: getAttributeColor(attributeId: 4, originalValue: original)
                        )
                        .attributeInfluences([4])
                    }
                }
                .listRowInsets(rowInsets)
            }
        }
        .onChange(of: itemDetails.typeId) { _, _ in
            itemNameShowsEnglish = false
        }
    }

    // MARK: - Layout

    private func compactLayoutView(renderImage: UIImage, masteryState: MasteryLevelState?) -> some View {
        HStack(alignment: .center) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: imageSize, height: imageSize)
                .cornerRadius(cornerRadius)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 8) {
                itemTitleLabel(lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .contextMenu { itemNameContextMenu(includeSaveImage: true) }

                Text(
                    "\(NSLocalizedString("Main_Database_Category", comment: "")): \(categoryGroupIDText)"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                if !marketPath.isEmpty {
                    Text(
                        "\(NSLocalizedString("Main_Database_Market_Category", comment: "")): \(marketPath)"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            masteryTrailingIcon(state: masteryState)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderImageLayoutView(renderImage: UIImage, masteryState: MasteryLevelState?) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: renderImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    itemTitleLabel(lineLimit: 2)
                    Text(categoryGroupIDText)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                masteryTrailingIcon(state: masteryState)
            }
            .contextMenu { itemNameContextMenu(includeSaveImage: true) }
            .padding(.horizontal, standardPadding * 2)
            .padding(.vertical, standardPadding)
            .background(masteryBackdrop(for: masteryState))
            .foregroundColor(.white)
        }
        // 图片四角圆角与文字遮罩共用同一裁剪，文字块无需自身圆角
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 渲染图文字遮罩背景：底层恒定半透明黑，右侧叠加专精色透明度淡入
    /// 叠加式可避免黑↔彩色的 RGB 插值（中间段发灰），色相全程纯正
    /// 自身无需圆角，由外层 clipShape 跟随图片圆角裁剪
    private func masteryBackdrop(for state: MasteryLevelState?) -> some View {
        ZStack {
            Color.black.opacity(0.5)

            if let masteryColor = masteryBackdropColor(for: state) {
                LinearGradient(
                    stops: [
                        .init(color: masteryColor.opacity(0), location: 0.4),
                        .init(color: masteryColor.opacity(0.9), location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private func originalLayoutView() -> some View {
        HStack(alignment: .center) {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                itemTitleLabel(lineLimit: nil)
                    .contextMenu { itemNameContextMenu(includeSaveImage: false) }
                Text(categoryGroupIDText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemTitleLabel(lineLimit: Int?) -> some View {
        HStack(spacing: 0) {
            Text(itemTitleDisplayName)
                .font(.title)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .contentTransition(.interpolate)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleItemNameLanguageAnimated)
    }

    @ViewBuilder
    private func itemNameContextMenu(includeSaveImage: Bool) -> some View {
        Button {
            UIPasteboard.general.string = itemTitleDisplayName
        } label: {
            Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
        }
        if let alt = itemTitleAlternateName {
            Button {
                UIPasteboard.general.string = alt
            } label: {
                Label(NSLocalizedString("Misc_Copy_Trans", comment: ""), systemImage: "translate")
            }
        }
        if includeSaveImage {
            Button {
                saveRenderImageToPhotos()
            } label: {
                Label(
                    NSLocalizedString("Misc_Save_Render_Image", comment: ""),
                    systemImage: "photo"
                )
            }
        }
    }

    private func iconTitleRow(icon: String, title: String) -> some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(title)
            Spacer()
        }
    }

    /// 专精等级行：locked = 驾驶技能未满足，level = 当前专精等级图标
    @ViewBuilder
    private func masteryRow(for state: MasteryLevelState) -> some View {
        let romanNumerals = ["0", "I", "II", "III", "IV", "V"]

        switch state {
        case .locked:
            iconTitleRow(
                icon: MasteryDisplayHelper.iconName(for: state),
                title: NSLocalizedString("Item_Mastery_Locked", comment: "未满足飞船驾驶技能")
            )
        case let .level(level):
            iconTitleRow(
                icon: MasteryDisplayHelper.iconName(for: state),
                title: String(
                    format: NSLocalizedString("Item_Mastery_Level", comment: "专精等级"),
                    romanNumerals[min(max(level, 0), 5)]
                )
            )
        }
    }

    private func basicStatRow(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = .secondary
    ) -> some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .frame(alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func toggleItemNameLanguageAnimated() {
        guard itemNameCanToggleEnglish else { return }
        withAnimation(Self.itemNameToggleAnimation) {
            itemNameShowsEnglish.toggle()
        }
    }

    private func getAttributeValue(attributeId: Int, originalValue: Double?) -> Double? {
        modifiedAttributes?[attributeId] ?? originalValue
    }

    private func getAttributeColor(attributeId: Int, originalValue: Double?) -> Color {
        guard let originalValue,
              let modifiedValue = modifiedAttributes?[attributeId]
        else { return .secondary }

        if abs(modifiedValue - originalValue) < 0.0001 {
            return .secondary
        }

        // mass(4): 越小越好；capacity(38): 越大越好
        let highIsGood = attributeId == 38
        if highIsGood {
            return modifiedValue > originalValue ? .green : .red
        }
        return modifiedValue < originalValue ? .green : .red
    }

    private func saveRenderImageToPhotos() {
        guard let renderImage else { return }
        ImageSaver.saveImage(renderImage) { success in
            if success {
                showSaveSuccess = true
            } else {
                showSaveError = true
            }
        }
    }

    private func fetchMarketPath(for marketGroupID: Int?) {
        guard let marketGroupID else {
            marketPath = ""
            return
        }

        Task {
            do {
                let path = try await getMarketGroupPath(groupID: marketGroupID)
                await MainActor.run {
                    marketPath = path.joined(separator: " / ")
                }
            } catch {
                Logger.error("获取市场目录路径失败: \(error.localizedDescription)")
                await MainActor.run {
                    marketPath = ""
                }
            }
        }
    }

    private func getMarketGroupPath(groupID: Int) async throws -> [String] {
        var path: [String] = []
        var currentGroupID = groupID
        var iterations = 0
        let maxIterations = 100

        while currentGroupID != 0, iterations < maxIterations {
            iterations += 1
            guard let group = SDEMemoryStore.marketGroup(for: currentGroupID) else { return path }

            path.insert(group.name, at: 0)

            if let parentGroupID = group.parentGroupID, parentGroupID > 0 {
                if parentGroupID == currentGroupID || path.count >= maxIterations {
                    Logger.warning("检测到可能的循环引用或过深的市场目录路径，中止查询")
                    return path
                }
                currentGroupID = parentGroupID
            } else {
                return path
            }
        }

        if iterations >= maxIterations {
            Logger.warning("市场目录路径查询达到最大迭代次数 \(maxIterations)，可能存在循环引用")
        }
        return path
    }

    private func loadRenderImage(for itemID: Int) {
        guard let categoryID = itemDetails.categoryID,
              Self.renderImageCategories.contains(categoryID) else { return }
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: itemID, size: 512
                )
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        renderImage = image
                    }
                }
            } catch {
                Logger.error("加载渲染图失败: \(error.localizedDescription)")
            }
        }
    }

    private func checkModelAvailability() {
        Task {
            do {
                let available = try await AvailableModelsAPI.shared.isModelAvailable(
                    itemDetails.typeId
                )
                await MainActor.run {
                    isModelAvailable = available
                }
            } catch {
                Logger.debug("检查模型可用性失败: \(error.localizedDescription)")
                await MainActor.run {
                    isModelAvailable = false
                }
            }
        }
    }
}
