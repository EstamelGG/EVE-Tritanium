import SwiftUI

// MARK: - 搜索列表（主界面嵌入）

struct AssetSearchResultsList: View {
    let groups: [AssetSearchItemGroup]
    let isSearching: Bool
    let context: AssetSearchNavigationContext

    var body: some View {
        if isSearching {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }

        if !groups.isEmpty {
            Section {
                ForEach(groups) { group in
                    NavigationLink {
                        AssetSearchItemLocationsView(group: group, context: context)
                    } label: {
                        AssetSearchItemGroupRow(group: group)
                    }
                }
            } header: {
                Text(
                    String(
                        format: NSLocalizedString("Assets_Search_Item_Types_Format", comment: ""),
                        groups.count
                    )
                )
            }
        }
    }
}

// MARK: - 聚合行：物品 + 总量 + 处数

private struct AssetSearchItemGroupRow: View {
    let group: AssetSearchItemGroup

    var body: some View {
        HStack(spacing: 12) {
            AssetIconView(iconName: group.itemInfo.iconFileName)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.itemInfo.name)
                    .lineLimit(2)

                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var summaryText: String {
        let total = String(
            format: NSLocalizedString("Assets_Search_Total_Quantity_Format", comment: ""),
            group.totalQuantity
        )
        let stacks = String(
            format: NSLocalizedString("Assets_Search_Occurrences_Format", comment: ""),
            group.occurrences.count
        )
        return "\(total) · \(stacks)"
    }
}

// MARK: - 物品存放位置详情

struct AssetSearchItemLocationsView: View {
    let group: AssetSearchItemGroup
    let context: AssetSearchNavigationContext

    var body: some View {
        List {
            Section {
                itemHeaderLink
            }

            Section {
                ForEach(group.occurrences) { occurrence in
                    NavigationLink {
                        occurrenceDestination(occurrence)
                    } label: {
                        AssetSearchOccurrenceRow(
                            occurrence: occurrence,
                            itemInfo: group.itemInfo,
                            stationNameCache: context.stationNameCache,
                            solarSystemNameCache: context.solarSystemNameCache,
                            showOwner: context.multiCharacterMode,
                            ownerName: context.ownerName(occurrence.ownerId),
                            ownerPortrait: context.ownerPortrait(occurrence.ownerId)
                        )
                    }
                }
            } header: {
                Text(NSLocalizedString("Assets_Search_Locations_Title", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.itemInfo.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var itemHeaderLink: some View {
        if context.dynamicResultingTypeIds.contains(group.typeId) {
            itemHeaderContent
        } else {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: context.databaseManager,
                    itemID: group.typeId
                )
            } label: {
                itemHeaderContent
            }
        }
    }

    private var itemHeaderContent: some View {
        HStack(spacing: 12) {
            AssetIconView(iconName: group.itemInfo.iconFileName, size: CharacterAssetsIconSize.location)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.itemInfo.name)
                Text(
                    String(
                        format: NSLocalizedString("Assets_Search_Total_Quantity_Format", comment: ""),
                        group.totalQuantity
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func occurrenceDestination(_ occurrence: AssetSearchOccurrence) -> some View {
        if occurrence.containerNode.item_id == occurrence.rootLocation.item_id {
            LocationAssetsView(
                location: occurrence.rootLocation,
                preloadedItemInfo: context.itemInfoCache,
                stationNameCache: context.stationNameCache,
                solarSystemNameCache: context.solarSystemNameCache,
                dynamicResultingTypeIds: context.dynamicResultingTypeIds,
                showOwner: context.multiCharacterMode,
                ownerId: occurrence.ownerId,
                ownerName: context.ownerName(occurrence.ownerId),
                ownerPortrait: context.ownerPortrait(occurrence.ownerId),
                typeFilterContext: context.typeFilterContext
            )
        } else {
            SubLocationAssetsView(
                parentNode: occurrence.containerNode,
                preloadedItemInfo: context.itemInfoCache,
                stationNameCache: context.stationNameCache,
                solarSystemNameCache: context.solarSystemNameCache,
                dynamicResultingTypeIds: context.dynamicResultingTypeIds,
                typeFilterContext: context.typeFilterContext.containerContext(
                    for: occurrence.containerNode
                )
            )
        }
    }
}

// MARK: - 站内容器路径行

private struct AssetSearchInnerPathRow: View {
    let segments: [AssetSearchPathSegment]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    Text("›")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    AssetIconView(
                        iconName: segment.iconName, size: CharacterAssetsIconSize.pathSegment
                    )
                    Text(segment.typeName)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let customName = segment.customName {
                        Text(customName)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .font(.caption)
        .lineLimit(2)
    }
}

// MARK: - 单处堆叠行

private struct AssetSearchOccurrenceRow: View {
    let occurrence: AssetSearchOccurrence
    let itemInfo: ItemInfo
    let stationNameCache: [Int64: String]
    let solarSystemNameCache: [Int: String]
    var showOwner: Bool = false
    var ownerName: String?
    var ownerPortrait: UIImage?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            locationIcon(for: occurrence.rootLocation)
                .frame(width: CharacterAssetsIconSize.location, height: CharacterAssetsIconSize.location)

            VStack(alignment: .leading, spacing: 4) {
                LocationInfoView(
                    stationName: location.getLocationName(stationNameCache: stationNameCache),
                    solarSystemName: solarSystemName(for: location),
                    security: location.security_status,
                    locationId: location.location_id,
                    font: .subheadline,
                    textColor: .primary,
                    inSpaceNote: location.location_type == "solar_system"
                        ? NSLocalizedString("Character_in_space", comment: "") : nil
                )

                if showOwner {
                    AssetOwnerRowLabel(
                        ownerId: occurrence.ownerId,
                        ownerName: ownerName,
                        ownerPortrait: ownerPortrait
                    )
                }

                if !occurrence.innerPath.isEmpty {
                    AssetSearchInnerPathRow(segments: occurrence.innerPath)
                }

                HStack(spacing: 4) {
                    AssetIconView(
                        iconName: itemInfo.iconFileName, size: CharacterAssetsIconSize.pathSegment
                    )
                    Text(itemInfo.name)
                        .lineLimit(1)
                    Text("×\(occurrence.quantity)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private var location: AssetTreeNode {
        occurrence.rootLocation
    }

    private func solarSystemName(for location: AssetTreeNode) -> String? {
        guard let systemId = location.system_id else { return nil }
        return solarSystemNameCache[systemId]
    }

    @ViewBuilder
    private func locationIcon(for location: AssetTreeNode) -> some View {
        if location.type_id > 0 {
            AssetIconView(
                iconName: location.resolvedIconName(itemInfo: nil),
                size: CharacterAssetsIconSize.location
            )
        } else if location.name == nil {
            Image("not_found")
                .resizable()
                .frame(width: CharacterAssetsIconSize.location, height: CharacterAssetsIconSize.location)
                .cornerRadius(6)
        }
    }
}
