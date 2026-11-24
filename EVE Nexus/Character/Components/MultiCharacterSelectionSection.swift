import SwiftUI

/// 角色名称文本：扫描 refreshTokenExpired 标签，过期则追加本地化的"（已过期）"后缀并显示为红色
struct CharacterNameText: View {
    let characterId: Int
    let name: String

    private var isExpired: Bool {
        EVELogin.shared.getCharacterByID(characterId)?.character.refreshTokenExpired ?? false
    }

    private var displayText: String {
        guard isExpired else { return name }
        return String(
            format: NSLocalizedString("Character_Name_Expired_Format", comment: "角色名（已过期）格式，%@ 为角色名"),
            name
        )
    }

    var body: some View {
        Text(displayText)
            .foregroundColor(isExpired ? .red : .primary)
    }
}

/// 多人物聚合功能中通用的角色选择列表 Section。
///
/// 包含：角色列表（头像 + 名称 + 选中勾号）+ 全选/全不选按钮。
struct MultiCharacterSelectionSection<Row: View>: View {
    let availableCharacters: [(id: Int, name: String)]
    @Binding var selectedCharacterIds: Set<Int>
    let showsSelectAllFirst: Bool
    private let row: ((Int, String) -> Row)?

    init(
        availableCharacters: [(id: Int, name: String)], selectedCharacterIds: Binding<Set<Int>>,
        showsSelectAllFirst: Bool = false, @ViewBuilder row: @escaping (Int, String) -> Row
    ) {
        self.availableCharacters = availableCharacters
        _selectedCharacterIds = selectedCharacterIds
        self.showsSelectAllFirst = showsSelectAllFirst
        self.row = row
    }

    init(
        availableCharacters: [(id: Int, name: String)], selectedCharacterIds: Binding<Set<Int>>,
        showsSelectAllFirst: Bool = false
    ) where Row == EmptyView {
        self.availableCharacters = availableCharacters
        _selectedCharacterIds = selectedCharacterIds
        self.showsSelectAllFirst = showsSelectAllFirst
        row = nil
    }

    private var availableIDs: Set<Int> {
        Set(availableCharacters.map(\.id))
    }

    private var allSelected: Bool {
        !availableIDs.isEmpty && availableIDs.isSubset(of: selectedCharacterIds)
    }

    var body: some View {
        Section(
            header: Text(
                NSLocalizedString("MultiCharacter_Select_Characters", comment: "选择角色")
            )
        ) {
            if showsSelectAllFirst {
                selectAllButton
            }

            ForEach(availableCharacters, id: \.id) { character in
                let selected = selectedCharacterIds.contains(character.id)
                Button {
                    if selected {
                        selectedCharacterIds.remove(character.id)
                    } else {
                        selectedCharacterIds.insert(character.id)
                    }
                } label: {
                    HStack {
                        if let row {
                            row(character.id, character.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            CharacterPortraitView(characterId: character.id)
                                .padding(.trailing, 8)
                            CharacterNameText(characterId: character.id, name: character.name)
                            Spacer()
                        }
                        if selected || row != nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .opacity(selected ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            if !showsSelectAllFirst {
                selectAllButton
            }
        }
    }

    private var selectAllButton: some View {
        Button {
            selectedCharacterIds = allSelected ? [] : availableIDs
        } label: {
            HStack {
                Text(NSLocalizedString("MultiCharacter_Select_All", comment: "全选"))
                Spacer()
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(allSelected ? Color.blue : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(availableIDs.isEmpty)
        .accessibilityAddTraits(allSelected ? .isSelected : [])
    }
}
