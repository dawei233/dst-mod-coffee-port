--[[----------------------------------------------------------------------------
    coffeebeans.lua —— 咖啡豆 & 烘焙咖啡豆

    海难原版数值：
      咖啡豆       吃下回 9.375 饥饿，不加速、不减理智，6 天腐坏（水果度 0.5）
      烘焙咖啡豆   火上烤咖啡豆得到；吃下 +5 移速持续 30 秒、海难原版 -5 理智
                   （本 Mod 默认 0，配置项 roasted_sanity），15 天腐坏
------------------------------------------------------------------------------]]

-- 注意：prefab 文件跑在严格模式环境里，没有 GLOBAL，也不能读未声明的全局；
-- modmain 把共享数据挂在 TUNING 下，这里照读即可。
local COFFEEP = TUNING.COFFEEP
assert(COFFEEP ~= nil, "[CoffeePort] modmain 未初始化 TUNING.COFFEEP，请检查 mod 是否完整")

local ART   = COFFEEP.art
local CFG   = COFFEEP.cfg
local SPEED = require("coffeep_speed")

-- 海难原版：基础移速 6 点，烘焙咖啡豆给 +5 点；12.5 饥饿 = 海难的 9.375 点换算到 DST 的小份食物档
local BEAN_HUNGER = 9.375
-- 海难原版烘焙咖啡豆和咖啡一样是 -5 理智 —— 官方设定，不是数值抄错。
-- 现由配置项 roasted_sanity 决定，默认 0；想还原原版手感在配置菜单里选 -5。
local BEAN_SANITY_ROASTED = CFG.roasted_sanity

local function MakeBean(data)
    local assets =
    {
        Asset("ANIM", "anim/"..data.build..".zip"),
    }

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)
        MakeInventoryFloatable(inst, "small", 0.05, 0.5)

        inst.AnimState:SetBank(data.bank)
        inst.AnimState:SetBuild(data.build)
        inst.AnimState:PlayAnimation(data.anim or "idle")

        -- 生豆可上火烤；熟豆不能再烤
        if data.cookproduct ~= nil then
            inst:AddTag("cookable")
        end

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")

        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem.atlasname = data.atlas
        -- ⚠ 这里必须用 data.icon（不带 .tex）。InventoryItem:SetImage 内部会自己补
        --   ".tex"（源码：classified.image:set(imagename..".tex")），若传 data.image
        --   （已带 .tex）就会变成 "coffeebeans.tex.tex"，图集里查不到 → 背包/物品栏
        --   图标空白，而且【日志里一个字都不报】。详见 coffeep_art.lua 的注释。
        inst.components.inventoryitem.imagename = data.icon

        inst:AddComponent("stackable")
        inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

        -- 可食性：只有【烤过的豆子】和【咖啡】能吃，生豆不能（生豆传 edible = false）。
        --
        -- 为什么生豆靠「不加 edible 组件」来实现不能吃：
        --   DST 里没有别的屏蔽手段 —— 玩家的 eater 组件默认 caneat = FOODGROUP.OMNI，
        --   认得所有 FOODTYPE，所以换个 foodtype 是屏蔽不掉的。
        --   原版 premole（鼹鼠）就是这么做的：有 cookable、可下锅，但完全没有 edible 组件。
        --
        --   ⚠ 这样做【不会】影响火上烤与下锅：
        --     火上烤  只看 item.components.cookable（components/cooker.lua:CanCook）
        --     下烹饪锅 只看 cooking.ingredients 注册表（containers.lua 的 itemtestfn
        --              → cooking.IsCookingIngredient），与组件无关。
        --     两条链路全程不读 components.edible（原版 mole 就是活证据）。
        if data.edible ~= false then
            inst:AddComponent("edible")
            -- ⚠ 千万不要写 FOODTYPE.FRUIT —— DST 的 FOODTYPE 表里根本没有 FRUIT 这一项！
            --   海难（原版 DLC）里咖啡豆算水果，但 DST 把「水果」并进了 VEGGIE
            --   （constants.lua 的注释：BERRY = "BERRY", --hack for smallbird; berries are actually part of veggie）。
            --   写成 FOODTYPE.FRUIT 会得到 nil → 实体挂不上 edible_XXX tag
            --   → Eater:PrefersToEat 返回 false → Eater:Eat 直接 return
            --   → 表现就是「右键吃不了」，而且日志里一个字都不报。
            --   锅的食材分类（AddIngredientValues 里的 fruit=0.5）是另一套东西，不受影响。
            inst.components.edible.foodtype = FOODTYPE.VEGGIE
            inst.components.edible.healthvalue = 0
            inst.components.edible.hungervalue = BEAN_HUNGER
            inst.components.edible.sanityvalue = data.sanity or 0
            inst.components.edible:SetOnEatenFn(data.oneatenfn)
        end

        inst:AddComponent("perishable")
        inst.components.perishable:SetPerishTime(data.perishtime)
        inst.components.perishable:StartPerishing()
        inst.components.perishable.onperishreplacement = "spoiled_food"

        if data.cookproduct ~= nil then
            inst:AddComponent("cookable")
            inst.components.cookable.product = data.cookproduct
        end

        MakeSmallBurnable(inst)
        MakeSmallPropagator(inst)
        MakeHauntableLaunchAndIgnite(inst)

        return inst
    end

    return Prefab(data.name, fn, assets)
end

-------------------------------------------------------------------------------
-- 烘焙咖啡豆：吃掉后获得 30 秒（原版）加速，不吃衰减
-------------------------------------------------------------------------------
local function on_eaten_roasted(inst, eater)
    if eater == nil then
        return
    end
    SPEED.Start(eater, CFG.roasted_time, CFG.speed_mult, false)
end

return MakeBean(
    {
        name        = "coffeebeans",
        bank        = ART.beans.bank,
        build       = ART.beans.build,
        atlas       = ART.beans.atlas,
        -- ⚠ 一定要用 icon（不带 .tex）。工厂里赋给 inventoryitem.imagename 的是
        --   data.icon，SetImage 内部再补 ".tex"。曾经这里写的是 image（带 .tex），
        --   而工厂读的是 data.icon —— 于是 imagename 恒为 nil，只是靠 DST 的
        --   「拿 prefab 名兜底」歪打正着（prefab 名恰好等于图集 region 名）。
        --   这种巧合一旦改个名字就露馅，所以字段名必须和工厂读的一致。
        icon        = ART.beans.icon,
        perishtime  = TUNING.PERISH_FAST,     -- 6 天
        cookproduct = "coffeebeans_cooked",
        -- 生豆不能直接吃（不挂 edible 组件），必须先烤。
        -- 注意：这不影响它当烹饪锅食材 —— 锅走的是 AddIngredientValues 注册表。
        edible      = false,
    }),
    MakeBean(
    {
        name        = "coffeebeans_cooked",
        bank        = ART.beans_cooked.bank,
        build       = ART.beans_cooked.build,
        atlas       = ART.beans_cooked.atlas,
        icon        = ART.beans_cooked.icon,
        perishtime  = TUNING.PERISH_SLOW,     -- 15 天
        cookproduct = nil,
        sanity      = BEAN_SANITY_ROASTED,
        oneatenfn   = on_eaten_roasted,
    })
