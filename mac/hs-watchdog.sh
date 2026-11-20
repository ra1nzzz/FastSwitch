#!/bin/bash
# 外层看门狗（launchd 每 10s 调用一次）
# 1. Hammerspoon 进程不在 -> open 拉起
# 2. 24800 端口不在 LISTEN -> 累计缺失次数；连续 3 次（约 30s）判定内层定时器假活，
#    重启 Hammerspoon，由其加载时的 ensureInputLeap() 重新拉起 server。
# 说明：launchd 上下文不能直接拉起 input-leaps（辅助功能不信任），只能重启已授权的 Hammerspoon。

STATE=/tmp/hs-watchdog-miss.count
PORT=24800

# 1. Hammerspoon 进程保活
if ! /usr/bin/pgrep -x Hammerspoon >/dev/null 2>&1; then
    /usr/bin/open -a Hammerspoon
    /bin/echo 0 > "$STATE" 2>/dev/null
    exit 0
fi

# 2. server 端口存活则清零计数
if /usr/sbin/lsof -tiTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    /bin/echo 0 > "$STATE" 2>/dev/null
    exit 0
fi

# 3. 端口缺失，累计连续次数
MISS=$(/bin/cat "$STATE" 2>/dev/null)
case "$MISS" in (*[!0-9]*) MISS=0;; esac
MISS=$((MISS+1))
/bin/echo "$MISS" > "$STATE" 2>/dev/null

if [ "$MISS" -ge 3 ]; then
    /usr/bin/killall Hammerspoon 2>/dev/null
    /bin/sleep 2
    /usr/bin/open -a Hammerspoon
    /bin/echo 0 > "$STATE" 2>/dev/null
fi

exit 0
