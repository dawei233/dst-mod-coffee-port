-- 海难咖啡移植 Coffee Port
-- 把《饥荒：海难》(Shipwrecked) DLC 的咖啡全套移植到 DST 地表世界。
-- 本文件是 mod 的描述与配置菜单。

name = "海难咖啡移植 Coffee Port"
description =
[[把《饥荒：海难》(Shipwrecked) 的咖啡整套搬进 DST 地表世界：

  · 咖啡丛 —— 可采摘、可铲起移植、采几轮会枯萎，施肥后复活
  · 咖啡豆 —— 采摘获得，生的不能直接吃，得放到火上烤
  · 烘焙咖啡豆 —— 火上烤制，吃了 30 秒大幅加速（原版数值）
  · 咖啡 —— 烹饪锅料理，喝下获得 4 分钟加速并随时间衰减

数值按海难原版还原：基础移速 6，咖啡 +5 速度（约 1.83 倍）。
所有数值都能在下面的配置里调整，咖啡移速加成可从 1.00 倍一路调到 10.00 倍。

唯一改动：海难原版【咖啡】与【烘焙咖啡豆】吃下各自 -5 理智（官方设定），
本 Mod 默认改成 0（不掉理智），想还原原版手感在配置里选「-5（海难原版）」。

外观：咖啡出锅时锅里、拿在手上、掉在地上是同一只杯子（借用游戏自带的
锅成品动画），不再是三个地方三个样子。物品栏里的图标仍是海难原版的咖啡杯。

咖啡丛可在新世界自然生长（默认密度约为浆果丛的 1/4，可在配置里调），
也能用「4 浆果 + 3 灰烬」直接制作（老存档也能用）。

装了「Quick Pick」这类快速采集 Mod 时，本 Mod 会自动让咖啡丛也支持快速采集。

【关于本 Mod】
· 本 Mod 由 AI 辅助开发（作者定方向与取舍，AI 负责绝大部分取证、实现与测试）。
  作者的方向是：用 AI 辅助去接手那些「老的、长期没有更新」的 mod ——
  读懂它原本的机制，做一个跟得上游戏更新、覆盖也更完整的版本。
· 所有项目都尽量全部开源并遵循 GPL-3.0，完整源码：
  https://github.com/dawei233/dst-mod-coffee-port
· 【代码】依 GPL-3.0 发布；【美术素材】版权归 Klei Entertainment /
  Capybara Games，提取自《饥荒：海难》DLC，仅在非商业 mod 范围内使用。]]

author = "dawei233"
version = "0.1.8"
forumthread = "https://github.com/dawei233/dst-mod-coffee-port"

api_version = 10

dst_compatible = true
all_clients_require_mod = true
client_only_mod = false

server_filter_tags = { "coffee", "shipwrecked", "咖啡", "海难" }

-- 游戏内 mod 列表里显示的图标（128x128，用 Mod Tools 的 png.exe 从 modicon.png 生成）
icon_atlas = "modicon.xml"
icon = "modicon.tex"

-----------------------
-- 配置菜单
-----------------------

local YES_NO =
{
    { description = "开启", data = true,  hover = "On" },
    { description = "关闭", data = false, hover = "Off" },
}

configuration_options =
{
    {
        name = "coffee_speed",
        label = "咖啡移速加成",
        hover =
            "加速时移动速度的峰值倍率。海难原版为基础速度 6 点、咖啡 +5 点，即 11/6 ≈ 1.8333 倍。\n" ..
            "1.00 倍＝完全不加速；数值越大跑得越快。\n" ..
            "想要列表里没有的精确数值（例如 2.7）：在服务器的 modoverrides.lua 里写\n" ..
            "CoffeePort = { configuration_options = { coffee_speed = 2.7 } }\n" ..
            "该写法支持任意小数（游戏内配置菜单只提供下拉列表，无法手动输入）。",
        options =
        {
            { description = "原版 1.83 倍（+5 速度）", data = 1.8333, hover = "海难原版数值" },

            { description = "1.00 倍（不加速）", data = 1.00, hover = "" },
            { description = "1.10 倍",           data = 1.10, hover = "" },
            { description = "1.20 倍",           data = 1.20, hover = "" },
            { description = "1.30 倍",           data = 1.30, hover = "" },
            { description = "1.40 倍",           data = 1.40, hover = "" },
            { description = "1.50 倍",           data = 1.50, hover = "" },
            { description = "1.60 倍",           data = 1.60, hover = "" },
            { description = "1.70 倍",           data = 1.70, hover = "" },
            { description = "1.80 倍",           data = 1.80, hover = "" },
            { description = "1.90 倍",           data = 1.90, hover = "" },
            { description = "2.00 倍",           data = 2.00, hover = "" },
            { description = "2.25 倍",           data = 2.25, hover = "" },
            { description = "2.50 倍",           data = 2.50, hover = "" },
            { description = "2.75 倍",           data = 2.75, hover = "" },
            { description = "3.00 倍",           data = 3.00, hover = "" },
            { description = "3.50 倍",           data = 3.50, hover = "" },
            { description = "4.00 倍",           data = 4.00, hover = "" },
            { description = "5.00 倍",           data = 5.00, hover = "" },
            { description = "6.00 倍",           data = 6.00, hover = "" },
            { description = "8.00 倍",           data = 8.00, hover = "" },
            { description = "10.00 倍",          data = 10.00, hover = "飞到起飞" },
        },
        default = 1.8333,
    },
    {
        name = "coffee_duration",
        label = "咖啡加速持续时间",
        hover = "喝下咖啡后加速持续的秒数。海难原版是「半天」，约 240 秒。",
        options =
        {
            { description = "4 分钟（原版）", data = 240, hover = "" },
            { description = "2 分钟",        data = 120, hover = "" },
            { description = "6 分钟",        data = 360, hover = "" },
            { description = "8 分钟",        data = 480, hover = "" },
        },
        default = 240,
    },
    {
        name = "coffee_decay",
        label = "咖啡加速随时间衰减",
        hover = "开启＝原版手感：速度从峰值线性衰减回正常；关闭＝全程保持峰值速度。",
        options =
        {
            { description = "开启（原版）", data = true,  hover = "" },
            { description = "关闭",         data = false, hover = "" },
        },
        default = true,
    },
    {
        name = "coffee_sanity",
        label = "咖啡的理智值",
        hover =
            "喝下一杯咖啡回多少理智。\n" ..
            "\n" ..
            "⚠ 海难原版是 -5（也就是掉 5 点理智）—— 这是官方设定，不是本 Mod 的失误，\n" ..
            "官方解释是「咖啡因过量带来的心悸与焦虑」。\n" ..
            "但 DST 的理智比单机海难更难攒，所以本 Mod 默认改成 0（不掉）。\n" ..
            "想按原版手感玩就选 -5；想让它顺便补理智就选正数。\n" ..
            "\n" ..
            "要列表里没有的数值（例如 +7.5）：在 modoverrides.lua 里写\n" ..
            "CoffeePort = { configuration_options = { coffee_sanity = 7.5 } }",
        options =
        {
            { description = "0（不掉理智）",   data = 0,  hover = "本 Mod 默认" },
            { description = "-5（海难原版）",  data = -5, hover = "原版数值" },
            { description = "+5",             data = 5,  hover = "" },
            { description = "+10",            data = 10, hover = "" },
        },
        default = 0,
    },
    {
        name = "sweetener_mode",
        label = "咖啡的甜味剂",
        hover =
            "决定锅里第四格能放什么。\n" ..
            "\n" ..
            "【只认蜂蜜】（本 Mod 默认）\n" ..
            "  3 烘焙咖啡豆 + 蜂蜜，或者直接用 4 烘焙咖啡豆。\n" ..
            "  跟烹饪书里画出来的配方一致（书里标的就是蜂蜜），\n" ..
            "  也跟「智能锅」等 Mod 读到的菜谱卡数据一致。\n" ..
            "\n" ..
            "【任意甜味剂】\n" ..
            "  单机《海难》原版的判定：蜂蜜 / 蜂巢（蜜脾）/ 蜂王浆 都算甜味度，\n" ..
            "  中文百科原话是「甜味剂包括蜂蜜和蜂巢（是的，蜂巢可以入锅）」。\n" ..
            "  想要原汁原味的手感就选这个。\n" ..
            "\n" ..
            "注：乳制品（黄油 / 羊奶 / 蛋清）两种口径下都能用，不受本项影响。",
        options =
        {
            { description = "只认蜂蜜（与书里配方一致）", data = "honey", hover = "本 Mod 默认" },
            { description = "任意甜味剂（海难原版）",      data = "any",   hover = "蜂蜜 / 蜂巢 / 蜂王浆" },
        },
        default = "honey",
    },
    {
        name = "roasted_speed_time",
        label = "烘焙咖啡豆加速时间",
        hover = "单吃烘焙咖啡豆（不下锅）获得的加速秒数。海难原版 30 秒。",
        options =
        {
            { description = "30 秒（原版）", data = 30,  hover = "" },
            { description = "15 秒",        data = 15,  hover = "" },
            { description = "60 秒",        data = 60,  hover = "" },
            { description = "不加成",       data = 0,   hover = "" },
        },
        default = 30,
    },
    {
        name = "roasted_sanity",
        label = "烘焙咖啡豆的理智值",
        hover =
            "直接吃烘焙咖啡豆（不下锅）回多少理智。\n" ..
            "\n" ..
            "海难原版同样是 -5（掉 5 点理智），和咖啡一样。本 Mod 默认改成 0。\n" ..
            "要列表里没有的数值可在 modoverrides.lua 里写 roasted_sanity。",
        options =
        {
            { description = "0（不掉理智）",  data = 0,  hover = "本 Mod 默认" },
            { description = "-5（海难原版）", data = -5, hover = "原版数值" },
            { description = "+5",            data = 5,  hover = "" },
        },
        default = 0,
    },
    {
        name = "cook_time",
        label = "咖啡出锅时间（秒）",
        hover =
            "把 4 颗烘焙咖啡豆放进烹饪锅后，要等多少【秒】才出锅。\n" ..
            "默认 10 秒，和原版大多数料理一个档位。\n" ..
            "\n" ..
            "⚠ 这是「秒」，不是游戏内部的倍率 —— 想调成列表里没有的数值，\n" ..
            "在服务器的 modoverrides.lua 里写（支持小数）：\n" ..
            "CoffeePort = { configuration_options = { cook_time = 7.5 } }\n" ..
            "\n" ..
            "注意：配置在服务器启动 / 重载模组时读取，改完要重新载入一次才生效。\n" ..
            "（DST 内部烹饪时间 = 20 秒基准 × 倍率，本 Mod 已经替你换算好了。）",
        options =
        {
            { description = "10 秒（推荐）",   data = 10, hover = "与原版多数料理同档" },
            { description = "3 秒（几乎秒出）", data = 3,  hover = "" },
            { description = "5 秒",            data = 5,  hover = "" },
            { description = "20 秒",           data = 20, hover = "原版慢档" },
            { description = "40 秒（海难原版）", data = 40, hover = "单机海难里咖啡就是这个时长" },
            { description = "60 秒（很慢）",   data = 60, hover = "" },
        },
        default = 10,
    },
    {
        name = "regrow_days",
        label = "咖啡丛再生天数",
        hover = "采摘后重新长出咖啡豆需要的游戏内天数（与原版浆果丛同尺度的基础上）。",
        options =
        {
            { description = "3 天（原版手感）", data = 3, hover = "" },
            { description = "1 天",            data = 1, hover = "" },
            { description = "2 天",            data = 2, hover = "" },
            { description = "6 天",            data = 6, hover = "" },
        },
        default = 3,
    },
    {
        name = "harvest_cycles",
        label = "一株咖啡丛可采次数",
        hover = "连续采摘多少次后枯萎。枯萎后用肥料（含灰烬）施肥即可复活继续产豆。",
        options =
        {
            { description = "4 次（原版手感）", data = 4, hover = "" },
            { description = "2 次",            data = 2, hover = "" },
            { description = "8 次",            data = 8, hover = "" },
            { description = "20 次",           data = 20, hover = "" },
        },
        default = 4,
    },
    {
        name = "wild_deplete",
        label = "野生咖啡丛也会被采枯",
        hover = "开启（海难手感）：野外长出来的咖啡丛采够次数同样会枯萎，需要用灰烬施肥才复活。\n关闭（DST 手感）：野生的咖啡丛永远不枯，只有「铲起再种下」的才需要施肥；此时上面的「可采次数」只对移植过的生效。",
        options =
        {
            { description = "开启（海难手感）", data = true,  hover = "" },
            { description = "关闭（DST 手感）", data = false, hover = "" },
        },
        default = true,
    },
    {
        name = "worldgen",
        label = "新世界自然生成咖啡丛密度",
        hover =
            "新建世界时，在原本长浆果丛的地皮上按比例掺入咖啡丛。\n" ..
            "\n" ..
            "数量是怎么算出来的：世界生成时，每个刷物点先按房间自己的\n" ..
            "distributepercent 掷一次骰子，掷中了再用「按权重抽签」挑一个 prefab\n" ..
            "（权重抽签 = 谁的权重数值大，谁被抽中的概率高）。\n" ..
            "所以这里的数值就是【咖啡丛相对浆果丛的权重】：\n" ..
            "   1.0  → 咖啡丛数量与浆果丛大致相当\n" ..
            "   0.25 → 大约浆果丛的四分之一\n" ..
            "   0.1  → 大约十分之一\n" ..
            "（默认原版世界里浆果丛约百来丛，所以 0.25 大概是二三十丛。）\n" ..
            "\n" ..
            "⚠ 只对【新世界】生效。已经在玩的世界是生成时定死的，改这个不会变。",
        options =
        {
            { description = "稀少（约浆果丛 1/4）",  data = 0.25, hover = "推荐，默认" },
            { description = "关闭（不自然生成）",     data = 0,    hover = "只能靠制作配方获得" },
            { description = "极少（约 1/10）",        data = 0.1,  hover = "" },
            { description = "普通（约 1/2）",         data = 0.5,  hover = "" },
            { description = "与浆果丛同密度",         data = 1.0,  hover = "数量会相当多" },
            { description = "较多（浆果丛的 2 倍）", data = 2.0,  hover = "" },
        },
        default = 0.25,
    },
    {
        name = "quick_pick",
        label = "兼容「快速采集」类 Mod",
        hover =
            "DST 的 pickable 组件自带一个 quickpick 开关：打开后采摘动作会从\n" ..
            "「长动作」变成「短动作」，也就是工坊 Mod「Quick Pick」那一类的效果。\n" ..
            "\n" ..
            "咖啡丛是本 Mod 自定义的 prefab，不在那些 Mod 的硬编码 prefab 名单里\n" ..
            "（名单里只有浆果丛、草、芦苇这些原版植物），所以只能由本 Mod 自己开。\n" ..
            "\n" ..
            "· 自动检测：装了 Quick Pick 才打开，没装就保持原版手感\n" ..
            "· 始终开启：不管装没装，咖啡丛都快速采集\n" ..
            "· 关闭：保持原版的「长动作」采摘",
        options =
        {
            { description = "自动检测", data = "auto", hover = "推荐" },
            { description = "始终开启", data = "on",   hover = "" },
            { description = "关闭",     data = "off",  hover = "原版长动作" },
        },
        default = "auto",
    },
    {
        name = "ash_fertilizer",
        label = "灰烬可作为肥料",
        hover = "海难设定：咖啡树要用灰烬浇灌。开启后灰烬会变成合法肥料，能施肥给枯萎的咖啡丛（也能给别的植物施肥）。",
        options = YES_NO,
        default = true,
    },
    {
        name = "craft_coffeeplant",
        label = "可制作咖啡丛",
        hover = "开启后可在制作栏用「4 浆果 + 3 灰烬」做出咖啡丛（铲起状态），种下即可。这是给老存档准备的保底途径。",
        options = YES_NO,
        default = true,
    },
}
