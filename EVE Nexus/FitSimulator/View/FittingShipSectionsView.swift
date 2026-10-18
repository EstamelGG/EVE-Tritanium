import SwiftUI

/// Group destination: ships remain visible as independent sections while editing in place.
struct FittingShipSectionsView<NormalRow: View>: View {
    let ships: [FittingShipNode]
    let source: FittingSourceType
    @Binding var isDeleting: Bool
    let onDelete: (FittingSourceType, Set<FittingRef>) async -> Set<FittingRef>
    @ViewBuilder let normalRow: (FittingItemNode) -> NormalRow

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editMode: EditMode = .inactive
    @State private var selection = FittingCatalogSelection()
    @State private var pendingDeletion: Set<FittingRef> = []
    @State private var showingConfirmation = false
    @State private var showingFailure = false
    @State private var failedCount = 0

    private var visibleRefs: Set<FittingRef> {
        Set(ships.flatMap(\.fittings).map(\.ref))
    }

    var body: some View {
        // A selection binding in browsing mode consumes value-based NavigationLink taps.
        List(selection: editMode.isEditing ? $selection.refs : nil) {
            if ships.isEmpty {
                NoDataSection()
            } else {
                ForEach(ships) { ship in
                    Section {
                        ForEach(ship.fittings) { item in
                            if editMode.isEditing {
                                FittingCatalogRow(name: item.name, iconFileName: ship.shipInfo.iconFileName)
                                    .tag(item.ref)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                            } else {
                                normalRow(item)
                            }
                        }
                    } header: {
                        shipHeader(ship)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .disabled(isDeleting)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editMode.isEditing
                    ? NSLocalizedString("Misc_Done", comment: "")
                    : NSLocalizedString("Fitting_Catalog_Edit", comment: ""))
                {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.refs.removeAll()
                    }
                }
                .disabled(isDeleting || ships.isEmpty)
                .accessibilityIdentifier("fitting.catalog.edit")
            }
        }
        .navigationBarBackButtonHidden(isDeleting)
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            if editMode.isEditing {
                deleteButton
                    .padding(.trailing, 20)
                    .padding(.vertical, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fittingDeleteConfirmation(
            message: String(format: source == .online
                ? NSLocalizedString("Fitting_Batch_Delete_Online_Confirm", comment: "")
                : NSLocalizedString("Fitting_Batch_Delete_Local_Confirm", comment: ""),
                pendingDeletion.count),
            isPresented: $showingConfirmation,
            onConfirm: deleteSelected,
            onCancel: { pendingDeletion.removeAll() }
        )
        .alert(NSLocalizedString("Error_Delete_Fitting", comment: ""), isPresented: $showingFailure) {
            Button(NSLocalizedString("Common_OK", comment: "")) {}
        } message: {
            Text(String(format: NSLocalizedString("Fitting_Batch_Delete_Failed", comment: ""), failedCount))
        }
        .onChange(of: visibleRefs) { _, refs in
            if !isDeleting {
                selection.retainVisible(refs)
            }
        }
        .onChange(of: source) { _, _ in
            selection.refs.removeAll()
            pendingDeletion.removeAll()
            editMode = .inactive
        }
    }

    private func shipHeader(_ ship: FittingShipNode) -> some View {
        HStack(spacing: 8) {
            Text(ship.shipInfo.name)
                .lineLimit(2)
            Spacer(minLength: 8)
            if editMode.isEditing {
                let allSelected = Set(ship.fittings.map(\.ref)).isSubset(of: selection.refs)
                Button(allSelected
                    ? NSLocalizedString("Fitting_Batch_Deselect_All", comment: "")
                    : NSLocalizedString("Fitting_Batch_Select_All", comment: ""))
                {
                    selection.toggleAll(in: ship.fittings)
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.borderless)
                .disabled(isDeleting)
                .accessibilityIdentifier("fitting.catalog.selectAll.\(ship.typeId)")
                .transition(.opacity)
            }
        }
        .textCase(nil)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            pendingDeletion = selection.refs.intersection(visibleRefs)
            showingConfirmation = !pendingDeletion.isEmpty
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "trash")
                }
                Text(String(format: NSLocalizedString("Fitting_Batch_Delete_Count", comment: ""), selection.refs.count))
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.red))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .opacity(selection.refs.isEmpty ? 0.5 : 1)
        .disabled(selection.refs.isEmpty || isDeleting)
        .accessibilityIdentifier("fitting.catalog.delete")
    }

    private func deleteSelected() {
        guard !isDeleting, !pendingDeletion.isEmpty else { return }
        let requested = pendingDeletion
        let deletingSource = source
        isDeleting = true
        Task { @MainActor in
            let succeeded = await onDelete(deletingSource, requested).intersection(requested)
            selection.refs = requested.subtracting(succeeded)
            pendingDeletion.removeAll()
            isDeleting = false
            if !selection.refs.isEmpty {
                failedCount = selection.refs.count
                showingFailure = true
            }
        }
    }
}

struct FittingCatalogRow: View {
    let name: String
    let iconFileName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: IconManager.shared.loadUIImage(for: iconFileName))
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(name.isEmpty ? NSLocalizedString("Unnamed", comment: "") : name)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
