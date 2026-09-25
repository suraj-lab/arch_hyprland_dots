// Test the actual Hypr helper bodies without connecting to a compositor.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname,
    '../../.config/quickshell/services/Hypr.qml'), 'utf8');
const dispatched = [];
const Hyprland = {monitors: {values: []}, dispatch: lua => dispatched.push(lua)};
const context = vm.createContext({Hyprland});
vm.runInContext(source.match(/    function dispatch\(lua\) \{[^\n]+\}/)[0], context);
vm.runInContext(source.match(/    function isFullscreen\(monitorName\) \{[\s\S]*?^    \}/m)[0], context);
assert.equal(context.isFullscreen('missing'), false);
Hyprland.monitors.values = [
    {name: 'DP-2', activeWorkspace: {hasFullscreen: true}},
    {name: 'HDMI-A-1', activeWorkspace: {hasFullscreen: false}},
    {name: 'unassigned', activeWorkspace: null},
];
assert.equal(context.isFullscreen('DP-2'), true);
assert.equal(context.isFullscreen('HDMI-A-1'), false);
assert.equal(context.isFullscreen('unassigned'), false);
context.dispatch('hl.dsp.exit()');
assert.deepEqual(dispatched, ['hl.dsp.exit()']);
console.log('PASS: Hypr per-monitor fullscreen lookup and unchanged Lua dispatch');
