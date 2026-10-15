# EVE Tritanium · 三钛合金

A companion for EVE Online pilots: explore items, compare equipment, plan fittings and keep up with your characters and New Eden.

**iOS · iPadOS · macOS**

[中文](Readme.md) | [English](Readme.en.md)

[Download on the App Store](https://apps.apple.com/us/app/tritanium/id6739530875) · [中国区 App Store](https://apps.apple.com/cn/app/%E4%B8%89%E9%92%9B%E5%90%88%E9%87%91/id6739530875)

<p align="center">
  <img src="img.webp" alt="EVE Tritanium" width="180">
</p>

## At a glance

| Feature | What you can do |
| --- | --- |
| **Ship fitting** | Manage modules, drones and cargo, inspect fitting stats and export fits. |
| **Database & market** | Browse items, compare equipment attributes and maintain market watch lists. |
| **Character management** | Review skills and training plans, wallet journals, assets and industry jobs. |
| **New Eden intel** | Explore jump routes, faction warfare, incursions and sovereignty. |

## Screenshots

Existing iPhone simulator captures from May 2025, showing the English interface. Layouts and data may differ in the current release. Click an image to view it at full size.

<table>
  <tr>
    <td align="center" width="33%"><strong>Item database</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-11%20at%2000.27.48.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-11%20at%2000.27.48.png" width="240" alt="Item database"></a><br>Explore ships, equipment, attributes and resistances.</td>
    <td align="center" width="33%"><strong>Module comparison</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.41.43.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.41.43.png" width="240" alt="Module comparison"></a><br>Compare attributes and focus on differences between modules.</td>
    <td align="center" width="33%"><strong>Market watch lists</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.38.39.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.38.39.png" width="240" alt="Market watch lists"></a><br>Value item lists by region and buy or sell orders.</td>
  </tr>
  <tr>
    <td align="center" width="33%"><strong>Skills & training</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.43.57.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.43.57.png" width="240" alt="Skills & training"></a><br>Review your training queue, remaining time and skill plans.</td>
    <td align="center" width="33%"><strong>Jump navigation</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.40.36.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.40.36.png" width="240" alt="Jump navigation"></a><br>Inspect route segments, jump counts and distance in light-years.</td>
    <td align="center" width="33%"><strong>Faction warfare</strong><br><br><a href="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.02.png"><img src="gallery/Simulator%20Screenshot%20-%20iPhone%2016%20Pro%20Max%20-%202025-05-10%20at%2023.42.02.png" width="240" alt="Faction warfare"></a><br>Explore warzone systems, contested levels and frontline status.</td>
  </tr>
</table>

[More screenshots](gallery)

## Development

<details>
<summary>Build environment and maintenance commands</summary>

## Xcode

Compiled with Xcode Version 16.2

## Third-party Dependencies

- **AppAuth-IOS**: https://github.com/openid/AppAuth-iOS
- **JWTDecode**: https://github.com/auth0/JWTDecode.swift
- **Zip**: https://github.com/marmelroy/Zip
- **Pulse**: https://github.com/kean/Pulse

## Formatting

```bash
cd "EVE Nexus" && $(xcrun --find swift-format) -r . -i --configuration .swift-format.json
```

## Scan Unused Functions

```bash
periphery scan | grep -v "/Thirdparty/" > log.txt
```

</details>

## Copyright & license

[Copyright and third-party licenses](Copyright.md) · [Project license](LICENSE)
