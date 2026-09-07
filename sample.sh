#!/usr/bin/env bash
# One metrics sample for the io.github.ztrek7.system-metrics bar widget, printed as a single
# space-separated line. Counters are emitted raw; the widget differences
# consecutive samples into rates and percentages.
#
# Everything but the GPU read is a builtin read of /proc or /sys, so a tick
# costs one fork for nvidia-smi rather than a pipeline per metric.
#
# Fields: cpuTotal cpuIdle memTotalKb memAvailKb rxBytes txBytes
#         gpuUtil gpuMemUsedMb gpuMemTotalMb clockSeconds iface
# gpuUtil is -1 when there is no NVIDIA GPU to ask; iface is "-" when no
# default route exists, in which case the byte counters are 0.

set -uo pipefail

iface="${1-}"

# The interface carrying the default route, lowest metric wins. tailscale0
# and a wired link can both hold one, and the lowest metric is the one the
# traffic a user thinks of as "the network" actually leaves by.
if [[ -z $iface ]]; then
  best=""
  while read -r dev dest _ _ _ _ metric _; do
    [[ $dest == 00000000 ]] || continue
    if [[ -z $best || $metric -lt $best ]]; then
      best=$metric
      iface=$dev
    fi
  done </proc/net/route
fi

read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
cpuTotal=$((user + nice + system + idle + iowait + irq + softirq + steal))
cpuIdle=$((idle + iowait))

memTotal=0
memAvail=0
while read -r key value _; do
  case $key in
    MemTotal:) memTotal=$value ;;
    MemAvailable:)
      memAvail=$value
      break
      ;;
  esac
done </proc/meminfo

rx=0
tx=0
if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
  read -r rx <"/sys/class/net/$iface/statistics/rx_bytes"
  read -r tx <"/sys/class/net/$iface/statistics/tx_bytes"
fi

gpuUtil=-1
gpuUsed=0
gpuTotal=0
if command -v nvidia-smi >/dev/null 2>&1; then
  # "12, 317, 6144" -> three fields; comma and space both delimit.
  IFS=', ' read -r util used total < <(nvidia-smi \
    --query-gpu=utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null)
  if [[ -n ${util:-} && $util =~ ^[0-9]+$ ]]; then
    gpuUtil=$util
    gpuUsed=${used:-0}
    gpuTotal=${total:-0}
  fi
fi

printf '%s %s %s %s %s %s %s %s %s %s %s\n' \
  "$cpuTotal" "$cpuIdle" "$memTotal" "$memAvail" "$rx" "$tx" \
  "$gpuUtil" "$gpuUsed" "$gpuTotal" "${EPOCHREALTIME/,/.}" "${iface:--}"
