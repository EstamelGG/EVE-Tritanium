import SwiftUI

struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @ObservedObject private var skillsManager = SharedSkillsManager.shared

    private let currentCharacterId: Int = UserDefaults.standard.object(forKey: "currentCharacterId") as? Int ?? 0

    var itemID: Int
    var modifiedAttributes: [Int: Double]?

    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []

    /// 异步加载顺序：每加载完一个 Section 就以动画淡入显示
    private enum SectionKey: Int, CaseIterable {
        case variations, attributes, skill, industry
        case mutationSource, mutationResults, requiredMutaplasmids
    }

    @State private var visibleSections: Set<SectionKey> = []

    private func buildTraitsText(
        roleBonuses: [Trait],
        typeBonuses: [Trait],
        miscBonuses: [Trait] = [],
        databaseManager: DatabaseManager
    ) -> String {
        var text = ""

        if !roleBonuses.isEmpty {
            text += "- <b>\(NSLocalizedString("Main_Database_Role_Bonuses", comment: ""))</b>\n"
            text += roleBonuses.map { " • \($0.content)" }.joined(separator: "\n")
        }

        if !roleBonuses.isEmpty && (!typeBonuses.isEmpty || !miscBonuses.isEmpty) {
            text += "\n\n"
        }

        if !typeBonuses.isEmpty {
            let groupedBonuses = Dictionary(grouping: typeBonuses, by: \.skill)
            let sortedSkills = groupedBonuses.keys.compactMap { $0 }.sorted()

            for skill in sortedSkills {
                guard let skillName = databaseManager.getTypeName(for: skill) else { continue }

                text +=
                    "- <a href=showinfo:\(skill)>\(skillName)</a> \(NSLocalizedString("Main_Database_Bonuses_Per_Level", comment: ""))\n"

                let bonuses = groupedBonuses[skill]?.sorted { $0.importance < $1.importance } ?? []
                text += bonuses.map { " • \($0.content)" }.joined(separator: "\n")

                if skill != sortedSkills.last {
                    text += "\n\n"
                }
            }
        }

        if !typeBonuses.isEmpty && !miscBonuses.isEmpty {
            text += "\n\n"
        }

        if !miscBonuses.isEmpty {
            text += "- <b>\(NSLocalizedString("Main_Database_Misc_Bonuses", comment: ""))</b>\n"
            text += miscBonuses
                .map { $0.content.hasPrefix("<b><u>") ? "-- \($0.content)" : " • \($0.content)" }
                .joined(separator: "\n")
        }

        return text
    }

    var body: some View {
        List {
            if let itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails,
                    databaseManager: databaseManager,
                    modifiedAttributes: modifiedAttributes
                )

                if visibleSections.contains(.variations) {
                    VariationsSection(typeID: itemID, databaseManager: databaseManager)
                        .transition(.opacity)
                }

                if visibleSections.contains(.attributes) {
                    AttributesView(
                        attributeGroups: attributeGroups,
                        typeID: itemID,
                        databaseManager: databaseManager
                    )
                    .transition(.opacity)
                }

                if itemDetails.categoryID == 16 && visibleSections.contains(.skill) {
                    SkillSection(
                        skillID: itemID,
                        currentCharacterId: currentCharacterId,
                        databaseManager: databaseManager
                    )
                    .transition(.opacity)
                }

                if visibleSections.contains(.industry) {
                    IndustrySection(
                        itemID: itemID,
                        databaseManager: databaseManager,
                        itemDetails: itemDetails
                    )
                    .transition(.opacity)
                }

                if visibleSections.contains(.mutationSource) {
                    MutationSourceSection(itemID: itemID, databaseManager: databaseManager)
                        .transition(.opacity)
                }
                if visibleSections.contains(.mutationResults) {
                    MutationResultsSection(itemID: itemID, databaseManager: databaseManager)
                        .transition(.opacity)
                }
                if visibleSections.contains(.requiredMutaplasmids) {
                    RequiredMutaplasmidsSection(itemID: itemID, databaseManager: databaseManager)
                        .transition(.opacity)
                }
            } else {
                Text(NSLocalizedString("Item_details_notfound", comment: ""))
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let details = itemDetails, SDEMemoryStore.isSimulatableShip(itemID) {
                    NavigationLink {
                        ShipFittingView(
                            shipTypeId: itemID,
                            shipInfo: (name: details.name, iconFileName: details.iconFileName),
                            databaseManager: databaseManager
                        )
                    } label: {
                        Text(NSLocalizedString("Main_Fitting", comment: ""))
                    }
                }
            }
        }
        .onAppear {
            getItemDetails(for: itemID)
            loadAttributes(for: itemID)
        }
        .task {
            // 串行加载各 Section：每加载完一项就以动画淡入显示下一项
            // 先等基础信息 onAppear 同步加载完成
            try? await Task.sleep(nanoseconds: 50_000_000)
            for key in SectionKey.allCases {
                // 让出主线程，让上一个 Section 渲染（包括其数据加载）
                await Task.yield()
                try? await Task.sleep(nanoseconds: 30_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    _ = visibleSections.insert(key)
                }
            }
        }
        .onChange(of: skillsManager.isLoading) { _, isLoading in
            if !isLoading {
                loadAttributes(for: itemID)
            }
        }
    }

    private func getItemDetails(for itemID: Int) {
        guard let itemDetail = databaseManager.getItemDetails(for: itemID) else { return }

        if let traitGroup = databaseManager.getTraits(for: itemID) {
            let traitText = buildTraitsText(
                roleBonuses: traitGroup.roleBonuses,
                typeBonuses: traitGroup.typeBonuses,
                miscBonuses: traitGroup.miscBonuses,
                databaseManager: databaseManager
            )
            let fullDescription =
                itemDetail.description + (traitText.isEmpty ? "" : "\n\n" + traitText)

            itemDetails = ItemDetails(
                name: itemDetail.name,
                en_name: itemDetail.en_name ?? "",
                description: fullDescription,
                iconFileName: itemDetail.iconFileName,
                groupName: itemDetail.groupName,
                categoryID: itemDetail.categoryID,
                categoryName: itemDetail.categoryName,
                typeId: itemDetail.typeId,
                groupID: itemDetail.groupID,
                volume: itemDetail.volume,
                repackagedVolume: itemDetail.repackagedVolume,
                capacity: itemDetail.capacity,
                mass: itemDetail.mass,
                marketGroupID: itemDetail.marketGroupID
            )
        } else {
            itemDetails = itemDetail
        }
    }

    private func loadAttributes(for itemID: Int) {
        attributeGroups = databaseManager.loadAttributeGroups(
            for: itemID,
            modifiedAttributes: modifiedAttributes
        )

        if itemDetails?.categoryID == 16,
           currentCharacterId != 0,
           let level = skillsManager.getSkillLevel(for: itemID),
           level >= 0
        {
            addOrUpdateSkillLevelAttribute(level: level)
        }

        AttributeDisplayConfig.initializeUnits(with: databaseManager.loadAttributeUnits())
    }

    /// 添加或更新技能等级属性（属性 ID 280）
    private func addOrUpdateSkillLevelAttribute(level: Int) {
        let skillLevelAttributeID = 280

        for (index, group) in attributeGroups.enumerated() {
            guard let attrIndex = group.attributes.firstIndex(where: { $0.id == skillLevelAttributeID })
            else { continue }

            var updatedAttributes = group.attributes
            let updatedAttribute = updatedAttributes[attrIndex]
            updatedAttributes[attrIndex] = DogmaAttribute(
                id: updatedAttribute.id,
                categoryID: updatedAttribute.categoryID,
                name: updatedAttribute.name,
                displayName: updatedAttribute.displayName,
                iconID: updatedAttribute.iconID,
                iconFileName: updatedAttribute.iconFileName,
                value: updatedAttribute.value,
                unitID: updatedAttribute.unitID,
                highIsGood: updatedAttribute.highIsGood,
                modifiedValue: Double(level)
            )
            attributeGroups[index] = AttributeGroup(
                id: group.id,
                name: group.name,
                attributes: updatedAttributes
            )
            return
        }

        guard let attributeInfo = databaseManager.getAttributeInfo(for: skillLevelAttributeID) else {
            return
        }

        let newAttribute = DogmaAttribute(
            id: skillLevelAttributeID,
            categoryID: attributeInfo.categoryID,
            name: attributeInfo.name,
            displayName: attributeInfo.displayName,
            iconID: attributeInfo.iconID,
            iconFileName: attributeInfo.iconFileName,
            value: 0,
            unitID: attributeInfo.unitID,
            highIsGood: attributeInfo.highIsGood,
            modifiedValue: Double(level)
        )

        if let groupIndex = attributeGroups.firstIndex(where: { $0.id == attributeInfo.categoryID }) {
            var updatedAttributes = attributeGroups[groupIndex].attributes
            updatedAttributes.append(newAttribute)
            updatedAttributes.sort { $0.id < $1.id }
            attributeGroups[groupIndex] = AttributeGroup(
                id: attributeGroups[groupIndex].id,
                name: attributeGroups[groupIndex].name,
                attributes: updatedAttributes
            )
        } else {
            let categoryName =
                databaseManager.getAttributeCategoryName(for: attributeInfo.categoryID) ?? "Skills"
            attributeGroups.append(
                AttributeGroup(
                    id: attributeInfo.categoryID,
                    name: categoryName,
                    attributes: [newAttribute]
                )
            )
            attributeGroups.sort { $0.id < $1.id }
        }
    }
}
