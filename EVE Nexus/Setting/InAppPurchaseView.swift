import SwiftUI

struct InAppPurchaseView: View {
    @StateObject private var iconManager = AppIconManager.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var changingIconId: String? = nil
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""

    // 使用统一配置
    private let iconList = AppIconConfig.iconList
    private let badgeList = AppIconConfig.badgeList
    private let selectedIconKey = AppIconConfig.selectedIconKey
    private let selectedBadgeKey = AppIconConfig.selectedBadgeKey

    /// 选中的图标和角标（从保存的值初始化）
    @State private var selectedIcon: String = {
        if let savedIcon = UserDefaults.standard.string(forKey: "selectedAppIconName"),
           ["Tritanium_basic", "Tritanium", "TriDB", "OverseerBox", "HyperCore"].contains(savedIcon)
        {
            return savedIcon
        }
        return "Tritanium"
    }()

    @State private var selectedBadge: String = {
        if let savedBadge = UserDefaults.standard.string(forKey: "selectedAppIconBadge"),
           ["T1", "T2", "T3", "Factions", "Deadspace", "Officers"].contains(savedBadge)
        {
            return savedBadge
        }
        return "T1"
    }()

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let preview = AppIconConfig.composeAppIcon(icon: selectedIcon, badge: selectedBadge) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Icon_\(selectedIcon)", comment: ""))
                            .font(.headline)
                        Text(NSLocalizedString("IAP_Free_Icons_Badge_Charge", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if changingIconId != nil {
                        ProgressView()
                    }
                }
                .padding(.vertical, 2)
            }

            Section(header: Text(NSLocalizedString("IAP_Choose_Icon", comment: "图标样式"))) {
                ForEach(iconList, id: \.self) { iconName in
                    iconRow(iconName)
                }
            }

            Section {
                BottomSelectionView(
                    badgeList: badgeList,
                    selectedBadge: $selectedBadge,
                    purchaseManager: purchaseManager,
                    onPurchaseRequest: { handlePurchaseRequest(for: $0) }
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text(NSLocalizedString("IAP_Choose_Badge", comment: "角标与赞助"))
            } footer: {
                Label(NSLocalizedString("IAP_Sponsor_Gift", comment: ""), systemImage: "gift")
                    .padding(.top, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_In_App_Purchase", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await purchaseManager.restorePurchases()
                        // 只在发生错误时提示
                        if let error = purchaseManager.errorMessage {
                            await MainActor.run {
                                errorAlertMessage = error
                                showingErrorAlert = true
                            }
                        }
                    }
                }) {
                    Text(NSLocalizedString("Purchase_Restore", comment: ""))
                }
                .disabled(purchaseManager.isLoading)
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text(NSLocalizedString("Purchase_Alert_Title", comment: "")),
                message: Text(errorAlertMessage),
                dismissButton: .default(Text(NSLocalizedString("Purchase_Alert_OK", comment: "")))
            )
        }
        .onAppear {
            loadSavedSelection()
            // 如果产品列表为空，尝试加载（通常已在应用启动时加载）
            if purchaseManager.products.isEmpty && !purchaseManager.isLoading {
                Task {
                    await purchaseManager.loadProducts()
                }
            }
        }
        .onChange(of: selectedIcon) { _, _ in
            saveSelection()
            Task {
                await applyIconChange()
            }
        }
        .onChange(of: selectedBadge) { _, _ in
            saveSelection()
            Task {
                await applyIconChange()
            }
        }
        .onChange(of: purchaseManager.purchasedRanks) { _, _ in
            // 当购买状态变化时（如后台检测到退款），验证当前选中的角标
            if !purchaseManager.isBadgeUnlocked(selectedBadge) {
                // 如果当前角标失效，回退到第一个免费角标（T1）
                Logger.info("[!] 检测到当前角标 \(selectedBadge) 已失效，自动回退到 T1")
                selectedBadge = "T1"
            }
        }
    }

    /// 根据选择的图标和角标生成图标ID
    private func iconRow(_ iconName: String) -> some View {
        let isSelected = selectedIcon == iconName
        return IconSelectionRow(iconName: iconName, isSelected: isSelected) {
            selectedIcon = iconName
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func getIconId() -> String? {
        return AppIconConfig.getIconId(icon: selectedIcon, badge: selectedBadge)
    }

    /// 从图标ID解析图标名称和角标
    private func parseIconId(_ iconId: String?) -> (icon: String, badge: String) {
        return AppIconConfig.parseIconId(iconId)
    }

    /// 加载保存的选择
    private func loadSavedSelection() {
        // 优先从 UserDefaults 读取保存的图标和角标
        if let savedIcon = UserDefaults.standard.string(forKey: selectedIconKey),
           iconList.contains(savedIcon)
        {
            selectedIcon = savedIcon
        }

        if let savedBadge = UserDefaults.standard.string(forKey: selectedBadgeKey),
           badgeList.contains(savedBadge)
        {
            // 检查该角标是否已解锁（T1/T2/T3 始终免费）
            if purchaseManager.isBadgeUnlocked(savedBadge) {
                selectedBadge = savedBadge
            } else {
                // 如果未解锁（可能是付费角标且已退款），回退到默认的 T1
                Logger.info("[!] 已缓存的角标 \(savedBadge) 未解锁（可能已退款），回退到 T1")
                selectedBadge = "T1"
                saveSelection() // 更新缓存
            }
        }

        // 如果 UserDefaults 中没有保存的值，尝试从 AppIconManager 解析当前图标ID
        if UserDefaults.standard.string(forKey: selectedIconKey) == nil,
           let currentIconId = iconManager.currentIconName, !currentIconId.isEmpty
        {
            let parsed = parseIconId(currentIconId)
            selectedIcon = parsed.icon

            // 验证解析出的角标是否已解锁（T1/T2/T3 始终免费）
            if purchaseManager.isBadgeUnlocked(parsed.badge) {
                selectedBadge = parsed.badge
            } else {
                Logger.info("[!] 解析的角标 \(parsed.badge) 未解锁，回退到 T1")
                selectedBadge = "T1"
            }

            // 保存解析后的值，以便下次直接使用
            saveSelection()
        }
    }

    /// 保存当前选择
    private func saveSelection() {
        UserDefaults.standard.set(selectedIcon, forKey: selectedIconKey)
        UserDefaults.standard.set(selectedBadge, forKey: selectedBadgeKey)
    }

    private func applyIconChange() async {
        let iconId = getIconId()
        changingIconId = iconId ?? ""

        do {
            try await iconManager.setIcon(iconId)
        } catch {
            Logger.error("切换应用图标失败: \(error)")
        }

        await MainActor.run {
            changingIconId = nil
        }
    }

    /// 处理购买请求（赞助）
    private func handlePurchaseRequest(for badge: String) {
        guard !purchaseManager.isBadgeUnlocked(badge) else {
            // 已解锁，直接选择
            selectedBadge = badge
            return
        }

        Task {
            // 如果产品列表为空，先加载产品
            if purchaseManager.products.isEmpty {
                await purchaseManager.loadProducts()
            }

            guard let productID = purchaseManager.getProductID(for: badge),
                  let product = purchaseManager.products.first(where: { $0.id == productID })
            else {
                // 找不到产品 - 这是关键错误，需要提示
                await MainActor.run {
                    errorAlertMessage = NSLocalizedString("Purchase_Product_Not_Found", comment: "")
                    showingErrorAlert = true
                }
                Logger.error("[x] 找不到产品ID: \(badge)")
                return
            }

            // 赞助流程：成功后会解锁所有付费角标
            let success = await purchaseManager.purchase(product, for: badge)
            if success {
                await MainActor.run {
                    // 购买成功后，自动选择当前点击的角标
                    selectedBadge = badge
                }
            }
        }
    }
}

/// 图标选择行
struct IconSelectionRow: View {
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 左侧图标
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // 右侧名称和描述
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Icon_\(iconName)", comment: ""))
                        .foregroundColor(.primary)
                        .font(.body)

                    Text(NSLocalizedString("Icon_\(iconName)_Desc", comment: ""))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 与图标列表一起滚动的角标选择和赞助入口
struct BottomSelectionView: View {
    let badgeList: [String]
    @Binding var selectedBadge: String
    @ObservedObject var purchaseManager: PurchaseManager
    let onPurchaseRequest: (String) -> Void

    /// 免费角标列表
    private let freeBadges = ["T1", "T2", "T3"]
    /// 付费角标列表
    private let paidBadges = ["Factions", "Deadspace", "Officers"]

    /// 检查是否所有付费角标都已解锁
    private var allPaidBadgesUnlocked: Bool {
        paidBadges.allSatisfy { purchaseManager.isBadgeUnlocked($0) }
    }

    /// 获取赞助价格
    private var sponsorPrice: String? {
        purchaseManager.getPriceString(for: "Factions")
    }

    /// 是否正在赞助（检查是否有任何付费角标正在购买）
    private var isSponsoring: Bool {
        if let purchasingBadge = purchaseManager.purchasingBadge {
            return paidBadges.contains(purchasingBadge)
        }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
            // 免费角标组
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    ForEach(freeBadges, id: \.self) { badge in
                        BadgeSelectionCell(
                            badgeName: badge,
                            isSelected: selectedBadge == badge,
                            isUnlocked: true, // 始终解锁
                            showPrice: false, // 不显示价格
                            isPurchasing: false
                        ) {
                            selectedBadge = badge
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 免费标签
                Text(NSLocalizedString("Purchase_Price_Free", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 分隔线
            Divider()
                .padding(.vertical, 2)

            // 付费角标组
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    ForEach(paidBadges, id: \.self) { badge in
                        BadgeSelectionCell(
                            badgeName: badge,
                            isSelected: selectedBadge == badge,
                            isUnlocked: purchaseManager.isBadgeUnlocked(badge),
                            showPrice: false, // 不显示价格
                            isPurchasing: false
                        ) {
                            if purchaseManager.isBadgeUnlocked(badge) {
                                selectedBadge = badge
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 统一的赞助按钮
                if allPaidBadgesUnlocked {
                    // 已解锁：显示"已解锁"标签
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(NSLocalizedString("Purchase_All_Badges_Unlocked", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // 未解锁：显示赞助按钮
                    Button(action: {
                        // 点击任意付费角标都会触发赞助
                        onPurchaseRequest(paidBadges.first ?? "Factions")
                    }) {
                        HStack(spacing: 6) {
                            if isSponsoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "gift.fill")
                                    .font(.subheadline)
                            }
                            if let price = sponsorPrice, !isSponsoring {
                                Text(NSLocalizedString("Purchase_Sponsor_Unlock_All", comment: ""))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(price)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            } else if isSponsoring {
                                Text(NSLocalizedString("Purchase_Processing", comment: ""))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            } else {
                                Text(NSLocalizedString("Purchase_Sponsor_Unlock_All", comment: ""))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSponsoring || purchaseManager.isLoading)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 角标选择单元格
struct BadgeSelectionCell: View {
    let badgeName: String
    let isSelected: Bool
    let isUnlocked: Bool
    let showPrice: Bool // 是否显示价格标签
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                ZStack {
                    if badgeName == "T1" {
                        // T1角标显示为空白圆角虚线框，中间显示减号
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                            )
                            .foregroundColor(.secondary)

                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else {
                        // 其他角标显示图标
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))

                        Image(badgeName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(4)
                            .opacity(isUnlocked ? 1.0 : 0.5)

                        // 锁定覆盖层
                        if !isUnlocked {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.3))

                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(badgeName)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .disabled(isPurchasing)
        }
    }
}
