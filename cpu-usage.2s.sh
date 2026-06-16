#!/bin/bash

ERROR_LOG="/tmp/swiftbar-cpu-usage.err"

: >"$ERROR_LOG"

format_percent() {
  awk -v pct="$1" '
    BEGIN {
      pct += 0
      if (pct < 0) {
        pct = 0
      } else if (pct > 100) {
        pct = 100
      }

      if (pct < 10) {
        printf "%.2f%%", pct
      } else if (pct < 100) {
        printf "%.1f%%", pct
      } else {
        printf "%.0f%%", pct
      }
    }
  '
}

CPU_LINE=$(top -l 1 -n 0 2>>"$ERROR_LOG" | awk '/^CPU usage:/ { print; exit }')

if [ -z "$CPU_LINE" ]; then
  echo "CPU ERR | font=Monaco size=12 trim=false"
  echo "---"
  echo "无法读取 CPU 汇总"
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

CPU_TOTAL=$(awk -v line="$CPU_LINE" '
  BEGIN {
    idle = -1
    n = split(line, parts, ",")
    for (i = 1; i <= n; i++) {
      if (parts[i] ~ /idle/) {
        gsub(/[^0-9.]/, "", parts[i])
        idle = parts[i] + 0
      }
    }
    if (idle < 0) {
      exit 1
    }
    printf "%.6f", 100 - idle
  }
')

if [ -z "$CPU_TOTAL" ]; then
  echo "CPU ERR | font=Monaco size=12 trim=false"
  echo "---"
  echo "无法解析 CPU 汇总: $CPU_LINE"
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

CPU_DISPLAY=$(format_percent "$CPU_TOTAL")

echo "CPU $CPU_DISPLAY | font=Monaco size=12 trim=false"
echo "---"
echo "总体占用: $CPU_DISPLAY | font=Monaco size=12"
echo "采样: $CPU_LINE"
echo "---"
echo "CPU 占用最高的 10 个应用"

ps -axo pcpu=,comm= 2>>"$ERROR_LOG" | awk '
  function label_for(command, label) {
    label = command
    sub(/^.*\//, "", label)

    if (label ~ /^Google Chrome Helper/) {
      label = "Google Chrome"
    } else if (label ~ /^Code Helper/) {
      label = "Code"
    } else if (label == "codex" || label ~ /^Codex /) {
      label = "Codex"
    } else if (label ~ /^Qianwen Helper/) {
      label = "Qianwen"
    } else if (label ~ /^WeChatAppEx Helper/) {
      label = "WeChatAppEx"
    } else if (label ~ /^Safari / || label ~ /^com\.apple\.WebKit\./) {
      label = "Safari"
    }

    return label
  }

  function is_sampler_noise(label) {
    return label == "top" || label == "ps" || label == "cpu-usage.2s.sh"
  }

  NF >= 2 {
    cpu = $1 + 0
    if (cpu <= 0) {
      next
    }

    command = $0
    sub(/^[[:space:]]*[0-9.]+[[:space:]]+/, "", command)
    label = label_for(command)
    if (is_sampler_noise(label)) {
      next
    }

    totals[label] += cpu
  }

  END {
    for (label in totals) {
      printf "%.6f\t%s\n", totals[label], label
    }
  }
' | sort -nr | head -n 10 | awk '
  function fmt(pct) {
    if (pct < 10) {
      return sprintf("%.2f%%", pct)
    } else if (pct < 100) {
      return sprintf("%.1f%%", pct)
    }
    return sprintf("%.0f%%", pct)
  }

  {
    cpu = $1 + 0
    label = $0
    sub(/^[^\t]*\t/, "", label)
    printf "%2d. %s: %s | font=Monaco size=12\n", NR, label, fmt(cpu)
  }
'

echo "---"
echo "刷新 | refresh=true"
echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
