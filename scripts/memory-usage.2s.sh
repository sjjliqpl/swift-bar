#!/bin/bash

ERROR_LOG="/tmp/swiftbar-memory-usage.err"

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

format_bytes() {
  awk -v bytes="$1" '
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
      bytes += 0
      if (bytes >= 1073741824) {
        print3(bytes / 1073741824, "GB")
      } else if (bytes >= 1048576) {
        print3(bytes / 1048576, "MB")
      } else if (bytes >= 1024) {
        print3(bytes / 1024, "KB")
      } else {
        printf "%.0fB", bytes
      }
    }
  '
}

print_top_memory_processes() {
  LC_ALL=C ps -axo pid=,rss=,comm= 2>>"$ERROR_LOG" |
    LC_ALL=C sort -k2 -nr |
    awk '
      function basename(path) {
        sub(/^.*\//, "", path)
        return path
      }

      function format_bytes(bytes, value, unit) {
        if (bytes >= 1073741824) {
          value = bytes / 1073741824
          unit = "GB"
        } else if (bytes >= 1048576) {
          value = bytes / 1048576
          unit = "MB"
        } else if (bytes >= 1024) {
          value = bytes / 1024
          unit = "KB"
        } else {
          printf "%.0fB", bytes
          return
        }

        if (value < 10) {
          printf "%.2f%s", value, unit
        } else if (value < 100) {
          printf "%.1f%s", value, unit
        } else {
          printf "%.0f%s", value, unit
        }
      }

      $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
        pid = $1
        rss_bytes = $2 * 1024
        $1 = ""
        $2 = ""
        sub(/^  */, "")
        name = basename($0)
        if (name == "") {
          name = "pid " pid
        }
        gsub(/\|/, "/", name)

        printf "%d. %s: ", ++count, name
        format_bytes(rss_bytes)
        printf " | font=Monaco size=12\n"

        if (count >= 5) {
          exit
        }
      }

      END {
        if (count == 0) {
          print "无法读取进程内存统计"
        }
      }
    '
}

TOTAL_BYTES=$(sysctl -n hw.memsize 2>>"$ERROR_LOG")
VM_STAT=$(vm_stat 2>>"$ERROR_LOG")

if [ -z "$TOTAL_BYTES" ] || [ -z "$VM_STAT" ]; then
  echo "MEM ERR | font=Monaco size=12 trim=false"
  echo "---"
  echo "无法读取内存统计"
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

read -r PAGE_SIZE FREE SPECULATIVE ACTIVE INACTIVE WIRED COMPRESSOR PURGEABLE FILE_BACKED ANONYMOUS <<EOF
$(printf '%s\n' "$VM_STAT" | awk '
  BEGIN { page_size = 4096 }
  /page size of/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "of") {
        page_size = $(i + 1) + 0
      }
    }
  }
  /^Pages free:/ { free = $3 + 0 }
  /^Pages speculative:/ { speculative = $3 + 0 }
  /^Pages active:/ { active = $3 + 0 }
  /^Pages inactive:/ { inactive = $3 + 0 }
  /^Pages wired down:/ { wired = $4 + 0 }
  /^Pages occupied by compressor:/ { compressor = $5 + 0 }
  /^Pages purgeable:/ { purgeable = $3 + 0 }
  /^File-backed pages:/ { file_backed = $3 + 0 }
  /^Anonymous pages:/ { anonymous = $3 + 0 }
  END {
    print page_size, free, speculative, active, inactive, wired, compressor, purgeable, file_backed, anonymous
  }
')
EOF

if [ -z "$PAGE_SIZE" ]; then
  echo "MEM ERR | font=Monaco size=12 trim=false"
  echo "---"
  echo "无法解析 vm_stat 输出"
  echo "---"
  echo "刷新 | refresh=true"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

FREE_BYTES=$(((FREE + SPECULATIVE) * PAGE_SIZE))
ACTIVE_BYTES=$((ACTIVE * PAGE_SIZE))
INACTIVE_BYTES=$((INACTIVE * PAGE_SIZE))
WIRED_BYTES=$((WIRED * PAGE_SIZE))
COMPRESSOR_BYTES=$((COMPRESSOR * PAGE_SIZE))
PURGEABLE_BYTES=$((PURGEABLE * PAGE_SIZE))
FILE_BACKED_BYTES=$((FILE_BACKED * PAGE_SIZE))
ANONYMOUS_BYTES=$((ANONYMOUS * PAGE_SIZE))

APP_BYTES=$((ANONYMOUS_BYTES + WIRED_BYTES + COMPRESSOR_BYTES))
CACHED_BYTES=$((FILE_BACKED_BYTES + PURGEABLE_BYTES))
ALLOCATED_BYTES=$((TOTAL_BYTES - FREE_BYTES))

if [ "$APP_BYTES" -lt 0 ]; then
  APP_BYTES=0
fi

if [ "$ALLOCATED_BYTES" -lt 0 ]; then
  ALLOCATED_BYTES=0
fi

AVAILABLE_BYTES=$((TOTAL_BYTES - APP_BYTES))
if [ "$AVAILABLE_BYTES" -lt 0 ]; then
  AVAILABLE_BYTES=0
fi

USED_PCT=$(awk -v used="$APP_BYTES" -v total="$TOTAL_BYTES" 'BEGIN { if (total > 0) printf "%.6f", used * 100 / total; else print 0 }')
USED_DISPLAY=$(format_percent "$USED_PCT")

SWAP_LINE=$(sysctl -n vm.swapusage 2>>"$ERROR_LOG")
SWAP_USED=$(printf '%s\n' "$SWAP_LINE" | awk '{ for (i = 1; i <= NF; i++) if ($i == "used") { gsub(/M/, "", $(i + 2)); print $(i + 2); exit } }')
SWAP_TOTAL=$(printf '%s\n' "$SWAP_LINE" | awk '{ for (i = 1; i <= NF; i++) if ($i == "total") { gsub(/M/, "", $(i + 2)); print $(i + 2); exit } }')

echo "MEM $USED_DISPLAY | font=Monaco size=12 trim=false"
echo "---"
echo "内存占用: $(format_bytes "$APP_BYTES") / $(format_bytes "$TOTAL_BYTES") ($USED_DISPLAY) | font=Monaco size=12"
echo "可用估算: $(format_bytes "$AVAILABLE_BYTES") | font=Monaco size=12"
echo "---"
echo "App/匿名+有线+压缩: $(format_bytes "$APP_BYTES")"
echo "活跃: $(format_bytes "$ACTIVE_BYTES")"
echo "非活跃: $(format_bytes "$INACTIVE_BYTES")"
echo "有线: $(format_bytes "$WIRED_BYTES")"
echo "压缩器占用: $(format_bytes "$COMPRESSOR_BYTES")"
echo "文件缓存/可清理: $(format_bytes "$CACHED_BYTES")"
echo "物理已分配/含缓存: $(format_bytes "$ALLOCATED_BYTES")"
echo "空闲页: $(format_bytes "$FREE_BYTES")"
echo "---"
echo "进程内存 Top 5"
print_top_memory_processes
echo "---"
if [ -n "$SWAP_USED" ] && [ -n "$SWAP_TOTAL" ]; then
  echo "Swap: $(format_bytes "$(awk -v mb="$SWAP_USED" 'BEGIN { printf "%.0f", mb * 1048576 }')") / $(format_bytes "$(awk -v mb="$SWAP_TOTAL" 'BEGIN { printf "%.0f", mb * 1048576 }')")"
else
  echo "Swap: 未知"
fi
echo "---"
echo "刷新 | refresh=true"
echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
