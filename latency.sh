#!/usr/bin/env bash
# Round-trip time in milliseconds to the given target, or -1 when nothing
# answered. Kept out of sample.sh because a probe can block for the whole
# timeout, and a stalled ping must not stretch the window the throughput and
# CPU rates are averaged over.
#
# "dns" selects a configured upstream DNS server; "gateway" selects the
# IPv4 default gateway. This measures ICMP latency, not DNS query time.

set -uo pipefail
export LC_ALL=C

dns_from_status() {
  # resolved can route different domains over different links. Prefer a
  # catch-all (~.) DNS route, then a default DNS link, then global DNS.
  # Domain-specific VPN servers must not win merely by appearing first.
  awk '
    function save(    rank, server) {
      server = current != "" ? current : first
      sub(/#.*/, "", server)
      if (server ~ /^\[/) {
        sub(/^\[/, "", server)
        sub(/\].*/, "", server)
      } else if (server ~ /^[0-9.]+:[0-9]+$/) sub(/:[0-9]+$/, "", server)
      if (server == "" || server ~ /^127\./ || server == "::1" || server == "0.0.0.0" || server == "::") return
      if (tolower(server) ~ /^fe[89ab][0-9a-f]:/ && server !~ /%/ && iface != "") server = server "%" iface
      rank = catchall ? 3 : default_route ? 2 : global ? 1 : 0
      if (rank > best_rank) { best = server; best_rank = rank }
    }
    /^Global$|^Link [0-9]+ / {
      save()
      global = ($0 == "Global")
      current = first = iface = ""
      catchall = default_route = 0
      if (!global) { iface = $0; sub(/^[^(]*\(/, "", iface); sub(/\).*$/, "", iface) }
      next
    }
    /Current DNS Server:/ { current = $NF; next }
    /DNS Servers:/ { sub(/^.*DNS Servers:[[:space:]]*/, ""); split($0, servers, /[[:space:]]+/); first = servers[1]; next }
    /Protocols:/ { for (i = 1; i <= NF; i++) if ($i == "+DefaultRoute") default_route = 1 }
    /Default Route:/ { default_route = ($NF == "yes") }
    { for (i = 1; i <= NF; i++) if ($i == "~.") catchall = 1 }
    END { save(); if (best != "") print best }
  '
}

dns_target() {
  local resolver_file="${1:-/etc/resolv.conf}"
  local key server rest
  [[ -r $resolver_file ]] || return 0
  while read -r key server rest; do
    [[ $key == nameserver && -n $server ]] || continue
    if [[ $server == 127.0.0.53 || $server == 127.0.0.54 ]]; then
      # Query only when resolv.conf actually delegates to resolved. A
      # separately configured static resolver must take precedence.
      local status
      if status=$(timeout 2 resolvectl --no-pager status 2>/dev/null); then
        printf '%s\n' "$status" | dns_from_status
      fi
    elif [[ $server != 127.* && $server != ::1 && $server != 0.0.0.0 && $server != :: ]]; then
      printf '%s\n' "$server"
    fi
    # A different local resolver cannot safely be mapped to an upstream.
    # Do not substitute a public DNS server or measure localhost latency.
    return 0
  done <"$resolver_file"
}

main() {
  local target="${1:-dns}"

  if [[ $target == dns ]]; then
    target=$(dns_target)
  fi

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
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
