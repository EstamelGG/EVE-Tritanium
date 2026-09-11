import Foundation
import SwiftUI

struct AgentCellView: View {
    let agent: AgentItem
    @ObservedObject var databaseManager: DatabaseManager
    @State private var portraitImage: Image?
    @State private var isLoadingPortrait = true

    var body: some View {
        HStack(spacing: 12) {
            // 左侧头像
            ZStack {
                if isLoadingPortrait {
                    ProgressView()
                        .frame(width: 64, height: 64)
                } else if let image = portraitImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Image("default_char")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 64, height: 64)

            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                // 名称
                Text(agent.name)
                    .font(.headline)

                // 位置信息
                LocationInfoView(
                    stationName: agent.solarSystemID == nil ? agent.locationName : nil,
                    solarSystemName: agent.solarSystemName ?? agent.locationName,
                    security: agent.security,
                    locationId: agent.locationID > 0 ? Int64(agent.locationID) : nil,
                    font: .caption,
                    textColor: .secondary
                )

                // 势力和军团信息
                HStack(spacing: 8) {
                    IconManager.shared.loadImage(for: agent.factionIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .cornerRadius(2)

                    Text(agent.factionName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    IconManager.shared.loadImage(for: agent.corporationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .cornerRadius(2)

                    Text(agent.corporationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 标签行
                HStack(spacing: 8) {
                    // 等级标签
                    Text(
                        String(
                            format: NSLocalizedString("Agent_Level", comment: "L%d"), agent.level
                        )
                    )
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(getLevelColor(agent.level))
                    .foregroundColor(.white)
                    .cornerRadius(4)

                    // 部门标签
                    if !agent.divisionName.isEmpty {
                        Text(agent.divisionName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(getDivisionColor(agent.divisionID))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    // 代理人类型标签 - 不显示BasicAgent类型
                    if agent.agentType != 2 {
                        Text(getAgentTypeShortName(agent.agentType))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(getAgentTypeColor(agent.agentType))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    // 定位代理人标签
                    if agent.isLocator {
                        Text(NSLocalizedString("Agent_Locator", comment: "寻人代理人"))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    // 空间代理人标签
                    if agent.solarSystemID != nil {
                        Text(NSLocalizedString("Agent_Space", comment: "空间代理人"))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = agent.name
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_CharID", comment: ""),
                        systemImage: "doc.on.doc"
                    )
                }

                // 根据代理人位置类型决定是否显示复制位置按钮
                if agent.solarSystemID == nil && !agent.locationName.isEmpty {
                    // 空间站代理人，复制空间站名称
                    Button {
                        UIPasteboard.general.string = agent.locationName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Location", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }

                    // 显示名与英文名不同时，追加复制英文名
                    if agent.locationID > 0,
                       let enName = SDEMemoryStore.stationEnglishName(for: Int(agent.locationID)),
                       enName != agent.locationName
                    {
                        Button {
                            UIPasteboard.general.string = enName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                systemImage: "translate"
                            )
                        }
                    }
                } else if let systemName = agent.solarSystemName, !systemName.isEmpty {
                    // 空间代理人，复制星系名称
                    Button {
                        UIPasteboard.general.string = systemName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Location", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }

                    // 显示名与英文名不同时，追加复制英文名
                    if let solarSystemID = agent.solarSystemID,
                       let enName = SDEMemoryStore.solarSystemEnglishName(for: solarSystemID),
                       enName != systemName
                    {
                        Button {
                            UIPasteboard.general.string = enName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                systemImage: "translate"
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadPortrait()
        }
    }

    private func loadPortrait() {
        isLoadingPortrait = true

        Task {
            do {
                let uiImage = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: agent.agentID,
                    size: 128,
                    forceRefresh: false,
                    catchImage: true
                )
                portraitImage = Image(uiImage: uiImage)
                isLoadingPortrait = false
            } catch {
                isLoadingPortrait = false
                // 加载失败时不设置portraitImage，将显示默认图标
            }
        }
    }

    /// 根据等级获取颜色
    private func getLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.gray
        case 2: return Color.green
        case 3: return Color.blue
        case 4: return Color.purple
        case 5: return Color.red
        default: return Color.gray
        }
    }

    /// 根据部门ID获取颜色
    private func getDivisionColor(_ divisionID: Int) -> Color {
        switch divisionID {
        case 18: return Color.blue.opacity(0.8) // 研发 - 深蓝色
        case 22: return Color.purple.opacity(0.8) // 物流 - 紫色
        case 23: return Color(red: 0.8, green: 0.6, blue: 0.0) // 采矿 - 深黄色
        case 24: return Color.red.opacity(0.8) // 安全 - 深红色
        default: return Color.gray.opacity(0.8) // 其他 - 灰色
        }
    }

    /// 根据代理人类型获取颜色
    private func getAgentTypeColor(_ agentType: Int) -> Color {
        switch agentType {
        case 1: return Color.gray.opacity(0.8)
        case 2: return Color.green.opacity(0.8)
        case 3: return Color.blue.opacity(0.8)
        case 4: return Color.blue.opacity(0.8)
        case 5: return Color.brown.opacity(0.8)
        case 6: return Color.green.opacity(0.8)
        case 7: return Color.green.opacity(0.8)
        case 8: return Color.yellow.opacity(0.8)
        case 9: return Color.cyan.opacity(0.8)
        case 10: return Color.mint.opacity(0.8)
        case 11: return Color.indigo.opacity(0.8)
        case 12: return Color.teal.opacity(0.8)
        case 13: return Color.brown.opacity(0.8)
        default: return Color.gray.opacity(0.8)
        }
    }
}
