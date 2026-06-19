#!/bin/bash

STATE_FILE="/tmp/swiftbar-network-speed.state"
PROCESS_STATE_FILE="/tmp/swiftbar-network-speed.processes.state"
PROCESS_STATE_TMP="/tmp/swiftbar-network-speed.processes.$$"
ERROR_LOG="/tmp/swiftbar-network-speed.err"

: >"$ERROR_LOG"

capture_process_network_state() {
  if ! command -v nettop >/dev/null 2>&1; then
    return 1
  fi

  nettop -P -L 1 -x -n -t external 2>>"$ERROR_LOG" |
    awk -F',' '
      NR > 1 && $2 != "" && $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ {
        print $2 "\t" ($5 + 0) "\t" ($6 + 0)
      }
    ' >"$PROCESS_STATE_TMP"
}

save_process_network_state() {
  if [ "$PROCESS_STATE_CAPTURED" = "1" ]; then
    mv "$PROCESS_STATE_TMP" "$PROCESS_STATE_FILE"
  else
    rm -f "$PROCESS_STATE_TMP"
  fi
}

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

PROCESS_STATE_CAPTURED=0
if capture_process_network_state; then
  PROCESS_STATE_CAPTURED=1
fi

if [ -z "$PREV_NOW" ] || [ "$PREV_IF" != "$DEFAULT_IF" ]; then
  echo "0.00M | font=Monaco size=12 trim=false"
  echo "---"
  echo "IP: ${LOCAL_IP:-未知}"
  echo "接口: $DEFAULT_IF"
  echo "等待下一次刷新计算速度"
  echo "---"
  echo "进程网络 Top 5"
  if [ "$PROCESS_STATE_CAPTURED" = "1" ]; then
    echo "等待下一次刷新计算进程速度"
  else
    echo "无法读取进程网络统计"
  fi
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  save_process_network_state
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

print_top_network_processes() {
  if [ "$PROCESS_STATE_CAPTURED" != "1" ]; then
    echo "无法读取进程网络统计"
    return
  fi

  if [ ! -f "$PROCESS_STATE_FILE" ]; then
    echo "等待下一次刷新计算进程速度"
    return
  fi

  awk -F '\t' -v elapsed="$ELAPSED" '
    FNR == NR {
      prev_in[$1] = $2
      prev_out[$1] = $3
      seen[$1] = 1
      next
    }

    seen[$1] {
      down = $2 - prev_in[$1]
      up = $3 - prev_out[$1]

      if (down < 0) {
        down = 0
      }
      if (up < 0) {
        up = 0
      }

      total_bps = int((down + up) / elapsed)
      if (total_bps > 0) {
        printf "%020d\t%s\t%d\t%d\n", total_bps, $1, int(down / elapsed), int(up / elapsed)
      }
    }
  ' "$PROCESS_STATE_FILE" "$PROCESS_STATE_TMP" |
    LC_ALL=C sort -r |
    awk -F '\t' '
      function format_speed(bps, value, unit) {
        if (bps < 102400) {
          value = bps / 1024
          unit = "K/s"
        } else if (bps < 104857600) {
          value = bps / 1048576
          unit = "M/s"
        } else {
          value = bps / 1073741824
          unit = "G/s"
        }

        if (value < 10) {
          return sprintf("%.2f%s", value, unit)
        }
        if (value < 100) {
          return sprintf("%.1f%s", value, unit)
        }
        return sprintf("%.0f%s", value, unit)
      }

      {
        name = $2
        gsub(/\|/, "/", name)
        printf "%d. %s: 下载 %s / 上传 %s | font=Monaco size=12\n", ++count, name, format_speed($3), format_speed($4)

        if (count >= 5) {
          exit
        }
      }

      END {
        if (count == 0) {
          print "暂无进程网络增量"
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
echo "进程网络 Top 5"
print_top_network_processes
echo "---"
echo "刷新 | refresh=true"
echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
save_process_network_state
