import SwiftUI

struct CharacterMailView: View {
    let characterId: Int
    @State private var showingComposeView = false

    var body: some View {
        List {
            // 全部邮件部分
            Section {
                NavigationLink {
                    CharacterMailListView(characterId: characterId)
                } label: {
                    mailboxRow(
                        icon: AnyView(
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.gray)
                                .frame(width: 24, height: 24)
                        ),
                        title: NSLocalizedString("Main_EVE_Mail_All", comment: "")
                    )
                }
            }

            // 邮箱列表部分
            Section {
                ForEach(MailboxType.allCases, id: \.self) { mailbox in
                    NavigationLink {
                        CharacterMailListView(
                            characterId: characterId,
                            labelId: mailbox.labelId,
                            title: mailbox.title
                        )
                    } label: {
                        mailboxRow(icon: mailbox.iconView, title: mailbox.title)
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Mailboxes", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_EVE_Mail_Title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingComposeView = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingComposeView) {
            NavigationStack {
                CharacterComposeMailView(characterId: characterId)
            }
        }
    }

    /// 邮箱行视图（图标 + 标题）
    private func mailboxRow(icon: AnyView, title: String) -> some View {
        HStack {
            icon
            Text(title)
            Spacer()
        }
    }
}

/// 邮箱类型枚举
enum MailboxType: CaseIterable {
    case inbox
    case sent
    case corporation
    case alliance

    var title: String {
        switch self {
        case .inbox: return NSLocalizedString("Main_EVE_Mail_Inbox", comment: "")
        case .sent: return NSLocalizedString("Main_EVE_Mail_Sent", comment: "")
        case .corporation: return NSLocalizedString("Main_EVE_Mail_Corporation", comment: "")
        case .alliance: return NSLocalizedString("Main_EVE_Mail_Alliance", comment: "")
        }
    }

    var labelId: Int {
        switch self {
        case .inbox: return 1
        case .sent: return 2
        case .corporation: return 4
        case .alliance: return 8
        }
    }

    /// 邮箱图标视图
    var iconView: AnyView {
        switch self {
        case .inbox:
            return AnyView(
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundColor(.gray)
                    .frame(width: 24, height: 24)
            )
        case .sent:
            return AnyView(
                Image(systemName: "tray.and.arrow.up.fill")
                    .foregroundColor(.gray)
                    .frame(width: 24, height: 24)
            )
        case .corporation:
            return AnyView(
                Image("corporation")
                    .resizable()
                    .frame(width: 24, height: 24)
            )
        case .alliance:
            return AnyView(
                Image("alliances")
                    .resizable()
                    .frame(width: 24, height: 24)
            )
        }
    }
}
