#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SWIFTBAR_ENV_FILE:-$SCRIPT_DIR/.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

BASE_URL="${NEWAPI_URL:-https://newapi.igong.com:31080}"
COOKIE="${NEWAPI_COOKIE:-}"
USER_ID="${NEWAPI_USER_ID:-1}"
DAILY_QUOTA="${NEWAPI_DAILY_QUOTA:-}"
ERROR_LOG="/tmp/swiftbar-newapi-usage.err"

request_json() {
  local url="$1"
  local output_file="$2"
  local http_code

  http_code="$(
    curl --silent --show-error --location \
      --connect-timeout 8 \
      --max-time 20 \
      --output "$output_file" \
      --write-out '%{http_code}' \
      "$url" \
      -H 'accept: application/json, text/plain, */*' \
      -H 'cache-control: no-cache' \
      -H "New-Api-User: $USER_ID" \
      -H 'user-agent: SwiftBar-NewAPI-Usage/1.0' \
      -b "$COOKIE"
  )"

  local curl_status=$?
  if [ "$curl_status" -ne 0 ]; then
    echo "curl failed with status $curl_status" >&2
    return "$curl_status"
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "HTTP $http_code" >&2
    sed -n '1,20p' "$output_file" >&2
    return 1
  fi
}

epoch_for_today() {
  date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') 00:00:00" '+%s'
}

run_check() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    return 1
  fi

  if [ -z "$COOKIE" ]; then
    echo "NEWAPI_COOKIE is required" >&2
    return 1
  fi

  if ! printf '%s' "$DAILY_QUOTA" | jq -eR 'tonumber > 0' >/dev/null 2>&1; then
    echo "NEWAPI_DAILY_QUOTA must be a positive USD amount" >&2
    return 1
  fi

  local status_file data_file users_file
  status_file="$(mktemp)"
  data_file="$(mktemp)"
  users_file="$(mktemp)"
  trap 'rm -f "$status_file" "$data_file" "$users_file"' EXIT

  local start_timestamp end_timestamp
  start_timestamp="$(epoch_for_today)"
  end_timestamp="$(date '+%s')"

  if ! request_json "$BASE_URL/api/status" "$status_file"; then
    return 1
  fi

  if ! request_json "$BASE_URL/api/data/?username=&start_timestamp=$start_timestamp&end_timestamp=$end_timestamp&default_time=hour" "$data_file"; then
    return 1
  fi

  if ! request_json "$BASE_URL/api/data/users?start_timestamp=$start_timestamp&end_timestamp=$end_timestamp" "$users_file"; then
    return 1
  fi

  jq -ner \
    --arg daily_quota "$DAILY_QUOTA" \
    --arg updated_at "$(date '+%Y-%m-%d %H:%M:%S')" \
    --slurpfile status "$status_file" \
    --slurpfile usage "$data_file" \
    --slurpfile users "$users_file" '
      ($status[0]) as $statusData
      | ($usage[0]) as $usageData
      | ($users[0]) as $usersData
      | if $statusData.success != true then
          error($statusData.message // "status request failed")
        elif $usageData.success != true then
          error($usageData.message // "usage request failed")
        elif $usersData.success != true then
          error($usersData.message // "user usage request failed")
        elif ($usageData.data | type) != "array" then
          error("missing usage data")
        elif ($usersData.data | type) != "array" then
          error("missing user usage data")
        else
          ($daily_quota | tonumber) as $dailyTotal
          | ($statusData.data.quota_per_unit // 500000 | tonumber) as $quotaPerUnit
          | ($usageData.data | map(.quota // 0 | tonumber) | add // 0) as $usedQuota
          | ($usageData.data | map(.token_used // 0 | tonumber) | add // 0) as $usedTokens
          | ($usageData.data | map(.count // 0 | tonumber) | add // 0) as $requests
          | ($usedQuota / $quotaPerUnit) as $usedAmount
          | ($dailyTotal - $usedAmount) as $remaining
          | ($usersData.data
              | map({
                  username: (.username // "未知用户"),
                  quota: (.quota // 0 | tonumber),
                  tokens: (.token_used // 0 | tonumber)
                })
              | sort_by(.username)
              | group_by(.username)
              | map({
                  username: .[0].username,
                  quota: (map(.quota) | add // 0),
                  tokens: (map(.tokens) | add // 0)
                })
              | sort_by(.quota)
              | reverse
              | .[0:5]) as $topUsers
          | def decimal1:
              (. * 10 | round) as $scaled
              | if ($scaled % 10) == 0 then
                  "\($scaled / 10).0"
                else
                  "\($scaled / 10)"
                end;
            def money2: . * 100 | round / 100;
            def compact_tokens:
              tonumber as $n
              | if $n >= 10000000 then
                  "\($n / 100000000 | decimal1)亿"
                elif $n > 1000 then
                  "\($n / 10000 | decimal1)万"
                else
                  "\($n | round)"
                end;
            def user_line($entry):
              "\($entry.key + 1). \($entry.value.username) / $\($entry.value.quota / $quotaPerUnit | money2) / \($entry.value.tokens | compact_tokens)";
            ([
              "$\($remaining | round)",
              "\($usedTokens | compact_tokens)",
              "今日剩余: $\($remaining | money2) / $\($dailyTotal | money2)",
              "今日已用: $\($usedAmount | money2)",
              "今日请求: \($requests | round)",
              "今日 Tokens: \($usedTokens | compact_tokens)",
              "---",
              "今日用户 Top 5 | color=gray",
              ($topUsers | to_entries[] | user_line(.)),
              "更新时间: \($updated_at)"
            ] | flatten)
            | .[]
        end
    '
}

USAGE_OUTPUT="$(run_check 2>"$ERROR_LOG")"
BALANCE="$(printf '%s\n' "$USAGE_OUTPUT" | sed -n '1p')"
TOKENS="$(printf '%s\n' "$USAGE_OUTPUT" | sed -n '2p')"

if [ -z "$BALANCE" ]; then
  echo "余额: ERR"
  echo "---"
  echo "查看错误 | bash=open param1=$ERROR_LOG terminal=false"
  echo "刷新 | refresh=true"
  exit 0
fi

echo "$BALANCE / $TOKENS | font=Monaco size=12 trim=false"
echo "---"
printf '%s\n' "$USAGE_OUTPUT" | sed '1,2d'
echo "---"
echo "刷新 | refresh=true"
echo "打开日志 | bash=open param1=$ERROR_LOG terminal=false"
