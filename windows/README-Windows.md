# FastSwitch — Windows 端方案（ASUS TUF A15 FA506IV → AOC U27U2DS）

目标：在 Windows 游戏本上一键把显示器切到 Mac（USB-C），Mac 端再一键切回 Windows（HDMI2），无需手动摇杆。

> 本目录文件可直接放到 Windows 任意目录（例如 `D:\Code\FastSwitch`）使用。下文中的 `D:\Code\FastSwitch` 仅为作者本机路径，替换成你自己的目录即可。

---

## 0. 核心机制（重要，2026-10-19 实测结论）

| 事实 | 说明 |
| --- | --- |
| 本机接口 | 笔记本 HDMI（RTX 2060，HDMI 2.0）→ 显示器 **HDMI2**，VCP 0x60 = **18** |
| Mac 接口 | Mac mini M2 用 USB-C（DP Alt）→ 显示器 USB-C 口，VCP 0x60 = **27** |
| 故障根因 | U27U2DS 从非活动状态切到 USB-C 时，端口冷启动需要约 **6.5 秒**才出 Mac 画面；但 DDC 触发切换后固件的"无信号自动回退"只等约 **2~3 秒**就跳回有信号的 HDMI，所以直接发"切到 USB-C"会被弹回来 |
| 已验证解法 | 先发 DDC 切到 USB-C（此刻 HDMI 还活动，指令可达），**立刻切断 HDMI 输出**，让显示器没有"可回退的源"；等 Mac 稳定后再恢复 HDMI |
| 非活动口 DDC 不可达 | 显示器只对当前活动的输入口响应 DDC。屏幕在 Mac 时 Windows HDMI 侧读不到 DDC（正常现象），切换只能在活动口发起 |

---

## 1. 文件清单

| 文件 | 作用 |
| --- | --- |
| `SwitchToMac.bat` | **双击/热键入口**。内部调用下面的 ps1 |
| `SwitchToMac.ps1` | **切到 Mac 的完整序列**：发 DDC → 切 HDMI → 等待 → 恢复 HDMI（约 16 秒，全自动） |
| `MonitorInput.ps1` | 零依赖 DDC 工具，直接调 Windows 自带 dxva2 API。支持 `list/get/caps/dump/usbc/hdmi1/hdmi2/set/getcode/setcode` 等 |
| `FastSwitch.Tray/` | 后台托盘程序源码与图标；发布后按 `Ctrl+Alt+M` 切换 |

> 无需安装 ControlMyMonitor、PowerToys、Python 等任何第三方软件。PowerShell 5.1 自带即可运行。

---

## 2. 一键切换（已验证）

### Windows → Mac

双击 `SwitchToMac.bat`（或绑热键，见第 5 节）。自动执行：

1. 在 HDMI 活动时发 DDC `Input Select = USB-C(27)`；
2. 立即 `displayswitch /internal`（仅内屏，停止 HDMI 输出）——阻止无信号回退；
3. 等待 12 秒（覆盖 USB-C 6.5 秒冷启动）；
4. `displayswitch /extend` 恢复 HDMI 输出——此时屏幕已稳定在 Mac，不会跳回。

结束后屏幕稳定在 Mac，同时 Windows 在后台恢复了 HDMI 输出，因此 Mac 端可以随时秒切回来。

### 后台快捷键版（托盘程序）

需要按快捷键直接切换时，可使用 `FastSwitch.Tray`。程序常驻系统托盘，按 **Ctrl+Alt+M** 切到 Mac；右键托盘图标也可手动切换或退出。快捷键只在程序运行时有效。

在仓库根目录运行以下命令生成 Windows x64 单文件程序：

```powershell
dotnet publish .\windows\FastSwitch.Tray\FastSwitch.Tray.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\windows\FastSwitch.Tray\publish
```

运行 `windows\FastSwitch.Tray\publish\FastSwitch.exe` 后，托盘图标会显示快捷键已注册。要让程序每次登录 Windows 自动运行，可将该 EXE 的快捷方式放入 `Win+R` 打开的 `shell:startup` 文件夹。

### Mac → Windows

在 Mac 上：双击仓库 `mac/切到 Windows.command`，或终端执行：

```
m1ddc set input 18
```

因为此时 Windows HDMI 已在后台输出，会**秒切**回 Windows。

---

## 3. 接线与 OSD（一次性配置）

| 笔记本端 | 线缆 | 显示器端 |
| --- | --- | --- |
| HDMI 口 | HDMI 2.0 线（包装内附） | HDMI2（实测 VCP=18） |
| USB-A 口 | USB-A 转 USB-B 线（包装内附） | USB-PC（USB-B 上行，KVM 用） |
| 键鼠接收器 | — | 显示器 USB-A |

OSD 确认：
- **Extra → DDC/CI = Yes**（必需）
- **Extra → Input Select = Auto**（自动扫描兜底；本方案主要靠 DDC 明确切换）
- **OSD Setup → USB Selection = Auto**（键鼠随视频源跟随，KVM）
- USB-C 4K60 时 OSD USB 相关项设为 2.0

---

## 4. 常用命令（排查用）

在本目录打开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 get            # 读当前输入源
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 caps           # 读 DDC 能力表
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 dump           # 读常用 VCP 码
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 usbc           # 只发切到 USB-C（不切断 HDMI，会被回退）
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 getcode -Code CC   # 读任意 VCP 码（十六进制）
```

显示模式命令（Windows 自带）：
```powershell
displayswitch /internal   # 仅内屏（停止外接 HDMI 输出）
displayswitch /extend     # 扩展（恢复外接 HDMI）
displayswitch /external   # 仅外接屏
```

---

## 5. 绑定全局热键（Ctrl+Alt+M）

1. 右键 `SwitchToMac.bat` → 发送到 → 桌面快捷方式；
2. 右键桌面快捷方式 → 属性 → 「快捷键」输入 `Ctrl + Alt + M`；
3. 快捷方式可放在任意位置，不影响热键使用。

> Mac 端热键：在「快捷指令」App 新建快速操作 → 运行 Shell 脚本调用 `mac/fastswitch.sh win`，再到系统设置绑定快捷键。

---

## 6. 显示模式说明

- 脚本结束时 Windows 处于「扩展」模式（内屏 + 外接屏都输出）。外接屏被 scaler 显示为 Mac，因此 Windows 上的外接屏内容不可见，但不影响切回；
- 如果你日常用「仅外接屏」（内屏关闭），把 `SwitchToMac.ps1` 末尾的 `displayswitch.exe /extend` 改成 `/external`；
- 切到 Mac 后，部分 Windows 窗口可能停留在外接屏（不可见），切回 Windows 后恢复正常。

---

## 7. 故障排查

| 现象 | 处理 |
| --- | --- |
| SetVCPFeature 0x60 FAIL（内屏那一条） | 正常，内屏不支持 DDC；看 AOC 那一条是否 OK |
| 屏幕在 Mac 时 get 全部失败（31） | 正常，非活动输入口不响应 DDC；切到 Windows 后再读 |
| 切到 Mac 后又跳回 Windows | 确认 OSD Input Select = Auto；确认 /internal 已生效；把脚本第 3 步等待从 12 秒加大到 15 秒 |
| 切回 Windows 失败 | 说明 HDMI 没在后台恢复，手动 `displayswitch /extend` 后再在 Mac 上 set 18 |
| DDC 完全不工作 | 确认 OSD DDC/CI = Yes；换一根原装 HDMI 线（劣质线不透传 DDC） |
| PowerShell 报中文解析错误 | 本脚本已全英文；若自行加入中文，请把文件保存为 UTF-8 **带 BOM** |

---

## 8. VCP 0x60 输入值速查

| 输入 | 值 |
| --- | --- |
| DisplayPort 1 | 15 |
| DisplayPort 2 | 16 |
| HDMI 1 | 17 |
| **HDMI 2（本机）** | **18** |
| USB-C（Mac） | 27 |

> 本机实测：`caps` 能力表中 0x60 只列 11/12/0F（HDMI1/HDMI2/DP1），USB-C(27) 未在列表但固件实际接受，切换有效。

---

## 9. 待验证：KVM 键鼠联动

接上 USB-B 上行线后，需确认：屏幕切到 Windows 时键鼠接收器走 USB-B 上行给笔记本，切到 Mac 时走 USB-C 上行给 Mac，OSD USB Selection = Auto 下是否自动跟随。若不联动则把 USB Selection 固定为手动策略。
