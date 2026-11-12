import SwiftUI

// 实体详情页公共组件
// 提取 CharacterDetailView / CorporationDetailView / AllianceDetailView 中重复的 UI 组件和逻辑

// MARK: - 声望数据加载

/// 声望数据集合
struct StandingsData {
    var myCorpInfo: (name: String, icon: UIImage?)?
    var myAllianceInfo: (name: String, icon: UIImage?)?
    var personalStandings: [Int: Double] = [:]
    var corpStandings: [Int: Double] = [:]
    var allianceStandings: [Int: Double] = [:]
}

/// 声望数据加载器
/// 封装三个 DetailView 中完全相同的 loadStandings() 逻辑
enum StandingsLoader {
    static func loadStandings(for character: EVECharacterInfo) async -> StandingsData {
        var data = StandingsData()

        // 加载我的军团信息
        if let corpId = character.corporationId {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corpId
            ) {
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corpId
                )
                data.myCorpInfo = (name: corpInfo.name, icon: corpIcon)
            }
        }

        // 加载我的联盟信息
        if let allianceId = character.allianceId {
            let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId])
            if let allianceName = allianceNames?[allianceId]?.name {
                let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId
                )
                data.myAllianceInfo = (name: allianceName, icon: allianceIcon)
            }
        }

        // 加载个人声望
        if let contacts = try? await GetCharContacts.shared.fetchContacts(
            characterId: character.CharacterID
        ) {
            for contact in contacts {
                data.personalStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载军团声望
        if let corpId = character.corporationId,
           let contacts = try? await GetCorpContacts.shared.fetchContacts(
               characterId: character.CharacterID, corporationId: corpId
           )
        {
            for contact in contacts {
                data.corpStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载联盟声望
        if let allianceId = character.allianceId,
           let contacts = try? await GetAllianceContacts.shared.fetchContacts(
               characterId: character.CharacterID, allianceId: allianceId
           )
        {
            for contact in contacts {
                data.allianceStandings[contact.contact_id] = contact.standing
            }
        }

        return data
    }
}

// MARK: - 声望行视图

/// 声望行视图（统一实现，替换三个 DetailView 中的重复 StandingRowView）
struct StandingRowView: View {
    let leftPortrait: (id: Int, type: MailRecipient.RecipientType)
    let rightPortrait: (id: Int, type: MailRecipient.RecipientType)
    let leftName: String
    let rightName: String
    let standing: Double?
    @State private var leftImage: UIImage?
    @State private var rightImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧头像和名称
                HStack(spacing: 6) {
                    Text(leftName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if let image = leftImage {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                    } else {
                        Color.gray
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                    }
                }
                .frame(width: geometry.size.width * 0.4, alignment: .trailing)

                // 中间声望值
                if let standing = standing {
                    Text(
                        standing > 0
                            ? "+\(String(format: "%.0f", standing))"
                            : standing < 0 ? "\(String(format: "%.0f", standing))" : "0"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(StandingColorProvider.color(for: standing))
                    .frame(width: geometry.size.width * 0.2, alignment: .center)
                } else {
                    Text("0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: geometry.size.width * 0.2, alignment: .center)
                }

                // 右侧头像和名称
                HStack(spacing: 6) {
                    if let image = rightImage {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                    } else {
                        Color.gray
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                    }
                    Text(rightName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .frame(width: geometry.size.width * 0.4, alignment: .leading)
            }
        }
        .frame(height: 32) // 设置固定高度以确保一致性
        .task {
            await loadImages()
        }
    }

    private func loadImages() async {
        // 加载左侧头像
        switch leftPortrait.type {
        case .character:
            leftImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: leftPortrait.id
            )
        case .corporation:
            leftImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                corporationId: leftPortrait.id
            )
        case .alliance:
            leftImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                allianceID: leftPortrait.id
            )
        default:
            break
        }

        // 加载右侧头像
        switch rightPortrait.type {
        case .character:
            rightImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: rightPortrait.id, catchImage: false
            )
        case .corporation:
            rightImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                corporationId: rightPortrait.id
            )
        case .alliance:
            rightImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                allianceID: rightPortrait.id
            )
        default:
            break
        }
    }
}

// MARK: - 声望颜色

/// 声望值颜色提供者（统一三个 DetailView 中不同的实现）
enum StandingColorProvider {
    static func color(for standing: Double) -> Color {
        switch standing {
        case 10.0:
            return Color.blue // 深蓝
        case 5.0 ..< 10.0:
            return Color.blue // 深蓝
        case 0.1 ..< 5.0:
            return Color(red: 0.3, green: 0.7, blue: 1.0) // 浅蓝
        case 0.0:
            return Color.secondary // 次要颜色
        case -5.0 ..< 0.0:
            return Color(red: 1.0, green: 0.5, blue: 0.0) // 橙红
        case -10.0 ... -5.0:
            return Color.red // 红色
        case ..<(-10.0):
            return Color.red // 红色
        default:
            return Color.secondary
        }
    }
}

// MARK: - ID 复制 Footer

/// 实体 ID 复制 Footer（统一三个 DetailView 中的 ID 复制按钮）
struct EntityIdCopyFooter: View {
    let entityId: Int
    @State private var idCopied: Bool = false

    var body: some View {
        Button {
            UIPasteboard.general.string = String(entityId)
            idCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                idCopied = false
            }
        } label: {
            HStack(spacing: 4) {
                Spacer()
                if idCopied {
                    Text(NSLocalizedString("Misc_Copied", comment: ""))
                        .font(.caption)
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .frame(width: 12, height: 12)
                }
                Text("ID: \(String(entityId))")
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!idCopied)
    }
}

// MARK: - 外部链接按钮

/// 实体外部链接类型
enum EntityLinkType: String {
    case character
    case corporation
    case alliance
}

/// 实体外部链接按钮（Eve Who + zKillboard）
/// 不含 Section 包装，由调用方根据布局需要自行包装
struct EntityExternalLinkButtons: View {
    let entityId: Int
    let linkType: EntityLinkType

    var body: some View {
        Button(action: {
            if let url = URL(string: "https://evewho.com/\(linkType.rawValue)/\(entityId)") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Eve Who").foregroundColor(.primary)
                    Text(NSLocalizedString("Open_In_Browser", comment: ""))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.blue)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        Button(action: {
            if let url = URL(string: "https://zkillboard.com/\(linkType.rawValue)/\(entityId)/") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text("zKillboard").foregroundColor(.primary)
                    Text(NSLocalizedString("Open_In_Browser", comment: ""))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.blue)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// MARK: - 势力信息行

/// 势力信息行（统一三个 DetailView 中的势力信息显示）
struct EntityFactionRow: View {
    let factionInfo: (name: String, iconName: String)

    var body: some View {
        HStack(spacing: 8) {
            Text("\(NSLocalizedString("Character_Faction", comment: ""))")
            Spacer()
            IconManager.shared.loadImage(for: factionInfo.iconName)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(factionInfo.name)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 加载/错误占位 Section

/// 详情页加载中占位
struct DetailLoadingSection: View {
    var body: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
    }
}

/// 详情页错误占位
struct DetailErrorSection: View {
    let error: Error

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
        }
    }
}
