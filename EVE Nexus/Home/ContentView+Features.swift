import Foundation
import SwiftUI

extension ContentView {
    func loadHiddenFeatures() {
        do {
            if !hiddenFeaturesData.isEmpty {
                hiddenFeatures = try JSONDecoder().decode(
                    Set<String>.self, from: hiddenFeaturesData
                )
            }
        } catch {
            Logger.error("加载隐藏功能列表失败: \(error)")
            hiddenFeatures = []
        }
    }

    func saveHiddenFeatures() {
        do {
            hiddenFeaturesData = try JSONEncoder().encode(hiddenFeatures)
        } catch {
            Logger.error("保存隐藏功能列表失败: \(error)")
        }
    }

    func loadPinnedFeatures() {
        do {
            if !pinnedFeaturesData.isEmpty {
                pinnedFeatures = try JSONDecoder().decode(
                    [String].self, from: pinnedFeaturesData
                )
            }
        } catch {
            Logger.error("加载置顶功能列表失败: \(error)")
            pinnedFeatures = []
        }
    }

    func savePinnedFeatures() {
        do {
            pinnedFeaturesData = try JSONEncoder().encode(pinnedFeatures)
        } catch {
            Logger.error("保存置顶功能列表失败: \(error)")
        }
    }

    func isFeaturePinned(_ featureId: String) -> Bool {
        pinnedFeatures.contains(featureId)
    }

    func toggleFeaturePin(_ featureId: String) {
        if let index = pinnedFeatures.firstIndex(of: featureId) {
            pinnedFeatures.remove(at: index)
        } else {
            pinnedFeatures.append(featureId)
        }
        savePinnedFeatures()
    }

    func isFeatureHidden(_ featureId: String) -> Bool {
        hiddenFeatures.contains(featureId)
    }

    func toggleFeatureVisibility(_ featureId: String) {
        if hiddenFeatures.contains(featureId) {
            hiddenFeatures.remove(featureId)
        } else {
            hiddenFeatures.insert(featureId)
        }
        saveHiddenFeatures()
    }

    var hasVisiblePinnedFeatures: Bool {
        pinnedFeatures.contains { featureId in
            isFeatureAvailableForCurrentUser(featureId) && !isFeatureHidden(featureId)
        }
    }

    var sortedPinnedFeatures: [String] {
        pinnedFeatures.sorted {
            FeatureRegistry.index(ofRaw: $0) < FeatureRegistry.index(ofRaw: $1)
        }
    }

    func hasVisibleFeatures(in section: FeatureSection) -> Bool {
        if isCustomizeMode {
            return true
        }
        return FeatureRegistry.features(in: section).contains { feature in
            guard feature.isAvailableOnCurrentPlatform else { return false }
            let isHidden = feature.participatesInHiding && isFeatureHidden(feature.id.rawValue)
            let isPinned = isFeaturePinned(feature.id.rawValue)
            return !isHidden && !isPinned && isFeatureAvailableForCurrentUser(feature.id.rawValue)
        }
    }

    func isFeatureAvailableForCurrentUser(_ featureId: String) -> Bool {
        guard let config = FeatureRegistry.descriptor(forRaw: featureId) else { return true }
        if config.requiresLogin {
            return currentCharacterId != 0
        }
        return true
    }

    func noteView(for feature: FeatureDescriptor) -> AnyView? {
        switch feature.noteKind {
        case .none:
            return nil
        case .skillPoints:
            let text = viewModel.characterStats.skillPoints
            guard !text.isEmpty, text != "--" else { return nil }
            return AnyView(
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
            )
        case .walletBalance:
            let text = viewModel.characterStats.walletBalance
            guard !text.isEmpty, text != "--" else { return nil }
            return AnyView(
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
            )
        case .cloneCooldown:
            return AnyView(CloneCountdownView(targetDate: viewModel.cloneCooldownEndDate))
        case .skillQueue:
            return AnyView(
                SkillQueueCountdownView(
                    queueEndDate: viewModel.skillQueueEndDate,
                    skillCount: viewModel.skillQueueCount
                )
            )
        case .killMailDataSource:
            return AnyView(
                Text(NSLocalizedString("KillMail_Data_Source", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
            )
        }
    }

    @ViewBuilder
    func featureNavigationLink(_ feature: FeatureDescriptor) -> some View {
        let raw = feature.id.rawValue
        let isHidden = feature.participatesInHiding && isFeatureHidden(raw)
        let showSelectionCircle = feature.showSelectionCircle

        let contentView = HStack {
            if isCustomizeMode && showSelectionCircle {
                Button(action: { toggleFeaturePin(raw) }) {
                    Image(systemName: isFeaturePinned(raw) ? "pin.fill" : "pin")
                        .font(.system(size: 16))
                        .foregroundColor(isFeaturePinned(raw) ? .orange : .gray)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Image(feature.icon)
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
                .drawingGroup()
                .opacity(isCustomizeMode && isHidden ? 0.4 : 1.0)

            VStack(alignment: .leading) {
                Text(feature.title)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = noteView(for: feature) {
                    note
                }
            }
            Spacer()

            if isCustomizeMode && showSelectionCircle {
                Image(systemName: !isFeatureHidden(raw) ? "eye.fill" : "eye.slash.fill")
                    .font(.title2)
                    .foregroundColor(!isFeatureHidden(raw) ? .blue : .red)
            }
        }

        Group {
            if isCustomizeMode {
                contentView
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if feature.participatesInHiding && showSelectionCircle {
                            toggleFeatureVisibility(raw)
                        }
                    }
            } else {
                NavigationLink(value: raw) {
                    contentView
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .isHidden(isHidden || isFeaturePinned(raw))
            }
        }
        .isHidden(!feature.isAvailableOnCurrentPlatform)
        .isHidden(feature.requiresLogin && currentCharacterId == 0 && !isCustomizeMode)
    }
}
