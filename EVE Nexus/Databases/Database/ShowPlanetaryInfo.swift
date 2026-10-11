import SwiftUI

struct ShowPlanetaryInfo: View {
    @Environment(\.locale) private var displayLocale
    private typealias TypeRef = (typeID: Int, name: String, iconFileName: String)

    let itemID: Int
    @ObservedObject var databaseManager: DatabaseManager

    @State private var itemDetails: ItemDetails?
    @State private var inputs: [(typeID: Int, name: String, iconFileName: String, quantity: Int)] = []
    @State private var output: (outputValue: Int, cycleTime: Int)?
    @State private var uses: [TypeRef] = []
    @State private var facilities: [TypeRef] = []
    @State private var harvestSources: [TypeRef] = []

    private let rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

    var body: some View {
        List {
            if let itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails,
                    databaseManager: databaseManager,
                    modifiedAttributes: nil
                )
            }

            if !inputs.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Planetary_Input_Materials", comment: ""))
                        .font(.headline)
                ) {
                    ForEach(inputs, id: \.typeID) { input in
                        NavigationLink {
                            ItemInfoMap.getItemInfoView(
                                itemID: input.typeID,
                                databaseManager: databaseManager
                            )
                        } label: {
                            HStack {
                                typeIcon(input.iconFileName)
                                Text(input.name)
                                    .font(.body)
                                Spacer()
                                Text(
                                    "\(input.quantity) \(NSLocalizedString("Misc_number_item", comment: ""))"
                                )
                                .font(.body)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowInsets(rowInsets)
                }
            }

            if let output {
                Section(
                    header: Text(NSLocalizedString("Planetary_Output_Info", comment: ""))
                        .font(.headline)
                ) {
                    HStack {
                        Text(NSLocalizedString("Planetary_Output_Quantity", comment: ""))
                        Spacer()
                        Text(
                            "\(output.outputValue) \(NSLocalizedString("Misc_number_item", comment: ""))"
                        )
                        .foregroundColor(.secondary)
                        .frame(alignment: .trailing)
                    }

                    HStack {
                        Text(NSLocalizedString("Planetary_Cycle_Time", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatBlueprintDuration(output.cycleTime))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            typeLinkSection(
                title: NSLocalizedString("Planetary_Uses", comment: ""),
                items: uses
            )
            typeLinkSection(
                title: NSLocalizedString("Planetary_Facilities", comment: ""),
                items: facilities
            )
            typeLinkSection(
                title: NSLocalizedString("Planetary_Harvest_from", comment: ""),
                items: harvestSources
            )

            IndustrySection(
                itemID: itemID,
                databaseManager: databaseManager,
                itemDetails: itemDetails
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: itemID)
            loadPlanetaryData()
            loadHarvestSources()
        }
    }

    @ViewBuilder
    private func typeLinkSection(title: String, items: [TypeRef]) -> some View {
        if !items.isEmpty {
            Section(
                header: Text(title).font(.headline)
            ) {
                ForEach(items, id: \.typeID) { item in
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: item.typeID,
                            databaseManager: databaseManager
                        )
                    } label: {
                        HStack {
                            typeIcon(item.iconFileName)
                            Text(item.name)
                                .font(.body)
                        }
                    }
                }
                .listRowInsets(rowInsets)
            }
        }
    }

    private func typeIcon(_ iconFileName: String) -> some View {
        IconManager.shared.loadImage(for: iconFileName)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(4)
    }

    private func loadPlanetaryData() {
        loadInputs()
        loadOutput()
        loadUses()
        loadFacilities()
    }

    private func loadInputs() {
        let query = """
            SELECT input_typeid, input_value
            FROM planetSchematics
            WHERE output_typeid = ?
        """
        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID]),
              let row = rows.first,
              let inputTypeIDs = row["input_typeid"] as? String,
              let inputValues = row["input_value"] as? String
        else { return }

        let typeIDs = inputTypeIDs.split(separator: ",").compactMap { Int($0) }
        let values = inputValues.split(separator: ",").compactMap { Int($0) }

        inputs = zip(typeIDs, values).compactMap { typeID, quantity in
            guard let details = databaseManager.getItemDetails(for: typeID) else { return nil }
            return (
                typeID: typeID,
                name: details.name,
                iconFileName: details.iconFileName,
                quantity: quantity
            )
        }
    }

    private func loadOutput() {
        let query = """
            SELECT output_value, cycle_time
            FROM planetSchematics
            WHERE output_typeid = ?
        """
        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID]),
              let row = rows.first,
              let outputValue = row["output_value"] as? Int,
              let cycleTime = row["cycle_time"] as? Int
        else { return }

        output = (outputValue: outputValue, cycleTime: cycleTime)
    }

    private func loadUses() {
        let query = """
            SELECT output_typeid
            FROM planetSchematics
            WHERE instr(',' || input_typeid || ',', ',\(itemID),') > 0
        """
        guard case let .success(rows) = databaseManager.executeQuery(query) else { return }

        uses = rows.compactMap { row in
            guard let typeID = row["output_typeid"] as? Int,
                  let details = databaseManager.getItemDetails(for: typeID)
            else { return nil }
            return (typeID: typeID, name: details.name, iconFileName: details.iconFileName)
        }
    }

    private func loadFacilities() {
        let query = """
            SELECT facilitys
            FROM planetSchematics
            WHERE output_typeid = ?
        """
        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID]),
              let row = rows.first,
              let facilityIDs = row["facilitys"] as? String
        else { return }

        facilities = facilityIDs.split(separator: ",")
            .compactMap { Int($0) }
            .compactMap { facilityID in
                guard let details = databaseManager.getItemDetails(for: facilityID) else {
                    return nil
                }
                return (
                    typeID: facilityID,
                    name: details.name,
                    iconFileName: details.iconFileName
                )
            }
    }

    private func loadHarvestSources() {
        let query = """
            SELECT harvest_typeid
            FROM planetResourceHarvest
            WHERE typeid = ?
        """
        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID])
        else { return }

        harvestSources = rows.compactMap { row in
            guard let harvestTypeID = row["harvest_typeid"] as? Int,
                  let details = databaseManager.getItemDetails(for: harvestTypeID)
            else { return nil }
            return (
                typeID: harvestTypeID,
                name: details.name,
                iconFileName: details.iconFileName
            )
        }
    }
}
