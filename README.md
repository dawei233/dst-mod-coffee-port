# 海难咖啡移植 · Coffee Port

把《饥荒：海难》(Shipwrecked) 的咖啡整套搬进 **《饥荒：联机版》的地表世界**。

作者：dawei233 ｜ 版本：0.1.8
源码：<https://github.com/dawei233/dst-mod-coffee-port>
创意工坊：<https://steamcommunity.com/sharedfiles/filedetails/?id=3810717914>
许可：**代码 GPL-3.0；美术素材版权归 Klei / Capybara**（见文末，请务必看清）

---

## 关于本项目的开发方式

**本项目由 AI 辅助开发。**
从机制取证、代码实现到测试与文档，绝大部分工作是在 AI 协助下完成的；
作者负责方向、取舍与验收。

**作者的做法：用 AI 辅助去接手「老 mod / 长期无更新的 mod」。**
社区里有很多好 mod，因为原作者退坑、没时间或跟不上版本更新而慢慢失效 ——
功能还想要，但已经落后好几个版本，也不覆盖后来新增的内容。
本项目的路子就是挑出这类 mod，**读懂它原本的机制**，然后做一个跟得上游戏更新、
覆盖也更完整的版本，并把源码完整放出来。
（本 Mod 的姊妹项目：[QuickPickPlus](https://github.com/dawei233/dst-mod-quick-pick-plus)，重做「快速采集」。）

**开源取向：尽量全部开源，遵循 GPL-3.0。**
自己写的、以及基于他人 GPL 项目改的，都会把完整源码放到 GitHub，
并以 GPL-3.0（或沿用上游原有许可证）发布。

> 如果发现授权或署名有遗漏、不当之处，欢迎提 issue，会尽快修正。

---

## 加了什么

- **咖啡丛** —— 可采摘、可铲起移植；采几轮后会枯萎，用**灰烬**施肥即可复活继续产豆
- **咖啡豆** —— 采摘获得；生的不能直接吃，得放到火上烤
- **烘焙咖啡豆** —— 火上烤制，吃下获得 30 秒大幅加速
- **咖啡** —— 烹饪锅料理，喝下获得 4 分钟加速，并随时间衰减

数值按海难原版还原：基础移速 6，咖啡 **+5 速度**（约 1.83 倍）。
所有数值都能在配置里调，咖啡的移速加成可以从 1.00 倍一路调到 10.00 倍。

**与原版唯一的不同**：海难原版【咖啡】与【烘焙咖啡豆】吃下各自 **-5 理智**（官方设定），
本 Mod **默认改成 0**（不掉理智）—— 因为 DST 的理智比单机海难难攒得多。
想还原原版手感，在配置里选「-5（海难原版）」即可。

**外观**：咖啡出锅时（锅里 / 拿在手上 / 掉在地上）是同一只杯子
（借用了游戏自带的锅成品动画），不再是三个地方三个样子。
物品栏里的图标仍是海难原版的咖啡杯。

**世界生成**：咖啡丛可在新世界自然生长（默认密度约为浆果丛的 1/4，可配置）；
也能直接用「**4 浆果 + 3 灰烬**」制作，**老存档也能用**。

**与快速采集 Mod 联动**：装了「快速采集」类 Mod
（例如 [QuickPickPlus](https://github.com/dawei233/dst-mod-quick-pick-plus)）时，
本 Mod 会自动让咖啡丛也支持快速采集。

---

## 主要配置项

| 配置 | 说明 |
|---|---|
| `speed_multiplier` | 咖啡加速的峰值倍率，默认 1.8333（= 海难原版） |
| `coffee_duration` | 喝咖啡后的加速时长（秒），默认 240（海难原版的"半天"） |
| `coffee_sanity` | 咖啡的理智变化，默认 `0`，可调回海难原版的 `-5` |
| `sweetener_mode` | 甜味剂判定：`honey`（只认蜂蜜）或 `any`（海难原版：蜂蜜/蜂巢/蜂王浆都算） |
| `plant_density` | 新世界中咖啡丛的生成密度 |

（完整配置见游戏内的 Mod 设置菜单，每一项都有中文说明。）

---

## 素材来源与版权

**本项目是「代码 + 移植素材」两部分，许可不同，请分别看待：**

| 部分 | 内容 | 版权 / 许可 |
|---|---|---|
| **代码** | `modmain.lua` · `modworldgenmain.lua` · `scripts/**` | © 2026 dawei233 · **GPL-3.0** |
| **美术素材** | `anim/*.zip` · `images/**` · `preview.jpg` · `modicon.*` | © **Klei Entertainment / Capybara Games** |

美术素材是从 **《饥荒：海难》(Shipwrecked) DLC** 中提取并重新打包的。
海难由 **Klei Entertainment** 与 **Capybara Games** 开发，**素材版权归其所有**。
本 Mod 按《饥荒》系列 mod 的通行做法，仅在**非商业**用途下使用这些素材。

其中 `images/` 下的图集并不是把原版大图集直接搬过来 ——
而是把用到的图块**重新打成只含本 Mod 所需内容的小图集**
（DXT 按 4×4 块独立压缩，只要图块坐标 4 像素对齐即可整块无损拷贝；
两个原版大图集 5.3 MB + 2.7 MB → 打出来 16 KB + 4 KB）。

**素材提取参考了 [Island Adventures](https://gitlab.com/IslandAdventures/IslandAdventures)**
—— 一个把海难整体搬进 DST 的大型开源 mod。特此致谢。
它 README 里写的是同样的话：

> *This mod contains assets from the game extension Shipwrecked for Don't Starve.
> Shipwrecked has been created by Klei Entertainment and Capybara Games.
> No copyright infringement intended.*

> ⚠️ 若版权方认为本项目对素材的使用有任何不妥，请联系我，**会立即移除相关内容**。

---

## License

### 代码

[GNU General Public License v3.0](LICENSE) 或更高版本。

```
CoffeePort · 海难咖啡移植
Copyright (C) 2026 dawei233

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.
```

### 美术素材

**不适用**上述 GPL 授权 —— 版权归 **Klei Entertainment / Capybara Games**，
按非商业 mod 惯例使用。详见上一节。
