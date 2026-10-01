--[[----------------------------------------------------------------------------
    coffee.lua —— 咖啡（烹饪锅料理）

    海难原版数值：
      配方      3 烘焙咖啡豆 + 甜味剂/乳制品（蜂蜜、蜂巢、羊奶、黄油…）或 4 烘焙咖啡豆
      食用      +9.375 饥饿、+3 生命、海难原版 -5 理智（本 Mod 默认 0，配置项 coffee_sanity），保质期 10 天
      效果      移速 +5（基础 6，约 1.83 倍），持续「半天」≈ 4 分钟，速度随时间衰减

    外观：
      锅上（出锅那一刻）、手上、地上，统一借用 DST 自带锅成品动画里的茶杯符号
      （原版「舒缓茶 sweettea」，bank = cook_pot_food / build = cook_pot_food7）。
      三处同源，全靠 coffeep_art.lua 的 coffee 条目 + 下面那次 OverrideSymbol 保证一致。
      物品栏里的 2D 图标仍是海难原版咖啡杯（coffee.tex），与模型无关。
      详细机制见 coffeep_art.lua 中 coffee 条目上方那段注释。
------------------------------------------------------------------------------]]

-- 注意：prefab 文件跑在严格模式环境里，没有 GLOBAL，也不能读未声明的全局；
-- modmain 把共享数据挂在 TUNING 下，这里照读即可。
local COFFEEP = TUNING.COFFEEP
assert(COFFEEP ~= nil, "[CoffeePort] modmain 未初始化 TUNING.COFFEEP，请检查 mod 是否完整")

local ART   = COFFEEP.art
local CFG   = COFFEEP.cfg
local SPEED = require("coffeep_speed")

local assets =
{
    -- ⚠ 两个 zip 缺一不可（这也是为什么美术表里 bank 与 build 是两个字段）：
    --     cook_pot_food.zip  → 提供 bank「cook_pot_food」与全部动画（它含 anim.bin）
    --     cook_pot_food7.zip → 只含 build.bin，提供茶杯符号本身（【没有】anim.bin）
    -- 原版 preparedfoods.lua:8-16 的工厂也是这么声明的（固定声明前者，
    -- 有 overridebuild 时再补声明后者）。
    Asset("ANIM", "anim/"..ART.coffee.bank_build..".zip"),
    Asset("ANIM", "anim/"..ART.coffee.build..".zip"),
}

local prefabs =
{
    "spoiled_food",
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)
    -- 尺寸/偏移/缩放跟原版「舒缓茶」完全对齐（preparedfoods.lua:893
    -- floater = {"med", 0.05, 0.65}）。注意第 4 个参数是【水花特效的缩放】，
    -- 不是物品本身的缩放 —— Floater:SetScale 只作用于 front_fx / back_fx。
    MakeInventoryFloatable(inst, "med", 0.05, 0.65)

    inst.AnimState:SetBank(ART.coffee.bank)
    inst.AnimState:SetBuild(ART.coffee.build)
    inst.AnimState:PlayAnimation(ART.coffee.anim or "idle")

    -- ★ 手上/地上的咖啡 = 锅里出锅那杯：靠「符号覆盖」实现，与烹饪锅同源。
    --
    --   ⚠ 这一行【不能省】，而且必须和 modmain 里 coffee_recipe 的
    --     overridebuild / overridesymbolname 填同一对值，否则就会出现
    --     「锅里是茶杯、手上是别的东西」这种不一致。
    --
    --   不覆盖的后果：cook_pot_food7 只是个符号仓库，它的 swap_food 槽本身是空的
    --   → 物品在世界里会变成完全看不见的隐形物（不报错、不崩、日志无痕，最难查）。
    --
    --   同一机制的另一半在 scripts/prefabs/cookpot.lua:105 的 SetProductSymbol：
    --       inst.AnimState:OverrideSymbol("swap_cooked", build, symbol)
    --   锅用的是 swap_cooked 槽，物品用的是 swap_food 槽，所以两处都得写。
    if ART.coffee.symbol ~= nil then
        inst.AnimState:OverrideSymbol("swap_food", ART.coffee.build, ART.coffee.symbol)
    end

    inst:AddTag("preparedfood")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    -- ⚠ 必须用 ART.coffee.icon（不带 .tex）！InventoryItem:SetImage 内部会自己补
    --   ".tex"（源码 components/inventoryitem_replica.lua: classified.image:set(imagename..".tex")）。
    --   这里曾经写的是 ART.coffee.image（已带 .tex）→ 最终拼成 "coffee.tex.tex"
    --   → 图集里查不到 → 物品栏里的咖啡渲染成一个纯色方块，而且日志里一个字都不报。
    --   同一个 mod 里 coffeebeans / coffeeplant 都写的是 icon，只有这里抄漏了。
    --   详见 coffeep_art.lua 里 icon 与 image 两个字段的注释。
    inst.components.inventoryitem.atlasname = ART.coffee.atlas
    inst.components.inventoryitem.imagename = ART.coffee.icon

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

    inst:AddComponent("edible")
    inst.components.edible.foodtype = FOODTYPE.GOODIES
    inst.components.edible.healthvalue = 3         -- 海难原版 +3 血
    inst.components.edible.hungervalue = 9.375     -- 海难原版 +9.375 饱食
    -- 海难原版 -5 理智（掉理智），官方设定而非数值错误；现由配置项 coffee_sanity
    -- 决定，默认 0。改这里就够了 —— 吃下去生效的是这一行，不是食谱表里的 sanity。
    inst.components.edible.sanityvalue = CFG.coffee_sanity
    inst.components.edible:SetOnEatenFn(function(inst, eater)
        if eater == nil then
            return
        end
        SPEED.Start(eater, CFG.coffee_time, CFG.speed_mult, CFG.decay)
    end)

    inst:AddComponent("perishable")
    inst.components.perishable:SetPerishTime(TUNING.PERISH_MED)   -- 10 天
    inst.components.perishable:StartPerishing()
    inst.components.perishable.onperishreplacement = "spoiled_food"

    MakeSmallBurnable(inst)
    MakeSmallPropagator(inst)
    MakeHauntableLaunchAndIgnite(inst)

    return inst
end

return Prefab("coffee", fn, assets, prefabs)
