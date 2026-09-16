#!/usr/bin/env bash

set -u

run_algo="${1:-}"
run_id="${2:-}"
server_ip="10.20.20.20"
server_port="5201"
run_duration="90"
loss_start="30"
recovery_time="50"

usage() {
  echo "用法: $0 cubic|bbr run01"
}

case "$run_algo" in
  cubic|bbr) ;;
  *) usage; exit 2 ;;
esac

if [[ -z "$run_id" ]]; then
  usage
  exit 2
fi

for required_command in iperf3 ss date sleep grep; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "缺少命令: $required_command"
    exit 4
  fi
done

run_prefix="${run_algo}_${run_id}"
ss_log="${run_prefix}_ss.log"
event_log="${run_prefix}_events.log"
iperf_json="${run_prefix}_iperf.json"

for output_file in "$ss_log" "$event_log" "$iperf_json"; do
  if [[ -e "$output_file" ]]; then
    echo "拒绝覆盖已有文件: $output_file"
    exit 3
  fi
done

ss_sampler_pid=""
event_timer_pid=""

cleanup() {
  if [[ -n "$event_timer_pid" ]]; then
    kill "$event_timer_pid" 2>/dev/null || true
    wait "$event_timer_pid" 2>/dev/null || true
  fi
  if [[ -n "$ss_sampler_pid" ]]; then
    kill "$ss_sampler_pid" 2>/dev/null || true
    wait "$ss_sampler_pid" 2>/dev/null || true
  fi
}

notify_operator() {
  local notice="$1"
  if [[ -w /dev/tty ]]; then
    printf '\n%s\n' "$notice" > /dev/tty
  else
    printf '\n%s\n' "$notice" >&2
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

(
  while true; do
    date +%s.%N
    ss -tinp "( dport = :${server_port} )"
    sleep 0.2
  done
) > "$ss_log" 2>&1 &
ss_sampler_pid=$!

printf '%s phase=start loss=0\n' "$(date +%s.%N)" > "$event_log"

(
  sleep "$loss_start"
  printf '%s phase=loss loss=2\n' "$(date +%s.%N)" >> "$event_log"
  notify_operator "[T=${loss_start}s] 现在把 GNS3 Packet loss 改为 2% 并点击 Apply"

  sleep "$((recovery_time - loss_start))"
  printf '%s phase=recovery loss=0\n' "$(date +%s.%N)" >> "$event_log"
  notify_operator "[T=${recovery_time}s] 现在把 GNS3 Packet loss 改回 0% 并点击 Apply"
) &
event_timer_pid=$!

echo "开始 ${run_algo} ${run_id}：总时长 ${run_duration} 秒"

iperf_status=0
iperf3 -c "$server_ip" -p "$server_port" -t "$run_duration" -i 1 \
  -C "$run_algo" -J > "$iperf_json" || iperf_status=$?

printf '%s phase=end loss=0 iperf_status=%s\n' \
  "$(date +%s.%N)" "$iperf_status" >> "$event_log"

cleanup
ss_sampler_pid=""
event_timer_pid=""
trap - EXIT INT TERM

if (( iperf_status == 0 )); then
  grep -q '"sum_sent"' "$iperf_json" || exit 5
fi

echo "本轮结束，iperf3 状态码=$iperf_status"
echo "已生成: $iperf_json  $ss_log  $event_log"
exit "$iperf_status"
