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
local switchScript = hs.configdir .. "/fastswitch.sh"
local inputleapd = "/Applications/InputLeap.app/Contents/MacOS/input-leaps"
local inputleapConf = os.getenv("HOME") .. "/input-leap.conf"
local inputleapName = "yitaodeMac-mini.local"

-- Keep the server in Hammerspoon's authorized GUI session.
local function ensureInputLeap()
    local _, listening = hs.execute("/usr/sbin/lsof -nP -iTCP:24800 -sTCP:LISTEN -t")
    if listening then return end
    -- An existing server may still be starting.
    local _, starting = hs.execute("/usr/bin/pgrep -x input-leaps")
    if starting then return end
    hs.execute(string.format(
        '/usr/bin/nohup "%s" --name "%s" --disable-crypto --no-daemon --config "%s" > /tmp/inputleap-server.log 2>&1 < /dev/null &',
        inputleapd, inputleapName, inputleapConf))
end

local switchTask
local function switchToWindows()
    if switchTask then return end
    switchTask = hs.task.new("/bin/bash", function(code, out, err)
        switchTask = nil
        hs.alert(code == 0 and out or (err ~= "" and err or "切换失败"), code == 0 and 1 or 4)
    end, { switchScript, "win" })
    if not switchTask or not switchTask:start() then
        switchTask = nil
        hs.alert("无法启动 " .. switchScript)
    end
end

local function jumpToMac()
    hs.eventtap.keyStroke({ "ctrl", "alt", "cmd" }, "m")
end

-- 不改变任何状态，只探测显示器是否在线
local function testConnection()
    if hs.fs.attributes(m1ddc) == nil then
        hs.alert("✗ m1ddc 未找到", 3)
        return
    end
    hs.task.new(m1ddc, function(code, out, err)
        if code == 0 and out and out:match("%S") then
            local trim = out and out:gsub("^%s*(.-)%s*$", "%1") or "(无输出)"
            hs.alert("✓ 显示器在线：\n" .. trim, 4)
        else
            hs.alert("✗ 连不上显示器：\n" .. (err or out or ""), 4)
        end
    end, { "display", "list" }):start()
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
-- InputLeap handles Ctrl+Alt+Cmd+M even while the client has focus.
hs.hotkey.bind({ "ctrl", "alt", "cmd", "shift" }, "R", function() hs.reload() end)

-- Keep references across Lua garbage collections.
fastSwitchMenu = menubar
ensureInputLeap()
fastSwitchWatchdog = hs.timer.doEvery(10, ensureInputLeap)
