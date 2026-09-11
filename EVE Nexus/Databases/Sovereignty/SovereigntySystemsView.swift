import SwiftUI

/// 主权势力星系详情视图（第三级：展示某星域内属于该主权的星系，按星座分 section）
/// 数据由第二级 SovereigntyRegionsView 加载后传入，本视图无网络请求
struct SovereigntySystemsView: View {
    let regionName: String
    let systems: [SolarSystemInfo]

    /// 按星座分组（星座按名称字母序，组内星系按名称字母序）
    private var constellationGroups: [(name: String, systems: [SolarSystemInfo])] {
        Dictionary(grouping: systems) { $0.constellationName }
            .map { (name: $0.key, systems: $0.value.sorted { $0.systemName < $1.systemName }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        SovereigntySearchScope {
            List {
                ForEach(constellationGroups, id: \.name) { group in
                    Section(
                        header: Text(group.name)
                    ) {
                        ForEach(group.systems, id: \.systemId) { system in
                            systemRow(system)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(regionName)
        .navigationBarTitleDisplayMode(.large)
    }

    /// 星系行：安全等级 + 星系名（星座已在 section 头）
    private func systemRow(_ system: SolarSystemInfo) -> some View {
        SystemRowView(
            name: system.systemName,
            security: system.security
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = system.systemName
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_Location", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }
}
