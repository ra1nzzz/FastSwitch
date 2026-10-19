#!/usr/bin/env bash
#
# fastswitch.sh — AOC U27U2DS 输入源切换（macOS / Apple Silicon，基于 m1ddc）
#
# 前置条件：
#   1. Mac 必须用 USB-C（雷雳）→ 显示器 USB-C 口连接；M1/M2 Mac mini 的 HDMI 口不支持 DDC/CI
#   2. brew install m1ddc
#   3. 显示器 OSD → Extra → DDC/CI = Yes
#
# 用法：
#   ./fastswitch.sh win      # 切到 Windows（HDMI2，VCP=18，2026-10-19 实测笔记本占用口）
#   ./fastswitch.sh dp       # 切到 DP（VCP=15，备用）
#   ./fastswitch.sh hdmi1    # 切到 HDMI1（VCP=17）
#   ./fastswitch.sh hdmi2    # 切到 HDMI2（VCP=18）
#   ./fastswitch.sh usbc     # 切到 USB-C（VCP=27）
#   ./fastswitch.sh status   # 查看当前输入源
#   ./fastswitch.sh list     # 列出显示器（多显示器时拿编号）
#
# 多显示器：先 list 拿编号，再用 DISPLAY=编号 环境变量，例如：
#   DISPLAY=1 ./fastswitch.sh win
#
# 绑热键：在「快捷指令」App 里新建快速操作 → 运行 Shell 脚本，
#         填 /Volumes/.../FastSwitch/mac/fastswitch.sh win，再到系统设置绑定快捷键。

set -euo pipefail

BIN="$(command -v m1ddc || true)"
if [[ -z "$BIN" ]]; then
  echo "[错误] 未找到 m1ddc，请先执行：brew install m1ddc" >&2
  exit 1
fi

# 输入源 VCP 0x60 数值
VCP_DP=15        # DisplayPort 1
VCP_HDMI1=17
VCP_HDMI2=18     # 本方案：Windows 笔记本（HDMI2，2026-10-19 实测）
VCP_USBC=27      # USB-C / DP Alt（Mac）

DISPLAY_ARG=()
if [[ -n "${DISPLAY:-}" ]]; then
  DISPLAY_ARG=(display "$DISPLAY")
fi

usage() {
  sed -n '2,26p' "$0"
  exit 1
}

[[ $# -ge 1 ]] || usage

case "$1" in
  win)
    # 2026-10-19 实测：Windows 笔记本（ASUS TUF A15）接在 HDMI2，VCP=18
    "${BIN}" "${DISPLAY_ARG[@]}" set input "$VCP_HDMI2"
    echo "已切换到 Windows（HDMI2）"
    ;;
  dp)
    "${BIN}" "${DISPLAY_ARG[@]}" set input "$VCP_DP"
    echo "已切换到 DP"
    ;;
  hdmi1)
    "${BIN}" "${DISPLAY_ARG[@]}" set input "$VCP_HDMI1"
    echo "已切换到 HDMI1"
    ;;
  hdmi2)
    "${BIN}" "${DISPLAY_ARG[@]}" set input "$VCP_HDMI2"
    echo "已切换到 HDMI2"
    ;;
  usbc|mac)
    "${BIN}" "${DISPLAY_ARG[@]}" set input "$VCP_USBC"
    echo "已切换到 USB-C（Mac）"
    ;;
  status)
    # 注意：macOS 26+ 上 m1ddc get 读取返回固定垃圾值（0x5F8A），不影响 set 切换
    "${BIN}" "${DISPLAY_ARG[@]}" get input
    ;;
  list)
    # 注意：macOS 26+ 上 "display list detailed" 可能段错误，用普通 list
    "${BIN}" display list
    ;;
  *)
    usage
    ;;
esac
