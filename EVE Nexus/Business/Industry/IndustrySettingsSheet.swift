import SwiftUI

struct IndustrySettingsSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // 项目显示设置
                Section {
                    Toggle(isOn: $viewModel.hideCompletedAndCancelled) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed", comment: "隐藏已交付和已取消的项目"
                                )
                            )
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed_Description",
                                    comment: "隐藏已完成、已取消、已撤销等状态的项目"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Settings_Multi_Character", comment: "多人物聚合"
                                )
                            )
                            Text(
                                NSLocalizedString(
                                    "Settings_Multi_Character_Description",
                                    comment: "聚合显示多个角色的工业项目数据"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // 只有在多人物模式开启时才显示角色选择
                if viewModel.multiCharacterMode {
                    MultiCharacterSelectionSection(
                        availableCharacters: viewModel.availableCharacters,
                        selectedCharacterIds: $viewModel.selectedCharacterIds
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Industry_Settings_Title", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
