# System Metrics for Omarchy

A compact bar widget for CPU, RAM, NVIDIA GPU usage and memory, network
throughput, and latency. It follows your Omarchy theme and supports horizontal
and vertical bars.

![System Metrics widget showing CPU, RAM, GPU, network throughput, and latency](preview.png)

*Preview rendered from the widget with sample readings; no live system data.*

## Install

Requires Omarchy 4.x with its Quickshell-based shell.

```bash
omarchy plugin add https://github.com/ztrek7/omarchy-system-metrics --enable
```

The default placement is the right side of the bar. Hover for detailed readings.
Left-click opens **btop**; right-click opens **nvtop**, if those optional tools
are installed. The plugin does not install them. To add them on Omarchy:

```bash
omarchy pkg add btop nvtop
```

## Configure

Edit this widget's entry in your existing `~/.config/omarchy/shell.json` bar
layout, preserving surrounding widgets. Changes reload automatically.

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

- Reorder or remove entries in `items` to choose what appears.
- Leave `interface` empty to follow the IPv4 default route, or set an interface name.
- Set `latencyTarget` to `gateway` for the local router, or to a specific IP/hostname.
- **Remove both `ping` and `latency` from `items` to stop probes.** An already
  running probe may finish.

See the [configuration reference](docs/REFERENCE.md#configuration) for every setting.

## Limits and privacy

**GPU readings are NVIDIA-only**, using optional `nvidia-smi`; only the first GPU
is shown. AMD and Intel GPU readings are not implemented. Unavailable GPU cells
are hidden. Polling can wake a discrete GPU.

**Latency is ping, not DNS lookup time or a DNS health check.** By default, each
widget sends one ICMP echo request to a configured DNS server every **five seconds**.
A server that blocks ICMP can show a dash while DNS still works. The target can
see your source IP and requests; hostname targets can also cause DNS lookups.
There is no hardcoded public fallback. Hiding latency stops new probes.

Metrics stay in the running widget: no telemetry, metrics uploads, or persistent
history. Sampling reads local system counters. The code runs with your desktop
user's permissions; review changes before installing or updating.

Latency requires `ping` from `iputils`, `timeout`, and `awk`; systemd-resolved
stub setups also need `resolvectl`. Automatic interface discovery uses IPv4;
IPv6-only setups need an explicit interface and reachable target. VPN routing
and split DNS may differ from the single path measured here. See the
[network and dependency reference](docs/REFERENCE.md#dependencies-and-network-discovery).

## Update or remove

```bash
omarchy plugin update io.github.ztrek7.system-metrics
omarchy plugin remove io.github.ztrek7.system-metrics
```

Removal stops the sampling and latency timers. There is no separate daemon or
stored metrics history to clean up.

## Help and development

[Report a problem or ask a question](https://github.com/ztrek7/omarchy-system-metrics/issues).
The [reference](docs/REFERENCE.md) covers counters, DNS selection, and offline checks.

MIT. See [LICENSE](LICENSE).
