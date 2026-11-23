# FastSwitch — 交接给 Codex 的连接参数与遗留清单

> 更新时间：2026-11-23。方案：AOC U27U2DS 双主机软件 KVM（InputLeap 键鼠共享 + DDC 切信号源），不接 USB-A/B 上行线。
> 基线事实见 `STATUS.md`；本文只列「怎么连上 Win」和「待解决遗留」。

---

## 1. 环境快照（实测）

| 角色 | 设备 | 系统 | 屏幕名 / 计算机名 | IP（当前，DHCP 会漂移） |
| --- | --- | --- | --- | --- |
| KVM server | Mac mini M1 | macOS | `yitaodeMac-mini.local` | 192.168.66.91 |
| KVM client | ASUS 游戏本 | Windows 11 | `YT-ASUS-NB` | 192.168.66.99 |

- Mac 工作区：`/Volumes/macOS Tahoe - Data/Users/yitao/FastSwitch`（与 origin/main 同步，HEAD `9a358aa`）
- Win 工作区：`D:\Code\FastSwitch`（git 可用，HEAD `a390d9a`，**落后 main**，工作区干净）
- InputLeap 默认端口 24800；双端 `--disable-crypto`。

## 2. SSH 远程连接（Mac → Win，仅公钥，局域网）

### 2.1 最简用法（已在 Mac `~/.ssh/config` 登记别名）

```bash
ssh win-nb                 # 免密登录 Win，用户 my
ssh win-nb 'powershell -NoProfile -Command "Get-Process input-leapc"'
scp ./watchdog.ps1 win-nb:/C:/Users/my/AppData/Local/Programs/InputLeap/watchdog.ps1
```

### 2.2 展开后的连接参数（供 Codex 远程后端 / 配置项填写）

| 字段 | 值 |
| --- | --- |
| Host / HostName | `192.168.66.99`（DHCP，漂移后需更新） |
| Port | `22` |
| Username | `my`（管理员，微软账户登录） |
| 认证方式 | `publickey`（唯一；密码 / 键盘交互 / 挑战响应均已关闭） |
| Private key | `/Users/yitao/.ssh/yt-asus-nb_ed25519`（权限 600，无口令） |
| 公钥 fingerprint | `SHA256:onGR9KUizMX7ifl9DcbD3W16V3NM+0Qfs13zFPTIGfg` |
| 公钥部署位置（Win） | `C:\ProgramData\ssh\administrators_authorized_keys`（ACL 仅 SYSTEM / Administrators） |
| 防火墙 | 规则 `OpenSSH-Server-LAN`：入站 TCP 22，远程地址 `192.168.66.0/255.255.255.0` |

不依赖 ssh config 的显式命令：

```bash
ssh -i /Users/yitao/.ssh/yt-asus-nb_ed25519 \
  -o IdentitiesOnly=yes -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no -p 22 my@192.168.66.99
```

### 2.3 给 Codex 的注意事项

- **私钥只在 Mac 本机**。若 Codex 运行在这台 Mac 上，直接用上面别名 / 命令即可。
- 若 Codex 跑在**另一台机器或容器**：不能复用该私钥；需在那台机器新生成 ed25519 密钥对，把新公钥追加到 Win `C:\ProgramData\ssh\administrators_authorized_keys`（Owner 须为 Administrators，ACL 仅 SYSTEM/Admin）。
- Win 本机**没有 `ssh.exe` 客户端**（`OpenSSH.Client` 未安装）；SSH 只做 Mac→Win 入站方向。
- 经 ssh 传 PowerShell 命令时，复杂脚本先 `scp` 上传到 Win 再执行，避免多层引号转义问题；简单命令用 `ssh win-nb 'powershell -NoProfile -Command "..."'`。
- 服务端是系统组件 OpenSSH 9.5p1（`C:\Windows\System32\OpenSSH\sshd.exe`），服务 `sshd` Running / Automatic / LocalSystem。

---

## 3. 遗留任务清单

### A. 审查并提交 Mac 工作区未入库改动

当前 `git status`（Mac 工作区）有 9 个已修改文件 + 1 个未跟踪配置。这些是本轮新流程的实现，**尚未提交**：

| 文件 | 现状要点 |
| --- | --- |
| `mac/fastswitch.sh` | `win` 流程：先探 24800 ESTABLISHED（离线则失败、画面留 Mac）→ 发 InputLeap 热键请求交接 → 轮询 server 日志确认进入 `YT-ASUS-NB` → 再复核连接 → DDC 切 HDMI2(18)；DDC 失败则回收键鼠（发 `m`）。已移除固定 2.5s 等待。 |
| `mac/hammerspoon-init.lua` | 菜单栏托盘 + 全局热键 `Ctrl+Alt+Cmd+W` 切 Win、`Ctrl+Alt+Cmd+M` 跳回 Mac；内层 10s 看门狗 `ensureInputLeap`。 |
| `mac/hs-watchdog.sh` | 外层 launchd 看门狗小改。 |
| `mac/切到 Windows.command` | 双击入口，调用 `fastswitch.sh win`。 |
| `mac/input-leap.conf` | **未跟踪**。screens/links/options；热键 `Control+Alt+Super+j` 切 Win、`Control+Alt+Super+m` 切回 Mac；与运行时 `~/input-leap.conf` 已核对一致。需入库。 |
| `windows/SwitchToMac.ps1` | Win→Mac 序列：DDC USB-C(27) → `/internal` 停 HDMI → 等 12s 冷启动 → `/external` 恢复仅外接屏；已删额外 4s 等待。 |
| `windows/FastSwitch.Tray/Program.cs` | .NET 托盘，`Ctrl+Alt+M` + 菜单触发切 Mac（见 C2 遗留）。 |
| `windows/README-Windows.md`、`README.md`、`mac/INPUTLEAP.md` | 文档同步。 |

**目标**：核对改动与上述流程一致、无调试残留、路径与屏幕名正确；`mac/input-leap.conf` 纳入版本控制；按逻辑分组提交并推送 `main`。
**验收**：`git status` 干净；本地与 `origin/main` 同步。

### B. Win 仓库同步

- `D:\Code\FastSwitch` HEAD `a390d9a`，落后 `origin/main`（`9a358aa`），工作区干净。在该目录 `git pull` 同步，拿到最新 `mac/`、`windows/watchdog.ps1` 等。
- 注意：Win 上实际运行的看门狗在 `%LOCALAPPDATA%\Programs\InputLeap\watchdog.ps1`（已部署新版并注册任务）；仓库副本同步后不要覆盖运行态配置。

### C. 功能遗留与未验收项

| # | 优先级 | 事项 | 现状 / 证据 | 目标 |
| --- | --- | --- | --- | --- |
| C1 | P0 | **双机真实键鼠交接与切换耗时未真机验收** | 网络链路 + 看门狗守护已真机验证（client↔server ESTABLISHED，杀进程自动重连通过）；交接成功、确认超时、焦点弹回、DDC 失败恢复目前仅模拟测试。 | 物理键鼠实测：光标能否跨屏、键盘鼠标是否跟随、双向切换耗时；记录失败路径与耗时。 |
| C2 | P1 | **Win 托盘 `Ctrl+Alt+M` 未联动 InputLeap 切回键鼠** | `Program.cs` 的 `SwitchToMacAsync` 只做 DDC USB-C + `/internal`→12s→`/external`，没有发 InputLeap 切屏热键 `Control+Alt+Super+m`；切到 Mac 后键鼠焦点可能仍留在 Win 侧。 | 切 Mac 序列中补 InputLeap 切回 server 的动作（或确认由 Mac 侧/热键兜底），保证画面切走后键鼠跟随到 Mac。 |
| C3 | P1 | **DHCP 漂移跟随** | Mac 看门狗已用 mDNS 主机名 `yitaodeMac-mini.local` 解析；SSH 别名 `win-nb` 仍写死 `192.168.66.99`，Win IP 漂移后 SSH 会断。 | 评估 SSH 别名改走主机名解析（NetBIOS/mDNS），或在路由器做双机 DHCP 地址保留。 |
| C4 | P2 | 清理预览版残留主机密钥 | Win `C:\ProgramData\ssh\` 仍有 `ssh_host_mldsa44_ed25519_key(.pub)`（便携 10.4 Preview 残留，v9.5 不识别）。 | 确认无用后删除这对残留密钥。 |
| C5 | P3 | （可选）补装 OpenSSH.Client | Win 本机无 `ssh.exe`，只能被连。 | 需要从 Win 主动外连时再装客户端组件。 |

### D. 已知不优化项（勿动）

- **鼠标闪烁**：Mac Retina HDPI 与 Win 1x DPI 不一致 + 局域网延迟；Win 鼠标加速已关。现状保留。
- **jetsam OOM 强杀**：plist 加固只挡 AppKit 主动退出，极端内存压力下的系统强杀不在本方案范围。

### E. 不可回退的架构约束（实测踩坑，优化时勿违反）

1. server 必须由已授权的常驻 Aqua 应用 Hammerspoon 用 `hs.execute nohup` 拉起；launchd 直拉会因辅助功能不信任 FATAL 秒退。
2. 双端必须 `--disable-crypto`，否则 TCP 握手成功但 InputLeap 协议 SSL 卡住超时。
3. server 必须 `--no-daemon` 前台常驻。
4. `--name` 必须显式对齐配置文件屏幕名。
5. Win client 的 server 地址是**位置参数**，不能写 `--server=host:port`；`--name` 用空格不用等号。
6. Mac 存活判定按 `lsof -tiTCP:24800 -sTCP:LISTEN` 取 PID；lsof COMMAND 列 8 字符截断，禁止 `grep input-leaps` 全名。
7. 辅助功能信任只能从已授权的 Hammerspoon 继承；`hs.task` 异步拉起子进程无图形会话会秒退。
8. 不接 USB-A/B 上行线，路线限定软件 KVM + DDC。

---

## 4. 常用排查命令

### Mac

```bash
pgrep -x input-leaps
lsof -iTCP:24800 -P -n
tail -f /tmp/inputleap-server.log
m1ddc set input 18   # 切 Windows（HDMI2）
m1ddc set input 27   # 切 Mac（USB-C）
ssh win-nb
```

### Windows（经 ssh 或本机 PowerShell 5.1）

```powershell
Get-Process input-leapc
Get-NetTCPConnection -RemotePort 24800
Get-ScheduledTask -TaskName "InputLeap Client Watchdog"
Get-Service sshd,ssh-agent
# 重新部署看门狗（脚本所在目录）：
powershell -NoProfile -ExecutionPolicy Bypass -File .\watchdog.ps1 -Install
```
