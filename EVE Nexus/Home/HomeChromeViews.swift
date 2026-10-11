import Foundation
import SwiftUI

// MARK: - 自定义按钮样式

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 导航栏头像组件

struct NavigationBarAvatarView: View {
    let characterPortrait: UIImage?
    let isRefreshTokenExpired: Bool
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            if let portrait = characterPortrait {
                Image(uiImage: portrait)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                if isRefreshing {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 32, height: 32)

                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                } else if isRefreshTokenExpired {
                    // Token过期覆盖层（缩小版）
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 32, height: 32)

                        ZStack {
                            Image(systemName: "triangle")
                                .font(.system(size: 16))
                                .foregroundColor(.red)

                            Image(systemName: "exclamationmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }
        }
        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1.5))
        .background(Circle().fill(Color.primary.opacity(0.05)))
        .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

/// 修改LoginButtonView组件
struct LoginButtonView: View {
    let isLoggedIn: Bool
    let serverStatus: ServerStatus?
    let selectedCharacter: EVECharacterInfo?
    let characterPortrait: UIImage?
    let isRefreshing: Bool
    let isRefreshTokenExpired: Bool
    @ObservedObject var mainViewModel: MainViewModel

    var body: some View {
        HStack {
            if let portrait = characterPortrait {
                ZStack {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    if isRefreshing {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 64, height: 64)

                        ProgressView()
                            .scaleEffect(0.8)
                    } else if isRefreshTokenExpired {
                        // 使用TokenExpiredOverlay组件
                        TokenExpiredOverlay()
                    }
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3))
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            } else {
                ZStack {
                    Image("default_char")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3))
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let character = selectedCharacter {
                    Text(character.CharacterName)
                        .font(.headline)
                        .lineLimit(1)

                    // 显示军团信息
                    HStack(spacing: 4) {
                        if let corporation = mainViewModel.corporationInfo,
                           let logo = mainViewModel.corporationLogo
                        {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text("[\(corporation.ticker)] \(corporation.name)")
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                            Text("[-] \(NSLocalizedString("No Corporation", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }

                    // 显示联盟信息
                    HStack(spacing: 4) {
                        if let alliance = mainViewModel.allianceInfo,
                           let logo = mainViewModel.allianceLogo
                        {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text("[\(alliance.ticker)] \(alliance.name)")
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                            Text("[-] \(NSLocalizedString("No Alliance", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }

                    // 显示势力信息
                    if let faction = mainViewModel.factionInfo,
                       let logo = mainViewModel.factionLogo
                    {
                        HStack(spacing: 4) {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(faction.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                } else if isLoggedIn {
                    Text(NSLocalizedString("Account_Management", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(NSLocalizedString("Account_Add_Character", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            .frame(height: 72)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .task {
            // 检查认证信息是否存在（token 过期状态由 ContentView 统一管理并通过参数传入）
            if let character = selectedCharacter {
                if EVELogin.shared.getCharacterByID(character.CharacterID) == nil {
                    Logger.error(
                        "找不到角色 \(character.CharacterName) (\(character.CharacterID)) 的认证信息"
                    )
                    // 如果找不到认证信息，通知 ContentView 执行登出操作
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CharacterLoggedOut"), object: nil
                    )
                }
            }
        }
    }
}

// MARK: - 克隆倒计时组件

struct CloneCountdownView: View {
    @Environment(\.locale) private var displayLocale
    let targetDate: Date?

    var body: some View {
        if let date = targetDate {
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                let now = timeline.date
                let remainingTime = date.timeIntervalSince(now)

                if remainingTime <= 0 {
                    Text("Main_Jump_Clones_Ready")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                } else {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Jump_Clones_Cooldown_Compact", comment: "Countdown with compact duration"),
                            FormatUtil.formatCompactDuration(remainingTime, rounding: .ceil)
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                }
            }
        } else {
            Text("Main_Jump_Clones_Ready")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(1)
        }
    }
}

// MARK: - 技能队列倒计时组件

struct SkillQueueCountdownView: View {
    let queueEndDate: Date?
    let skillCount: Int

    var body: some View {
        if let endDate = queueEndDate, skillCount > 0 {
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                let now = timeline.date
                let remainingTime = endDate.timeIntervalSince(now)

                if remainingTime <= 0 {
                    // 队列已完成
                    Text(NSLocalizedString("Main_Skills_Queue_Complete", comment: "完成"))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                } else {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Skills_Queue_Training_Compact", comment: "Countdown with compact duration"),
                            skillCount, FormatUtil.formatCompactDuration(remainingTime, rounding: .ceil)
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                }
            }
        } else if skillCount > 0 {
            // 有技能但暂停中
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Paused", comment: "暂停中 - %d个技能"),
                    skillCount
                )
            )
            .font(.system(size: 12))
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
        } else {
            // 空队列
            Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: "技能队列为空"))
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(1)
        }
    }
}
