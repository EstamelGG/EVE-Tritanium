# EVE Tritanium

![img.png](img.webp)

[中文](Readme.md) | [English](Readme.en.md)

# SDE 更新

1. 如果 Tritanium 某版本开始不再兼容旧版本 app 的 sde，则需要修改 `EVE Nexus/Info.plist` 中的 `SDEMinimumAppVersion` 为当前 app 版本，以确保此版本 app 不会检查低版本的 sde 更新
2. 将 Github SDE Release 下载的图标包的 `metadata.json` 覆盖到 `EVE Nexus/utils/icons`
 
# Xcode

使用 Xcode Version 16.2 编译

# 第三方依赖

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **JWTDecode**: https://github.com/auth0/JWTDecode.swift
- **Zip**: https://github.com/marmelroy/Zip
- **Pulse**: https://github.com/kean/Pulse

# 格式化

```bash
# cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
# brew install swiftformat
swiftformat .
```

# 扫描未被使用的函数

执行此命令以扫描项目代码

```bash
periphery scan | grep -v "/Thirdparty/" > log.txt
# 在 `log.txt` 中执行此正则以过滤出我们需要处理的行
grep -iE 'Unused (Enum|Property|Function|Initializer|Class|struct)' log.txt
# 如果不为空，请逐个检查防止误报
# 如果为空，则说明没有未被使用的函数，无需优化
```

针对这些过滤出的行进行优化即可

# 未被定义的strings

```bash
swift run LocalizableChecker "/EVE-Nexus/EVE Nexus/utils/Language/en.lproj/Localizable.strings" "/EVE-Nexus/EVE Nexus" 2 --extensions swift
```

# 扫描 key 与 value 相等的 Localizable 条目

此类条目在 AnyLanguageBundle 的 `result == key` 判断中会被误判为未找到并回退英文，需关注。

```bash
perl -ne 'next if $ARGV =~ /en\.lproj/; print "$ARGV:$_" if /^"(.*)"\s*=\s*"\1";\s*$/' "EVE Nexus/utils/Language/"*"/Localizable.strings"
```

# 获取应用 / Get App

iOS / iPadOS / macOS: 

- [Tritanium on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875)
- [三钛合金(App Store)](https://apps.apple.com/cn/app/%E4%B8%89%E9%92%9B%E5%90%88%E9%87%91/id6739530875)
