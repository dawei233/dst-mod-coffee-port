--[[----------------------------------------------------------------------------
    CoffeePort / 海难咖啡移植 —— modmain

    做四件事：
      1. 读配置，并把美术表 + 数值表挂到 GLOBAL.COFFEEP 上给 prefab 文件用
      2. 声明资源与 prefab
      3. 注册咖啡豆的烹饪锅食材属性、咖啡的锅配方、咖啡丛的制作配方
      4. 世界生成时把咖啡丛撒进浆果丛的地皮；可选把灰烬变成肥料

    ⚠ 重要坑位：DST 的 modmain 跑在一个【白名单环境】里（scripts/mods.lua 的
      CreateEnvironment），里面只有：
        pairs / ipairs / print / math / table / type / string / tostring / require /
        Class / TUNING / LEVELCATEGORY / GROUND / WORLD_TILES / LOCKS / KEYS /
        LEVELTYPE / GLOBAL / modname / MODROOT
      外加 modutil 注入的 Asset / Ingredient / Prefab / AddRecipe2 /
      AddCookerRecipe / AddIngredientValues / AddPrefabPostInit / AddRoomPreInit /
      GetModConfigData 等 Add* 系列。

      tonumber、assert、pcall、select、error、setmetatable、
      FOODTYPE、TECH、STRINGS、TheWorld、ACTIONS、LOC、CreateEntity
      —— 这些【全都不在】modmain 的直接作用域里，直接写会报
      "attempt to call global 'xxx' (a nil value)"。
      所以下面统一走 GLOBAL.（prefab 文件不受影响，它们跑在完整游戏环境里）。
------------------------------------------------------------------------------]]

local ART_PACK = require("coffeep_art")

local ART = ART_PACK.art

-------------------------------------------------------------------------------
-- 白名单环境下取标准库 / 游戏全局
-------------------------------------------------------------------------------

local G        = GLOBAL

local tonumber = G.tonumber
local tostring = G.tostring
local type     = G.type
local pcall    = G.pcall
local math     = G.math
local string   = G.string
local table    = G.table
local ipairs   = G.ipairs
local pairs    = G.pairs

local TUNING   = G.TUNING
local FOODTYPE = G.FOODTYPE
local TECH     = G.TECH
local STRINGS  = G.STRINGS

-------------------------------------------------------------------------------
-- 读配置
-------------------------------------------------------------------------------

local function OPT(name, default)
    local v = GetModConfigData(name)
    if v == nil then
        return default
    end
    return v
end

local function NUM(name, default)
    return tonumber(OPT(name, default)) or default
end

-------------------------------------------------------------------------------
-- 「快速采集」兼容开关
--
--   DST 的 Pickable 组件自带一个 quickpick 开关（源码 components/pickable.lua）：
--   它被注册成属性 setter，内部只做一件事 —— AddTag("quickpick")。
--   而 wilson stategraph 的 PICK 分支据此决定动画：
--
--       return (action.target.components.pickable.jostlepick and "dojostleaction")
--           or (action.target.components.pickable.quickpick and "doshortaction")   -- 短动作
--           or (inst:HasTag("fastpicker") and "doshortaction")
--           or "dolongaction"                                                      -- 长动作
--
--   工坊 Mod「Quick Pick」(workshop-501385076) 做的事就是维护一份【硬编码】
--   prefab 名单，逐个把 quickpick 打开。咖啡丛是我们自定义的 prefab，
--   永远不可能出现在别人的名单里，所以只能由本 Mod 自己打开。
--
--   ⚠ 客户端 stategraph 读的是 tag（HasAnyTag("quickpick")），不是组件字段
--     —— 组件字段不跨网络，tag 会。所以服务端设一次就够了，
--     不需要 netvar / SetPristine / AddNetwork 之类的额外处理。
-------------------------------------------------------------------------------

local function QuickPickEnabled()
    local mode = OPT("quick_pick", "auto")

    if mode == true or mode == "on" then
        return true
    end
    if mode == false or mode == "off" then
        return false
    end

    -- "auto"（或任何没见过的值）：看看玩家有没有装 Quick Pick
    --
    -- ⚠ 索引 KnownModIndex 必须用 pcall 包一层：
    --   正式游戏里它一定存在（modmain 的 GLOBAL 就是 _G），但
    --   modmain 环境的 GLOBAL 是【严格模式】的 —— 读一个还不存在的全局是
    --   【抛异常】而不是返回 nil。所以直接写 G.KnownModIndex，
    --   万一在某个极早期/裁剪过的环境里它还没建好，会把整个 mod 的加载打断。
    --   宁可检测不到（退回 false，玩家可以手动改成「始终开启」），也不能崩。
    local ok_idx, idx = pcall(function() return G.KnownModIndex end)
    if not ok_idx or idx == nil or idx.IsModEnabled == nil then
        return false
    end

    local ok, enabled = pcall(idx.IsModEnabled, idx, "workshop-501385076")
    return ok and enabled == true
end

local CFG =
{
    speed_mult        = NUM("coffee_speed", 1.8333),
    coffee_time       = NUM("coffee_duration", 240),
    decay             = OPT("coffee_decay", true) and true or false,
    -- 理智值：海难原版【咖啡】和【烘焙咖啡豆】都是 -5（掉理智），这是官方设定
    -- （官方说法是咖啡因过量带来的心悸与焦虑），不是数值抄错。DST 里理智比单机
    -- 海难难攒，所以默认给 0；想还原原版手感在配置菜单里把这两项调回 -5。
    --
    -- ⚠ 两处都要读同一份 CFG，别只改一处：
    --     真正的效果  → prefab 里的 edible.sanityvalue（stewer 出锅走 SpawnPrefab，
    --                    不会把食谱表的数值刷到成品上），见 coffee.lua / coffeebeans.lua
    --     图鉴/食谱卡 → 下面 coffee_recipe 的 sanity 字段
    coffee_sanity     = NUM("coffee_sanity", 0),
    roasted_sanity    = NUM("roasted_sanity", 0),

    -- 甜味剂口径（modinfo 的 sweetener_mode）：
    --   "honey"（默认）= 只认蜂蜜，跟烹饪书里画出来的配方一致
    --   "any"          = 单机海难原版：蜂蜜 / 蜂巢（蜜脾）/ 蜂王浆 都算甜味度
    -- 见下方 coffee_recipe.test 的说明。
    sweetener_any     = (OPT("sweetener_mode", "honey") == "any"),
    roasted_time      = NUM("roasted_speed_time", 30),
    harvest_cycles    = math.max(1, math.floor(NUM("harvest_cycles", 4))),
    -- 注意：这个值实际由 modworldgenmain.lua 自己读（世界生成那一轮不加载 modmain），
    -- 这里留一份只是为了日志/调试时能对照，改默认值务必两边一起改。
    worldgen          = math.max(0, NUM("worldgen", 0.25)),
    quick_pick        = QuickPickEnabled(),
    wild_deplete      = OPT("wild_deplete", true) and true or false,
    ash_fertilizer    = OPT("ash_fertilizer", true) and true or false,
    craft_coffeeplant = OPT("craft_coffeeplant", true) and true or false,
}

CFG.regrow_days     = NUM("regrow_days", 3)
CFG.regrow_time     = TUNING.TOTAL_DAY_TIME * CFG.regrow_days
CFG.regrow_increase = CFG.regrow_time * 0.25
CFG.ash_withered_cycles = 1

-------------------------------------------------------------------------------
-- 出锅时间：配置菜单给玩家填的是【秒】，而食谱要的是【倍率】
-------------------------------------------------------------------------------
--
-- components/stewer.lua:167 的真实耗时 = TUNING.BASE_COOK_TIME × 食谱的 cooktime
-- 而 TUNING.BASE_COOK_TIME 由 tuning.lua 的 night_time × .3333 推出，标准值 20 秒。
--
--   ⚠ 也就是说 cooktime = 2 不是「2 秒」，真机上是 **40 秒**。
--     上一版就是把单机海难的 cooktime = 2 直接抄过来，玩家反馈「做一个要等好久」。
--
-- 配置菜单里让玩家填「秒」比填「倍率」直观得多，所以换算只在这一处做一次：
--
--     食谱 cooktime = 想要的秒数 ÷ BASE_COOK_TIME
--         填 10 秒 → 0.5        填 40 秒 → 2        填 3 秒 → 0.15
--
-- 食谱那边直接写 CFG.cooktime，【绝不要】在别处再乘再除一次。
--
-- 夹取到 [1, 300] 秒：0 / 负数会让 DoTaskInTime 立即触发（不崩，但毫无意义）；
-- 上限纯粹是防手滑把「毫秒」当「秒」填进来。玩家在 modoverrides.lua 里
-- 可以写任意小数秒，例如 cook_time = 7.5。
local BASE_COOK_TIME = TUNING.BASE_COOK_TIME
if type(BASE_COOK_TIME) ~= "number" or BASE_COOK_TIME <= 0 then
    -- 兜底：某个精简环境 / 别的 Mod 改坏了这个值时，用 tuning.lua 的标准值
    BASE_COOK_TIME = 20
end

CFG.base_cook_time = BASE_COOK_TIME
CFG.cook_seconds  = math.max(1, math.min(300, NUM("cook_time", 10)))
CFG.cooktime      = CFG.cook_seconds / BASE_COOK_TIME

-- prefab 文件跑在【严格模式】的游戏环境里：没有 GLOBAL，读任何未声明的全局都会直接报
-- "variable 'X' is not declared"，连自定义全局也不行。
-- 所以 modmain ↔ prefab 之间的共享数据挂在 TUNING 下（TUNING 两边都可访问，且是可变表）。
TUNING.COFFEEP = { art = ART, cfg = CFG }

-------------------------------------------------------------------------------
-- 资源 & prefab
-------------------------------------------------------------------------------

PrefabFiles =
{
    "coffeebeans",
    "coffee",
    "coffeeplant",
}

Assets = {}

local function AddAsset(kind, path)
    Assets[#Assets + 1] = Asset(kind, path)
end

-- 动画 build 声明：同一个 build 可能被多个物品共用（比如生豆/熟豆同属 coffeebeans
-- 这个 build，只是播不同动画），所以先去重再声明。
local seen_anim = {}
local function AddAnim(build)
    if build ~= nil and not seen_anim[build] then
        seen_anim[build] = true
        AddAsset("ANIM", "anim/"..build..".zip")
    end
end
AddAnim(ART.plant_build)
AddAnim(ART.beans.build)
AddAnim(ART.beans_cooked.build)

-- 咖啡的物品模型借用了原版「锅成品」的两段素材，两个都要声明：
--   cook_pot_food  → 只有它含 anim.bin，提供 bank 与所有动画
--   cook_pot_food7 → 只有 build.bin，提供借来当咖啡杯的「舒缓茶」符号
-- 与 scripts/prefabs/coffee.lua 里 prefab 自己的 assets 表重复声明也无妨
-- （资源管理器按路径去重），mod 级声明只是让它在加载阶段就备好。
AddAnim(ART.coffee.bank_build)
AddAnim(ART.coffee.build)
if ART.dug ~= nil then
    AddAnim(ART.dug.build)
end

-- mod 自带的美术资源（海难图集等）
for _, kv in ipairs(ART.own_assets or {}) do
    AddAsset(kv[1], kv[2])
end

-- 小地图图标：MiniMapEntity:SetIcon("coffeebush.tex") 只在【已注册的小地图图集】
-- 里查找图标，光声明 Asset 是不够的，必须走 AddMinimapAtlas（modutil 注入的接口）。
if ART.minimap_atlas ~= nil then
    AddMinimapAtlas(ART.minimap_atlas)
end

-------------------------------------------------------------------------------
-- 给 mod 自己的图集做「图标登记」
--
-- 配方 UI、烹饪锅配方书、材料格这些东西找图标走的是
-- GetInventoryItemAtlas(imagename)（simutil.lua），它【只会】在
-- images/inventoryimages1~4.xml 这四张原版图集里翻，
-- mod 的图集必须先用 RegisterInventoryItemAtlas(atlas, imagename) 登记进去。
--
-- 不登记的后果和图标名写错一样：图标空白、【日志里一个字都不报】。
-- 物品栏格子本身走 inventoryitem.atlasname 不经过这里，但锅里那杯咖啡是烹饪锅
-- 产物、咖啡豆又是它的材料，配方书一定会查这张表，所以必须登记。
--
-- key 的形态两种都登记：Recipe/Ingredient 传进来的是带 ".tex" 的
-- （recipe.lua：self.image = self.product..".tex"），而 modutil 的注释又建议
-- 用 prefab 名，索性两种都写一遍，成本为零。
-------------------------------------------------------------------------------
local function RegisterIcon(entry)
    if entry == nil or entry.atlas == nil then
        return
    end
    for _, key in ipairs({ entry.icon, entry.image }) do
        if key ~= nil then
            RegisterInventoryItemAtlas(entry.atlas, key)
        end
    end
end

RegisterIcon(ART.beans)
RegisterIcon(ART.beans_cooked)
RegisterIcon(ART.coffee)
RegisterIcon(ART.dug)

-------------------------------------------------------------------------------
-- 文案（DST 没有咖啡的官方翻译，这里自己补；跟随游戏语言）
-------------------------------------------------------------------------------

-- 取当前语言代码："zh"（简中）/ "zht"（繁中）/ "zhr"（简体·国服 Rail）/ "en" …
--
-- ⚠⚠ 这里踩过一个真机坑，千万别改回直觉写法 ⚠⚠
--
--   直觉写法是 `LOC.GetLanguage() == "zh"`，但它【永远是 false】——
--   因为 GetLanguage() 返回的【不是】语言代码字符串，而是 constants.lua 里
--   LANGUAGE 枚举的【数字】：
--
--       ENGLISH = 0 … KOREAN = 19 … CHINESE_T = 21, CHINESE_S = 22, CHINESE_S_RAIL = 23
--
--   （源码 scripts/languages/loc.lua:91    GetLanguage() → CurrentLocale.id）
--
--   数字 22 和字符串 "zh" 比较恒为 false，于是【简体中文玩家也一直走英文分支】，
--   物品名全是 "Coffee Beans" / "Roasted Coffee Beans"。这个 bug 很隐蔽：
--   它不报错、不崩溃，只是静静地显示英文，连日志都没有一行提示。
--
--   正确链路要两步（loc.lua:82 → 68）：
--       LOC.GetLocaleCode( LOC.GetLanguage() )
--           →  LOC.GetLocale(id).code  →  "zh"
--
--   下面再留一层「直接比枚举」的兜底，防止某个精简环境里没有 GetLocaleCode。
local function CurrentLanguageCode()
    local loc = G.LOC
    if loc == nil then
        return nil
    end

    -- ① 官方链路：枚举 id → 语言代码
    if loc.GetLocaleCode ~= nil and loc.GetLanguage ~= nil then
        local ok, code = pcall(function()
            return loc.GetLocaleCode(loc.GetLanguage())
        end)
        if ok and type(code) == "string" then
            return code
        end
    end

    -- ② 兜底：自己按 LANGUAGE 枚举判断
    --    （GLOBAL 是严格模式，读 G.LANGUAGE 也要 pcall —— 见文件开头的环境说明）
    local ok_lang, LANGUAGE = pcall(function() return G.LANGUAGE end)
    local ok_id, id = pcall(function() return loc.GetLanguage() end)
    if ok_lang and ok_id and LANGUAGE ~= nil and id ~= nil then
        if id == LANGUAGE.CHINESE_S or id == LANGUAGE.CHINESE_T or id == LANGUAGE.CHINESE_S_RAIL then
            return "zh"
        end
        if id == LANGUAGE.ENGLISH or id == LANGUAGE.ENGLISH_UK then
            return "en"
        end
    end

    return nil
end

local LANG_CODE = CurrentLanguageCode()

-- 中文的三种 code：zh(简) / zht(繁) / zhr(简体·Rail)
-- 检测不出来时按中文处理：本 Mod 面向中文玩家，宁可显示中文，也不要莫名其妙显英文
local IS_ZH = (LANG_CODE == nil) or LANG_CODE == "zh" or LANG_CODE == "zht" or LANG_CODE == "zhr"

local TEXT = IS_ZH and
{
    COFFEEPLANT         = "咖啡丛",
    DUG_COFFEEPLANT     = "咖啡丛（铲起）",
    COFFEEBEANS         = "咖啡豆",
    COFFEEBEANS_COOKED  = "烘焙咖啡豆",
    COFFEE              = "咖啡",

    DESCRIPTION         = "一小丛咖啡树，结着小小的豆子。",
    DESC_DUG            = "连根挖起的咖啡树，还能再种回去。种下后浇点灰烬就会重新长豆。",
    DESC_BEANS          = "生的，不能直接吃。得放到火上烤一烤。",
    DESC_ROASTED        = "烤过的豆子，闻一口就精神，腿脚也轻快了。",
    DESC_COFFEE         = "又苦又香。喝下去整个人都轻了。",
}
or
{
    COFFEEPLANT         = "Coffee Plant",
    DUG_COFFEEPLANT     = "Coffee Plant (Dug)",
    COFFEEBEANS         = "Coffee Beans",
    COFFEEBEANS_COOKED  = "Roasted Coffee Beans",
    COFFEE              = "Coffee",

    DESCRIPTION         = "A small coffee shrub dotted with tiny beans.",
    DESC_DUG            = "Dug up by the roots. Replant it and feed it some ash.",
    DESC_BEANS          = "Raw. Not edible as is - it needs to be roasted on a fire.",
    DESC_ROASTED        = "Roasted beans. Just the smell perks you up.",
    DESC_COFFEE         = "Bitter and fragrant. It really puts a spring in your step.",
}

STRINGS.NAMES.COFFEEPLANT        = TEXT.COFFEEPLANT
STRINGS.NAMES.DUG_COFFEEPLANT    = TEXT.DUG_COFFEEPLANT
STRINGS.NAMES.COFFEEBEANS        = TEXT.COFFEEBEANS
STRINGS.NAMES.COFFEEBEANS_COOKED = TEXT.COFFEEBEANS_COOKED
STRINGS.NAMES.COFFEE             = TEXT.COFFEE

STRINGS.RECIPE_DESC = STRINGS.RECIPE_DESC or {}
STRINGS.RECIPE_DESC.DUG_COFFEEPLANT = TEXT.DESC_DUG

if STRINGS.CHARACTERS ~= nil and STRINGS.CHARACTERS.GENERIC ~= nil then
    STRINGS.CHARACTERS.GENERIC.DESCRIBE = STRINGS.CHARACTERS.GENERIC.DESCRIBE or {}
    local D = STRINGS.CHARACTERS.GENERIC.DESCRIBE
    D.COFFEEPLANT        = TEXT.DESCRIPTION
    D.DUG_COFFEEPLANT    = TEXT.DESC_DUG
    D.COFFEEBEANS        = TEXT.DESC_BEANS
    D.COFFEEBEANS_COOKED = TEXT.DESC_ROASTED
    D.COFFEE             = TEXT.DESC_COFFEE
end

-------------------------------------------------------------------------------
-- 烹饪：咖啡豆作为锅食材；咖啡作为锅配方
-------------------------------------------------------------------------------

-- ⚠⚠ 锅食材必须登记在【熟豆】头上，不要登记生豆 ⚠⚠
--
--   原来的写法是海难原版那一套：
--       AddIngredientValues({ "coffeebeans" }, { fruit = 0.5 }, true)
--   它一次往 cooking.ingredients 写了两个键 —— coffeebeans（fruit 0.5）和
--   coffeebeans_cooked（fruit 0.5 + precook）。数值没错，但会让
--   【馨食记 / CookDiary】把「烘焙咖啡豆」当成「普通咖啡豆」来算：
--
--     diary_hook.lua:119 ParseNumber —— 扫描完玩家背包后做数量归并：
--         某食材带 _cooked 后缀、且【它的原始名也是锅食材】时，
--         就把数量并进原始名（作者的理由：大部分烤制食材和原始食材效果一致）。
--     因为 coffeebeans 也被登记成了锅食材 → coffeebeans_cooked 被并进 coffeebeans，
--     客户端 diary_ingTable 里【从此永远没有 coffeebeans_cooked 这个键】。
--     而本 mod 的食谱 test() 恰恰只认 names.coffeebeans_cooked（见下方 coffee_recipe），
--     于是出现两个症状：
--       · 今天吃些啥 / 配方快捷按钮：GetNumber("coffeebeans_cooked") 恒为 0，
--         算不出「烘焙咖啡豆」的做法，菜单里只剩背包里那份「普通咖啡豆」；
--       · 帮我做大餐：食材列表里只有普通咖啡豆，没有烘焙咖啡豆。
--
--   修法：锅食材只登记熟豆，生豆不登记。
--     这样 IsCookingIngredient("coffeebeans") 为 false，CookDiary 会走它自己写的
--     「若原始食材不可入锅，则返回烤制食材数量」那条分支 —— 烘焙咖啡豆
--     从此是一个独立的、能被识别和取用的锅食材。
--
--   副作用：生豆不再贡献 0.5 果度（锅照样收得下它，只是当成填充物）。
--     海难原版里生豆本来也煮不出咖啡，配方要求的就是熟豆，所以这个副作用反而是对的。
AddIngredientValues({ "coffeebeans_cooked" }, { fruit = 0.5, precook = 1 })

-- 咖啡的锅配方。单机《海难》原版写法：
--
--     4 份烘焙咖啡豆，或
--     3 份烘焙咖啡豆 + 1 个（乳制品 / 甜味剂 / 第 4 颗烘焙咖啡豆）
--
-- ⚠ 关于「甜味剂」这一格，本 Mod 【故意比原版紧一点】，默认只认蜂蜜：
--
--   原版判定是 tags.sweetener（scripts/cooking.lua:97-98）——
--       AddIngredientValues({"honey", "honeycomb"}, {sweetener = 1}, true)
--       AddIngredientValues({"royal_jelly"},          {sweetener = 3}, true)
--   也就是说 蜂蜜 / 蜜脾（蜂巢）/ 蜂王浆 三样都能煮出咖啡，
--   中文百科里那句「甜味剂包括蜂蜜和蜂巢（是的，蜂巢可以入锅）」说的就是它。
--
--   但 DST 的烹饪书（以及所有照着菜谱卡画 UI 的 Mod）只会把这一格画成【蜂蜜】——
--   玩家照着书去准备，锅里放蜜脾也出咖啡，就成了「显示与实际不一致」。
--   所以本 Mod 默认收紧成 names.honey（只认蜂蜜），让书里的配方和锅里的判定对齐；
--   想要完全复刻单机海难手感的，把 modinfo 的 sweetener_mode 调成「任意甜味剂」即可
--   （那就会退回上面那套 tags.sweetener 判定）。
--
--   乳制品（黄油 / 羊奶 / 蛋清）不在收紧范围内：它跟甜味剂在原版就是并列的两类
--   （「甜味剂【或】乳制品」），书里的「奶度>0」也一直明示着，所以两个口径下都放行。
--
-- ⚠⚠ weight 字段【不是可选的】，不写就是一颗定时炸弹 ⚠⚠
--
--   scripts/cooking.lua 的 CalculateRecipe（268-288 行）在最后一步挑料理时按 weight
--   加权抽签，而 Klei 只在这三行里的前两行写了兜底：
--
--       272  table.sort( candidates, function(a,b) return (a.weight or 1) > (b.weight or 1) end )
--       275  total = total + (v.weight or 1)
--       281  val = val - candidates[idx].weight          ← 唯独这一行没写 (x or 1)
--
--   后果：锅里只要出现一个没有 weight 的候选食谱，272/275 会把它当成 1 混进 total，
--   走到 281 行却在 nil 上做减法，直接抛
--       attempt to perform arithmetic on field 'weight' (a nil value)
--   并且这是【服务端 Lua 崩】，整局服务器一起挂。
--
--   为什么原版食谱都没事？因为 preparedfoods.lua 结尾（1098-1104 行）有一个
--   兜底循环专门给官方食谱补了 weight / priority：
--
--       for k, v in pairs(foods) do v.name = k; v.weight = v.weight or 1; ... end
--
--   而【mod 通过 AddCookerRecipe 注册的食谱完全不走那个循环】，官方文档也从没提过
--   weight 是必填 —— 于是「忘写 weight」成了 mod 圈最经典的崩服陷阱之一。
--   本 Mod 之前就漏了这个字段：往锅里放 4 颗烘焙咖啡豆一开火即崩。
local coffee_recipe =
{
    name = "coffee",
    weight = 1,          -- 见上方说明：必填。漏了会在煮锅那一刻崩掉整局服务器
    test = function(cooker, names, tags)
        local roasted = names.coffeebeans_cooked or 0
        if roasted >= 4 then
            return true          -- 4 颗烘焙咖啡豆：第四颗自己就是那颗豆，不要甜味剂
        end

        -- 第四格（甜味剂）的口径由 sweetener_mode 决定，理由见上方长注释。
        --   names.honey      → 只认【蜂蜜】这一件物品（跟烹饪书里画的一致）
        --   tags.sweetener   → 海难原版：蜂蜜/蜂巢/蜂王浆都带这个标签
        -- ⚠ 生豆算不算「甜味剂」？不算 —— 生豆没有 sweetener 标签，
        --   而且生豆早就从锅食材表里摘掉了（见上方 AddIngredientValues 那一段）。
        local sweetener_ok
        if CFG.sweetener_any then
            sweetener_ok = (tags.sweetener ~= nil)
        else
            sweetener_ok = (names.honey ~= nil)
        end

        -- 乳制品（黄油 / 羊奶 / 蛋清）两种口径都放行：它跟甜味剂是并列的两类，
        -- 海难原版就是「甜味剂【或】乳制品」，书里的「奶度>0」也一直显示着。
        return roasted >= 3 and (sweetener_ok or tags.dairy ~= nil)
    end,
    priority = 30,
    foodtype = FOODTYPE.GOODIES,
    health = 3,          -- 海难原版 +3 生命
    hunger = 9.375,      -- 海难原版 +9.375 饱食
    sanity = CFG.coffee_sanity,   -- 海难原版 -5 理智；现由配置项 coffee_sanity 决定（默认 0）
    perishtime = TUNING.PERISH_MED,   -- 10 天

    -- ⚠⚠ cooktime 是【倍率】，不是秒数！ ⚠⚠
    --
    --   components/stewer.lua:146-172 的真实公式：
    --
    --       local cooktime = 1
    --       self.product, cooktime = cooking.CalculateRecipe(cooker, names)
    --       ...
    --       cooktime = TUNING.BASE_COOK_TIME * cooktime * self.cooktimemult
    --       self.task = self.inst:DoTaskInTime(cooktime, dostew, self)
    --
    --   而 cooking.lua:283 是 `return candidates[idx].name, candidates[idx].cooktime or 1`
    --   —— 食谱不写这个字段就默认 1（= 20 秒）。
    --
    --   TUNING.BASE_COOK_TIME ≈ 20 秒（tuning.lua：BASE_COOK_TIME = night_time * .3333，
    --   而 night_time = seg_time(30) × night_segs(2) = 60）。
    --
    --   所以写 2 不是「2 秒」，而是 **40 秒**。原版食谱绝大多数是 .5（10 秒）/ 1（20 秒），
    --   只有极少数硬菜才写 2。海难原版咖啡确实写 cooktime = 2，但那是【单机】的时间体系。
    --
    --   这里【不要写常数】—— 用 CFG.cooktime，它由配置项 cook_time（单位：秒）
    --   除以 BASE_COOK_TIME 换算得到，见上方「出锅时间」一节。默认 10 秒 → 0.5。
    cooktime = CFG.cooktime,
    tags = { "caffeine" },

    -- ⚠ 这个 floater 字段对烹饪【不生效】—— 只被原版 preparedfoods 的 prefab 工厂读取，
    --   而本 mod 的 coffee 是自己的 prefab 文件，真正的漂浮参数写在
    --   scripts/prefabs/coffee.lua（MakeInventoryFloatable(inst, "med", 0.05, 0.65)）。
    --   这里保持同值纯粹是为了对照，别指望改它能看出效果。
    floater = { "med", 0.05, 0.65 },

    ---------------------------------------------------------------------------
    -- ★ 锅上那杯咖啡的外观：必须借原版菜肴的「动画符号」，否则锅是空的
    ---------------------------------------------------------------------------
    --
    -- 现象：咖啡出锅时，锅上什么都不显示（不是空白方块，是压根没画东西），
    --       客户端日志里刷 "Could not find anim build coffee"。
    --
    -- 原因链（scripts/prefabs/cookpot.lua:135 与 :105）：
    --
    --     local function ShowProduct(inst)
    --         local product = inst.components.stewer.product
    --         SetProductSymbol(inst, product, IsModCookingProduct(inst.prefab, product) and product or nil)
    --     end
    --
    --     local build  = (recipe ~= nil and recipe.overridebuild) or overridebuild or "cook_pot_food"
    --     local symbol = (recipe ~= nil and recipe.overridesymbolname) or product
    --     inst.AnimState:OverrideSymbol("swap_cooked", build, symbol)
    --
    -- 而 cooking.lua 的 IsModCookingProduct 对【所有 mod 通过 AddCookerRecipe 注册的菜】
    -- 返回 true（它翻 ModManager 的 cookerrecipes 名单）→ 第三参数 = 成品名 "coffee"
    -- → build 变成 "coffee" → 游戏找不到 anim/coffee.zip → 静默失败。
    --
    -- ⚠ 也就是说：mod 菜肴要么自带 anim/<成品名>.zip（且里面有个同名 symbol），
    --   要么就得像下面这样显式指定 build + symbol。原版菜能正常显示，是因为它们
    --   的 symbol 就画在 cook_pot_food*.zip 里（见 preparedfoods.lua 每个菜目的
    --   overridebuild 字段）。
    --
    -- 这里借原版「舒缓茶 sweettea」的茶杯符号（preparedfoods.lua:883，
    -- overridebuild = "cook_pot_food7"，symbol 名 = 菜名），零新增素材。
    -- cook_pot_food7.zip 只是符号仓库（只有 build.bin 没有 anim.bin），
    -- bank 与动画仍来自 cook_pot_food.zip —— 两个 zip 都由下面 AddAnim 声明。
    --
    -- ⚠⚠ 这两行必须与 scripts/coffeep_art.lua 里 coffee 条目的
    --     build / symbol 保持完全一致 ⚠⚠
    --     锅上（swap_cooked 槽）与手上（swap_food 槽）是同一套 build+符号，
    --     改了一边不改另一边，就会出现「锅里是茶杯、手上却是别的形状」。
    --     权威定义在 coffeep_art.lua（物品模型也读那张表），这里只是锅那一半。
    --
    -- 想换个外观，直接改这两行【以及美术表对应字段】即可（build 与 symbol 必须配套）：
    --     bananajuice          → cook_pot_food10
    --     frozenbananadaiquiri → cook_pot_food9
    --     bunnystew            → cook_pot_food11
    --     lobsterbisque        → cook_pot_food3
    --     不写 overridebuild    → 默认 build 是 cook_pot_food（湿哒哒的 broth 类菜都在这）
    overridebuild = "cook_pot_food7",
    overridesymbolname = "sweettea",

    card_def = { ingredients = { { "coffeebeans_cooked", 3 }, { "honey", 1 } } },
}

AddCookerRecipe("cookpot", coffee_recipe)
AddCookerRecipe("portablecookpot", coffee_recipe)

-------------------------------------------------------------------------------
-- 【兜底】煮锅「食谱缺 weight」崩服保护
--
-- 原理见上方 coffee_recipe 的注释：CalculateRecipe 最后一行 val - candidates[idx].weight
-- 没有兜底，谁缺 weight 谁崩，而且是崩服务端。
--
-- 本 Mod 自己已经写对了，但玩家通常同时开着一堆别的 Mod —— 只要其中【任何一个】
-- 作者忘了写 weight，玩家往锅里放东西的那一刻服务器就会崩。既然补这个值的成本
-- 趋近于零、风险也趋近于零（补的就是原版自己会用的默认值 1），不如顺手兜住。
--
-- 两层：
--   ① 加载时把 cooking.recipes 里【已经注册】的食谱全部补齐（能覆盖比我们早加载的 Mod）
--   ② 再把 cooking.CalculateRecipe 包一层，开火前顺手补齐（能覆盖之后才加载的 Mod）
--
--   ② 之所以能生效：components/stewer.lua 第 147 行是以
--       cooking.CalculateRecipe(self.inst.prefab, self.ingredient_prefabs)
--   的形式调用的（走表字段，不是文件顶部 local 化的引用），所以替换字段是真生效的。
--
-- 全程 pcall 保护：拿不到 cooking 模块（或它内部结构变了）就安静跳过，
-- 绝不因为这段"保护代码"本身而影响本 Mod 的加载。
-------------------------------------------------------------------------------

local function PatchCookerRecipeWeights()
    local ok, cooking = pcall(require, "cooking")
    if not ok or type(cooking) ~= "table" or type(cooking.recipes) ~= "table" then
        return false
    end

    -- 把一张 cooker → { 名字 → 食谱 } 表里所有食谱的 weight 补齐
    local function fill(recipes)
        if type(recipes) ~= "table" then
            return
        end
        for _, recipe in pairs(recipes) do
            if type(recipe) == "table" and recipe.weight == nil then
                recipe.weight = 1
            end
        end
    end

    -- ① 已经注册进来的
    local ok1 = pcall(function()
        for _, recipes in pairs(cooking.recipes) do
            fill(recipes)
        end
    end)

    -- ② 之后才注册的
    local ok2 = pcall(function()
        local orig = cooking.CalculateRecipe
        if type(orig) ~= "function" then
            return
        end
        cooking.CalculateRecipe = function(cooker, names)
            -- 一个 cooker 顶多几十条食谱，遍历成本可以忽略
            pcall(fill, cooking.recipes[cooker])
            return orig(cooker, names)
        end
    end)

    return ok1 and ok2
end

CFG.weight_guard = PatchCookerRecipeWeights()

-------------------------------------------------------------------------------
-- 烹饪书「最近食谱」把烘焙咖啡豆画成生豆 —— 别让 cooked 后缀被剥掉
--
-- 现象（2026-09-25 玩家截图）：
--   ·「今天吃些啥」页的【可做食谱】：4 格全是深棕色的烘焙咖啡豆  ✔
--   ·「模组食谱」页的【最近食谱】：同一道咖啡，格子却是白色的生豆  ✘
--   同一道菜、同一份图集，两个页面画出两种豆子。
--
-- 根因在【游戏本体】的烹饪书记录逻辑，跟馨食记无关：
--
--   scripts/cookbookdata.lua:200  AddRecipe() 存盘前先剥名字
--   scripts/cookbookdata.lua:240  RemoveCookedFromName() —— 五连 gsub：
--
--       str = string.gsub(str, "_cooked_", "")            str = string.gsub(str, "_cooked", "")
--       str = string.gsub(str, "cooked_",  "")            str = string.gsub(str, "cooked",  "")
--       str = string.gsub(str, "quagmire_cooked", "quagmire_")
--
--   这是给原版「同一种东西有生/熟两个 prefab」准备的：玩家拿 berries_cooked 下锅，
--   书里就记成 berries，于是「3 浆果 + 蜂蜜」和「3 熟浆果 + 蜂蜜」算同一条食谱，
--   图标统一显示生浆果（原版 berry 生熟图标本来就长得差不多，没人会注意）。
--
--   ⚠ 我们的 coffeebeans_cooked 撞上了这条规则，但它俩不是「生/熟同物」：
--     生豆根本不能入锅，熟豆才是唯一被 AddIngredientValues 登记过的食材。
--     名字被剥成 coffeebeans 之后：
--        图标 → GetInventoryItemAtlas("coffeebeans.tex") → 咖啡豆区域 → 白豆
--        悬停 → STRINGS.NAMES["COFFEEBEANS"] →「咖啡豆」
--
--   「今天吃些啥」为什么是对的？那一页的数据是馨食记自己扫锅食材表
--   （diary_cookable / SmartSearch 记录的 minlist.names）算出来的，拿到的是
--   原样的 coffeebeans_cooked，所以颜色正确。两个页面表现不一致，根因就这一处。
--   （客户端日志里能直接看到佐证：
--      [CoffeePort-DIAG] 名项 = coffeebeans_cooked  atlas=images/coffeeport_items.xml）
--
-- 为什么改【数据层】而不是改图标表：
--   · 游戏本体的 ingredient_icon_remap 是 cookbookpage_crockpot.lua:133 里的
--     **local 表**，mod 根本碰不到（馨食记自己在 diary_utils.lua:18 另抄了一份，
--     所以只改它的话，只有馨食记的页面会好，「模组食谱 / 烹饪锅食谱」这两页照旧）。
--   · RemoveCookedFromName 是 CookbookData 的【类方法】，一个 override 就同时修好
--     所有页面 —— 因为大家读的都是 TheCookbook.preparedfoods 这份数据：
--        游戏本体 cookbookpage_crockpot.lua:495  TheCookbook.preparedfoods
--        馨食记 cookbookpage_original.lua:69 / whattoeat.lua:162 / helpmecook.lua:373
--
-- 时序（决定这里为什么必须挂 Load）：
--   scripts/main.lua:392  ModManager:LoadMods()          ← modmain 在这里跑，打补丁
--   scripts/main.lua:412  TheCookbook = require("cookbookdata")()
--   scripts/main.lua:413  TheCookbook:Load()             ← 补丁生效后再读存档
--   所以 modmain 里此刻 G.TheCookbook 还是 nil（main.lua:342 显式置 nil），
--   只能挂类方法，不能就地改数据。
--
-- 老存档怎么办：
--   已经被剥过的数据躺在本地烹饪书存档里（TheSim 持久化串 "cookbook"），
--   光靠上面的补丁【修不回来】，玩家重煮一次只会多出一行正确的、旧的错行还在。
--   所以 Load 之后再跑一次就地还原（MigrateCookbookNames）。
--   ⚠ 已知取舍：存档里 coffeebeans 究竟是「剥出来的熟豆」还是「玩家真拿生豆当填充物」，
--     数据上无法区分（这正是游戏那套归并规则自己的歧义）。这里一律按熟豆还原 ——
--     四格全熟豆是绝对主流，而拿生豆当填充的咖啡本来就极少见。
-------------------------------------------------------------------------------

local function PatchCookbookCookedSuffix()
    local ok, CookbookData = pcall(require, "cookbookdata")
    if not ok or type(CookbookData) ~= "table"
        or type(CookbookData.RemoveCookedFromName) ~= "function" then
        return false
    end

    local COOKED_BEAN = "coffeebeans_cooked"
    local RAW_BEAN    = "coffeebeans"

    -- ① 数据入口：把我们这颗熟豆的名字原样放回去（其余食材一个字都不动）
    local orig_remove = CookbookData.RemoveCookedFromName
    CookbookData.RemoveCookedFromName = function(self, ingredients)
        local ret = orig_remove(self, ingredients)
        if type(ret) == "table" and type(ingredients) == "table" then
            for i = 1, #ingredients do
                if ingredients[i] == COOKED_BEAN then
                    ret[i] = COOKED_BEAN
                end
            end
        end
        return ret
    end

    -- ② 老存档还原：把已经存成 coffeebeans 的位置改回 coffeebeans_cooked
    --
    --   只动 preparedfoods[成品].recipes 这一层，别的字段（has_eaten / filters 等）不碰。
    --   幂等：跑多少遍结果都一样，所以不需要「已迁移」标记，也不需要立刻回写存档 ——
    --   每次进游戏读档时修一遍内存，显示就是对的。
    local function MigrateCookbookNames(preparedfoods)
        if type(preparedfoods) ~= "table" then
            return 0
        end
        local fixed = 0
        for _, entry in pairs(preparedfoods) do
            local recipes = (type(entry) == "table") and entry.recipes or nil
            if type(recipes) == "table" then
                for _, combo in ipairs(recipes) do
                    if type(combo) == "table" then
                        for i = 1, #combo do
                            if combo[i] == RAW_BEAN then
                                combo[i] = COOKED_BEAN
                                fixed = fixed + 1
                            end
                        end
                    end
                end
            end
        end
        return fixed
    end

    local orig_load = CookbookData.Load
    if type(orig_load) == "function" then
        --   TheSim:GetPersistentString 是【同步】的（cookbookdata.lua:31-49 的回调
        --   执行完才轮到第 50 行判断 really_bad_state），所以 orig_load 返回时
        --   self.preparedfoods 已经填好了，这里改就是最终结果。
        CookbookData.Load = function(self, ...)
            orig_load(self, ...)
            local n = MigrateCookbookNames(self.preparedfoods)
            if n > 0 then
                print(string.format(
                    "[CoffeePort] 烹饪书：把 %d 处被 cooked 后缀抹掉的烘焙咖啡豆名称还原了（老存档修正）", n))
            end
        end
    end

    CFG.migrate_cookbook = MigrateCookbookNames   -- 供验证桩直接调
    return true
end

CFG.cookbook_patch = PatchCookbookCookedSuffix()

-------------------------------------------------------------------------------
-- 制作咖啡丛：给老存档 / 找不到野生咖啡丛的人一条保底路径
-------------------------------------------------------------------------------

if CFG.craft_coffeeplant then
    -- ⚠ 第 5 个参数 filters 不能省！
    --
    --   modutil 的 AddRecipe2 行为：
    --       nounlock = true  → 只进 CRAFTING_STATION 过滤器
    --       否则             → 只进 MODS 过滤器
    --       再叠加第 5 参数的 filters 列表
    --
    --   而制作菜单的搜索是【按当前页签】过滤的
    --   （craftingmenu_widget.lua 的 IsRecipeValidForFilter 只认
    --     CRAFTING_FILTERS[当前页签].default_sort_values），
    --   所以不写 filters 的配方，在任何一个正常页签里都搜不到，
    --   表现就是「科技列表里搜不到」。
    --
    --   "GARDENING" = 园艺页签，和农场 / 肥料 / 洒水壶同一栏，最贴切。
    AddRecipe2(
        "dug_coffeeplant",
        { Ingredient("berries", 4), Ingredient("ash", 3) },
        TECH.NONE,
        {
            atlas = ART.dug.atlas,
            image = ART.dug.image,
            nounlock = true,
        },
        { "GARDENING" }
    )
end

-------------------------------------------------------------------------------
-- 灰烬当肥料（海难设定：咖啡树要靠浇灰烬恢复）
-------------------------------------------------------------------------------

if CFG.ash_fertilizer then
    AddPrefabPostInit("ash", function(inst)
        -- 回调稍后才执行，所以这里用 G.TheWorld 而不是快照
        local world = G.TheWorld
        if world ~= nil and world.ismastersim then
            if inst.components.fertilizer == nil then
                inst:AddComponent("fertilizer")
            end
            local f = inst.components.fertilizer
            if f ~= nil then
                f.fertilizervalue = 1
                f.withered_cycles = CFG.ash_withered_cycles
                f.fertilize_sound = "dontstarve/common/fertilize"
            end
        end
        -- 客户端靠 tag 决定「施肥」这个动作能不能出现
        inst:AddTag("fertilizer")
    end)
end

-------------------------------------------------------------------------------
-- 世界生成（在森林里自然长出咖啡丛）
-------------------------------------------------------------------------------
--
-- ⚠ 这一段【不能】写在这里，必须写在同目录的 modworldgenmain.lua。
--
--   原因：DST 的 scripts/mods.lua 在 worldgen 那一轮只加载 modworldgenmain.lua：
--
--       self:InitializeModMain(mod.modname, mod, "modworldgenmain.lua")
--       if not self.worldgen then
--           self:InitializeModMain(mod.modname, mod, "modmain.lua")
--       end
--
--   而 map/storygen.lua 取 RoomPreInit 回调用的是
--   `ModManager:GetPostInitFns("RoomPreInit", roomname)`，
--   读的就是「当前这一轮 env」的 postinitfns。
--   写在 modmain 里虽然不会报错，但注册进的是主环境的表，世界生成时读不到，
--   表现为「日志说注入了 60 个 room，实际新世界里 0 棵咖啡丛」。
--
--   所以这里只留说明，真正的 AddRoomPreInit 在 modworldgenmain.lua。

-------------------------------------------------------------------------------

print(string.format("[CoffeePort] 已加载。美术方案=%s，语言=%s(code=%s)，咖啡倍率=%.3f，持续时间=%d 秒，出锅=%s 秒（内部 cooktime=%.3f，基准 %.1f 秒），甜味剂口径=%s，快速采集=%s，煮锅weight兜底=%s，烹饪书熟豆名补丁=%s；世界生成注入见 modworldgenmain",
    ART_PACK.mode, IS_ZH and "中文" or "英文", tostring(LANG_CODE),
    CFG.speed_mult, CFG.coffee_time,
    tostring(CFG.cook_seconds), CFG.cooktime, CFG.base_cook_time,
    CFG.sweetener_any and "任意甜味剂(海难原版：蜂蜜/蜂巢/蜂王浆)" or "只认蜂蜜",
    CFG.quick_pick and "开" or "关", CFG.weight_guard and "开" or "关",
    CFG.cookbook_patch and "开" or "关"))
