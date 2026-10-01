--[[----------------------------------------------------------------------------
    coffeep_art.lua —— 美术资源映射表（纯数据模块）

    这个模块只返回一张纯字符串/数字组成的表，不引用任何游戏全局，
    因此可以安全地被 modmain 和 prefab 文件 require。

    素材来源：Shipwrecked(海难) 原版素材，取自开源海难移植项目
    Island Adventures（gitlab.com/IslandAdventures）——
      动画    anim/coffeebush.zip   ← 咖啡丛（bank/build 都叫 coffeebush）
      动画    anim/coffeebeans.zip  ← 咖啡豆（生豆 idle / 熟豆 cooked）
      图标    从 ia_inventoryimages 大图集里抠出的 4 个 64×64 图块
      小地图  从 ia_minimap 大图集里抠出的 coffeebush 图块
    原始大图集 5.3MB + 2.7MB，我们只要 5 个图标，用 _tools/pack_atlas.py
    按 DXT 块无损裁剪成了 16KB + 4KB 的小图集。

    海难咖啡丛的动画名（已从 IA 的 coffeebush.lua 核对）：
      idle / picked / dead / grow / idle_to_dead / dead_to_idle / shake / shake_dead
    果实不是换帧，而是三个 symbol 的显示/隐藏：
      berries（少） / berriesmore（中） / berriesmost（多）
------------------------------------------------------------------------------]]

local ART_MODE = "shipwrecked"   -- "placeholder"（借游戏本体素材占位） | "shipwrecked"（真海难素材）

local DEFS =
{
    ---------------------------------------------------------------------------
    -- 占位方案：借用 DST 本体已有的动画 build 和图标。
    -- 外观不还原海难，但功能完全一致 —— 万一海难素材被删掉，改回这一档即可。
    ---------------------------------------------------------------------------
    placeholder =
    {
        plant_bank    = "berrybush",
        plant_build   = "berrybush",
        plant_minimap = "berrybush.png",

        plant_fruit_symbols = { "berriesmost", "berriesmore", "berries" },

        anim =
        {
            idle         = "idle",
            picked       = "picked",
            grow         = "grow",
            dead         = "dead",
            idle_to_dead = "idle_to_dead",
            dead_to_idle = "dead_to_idle",
            shake        = "shake",
            shake_dead   = "shake_dead",
        },

        -- ⚠ icon 与 image 是【两个不同约定】，写错游戏不报错、图标直接空白：
        --   icon  → 赋给 inventoryitem.imagename。游戏内部 InventoryItem:SetImage()
        --           会自己补 ".tex"（源码：classified.image:set(imagename..".tex")），
        --           所以这里【绝对不能】带后缀，否则变成 "seeds.tex.tex"。
        --   image → 图集里的 region 名，给配方 UI（Recipe.image）用，【必须带】.tex
        --           （源码 recipe.lua：self.image = self.product..".tex"）。
        beans        = { bank = "seeds",    build = "seeds",    anim = "idle", icon = "seeds",    image = "seeds.tex",    atlas = "images/inventoryimages3.xml" },
        beans_cooked = { bank = "charcoal", build = "charcoal", anim = "idle", icon = "charcoal", image = "charcoal.tex", atlas = "images/inventoryimages1.xml" },

        -- 咖啡的物品模型：两档美术方案共用同一套「锅成品模型」，理由见下方
        -- shipwrecked 段那份长注释（简言之：锅上/手上/地上必须是同一个 build+符号）。
        coffee       = { bank = "cook_pot_food", build = "cook_pot_food7", anim = "idle",
                         symbol     = "sweettea",
                         bank_build = "cook_pot_food",
                         icon = "honey",    image = "honey.tex",    atlas = "images/inventoryimages2.xml" },

        dug          = { bank = "berrybush", build = "berrybush", anim = "idle", icon = "cutgrass",
                         image = "cutgrass.tex", atlas = "images/inventoryimages1.xml" },

        own_assets = {},
    },

    ---------------------------------------------------------------------------
    -- 海难素材方案：素材就在 mod 自己的 anim / images 目录里。
    ---------------------------------------------------------------------------
    shipwrecked =
    {
        plant_bank    = "coffeebush",
        plant_build   = "coffeebush",
        plant_minimap = "coffeebush.tex",

        plant_fruit_symbols = { "berriesmost", "berriesmore", "berries" },

        anim =
        {
            idle         = "idle",
            picked       = "picked",
            grow         = "grow",
            dead         = "dead",
            idle_to_dead = "idle_to_dead",
            dead_to_idle = "dead_to_idle",
            shake        = "shake",
            shake_dead   = "shake_dead",
        },

        -- 物品：世界模型（bank/build/anim）+ 图集图标。
        -- 注意 icon（不带 .tex）与 image（带 .tex）的区分，理由见 placeholder 段的注释：
        --   icon  → inventoryitem.imagename，游戏会自动补 ".tex"
        --   image → 图集 region 名 / 配方 UI，必须带 ".tex"
        beans        = { bank = "coffeebeans", build = "coffeebeans", anim = "idle",
                         icon  = "coffeebeans",            image = "coffeebeans.tex",
                         atlas = "images/coffeeport_items.xml" },
        beans_cooked = { bank = "coffeebeans", build = "coffeebeans", anim = "cooked",
                         icon  = "coffeebeans_cooked",     image = "coffeebeans_cooked.tex",
                         atlas = "images/coffeeport_items.xml" },

        ---------------------------------------------------------------------------
        -- 咖啡：模型必须与「锅里出锅时那杯」用同一套 build + 符号
        ---------------------------------------------------------------------------
        --
        -- 背景：海难原版咖啡是锅料理，成品用的是海难专属的碗（cook_pot_food_sw），
        -- 那个 build 连同几十道菜的 symbol 一起好几 MB。为了不给 mod 增重，
        -- 这里改用【DST 自带】的锅成品动画，借原版「舒缓茶 sweettea」的茶杯符号。
        --
        -- 为什么必须连 bank 一起借（bank 和 build 拆成两个字段）：
        --     anim/cook_pot_food.zip      内含 anim.bin + build.bin
        --                                 → 提供 bank "cook_pot_food"（所有动画都在这）
        --     anim/cook_pot_food7.zip     只有 build.bin + atlas-0.tex，【没有 anim.bin】
        --                                 → 只是个「符号仓库」，提供 sweettea 茶杯符号
        -- 所以原版 preparedfoods 工厂才写成 SetBank("cook_pot_food") +
        -- SetBuild("cook_pot_food7") + OverrideSymbol("swap_food", "cook_pot_food7", "sweettea")
        -- （scripts/prefabs/preparedfoods.lua:61-66），本 mod 照着抄即可。
        -- 两个 zip 都要在 Assets 里声明，见 modmain.lua 的 AddAnim 两行。
        --
        -- ⚠ 上一版的坑：这里原来借的是蜂蜜罐（bank/build 都是 honey），
        --   而锅里出锅时借的是茶杯 → 同一杯咖啡，锅里是杯子、手上是蜂蜜罐、图标又是
        --   海难咖啡杯，三处各不相同的「怪怪的」来源。现在统一成茶杯。
        --   （物品栏图标仍用海难原版咖啡杯 coffee.tex，那是 2D 图，与模型无关。）
        --
        -- 想换外观：改 build / symbol / bank_build 三个字段，且必须配套改 ——
        -- 符号名 = 那道原版菜的名字，build 就在 preparedfoods.lua 该菜目的 overridebuild 字段。
        coffee       = { bank = "cook_pot_food", build = "cook_pot_food7", anim = "idle",
                         symbol     = "sweettea",          -- 换到 swap_food 槽里的符号名
                         bank_build = "cook_pot_food",     -- 提供 bank/动画的那个 zip（需一并声明 Asset）
                         icon  = "coffee",                 image = "coffee.tex",
                         atlas = "images/coffeeport_items.xml" },

        -- 铲起的咖啡丛：世界模型直接复用咖啡丛 build 的「枯死」动画
        -- （Island Adventures 的 plantables 工厂就是这么处理 dug_ 的）。
        -- 图标 region 名随 prefab 名走（dug_coffeeplant.tex）——图集是我们自己打的，
        -- 名字与 prefab 对齐后，物品栏靠默认回退（prefab名..".tex"）就能命中，
        -- 少一处需要手动同步的地方。
        dug          = { bank = "coffeebush", build = "coffeebush", anim = "dead",
                         icon  = "dug_coffeeplant",        image = "dug_coffeeplant.tex",
                         atlas = "images/coffeeport_items.xml" },

        -- 用 AddMinimapAtlas 注册的小地图图集（不填则沿用占位/原版图标）
        minimap_atlas = "images/minimap/coffeeport_minimap.xml",

        -- {Asset 类型, 路径}
        own_assets =
        {
            { "IMAGE", "images/coffeeport_items.tex" },
            { "ATLAS", "images/coffeeport_items.xml" },

            { "IMAGE", "images/minimap/coffeeport_minimap.tex" },
            { "ATLAS", "images/minimap/coffeeport_minimap.xml" },
        },
    },
}

local art = DEFS[ART_MODE]
if art == nil then
    -- 配置写错时的兜底，避免整个 mod 直接崩掉
    ART_MODE = "placeholder"
    art = DEFS.placeholder
end
art.mode = ART_MODE

return { art = art, mode = ART_MODE }
