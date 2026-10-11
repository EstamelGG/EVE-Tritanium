import SwiftUI

/// 人物表单子页面：奖章（懒加载；空数据显示占位）
struct CharacterMedalsPage: View {
    @Environment(\.timeZone) private var displayTimeZone
    let character: EVECharacterInfo

    @State private var medals: [CharacterMedal]?
    @State private var isLoading = true

    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var body: some View {
        List {
            Section {
                if let medals, !medals.isEmpty {
                    // 同一奖章可被多次授予（title 重复），用索引作唯一 ID
                    ForEach(Array(medals.enumerated()), id: \.offset) { _, medal in
                        medalRow(medal)
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                } else {
                    Text(NSLocalizedString("Character_No_Medals", comment: "无奖章占位"))
                        .foregroundColor(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Character_Medals", comment: ""))
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func medalRow(_ medal: CharacterMedal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image("achievements")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    if let date = isoDateFormatter.date(from: medal.date) {
                        Text(FormatUtil.formatDateToLocalDate(date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(medal.title)
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(medal.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let reason = medal.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        let fetched = try? await CharacterMedalsAPI.shared.fetchCharacterMedals(
            characterId: character.CharacterID
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            medals = fetched
            isLoading = false
        }
    }
}
