--[[----------------------------------------------------------------------------
    coffeeplant.lua —— 咖啡丛 / 铲起的咖啡丛

    玩法（对齐海难原版基调）：
      · 采摘一次得 1 颗咖啡豆，采完进入再生期
      · 连续采若干次后枯萎（显示枯枝），此时只能挖到 2 个小树枝
      · 用铲子挖走 → 得到「铲起的咖啡丛」，可种到任意地面
      · 刚种下的咖啡丛是枯的，需要施肥（含灰烬，见 modmain 配置）才会重新长豆
      · 施肥同样可以让枯萎的咖啡丛复活，而且是【当场】复活（海难原版的浇灰烬手感）
------------------------------------------------------------------------------]]

-- 注意：prefab 文件跑在严格模式环境里，没有 GLOBAL，也不能读未声明的全局；
-- modmain 把共享数据挂在 TUNING 下，这里照读即可。
local COFFEEP = TUNING.COFFEEP
assert(COFFEEP ~= nil, "[CoffeePort] modmain 未初始化 TUNING.COFFEEP，请检查 mod 是否完整")

local ART = COFFEEP.art
local CFG = COFFEEP.cfg

local BEAN_PREFAB  = "coffeebeans"
local PLANT_PREFAB = "coffeeplant"
local DUG_PREFAB   = "dug_coffeeplant"

local ANIMS  = ART.anim
local FRUITS = ART.plant_fruit_symbols

local plant_assets =
{
    Asset("ANIM", "anim/"..ART.plant_build..".zip"),
}

local plant_prefabs =
{
    BEAN_PREFAB,
    DUG_PREFAB,
    "twigs",
}

-------------------------------------------------------------------------------
-- 视觉
-------------------------------------------------------------------------------

--- 按剩余产量比例切换咖啡豆的贴图符号（多 / 中 / 少 / 无）
local function SetFruitSymbol(inst, pct)
    local want = nil
    if pct ~= nil then
        want = (pct >= 0.9 and FRUITS[1]) or (pct >= 0.34 and FRUITS[2]) or FRUITS[3]
    end
    for i = 1, #FRUITS do
        if FRUITS[i] == want then
            inst.AnimState:Show(FRUITS[i])
        else
            inst.AnimState:Hide(FRUITS[i])
        end
    end
end

local function PlayIdle(inst)
    inst.AnimState:PlayAnimation(ANIMS.idle, true)
end

-- 「空」状态的外观。这里有两条不同的来路，必须分开处理 ——
-- DST 把「施肥救活」也塞进了同一个 MakeEmpty()（源码 pickable.lua:289），
-- 所以 makeemptyfn 会被两种完全不同的场景调用：
--
--   ① 普通采摘一次 → 只剩叶子：播 picked → idle，豆子全隐
--   ② 施肥救活枯萎丛 → 当前还停在「枯枝」动画上，要播 dead_to_idle → idle，
--      并把这株剩余的豆子按比例重新显示出来
--
-- 原版浆果丛就是这么区分的（berrybush.lua:38 的 makeemptyfn，在
-- `IsCurrentAnimation("dead")` 分支里播 dead_to_idle）。
-- ⚠ 我最初这里写成「当前是 dead 就直接 return」，结果施肥后视觉永远卡在枯枝上：
--   功能其实已经活了（能采），但玩家看到的还是一棵枯树，等于白施肥。
local function makeemptyfn(inst)
    if POPULATING then
        PlayIdle(inst)
        SetFruitSymbol(inst, nil)
        return
    end

    local p = inst.components.pickable
    local revived = inst.AnimState:IsCurrentAnimation(ANIMS.dead)

    if revived then
        inst.AnimState:PlayAnimation(ANIMS.dead_to_idle)
        inst.AnimState:PushAnimation(ANIMS.idle, true)
    else
        inst.AnimState:PlayAnimation(ANIMS.picked)
        inst.AnimState:PushAnimation(ANIMS.idle, true)
    end

    -- 只有「救活」这条路上才该有豆子；普通采摘完是空的
    local pct = nil
    if revived and p ~= nil and p.max_cycles ~= nil and p.max_cycles > 0 and p.cycles_left ~= nil then
        pct = p.cycles_left / p.max_cycles
        if pct <= 0 then
            pct = nil
        end
    end
    SetFruitSymbol(inst, pct)
end

-- 枯萎：彻底死掉
local function makebarrenfn(inst)
    if not POPULATING and not inst.AnimState:IsCurrentAnimation(ANIMS.dead) then
        inst.AnimState:PlayAnimation(ANIMS.idle_to_dead)
        inst.AnimState:PushAnimation(ANIMS.dead, false)
    else
        inst.AnimState:PlayAnimation(ANIMS.dead)
    end
    SetFruitSymbol(inst, nil)
end

-- 重新长满：按剩余可采次数决定果实的多少
local function makefullfn(inst)
    local p = inst.components.pickable
    if p ~= nil and p:IsBarren() then
        inst.AnimState:PlayAnimation(ANIMS.dead)
        SetFruitSymbol(inst, nil)
        return
    end

    local pct = 1
    if p ~= nil and p.max_cycles ~= nil and p.cycles_left ~= nil and p.max_cycles > 0 then
        pct = p.cycles_left / p.max_cycles
    end

    if POPULATING then
        PlayIdle(inst)
    else
        inst.AnimState:PlayAnimation(ANIMS.grow)
        inst.AnimState:PushAnimation(ANIMS.idle, true)
    end
    SetFruitSymbol(inst, pct)
end

local function onpickedfn(inst, picker)
    local p = inst.components.pickable
    if p == nil then
        return
    end

    -- ⚠ DST 的 Pickable:Pick 只在【移植过】的植物上扣 cycles_left（源码 pickable.lua
    --   里的 `if self.transplanted and self.cycles_left ~= nil then`），
    --   也就是说 DST 原版的野生植物是「无限采」的（浆果丛就是如此）。
    --   海难里的咖啡丛是野生的也会被采枯，所以这里自己补扣一次。
    --   移植过的不用管：Pick 已经替我们扣过了，而且它扣在调用 onpickedfn 之前。
    --
    --   cycles_left 是 netvar，归零时会自动挂上 "barren" tag
    --   （oncyclesleft 回调），客户端正是靠这个 tag 才出现「施肥」动作。
    if not p.transplanted and CFG.wild_deplete and p.cycles_left ~= nil then
        p.cycles_left = math.max(0, p.cycles_left - 1)
    end

    -- 注意：此时 cycles_left 已经反映本次采摘
    if p:IsBarren() then
        -- 采空了：播枯枝动画，同时 Pick 那边也不会再安排再生（它检查 IsBarren()）
        makebarrenfn(inst)
    else
        inst.AnimState:PlayAnimation(ANIMS.picked)
        inst.AnimState:PushAnimation(ANIMS.idle, true)
        SetFruitSymbol(inst, nil)
    end
end

-------------------------------------------------------------------------------
-- 铲起 / 移植
-------------------------------------------------------------------------------

local function dig_up(inst, worker)
    local loot = inst.components.lootdropper
    local p = inst.components.pickable

    if loot ~= nil and p ~= nil then
        if p:IsBarren() then
            -- 海难原版：枯掉的咖啡树只能挖到 2 个小树枝
            loot:SpawnLootPrefab("twigs")
            loot:SpawnLootPrefab("twigs")
        else
            if p:CanBePicked() then
                loot:SpawnLootPrefab(BEAN_PREFAB)
            end
            loot:SpawnLootPrefab(DUG_PREFAB)
        end
    end
    inst:Remove()
end

local function ontransplantfn(inst)
    -- 移植后先处于枯死状态，施肥才会重新产豆（海难原版：浇灌灰烬才恢复）
    if inst.components.pickable ~= nil then
        inst.components.pickable:MakeBarren()
    end
end

--- 采得越多，下一轮长得越慢
local function getregentimefn(inst)
    local p = inst.components.pickable
    if p == nil or p.max_cycles == nil or p.cycles_left == nil then
        return CFG.regrow_time
    end
    local passed = math.max(0, p.max_cycles - p.cycles_left)
    return CFG.regrow_time + CFG.regrow_increase * passed
end

-------------------------------------------------------------------------------
-- 咖啡丛本体
-------------------------------------------------------------------------------

local function plant_fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    inst:AddTag("bush")
    inst:AddTag("plant")
    inst:AddTag("renewable")

    MakeSmallObstaclePhysics(inst, 0.1)
    inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.DEFAULT] / 2)

    if ART.plant_minimap ~= nil then
        inst.MiniMapEntity:SetIcon(ART.plant_minimap)
    end

    inst.AnimState:SetBank(ART.plant_bank)
    inst.AnimState:SetBuild(ART.plant_build)
    inst.AnimState:PlayAnimation(ANIMS.idle, true)
    SetFruitSymbol(inst, 1)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("pickable")
    inst.components.pickable.picksound = "dontstarve/wilson/harvest_berries"
    inst.components.pickable.onpickedfn     = onpickedfn
    inst.components.pickable.makeemptyfn    = makeemptyfn
    inst.components.pickable.makebarrenfn   = makebarrenfn
    inst.components.pickable.makefullfn     = makefullfn
    inst.components.pickable.ontransplantfn = ontransplantfn
    inst.components.pickable.getregentimefn = getregentimefn
    inst.components.pickable:SetUp(BEAN_PREFAB, CFG.regrow_time, 1)
    inst.components.pickable.max_cycles  = CFG.harvest_cycles
    inst.components.pickable.cycles_left = CFG.harvest_cycles

    -- 快速采集（配置见 modmain 的 QuickPickEnabled）：
    --   pickable 的 quickpick 是个属性 setter，内部只做 AddTag("quickpick")
    --   （源码 components/pickable.lua 的 onquickpick）。wilson stategraph 据此
    --   把采摘动作从 dolongaction 换成 doshortaction（SGwilson.lua 的 PICK 分支）。
    --   这个 tag 会自动从服务端同步到客户端（客户端 stategraph 读的正是 tag），
    --   所以不需要 netvar / 额外网络化处理。
    --
    --   之所以要自己开：工坊 Mod「Quick Pick」是维护一份硬编码 prefab 名单再逐个
    --   打开的，咖啡丛是我们自定义的 prefab，永远不在那份名单里。
    if CFG.quick_pick then
        inst.components.pickable.quickpick = true
    end

    -- 施肥救活：当场复活，不重新等一个再生周期。
    --
    -- 为什么需要这一步：DST 的 Pickable:Fertilize 把「救活」复用成了「采摘一次」的流程
    -- （源码 pickable.lua:274-290）——
    --       self.cycles_left = self.max_cycles   ← 次数确实补满了
    --       self:MakeEmpty()                     ← 然后走「采摘后的空窗」流程
    -- 而 MakeEmpty 紧接着会把 canbepicked 置 false，并排一个再生计时器
    -- （pickable.lua:426-448）。也就是说光靠原版逻辑，施肥后还要再干等一整个再生周期
    -- （本 mod 默认 3 天）才能采，那期间植物看着是活的却一颗豆都没有，
    -- 玩家会觉得「施肥根本没用」。海难原版是浇了灰烬当场复活，这里就补回这一步。
    --
    -- 做法：包一层实例方法（不做全局 AddComponentPostInit，免得影响别的植物）。
    -- 视觉部分由上面的 makeemptyfn 负责 —— 它会发现「当前还是枯枝动画 + 次数已补满」
    -- 从而播 dead_to_idle 并把豆子显出来。
    local pickable_fertilize = inst.components.pickable.Fertilize
    inst.components.pickable.Fertilize = function(self, fertilizer, doer)
        local ok = pickable_fertilize(self, fertilizer, doer)

        if ok and self.cycles_left ~= 0 and not self:IsBarren() then
            -- 撤掉 MakeEmpty 顺手排的那个再生计时器
            if self.task ~= nil then
                self.task:Cancel()
                self.task = nil
            end
            self.targettime = nil

            self.canbepicked = true
            -- 视觉（复活动画 + 豆子 symbol）只由 makeemptyfn 负责，这里不重复设 ——
            -- 一处一处改，才不会出现「两个地方都做了同一件事，破坏了其中一个照样正常」
            -- 这种掩盖问题的冗余。
        end

        return ok
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("lootdropper")

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.DIG)
    inst.components.workable:SetWorkLeft(1)
    inst.components.workable:SetOnFinishCallback(dig_up)

    MakeMediumBurnable(inst)
    MakeSmallPropagator(inst)
    MakeHauntableIgnite(inst)

    return inst
end

-------------------------------------------------------------------------------
-- 铲起的咖啡丛（可堆叠、可种下）
-------------------------------------------------------------------------------

-- 铲起态的外观：优先用美术表里 dug 自己的 bank/build/anim
-- （海难素材里 = coffeebush build 的 dead 动画，也就是一棵躺倒的枯丛）
local DUG_BANK  = (ART.dug ~= nil and ART.dug.bank)  or ART.plant_bank
local DUG_BUILD = (ART.dug ~= nil and ART.dug.build) or ART.plant_build
local DUG_ANIM  = (ART.dug ~= nil and ART.dug.anim)  or ANIMS.dead

local dug_assets =
{
    Asset("ANIM", "anim/"..DUG_BUILD..".zip"),
}

local function ondeploy(inst, pt, deployer)
    local plant = SpawnPrefab(PLANT_PREFAB)
    if plant == nil then
        return
    end

    plant.Transform:SetPosition(pt:Get())
    inst.components.stackable:Get():Remove()

    if plant.components.pickable ~= nil then
        plant.components.pickable:OnTransplant()
    end

    if deployer ~= nil and deployer.SoundEmitter ~= nil then
        deployer.SoundEmitter:PlaySound("dontstarve/common/plant")
    end
end

local function dug_fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst:AddTag("deployedplant")

    inst.AnimState:SetBank(DUG_BANK)
    inst.AnimState:SetBuild(DUG_BUILD)
    inst.AnimState:PlayAnimation(DUG_ANIM)

    MakeInventoryFloatable(inst)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_LARGEITEM

    inst:AddComponent("inspectable")
    inst.components.inspectable.nameoverride = DUG_PREFAB

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = ART.dug.atlas
    -- ⚠ 用 ART.dug.icon（不带 .tex）—— SetImage 内部会自己补 ".tex"，
    --   传 ART.dug.image（带 .tex）会拼成 ".tex.tex" 导致图标空白且不报错。
    inst.components.inventoryitem.imagename = ART.dug.icon

    inst:AddComponent("fuel")
    inst.components.fuel.fuelvalue = TUNING.LARGE_FUEL

    MakeMediumBurnable(inst, TUNING.LARGE_BURNTIME)
    MakeSmallPropagator(inst)
    MakeHauntableLaunchAndIgnite(inst)

    inst:AddComponent("deployable")
    inst.components.deployable.ondeploy = ondeploy
    inst.components.deployable:SetDeployMode(DEPLOYMODE.PLANT)

    return inst
end

return Prefab(PLANT_PREFAB, plant_fn, plant_assets, plant_prefabs),
    Prefab(DUG_PREFAB, dug_fn, dug_assets),
    MakePlacer(DUG_PREFAB.."_placer", ART.plant_bank, ART.plant_build, ANIMS.idle)
