-- ============================================================================
-- FastSwitch — 顶部菜单栏托盘 + 全局热键（AOC U27U2DS）
--
--   菜单栏图标：FS（点它看状态 / 手动切换 / 测试连接）
--   Cmd + Ctrl + Alt + W    切到 Windows（HDMI2，VCP 18）
--   Cmd + Ctrl + Alt + Shift + R   重载本配置
--
-- 说明：
--   * m1ddc 用绝对路径调用（Hammerspoon 任务不继承交互 shell 的 PATH）。
--   * 原来用 Ctrl+Alt+W，但在这台机器上被其他常驻 App 抢占，故加 Cmd。
--   * macOS 上 m1ddc 的 `get` 读回值可能不准，但 `set` 切换稳定。
-- ============================================================================

pcall(function() hs.ipc = require("hs.ipc") end)

local m1ddc = "/opt/homebrew/bin/m1ddc"
local VCP_HDMI2 = "18"

-- 跑一条 m1ddc 命令并弹窗反馈
local function runM1ddc(args, okMsg, failMsg)
    if hs.fs.attributes(m1ddc) == nil then
        hs.alert("✗ m1ddc 未找到：" .. m1ddc)
        return
    end
    hs.task.new(m1ddc, function(code, out, err)
        if code == 0 then
            hs.alert(okMsg, 1.6)
        else
            local detail = (err and err ~= "") and err or out
            hs.alert(failMsg .. "（code " .. tostring(code) .. "）\n" .. (detail or ""), 4)
        end
    end, args):start()
end

local function switchToWindows()
    runM1ddc(
        { "set", "input", VCP_HDMI2 },
        "✓ 已切到 Windows（HDMI2）",
        "✗ 切到 Windows 失败"
    )
end

-- 不改变任何状态，只探测显示器是否在线
local function testConnection()
    if hs.fs.attributes(m1ddc) == nil then
        hs.alert("✗ m1ddc 未找到", 3)
        return
    end
    hs.task.new(m1ddc, function(code, out, err)
        if code == 0 then
            local trim = out and out:gsub("^%s*(.-)%s*$", "%1") or "(无输出)"
            hs.alert("✓ 显示器在线：\n" .. trim, 4)
        else
            hs.alert("✗ 连不上显示器：\n" .. (err or out or ""), 4)
        end
    end, { "displays" }):start()
end

-- ======================= 顶部菜单栏托盘 =======================
local menubar = hs.menubar.new()
if menubar then
    menubar:setTitle("FS")
    menubar:setTooltip("FastSwitch — 显示器输入切换")

    local function yesno(b) return b and "✓ 是" or "✗ 否" end

    menubar:setMenu(function()
        local m1ok = hs.fs.attributes(m1ddc) ~= nil
        local acc  = hs.accessibilityState()

        return {
            { title = "FastSwitch · 运行中", disabled = true },
            { title = "-" },
            { title = "切换到 Windows   ⌃⌥⌘W", fn = switchToWindows },
            { title = "测试显示器连接",        fn = testConnection },
            { title = "-" },
            {
                title = "状态",
                menu = {
                    { title = "m1ddc：" .. (m1ok and "✓ 就绪" or "✗ 未找到"), disabled = true },
                    { title = "辅助功能权限：" .. yesno(acc), disabled = true },
                    { title = "热键：Cmd+Ctrl+Alt+W", disabled = true },
                    { title = "切换到：Windows / HDMI2", disabled = true },
                }
            },
            { title = "-" },
            { title = "重载配置   ⇧⌃⌥⌘R", fn = function() hs.reload() end },
        }
    end)
end

-- ======================= 全局热键 =======================
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "W", switchToWindows)
hs.hotkey.bind({ "ctrl", "alt", "cmd", "shift" }, "R", function() hs.reload() end)
