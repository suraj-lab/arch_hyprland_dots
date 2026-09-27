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
for (const [code, glyph] of [['113', '\ue30d'], ['116', '\ue302'], ['122', '\ue312'], ['248', '\ue313'],
                             ['200', '\ue31d'], ['392', '\ue31d'], ['179', '\ue31a'], ['230', '\ue31a'],
                             ['338', '\ue31a'], ['371', '\ue31a'], ['176', '\ue318'], ['266', '\ue318'],
                             ['308', '\ue318'], ['350', '\ue318'], ['', '\ue312'], ['999', '\ue318']])
    assert.equal(wx.icon(code), glyph, `weather code ${code}`);   // thunder/snow before the rain range
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

// Net: the real functions with fake NetworkManager networks.
const Sec = {Open: 0, Wpa2Psk: 1, toString: v => (v === 0 ? 'Open' : 'WPA2')};
const wnet = (name, extra = {}) => Object.assign({name, connected: false, known: false, signalStrength: 0.5,
    security: Sec.Wpa2Psk, connects: 0, connect() { this.connects++; }}, extra);
const home = wnet('home', {connected: true, known: true, signalStrength: 0.72});
const strong = wnet('cafe', {signalStrength: 0.9, security: Sec.Open});
const saved = wnet('office', {known: true, signalStrength: 0.4});
const hostile = wnet("x'; touch /tmp/pwned; echo '", {signalStrength: 0.3});
const hidden = wnet('', {signalStrength: 0.99});
const dispatched2 = [];
const net = load('services/Net.qml', ['entry', 'sortNetworks', 'connect'],
    {WifiSecurityType: Sec, Hypr: {dispatch: lua => dispatched2.push(lua)}});
Object.assign(net, {root: net, wifiDevice: {networks: {values: [saved, hostile, strong, home, hidden]}}});
const list = JSON.parse(JSON.stringify(net.sortNetworks(net.wifiDevice.networks.values)));
assert.deepEqual(list.map(n => n.ssid), ['home', 'cafe', 'office', hostile.name]);  // connected first, no hidden
assert.deepEqual(list[0], {inUse: true, ssid: 'home', signal: 72, known: true, security: 'WPA2'});
assert.equal(list[1].security, '');                                   // open: no label, like nmcli '--'
net.connect('office'); net.connect('cafe'); net.connect('missing');
assert.deepEqual([saved.connects, strong.connects, dispatched2.length], [1, 1, 0]);  // known/open: native
net.connect(hostile.name);                                            // new secured: terminal fallback
assert.equal(dispatched2.length, 1);
const lua = dispatched2[0];
const arg = JSON.parse(lua.match(/^hl\.dsp\.exec_cmd\(("(?:[^"\\]|\\.)*")/)[1]);    // the Lua string == JSON string
assert.equal(arg, "ghostty -e nmcli dev wifi connect 'x'\\''; touch /tmp/pwned; echo '\\''' --ask");
const {execFileSync} = require('node:child_process');                // sh sees exactly one argument
const argv = execFileSync('sh', ['-c', arg.replace('ghostty -e ', 'printf "%s\\n" '), 'sh'], {encoding: 'utf8'});
assert.deepEqual(argv.trimEnd().split('\n'), ['nmcli', 'dev', 'wifi', 'connect', hostile.name, '--ask']);
console.log('PASS: Net list order/labels, native connect for known/open, untrusted SSID stays one argument');

const bt = load('services/Bt.qml', ['toggle']);
bt.adapter = {enabled: true}; bt.toggle(); assert.equal(bt.adapter.enabled, false);
bt.adapter = null; bt.toggle();                                       // no adapter: no throw
console.log('PASS: Bt power toggle');

// Brightness: parse the real `ddcutil detect --brief` output into connector → bus.
const io = {running: false, command: [], writing: false};
const br = load('services/Brightness.qml', ['parseDetect', 'parseReading', 'read', 'set', 'flush'], {ioProc: io});
Object.assign(br, {root: br, ready: true, buses: [8, 10], readBus: 8,
    pendingValue: -1, readRequested: false, brightness: 0, error: ''});
const detect = `Display 1
   I2C bus:          /dev/i2c-8
   DRM connector:    card1-HDMI-A-1
   drm_connector_id: 471
   Monitor:          VSC:VX2476 Series:UPA213310203

Display 2
   I2C bus:          /dev/i2c-10
   DRM connector:    card1-DP-2
   drm_connector_id: 458
   Monitor:          DEL:AW3423DWF:70742S3
`;
assert.deepEqual(JSON.parse(JSON.stringify(br.parseDetect(detect))), {'HDMI-A-1': 8, 'DP-2': 10});
assert.deepEqual(JSON.parse(JSON.stringify(br.parseDetect('garbage\nI2C bus: /dev/i2c-7\nno connector'))), {});
assert.deepEqual(JSON.parse(JSON.stringify(br.parseDetect(detect + `
Invalid display
   I2C bus: /dev/i2c-12
   DRM connector: card1-DP-3
   DDC communication failed
Display 3
   DRM connector: card1-DP-4
`))), {'HDMI-A-1': 8, 'DP-2': 10});
assert.deepEqual(JSON.parse(JSON.stringify(br.parseDetect(`Display 1
   I2C bus: /dev/i2c-0
   DRM connector: card0-DP-1
`))), {'DP-1': 0});
assert.equal(br.parseReading('VCP 10 C 28 100\n'), 0.28);
assert.equal(br.parseReading('VCP 10 C 50 200\n'), 0.25);
for (const invalid of ['', 'VCP 10 ERR', 'VCP 10 C 0 0', 'VCP 10 C 101 100', 'VCP 10 C -1 100'])
    assert.equal(br.parseReading(invalid), -1);
br.set(0.4);
const firstCommand = JSON.stringify(io.command);
br.set(0.7); br.set(0.9); br.read();
assert.equal(JSON.stringify(io.command), firstCommand);              // never replace a running command
assert.equal(br.pendingValue, 90);
io.running = false; br.flush();
assert.equal(io.command[4], '90');                                  // latest drag value, not the intermediate 70
assert.deepEqual(Array.from(io.command).slice(5), ['8', '10']);
io.running = false; br.flush();
assert.deepEqual(Array.from(io.command), ['ddcutil', 'getvcp', '10', '--bus', '8', '--brief']);
assert.equal(br.readRequested, false);
io.running = false;
for (const invalid of [NaN, Infinity, -Infinity, '0.5', null]) br.set(invalid);
assert.equal(io.running, false);
br.ready = false; br.set(0.5); assert.equal(io.running, false);
br.ready = true; br.set(-1); assert.equal(io.command[4], '5');
console.log('PASS: Brightness detection, read validation, latest-value queue and invalid-input guards');

const config = load('services/Config.qml', ['validBuses']);
for (const invalid of [null, [], '8', 8, true])
    assert.deepEqual(JSON.parse(JSON.stringify(config.validBuses(invalid))), {});
assert.deepEqual(JSON.parse(JSON.stringify(config.validBuses({
    'DP-2': 10, 'HDMI-A-1': 8, 'DP-1-1': 0, 'DP-3': '7', 'DP-4': -1,
    'DP-5': 1.5, 'DP-6': Infinity, 'DP-7': 2147483648, '$(touch pwned)': 5
}))), {'DP-2': 10, 'HDMI-A-1': 8, 'DP-1-1': 0});
console.log('PASS: Config validates optional connector-to-bus overrides');

// Dashboard pure helpers.
const dash = load('components/pill/surfaces/Dashboard.qml', ['formatUptime', 'parseDf', 'gib', 'monthOffset', 'formatTime']);
assert.equal(dash.formatUptime(59), 'up 0m');
assert.equal(dash.formatUptime(25921.76), 'up 7h 12m');
assert.equal(dash.formatUptime(2 * 86400 + 3 * 3600 + 59), 'up 2d 3h');
assert.equal(dash.formatUptime(NaN), '');
assert.equal(dash.formatUptime(-5), '');
assert.deepEqual(JSON.parse(JSON.stringify(dash.parseDf('     1B-blocks          Used\n999653638144 438086393856\n'))),
                 {size: 999653638144, used: 438086393856});
assert.equal(dash.parseDf(''), null);
assert.equal(dash.parseDf('Size Used\n0 0\n'), null);                  // no division by zero later
assert.equal(dash.parseDf('Size Used\nabc def\n'), null);
assert.equal(dash.gib(1724985344), '1.6 GiB');
assert.equal(dash.gib(999653638144), '931 GiB');
assert.equal(dash.monthOffset(2026, 8), 1);                             // 1 Sep 2026 is a Tuesday (Mon-first)
assert.equal(dash.monthOffset(2026, 10), 6);                            // 1 Nov 2026 is a Sunday
for (const [sec, text] of [[0, '0:00'], [9.9, '0:09'], [75, '1:15'], [3599, '59:59'], [3605, '1:00:05'], [NaN, '0:00'], [-3, '0:00']])
    assert.equal(dash.formatTime(sec), text, `formatTime(${sec})`);
console.log('PASS: Dashboard uptime, df parsing, GiB, Monday-first calendar offset, track times');

// Media: Spotify first, then playing players, then the rest (stable).
const media = load('services/Media.qml', ['isSpotify', 'rank', 'order', 'controllable']);
const pl = (identity, isPlaying, desktopEntry = '') => ({identity, isPlaying, desktopEntry});
const mFirefox = pl('Mozilla Firefox', true), mSpotify = pl('Spotify', false), mVlc = pl('VLC media player', false),
      mMpv = pl('mpv', true), mSpotifyDesk = pl('', false, 'spotify-launcher');
const names = list => Array.from(media.order(list)).map(p => p.identity || p.desktopEntry);
assert.deepEqual(names([mFirefox, mVlc, mSpotify, mMpv]), ['Spotify', 'Mozilla Firefox', 'mpv', 'VLC media player']);
assert.deepEqual(names([mVlc, mFirefox]), ['Mozilla Firefox', 'VLC media player']);
assert.deepEqual(names([mSpotifyDesk, mFirefox]), ['spotify-launcher', 'Mozilla Firefox']);   // matched by desktop entry
assert.deepEqual(names([]), []);
const bus = (dbusName, extra = {}) => Object.assign({dbusName, canTogglePlaying: true, trackTitle: 't'}, extra);
assert.deepEqual(Array.from(media.controllable([bus('org.mpris.MediaPlayer2.spotify'), bus('org.mpris.MediaPlayer2.playerctld'),
    bus('org.mpris.MediaPlayer2.firefox.instance_1_42'), bus('org.mpris.MediaPlayer2.idle', {canTogglePlaying: false, trackTitle: ''})]))
    .map(p => p.dbusName), ['org.mpris.MediaPlayer2.spotify', 'org.mpris.MediaPlayer2.firefox.instance_1_42']);
console.log('PASS: Media order (Spotify first, then playing, stable); playerctld proxy and idle players filtered');

// Launcher (SPEC 5.1): app filter/ranking, categories, actions filter, cliphist parsing.
const launcher = load('components/pill/surfaces/Launcher.qml',
    ['appCategories', 'filterApps', 'filterActions', 'parseClips']);
const catMap = {Game: 'Games', Network: 'Internet', WebBrowser: 'Internet', Utility: 'Utilities'};
const appList = [
    {name: 'Firefox', genericName: 'Web Browser', categories: ['Network', 'WebBrowser'], keywords: ['internet']},
    {name: 'Steam', genericName: '', categories: ['Game'], keywords: []},
    {name: 'Kitty', genericName: 'Terminal', categories: ['Utility'], keywords: ['shell', 'prompt']},
    {name: 'Thunar', genericName: 'File Manager', categories: null, keywords: null},
];
const appNames = list => Array.from(list).map(a => a.name);
assert.deepEqual(Array.from(launcher.appCategories(appList, catMap)), ['All', 'Internet', 'Games', 'Utilities']);
assert.deepEqual(appNames(launcher.filterApps(appList, '', 'All', catMap)), ['Firefox', 'Steam', 'Kitty', 'Thunar']);
assert.deepEqual(appNames(launcher.filterApps(appList, '', 'Internet', catMap)), ['Firefox']);
assert.deepEqual(appNames(launcher.filterApps(appList, 'SHELL', 'All', catMap)), ['Kitty']);   // keywords, any case
assert.deepEqual(appNames(launcher.filterApps(appList, 'file', 'All', catMap)), ['Thunar']);   // generic name
// Names starting with the query rank first, the rest by name ("te": Firefox via the keyword
// "internet", Kitty via "Terminal", Steam by name).
assert.deepEqual(appNames(launcher.filterApps([...appList, {name: 'Terminator', categories: []}], 'te', 'All', catMap)),
    ['Terminator', 'Firefox', 'Kitty', 'Steam']);
assert.deepEqual(appNames(launcher.filterApps(appList, 'steam', 'Internet', catMap)), []);
const acts = [{id: 'reboot', title: 'Reboot'}, {id: 'screenshot', title: 'Screenshot'}, {id: 'dnd', title: 'Do Not Disturb'}];
assert.deepEqual(Array.from(launcher.filterActions(acts, '')).map(a => a.id), ['reboot', 'screenshot', 'dnd']);
assert.deepEqual(Array.from(launcher.filterActions(acts, 'S')).map(a => a.id), ['screenshot', 'dnd']);  // starts-with first
assert.deepEqual(Array.from(launcher.filterActions(acts, 'dnd')).map(a => a.id), ['dnd']);              // by id too
const clips = launcher.parseClips('12\thello world\n11\t[[ binary data 36 KiB png 1052x516 ]]\n'
    + '10\t  tabs\tinside  \n9\t[[ binary data 2 MiB jpeg 4000x3000 ]]\nnot a line\n\n');
assert.deepEqual(Array.from(clips).map(c => [c.id, c.text, c.ext]),
    [['12', 'hello world', ''], ['11', '[[ binary data 36 KiB png 1052x516 ]]', 'png'],
     ['10', '  tabs\tinside  ', ''], ['9', '[[ binary data 2 MiB jpeg 4000x3000 ]]', 'jpeg']]);
assert.equal(clips[2].line, '10\t  tabs\tinside  ');   // the raw line goes back to cliphist unchanged
console.log('PASS: Launcher app filter/ranking/categories, actions filter, cliphist parsing');

// Cheatsheet (SPEC 5.2): modmask decoding, key labels, grouping by description prefix.
const sheet = load('components/pill/surfaces/Cheatsheet.qml',
    ['modNames', 'keyLabel', 'parseBinds', 'filterGroups', 'balance']);
assert.deepEqual(Array.from(sheet.modNames(0)), []);
assert.deepEqual(Array.from(sheet.modNames(64 | 1)), ['Super', 'Shift']);
assert.deepEqual(Array.from(sheet.modNames(4 | 8 | 1)), ['Ctrl', 'Alt', 'Shift']);
assert.deepEqual(Array.from(sheet.modNames(255)), ['Super', 'Ctrl', 'Alt', 'Shift', 'Caps', 'Mod2', 'Mod3', 'Mod5']);
assert.deepEqual(['return', 'Space', 'slash', 'left', 'mouse:272', 'mouse_down', 'XF86AudioMicMute', 'c', 'F', '6', 'Print']
    .map(k => sheet.keyLabel(k)), ['Enter', 'Space', '/', '\u2190', 'Left drag', 'Scroll down', 'Mic mute', 'C', 'F', '6', 'Print']);
const bind = (modmask, key, description) =>
    ({modmask, key, description: description || '', has_description: !!description, dispatcher: '__lua', arg: '1'});
const groups = sheet.parseBinds([
    bind(64, 'return', 'Apps: Terminal'), bind(64, 'C', 'Windows: Close'), bind(64, 'E', 'Apps: File manager'),
    bind(65, 'left', 'Windows: Move left'), bind(64, 'SUPER_L', 'Shell: Double-tap Super expands the pill'),
    bind(0, 'XF86AudioMute', 'Media: Mute audio'), bind(8, 'M', ''), bind(64, 'X', 'Label without a group'),
]);
assert.deepEqual(Array.from(groups).map(g => g.name), ['Apps', 'Windows', 'Shell', 'Media', 'Other']);
assert.deepEqual(JSON.parse(JSON.stringify(groups[0].items)),
    [{keys: ['Super', 'Enter'], text: 'Terminal'}, {keys: ['Super', 'E'], text: 'File manager'}]);
assert.deepEqual(Array.from(groups[1].items[1].keys), ['Super', 'Shift', '\u2190']);
assert.deepEqual(Array.from(groups[2].items[0].keys), ['Super \u00d72']);        // double-tap, not "Super + Super_L"
assert.deepEqual(Array.from(groups[3].items[0].keys), ['Mute']);                 // no modifiers
assert.deepEqual(JSON.parse(JSON.stringify(groups[4].items)),                    // no prefix / no description
    [{keys: ['Alt', 'M'], text: 'No description'}, {keys: ['Super', 'X'], text: 'Label without a group'}]);
assert.deepEqual(Array.from(sheet.filterGroups(groups, '')).length, 5);
assert.deepEqual(JSON.parse(JSON.stringify(sheet.filterGroups(groups, 'FILE'))), [{name: 'Apps', items: [{keys: ['Super', 'E'], text: 'File manager'}]}]);
assert.deepEqual(Array.from(sheet.filterGroups(groups, 'windows')[0].items).length, 2);   // a group name keeps all
assert.deepEqual(Array.from(sheet.filterGroups(groups, 'shift')).map(g => g.name), ['Windows']);   // by key
assert.deepEqual(Array.from(sheet.filterGroups(groups, 'nothing here')), []);
const cols = sheet.balance([{name: 'A', items: [1, 2, 3, 4, 5, 6]}, {name: 'B', items: [1]}, {name: 'C', items: [1]},
    {name: 'D', items: [1, 2]}], 3);
assert.deepEqual(Array.from(cols).map(c => Array.from(c).map(g => g.name)), [['A'], ['D'], ['B', 'C']]);
// The live shape: one big late group must not stack onto an early column.
const sizes = {Media: 8, Screenshot: 2, Apps: 3, Windows: 15, Shell: 7, Session: 2, Workspaces: 16};
const live = sheet.balance(Object.entries(sizes).map(([name, n]) => ({name, items: Array(n).fill(0)})), 3);
const rows = Array.from(live).map(c => Array.from(c).reduce((s, g) => s + g.items.length + 1.5, 0));
assert.ok(Math.max(...rows) - Math.min(...rows) <= 2, rows);
assert.deepEqual(Array.from(live).map(c => Array.from(c).map(g => g.name)),
    [['Screenshot', 'Workspaces'], ['Apps', 'Windows'], ['Media', 'Shell', 'Session']]);   // original order kept
console.log('PASS: Cheatsheet modmask decoding, key labels, grouping, filter, balanced columns');

// Updates (SPEC 6.4): per-tool exit codes, item names, absent tools, the update command.
const upd = load('services/Updates.qml', ['parse', 'updateCommand']);
const plain = o => JSON.parse(JSON.stringify(o));
const all = upd.parse('@pacman\nbash 5.3.15-2 -> 5.3.20-2\ngspell 1.14.4-1.1 -> 1.14.5-1.1\n@pacman-exit 0\n'
    + '@flatpak\ncom.usebottles.bottles\norg.freedesktop.Platform.Compat.i386\n\n@flatpak-exit 0\n'
    + '@aur\nani-cli 5.0-1 -> 5.1-1\nlianli-linux-git 0.8.9.r0.g515ee32-1 -> latest-commit\n@aur-exit 0\n');
assert.deepEqual(plain(all), {
    pacman: {count: 2, items: ['bash', 'gspell'], ok: true, present: true},
    flatpak: {count: 2, items: ['com.usebottles.bottles', 'org.freedesktop.Platform.Compat.i386'], ok: true, present: true},
    aur: {count: 2, items: ['ani-cli', 'lianli-linux-git'], ok: true, present: true}});
// Nothing to do: checkupdates exits 2, paru -Qua exits 1 with no output.
assert.deepEqual(plain(upd.parse('@pacman\n@pacman-exit 2\n@flatpak\n@flatpak-exit 0\n@aur\n@aur-exit 1\n')), {
    pacman: {count: 0, items: [], ok: true, present: true}, flatpak: {count: 0, items: [], ok: true, present: true},
    aur: {count: 0, items: [], ok: true, present: true}});
// Failures (offline: checkupdates 1; timeout 124) are unknown, not zero; tools absent (127).
assert.deepEqual(plain(upd.parse('@pacman\n@pacman-exit 1\n@flatpak\n@flatpak-exit 127\n@aur\npartial -> x\n@aur-exit 124\n')), {
    pacman: {count: -1, items: [], ok: false, present: true}, flatpak: {count: -1, items: [], ok: false, present: false},
    aur: {count: -1, items: [], ok: false, present: true}});
assert.deepEqual(plain(upd.parse('')), {});                        // no output at all: nothing changes
assert.equal(upd.updateCommand(true, 0),
    "paru; qs ipc call updates check >/dev/null 2>&1; printf '\\nDone. Press Enter to close. '; read _");
assert.ok(upd.updateCommand(true, 3).startsWith('paru; flatpak update; qs ipc call updates check'));
assert.ok(upd.updateCommand(false, 0).startsWith('sudo pacman -Syu; qs ipc call updates check'));
console.log('PASS: Updates parsing (exit codes per tool, absent tools, failures stay unknown) and update command');
