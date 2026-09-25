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
function load(file, names, globals = {}) {
    const src = fs.readFileSync(path.join(__dirname, '../../.config/quickshell/' + file), 'utf8');
    const ctx = vm.createContext(globals);
    for (const name of names) {
        const head = `    function ${name}\\([^)]*\\) \\{`;
        const one = src.match(new RegExp(head + '[^\\n]*\\}$', 'm'));       // one-line function
        vm.runInContext((one || src.match(new RegExp(head + '[\\s\\S]*?^    \\}', 'm')))[0], ctx);
    }
    return ctx;
}
const sys = load('services/Sysmon.qml', ['cpuSample', 'cpuPercent', 'memPercent']);
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

const wx = load('services/Weather.qml', ['parse', 'icon']);
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

// Audio: the real functions against fake PipeWire nodes.
const node = (id, name, type, extra = {}) => Object.assign({id, name, type, description: name + ' desc',
    properties: {}, audio: {volume: 0.5, muted: false}}, extra);
const T = {AudioSink: 1, AudioSource: 2, AudioOutStream: 3};
const spk = node(62, 'dock', T.AudioSink), hdmi = node(64, 'hdmi', T.AudioSink), mic = node(63, 'mic', T.AudioSource);
const ff = node(116, 'Firefox', T.AudioOutStream, {properties: {'application.name': 'Firefox'},
                                                   audio: {volume: 0.29, muted: false}});
const bare = node(117, 'spotify', T.AudioOutStream, {audio: {volume: 1, muted: true}});
const pw = {nodes: {values: [spk, hdmi, mic, ff, bare]}, preferredDefaultAudioSink: null,
            preferredDefaultAudioSource: null};
const au = load('services/Audio.qml', ['devices', 'appEntry', 'parseStates', 'setVolume', 'setAppVolume',
    'setDefaultSink', 'setDefaultSource', 'setPreferred'], {Pipewire: pw, PwNodeType: T});
Object.assign(au, {root: au, ready: true, sink: spk, streams: [ff, bare],
    states: {dock: 'running', hdmi: 'suspended'}});
const sinks = JSON.parse(JSON.stringify(au.devices(T.AudioSink, spk)));
assert.deepEqual(sinks, [
    {name: 'dock', desc: 'dock desc', index: 62, state: 'running', isDefault: true},
    {name: 'hdmi', desc: 'hdmi desc', index: 64, state: 'suspended', isDefault: false}]);
assert.deepEqual(JSON.parse(JSON.stringify(au.devices(T.AudioSource, null))).map(d => [d.name, d.state, d.isDefault]),
                 [['mic', '', false]]);                               // unknown state: empty label
assert.deepEqual(JSON.parse(JSON.stringify([ff, bare].map(au.appEntry))), [
    {index: 116, volume: 29, muted: false, appName: 'Firefox'},
    {index: 117, volume: 100, muted: true, appName: 'spotify'}]);    // falls back to the node name
assert.deepEqual(JSON.parse(JSON.stringify(au.parseStates(
    '62\tdock\tPipeWire\ts24le 2ch 48000Hz\tRUNNING\n64\thdmi\tPipeWire\ts32le 2ch 48000Hz\tSUSPENDED\n\n'))),
    {dock: 'running', hdmi: 'suspended'});
au.setVolume(2); assert.equal(spk.audio.volume, 1.5);                 // same 150% ceiling as before
au.setVolume(-1); assert.equal(spk.audio.volume, 0);
au.ready = false; au.setVolume(0.7); assert.equal(spk.audio.volume, 0); au.ready = true;
au.setAppVolume(116, 140); assert.equal(ff.audio.volume, 1);
au.setAppVolume(116, 30); assert.equal(ff.audio.volume, 0.3);
au.setAppVolume(999, 50);                                             // vanished stream: no throw
au.setDefaultSink('hdmi'); assert.equal(pw.preferredDefaultAudioSink, hdmi);
au.setDefaultSource('mic'); assert.equal(pw.preferredDefaultAudioSource, mic);
au.setDefaultSink('gone'); assert.equal(pw.preferredDefaultAudioSink, hdmi);   // unknown name: unchanged
console.log('PASS: Audio device/app lists (pactl-compatible shapes), state labels, volume clamps, default device');

// OSD: show on change after the first reading, as the 500 ms wpctl poll did.
const fakeAudio = {ready: false, volume: 0, muted: false};
let shown = 0;
const osd = load('components/OSD.qml', ['check'], {Audio: fakeAudio});
Object.assign(osd, {root: osd, prevVolume: -1, prevMuted: false, showOSD: () => shown++});
osd.check(); assert.equal(shown, 0);                                  // not ready: ignored
Object.assign(fakeAudio, {ready: true, volume: 0.29}); osd.check(); assert.equal(shown, 0);  // first reading
fakeAudio.volume = 0.293; osd.check(); assert.equal(shown, 0);        // below 0.5%: no popup
fakeAudio.volume = 0.34; osd.check(); assert.equal(shown, 1);
fakeAudio.muted = true; osd.check(); assert.equal(shown, 2);
osd.check(); assert.equal(shown, 2);                                  // no change, no popup
console.log('PASS: OSD appears only on real volume/mute changes');
