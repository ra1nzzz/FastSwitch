-- ============================================================================
-- Hammerspoon configuration for FastSwitch
--
-- Install Hammerspoon (macOS global hotkey daemon):
--     brew install --cask hammerspoon
--
-- Copy this file to ~/.hammerspoon/init.lua:
--     mkdir -p ~/.hammerspoon
--     cp mac/hammerspoon-init.lua ~/.hammerspoon/init.lua
--
-- Then launch Hammerspoon once and grant Accessibility permission when prompted
-- (System Settings -> Privacy & Security -> Accessibility -> toggle Hammerspoon).
--
-- Hotkeys:
--   Ctrl + Alt + W          Switch monitor input to Windows (HDMI2, VCP 18)
--   Ctrl + Alt + Cmd + R    Reload the Hammerspoon config
--
-- Tip: enable "Launch Hammerspoon at login" in its menu so the hotkey survives
-- restarts.
-- ============================================================================

pcall(function()
    hs.ipc = require("hs.ipc")
end)

-- Locate m1ddc (Apple Silicon Homebrew, then Intel Homebrew).
local m1ddc = "/opt/homebrew/bin/m1ddc"
if hs.fs.attributes(m1ddc) == nil then
    m1ddc = "/usr/local/bin/m1ddc"
end
local VCP_HDMI2 = "18"

local function runM1ddc(args, okMessage, failMessage)
    if hs.fs.attributes(m1ddc) == nil then
        hs.alert("m1ddc not found: brew install m1ddc")
        return
    end

    local task = hs.task.new(m1ddc, function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.alert(okMessage, 1.5)
        else
            local detail = (stdErr and stdErr ~= "") and stdErr or stdOut
            hs.alert(failMessage .. " (code " .. tostring(exitCode) .. ")\n" .. (detail or ""), 4)
        end
    end, args)
    task:start()
end

local function switchToWindows()
    runM1ddc(
        { "set", "input", VCP_HDMI2 },
        "已切换到 Windows（HDMI2）",
        "切换到 Windows 失败"
    )
end

hs.hotkey.bind({ "ctrl", "alt" }, "W", switchToWindows)

hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "R", function()
    hs.reload()
end)

hs.alert("FastSwitch 已加载：Ctrl+Alt+W 切到 Windows", 2)
