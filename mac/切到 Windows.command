#!/usr/bin/env bash
# 双击即把显示器切到 Windows（HDMI2 输入，VCP=18）。
# 前置：Windows 端「切到 Mac」流程会自动恢复 HDMI 输出，因此本命令直接切即可秒切。
# 首次双击若提示无权限：终端执行 chmod +x "切到 Windows.command"
# 绑全局热键：在「快捷指令」App 里新建快速操作 → 运行 Shell 脚本粘贴本文件绝对路径，
# 再到 系统设置 → 键盘 → 快捷键 → 服务 中绑定。

DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/fastswitch.sh" win
