# FastSwitch 现状基线快照（供后续优化使用）

> 快照时间：2026-11-23 21:50（Asia/Shanghai）
> 方案：AOC U27U2DS 双主机共用一套键鼠。Mac 走 USB-C、Windows 走 HDMI2；DDC 切信号源，
> InputLeap 局域网软件 KVM 让键鼠跟随。**未接 USB-A/B 上行线**（用户明确拒绝硬件 USB KVM）。
> 本文为优化前的客观基线，所有进程/版本/连接状态均为实测；优化时请先对照第 8、9 节。

---

## 1. 硬件与网络拓扑

| 角色 | 设备 | 系统 | 计算机名 / 屏幕名 | 网卡 | IP（实测） | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| KVM server | Mac mini M1 (Apple Silicon) | macOS | LocalHostName `yitaodeMac-mini`；ComputerName `弈韬的Mac mini`；hostname `yitaodeMac-mini.local` | en1（en0 无地址） | **192.168.66.91** | DHCP，IP 会漂移；旧地址 `.52` 已释放，不在 ARP 表 |
| KVM client | ASUS 游戏本 YT-ASUS-NB | Windows 11 | `YT-ASUS-NB` | WLAN（另有 VirtualBox `192.168.56.1`） | **192.168.66.99** | 地址较稳定 |
| 显示器 | AOC U27U2DS | — | — | — | — | VCP 18=HDMI2(Win)，27=USB-C(Mac) |
| 键鼠 | LEOBOG HI86 三模键盘 + Logitech MX Master 3 | — | — | — | — | 蓝牙只连 Mac；通道 1=macOS，通道 2=Win11 |

- 网关 `192.168.66.1`；Win ping Mac（.91）通，0% 丢包，RTT 2.8~76ms。
- **关键事实**：Mac 当前 `.91`，但 Win client 与看门狗脚本里写死的仍是旧 `.52`（见第 5、7 节）。

## 2. 软件版本清单（实测）

| 组件 | 版本 | 位置 / 说明 |
| --- | --- | --- |
| InputLeap | `3.0.3-'git-2025-06-13-aac3e88'` | Mac Apple Silicon debug；Win windows-2022-Debug；默认端口 24800 |
| Hammerspoon | `1.1.1` | Mac 内层看门狗宿主 + 全局热键 + FS 菜单栏托盘 |
| m1ddc | brew 安装（/opt/homebrew/bin/m1ddc） | Mac DDC 输入切换 |
| FastSwitch.Tray | .NET 10 / WinForms，发布单文件 `FastSwitch.exe` | Win 托盘 + 全局热键 Ctrl+Alt+M |
| InputLeap 签名（Mac） | adhoc（`flags=0x2(adhoc)`，TeamIdentifier=not set） | 改包内 plist 后已 `codesign --force --deep --sign -` 重签 |

---

## 3. Mac 端现状

### 3.1 进程与连接（实测）

| 项 | 值 |
| --- | --- |
| server 进程 | PID `82241`，启动于 2026-11-20 23:31:36 |
| 监听 | `*:24800` LISTEN（`input-leaps`） |
| 已建立连接 | **无 ESTABLISHED**（Win client 未连上当前 server，原因见第 7 节） |
| Hammerspoon | PID `82222`，启动于 2026-11-20 23:31:34 |
| 外层 launchd 任务 | `com.hammerspoon.watchdog`，`launchctl list` 退出码 0，StartInterval 10，RunAtLoad |
| 看门狗缺失计数 | `/tmp/hs-watchdog-miss.count` = 0 |

### 3.2 关键路径

| 用途 | 路径 |
| --- | --- |
| server 二进制 | `/Applications/InputLeap.app/Contents/MacOS/input-leaps` |
| server 配置 | `/Users/yitao/input-leap.conf` |
| server 日志 | `/tmp/inputleap-server.log`（/tmp 重启/清理后丢失） |
| Hammerspoon 配置 | `/Users/yitao/.hammerspoon/init.lua` |
| 外层看门狗脚本 | `/Users/yitao/hs-watchdog.sh` |
| 外层 launchd plist | `~/Library/LaunchAgents/com.hammerspoon.watchdog.plist` |
| plist 备份 | `/Users/yitao/Info.plist.inputleap.bak` |

### 3.3 server 启动命令（实测可用）

```bash
/Applications/InputLeap.app/Contents/MacOS/input-leaps \
  --name yitaodeMac-mini.local \
  --disable-crypto --no-daemon \
  --config /Users/yitao/input-leap.conf
```

### 3.4 server 配置文件 `~/input-leap.conf`

```ini
section: screens
  yitaodeMac-mini.local:
  YT-ASUS-NB:
end

section: links
  yitaodeMac-mini.local:
    right = YT-ASUS-NB
  YT-ASUS-NB:
    left = yitaodeMac-mini.local
end
```

### 3.5 Info.plist 加固（2026-11-20 落地，根因修复）

| 键 | 值 | 作用 |
| --- | --- | --- |
| `NSSupportsAutomaticTermination` | `false` | 禁止 AppKit 自动终止（TAL quiet auto-quit） |
| `NSSupportsAppNap` | `false` | 禁止 App Nap 空闲降频 |
| `LSUIElement` | `true` | 后台代理进程，无 Dock 图标 |

> 背景：server 曾在内存压力下被 AppKit TAL 静默退出（`applicationShouldTerminate:` 返回 YES）。
> 加固后新进程日志标志 `WouldBeTerminatedByTALKey=0`。**InputLeap 升级/覆盖安装会还原此 plist，需重做。**

### 3.6 自启与睡眠

- 登录项：`DockX, uTools, Snug, Hammerspoon`（Hammerspoon 开机自启，加载时 `ensureInputLeap()` 拉起 server）。
- 电源策略：`sleep=0`、`displaysleep=0`、`disksleep=0`（不睡、显示器不灭）。

### 3.7 双层看门狗架构

- **内层 Hammerspoon**（`init.lua`）：每 10s `lsof -iTCP:24800 -sTCP:LISTEN` 探端口；空则 `hs.execute nohup` 拉起 server。
- **外层 launchd**（`hs-watchdog.sh`）：每 10s 调用；Hammerspoon 不在则 `open -a Hammerspoon`；端口连续 3 次（约 30s）缺失判定内层定时器假活，`killall Hammerspoon` → `open -a Hammerspoon`，由新 Hammerspoon 重新拉起 server。

---

## 4. Windows 端现状

### 4.1 进程与连接（实测）

| 项 | 值 |
| --- | --- |
| client 进程 | PID `23208`，启动于 2026/11/21 0:21:23 |
| client 命令行 | `input-leapc.exe --name YT-ASUS-NB --disable-crypto --restart --no-tray 192.168.66.52:24800` |
| 连接 1 | `192.168.66.99:13104 → 192.168.66.52:24800 ESTABLISHED`（PID 23208，旧连接僵死） |
| 连接 2 | `192.168.66.99:13105 → 192.168.66.52:24800 SYN_SENT`（PID 20464，重试失败） |
| 看门狗计划任务 | `InputLeap Client Watchdog`，State=Running；AtLogOn 触发 |
| 托盘进程 | `FastSwitch` PID `29672`，启动于 2026/11/21 0:22:11 |

### 4.2 关键路径

| 用途 | 路径 |
| --- | --- |
| client 二进制 | `%LOCALAPPDATA%\Programs\InputLeap\input-leapc.exe` |
| Win 看门狗脚本 | `%LOCALAPPDATA%\Programs\InputLeap\watchdog.ps1` |
| 仓库工作区 | `D:\Code\FastSwitch` |

### 4.3 Win 看门狗脚本 `watchdog.ps1`（现状，硬编码旧 IP）

```powershell
$exe = "$env:LOCALAPPDATA\Programs\InputLeap\input-leapc.exe"
$clientArgs = "--name YT-ASUS-NB --disable-crypto --restart --no-tray 192.168.66.52:24800"
while ($true) {
    $p = Get-Process -Name "input-leapc" -ErrorAction SilentlyContinue
    if (-not $p) {
        Start-Process -FilePath $exe -ArgumentList $clientArgs -WindowStyle Hidden
    }
    Start-Sleep 10
}
```

> 注意：只检测**进程是否存在**，不检测连接是否存活；进程在但连接僵死时不会重启。

### 4.4 SSH 远程管理链路（2026-11-23 落地，Mac → Win）

定位：双主机跨机管理补充通道，**局域网内仅公钥**，供 Mac 免密登录 Win 执行命令 / SFTP。

| 项 | 值 |
| --- | --- |
| Win 服务端 | 系统组件 `OpenSSH.Server` 9.5p1（微软编译），二进制 `C:\Windows\System32\OpenSSH\sshd.exe` |
| 服务 | `sshd` Running / Automatic / LocalSystem；`ssh-agent` Stopped / Manual |
| 监听 | `0.0.0.0:22`、`[::]:22` 双栈 |
| 认证 | 仅 `publickey`；`PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`ChallengeResponseAuthentication no` |
| 防火墙规则 | `OpenSSH-Server-LAN`：入站 Allow，TCP 22，RemoteAddress `192.168.66.0/24`，Profile Any |
| Win 公钥文件 | `C:\ProgramData\ssh\administrators_authorized_keys`（my 属管理员组，管理员公钥不走用户目录 `.ssh\authorized_keys`） |
| 主机密钥 | `C:\ProgramData\ssh\ssh_host_{rsa,ecdsa,ed25519}_key`；Owner=`BUILTIN\Administrators`，ACL 仅 `SYSTEM` / `Administrators` FullControl |
| Mac 别名 | `win-nb` → `192.168.66.99:22`，User `my` |
| Mac 专用密钥 | `~/.ssh/yt-asus-nb_ed25519`（无口令，不复用既有 github/id_ed25519 等密钥）；公钥 fingerprint `SHA256:onGR9KUizMX7ifl9DcbD3W16V3NM+0Qfs13zFPTIGfg` |
| 实测 | `ssh win-nb` 返回 `yt-asus-nb\my` / `YT-ASUS-NB`；SFTP 子系统可用（`/C:/Users/my`）；服务端 `Authentications that can continue: publickey` |

**踩坑结论（优化时勿回退）：**

1. 本机系统组件通道一度 `NotPresent`（CBS `0x800F0984`，组件存储缺 `wcnagent.dll`）；便携 GitHub 包 10.4.0.0p1-Preview 在 LocalSystem 下 `sshd-auth.exe` 退出 `0xC0000135` 无法完成认证，最终系统组件落地后改用 `System32\OpenSSH` 自带 9.5p1 单体二进制，服务化正常。
2. 主机私钥 **Owner 必须是 `Administrators`/`SYSTEM`**；若 Owner 为普通用户 `my`，sshd 以 LocalSystem 启动时判 `bad permissions` → `no hostkeys available -- exiting`。
3. 管理员账户公钥必须放 `administrators_authorized_keys`，该文件 ACL 仅 SYSTEM/Administrators；放用户目录会被 sshd 忽略。
4. Win WLAN IP 走 DHCP，别名写死 `.99`；若漂移需同步改 `~/.ssh/config` 的 `win-nb` HostName。`OpenSSH.Client` 未装，Win 本机无 `ssh.exe` 客户端。

### 4.5 Win 看门狗新版部署（2026-11-23 落地，替代 4.3 旧版）

定位：把写死旧 `.52`、只看进程的旧看门狗，换成**按 mDNS 主机名解析 + 连接存活探测 + 断线重连**的新版；经已打通的 SSH（`win-nb`）从 Mac 推送部署。

| 项 | 值（实测） |
| --- | --- |
| 脚本位置（Win） | `%LOCALAPPDATA%\Programs\InputLeap\watchdog.ps1`（仓库 `windows/watchdog.ps1`） |
| 计划任务 | `InputLeap Client Watchdog`，State=Running；主体 `my` / Interactive / Limited；AtLogOn 触发；`ExecutionTimeLimit=PT0S`（无时限） |
| 任务动作 | `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "<dest>\watchdog.ps1" -Server "yitaodeMac-mini.local"` |
| 解析目标 | `-Server yitaodeMac-mini.local`（mDNS 主机名，不再写死 IP）；实测解析到 `192.168.66.91` |
| 守护周期 | 每 5s 一轮；同会话、同路径的 `input-leapc.exe`；查 ESTABLISHED 到解析地址 `:24800` |
| 重连策略 | 有活跃连接则清理冗余实例；无进程立即重启；进程在但连续 3 轮未活跃则杀进程重启 |
| client 参数 | `--name YT-ASUS-NB --disable-crypto --restart --no-tray <addr>:24800`（地址为位置参数） |

**部署命令（脚本所在目录，PowerShell 5.1）：**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\watchdog.ps1 -Install
```

**踩坑结论（勿回退）：**

- Windows 上 .NET `[Net.Dns]::GetHostAddresses("*.local")` 对 mDNS 只返回链路本地 IPv6（`fe80::...%8`），**丢弃 A 记录**；而 `Resolve-DnsName -Name <host>.local -Type A` 能稳定取到 IPv4。脚本 `Resolve-ServerIPv4` 改为 `Resolve-DnsName -Type A` 优先、`GetHostAddresses` 回退。
- 安装前先停旧任务、清掉僵死 client，避免旧实例占用；`-Install` 内部会先校验主机名可解析再替换运行中的看门狗。

**真机验证（本轮）：**

- 首轮拉起 client PID `12424`，ESTABLISHED `192.168.66.99:12480 → 192.168.66.91:24800`。
- 手动杀掉 `12424` 后，看门狗自动拉起新 client PID `13992`，重连 ESTABLISHED `192.168.66.99:1551 → 192.168.66.91:24800`。
- **尚未验收**：键鼠实际穿透交接（光标跨屏、键盘鼠标跟随）与双机切换耗时，需物理键鼠 + DDC 切画面人工实测；网络链路与看门狗守护已验证通过。

---

## 5. 仓库与版本控制状态

远端：`https://github.com/ra1nzzz/FastSwitch.git`，分支 `main`。

| 端 | 工作区 | HEAD | 状态 | 与远端 |
| --- | --- | --- | --- | --- |
| Mac | `/Volumes/macOS Tahoe - Data/Users/yitao/FastSwitch` | `ce6ab5a` | 干净 | 已同步 origin/main |
| Win | `D:\Code\FastSwitch` | `a390d9a` | 干净 | **落后 Mac 2 个提交** |

### Mac 仓库文件（已入库）

```
README.md
mac/fastswitch.sh
mac/切到 Windows.command
mac/hammerspoon-init.lua
mac/hs-watchdog.sh
mac/com.hammerspoon.watchdog.plist
mac/INPUTLEAP.md
windows/MonitorInput.ps1
windows/README-Windows.md
windows/SwitchToMac.bat
windows/SwitchToMac.ps1
windows/FastSwitch.Tray/（Program.cs、csproj、manifest、ico 等）
```

### 版本控制缺口（优化时需补）

- Win 工作区缺少 Mac 侧新增的 `mac/hs-watchdog.sh`、`mac/com.hammerspoon.watchdog.plist`、`mac/INPUTLEAP.md`（落后提交所致）。
- Win `watchdog.ps1` **未纳入仓库**，仅存在于 `%LOCALAPPDATA%\Programs\InputLeap\`。
- Win 托盘 `bin/obj/publish` 构建产物已被 `.gitignore` 覆盖、未跟踪，无需处理。

---

## 6. 配置与环境关键值

| 项 | Mac | Win |
| --- | --- | --- |
| 屏幕名 / `--name` | `yitaodeMac-mini.local` | `YT-ASUS-NB` |
| 端口 | 24800 | 24800 |
| 加密 | `--disable-crypto` | `--disable-crypto` |
| 前台常驻 | `--no-daemon` | — |
| 自动重连 | — | `--restart` |
| 托盘 | `--no-tray`（Win） | — |

---

## 7. 当前连通性判定（实测证据）

- Mac server 在 `24800` LISTEN，但 lsof 无来自 `.99` 的 ESTABLISHED。
- Win 侧两条到 `.52:24800` 的连接：一条僵死 ESTABLISHED、一条 SYN_SENT 重试；ARP 表中 `.52` 已不存在（旧 Mac IP 释放），`.91` 才是当前 Mac。
- **结论**：当前键鼠跟随链路**未连通**。直接原因是 Win client / 看门狗写死旧 Mac IP `.52`，Mac DHCP 漂移到 `.91` 后无法建立新连接；旧 ESTABLISHED 是漂移前留下的僵死连接。
- 修复方向（候选，未实施）：
  1. 用 mDNS 主机名 `yitaodeMac-mini.local:24800` 替代硬编码 IP（InputLeap 是否解析 mDNS 需实测）；
  2. 或 Mac 侧绑静态 IP / 路由器做 DHCP 地址保留；
  3. Win 看门狗增加连接存活探测（端口 ESTABLISHED / 协议握手），僵死时重启 client；
  4. 先手动把 client 指向 `.91:24800` 验证链路恢复。

---

## 8. 已知问题与优化候选（按优先级）

| 优先级 | 问题 | 现象 / 证据 | 候选方向 |
| --- | --- | --- | --- |
| P0 | Mac IP DHCP 漂移，client 写死旧 `.52` | 见第 7 节，链路未连通 | mDNS 主机名 / 静态 IP / DHCP 保留；双端配置抽离到一份可维护清单 |
| P0 | Win 看门狗只看进程、不看连接 | 进程在但连接僵死不重启 | 增加 `netstat`/TCP 探测，僵死即杀进程重启；client 目标地址可动态解析 |
| P1 | Win 仓库落后 Mac，看门狗脚本未入库 | 第 5 节 | 同步提交；把 `watchdog.ps1`、计划任务注册方式纳入版本控制与部署文档 |
| P1 | InputLeap 升级还原 plist 加固 | 第 3.5 节 | 加固步骤脚本化（重签命令入库），升级后一键复核 |
| P2 | Win 托盘 Ctrl+Alt+M 只切 DDC，未联动 InputLeap | 遗留功能项 | 切回 Mac 时联动把键鼠切回 server 侧 |

## 9. 不可违背的架构约束（实测踩坑结论，优化时勿回退）

1. **server 必须由已授权的常驻 Aqua 应用 Hammerspoon 用 `hs.execute nohup` 拉起**；launchd 直接 fork `input-leaps` 会 FATAL「assistive devices does not trust this process」秒退；`launchctl asuser` 嵌套拉起同样救不回。
2. 双端必须 `--disable-crypto`；否则 TCP 握手成功但 InputLeap 协议 SSL 握手卡住，client 超时。
3. server 必须 `--no-daemon`（前台常驻），否则 daemon fork 脱离管控、掩盖真实 FATAL。
4. `--name` 必须显式对齐配置文件屏幕名，否则 links 邻接静默失效且日志不报错。
5. Win client 的 server 地址是**位置参数**，不能写成 `--server=host:port`（unrecognized option）；`--name` 用空格不用等号。
6. 存活判定**按 `lsof -tiTCP:24800 -sTCP:LISTEN` 取 PID**；lsof COMMAND 列按 8 字符截断成 `input-lea`，禁止 `grep input-leaps` 全名匹配（会永远计数 0）。
7. 辅助功能信任只能从已授权的 Hammerspoon 继承；`hs.task` 异步拉起子进程无图形会话会秒退。
8. 用户明确**不接 USB-A/B 上行线**；优化路线限定在软件 KVM + DDC 范畴。

## 10. 遗留与已知不优化项

- **鼠标闪烁**：Mac Retina HDPI 与 Win 1x DPI 不一致 + 局域网延迟；Win 鼠标加速已关（MouseSpeed=0, Threshold1/2=0）。已知现状，暂不优化。
- **jetsam OOM 回收**：plist 加固只挡 AppKit 主动退出；极端内存压力下的 jetsam 强杀挡不住，需另查内存占用。
- v3.0.3 debug 版不认 `hotkeys` section；切屏热键用内置 `Ctrl+Alt+Shift`。

---

## 11. 关键命令速查

### Mac

```bash
cd "/Volumes/macOS Tahoe - Data/Users/yitao/FastSwitch"
pgrep -x input-leaps                                  # server PID
lsof -iTCP:24800 -P -n                                # LISTEN / ESTABLISHED
pgrep -x Hammerspoon
launchctl list | grep hammerspoon.watchdog
tail -f /tmp/inputleap-server.log
m1ddc set input 18      # 切 Windows（HDMI2）
m1ddc set input 27      # 切 Mac（USB-C）
ssh win-nb              # 免密登录 Win（仅公钥，别名见 ~/.ssh/config）
sftp win-nb
git status && git push origin main
```

### Windows（PowerShell）

```powershell
Get-Process input-leapc
netstat -ano | Select-String 24800
Get-ScheduledTask -TaskName "InputLeap Client Watchdog"
& "$env:LOCALAPPDATA\Programs\InputLeap\input-leapc.exe" `
  --name YT-ASUS-NB --disable-crypto --restart --no-tray 192.168.66.91:24800
Get-Service sshd,ssh-agent
Get-NetTCPConnection -State Listen -LocalPort 22
Get-NetFirewallRule -Name "OpenSSH-Server-LAN" | Get-NetFirewallAddressFilter
```
