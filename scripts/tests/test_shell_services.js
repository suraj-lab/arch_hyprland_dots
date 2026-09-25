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

// Pure helpers of Sysmon and Weather: load the real function bodies from the QML.
function load(file, names) {
    const src = fs.readFileSync(path.join(__dirname, '../../.config/quickshell/services/' + file), 'utf8');
    const ctx = vm.createContext({});
    for (const name of names)
        vm.runInContext(src.match(new RegExp(`    function ${name}\\([^)]*\\) \\{[\\s\\S]*?^    \\}`, 'm'))[0], ctx);
    return ctx;
}
const sys = load('Sysmon.qml', ['cpuSample', 'cpuPercent', 'memPercent']);
// user nice system idle iowait irq softirq steal (guest columns ignored)
const a = sys.cpuSample('cpu  100 0 100 700 100 0 0 0 5 5\ncpu0 1 2 3');
const b = sys.cpuSample('cpu  200 0 150 850 200 0 0 0 5 5\n');
assert.deepEqual([a.idle, a.total], [700, 1000]);
assert.equal(sys.cpuPercent(a, b), 63);            // 150 idle of 400 = 62.5% busy; iowait counts as busy (vmstat 'id')
assert.equal(sys.cpuPercent(a, a), -1);            // no elapsed ticks: unknown, not 0 or NaN
assert.equal(sys.memPercent('MemTotal: 1000 kB\nMemFree: 1 kB\nMemAvailable: 250 kB\n'), 75);
assert.equal(sys.memPercent('MemTotal: 1000 kB\n'), -1);
assert.equal(sys.memPercent('MemTotal: 0 kB\nMemAvailable: 0 kB\n'), -1);
console.log('PASS: Sysmon CPU (vmstat-equivalent) and memory (free-equivalent) maths');

const wx = load('Weather.qml', ['parse', 'icon']);
const hourly = code => Array.from({length: 8}, (_, i) => ({weatherCode: i === 4 ? code : '999'}));
const sample = {
    current_condition: [{temp_C: '12', FeelsLikeC: '10', humidity: '80', windspeedKmph: '15',
                          weatherCode: '116', weatherDesc: [{value: 'Partly cloudy'}]}],
    weather: ['113', '266', '338', '200'].map((c, i) => ({date: `2026-09-2${i}`, maxtempC: '20',
                                                          mintempC: '9', hourly: hourly(c)})),
};
const w = wx.parse(JSON.stringify(sample));
assert.deepEqual([w.temp, w.desc, w.feels, w.humidity, w.wind, w.code],
                 ['12', 'Partly cloudy', '10', '80', '15', '116']);
assert.deepEqual(JSON.parse(JSON.stringify(w.forecastDays.map(d => d.code))), ['113', '266', '338']); // 3 days, midday code (copy: vm arrays have another prototype)
assert.throws(() => wx.parse(''));
assert.throws(() => wx.parse('{"current_condition": []}'));
assert.equal(wx.icon('113'), '\uf185');
assert.equal(wx.icon('338'), '\uf2dc');
console.log('PASS: Weather parsing, 3-day forecast and malformed-response rejection');
