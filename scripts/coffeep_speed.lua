--[[----------------------------------------------------------------------------
    coffeep_speed.lua —— 咖啡因移速加成

    海难原版机制：基础移速 6，咖啡 +5 速度（即 11/6 ≈ 1.8333 倍），持续一段时间。
    本模块用 locomotor 的「外部倍率」实现，key 固定，重复喝只会刷新时长，不会叠加。

    纯实例方法实现，不引用 GetTime / TUNING 等全局，可被 prefab 文件安全 require。
------------------------------------------------------------------------------]]

local KEY = "coffeep_caffeine"
local TICK = 0.25          -- 每 0.25 秒刷新一次倍率，用于实现衰减

local M = {}

local function SetMultiplier(inst, mult)
    if inst.components.locomotor == nil then
        return false
    end
    inst.components.locomotor:SetExternalSpeedMultiplier(inst, KEY, mult)
    return true
end

local function Stop(inst)
    if inst._coffeep_task ~= nil then
        inst._coffeep_task:Cancel()
        inst._coffeep_task = nil
    end
    inst._coffeep_elapsed = nil
    inst._coffeep_total = nil
    inst._coffeep_peak = nil
    inst._coffeep_decay = nil
    if inst.components ~= nil and inst.components.locomotor ~= nil then
        inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, KEY)
    end
end

local function Step(inst)
    local elapsed = (inst._coffeep_elapsed or 0) + TICK
    local total = inst._coffeep_total or 0

    if elapsed >= total then
        Stop(inst)
        return
    end

    inst._coffeep_elapsed = elapsed

    local mult = inst._coffeep_peak
    if inst._coffeep_decay and total > 0 then
        -- 原版手感：速度从峰值线性衰减回正常
        mult = 1 + (inst._coffeep_peak - 1) * (1 - elapsed / total)
    end
    SetMultiplier(inst, mult)
end

--- 给实体挂上咖啡因加速
--- @param inst     目标实体（通常是玩家）
--- @param duration 持续秒数，<=0 表示不加成
--- @param peak     峰值倍率，例如 1.8333
--- @param decay    true = 随时间线性衰减；false = 全程保持峰值
function M.Start(inst, duration, peak, decay)
    if inst == nil or inst.components == nil then
        return
    end

    duration = tonumber(duration) or 0
    peak = tonumber(peak) or 1

    -- 先清掉旧状态，避免重复喝时倍率叠着不清
    if inst._coffeep_task ~= nil then
        inst._coffeep_task:Cancel()
        inst._coffeep_task = nil
    end

    if duration <= 0 or peak <= 1 or not SetMultiplier(inst, peak) then
        Stop(inst)
        return
    end

    inst._coffeep_total = duration
    inst._coffeep_elapsed = 0
    inst._coffeep_peak = peak
    inst._coffeep_decay = decay and true or false

    inst._coffeep_task = inst:DoPeriodicTask(TICK, Step)
end

function M.Stop(inst)
    Stop(inst)
end

function M.IsActive(inst)
    return inst ~= nil and inst._coffeep_task ~= nil
end

return M
