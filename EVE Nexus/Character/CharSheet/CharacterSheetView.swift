import SwiftUI

struct CharacterSheetView: View {
    @Environment(\.timeZone) private var displayTimeZone
    @StateObject private var viewModel: CharacterSheetViewModel

    init(
        character: EVECharacterInfo, characterPortrait: UIImage?,
        databaseManager: DatabaseManager = DatabaseManager()
    ) {
        _viewModel = StateObject(
            wrappedValue: CharacterSheetViewModel(
                character: character,
                characterPortrait: characterPortrait,
                databaseManager: databaseManager
            )
        )
    }

    var body: some View {
        List {
            basicInfoSection
            fatigueSection
            detailPagesSection
        }
        .navigationTitle(NSLocalizedString("Main_Character_Sheet", comment: ""))
        .onAppear {
            viewModel.loadInitialData()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section {
            HStack {
                viewModel.portraitImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .foregroundColor(
                        viewModel.characterPortrait == nil ? Color.primary.opacity(0.5) : nil
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(
                            Color.primary.opacity(0.2), lineWidth: 1
                        )
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                    )
                    .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        HStack {
                            if viewModel.isLoadingOnlineStatus {
                                OnlineStatusIndicator(
                                    isOnline: true, size: 8, isLoading: true, statusUnknown: false
                                )
                            } else if let status = viewModel.onlineStatus {
                                OnlineStatusIndicator(
                                    isOnline: status.online, size: 8, isLoading: false,
                                    statusUnknown: false
                                )
                            } else {
                                OnlineStatusIndicator(
                                    isOnline: false, size: 8, isLoading: false, statusUnknown: true
                                )
                            }
                        }
                        .frame(width: 18, alignment: .center)

                        Text(viewModel.character.CharacterName)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if let corporation = viewModel.corporationInfo, let logo = viewModel.corporationLogo {
                        organizationRow(logo: logo, name: corporation.name, ticker: corporation.ticker)
                    } else {
                        organizationPlaceholderRow(
                            text: NSLocalizedString("No Corporation", comment: "")
                        )
                    }

                    if let alliance = viewModel.allianceInfo, let logo = viewModel.allianceLogo {
                        organizationRow(logo: logo, name: alliance.name, ticker: alliance.ticker)
                    } else {
                        organizationPlaceholderRow(
                            text: NSLocalizedString("No Alliance", comment: "")
                        )
                    }
                }
                .padding(.leading, 2)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = viewModel.character.CharacterName
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_CharID", comment: ""),
                        systemImage: "doc.on.doc"
                    )
                }

                Divider()

                if viewModel.corporationInfo != nil, let corpId = viewModel.character.corporationId {
                    NavigationLink {
                        navigationDestination(for: corpId, type: "corporation")
                    } label: {
                        Label(
                            NSLocalizedString("View Corporation", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                }
                if viewModel.allianceInfo != nil, let allianceId = viewModel.character.allianceId {
                    NavigationLink {
                        navigationDestination(for: allianceId, type: "alliance")
                    } label: {
                        Label(
                            NSLocalizedString("View Alliance", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                }
            }

            if let birthday = viewModel.birthday {
                HStack {
                    assetIconView(name: "channeloperator")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Character_Birthday", comment: ""))
                            .font(.body)
                            .foregroundColor(.primary)
                        if let date = viewModel.isoDateFormatter.date(from: birthday) {
                            Text(
                                "\(viewModel.formatBirthday(date)) (\(viewModel.calculateAge(from: date)))"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let security = viewModel.securityStatus {
                HStack {
                    assetIconView(name: "securitystatus")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Character_Security_Status", comment: ""))
                            .font(.body)
                            .foregroundColor(.primary)
                        Text(String(format: "%.2f", security))
                            .font(.caption)
                            .foregroundColor(viewModel.getSecurityStatusColor(security))
                    }
                }
            }

            HStack {
                if let typeId = viewModel.locationTypeId,
                   let iconFileName = viewModel.getTypeIcon(typeId: typeId)
                {
                    typeIconView(iconFileName: iconFileName)
                } else if let location = viewModel.currentLocation,
                          let iconFileName = viewModel.getSystemIcon(solarSystemId: location.systemId)
                {
                    typeIconView(iconFileName: iconFileName)
                } else {
                    typeIconView(iconFileName: nil)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Character_Current_Location", comment: ""))
                    if let locationDetail = viewModel.locationDetail {
                        LocationInfoView(
                            stationName: locationDetail.stationName,
                            solarSystemName: locationDetail.solarSystemName,
                            security: locationDetail.security,
                            font: .caption,
                            textColor: .secondary
                        )
                    } else if let location = viewModel.currentLocation {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(formatSystemSecurity(location.security))
                                    .foregroundColor(getSecurityColor(location.security))
                                Text("\(location.systemName) / \(location.regionName)")
                                if let status = viewModel.locationStatus {
                                    Text(status.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Unknown")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                typeIconView(
                    iconFileName: viewModel.currentShip.flatMap {
                        viewModel.getTypeIcon(typeId: $0.ship_type_id)
                    }
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Character_Current_Ship", comment: ""))
                        .font(.body)
                        .foregroundColor(.primary)
                    if viewModel.currentShip != nil, let typeName = viewModel.shipTypeName {
                        Text(typeName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unknown")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text(NSLocalizedString("Common_info", comment: ""))
        }
        .listRowInsets(listRowPadding)
    }

    private var fatigueSection: some View {
        Section {
            if viewModel.isLoadingFatigue {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            } else if let fatigue = viewModel.fatigue {
                HStack {
                    assetIconView(name: "capitalnavigation")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(NSLocalizedString("Character_Jump_Fatigue", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)

                            if let jumpFatigueExpireDate = fatigue.jump_fatigue_expire_date,
                               let expireDate = viewModel.isoDateFormatter.date(from: jumpFatigueExpireDate)
                            {
                                let remainingTime = expireDate.timeIntervalSince(Date())
                                if remainingTime > 0 {
                                    Text(viewModel.formatRemainingTime(remainingTime))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text(NSLocalizedString("Character_No_Jump_Fatigue", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        if let lastJumpDate = fatigue.last_jump_date,
                           let jumpDate = viewModel.isoDateFormatter.date(from: lastJumpDate)
                        {
                            Text(
                                String(
                                    format: NSLocalizedString("Character_Last_Jump", comment: ""),
                                    viewModel.formatDate(jumpDate)
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .transition(.opacity)
            }
        } header: {
            Text(NSLocalizedString("Timer", comment: ""))
        }
        .listRowInsets(listRowPadding)
    }

    /// 详情入口 section：技能属性/奖章/雇佣记录/势力与军衔跳转（子页面懒加载）
    private var detailPagesSection: some View {
        Section {
            detailPageLink(
                title: NSLocalizedString("Character_Attributes_Basic", comment: ""),
                icon: "attributes"
            ) {
                CharacterAttributesPage(character: viewModel.character)
            }

            detailPageLink(
                title: NSLocalizedString("Character_Medals", comment: ""),
                icon: "achievements"
            ) {
                CharacterMedalsPage(character: viewModel.character)
            }

            detailPageLink(
                title: NSLocalizedString("Employment History", comment: ""),
                icon: "employmenthistory"
            ) {
                CharacterEmploymentPage(character: viewModel.character)
            }

            detailPageLink(
                title: NSLocalizedString("Character_Standings_Contacts", comment: "声望与联系人"),
                icon: "personalstandings"
            ) {
                CharacterStandingsContactsPage(character: viewModel.character)
            }

            if viewModel.hasFaction {
                detailPageLink(
                    title: NSLocalizedString("Character_Faction_And_Rank", comment: "势力与军衔"),
                    icon: "corporationdecorations"
                ) {
                    CharacterFactionPage(character: viewModel.character)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
    }

    private func detailPageLink<Content: View>(
        title: String, icon: String, @ViewBuilder destination: @escaping () -> Content
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                assetIconView(name: icon)

                Text(title)
            }
        }
    }

    // MARK: - View Builders

    private var listRowPadding: EdgeInsets {
        EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
    }

    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        switch type {
        case "corporation":
            CorporationDetailView(corporationId: id, character: viewModel.character)
        case "alliance":
            AllianceDetailView(allianceId: id, character: viewModel.character)
        default:
            EmptyView()
        }
    }

    private func organizationRow(logo: UIImage, name: String, ticker: String) -> some View {
        HStack(spacing: 4) {
            Image(uiImage: logo)
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Text("[\(ticker)] \(name)")
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func organizationPlaceholderRow(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "square.dashed")
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundColor(.gray)
            Text("[-] \(text)")
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func typeIconView(iconFileName: String?) -> some View {
        if let iconFileName {
            IconManager.shared.loadImage(for: iconFileName)
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
        } else {
            Image("not_found")
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
        }
    }

    private func assetIconView(name: String) -> some View {
        Image(name)
            .resizable()
            .frame(width: 36, height: 36)
            .cornerRadius(6)
    }
}
