import Foundation

/// Explicit literals let Xcode extract each translation, including labels selected by report fields.
func sdeText(_ field: String) -> String {
    switch field {
    case "Absent": return NSLocalizedString("SDE_Changes_Absent", comment: "SDE change report")
    case "Attributes": return NSLocalizedString("SDE_Changes_Attributes", comment: "SDE change report")
    case "Collapse": return NSLocalizedString("SDE_Changes_Collapse", comment: "SDE change report")
    case "DemoNotice": return NSLocalizedString("SDE_Changes_DemoNotice", comment: "SDE change report")
    case "DescriptionChanges": return NSLocalizedString("SDE_Changes_DescriptionChanges", comment: "SDE change report")
    case "Done": return NSLocalizedString("SDE_Changes_Done", comment: "SDE change report")
    case "Empty": return NSLocalizedString("SDE_Changes_Empty", comment: "SDE change report")
    case "EmptyString": return NSLocalizedString("SDE_Changes_EmptyString", comment: "SDE change report")
    case "Expand": return NSLocalizedString("SDE_Changes_Expand", comment: "SDE change report")
    case "General": return NSLocalizedString("SDE_Changes_General", comment: "SDE change report")
    case "NameChanges": return NSLocalizedString("SDE_Changes_NameChanges", comment: "SDE change report")
    case "New": return NSLocalizedString("SDE_Changes_New", comment: "SDE change report")
    case "NoResults": return NSLocalizedString("SDE_Changes_NoResults", comment: "SDE change report")
    case "Old": return NSLocalizedString("SDE_Changes_Old", comment: "SDE change report")
    case "ReadError": return NSLocalizedString("SDE_Changes_ReadError", comment: "SDE change report")
    case "Records": return NSLocalizedString("SDE_Changes_Records", comment: "SDE change report")
    case "Search": return NSLocalizedString("SDE_Changes_Search", comment: "SDE change report")
    case "Title": return NSLocalizedString("SDE_Changes_Title", comment: "SDE change report")
    case "Unavailable": return NSLocalizedString("SDE_Changes_Unavailable", comment: "SDE change report")
    case "Unknown": return NSLocalizedString("SDE_Changes_Unknown", comment: "SDE change report")
    case "ViewItem": return NSLocalizedString("SDE_Changes_ViewItem", comment: "SDE change report")
    case "activities": return NSLocalizedString("SDE_Changes_activities", comment: "SDE change report")
    case "added": return NSLocalizedString("SDE_Changes_added", comment: "SDE change report")
    case "changed": return NSLocalizedString("SDE_Changes_changed", comment: "SDE change report")
    case "copying": return NSLocalizedString("SDE_Changes_copying", comment: "SDE change report")
    case "description": return NSLocalizedString("SDE_Changes_description", comment: "SDE change report")
    case "invention": return NSLocalizedString("SDE_Changes_invention", comment: "SDE change report")
    case "level": return NSLocalizedString("SDE_Changes_level", comment: "SDE change report")
    case "manufacturing": return NSLocalizedString("SDE_Changes_manufacturing", comment: "SDE change report")
    case "materials": return NSLocalizedString("SDE_Changes_materials", comment: "SDE change report")
    case "maxProductionLimit": return NSLocalizedString("SDE_Changes_maxProductionLimit", comment: "SDE change report")
    case "probability": return NSLocalizedString("SDE_Changes_probability", comment: "SDE change report")
    case "products": return NSLocalizedString("SDE_Changes_products", comment: "SDE change report")
    case "quantity": return NSLocalizedString("SDE_Changes_quantity", comment: "SDE change report")
    case "reaction": return NSLocalizedString("SDE_Changes_reaction", comment: "SDE change report")
    case "removed": return NSLocalizedString("SDE_Changes_removed", comment: "SDE change report")
    case "research_material": return NSLocalizedString("SDE_Changes_research_material", comment: "SDE change report")
    case "research_time": return NSLocalizedString("SDE_Changes_research_time", comment: "SDE change report")
    case "skills": return NSLocalizedString("SDE_Changes_skills", comment: "SDE change report")
    case "time": return NSLocalizedString("SDE_Changes_time", comment: "SDE change report")
    default: return field // Preserve unknown report field names without inventing localization keys.
    }
}

struct SDEChangeRowData: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var typeID: Int? = nil
    var change: SDEValueChange? = nil
    var text: String? = nil
    var layout: Layout = .inline
    enum Layout { case inline, text, materialRecords }
}

struct SDEChangeSectionData: Identifiable {
    let id: String
    let title: String
    var icon: String? = nil
    var rows: [SDEChangeRowData]
}

struct SDEChangeNode: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var symbol = "folder"
    var icon: String? = nil
    var typeID: Int? = nil
    var status: String? = nil
    var children: [SDEChangeNode] = []
    var details: [SDEChangeSectionData] = []
    var count: Int? = nil
    var isCategory = false

    var isDetail: Bool {
        typeID != nil || !details.isEmpty
    }

    static func name(_ id: String, kind: String = "type") -> String {
        guard let number = Int(id) else { return sdeText("Unknown") }
        let name: String?
        switch kind {
        case "attribute":
            let attribute = SDEMemoryStore.dogmaAttribute(for: number)
            name = attribute?.displayName ?? attribute?.name
        case "group": name = SDEMemoryStore.group(for: number)?.name
        case "category": name = SDEMemoryStore.category(for: number)?.name
        default: name = ItemInfoMap.typeName(for: number)
        }
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "ID \(id)"
    }

    static func icon(_ id: String, kind: String = "type") -> String {
        guard let number = Int(id) else { return IconManager.defaultIcon }
        switch kind {
        case "attribute": return SDEMemoryStore.dogmaAttribute(for: number)?.iconFilename ?? IconManager.defaultIcon
        case "group": return SDEMemoryStore.group(for: number)?.iconFilename ?? IconManager.defaultIcon
        case "category": return SDEMemoryStore.category(for: number)?.iconFilename ?? IconManager.defaultIcon
        default: return ItemInfoMap.iconFilename(for: number)
        }
    }

    static func sorted(_ nodes: [Self]) -> [Self] {
        nodes.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private static func item(_ id: Int, report: SDEChangeReport) -> Self {
        let type = ItemInfoMap.typeInfo(for: id)
        let groupID = type?.groupID.map { String($0) }
        let categoryID = type.map { String($0.categoryID) }
        let path = [categoryID.map { name($0, kind: "category") }, groupID.map { name($0, kind: "group") }]
            .compactMap { $0 }.joined(separator: " / ")
        var node = Self(id: String(id), title: name(String(id)), subtitle: path.isEmpty ? "ID \(id)" : "\(path) · ID \(id)",
                        icon: icon(String(id)), typeID: id, status: report.newTypeIDs.contains(id) ? "added" : "changed")
        if let modification = report.modifications[id] {
            node.details += textSections(modification)
            if !modification.attributes.isEmpty {
                node.details.append(SDEChangeSectionData(id: "attributes", title: sdeText("Attributes"), rows:
                    modification.attributes.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { attribute in
                        SDEChangeRowData(id: attribute, title: name(attribute, kind: "attribute"),
                                         icon: icon(attribute, kind: "attribute"), change: modification.attributes[attribute])
                    }))
            }
            node.details += blueprintSections(modification.blueprint)
        }
        return node
    }

    /// One catalog for every affected type, including ships and blueprints.
    static func sections(for report: SDEChangeReport) -> [Self] {
        let categories = Dictionary(grouping: report.affectedTypeIDs) { id in
            ItemInfoMap.typeInfo(for: id).map { String($0.categoryID) } ?? "?"
        }
        return sorted(categories.map { category, ids in
            let groups = Dictionary(grouping: ids) { id in
                ItemInfoMap.typeInfo(for: id)?.groupID.map { String($0) } ?? "?"
            }
            return Self(id: category, title: name(category, kind: "category"), icon: icon(category, kind: "category"),
                        children: sorted(groups.map { group, ids in
                            Self(id: group, title: name(group, kind: "group"), icon: icon(group, kind: "group"),
                                 children: sorted(ids.map { item($0, report: report) }), count: ids.count)
                        }), count: ids.count, isCategory: true)
        })
    }

    private static func textSections(_ modification: SDEChangeReport.Modification) -> [SDEChangeSectionData] {
        [("NameChanges", modification.name), ("DescriptionChanges", modification.description)].compactMap { key, changes in
            guard !changes.isEmpty else { return nil }
            let preferred = SDELanguage.columnPrefix()
            let languages = changes.keys.sorted {
                if ($0 == preferred) != ($1 == preferred) {
                    return $0 == preferred
                }
                return $0 < $1
            }
            return SDEChangeSectionData(id: key, title: sdeText(key), rows: languages.map { language in
                SDEChangeRowData(id: language, title: language,
                                 change: changes[language]?.valueChange, layout: .text)
            })
        }
    }

    private static func blueprintSections(_ blueprint: [String: SDEChangeTree]) -> [SDEChangeSectionData] {
        let differences = SDEBlueprintDifference.flatten(blueprint)
        let grouped = Dictionary(grouping: differences) { difference in
            [difference.activity ?? "", difference.collection ?? ""]
        }
        return grouped.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { key in
            let title = key.filter { !$0.isEmpty }.map { sdeText($0) }.joined(separator: " · ")
            let rows = (grouped[key] ?? []).map { difference -> SDEChangeRowData in
                let fields = difference.fields.map { sdeText($0) }.joined(separator: " / ")
                if let typeID = difference.typeID {
                    return SDEChangeRowData(id: difference.path.joined(separator: "/"), title: name(typeID),
                                            subtitle: difference.fields.isEmpty || difference.fields == ["quantity"] ? nil : fields,
                                            icon: icon(typeID), typeID: Int(typeID), change: difference.change,
                                            layout: difference.collection == "materials" && difference.fields.isEmpty ? .materialRecords : .inline)
                }
                return SDEChangeRowData(id: difference.path.joined(separator: "/"), title: fields, change: difference.change)
            }
            return SDEChangeSectionData(id: key.joined(separator: "/"), title: title.isEmpty ? sdeText("General") : title, rows: rows)
        }
    }
}
