# System Metrics reference

[Back to the README](../README.md)

## Configuration

Edit this widget's entry in your existing `~/.config/omarchy/shell.json` bar
layout. Preserve the surrounding layout and other widgets. Changes reload
automatically.

```json
{
  "id": "io.github.ztrek7.system-metrics",
  "items": ["cpu", "mem", "gpu", "gpumem", "down", "up", "ping"],
  "interval": 2,
  "alertPercent": 90,
  "interface": "",
  "latencyTarget": "dns",
  "latencyInterval": 5,
  "latencyAlertMs": 150
}
```

| Setting | Meaning |
| --- | --- |
| `items` | Metrics to show, in order. Remove an entry to hide it. `latency` is an alias for `ping`. |
| `interval` | Seconds between counter samples, minimum 0.5. |
| `alertPercent` | CPU, RAM, GPU, or GPU-memory percentage that triggers the alert color. |
| `interface` | Network interface name; empty follows the lowest-metric IPv4 default route. |
| `latencyTarget` | `dns` (default) for a configured DNS server, `gateway` for the IPv4 default gateway, or an explicit IP address/hostname. |
| `latencyInterval` | Seconds between latency probes, minimum 1. |
| `latencyAlertMs` | Round-trip time that triggers the alert color. An unanswered probe also alerts. |

The default `dns` target is discovered again before each probe, so changes
to the network or DNS settings are picked up automatically. This is **ping
latency to the DNS server**, not DNS lookup time or a DNS health check.
A DNS server that blocks ICMP shows as unavailable even if DNS works.

For local-link latency, set `"latencyTarget": "gateway"`. To stop latency
probes entirely, remove both `ping` and `latency` from `items`. An already
running probe may finish after the setting changes.

Rates use binary units: `K` is 1,024 bytes and `M` is 1,048,576 bytes. The
bar shows bytes per second for upload/download; the tooltip adds `/s`.
RAM usage is total minus Linux's available-memory estimate, including
reclaimable memory in the available figure. Hover for the detailed readings.

## Dependencies and network discovery

- Bash 5+ and readable Linux `/proc` and `/sys` counters.
- Omarchy 4.x, Quickshell, and the shell's usual icon font and UI modules.
- `ping` from `iputils` for latency; a failed or unavailable probe shows a dash.
- `awk` for systemd-resolved status parsing, and `timeout` from coreutils.
  `resolvectl` is needed when `/etc/resolv.conf` uses systemd-resolved's stub.
- Optional `nvidia-smi` for GPU readings. Only the first NVIDIA GPU is shown;
  AMD and Intel GPU readings are not implemented. GPU cells disappear when
  utilization cannot be read. Polling may wake a discrete GPU.
- Optional `btop` and `nvtop` for the click actions.

The plugin does not install packages. On Omarchy, optional tools can be
installed with `omarchy pkg add btop nvtop`.

Automatic interface and gateway discovery uses the IPv4 route table. On an
IPv6-only system, set `interface` explicitly and use a reachable latency
target. Policy routing and VPNs may differ from the route this widget picks;
the widget does not aggregate traffic across interfaces.

DNS discovery uses the first nameserver in `/etc/resolv.conf`. For
systemd-resolved's `127.0.0.53` or `127.0.0.54` stub, it reads `resolvectl
status` and prefers a catch-all DNS route (`~.`), then a default DNS link,
then global DNS. It uses the current server, or the first configured server
when no current one is reported. If multiple links have equal priority, the
first reported suitable link is used. Domain-specific split DNS can use
other servers for particular queries; a single ping cannot represent all
of them. IPv6 DNS addresses are supported, including link-local scope IDs
reported or inferred from resolved's link name.

Other local DNS proxies cannot reliably be mapped to an upstream server.
An unknown upstream, unavailable resolver status, or missing DNS configuration
shows a dash rather than pinging localhost or a hardcoded public server.
Set an explicit target if you want to monitor a particular server instead.

## Data sources

The scripts read CPU and memory counters from `/proc`, network counters from
`/sys`, local DNS configuration from `/etc/resolv.conf` and, when needed,
`resolvectl status`, and optional NVIDIA readings through `nvidia-smi`. They do not read
credentials, browser profiles, clipboard contents, or personal documents.
Click actions launch local monitoring tools through Omarchy. The plugin
itself does not modify user configuration or require root.

Like other Omarchy plugins, this code runs with your desktop user's
permissions. Review source changes before installing or updating.

## Development checks

Tests require Python 3 and Node.js; neither is a runtime dependency.
The tests use a fake `ping` and do not send network requests.

```bash
omarchy plugin validate .
bash -n sample.sh latency.sh
python3 -m unittest discover -s tests
node tests/latency-policy.mjs
```
