import SwiftUI

struct IndustrySlotDetailSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // 只显示选中的人物信息
                ForEach(viewModel.characterSlotDetails, id: \.characterId) { detail in
                    Section(
                        header: HStack {
                            CharacterPortraitView(characterId: detail.characterId)
                                .padding(.trailing, 8)
                            Text(detail.characterName)
                        }
                    ) {
                        // 加工任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString(
                                        "Industry_Slots_Manufacturing", comment: "加工任务"
                                    )
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.manufacturingRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.manufacturingUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.manufacturingUsed >= detail.manufacturingSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.manufacturingSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                                    )
                            }
                        }
                        .padding(.vertical, 4)

                        // 研究任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Industry_Slots_Research", comment: "研究任务")
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.researchRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.researchUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.researchUsed >= detail.researchSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.researchSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.blue)
                            }
                        }
                        .padding(.vertical, 4)

                        // 反应任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Industry_Slots_Reaction", comment: "反应任务")
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.reactionRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.reactionUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.reactionUsed >= detail.reactionSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.reactionSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.cyan)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Industry_Slots_Detail_Title", comment: "槽位详情"))
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

struct IndustryProductionListSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if viewModel.productionList.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("Industry_Production_List_Empty", comment: "暂无生产项目"))
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                } else {
                    ForEach(viewModel.productionList, id: \.typeId) { item in
                        HStack(spacing: 12) {
                            // 产品图标
                            if !item.typeIcon.isEmpty {
                                IconManager.shared.loadImage(for: item.typeIcon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                            }

                            // 产品名称和数量
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.typeName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Industry_Production_Quantity", comment: "数量: %d"
                                        ),
                                        item.totalQuantity
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 数量（右侧显示）
                            Text("\(item.totalQuantity)")
                                .font(.body)
                                .fontDesign(.monospaced)
                                .foregroundColor(
                                    Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                                )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Industry_Production_List", comment: "生产清单"))
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
