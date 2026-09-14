#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SWIFTBAR_STOCK_CONFIG:-$SCRIPT_DIR/stock-change.conf}"
ERROR_LOG="/tmp/swiftbar-stock-change.err"
URL_BASE="http://qt.gtimg.cn/q="

: >"$ERROR_LOG"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

CACHE_DIR="${TMPDIR:-/tmp}"
SWITCH_SECONDS="${switch_seconds:-10}"

print_error() {
  printf '%s\n' "$1" >>"$ERROR_LOG"

  echo "股票 ERR | font=Monaco size=12 trim=false"
  echo "---"
  echo "$1"
}

is_trading_time() {
  day_of_week="$(date '+%u')"
  current_hm="$(date '+%H%M')"

  [ "$day_of_week" -ge 1 ] && [ "$day_of_week" -le 5 ] &&
    {
      { [ "$current_hm" -ge 930 ] && [ "$current_hm" -le 1130 ]; } ||
        { [ "$current_hm" -ge 1300 ] && [ "$current_hm" -le 1500 ]; }
    }
}

normalize_stock_id() {
  stock_id="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  case "$stock_id" in
    sh[0-9][0-9][0-9][0-9][0-9][0-9]|sz[0-9][0-9][0-9][0-9][0-9][0-9])
      printf '%s' "$stock_id"
      ;;
    [0-9][0-9][0-9][0-9][0-9][0-9])
      case "$stock_id" in
        60*|68*|90*) printf 'sh%s' "$stock_id" ;;
        *) printf 'sz%s' "$stock_id" ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

load_stock_ids() {
  raw_ids="${ids:-}"

  if [ -z "$raw_ids" ]; then
    raw_ids="${STOCK_ID:-${STOCK_CODE:-${id:-}}}"
  fi

  if [ -z "$raw_ids" ]; then
    echo "STOCK_ID is required" >&2
    print_error "请先在配置文件里设置 ids"
    exit 0
  fi

  IFS=',' read -r -a CONFIGURED_IDS <<<"$raw_ids"
  NORMALIZED_STOCK_IDS=()

  for configured_id in "${CONFIGURED_IDS[@]}"; do
    normalized_id="$(normalize_stock_id "$configured_id")"
    if [ -z "$normalized_id" ]; then
      echo "invalid stock id: $configured_id" >&2
      print_error "股票 ID 格式不正确: $configured_id"
      exit 0
    fi
    NORMALIZED_STOCK_IDS+=("$normalized_id")
  done

  if [ "${#NORMALIZED_STOCK_IDS[@]}" -eq 0 ]; then
    echo "no stock ids configured" >&2
    print_error "请先在配置文件里设置 ids"
    exit 0
  fi
}

select_stock_id() {
  case "$SWITCH_SECONDS" in
    ''|*[!0-9]*|0) SWITCH_SECONDS=10 ;;
  esac

  stock_count="${#NORMALIZED_STOCK_IDS[@]}"
  now_seconds="$(date '+%s')"
  current_index=$(((now_seconds / SWITCH_SECONDS) % stock_count))
  NORMALIZED_STOCK_ID="${NORMALIZED_STOCK_IDS[$current_index]}"
}

format_change_percent() {
  awk -v pct="$1" '
    BEGIN {
      pct += 0
      if (pct > 0) {
        printf "+%.2f%%", pct
      } else {
        printf "%.2f%%", pct
      }
    }
  '
}

format_price_percent() {
  awk -v price="$1" -v prev="$2" '
    BEGIN {
      price += 0
      prev += 0
      if (prev == 0) {
        printf "--"
        exit
      }

      pct = (price - prev) / prev * 100
      if (pct > 0) {
        printf "+%.2f%%", pct
      } else {
        printf "%.2f%%", pct
      }
    }
  '
}

format_amount() {
  awk -v value="$1" '
    BEGIN {
      value += 0
      if (value >= 10000) {
        printf "%.2f亿", value / 10000
      } else {
        printf "%.2f万", value
      }
    }
  '
}

format_volume() {
  awk -v value="$1" '
    BEGIN {
      value += 0
      if (value >= 10000) {
        printf "%.2f万手", value / 10000
      } else {
        printf "%.0f手", value
      }
    }
  '
}

format_datetime() {
  value="$1"

  if [ "${#value}" -ge 14 ]; then
    printf '%s-%s-%s %s:%s:%s' \
      "${value:0:4}" "${value:4:2}" "${value:6:2}" \
      "${value:8:2}" "${value:10:2}" "${value:12:2}"
  else
    printf '%s' "$value"
  fi
}

stock_menu_label() {
  stock_name="$1"
  change_display="$2"

  if [ -n "$stock_name" ]; then
    prefix="$(printf '%s' "$stock_name" | LC_CTYPE=UTF-8 cut -c 1-2)"
  else
    prefix="$(stock_id_prefix)"
  fi

  printf '%s %s' "$prefix" "$change_display"
}

stock_id_prefix() {
  printf '%s' "$NORMALIZED_STOCK_ID" | LC_CTYPE=UTF-8 cut -c 1-2
}

print_book_row() {
  buy_label="$1"
  buy_price="$2"
  buy_quantity="$3"
  sell_label="$4"
  sell_price="$5"
  sell_quantity="$6"

  buy_text="$(printf '%s %s/%s手' "$buy_label" "$buy_price" "$buy_quantity")"
  sell_text="$(printf '%s %s/%s手' "$sell_label" "$sell_price" "$sell_quantity")"
  printf '%-24s %s | font=Monaco size=12\n' "$buy_text" "$sell_text"
}

print_stock_info() {
  source_label="$1"

  IFS='~' read -r -a FIELDS <<<"$DATA"

  NAME="${FIELDS[1]}"
  CODE="${FIELDS[2]}"
  LAST_PRICE="${FIELDS[3]}"
  PREV_CLOSE="${FIELDS[4]}"
  OPEN_PRICE="${FIELDS[5]}"
  DATE_TIME="${FIELDS[30]}"
  PRICE_CHANGE="${FIELDS[31]}"
  CHANGE_PERCENT="${FIELDS[32]}"
  HIGH_PRICE="${FIELDS[33]}"
  LOW_PRICE="${FIELDS[34]}"
  VOLUME="${FIELDS[36]}"
  TURNOVER_RATE="${FIELDS[38]}"
  AMPLITUDE="${FIELDS[43]}"
  PB="${FIELDS[46]}"
  PE="${FIELDS[52]}"
  AMOUNT="${FIELDS[57]}"

  if [ -z "$NAME" ] || [ -z "$CHANGE_PERCENT" ]; then
    echo "missing required fields: $DATA" >&2
    print_error "股票行情字段不完整"
    exit 0
  fi

  CHANGE_DISPLAY="$(format_change_percent "$CHANGE_PERCENT")"
  AMOUNT_DISPLAY="$(format_amount "$AMOUNT")"
  VOLUME_DISPLAY="$(format_volume "$VOLUME")"
  TIME_DISPLAY="$(format_datetime "$DATE_TIME")"
  OPEN_PERCENT="$(format_price_percent "$OPEN_PRICE" "$PREV_CLOSE")"
  HIGH_PERCENT="$(format_price_percent "$HIGH_PRICE" "$PREV_CLOSE")"
  LOW_PERCENT="$(format_price_percent "$LOW_PRICE" "$PREV_CLOSE")"
  MENU_LABEL="$(stock_menu_label "$NAME" "$CHANGE_DISPLAY")"

  echo "$MENU_LABEL | font=Monaco size=12 trim=false"
  echo "---"
  echo "$NAME ($CODE) | font=Monaco size=12"
  if [ -n "$source_label" ]; then
    echo "$source_label"
  fi
  echo "最新: $LAST_PRICE    涨跌: $PRICE_CHANGE ($CHANGE_DISPLAY)"
  echo "开盘: $OPEN_PERCENT    高低: $HIGH_PERCENT / $LOW_PERCENT"
  echo "量额: $VOLUME_DISPLAY / $AMOUNT_DISPLAY"
  echo "换手/振幅: ${TURNOVER_RATE}% / ${AMPLITUDE}%"
  echo "估值: PB $PB / PE $PE"
  echo "时间: $TIME_DISPLAY"
  echo "---"
  printf '%-24s %s | font=Monaco size=12\n' "买盘" "卖盘"
  print_book_row "买一" "${FIELDS[9]}" "${FIELDS[10]}" "卖一" "${FIELDS[19]}" "${FIELDS[20]}"
  print_book_row "买二" "${FIELDS[11]}" "${FIELDS[12]}" "卖二" "${FIELDS[21]}" "${FIELDS[22]}"
  print_book_row "买三" "${FIELDS[13]}" "${FIELDS[14]}" "卖三" "${FIELDS[23]}" "${FIELDS[24]}"
  print_book_row "买四" "${FIELDS[15]}" "${FIELDS[16]}" "卖四" "${FIELDS[25]}" "${FIELDS[26]}"
  print_book_row "买五" "${FIELDS[17]}" "${FIELDS[18]}" "卖五" "${FIELDS[27]}" "${FIELDS[28]}"
}

load_stock_ids
select_stock_id

CACHE_FILE="$CACHE_DIR/swiftbar-stock-change-${NORMALIZED_STOCK_ID}.cache"

if ! is_trading_time; then
  if [ -f "$CACHE_FILE" ]; then
    DATA="$(sed -n '1p' "$CACHE_FILE")"
    print_stock_info ""
  else
    echo "$(stock_id_prefix) -- | font=Monaco size=12 trim=false"
    echo "---"
    echo "暂无缓存数据"
  fi
  exit 0
fi

RAW_RESPONSE="$(
  curl --silent --show-error --location \
    --connect-timeout 8 \
    --max-time 12 \
    "${URL_BASE}${NORMALIZED_STOCK_ID}" 2>>"$ERROR_LOG"
)"
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ]; then
  echo "curl failed with status $CURL_STATUS" >&2
  print_error "请求股票行情失败"
  exit 0
fi

if command -v iconv >/dev/null 2>&1; then
  RESPONSE="$(printf '%s' "$RAW_RESPONSE" | iconv -f GB18030 -t UTF-8 2>>"$ERROR_LOG")"
else
  RESPONSE="$RAW_RESPONSE"
fi

DATA="$(printf '%s' "$RESPONSE" | sed -n 's/^.*="\([^"]*\)".*$/\1/p')"
if [ -z "$DATA" ]; then
  echo "unexpected response: $RESPONSE" >&2
  print_error "无法解析股票行情返回"
  exit 0
fi

IFS='~' read -r -a FIELDS <<<"$DATA"
NAME="${FIELDS[1]}"
CHANGE_PERCENT="${FIELDS[32]}"

if [ -z "$NAME" ] || [ -z "$CHANGE_PERCENT" ]; then
  echo "missing required fields: $RESPONSE" >&2
  print_error "股票行情字段不完整"
  exit 0
fi

printf '%s\n' "$DATA" >"$CACHE_FILE"
print_stock_info ""
