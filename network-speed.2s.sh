#!/bin/bash

STATE_FILE="/tmp/swiftbar-network-speed.state"
ERROR_LOG="/tmp/swiftbar-network-speed.err"

: >"$ERROR_LOG"
DEFAULT_IF=$(route -n get default 2>"$ERROR_LOG" | awk '/interface:/{print $2; exit}')

if [ -z "$DEFAULT_IF" ]; then
  DEFAULT_IF=$(ifconfig -l | tr ' ' '\n' | awk '/^en[0-9]+$/{print; exit}')
fi

LOCAL_IP=$(ipconfig getifaddr "$DEFAULT_IF" 2>/dev/null)

read -r IBYTES OBYTES <<EOF
$(netstat -ibn -I "$DEFAULT_IF" 2>>"$ERROR_LOG" | awk -v iface="$DEFAULT_IF" '
  $1 == iface && $7 ~ /^[0-9]+$/ && $10 ~ /^[0-9]+$/ {
    print $7, $10
    exit
  }
')
EOF

if [ -z "$IBYTES" ] || [ -z "$OBYTES" ]; then
  echo "网速: ERR"
  echo "---"
  echo "无法读取接口: $DEFAULT_IF"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

NOW=$(date '+%s')

PREV_NOW=""
PREV_IBYTES=""
PREV_OBYTES=""
PREV_IF=""

if [ -f "$STATE_FILE" ]; then
  read -r PREV_NOW PREV_IBYTES PREV_OBYTES PREV_IF <"$STATE_FILE"
fi

printf '%s %s %s %s\n' "$NOW" "$IBYTES" "$OBYTES" "$DEFAULT_IF" >"$STATE_FILE"

if [ -z "$PREV_NOW" ] || [ "$PREV_IF" != "$DEFAULT_IF" ]; then
  echo "0.00M | font=Monaco size=12 trim=false"
  echo "---"
  echo "IP: ${LOCAL_IP:-未知}"
  echo "接口: $DEFAULT_IF"
  echo "等待下一次刷新计算速度"
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

ELAPSED=$((NOW - PREV_NOW))
if [ "$ELAPSED" -le 0 ]; then
  ELAPSED=1
fi

DOWN_DELTA=$((IBYTES - PREV_IBYTES))
UP_DELTA=$((OBYTES - PREV_OBYTES))

if [ "$DOWN_DELTA" -lt 0 ]; then
  DOWN_DELTA=0
fi

if [ "$UP_DELTA" -lt 0 ]; then
  UP_DELTA=0
fi

DOWN_BPS=$((DOWN_DELTA / ELAPSED))
UP_BPS=$((UP_DELTA / ELAPSED))

format_speed() {
  awk -v bps="$1" '
    function print3(value, unit) {
      if (value < 10) {
        printf "%.2f%s", value, unit
      } else if (value < 100) {
        printf "%.1f%s", value, unit
      } else {
        printf "%.0f%s", value, unit
      }
    }

    BEGIN {
      kb = bps / 1024
      mb = bps / 1048576

      if (kb < 100) {
        print3(kb, "K/s")
      } else if (mb < 100) {
        print3(mb, "M/s")
      } else if (mb < 1000) {
        print3(mb / 1024, "G/s")
      } else {
        gb = mb / 1024
        print3(gb, "G/s")
      }
    }
  '
}

format_bytes() {
  awk -v bytes="$1" '
    BEGIN {
      if (bytes >= 1073741824) {
        printf "%.2f GB", bytes / 1073741824
      } else if (bytes >= 1048576) {
        printf "%.2f MB", bytes / 1048576
      } else if (bytes >= 1024) {
        printf "%.1f KB", bytes / 1024
      } else {
        printf "%d B", bytes
      }
    }
  '
}

DOWN_SPEED=$(format_speed "$DOWN_BPS")
UP_SPEED=$(format_speed "$UP_BPS")

echo "$DOWN_SPEED | font=Monaco size=12"
echo "---"
echo "上传: $UP_SPEED | font=Monaco size=12"
echo "下载: $DOWN_SPEED | font=Monaco size=12"
echo "---"
echo "IP: ${LOCAL_IP:-未知}"
echo "接口: $DEFAULT_IF"
echo "---"
echo "累计上传: $(format_bytes "$OBYTES")"
echo "累计下载: $(format_bytes "$IBYTES")"
echo "---"
echo "刷新 | refresh=true"
echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
