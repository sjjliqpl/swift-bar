#!/usr/bin/env bash

set -o pipefail

URL="https://cc.nf.video/8081/api/applet/codex/openai/users/dashboard"
COOKIE="${NF_VIDEO_COOKIE:-}"
ERROR_LOG="/tmp/swiftbar-balance.err"

run_check() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    return 1
  fi

  if [ -z "$COOKIE" ]; then
    echo "NF_VIDEO_COOKIE is required" >&2
    return 1
  fi

  response_file="$(mktemp)"
  trap 'rm -f "$response_file"' RETURN

  http_code="$(
    curl --silent --show-error --location \
      --connect-timeout 8 \
      --max-time 20 \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$URL" \
      -H 'accept: application/json, text/plain, */*' \
      -H 'accept-language: zh-CN,zh;q=0.9' \
      -H 'priority: u=1, i' \
      -H 'referer: https://cc.nf.video/claude/web/points' \
      -H 'sec-ch-ua: "Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"' \
      -H 'sec-ch-ua-mobile: ?0' \
      -H 'sec-ch-ua-platform: "macOS"' \
      -H 'sec-fetch-dest: empty' \
      -H 'sec-fetch-mode: cors' \
      -H 'sec-fetch-site: same-origin' \
      -H 'sys_type: shop' \
      -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36' \
      -b "$COOKIE"
  )"

  curl_status=$?
  if [ "$curl_status" -ne 0 ]; then
    echo "curl failed with status $curl_status" >&2
    return "$curl_status"
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "HTTP $http_code" >&2
    sed -n '1,20p' "$response_file" >&2
    return 1
  fi

  jq -er '
    if (.success != true) then
      error(.message // "request failed")
    elif (.data | type) != "object" then
      error("missing data")
    else
      .data as $d
      | def money_round: tonumber | round;
        def compact_tokens:
          tonumber as $n
          | if $n >= 10000000 then
              "\($n / 100000000 | . * 100 | round / 100)亿"
            elif $n > 1000 then
              "\($n / 10000 | . * 100 | round / 100)万"
            else
              "\($n)"
            end;
        [
          "$\($d.daily_remaining | money_round)",
          "\($d.today_tokens | compact_tokens)",
          "今日剩余: $\($d.daily_remaining | tonumber | . * 100 | round / 100) / $\($d.daily_total | tonumber | . * 100 | round / 100)",
          "今日已用: $\($d.today_cost | tonumber | . * 100 | round / 100)",
          "今日请求: \($d.today_requests)",
          "今日 Tokens: \($d.today_tokens | compact_tokens)",
          "本月剩余: $\($d.month_remaining | tonumber | . * 100 | round / 100) / $\($d.month_total | tonumber | . * 100 | round / 100)",
          "本月 Tokens: \($d.month_tokens | compact_tokens)",
          "更新时间: \($d.last_updated)"
        ]
        | .[]
    end
  ' "$response_file"
}

BALANCE_OUTPUT="$(run_check 2>"$ERROR_LOG")"
BALANCE="$(printf '%s\n' "$BALANCE_OUTPUT" | sed -n '1p')"
TOKEN="$(printf '%s\n' "$BALANCE_OUTPUT" | sed -n '2p')"

if [ -z "$BALANCE" ]; then
  echo "余额: ERR"
  echo "---"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

echo "$BALANCE / $TOKEN | font=Monaco size=12 trim=false"
echo "---"
printf '%s\n' "$BALANCE_OUTPUT" | sed '1d'
echo "---"
echo "刷新 | refresh=true"
echo "打开日志 | bash=open param1=$ERROR_LOG terminal=false"
