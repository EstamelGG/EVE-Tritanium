import SwiftUI

extension ContentView {
    var pinnedFeaturesSection: some View {
        Section {
            ForEach(sortedPinnedFeatures, id: \.self) { featureId in
                if isFeatureAvailableForCurrentUser(featureId),
                   !isFeatureHidden(featureId),
                   let feature = FeatureRegistry.descriptor(forRaw: featureId)
                {
                    NavigationLink(value: featureId) {
                        HStack {
                            Image(feature.icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                                .drawingGroup()

                            VStack(alignment: .leading) {
                                Text(feature.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let note = noteView(for: feature) {
                                    note
                                }
                            }
                            Spacer()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        } header: {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 16))
                Text(NSLocalizedString("Main_Pinned_Features", comment: "常用功能"))
            }
        }
    }

    var loginSection: some View {
        Section {
            NavigationLink(value: "accounts") {
                LoginButtonView(
                    isLoggedIn: currentCharacterId != 0,
                    serverStatus: viewModel.serverStatus,
                    selectedCharacter: viewModel.selectedCharacter,
                    characterPortrait: viewModel.characterPortrait,
                    isRefreshing: viewModel.isRefreshing,
                    isRefreshTokenExpired: isRefreshTokenExpired,
                    mainViewModel: viewModel
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            .onDisappear {
                if currentCharacterId != 0 {
                    let auth = EVELogin.shared.getCharacterByID(currentCharacterId)
                    if auth == nil {
                        currentCharacterId = 0
                        viewModel.resetCharacterInfo()
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ServerStatusView(mainViewModel: viewModel)
                    Spacer()
                    if sdeUpdateChecker.updateStatus == .hasUpdate {
                        sdeUpdateAvailableButton
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)),
                                    removal: .opacity.combined(with: .scale(scale: 0.8, anchor: .trailing))
                                )
                            )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: sdeUpdateChecker.updateStatus)
                RateLimitCooldownView()
            }
        }
    }

    func featureSection(_ section: FeatureSection) -> some View {
        Section {
            ForEach(FeatureRegistry.features(in: section)) { feature in
                featureNavigationLink(feature)
            }
        } header: {
            featureSectionHeader(section)
        }
        .isHidden(!hasVisibleFeatures(in: section))
    }

    private func featureSectionHeader(_ section: FeatureSection) -> some View {
        Text(section.title)
    }

    private var sdeUpdateAvailableButton: some View {
        Button {
            showingSDEUpdateSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(NSLocalizedString("Main_SDE_Update_Available", comment: ""))
                    .font(.caption)
                    .foregroundColor(.green)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    var characterSection: some View {
        featureSection(.character)
    }

    var corporationSection: some View {
        featureSection(.corporation)
    }

    var databaseSection: some View {
        featureSection(.database)
    }

    var businessSection: some View {
        featureSection(.business)
    }

    var KillBoardSection: some View {
        featureSection(.battle)
    }

    var FittingSection: some View {
        featureSection(.fitting)
    }

    var otherSection: some View {
        Section {
            ForEach(FeatureRegistry.features(in: .other)) { feature in
                featureNavigationLink(feature)
            }
        } header: {
            featureSectionHeader(.other)
        } footer: {
            otherSectionFooter
        }
        .isHidden(!hasVisibleFeatures(in: .other))
    }

    var otherSectionFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                if isCustomizeMode {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCustomizeMode = false
                        }
                    }) {
                        Text(NSLocalizedString("Features_Exit_Customize", comment: ""))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCustomizeMode.toggle()
                        }
                    }) {
                        let hiddenCount = hiddenFeatures.count
                        if hiddenCount > 0 {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Features_Too_Many_With_Count", comment: ""
                                    ),
                                    hiddenCount
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.blue)
                        } else {
                            Text(NSLocalizedString("Features_Too_Many", comment: ""))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                Spacer()
            }

            if isCustomizeMode {
                HStack {
                    Spacer()
                    Button(action: {
                        hiddenFeatures.removeAll()
                        saveHiddenFeatures()
                    }) {
                        Text(NSLocalizedString("Features_Restore_Default", comment: ""))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }

                Text(NSLocalizedString("Features_Customize_Mode", comment: ""))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 8)
    }
}
