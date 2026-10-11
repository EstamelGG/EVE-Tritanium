import SwiftUI

struct IndustryFilterSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 获取活动类型的本地化名称
    private func getActivityTypeName(_ activityId: Int) -> String {
        switch activityId {
        case 1:
            return NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "制造")
        case 3:
            return NSLocalizedString("Industry_Type_Research_Time_Short", comment: "时间效率研究")
        case 4:
            return NSLocalizedString("Industry_Type_Research_Material_Short", comment: "材料效率研究")
        case 5:
            return NSLocalizedString("Industry_Type_Copying", comment: "复制")
        case 8:
            return NSLocalizedString("Industry_Type_Invention", comment: "发明")
        case 9:
            return NSLocalizedString("Industry_Type_Reaction", comment: "反应")
        default:
            return "Unknown Activity \(activityId)"
        }
    }

    /// 获取活动类型对应的颜色
    private func getActivityTypeColor(_ activityId: Int) -> Color {
        switch activityId {
        case 1: // 制造
            return Color(red: 0.9, green: 0.7, blue: 0.3) // 土黄色
        case 3, 4, 5, 8: // 时间效率研究、材料效率研究、复制、发明
            return Color.blue // 蓝色
        case 9: // 反应
            return Color.cyan // 青蓝色
        default:
            return Color.gray
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // 按项目类型过滤
                Section {
                    ForEach(viewModel.availableActivityTypes, id: \.self) { activityId in
                        Button(action: {
                            if viewModel.selectedActivityTypes.contains(activityId) {
                                viewModel.selectedActivityTypes.remove(activityId)
                            } else {
                                viewModel.selectedActivityTypes.insert(activityId)
                            }
                        }) {
                            HStack {
                                // 添加彩色圆点
                                Circle()
                                    .fill(getActivityTypeColor(activityId))
                                    .frame(width: 8, height: 8)

                                // 添加工业类型图标
                                if colorScheme == .light {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(for: activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                    .colorInvert()
                                } else {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(for: activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                }
                                Text(getActivityTypeName(activityId))
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedActivityTypes.contains(activityId) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Industry_Filter_Activity_Types", comment: "项目类型"))
                        Spacer()
                        Button(action: {
                            if viewModel.selectedActivityTypes.count
                                == viewModel.availableActivityTypes.count
                            {
                                viewModel.selectedActivityTypes = []
                            } else {
                                viewModel.selectedActivityTypes = Set(
                                    viewModel.availableActivityTypes
                                )
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                    .font(.caption)
                                if viewModel.selectedActivityTypes.count
                                    == viewModel.availableActivityTypes.count
                                {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // 第三个section：按发起人过滤（仅在聚合模式下且选择了多个人物时显示）
                if viewModel.multiCharacterMode && viewModel.selectedCharacterIds.count > 1
                    && !viewModel.availableInstallers.isEmpty
                {
                    Section {
                        ForEach(viewModel.availableInstallers, id: \.self) { installerId in
                            Button(action: {
                                if viewModel.selectedInstallers.contains(installerId) {
                                    viewModel.selectedInstallers.remove(installerId)
                                } else {
                                    viewModel.selectedInstallers.insert(installerId)
                                }
                            }) {
                                HStack {
                                    // 显示发起人头像和名称
                                    if let installerImage = viewModel.installerImages[installerId] {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 32, height: 32)
                                    }

                                    Text(viewModel.installerNames[installerId] ?? "Unknown")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if viewModel.selectedInstallers.contains(installerId) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Installers", comment: "发起人"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedInstallers.count
                                    == viewModel.availableInstallers.count
                                {
                                    viewModel.selectedInstallers = []
                                } else {
                                    viewModel.selectedInstallers = Set(
                                        viewModel.availableInstallers
                                    )
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedInstallers.count
                                        == viewModel.availableInstallers.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // 第四个section：按星系过滤
                if !viewModel.availableSolarSystems.isEmpty {
                    Section {
                        ForEach(viewModel.availableSolarSystems, id: \.self) { solarSystem in
                            Button(action: {
                                if viewModel.selectedSolarSystems.contains(solarSystem) {
                                    viewModel.selectedSolarSystems.remove(solarSystem)
                                } else {
                                    viewModel.selectedSolarSystems.insert(solarSystem)
                                }
                            }) {
                                HStack {
                                    // 安全等级和星系名称
                                    if let security = viewModel.getSolarSystemSecurity(solarSystem) {
                                        Text(formatSystemSecurity(security))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(getSecurityColor(security))
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    }

                                    Spacer()
                                    if viewModel.selectedSolarSystems.contains(solarSystem) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Solar_Systems", comment: "星系"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedSolarSystems.count
                                    == viewModel.availableSolarSystems.count
                                {
                                    viewModel.selectedSolarSystems = []
                                } else {
                                    viewModel.selectedSolarSystems = Set(
                                        viewModel.availableSolarSystems
                                    )
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedSolarSystems.count
                                        == viewModel.availableSolarSystems.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Industry_Filter_Title", comment: "过滤设置"))
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
