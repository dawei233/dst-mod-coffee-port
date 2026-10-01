--[[----------------------------------------------------------------------------
    CoffeePort / 海难咖啡移植 —— modworldgenmain
    （世界生成专用环境，只在「生成新世界」那一轮被加载）

    ⚠⚠ 为什么世界生成逻辑必须单独放这个文件，而不能写在 modmain.lua 里：

      DST 的 scripts/mods.lua → ModWrangler:LoadMods(worldgen) 里是这样写的：

          self:InitializeModMain(mod.modname, mod, "modworldgenmain.lua")
          if not self.worldgen then
              -- worldgen has to always run (for customization screen) but modmain
              -- can be skipped for worldgen. This reduces a lot of issues with
              -- missing globals.
              self:InitializeModMain(mod.modname, mod, "modmain.lua")
          end

      也就是说：worldgen == true 的那一轮【只加载 modworldgenmain.lua，
      完全跳过 modmain.lua】。

      而 AddRoomPreInit 注册的回调，是在地图生成过程中被
      scripts/map/storygen.lua 通过下面这行取出来的：

          local modfns = ModManager:GetPostInitFns("RoomPreInit", roomname)

      它读的是「这一轮加载用的那个 env」里的 postinitfns 表。
      所以注册必须发生在 worldgen 那一轮里 —— 写在 modmain.lua 里虽然不报错，
      但那时的注册进了「主环境」的 postinitfns，世界生成时根本读不到，等于白写。
      （早期版本就是这么踩的：日志里 room 注入了 60 个，实际世界 0 棵咖啡丛。）

    ⚠ 这个环境的白名单比 modmain 还窄：
      modutil.InsertPostInitFunctions 里有注释
        "Everything below is ONLY available in Main."
      紧接着 `if isworldgen then return end`。
      所以 AddAction / AddComponentAction / AddPlayerActionPostInit 等在此不可用。
      本文件只用到 AddRoomPreInit / GetModConfigData / require / print / ipairs，
      全部位于那道 return 之前，安全。

    ⚠ 白名单里【没有 tonumber】（只有 pairs/ipairs/print/math/table/type/
      string/tostring/require/Class/TUNING/LEVELCATEGORY/GROUND/WORLD_TILES/
      LOCKS/KEYS/LEVELTYPE/GLOBAL/modname/MODROOT），
      也没有 assert / pcall / select。
      所以取数一律走 GLOBAL.tonumber，并且不做 assert。
------------------------------------------------------------------------------]]

local G = GLOBAL

local tonumber = G.tonumber

local ROOMS = require("coffeep_rooms")

-------------------------------------------------------------------------------
-- 读「自然生成密度」配置
--   注意：worldgen 这一轮 DST 不会去载入 mod 配置存档（mods.lua 里
--   LoadModConfigurationOptions 只在 worldgen == false 时调用），
--   所以这里拿到的一般是 modinfo.lua 里写的 default。
--   万一拿到 nil，就退回 1.0，保证「只要装了 mod 新世界就有咖啡丛」。
-------------------------------------------------------------------------------

local function WorldgenRatio()
    local v = nil
    if GetModConfigData ~= nil then
        v = GetModConfigData("worldgen")
    end
    v = tonumber(v)
    if v == nil then
        -- 兜底必须跟 modinfo.lua 里 worldgen 的 default 保持一致（0.25），
        -- 否则「配置读不到」时会偷偷按 1.0 撒满地图。
        v = 0.25
    end
    if v < 0 then
        v = 0
    end
    return v
end

local ratio = WorldgenRatio()

-------------------------------------------------------------------------------
-- 往「原本长浆果丛」的房间里按比例掺咖啡丛
--
--   房间的 room.contents.distributeprefabs 是「prefab 名 -> 权重」的表，权重不是个数。
--   世界生成掏空 map/graphnode.lua 时是这样的（Node:PopulateExtra）：
--
--       for current_pos_idx = ... do
--           if math.random() < contents.distributepercent then          -- 先掷骰子
--               local prefab = spawnFn.pickspawnprefab(distributeprefabs, ...)  -- 再抽签
--           end
--       end
--
--   而 forest_map.lua 的 pickspawnprefab 是纯粹的【加权随机】：把所有条目的权重
--   求和当分母，谁权重大谁被抽中的概率高。
--
--   所以 dp.coffeeplant = dp.berrybush * ratio 的准确含义是：
--       咖啡丛数量 ≈ 浆果丛数量 × ratio
--   ratio = 1.0 就是「咖啡丛跟浆果丛一样多」（原版世界里 ≈ 上百丛，非常多），
--   ratio = 0.25 则是大约四分之一。
--   另外要注意：它是往抽签池里【加一个条目】，浆果丛的份额会被略微稀释，
--   并不会凭空多出一倍的灌木。
--
--   之所以不写死个数而是挂靠 berrybush：这样咖啡丛密度会自动跟随每个房间
--   自己的浆果丛密度（森林密、荒地疏），不用为 60 个房间分别调参。
-------------------------------------------------------------------------------

local function InjectCoffee(room)
    local contents = room ~= nil and room.contents or nil
    if contents == nil then
        return
    end

    local dp = contents.distributeprefabs
    if dp == nil then
        -- 房间没有 distributeprefabs（例如纯地形房间），跳过
        return
    end

    -- 已经有就别重复加（同一个 room 可能被多个 task 引用，PreInit 会跑多次）
    if dp.coffeeplant ~= nil then
        return
    end

    local base = dp.berrybush or dp.berrybush2 or dp.berrybush_juicy
    if base == nil then
        -- 兜底：万一将来 DST 换了浆果丛 prefab 名，用一个很小的默认密度，
        -- 免得因为读不到基准值而完全不生成。
        base = 0.02
    end

    dp.coffeeplant = base * ratio
end

if ratio > 0 then
    ---------------------------------------------------------------------------
    -- 地皮过滤：让咖啡丛和浆果丛长在同样的地皮上
    --
    -- 世界生成挑地板物件时会查 `terrain.filter[prefab名]`，命中列表里的地皮就跳过
    -- （见 map/forest_map.lua 的 pickspawnprefab）。terrain.filter 里没有
    -- coffeeplant 这一项，默认就是「哪都能长」，会跑到岩石地 / 沙漠 / 沼泽上，很出戏。
    -- 这里直接把 berrybush 的黑名单抄一份给 coffeeplant。
    --
    -- ⚠ 两个坑：
    --   1) map/terrain.lua 最后一行是 `terrain={rooms=..., filter=TERRAIN_FILTER}` ——
    --      它是把表【赋给全局 terrain】，函数【没有 return】。
    --      所以 require("map/terrain") 的返回值是 true，不是模块表！
    --      必须先 require 把它加载出来，再去读全局 terrain。
    --   2) 这个世界生成环境里 _G 是 strict 的，直接写 G.terrain 在
    --      「还没加载 map/terrain」时会抛 "variable 'terrain' is not declared"。
    --      所以用 rawget 绕开 strict，拿不到就当作没应用。
    ---------------------------------------------------------------------------
    local terr_ok = false
    if G ~= nil then
        G.pcall(G.require, "map/terrain")

        local terrain = G.rawget(G, "terrain")
        local tf = terrain ~= nil and terrain.filter or nil
        if tf ~= nil then
            if tf.coffeeplant == nil then
                local base = tf.berrybush
                if base ~= nil then
                    local copy = {}
                    for i = 1, #base do
                        copy[i] = base[i]
                    end
                    tf.coffeeplant = copy
                else
                    tf.coffeeplant = {}
                end
            end
            terr_ok = true
        end
    end

    local n = 0
    for _, roomname in ipairs(ROOMS) do
        AddRoomPreInit(roomname, InjectCoffee)
        n = n + 1
    end
    print(string.format(
        "[CoffeePort] 世界生成：已对 %d 个含浆果丛的房间注册咖啡丛注入" ..
        "（密度系数 %.2f → 咖啡丛数量约为浆果丛的 %.2f 倍，地皮过滤 %s）",
        n, ratio, ratio, terr_ok and "已应用" or "未应用"))
else
    print("[CoffeePort] 世界生成：密度系数为 0，跳过咖啡丛注入（只能靠制作配方获得咖啡丛）")
end
