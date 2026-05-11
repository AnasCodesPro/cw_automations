#!/usr/bin/env bash

# Purpose: Debug server load (clean + safe version)

set -euo pipefail

APPS_DIR="/home/master/applications"

cd "$APPS_DIR" || {
  echo "Error: Cannot access $APPS_DIR"
  exit 1
}

# -----------------------------
# Validate dependencies
# -----------------------------
if ! command -v apm >/dev/null 2>&1; then
  echo "Error: 'apm' command not found"
  exit 1
fi

# -----------------------------
# Inputs
# -----------------------------
date_to_check="${1:-}"
time_in_UTC="${2:-}"
interval_in_mins="${3:-}"
iv="${4:-min}"

# -----------------------------
# Helpers
# -----------------------------
print_header() {
  echo
  echo "---------------- APPLICATION MONITORING STATS ----------------"
  echo
}

get_app_list() {
  # safer than ls parsing
  find . -maxdepth 1 -mindepth 1 -type d -printf "%f\n"
}

build_time_range() {
  local date_input="$1"
  local time_input="$2"
  local interval="$3"
  local unit="$4"

  local dd mm yy
  dd=$(cut -d '/' -f1 <<< "$date_input")
  mm=$(cut -d '/' -f2 <<< "$date_input")
  yy=$(cut -d '/' -f3 <<< "$date_input")

  local date_new="${mm}/${dd}/${yy}"
  local base_time="${date_input}:${time_input}"

  local offset_time
  offset_time=$(date --date="${date_new} ${time_input} UTC ${interval} ${unit}" -u +'%d/%m/%Y:%H:%M')

  local op="${interval:0:1}"

  local from_param until_param
  if [[ "$op" == "-" ]]; then
    from_param="$offset_time"
    until_param="$base_time"
  else
    from_param="$base_time"
    until_param="$offset_time"
  fi

  echo "$from_param|$until_param"
}

get_top_apps() {
  local from="$1"
  local until="$2"

  local app counts app count

  declare -A counts

  while IFS= read -r app; do
    count=$(sudo apm -s "$app" traffic --statuses -f "$from" -u "$until" -j \
      | grep -Po '\d+","?\d*' \
      | cut -d ',' -f2 \
      | head -n1 || echo 0)

    counts["$app"]="$count"
  done < <(get_app_list)

  for app in "${!counts[@]}"; do
    echo "$app:${counts[$app]}"
  done | sort -t ':' -k2 -nr | cut -d ':' -f1 | head -n 5
}

show_app_stats() {
  local app="$1"
  local from="$2"
  local until="$3"

  echo
  echo "DB: $app"

  if [[ -f "$app/conf/server.nginx" ]]; then
    awk '{print $NF}' "$app/conf/server.nginx" | head -n1
  fi

  sudo apm -s "$app" traffic -n5 -f "$from" -u "$until"
  sudo apm -s "$app" mysql   -n5 -f "$from" -u "$until"
  sudo apm -s "$app" php --slow_pages -n5 -f "$from" -u "$until"
}

show_slow_plugins() {
  local app="$1"
  local log_file="/home/master/applications/$app/logs/php-app.slow.log"

  [[ -f "$log_file" ]] || return

  local slow_plugins
  slow_plugins=$(grep -ai 'wp-content/plugins' "$log_file" \
    | cut -d " " -f1 --complement \
    | cut -d '/' -f8 \
    | sort | uniq -c | sort -nr)

  if [[ -n "$slow_plugins" ]]; then
    echo
    echo "--- Slow plugins ---"
    echo "$slow_plugins"
    echo "--------------------"
  fi
}

# -----------------------------
# Main logic
# -----------------------------
print_header

if [[ -z "$date_to_check" && -z "$time_in_UTC" && -z "$interval_in_mins" ]]; then

  read -rp "Enter duration (e.g. 1h, 30m): " dur

  echo "Fetching logs for last $dur ..."

  while IFS= read -r app; do
    echo "DB: $app"

    sudo apm traffic -s "$app" -l "$dur" -n5
    sudo apm mysql   -s "$app" -l "$dur" -n5
    sudo apm php     -s "$app" --slow_pages -l "$dur" -n5

    show_slow_plugins "$app"

  done < <(get_app_list)

elif [[ -z "$iv" ]]; then

  iv="min"
  IFS='|' read -r from_param until_param <<< "$(build_time_range "$date_to_check" "$time_in_UTC" "$interval_in_mins" "$iv")"

  echo "Stats from $from_param to $until_param"

  for app in $(get_top_apps "$from_param" "$until_param"); do
    show_app_stats "$app" "$from_param" "$until_param"
  done

else

  IFS='|' read -r from_param until_param <<< "$(build_time_range "$date_to_check" "$time_in_UTC" "$interval_in_mins" "$iv")"

  echo "Stats from $from_param to $until_param"

  for app in $(get_top_apps "$from_param" "$until_param"); do
    show_app_stats "$app" "$from_param" "$until_param"
  done

fi
