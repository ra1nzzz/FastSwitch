#!/bin/bash
# win coordinates InputLeap and HDMI2. hdmi2 is the display-only command.
set -euo pipefail
export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"

fail() { echo "$*" >&2; exit 1; }
ddc=$(command -v m1ddc) || fail "未找到 m1ddc，请先安装 m1ddc。"
# Bound driver calls, including reads while a monitor is sleeping.
run_ddc() { /usr/bin/perl -e 'alarm 4; exec @ARGV or die $!' "$ddc" "$@"; }

case "${1:-}" in
    list) run_ddc display list; exit ;;
    win|hdmi2) input=18 ;;
    dp) input=15 ;;
    hdmi1) input=17 ;;
    usbc|mac) input=27 ;;
    status) ;;
    *) fail "用法: $0 {win|dp|hdmi1|hdmi2|usbc|mac|status|list}" ;;
esac

# DISPLAY may contain an XQuartz socket. Preserve legacy numeric selectors.
target=${FASTSWITCH_DISPLAY:-}
if [[ -z "$target" && "${DISPLAY:-}" =~ ^[0-9]+$ ]]; then target=$DISPLAY; fi
if [[ -z "$target" ]]; then
    displays=$(run_ddc display list) || fail "无法枚举显示器，请检查 USB-C 和 DDC/CI。"
    target=$(awk '/^\[[0-9]+\]/ && toupper($0) ~ /U27U2/ {gsub(/[][]/, "", $1); print $1}' <<< "$displays")
    [[ "$target" =~ ^[0-9]+$ ]] || fail "未识别到唯一的 AOC U27U2。请运行 list 并设置 FASTSWITCH_DISPLAY。"
fi
if [[ "$1" == status ]]; then run_ddc display "$target" get input; exit; fi

if [[ "$1" == win ]]; then
    # shlock recovers locks left by dead processes.
    lock="${TMPDIR:-/tmp}/fastswitch-win-$UID.lock"
    /usr/bin/shlock -p "$$" -f "$lock" || fail "已有切换正在进行。"
    return_focus=0
    hscli=/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs
    send_key() {
        "$hscli" -q -t 2 -c "assert(hs.accessibilityState(), '需要辅助功能权限'); assert(fastSwitchInputKey('$1'))" </dev/null
    }
    cleanup() {
        if [[ "$return_focus" == 1 ]]; then
            send_key m || echo "请按 Ctrl+Alt+Cmd+M 将键鼠切回 Mac。" >&2
        fi
        /bin/rm -f "$lock"
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    connected() {
        /usr/sbin/lsof -nP -a -c input-lea -iTCP:24800 -sTCP:ESTABLISHED -Fn 2>/dev/null |
            /usr/bin/awk '/^n.*:24800->/ {found=1} END {exit !found}'
    }
    connected || fail "Win11 键鼠客户端未连接。请唤醒 Windows，并检查 InputLeap Client Watchdog 和局域网。"
    log=/tmp/inputleap-server.log
    offset=$(/usr/bin/stat -f %z "$log") || fail "无法读取 InputLeap 服务日志。"
    [[ -x "$hscli" ]] && /usr/bin/pgrep -ax Hammerspoon >/dev/null || fail "请启动 Hammerspoon。"
    return_focus=1
    send_key j || fail "未能请求键鼠切换，请检查 Hammerspoon IPC 和辅助功能权限。"
    # Only accept a new transition from this attempt. A later bounce cancels it.
    confirmed=0
    for ((i=0; i<12; i++)); do
        if tail -c "+$((offset+1))" "$log" | awk '
            /INFO: switch from "/ {ok = index($0, " to \"YT-ASUS-NB\" at ") > 0}
            END {exit !ok}'; then
            confirmed=1
            break
        fi
        sleep 0.1
    done
    [[ $confirmed == 1 ]] && connected || fail "InputLeap 未确认键鼠进入 Win11。请检查屏幕名及 InputLeap 热键配置。"
fi

run_ddc display "$target" set input "$input" || fail "DDC 写入失败，请检查显示器活动输入及 DDC/CI。"
return_focus=0
echo "已发送显示器输入源 $input 切换指令。"
