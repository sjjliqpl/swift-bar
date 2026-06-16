#!/usr/bin/env bash

set -o pipefail

URL="https://platform.deepseek.com/api/v0/users/get_user_summary"
AUTH_TOKEN="${DEEPSEEK_TOKEN:-}"
ERROR_LOG="/tmp/swiftbar-deepseek-balance.err"

run_check() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    return 1
  fi

  if [ -z "$AUTH_TOKEN" ]; then
    echo "DEEPSEEK_TOKEN is required" >&2
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
      -H 'accept: */*' \
      -H 'accept-language: zh-CN,zh;q=0.9' \
      -H "authorization: Bearer $AUTH_TOKEN" \
      -H 'priority: u=1, i' \
      -H 'referer: https://platform.deepseek.com/usage' \
      -H 'sec-ch-ua: "Chromium";v="148", "Google Chrome";v="148", "Not/A)Brand";v="99"' \
      -H 'sec-ch-ua-mobile: ?1' \
      -H 'sec-ch-ua-platform: "iOS"' \
      -H 'sec-fetch-dest: empty' \
      -H 'sec-fetch-mode: cors' \
      -H 'sec-fetch-site: same-origin' \
      -H 'user-agent: Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1' \
      -H 'x-app-version: 1.0.0' \
      -H 'x-client-bundle-id: com.deepseek.chat' \
      -H 'x-client-locale: zh_CN' \
      -H 'x-client-platform: web' \
      -H 'x-client-timezone-offset: 28800' \
      -H 'x-client-version: 1.0.0'
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
    if (.code != 0) then
      error(.msg // "request failed")
    elif (.data.biz_code != 0) then
      error(.data.biz_msg // "business request failed")
    elif (.data.biz_data | type) != "object" then
      error("missing biz_data")
    else
      .data.biz_data as $d
      | def num: tonumber? // 0;
        def money:
          num | "¥\(. * 100 | round / 100)";
        def compact_tokens:
          num as $n
          | if $n >= 100000000 then
              "\($n / 100000000 | . * 100 | round / 100)亿"
            elif $n >= 10000 then
              "\($n / 10000 | . * 100 | round / 100)万"
            else
              "\($n | floor)"
            end;
        def wallet_sum($name):
          [($d[$name] // [])[] | select(.currency == "CNY") | .balance | num] | add // 0;
        def wallet_tokens($name):
          [($d[$name] // [])[] | select(.currency == "CNY") | .token_estimation | num] | add // 0;
        def monthly_cost:
          [($d.monthly_costs // [])[] | select(.currency == "CNY") | .amount | num] | add // 0;
        (wallet_sum("normal_wallets")) as $normal_balance
        | (wallet_sum("bonus_wallets")) as $bonus_balance
        | (wallet_tokens("normal_wallets")) as $normal_tokens
        | (wallet_tokens("bonus_wallets")) as $bonus_tokens
        | ($normal_balance + $bonus_balance) as $total_balance
        | [
          ($total_balance | money),
          ($d.total_available_token_estimation | compact_tokens),
          "可用余额: \($total_balance | money)",
          "普通余额: \($normal_balance | money) / \($normal_tokens | compact_tokens) Tokens",
          "赠送余额: \($bonus_balance | money) / \($bonus_tokens | compact_tokens) Tokens",
          "可用 Tokens: \($d.total_available_token_estimation | compact_tokens)",
          "本月花费: \(monthly_cost | money)",
          "本月 Tokens: \($d.monthly_token_usage | compact_tokens)",
          "当前 Token 额度: \($d.current_token | compact_tokens)"
        ]
        | .[]
    end
  ' "$response_file"
}

BALANCE_OUTPUT="$(run_check 2>"$ERROR_LOG")"
BALANCE="$(printf '%s\n' "$BALANCE_OUTPUT" | sed -n '1p')"

if [ -z "$BALANCE" ]; then
  echo "DeepSeek: ERR"
  echo "---"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  exit 0
fi

echo "$BALANCE | font=Monaco size=12 trim=false"
echo "---"
printf '%s\n' "$BALANCE_OUTPUT" | sed '1d'
echo "---"
echo "刷新 | refresh=true"
echo "打开错误 | bash=open param1=$ERROR_LOG terminal=false"
