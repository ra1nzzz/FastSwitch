-- ============================================================================
-- FastSwitch — 顶部菜单栏托盘 + 全局热键（AOC U27U2DS）+ InputLeap KVM
--
--   菜单栏图标：FS（点它看状态 / 手动切换 / 测试连接）
--   Cmd + Ctrl + Alt + W    切到 Windows（HDMI2，VCP 18），鼠标自动穿过去
--   Cmd + Ctrl + Alt + M    鼠标跳回 Mac（InputLeap 热键）
--   Cmd + Ctrl + Alt + Shift + R   重载本配置
-- ============================================================================

pcall(function() hs.ipc = require("hs.ipc") end)

local m1ddc = "/opt/homebrew/bin/m1ddc"
local VCP_HDMI2 = "18"
local VCP_USBC  = "27"
local inputleapd = "/Applications/InputLeap.app/Contents/MacOS/input-leaps"
local inputleapConf = "/Users/yitao/input-leap.conf"
local inputleapName = "yitaodeMac-mini.local"

-- 检测 server 是否存活：端口 24800 在 LISTEN 才算活
local function isServerAlive()
    local out = hs.execute("lsof -iTCP:24800 -sTCP:LISTEN 2>/dev/null", true)
    return out ~= nil and out ~= ""
end

-- 启动 server（先杀残留，再启动）
-- 注意：必须由 Hammerspoon（已授权的常驻 Aqua 应用）拉起，辅助功能信任才可继承；
--       直接由 launchd 拉起会 FATAL「assistive devices does not trust this process」。
--       --no-daemon 强制前台常驻，避免 daemon fork 脱离管控、掩盖报错。
local function startServer()
    -- 按端口取 PID 清理残留（进程名会被 lsof/pkill 截断，不用 -x 全名匹配）
    hs.execute("for p in $(/usr/sbin/lsof -tiTCP:24800 2>/dev/null); do kill -9 $p 2>/dev/null; done")
    hs.execute(string.format(
        'nohup %s --name %s --disable-crypto --no-daemon --config %s > /tmp/inputleap-server.log 2>&1 &',
        inputleapd, inputleapName, inputleapConf))
end

-- 确保 InputLeap server 在跑
local function ensureInputLeap()
    if not isServerAlive() then
        startServer()
        hs.alert("✓ InputLeap server 已启动", 1.5)
    end
end
ensureInputLeap()

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

-- 切到 Windows：先切 DDC，再把鼠标移到右边缘让 InputLeap 穿过去
local function switchToWindows()
    runM1ddc(
        { "set", "input", VCP_HDMI2 },
        "✓ 已切到 Windows（HDMI2）",
        "✗ 切到 Windows 失败"
    )
    -- 等显示器切换后，鼠标移到最右边缘，InputLeap 会自动穿到 Windows
    hs.timer.doAfter(2.5, function()
        local scr = hs.screen.primaryScreen()
        local f = scr:fullFrame()
        hs.mouse.setAbsolutePosition({ x = f.x + f.w - 1, y = f.y + f.h / 2 })
    end)
end

-- 鼠标跳回 Mac 屏幕中心
local function jumpToMac()
    local scr = hs.screen.primaryScreen()
    local f = scr:fullFrame()
    hs.mouse.setAbsolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
    hs.alert("✓ 鼠标已回到 Mac", 1)
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
            { title = "鼠标跳回 Mac     ⌃⌥⌘M", fn = jumpToMac },
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
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "M", jumpToMac)
hs.hotkey.bind({ "ctrl", "alt", "cmd", "shift" }, "R", function() hs.reload() end)

-- ======================= 看门狗：每 10s 检测 server =======================
hs.timer.doEvery(10, function()
    local out = hs.execute("/usr/sbin/lsof -iTCP:24800 -sTCP:LISTEN 2>/dev/null", true)
    if not out or out == "" then
        startServer()
        hs.alert("✓ InputLeap 看门狗拉起", 1)
    end
end)

-- ======================= 输入源自动检测：切回 Mac 时自动拉鼠标 =======================
local lastInput = VCP_USBC  -- 初始假设在 Mac
hs.timer.doEvery(2, function()
    local out = hs.execute(m1ddc .. " get input 2>/dev/null", true)
    if out then
        out = out:gsub("^%s*(.-)%s*$", "")
        -- 从 Windows(18) 切回 Mac(27)，自动拉鼠标回中心
        if lastInput == VCP_HDMI2 and out == VCP_USBC then
            hs.timer.doAfter(1, function()
                local scr = hs.screen.primaryScreen()
                local f = scr:fullFrame()
                hs.mouse.setAbsolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
            end)
        end
        lastInput = out
    end
end)
