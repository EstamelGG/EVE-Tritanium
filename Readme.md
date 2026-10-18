# EVE Tritanium · 三钛合金

面向 EVE Online 飞行员的工具箱：查询物品、比较装备、规划装配，随时掌握角色与新伊甸动态。

**iOS · iPadOS · macOS**

[中文](Readme.md) | [English](Readme.en.md)

[Download on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875) · [中国区 App Store](https://apps.apple.com/cn/app/%E4%B8%89%E9%92%9B%E5%90%88%E9%87%91/id6739530875)

<p align="center">
  <img src="img.webp" alt="EVE Tritanium" width="180">
</p>

## 功能一览

| 功能 | 可以做什么 |
| --- | --- |
| **舰船装配** | 管理模块、无人机与货舱，查看装配统计并导出方案。 |
| **资料与市场** | 查询物品数据库、比较装备属性、维护市场关注列表。 |
| **角色管理** | 查看技能与训练计划、钱包流水、资产和工业任务。 |
| **新伊甸情报** | 查询跳跃路线、势力战争、入侵与主权信息。 |

## 界面预览

以下为仓库中已有的 2025 年 5 月 iPhone 模拟器实拍截图（英文界面），展示核心使用场景；当前版本的布局与数据可能不同。点击图片查看原图。

<table>
  <tr>
    <td align="center" width="33%"><strong>物品数据库</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-11%20at%2000.27.48.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-11%20at%2000.27.48.png" width="240" alt="物品数据库"></a><br>查看舰船与装备资料、属性和抗性。</td>
    <td align="center" width="33%"><strong>装备对比</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.41.43.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.41.43.png" width="240" alt="装备对比"></a><br>并排比较属性，快速定位装备差异。</td>
    <td align="center" width="33%"><strong>市场关注列表</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.38.39.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.38.39.png" width="240" alt="市场关注列表"></a><br>按地区和买卖方向查看清单估值。</td>
  </tr>
  <tr>
    <td align="center" width="33%"><strong>技能与训练</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.43.57.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.43.57.png" width="240" alt="技能与训练"></a><br>查看训练队列、剩余时间与技能计划。</td>
    <td align="center" width="33%"><strong>跳跃导航</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.40.36.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.40.36.png" width="240" alt="跳跃导航"></a><br>查看分段航线、跳跃次数与光年距离。</td>
    <td align="center" width="33%"><strong>势力战争</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.02.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.02.png" width="240" alt="势力战争"></a><br>查看战区星系、争夺进度与前线状态。</td>
  </tr>
</table>

[查看更多截图](gallery)

## 开发与维护

<details>
<summary>构建环境、回归测试与维护命令</summary>

## 装配计算测试

测试运行、基准维护和 SDE 升级流程见[装配回归测试维护说明](EVE%20NexusTests/FittingRegression/README.txt)。

## SDE 更新

1. 如果 Tritanium 某版本开始不再兼容旧版本 app 的 sde，则需要修改 `EVE Nexus/Info.plist` 中的 `SDEMinimumAppVersion` 为当前 app 版本，以确保此版本 app 不会检查低版本的 sde 更新
2. 将 Github SDE Release 下载的图标包的 `metadata.json` 覆盖到 `EVE Nexus/utils/icons`
 
## Xcode

使用 Xcode Version 16.2 编译

## 第三方依赖

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **JWTDecode**: https://github.com/auth0/JWTDecode.swift
- **Zip**: https://github.com/marmelroy/Zip
- **Pulse**: https://github.com/kean/Pulse

## 格式化

```bash
## cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
## brew install swiftformat
swiftformat .
```

## 扫描未被使用的函数

执行此命令以扫描项目代码

```bash
periphery scan | grep -v "/Thirdparty/" > log.txt
## 在 `log.txt` 中执行此正则以过滤出我们需要处理的行
grep -iE 'Unused (Enum|Property|Function|Initializer|Class|struct)' log.txt
## 如果不为空，请逐个检查防止误报
## 如果为空，则说明没有未被使用的函数，无需优化
```

针对这些过滤出的行进行优化即可

## 未被定义的strings

```bash
swift run LocalizableChecker "/EVE-Nexus/EVE Nexus/utils/Language/en.lproj/Localizable.strings" "/EVE-Nexus/EVE Nexus" 2 --extensions swift
```

## 扫描 key 与 value 相等的 Localizable 条目

此类条目在 AnyLanguageBundle 的 `result == key` 判断中会被误判为未找到并回退英文，需关注。

```bash
perl -ne 'next if $ARGV =~ /en\.lproj/; print "$ARGV:$_" if /^"(.*)"\s*=\s*"\1";\s*$/' "EVE Nexus/utils/Language/"*"/Localizable.strings"
```

</details>

## 版权与许可

[版权与第三方许可](Copyright.md) · [项目许可证](LICENSE)
