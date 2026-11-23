# InputLeap 软件 KVM 部署与防掉线加固（macOS server / Windows client）

双主机共用一套蓝牙键鼠（键盘只连 Mac，鼠标 MX Master 3 走蓝牙），不接 USB-A/B 上行线，
通过局域网让键鼠在切信号源时跟随另一台主机。基于 [InputLeap](https://github.com/input-leap/input-leap)（Barrier fork）v3.0.3。

- **Mac mini M1 = server**，DHCP 地址，客户端使用主机名，屏幕名 `yitaodeMac-mini.local`
- **Win11 笔记本 = client**，IP `192.168.66.99`，计算机名 `YT-ASUS-NB`
- 默认端口 `24800`，双端必须 `--disable-crypto`（debug 版加密握手有兼容问题）

> 配套 DDC 信号切换见根目录 [README.md](../README.md)：Mac→Win 用 `m1ddc set input 18`，
> Win→Mac 走 `windows/SwitchToMac.ps1` 时序。本文只讲键鼠跟随链路。

---

## 1. 安装与二进制位置

| 端 | 版本 | 二进制 |
| --- | --- | --- |
| macOS | Apple Silicon debug | `/Applications/InputLeap.app/Contents/MacOS/input-leaps` |
| Windows | windows-2022-Debug | `%LOCALAPPDATA%\Programs\InputLeap\input-leapc.exe` |

brew cask 无包，从 GitHub release 手动下载对应 debug 版。**GUI 版双端都卡在"正在启动"、不监听 24800，必须用包内命令行二进制。**

### Mac server 启动命令

```bash
/Applications/InputLeap.app/Contents/MacOS/input-leaps \
  --name yitaodeMac-mini.local \
  --disable-crypto \
  --no-daemon \
  --config /Users/yitao/input-leap.conf
```

- `--name` 必须显式对齐配置文件里的屏幕名，否则 links 邻接静默失效（日志不报错）。
- `--no-daemon`（即 `-f`）强制前台常驻；默认 `--daemon` 会 fork 脱离管控并掩盖真实 FATAL。
- 日志：`/tmp/inputleap-server.log`（/tmp 重启或清理后会丢）。

### Win client 启动命令

```powershell
input-leapc.exe --name YT-ASUS-NB --disable-crypto --restart --no-tray yitaodeMac-mini.local:24800
```

- server 地址是**位置参数**，不能写成 `--server=yitaodeMac-mini.local:24800`（unrecognized option）。
- `--restart` 掉线后自动重连；`--name` 用空格分隔不用等号。

### Mac 配置文件 `/Users/yitao/input-leap.conf`

使用仓库的 [input-leap.conf](./input-leap.conf)。脚本通过 Ctrl+Alt+Cmd+J 请求将键鼠交给 Win11，Ctrl+Alt+Cmd+M 将键鼠送回 Mac。配置放入 `~/input-leap.conf` 后，运行 `pkill -TERM -x input-leaps` 由 Hammerspoon 看门狗重新拉起服务。屏幕名必须与两端启动参数一致。

---

## 2. macOS 防自动终止加固（反复掉线的根因修复）

### 2.1 现象与根因

server 长跑一段时间后进程与 24800 监听全部丢失。系统日志定位到退出链路：

```
AutomaticTermination ... Memory pressure. Attempting termination.
_terminateOnMemoryPressureFromMainRunLoopPerformBlock canAutoQuitQuietly=1 ... Terminating!
Asking app delegate whether applicationShouldTerminate:
replyToApplicationShouldTerminate:YES
App termination approved → Termination commencing → Termination complete
```

**根因**：`input-leaps` 是无窗口后台应用，Info.plist 默认允许 AppKit 在**内存压力**下做
TAL（后台自动退出，quiet auto-quit）回收；应用 delegate 对 `applicationShouldTerminate:` 返回 YES，于是被静默退出。

旧实例日志里 `_kLSApplicationWouldBeTerminatedByTALKey=1`（允许被 TAL 终止）。

### 2.2 修复：在 Info.plist 加三个键并 adhoc 重签

应用是 adhoc / linker-signed、TeamIdentifier=not set，改包内文件后需重签。

```bash
APP=/Applications/InputLeap.app
# 1. 备份原 plist（移出 .app 包，避免纳入签名范围）
cp "$APP/Contents/Info.plist" ~/Info.plist.inputleap.bak

# 2. 写入禁用键
P="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSSupportsAutomaticTermination bool false" "$P"
/usr/libexec/PlistBuddy -c "Add :NSSupportsAppNap bool false" "$P"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$P"

# 3. adhoc deep 重签（含 PlugIns 下的 dylib）
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
```

| 键 | 值 | 作用 |
| --- | --- | --- |
| `NSSupportsAutomaticTermination` | `false` | 禁止 AppKit 自动终止（TAL quiet auto-quit） |
| `NSSupportsAppNap` | `false` | 禁止 App Nap 空闲降频 |
| `LSUIElement` | `true` | 作为后台代理进程（无 Dock 图标），符合 server 形态 |

### 2.3 验证是否生效

重启 server 后查系统日志，新实例的 TAL 标志应为 **0**（旧实例为 1）：

```bash
log show --predicate 'process == "input-leaps"' --last 5m \
  | grep -iE "TALKey|should terminate|termination approved"
# 期望：_kLSApplicationWouldBeTerminatedByTALKey=0；不再出现 termination approved
```

> 注意：内存压力下还有一套 jetsam 内存回收（plist 挡不住），若长期仍被强杀需另查内存占用；
> 本修复针对的是 AppKit 主动 `applicationShouldTerminate:` 退出链路。

---

## 3. 双层看门狗架构

辅助功能（AX）信任只能从已授权的常驻 Aqua 应用 Hammerspoon 继承；**launchd 直接 fork `input-leaps`
会 FATAL `assistive devices does not trust this process` 秒退**，`launchctl asuser` 嵌套拉起同样救不回。
因此采用两层保活：

### 内层：Hammerspoon 定时器（`~/.hammerspoon/init.lua`）

- 每 10 秒检查监听端口和进程。服务缺失时由 Hammerspoon 拉起，已有进程启动期间等待下一次检查。
- 切换时单独检查已建立连接和 InputLeap 焦点日志。

### 外层：launchd 兜底（`mac/com.hammerspoon.watchdog.plist` + `mac/hs-watchdog.sh`）

- 每 10s 调用一次脚本；Hammerspoon 进程不在则 `open -a Hammerspoon` 拉起。
- 端口连续 **3 次**（约 30s）无 LISTEN，判定内层定时器假活（进程在但 timer 死了），
  `killall Hammerspoon` → `open -a Hammerspoon`，由新 Hammerspoon 加载时的 `ensureInputLeap()` 重新拉起 server。
- 缺失计数落在 `/tmp/hs-watchdog-miss.count`，避免启动窗口期抖动误重启。

### Win client 看门狗

从 Windows 仓库根目录运行以下命令。它会检查 Mac 名称解析、替换当前用户的 `InputLeap Client Watchdog` 登录任务并立即启动。默认按 Mac 主机名解析 IPv4，连续三次检查未找到匹配地址的客户端连接时重新启动客户端。若局域网无法解析 .local，可在路由器为 Mac 保留 DHCP 地址，并在安装命令末尾加 `-Server 保留的IPv4地址`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\watchdog.ps1 -Install
```

### 部署外层 launchd 任务

```bash
cp mac/com.hammerspoon.watchdog.plist ~/Library/LaunchAgents/
cp mac/hs-watchdog.sh ~/hs-watchdog.sh && chmod +x ~/hs-watchdog.sh
launchctl unload ~/Library/LaunchAgents/com.hammerspoon.watchdog.plist
launchctl load   ~/Library/LaunchAgents/com.hammerspoon.watchdog.plist
launchctl list | grep hammerspoon.watchdog
```

---

## 4. 已验证做不通 / 已验证有效

| 结论 | 说明 |
| --- | --- |
| ❌ GUI 版 input-leap | 卡"正在启动"，不监听 24800 |
| ❌ launchd KeepAlive 直管 server | FATAL 辅助功能不信任，秒退 |
| ❌ launchd 脚本里 `asuser` 嵌套拉起 | 同样秒退，信任链不成立 |
| ❌ `--server=` 写法 | unrecognized option，地址必须是位置参数 |
| ❌ crontab 拉起 | seteuid 权限错误 |
| ❌ `hs.task` 异步拉起子进程 | 无图形会话，秒退 |
| ✅ 命令行二进制 + Hammerspoon `hs.execute nohup` | 继承 AX 信任，稳定常驻 |
| ✅ 双端 `--disable-crypto` | 加密握手兼容问题，必须关 |
| ✅ 缩进 links 语法 + `--name` 对齐 | 邻接才生效 |
| ✅ `lsof -ti` 端口 PID 判定 + `--no-daemon` 前台常驻 | 存活判定准确、报错可见 |
| ✅ Win client `--restart` | 掉线自动重连 |

---

## 5. 日常排查命令

### Mac

```bash
pgrep -x input-leaps                                   # server PID
lsof -iTCP:24800 -P -n                                 # 监听 + 已建立连接（ESTABLISHED 到 .99 即 Win 在线）
pgrep -x Hammerspoon                                   # 内层看门狗宿主
launchctl list | grep -iE 'hammerspoon|inputleap'      # 外层任务
tail -f /tmp/inputleap-server.log                      # server 日志
log show --predicate 'process == "input-leaps"' --last 10m | grep -i terminat
```

### Windows

```powershell
Get-Process input-leapc
netstat -ano | Select-String 24800
Get-ScheduledTask -TaskName "InputLeap Client Watchdog"
```

### 已知遗留（不再优化）

- 鼠标闪烁：Mac Retina HDPI 与 Win 1x DPI 不一致 + 局域网延迟；Win 鼠标加速已关（MouseSpeed=0, Threshold1/2=0）。
- Win 端 `FastSwitch.Tray`（Ctrl+Alt+M）与 PowerShell 入口均在断开 HDMI 后结束当前会话的 InputLeap 客户端，使 server 收回键鼠。Windows 登录看门狗会重新连接。手动恢复时可按 Ctrl+Alt+Cmd+M 将键鼠交还 Mac。

### 2026-11-24 双机验收记录

- 客户端 TCP 已连接时，Hammerspoon 的普通模拟按键未触发 InputLeap 的交接日志。旧路径两次分别在 2.03 秒、1.87 秒报错退出，均停在 HDMI 写入之前。
- 改为从已授权的 Hammerspoon 发送 HID 事件，并让服务日志即时刷新。00:07:24 日志确认进入 YT-ASUS-NB，随后 HDMI2 写入返回 18。正向脚本用时 0.61 秒，未测面板点亮时间。
- 00:11:03 客户端连接关闭，Mac server 记录进入本机并显示光标。00:11:06 Win 看门狗启动的客户端重新连上。反向流程保留 12 秒 USB-C 稳定等待。
- Mac 当天未能解析 YT-ASUS-NB.local。SSH 继续使用 win-nb 的 IPv4 配置，建议在路由器为笔记本保留当前地址。
