import SwiftUI

struct ContractRow: View {
    @State private var shouldUseCompactLayout = false

    @Environment(\.timeZone) private var displayTimeZone
    let contract: ContractInfo
    let contractType: PersonalContractsViewModel.ContractType
    let databaseManager: DatabaseManager
    let groupingMode: PersonalContractsViewModel.GroupingMode
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    private func formatContractType(_ type: String) -> String {
        return NSLocalizedString("Contract_Type_\(type)", comment: "")
    }

    private func formatContractStatus(_ status: String) -> String {
        // 将所有finished相关状态统一显示为"finished"
        let normalizedStatus: String
        switch status {
        case "finished", "finished_issuer", "finished_contractor":
            normalizedStatus = "finished"
        default:
            normalizedStatus = status
        }
        return NSLocalizedString("Contract_Status_\(normalizedStatus)", comment: "")
    }

    /// 判断当前角色是否是合同发布者
    private var isIssuer: Bool {
        switch contractType {
        case .personal:
            // 个人合同：检查是否是当前角色发布的
            return contract.issuer_id == currentCharacterId
        case .corporation:
            // 军团合同：检查是否是军团发布的合同
            return contract.for_corporation
        case .alliance:
            // 联盟合同：检查是否是当前角色发布的
            return contract.issuer_id == currentCharacterId
        }
    }

    /// 判断当前角色是否是合同接收者
    private var isAcceptor: Bool {
        switch contractType {
        case .personal:
            // 个人合同：检查是否是指定给当前角色的
            return contract.acceptor_id == currentCharacterId
        case .corporation:
            // 军团合同：检查是否是指定给军团的
            return contract.assignee_id == contract.issuer_corporation_id
        case .alliance:
            // 联盟合同：检查是否是指定给联盟的
            return contract.acceptor_id == currentCharacterId
        }
    }

    /// 字段显示信息
    private struct FieldDisplayInfo {
        let value: Double // 字段值
        let prefix: String // 符号：+、- 或空字符串
        let color: Color // 颜色
    }

    /// 合同价格显示信息：包含要显示的所有字段
    private struct ContractPriceDisplayInfo {
        let fields: [FieldDisplayInfo] // 要显示的字段列表（可能包含 price 和/或 reward）
    }

    /*
     * 合同价格显示逻辑说明
     * ===================
     *
     * 1. 物品交换合同 (item_exchange)
     *    - 角色：发起人/接收者
     *    - price 字段：发起人显示收入（绿色+），接收者显示支出（红色-）
     *    - reward 字段：发起人显示支出（红色-），接收者显示收入（绿色+）
     *
     *    场景1：price > 0 && reward > 0
     *      - 发起人：显示 [+price 绿色] [-reward 红色]
     *      - 接收者：显示 [-price 红色] [+reward 绿色]
     *
     *    场景2：只有 price > 0
     *      - 发起人：显示 [+price 绿色]
     *      - 接收者：显示 [-price 红色]
     *
     *    场景3：只有 reward > 0
     *      - 发起人：显示 [-reward 红色]
     *      - 接收者：显示 [+reward 绿色]
     *
     *    场景4：price = 0 && reward = 0
     *      - 发起人：显示 [+0 绿色]（显示 price）
     *      - 接收者：显示 [-0 红色]（显示 price）
     *
     * 2. 运输合同 (courier)
     *    - 角色：发起人/接收者
     *    - reward 字段：发起人显示支出（红色-），接收者显示收入（绿色+）
     *    - price 字段：通常不使用，如果出现则显示为灰色无符号
     *
     *    场景1：price > 0 && reward > 0
     *      - 发起人：显示 [price 灰色] [-reward 红色]
     *      - 接收者：显示 [price 灰色] [+reward 绿色]
     *
     *    场景2：只有 reward > 0
     *      - 发起人：显示 [-reward 红色]
     *      - 接收者：显示 [+reward 绿色]
     *
     *    场景3：只有 price > 0（不常见）
     *      - 显示 [price 灰色]
     *
     *    场景4：price = 0 && reward = 0
     *      - 发起人：显示 [-0 红色]（显示 reward）
     *      - 接收者：显示 [+0 绿色]（显示 reward）
     *
     * 3. 拍卖合同 (auction)
     *    - 角色：发起人/接收者/其他角色
     *    - price 字段：
     *      * 发起人：收入（绿色+）
     *      * 接收者：支出（红色-）
     *      * 其他角色：无符号，橙色
     *    - reward 字段：始终为收入（绿色+）
     *
     *    场景1：price > 0 && reward > 0
     *      - 发起人：显示 [+price 绿色] [+reward 绿色]
     *      - 接收者：显示 [-price 红色] [+reward 绿色]
     *      - 其他角色：显示 [price 橙色] [+reward 绿色]
     *
     *    场景2：只有 price > 0
     *      - 发起人：显示 [+price 绿色]
     *      - 接收者：显示 [-price 红色]
     *      - 其他角色：显示 [price 橙色]
     *
     *    场景3：只有 reward > 0
     *      - 所有角色：显示 [+reward 绿色]
     *
     *    场景4：price = 0 && reward = 0
     *      - 发起人：显示 [+0 绿色]（显示 price）
     *      - 接收者：显示 [-0 红色]（显示 price）
     *      - 其他角色：显示 [0 橙色]（显示 price）
     */

    /// 统一的显示信息计算函数：根据合同类型、字段值和角色决定显示哪些字段及其格式
    private func getContractPriceDisplayInfo(
        contractType: String,
        price: Double,
        reward: Double,
        contractTypeEnum: PersonalContractsViewModel.ContractType
    ) -> ContractPriceDisplayInfo {
        let hasPrice = price > 0
        let hasReward = reward > 0
        let isCurrentUserIssuer = contract.issuer_id == currentCharacterId
        var fields: [FieldDisplayInfo] = []

        switch contractType {
        case "item_exchange":
            // 物品交换合同
            if hasPrice && hasReward {
                // 两个字段都有值：都显示
                // price 字段：发布者显示收入（绿色+），接收者显示支出（红色-）
                let pricePrefix: String
                let priceColor: Color
                switch contractTypeEnum {
                case .personal:
                    pricePrefix = isIssuer ? "+" : "-"
                    priceColor = isIssuer ? .green : .red
                case .corporation, .alliance:
                    pricePrefix = isCurrentUserIssuer ? "+" : "-"
                    priceColor = isCurrentUserIssuer ? .green : .red
                }
                fields.append(FieldDisplayInfo(value: price, prefix: pricePrefix, color: priceColor))

                // reward 字段：发布者显示支出（红色-），接收者显示收入（绿色+）
                let rewardPrefix: String
                let rewardColor: Color
                switch contractTypeEnum {
                case .personal:
                    rewardPrefix = isIssuer ? "-" : "+"
                    rewardColor = isIssuer ? .red : .green
                case .corporation, .alliance:
                    rewardPrefix = isCurrentUserIssuer ? "-" : "+"
                    rewardColor = isCurrentUserIssuer ? .red : .green
                }
                fields.append(FieldDisplayInfo(value: reward, prefix: rewardPrefix, color: rewardColor))
            } else if hasPrice {
                // 只有 price 有值
                let prefix: String
                let color: Color
                switch contractTypeEnum {
                case .personal:
                    prefix = isIssuer ? "+" : "-"
                    color = isIssuer ? .green : .red
                case .corporation, .alliance:
                    prefix = isCurrentUserIssuer ? "+" : "-"
                    color = isCurrentUserIssuer ? .green : .red
                }
                fields.append(FieldDisplayInfo(value: price, prefix: prefix, color: color))
            } else if hasReward {
                // 只有 reward 有值
                let prefix: String
                let color: Color
                switch contractTypeEnum {
                case .personal:
                    prefix = isIssuer ? "-" : "+"
                    color = isIssuer ? .red : .green
                case .corporation, .alliance:
                    prefix = isCurrentUserIssuer ? "-" : "+"
                    color = isCurrentUserIssuer ? .red : .green
                }
                fields.append(FieldDisplayInfo(value: reward, prefix: prefix, color: color))
            } else {
                // 两个都为0：显示 price
                let prefix: String
                let color: Color
                switch contractTypeEnum {
                case .personal:
                    prefix = isIssuer ? "+" : "-"
                    color = isIssuer ? .green : .red
                case .corporation, .alliance:
                    prefix = isCurrentUserIssuer ? "+" : "-"
                    color = isCurrentUserIssuer ? .green : .red
                }
                fields.append(FieldDisplayInfo(value: price, prefix: prefix, color: color))
            }

        case "courier":
            // 运输合同：主要显示 reward
            if hasPrice && hasReward {
                // 两个字段都有值：都显示（price 使用默认格式）
                fields.append(FieldDisplayInfo(value: price, prefix: "", color: .secondary))

                // reward 字段：发布者显示支出（红色-），接收者显示收入（绿色+）
                let rewardPrefix: String
                let rewardColor: Color
                switch contractTypeEnum {
                case .personal:
                    rewardPrefix = isIssuer ? "-" : "+"
                    rewardColor = isIssuer ? .red : .green
                case .corporation, .alliance:
                    rewardPrefix = isCurrentUserIssuer ? "-" : "+"
                    rewardColor = isCurrentUserIssuer ? .red : .green
                }
                fields.append(FieldDisplayInfo(value: reward, prefix: rewardPrefix, color: rewardColor))
            } else if hasReward {
                // 只有 reward 有值
                let prefix: String
                let color: Color
                switch contractTypeEnum {
                case .personal:
                    prefix = isIssuer ? "-" : "+"
                    color = isIssuer ? .red : .green
                case .corporation, .alliance:
                    prefix = isCurrentUserIssuer ? "-" : "+"
                    color = isCurrentUserIssuer ? .red : .green
                }
                fields.append(FieldDisplayInfo(value: reward, prefix: prefix, color: color))
            } else if hasPrice {
                // 只有 price 有值（不常见）
                fields.append(FieldDisplayInfo(value: price, prefix: "", color: .secondary))
            } else {
                // 两个都为0：显示 reward
                let prefix: String
                let color: Color
                switch contractTypeEnum {
                case .personal:
                    prefix = isIssuer ? "-" : "+"
                    color = isIssuer ? .red : .green
                case .corporation, .alliance:
                    prefix = isCurrentUserIssuer ? "-" : "+"
                    color = isCurrentUserIssuer ? .red : .green
                }
                fields.append(FieldDisplayInfo(value: reward, prefix: prefix, color: color))
            }

        case "auction":
            // 拍卖合同
            if hasPrice && hasReward {
                // 两个字段都有值：都显示
                // price 字段
                let pricePrefix: String
                let priceColor: Color
                if isIssuer {
                    pricePrefix = "+"
                    priceColor = .green
                } else if isAcceptor {
                    pricePrefix = "-"
                    priceColor = .red
                } else {
                    pricePrefix = ""
                    priceColor = .orange
                }
                fields.append(FieldDisplayInfo(value: price, prefix: pricePrefix, color: priceColor))

                // reward 字段：拍卖合同的 reward 通常为收入（绿色+）
                fields.append(FieldDisplayInfo(value: reward, prefix: "+", color: .green))
            } else if hasPrice {
                // 只有 price 有值
                let prefix: String
                let color: Color
                if isIssuer {
                    prefix = "+"
                    color = .green
                } else if isAcceptor {
                    prefix = "-"
                    color = .red
                } else {
                    prefix = ""
                    color = .orange
                }
                fields.append(FieldDisplayInfo(value: price, prefix: prefix, color: color))
            } else if hasReward {
                // 只有 reward 有值
                fields.append(FieldDisplayInfo(value: reward, prefix: "+", color: .green))
            } else {
                // 两个都为0：显示 price
                let prefix: String
                let color: Color
                if isIssuer {
                    prefix = "+"
                    color = .green
                } else if isAcceptor {
                    prefix = "-"
                    color = .red
                } else {
                    prefix = ""
                    color = .orange
                }
                fields.append(FieldDisplayInfo(value: price, prefix: prefix, color: color))
            }

        default:
            // 其他合同类型：默认显示 price
            if hasPrice {
                fields.append(FieldDisplayInfo(value: price, prefix: "", color: .secondary))
            } else if hasReward {
                fields.append(FieldDisplayInfo(value: reward, prefix: "", color: .secondary))
            }
        }

        return ContractPriceDisplayInfo(fields: fields)
    }

    /// 根据字段显示信息创建文本视图
    private func createFieldText(_ fieldInfo: FieldDisplayInfo) -> some View {
        Text("\(fieldInfo.prefix)\(FormatUtil.format(fieldInfo.value)) ISK")
            .foregroundColor(fieldInfo.color)
            .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder
    private func priceView() -> some View {
        let displayInfo = getContractPriceDisplayInfo(
            contractType: contract.type,
            price: contract.price,
            reward: contract.reward,
            contractTypeEnum: contractType
        )

        if displayInfo.fields.isEmpty {
            EmptyView()
        } else if displayInfo.fields.count == 1 {
            // 只显示一个字段
            createFieldText(displayInfo.fields[0])
        } else {
            // 显示多个字段（用 HStack 排列）
            HStack(spacing: 8) {
                ForEach(Array(displayInfo.fields.enumerated()), id: \.offset) { _, fieldInfo in
                    createFieldText(fieldInfo)
                }
            }
        }
    }

    var body: some View {
        NavigationLink {
            ContractDetailView(
                characterId: currentCharacterId,
                contract: contract,
                databaseManager: databaseManager,
                contractType: contractType
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if shouldUseCompactLayout {
                    // 可用宽度足够时将状态、类型和价格并排显示
                    HStack {
                        Text(formatContractStatus(contract.status))
                            .font(.caption)
                            .foregroundColor(contractStatusColor(contract.status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                            )
                        Text(formatContractType(contract.type))
                            .font(.body)
                            .lineLimit(1)
                        Spacer()
                        priceView()
                    }

                    HStack {
                        Text(
                            NSLocalizedString("Contract_Title", comment: "") + ": "
                                + (contract.title.isEmpty
                                    ? "[\(NSLocalizedString("Contract_No_Title", comment: ""))]"
                                    : contract.title)
                        )
                        .font(.caption)
                        .foregroundColor(contract.title.isEmpty ? .secondary : .secondary)
                        .lineLimit(1)

                        Spacer()
                    }
                } else {
                    // 小屏幕：分离布局，类型和状态分开
                    // 第一行：类型和状态
                    HStack {
                        Text(formatContractType(contract.type))
                            .font(.body)
                            .lineLimit(1)

                        Spacer()

                        Text(formatContractStatus(contract.status))
                            .font(.caption)
                            .foregroundColor(contractStatusColor(contract.status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                            )
                    }

                    // 第二行：标题和价格
                    HStack {
                        Text(
                            NSLocalizedString("Contract_Title", comment: "") + ": "
                                + (contract.title.isEmpty
                                    ? "[\(NSLocalizedString("Contract_No_Title", comment: ""))]"
                                    : contract.title)
                        )
                        .font(.caption)
                        .foregroundColor(contract.title.isEmpty ? .secondary : .secondary)
                        .lineLimit(1)

                        Spacer()

                        priceView()
                    }
                }
                HStack {
                    Text(
                        NSLocalizedString("Contract_Volume", comment: "")
                            + ": \(FormatUtil.format(contract.volume)) m³"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    Spacer()

                    // 根据分组方式决定显示的时间
                    if groupingMode == .byIssueDate {
                        // 按发起时间分组：显示发起时间
                        if contract.status == "outstanding" {
                            // 计算剩余天数
                            let remainingDays =
                                Calendar.current.dateComponents(
                                    [.day],
                                    from: Date(),
                                    to: contract.date_expired
                                ).day ?? 0

                            if remainingDays > 0 {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(String.localizedStringWithFormat(NSLocalizedString("Contract_Days_Remaining", comment: ""), remainingDays)))"
                                )
                                .font(.caption)
                                .foregroundColor(.gray)
                            } else if remainingDays == 0 {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(NSLocalizedString("Contract_Expires_Today", comment: "")))"
                                )
                                .font(.caption)
                                .foregroundColor(.orange)
                            } else {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(NSLocalizedString("Contract_Expired", comment: "")))"
                                )
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        } else {
                            Text("\(FormatUtil.formatDateToLocalTime(contract.date_issued))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        // 按完成时间分组
                        if contract.status == "outstanding" || contract.status == "in_progress" {
                            // 未完成的合同：只显示剩余天数
                            if contract.status == "outstanding" {
                                // 计算剩余天数
                                let remainingDays =
                                    Calendar.current.dateComponents(
                                        [.day],
                                        from: Date(),
                                        to: contract.date_expired
                                    ).day ?? 0

                                if remainingDays > 0 {
                                    Text(String.localizedStringWithFormat(NSLocalizedString("Contract_Days_Remaining_Full", comment: ""), remainingDays))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else if remainingDays == 0 {
                                    Text(NSLocalizedString("Contract_Expires_Today", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text(NSLocalizedString("Contract_Expired", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            } else {
                                // in_progress 状态显示进行中
                                Text(NSLocalizedString("Contract_Status_in_progress", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            // 已完成的合同：显示完成时间
                            if let completedDate = contract.date_completed {
                                Text("\(FormatUtil.formatDateToLocalTime(completedDate))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            } else {
                                // 如果没有完成时间，降级显示发起时间
                                Text("\(FormatUtil.formatDateToLocalTime(contract.date_issued))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.size.width >= 560
            } action: { usesWideLayout in
                shouldUseCompactLayout = usesWideLayout
            }
            .padding(.vertical, 2)
            .contextMenu {
                if !contract.title.isEmpty {
                    Button {
                        UIPasteboard.general.string = contract.title
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Contract_Title", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }
                }
            }
        }
    }
}
