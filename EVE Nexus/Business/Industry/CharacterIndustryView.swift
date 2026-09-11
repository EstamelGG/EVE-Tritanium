import SwiftUI

struct CharacterIndustryView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterIndustryViewModel
    @State private var showFilterSheet = false
    @State private var showSettingsSheet = false
    @State private var showSlotDetailSheet = false
    @State private var showProductionListSheet = false

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        // 构造表达式必须内联在 autoclosure 中：StateObject 只在视图身份首次建立时求值一次，
        _viewModel = StateObject(wrappedValue: CharacterIndustryViewModel(
            characterId: characterId, databaseManager: databaseManager
        ))
    }

    /// 格式化状态组标题
    private func formatStatusGroupHeader(_ statusKey: String) -> String {
        switch statusKey {
        case "ready":
            return NSLocalizedString("Industry_Ready_For_Delivery", comment: "准备交付")
        case "soon":
            return NSLocalizedString("Industry_Soon_Complete", comment: "即将完成")
        case "active":
            return NSLocalizedString("Industry_In_Progress", comment: "进行中")
        case "completed":
            return NSLocalizedString("Industry_Completed_Cancelled", comment: "已交付/已取消")
        default:
            return statusKey
        }
    }

    /// 获取工业项目的发起人名称
    private func getInstallerName(for job: IndustryJob) -> String? {
        // 从jobsWithOwner中找到该项目的所有者
        if let jobWithOwner = viewModel.jobsWithOwner.first(where: { $0.job.job_id == job.job_id }) {
            return viewModel.installerNames[jobWithOwner.ownerId]
        }
        return nil
    }

    /// 获取工业项目的发起人头像
    private func getInstallerImage(for job: IndustryJob) -> UIImage? {
        // 从jobsWithOwner中找到该项目的所有者
        if let jobWithOwner = viewModel.jobsWithOwner.first(where: { $0.job.job_id == job.job_id }) {
            return viewModel.installerImages[jobWithOwner.ownerId]
        }
        return nil
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)

                    // 显示工业项目加载进度（如果有多人物模式且正在加载）
                    if let progress = viewModel.loadingProgress, progress.total > 1 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Industry_Loading_Progress", comment: "已加载人物 %d/%d"), progress.current, progress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 显示技能加载进度
                    if let skillProgress = viewModel.skillLoadingProgress, skillProgress.total > 0 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Industry_Loading_Skills_Progress", comment: "正在加载技能数据 %d/%d"), skillProgress.current, skillProgress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                // 工业槽位统计 Section - 始终显示
                Section(
                    header: HStack {
                        Text(NSLocalizedString("Industry_Slots_Header", comment: "工业槽位"))
                        Spacer()
                        Button(action: {
                            showSlotDetailSheet = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                    }
                ) {
                    // 加工任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString(
                                        "Industry_Slots_Manufacturing", comment: "加工任务"
                                    )
                                )
                                .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.manufacturingRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.manufacturingSlots.used)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.manufacturingSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                                    )
                            }
                        }
                    }

                    // 研究任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Industry_Slots_Research", comment: "研究任务"))
                                    .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.researchRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.researchSlots.used)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.researchSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.blue) // 蓝色
                            }
                        }
                    }

                    // 反应任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Industry_Slots_Reaction", comment: "反应任务"))
                                    .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.reactionRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.reactionSlots.used)")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.reactionSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.cyan) // 青蓝色
                            }
                        }
                    }

                    // 生产清单
                    Button(action: {
                        showProductionListSheet = true
                    }) {
                        HStack {
                            Text(NSLocalizedString("Industry_Production_List", comment: "生产清单"))
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if !viewModel.productionList.isEmpty {
                                Text("\(viewModel.productionList.count)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .listSectionSpacing(.compact)

                // 过滤刷新指示器
                if viewModel.isFiltering {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(
                                    NSLocalizedString(
                                        "Industry_Filtering_Data", comment: "正在更新数据..."
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                }

                // 工业任务列表部分
                if viewModel.filteredGroupedJobs.isEmpty && !viewModel.isFiltering {
                    Section {
                        // 计算总项目数
                        let totalJobsCount = viewModel.groupedJobs.values.reduce(0) {
                            $0 + $1.count
                        }

                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                                    .foregroundColor(.secondary)

                                // 如果有总项目但被过滤完了，显示过滤信息
                                if totalJobsCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Industry_Filtered_Count", comment: "已过滤 %d 个项目"
                                            ),
                                            totalJobsCount
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                }
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if !viewModel.isFiltering {
                    // 按优先级排序：ready -> soon -> active -> completed
                    ForEach(
                        ["ready", "soon", "active", "completed"].filter {
                            viewModel.filteredGroupedJobs.keys.contains($0)
                        },
                        id: \.self
                    ) { statusKey in
                        Section(
                            header: HStack {
                                Text(formatStatusGroupHeader(statusKey))

                                Spacer()

                                // 显示每个section的项目数量
                                let sectionCount =
                                    viewModel.filteredGroupedJobs[statusKey]?.count ?? 0
                                Text("(\(sectionCount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        ) {
                            ForEach(viewModel.filteredGroupedJobs[statusKey] ?? [], id: \.job_id) {
                                job in
                                IndustryJobRow(
                                    job: job,
                                    blueprintName: viewModel.itemNames[job.blueprint_type_id]
                                        ?? "Unknown BP",
                                    blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
                                    locationInfo: viewModel.locationInfoCache[job.station_id],
                                    currentTime: Date(), // 使用当前时间作为倒计时基准
                                    showInstaller: viewModel.multiCharacterMode,
                                    installerName: getInstallerName(for: job),
                                    installerImage: getInstallerImage(for: job),
                                    isFromCorporation: viewModel.isJobFromCorporation(job)
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refreshAllIndustryData()
        }
        .navigationTitle(NSLocalizedString("Main_Industry_Jobs", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        showSettingsSheet = true
                    }) {
                        Image(systemName: "gear")
                    }

                    Button(action: {
                        showFilterSheet = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            IndustryFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            IndustrySettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSlotDetailSheet) {
            IndustrySlotDetailSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showProductionListSheet) {
            IndustryProductionListSheet(viewModel: viewModel)
        }
    }
}
