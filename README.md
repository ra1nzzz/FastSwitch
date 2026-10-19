# FastSwitch — AOC U27U2DS 双主机软件切换输入源方案

Mac mini M2（Apple Silicon）+ Windows 11 游戏本共用一台 AOC U27U2DS，不用起身按显示器摇杆，**热键 / 双击即可一键切换输入源**，并让一套键鼠随画面自动跟随（软件 KVM）。

> **2026-10-19 双向切换已在真机完整打通并实测稳定**：Mac 走 USB-C、Windows 走 HDMI2；零第三方依赖、无需 SSH/网络。详细机制见第 2 节。

---

## 0. 快速开始（TL;DR）

**接线**：Mac 用 C-C 线接显示器 USB-C；Windows 用 HDMI 线接显示器 HDMI2（可选再用 USB-A 转 USB-B 线接 USB-PC 做 KVM）。OSD 打开 `DDC/CI = Yes`、`Input Select = Auto`、`USB Selection = Auto`。

| 方向 | 操作 | 耗时 |
| --- | --- | --- |
| **Windows → Mac** | 运行托盘版 `FastSwitch.exe` 后按 `Ctrl+Alt+M`；也可双击 `windows/SwitchToMac.bat` | 约 16 秒 |
| **Mac → Windows** | 双击 `mac/切到 Windows.command`，或终端 `m1ddc set input 18` | 秒切 |

- Mac 端：`brew install m1ddc`，脚本见 [`mac/`](./mac/)。
- Windows 端：直接用 [`windows/`](./windows/) 里的零依赖 PowerShell 脚本（只调系统自带 dxva2 API，无需安装任何软件）。

---

## 1. 仓库结构

```
FastSwitch/
├── README.md                    # 本文件（总览 + 调研 + 双端方案）
├── mac/
│   ├── fastswitch.sh            # macOS 输入源切换（基于 m1ddc）
│   └── 切到 Windows.command      # 双击即切到 Windows
└── windows/
    ├── README-Windows.md        # Windows 端详细说明与故障排查
    ├── SwitchToMac.bat          # 双击/热键入口
    ├── SwitchToMac.ps1          # 切到 Mac 的完整时序（自动断/恢复 HDMI）
    └── MonitorInput.ps1         # 零依赖 DDC 工具（内联 C# 调 dxva2）
```

---

## 2. 核心机制：为什么直接切会被弹回，以及如何解决（关键）

### 2.1 实测到的关键时序

| 现象 | 实测值 |
| --- | --- |
| 显示器切换到非活动 USB-C 口后，冷启动到 Mac 桌面可见 | **约 6.5 秒** |
| DDC 触发切换后，固件对"无信号"的自动回退阈值 | **约 2~3 秒** |
| 结论 | 6.5s > 2~3s：只要 HDMI 仍在输出，切到 USB-C 后等不到 Mac 出画就被弹回 HDMI |

另外两条实测规律：
1. **显示器只对当前活动输入口响应 DDC**。屏幕在 Mac 时，Windows HDMI 侧读 DDC 全部返回错误 31（非活动口正常现象）；切换指令必须在当前活动的一侧发出。
2. U27U2DS 的 DDC `capabilities` 能力表中 0x60 只列出 `11 12 0F`（HDMI1/HDMI2/DP1），**未列 USB-C(27)，但固件实际接受 27**，切换有效。

### 2.2 Windows → Mac 的已验证时序（顺序很重要）

1. **HDMI 还活动时**发 DDC `Input Select = USB-C(27)`（这是显示器唯一会响应 DDC 的时刻，返回 OK）；
2. **立即** `displayswitch /internal` 切断 HDMI 输出（仅内屏）——HDMI 源在固件回退计时到期前消失，显示器没有"可回退的源"，便停在 USB-C 等待冷启动；
3. 等待 12 秒（覆盖 6.5 秒冷启动 + 稳定余量）；
4. `displayswitch /extend` 恢复 HDMI 输出——此时屏幕已锁定稳定的 Mac 画面，**不会跳回**；
5. Windows 在后台持续输出 HDMI，因此 Mac 端随后发 `m1ddc set input 18` 时能**秒切**回 Windows。

> 兜底：即便第 1 步 DDC 丢失（例如 /internal 后 AOC 从活动 HMONITOR 枚举中消失），只要 OSD 是 `Input Select = Auto`，HDMI 无信号时显示器也会自动扫描到 USB-C，同样能成功。

### 2.3 Mac → Windows

一条命令 `m1ddc set input 18`（HDMI2）。因为 Windows HDMI 已在后台输出，握手很快、秒切稳定。

---

## 3. 显示器支持情况与开源工具调研

### 3.1 显示器是否支持？——支持

U27U2DS 官方说明书明确支持 **VESA DDC2B/CI**（OSD → Extra → DDC/CI 有 Yes/No 开关），可通过软件发送 VCP 0x60（Input Select）切换 HDMI1 / HDMI2 / DP / USB-C。

### 3.2 成熟开源工具

| 平台 | 工具 | 许可 | 说明 |
| --- | --- | --- | --- |
| macOS（Apple Silicon） | **m1ddc** | MIT | 命令行，MonitorControl/BetterDisplay 作者维护，`brew` 可装，输入切换完整；本仓库 Mac 端使用 |
| Windows | 微软 **PowerToys · Power Display** | MIT | 2025 年起内置，支持输入源切换，GUI 友好 |
| Windows | NirSoft **ControlMyMonitor** | 免费闭源 | 命令行热键最常用，非开源 |
| Windows | Python **monitorcontrol** | MIT | 纯开源库，需要 Python |
| **Windows（本仓库）** | **MonitorInput.ps1** | MIT | **零依赖**：内联 C# 直接调系统 dxva2，PowerShell 5.1 即可运行，无需安装任何东西 |

### 3.3 关键前提（本机实测）

Mac mini M2 的 **HDMI 口不支持 DDC/CI**（Apple Silicon 已知限制），必须改用 **USB-C（DP Alt）口**连接显示器，Mac 端才有软件控制能力。

### 3.4 本机实测记录

**Mac mini M2 / macOS 27.0.1 / m1ddc 1.2.0（C-C 直连 USB-C，4K60 HBR2×4）**：

| 验证项 | 结果 |
| --- | --- |
| `m1ddc display list` | 正常识别 U27U2G6R4B |
| `set luminance`（亮度写入） | 屏幕实测有明显变化，写入通道正常 |
| `set input ...`（输入切换） | 实测成功，切换只靠 set |
| `get ...`（读取） | macOS 27 下返回固定垃圾值 `0x5F8A`（I2C 兼容问题），**不影响 set**；需要读取可试 BetterDisplay |
| `display list detailed` | macOS 27 下可能段错误，用普通 `display list` 即可 |

**Windows 11 / ASUS TUF A15 FA506IV（HDMI → HDMI2）**：

| 验证项 | 结果 |
| --- | --- |
| `MonitorInput.ps1 get`（HDMI 活动时） | VCP 0x60 current = 18（HDMI2），读取正常 |
| `caps` 能力表 | 0x60 列出 11/12/0F，USB-C(27) 未列但固件接受 |
| 直接 `set 27` 不断 HDMI | 闪一下无信号后被弹回（6.5s vs 2~3s） |
| 断 HDMI + 等待 + 恢复 HDMI 序列 | **成功，屏幕稳定在 Mac** |
| Mac 端 `set input 18` 回切 | **秒切回 Windows，闭环成功** |

---

## 4. U27U2DS 接口与能力盘点

| 项目 | 规格 |
| --- | --- |
| 分辨率 | 3840×2160@60Hz（HDMI / DP / USB-C 均可） |
| 视频输入 | HDMI1、HDMI2（HDMI 2.0）、DP（1.4）、USB-C（DP Alt Mode） |
| USB-C 供电 | USB PD 3.0，最高 90W（SDR、亮度≤70 等条件下，否则 65W） |
| USB 上行 | ① USB-C 兼作上行；② 独立 **USB-PC（USB-B 上行）口** |
| USB 下行 | 4× USB-A 3.2 Gen1（其中 1 个快充） |
| DDC/CI | 支持（OSD → Extra → DDC/CI = Yes） |
| USB 路径选择 | OSD → OSD Setup → USB Selection：**Auto / USB C / USB Up** |
| PIP/PBP | 支持（PBP 时 DP 必须作为主或次信号源） |

> **KVM 潜力**：两条 USB 上行路径（USB-C 与 USB-B）+ 4 个 USB-A + USB Selection = Auto，构成一套 KVM 硬件。同门新款 U27U2DP 官方直接宣传「KVM 易用模式，USB C1 和其他信号源共享一套键鼠，自动切换」。U27U2DS 硬件与 OSD 选项一致，Auto 是否随视频源联动需实测（见第 11 节）。

---

## 5. 接线方案

```
Mac mini M2 ──USB-C 全功能线（C-C）──► 显示器 USB-C 口      （视频 4K60 + DDC 控制 + USB 上行）
Windows 11 ──HDMI 线────────────────► 显示器 HDMI2 口      （视频；本机实测占用 HDMI2）
Windows 11 ──USB-A 转 USB-B 线──────► 显示器 USB-PC 口      （USB 上行，KVM 用）
键盘 / 鼠标（接收器）────────────────► 显示器 USB-A 口 ×2   （两机共用）
```

- 随机配件箱通常已含 USB C-C 线、HDMI 线、DP 线、USB 上行线，优先找一找。
- 若 Windows 显卡有 DP 输出，也可接 DP 口（把 VCP 值改为 15）。

---

## 6. 显示器 OSD 设置（摇杆操作）

1. **Extra → DDC/CI = Yes**（软件控制总开关）
2. **Extra → Input Select = Auto**（本方案的兜底自动扫描）
3. **OSD Setup → USB Selection = Auto**（USB 上行随视频源自动切换，即 KVM）
4. **OSD Setup → USB = 2.0**（USB-C 走视频时，USB 设为 2.0 才能 4K60；键鼠是低速设备无影响）

---

## 7. Mac 端配置

### 安装

```bash
brew install m1ddc
m1ddc display list          # 能看到 U27U2 系列即说明 DDC 通道正常
```

### 本仓库脚本

```bash
./mac/fastswitch.sh win      # 切到 Windows（HDMI2，VCP=18）
./mac/fastswitch.sh usbc     # 切到 USB-C（Mac，VCP=27）
./mac/fastswitch.sh list     # 列出显示器
# 或双击：mac/切到 Windows.command
```

### 绑热键

在「快捷指令」App 新建「快速操作」→ 添加「运行 Shell 脚本」→ 填 `fastswitch.sh` 的绝对路径加 `win` 参数，再到系统设置 → 键盘 → 快捷键 → 服务中绑定。也可用 Raycast 扩展「Display Input Switcher」（m1ddc 的 GUI）。

### 其他 GUI 工具

MonitorControl（MIT，仅亮度/音量，不做输入切换）、BetterDisplay（免费+Pro，全功能）、Lunar（闭源，支持输入切换）。

---

## 8. Windows 端配置

**命令行/双击方式：**用本仓库 [`windows/`](./windows/) 中的 PowerShell 脚本，无需安装第三方软件，详见 [windows/README-Windows.md](./windows/README-Windows.md)。

**后台快捷键方式：**用 `windows/FastSwitch.Tray` 项目发布单文件 `FastSwitch.exe`。它常驻系统托盘，按 `Ctrl+Alt+M` 切到 Mac，也可以从托盘菜单切换或退出。构建命令见 [Windows 端说明](./windows/README-Windows.md)。

**备选方案**（都需要安装软件，本仓库主流程不依赖）：
- PowerToys → Power Display → Input source 选 USB-C（官方开源 GUI）；
- ControlMyMonitor：`ControlMyMonitor.exe /SetValue Primary 60 27`（免费闭源）；
- Python `monitorcontrol`：`pip install monitorcontrol` 后自行 `set_input_source(27)`。

---

## 9. VCP 0x60 输入值对照表

| 输入源 | 标准值 |
| --- | --- |
| DisplayPort 1 | 15 |
| DisplayPort 2 | 16 |
| HDMI 1 | 17 |
| **HDMI 2（本机 Windows）** | **18** |
| **USB-C（本机 Mac）** | **27** |

> 以显示器实际 capabilities 为准。个别厂商面板用 alternate VCP，m1ddc 可用 `set input-alt ...`（DP=208/209，HDMI=144/145，USB-C=210）。

---

## 10. 重要限制与故障排查

- **切走后当前主机的 DDC 通道即断开**：屏幕在 Mac 时 Windows 读不到 DDC、反之亦然，属正常现象；所以两台主机都要装好切换工具，且切出指令必须在当前活动的一侧发出。
- **Mac 必须走 USB-C/DP 连接**：M1/M2 Mac mini 的 HDMI 口不支持 DDC/CI。
- **Windows 直接切 USB-C 会被弹回**：必须先切断 HDMI 消除回退源（见第 2 节），这是本方案的核心。
- Windows 端 DDC 无响应：确认 OSD `DDC/CI=Yes`；检查显卡驱动未禁用 DDC/CI；换原装 HDMI 线（劣质线/转接头不透传 DDC）。
- USB-C 只有 4K30：OSD 把 USB 设为 2.0（DP Alt 需 4 通道带宽）。
- PowerShell 脚本报中文解析错误：本仓库脚本已全英文；若自行加中文，请把 `.ps1` 保存为 UTF-8 **带 BOM**。
- 若日常用「仅外接屏」模式：把 `SwitchToMac.ps1` 末尾的 `/extend` 改为 `/external`。

---

## 11. 待验证：KVM 键鼠联动

接上 USB-A 转 USB-B 上行线后，需要验证 OSD `USB Selection = Auto` 下键鼠是否随视频源自动跟随：
- 切到 Windows 时键鼠接收器走 USB-B 上行给笔记本；
- 切到 Mac 时走 USB-C 上行给 Mac。

若不联动，可在 OSD 手动固定 USB 路径，或退而求其次使用显示器 PBP 分屏。

---

## 12. 参考链接

- U27U2DS 官方中文说明书：https://device.report/m/5b95d32da755b8cf299e02d82647cdd13901f17bfc174bc14d8a5504406124e6.pdf
- m1ddc（GitHub）：https://github.com/waydabber/m1ddc
- PowerToys Power Display（微软文档）：https://learn.microsoft.com/zh-cn/windows/powertoys/power-display
- ControlMyMonitor：https://www.nirsoft.net/utils/control_my_monitor.html
- Python monitorcontrol：https://pypi.org/project/monitorcontrol/
- Twinkle Tray（开源，亮度）：https://github.com/xanderfrangos/twinkle-tray
- Monitorian（开源，亮度）：https://github.com/emoacht/Monitorian
- Raycast Display Input Switcher：https://www.raycast.com/clins1994/display-input-switcher
- 显示器 KVM 配置通用教程：https://huhuidong.wordpress.com/2023/02/27/enabling-kvm-keyboard-video-mouse-mode-for-your-monitor/
