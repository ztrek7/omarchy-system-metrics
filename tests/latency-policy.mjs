// Exercise the widget's actual probe gate without loading a desktop or pinging.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../BarWidget.qml", import.meta.url), "utf8");
const enabled = source.match(/readonly property bool latencyEnabled: ([\s\S]*?\n  \})\)/)?.[1] + ")";
const probe = source.match(/function probeLatency\(\) \{[\s\S]*?\n  \}/)?.[0];
assert.ok(probe, "Widget probe function must be found");

for (const [items, expected] of [
  [["cpu", "mem"], false],
  [[], false],
  [["cpu", "ping"], true],
  [["latency"], true],
  [["PING"], true],
]) {
  const context = { items, latencyProbe: { running: false } };
  vm.runInNewContext(`const latencyEnabled = ${enabled}; ${probe}; probeLatency();`, context);
  assert.equal(context.latencyProbe.running, expected, JSON.stringify(items));
}

let starts = 0;
const context = {
  items: ["ping"],
  latencyProbe: { get running() { return true; }, set running(_) { starts++; } },
};
vm.runInNewContext(`const latencyEnabled = ${enabled}; ${probe}; probeLatency();`, context);
assert.equal(starts, 0, "An active probe must not be started again");
console.log("Latency probe policy: passed");
