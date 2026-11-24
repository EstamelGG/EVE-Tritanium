import SwiftUI

/// 创建一个 ObservableObject 类来管理钱包数据
class CorpWalletViewModel: ObservableObject {
    @Published var wallets: [CorpWallet] = []
    @Published var isLoading = true
    @Published var error: Error?

    let characterId: Int

    init(characterId: Int) {
        self.characterId = characterId
        loadWallets()
    }

    func loadWallets(forceRefresh: Bool = false) {
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await CorpWalletAPI.shared.fetchCorpWallets(
                    characterId: characterId, forceRefresh: forceRefresh
                )
                await MainActor.run {
                    self.wallets = result.sorted { $0.division < $1.division }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
                Logger.error("获取军团钱包数据失败: \(error)")
            }
        }
    }
}

struct CorpWalletView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpWalletViewModel

    init(characterId: Int) {
        self.characterId = characterId
        // 在初始化时创建 ViewModel 并开始加载数据
        _viewModel = StateObject(wrappedValue: CorpWalletViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if let error = viewModel.error,
                      !viewModel.isLoading && viewModel.wallets.isEmpty
            {
                // 显示错误信息
                ErrorStateSection(
                    message: error.localizedDescription
                ) {
                    viewModel.loadWallets(forceRefresh: true)
                }
            } else if viewModel.wallets.isEmpty {
                NoDataSection(icon: "banknote")
            } else {
                ForEach(viewModel.wallets, id: \.division) { wallet in
                    NavigationLink(
                        destination: CorpWalletDivisionDetails(
                            characterId: characterId,
                            division: wallet.division,
                            divisionName: wallet.name
                                ?? String(
                                    format: NSLocalizedString(
                                        "Main_Corporation_Wallet_Default", comment: ""
                                    ),
                                    wallet.division
                                )
                        )
                    ) {
                        HStack {
                            // 钱包图标
                            Image("wallet")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                // 钱包分部名称
                                Text(
                                    wallet.name
                                        ?? String(
                                            format: NSLocalizedString(
                                                "Main_Corporation_Wallet_Default", comment: ""
                                            ),
                                            wallet.division
                                        )
                                )
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                                // 余额
                                Text(FormatUtil.formatISK(wallet.balance))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 2)

                            Spacer()
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_wallet", comment: ""))
        .refreshable {
            viewModel.loadWallets(forceRefresh: true)
        }
    }
}
