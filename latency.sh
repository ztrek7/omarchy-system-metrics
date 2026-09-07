#!/usr/bin/env bash
# Round-trip time in milliseconds to the given target, or -1 when nothing
# answered. Kept out of sample.sh because a probe can block for the whole
# timeout, and a stalled ping must not stretch the window the throughput and
# CPU rates are averaged over.
#
# The literal target "gateway" resolves to the current default gateway, which
# measures the link to the router rather than the path to the internet.

set -uo pipefail
export LC_ALL=C

target="${1:-1.1.1.1}"

if [[ $target == gateway ]]; then
  target=""
  best=""
  while read -r _ dest gw _ _ _ metric _; do
    [[ $dest == 00000000 && $gw != 00000000 ]] || continue
    if [[ -z $best || $metric -lt $best ]]; then
      best=$metric
      # /proc/net/route holds the gateway as a little-endian hex word.
      target="$((16#${gw:6:2})).$((16#${gw:4:2})).$((16#${gw:2:2})).$((16#${gw:0:2}))"
    fi
  done </proc/net/route
fi

if [[ -z $target ]]; then
  echo -1
  exit 0
fi

# -q prints only the summary; the average of a single probe is that probe.
if ! summary=$(ping -n -q -c 1 -W 1 -- "$target" 2>/dev/null); then
  echo -1
  exit 0
fi

stats=${summary##*= }
stats=${stats%% *}
IFS=/ read -r _ avg _ <<<"$stats"

if [[ ${avg:-} =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "$avg"
else
  echo -1
fi
