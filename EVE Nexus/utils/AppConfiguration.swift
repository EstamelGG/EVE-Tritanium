import Foundation

enum AppConfiguration {
    /// 应用版本信息
    enum Version {
        static var fullVersion: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? NSLocalizedString("Unknown", comment: "")
        }
    }

    /// SDE CloudKit 配置
    enum SDE {
        static var minimumAppVersion: String {
            Bundle.main.object(forInfoDictionaryKey: "SDEMinimumAppVersion") as? String ?? "1.13"
        }

        static var recordType: String {
            Bundle.main.object(forInfoDictionaryKey: "SDERecordType") as? String ?? "SDE_Record"
        }
    }

    /// 装配模拟器调试配置
    enum Fitting {
        static let collapseIdenticalModulesKey = "fittingCollapseIdenticalModulesByDefault"

        static var collapseIdenticalModulesByDefault: Bool {
            UserDefaults.standard.bool(forKey: collapseIdenticalModulesKey)
        }

        static var showDebug: Bool {
            Bundle.main.object(forInfoDictionaryKey: "showFittingDebug") as? Bool ?? false
        }
    }

    /// 数据库版本信息
    enum Database {
        struct VersionInfo {
            let buildNumber: Int
            let patchNumber: Int?
            let releaseDate: String

            var displayVersion: String {
                return "\(buildNumber)"
            }

            var isPatchVersion: Bool {
                guard let patch = patchNumber else { return false }
                return patch > 0
            }

            var formattedReleaseDate: String {
                let dateFormatter = ISO8601DateFormatter()
                if let releaseDate = dateFormatter.date(from: releaseDate) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "yyyy-MM-dd"
                    return displayFormatter.string(from: releaseDate)
                } else {
                    return String(releaseDate.prefix(10))
                }
            }

            var fullVersion: String {
                return "\(formattedReleaseDate)-\(displayVersion)"
            }
        }

        static var detailedVersionInfo: VersionInfo? {
            return getSDEVersionInfo()
        }

        private static func getSDEVersionInfo() -> VersionInfo? {
            let databaseManager = DatabaseManager.shared

            let query = "SELECT build_number, patch_number, release_date FROM version_info WHERE id = 1"

            if case let .success(results) = databaseManager.executeQuery(query, useCache: false),
               let row = results.first,
               let releaseDateString = row["release_date"] as? String
            {
                let buildNumber = getIntValue(from: row["build_number"])
                let patchNumber = getIntValue(from: row["patch_number"])

                return VersionInfo(
                    buildNumber: buildNumber,
                    patchNumber: patchNumber > 0 ? patchNumber : nil,
                    releaseDate: releaseDateString
                )
            }

            return nil
        }

        /// 处理可能是Int、Double或String的数值字段
        private static func getIntValue(from value: Any?) -> Int {
            if let intValue = value as? Int {
                return intValue
            } else if let doubleValue = value as? Double {
                return Int(doubleValue)
            } else if let int64Value = value as? Int64 {
                return Int(int64Value)
            } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                return intValue
            } else {
                return 0
            }
        }
    }
}
