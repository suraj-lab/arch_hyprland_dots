// Offline unit tests of the actual QML method bodies (not a duplicate policy).
// This does not test QML bindings, Process signal ordering, or Wayland integration.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname,
    '../../.config/quickshell/services/Desktop.qml'), 'utf8');
const pending = [];
const state = {
    gameModeOverride: 'auto', gamemodedActive: false, gameMode: false,
    gameModeError: '', dndEnabled: false, _gameChecked: false, _gamemodedKnown: true,
    gameModeProc: {running: false}, gameResult: {text: ''}, gameError: {text: ''},
    Quickshell: {shellDir: '/test'}, Qt: {callLater: fn => pending.push(fn)},
    console: {warn() {}},
    dndRequested(value) { state.dndEnabled = value; },
};
// Use the binding expression from the component as well.
const desired = source.match(/readonly property bool desiredGameMode: ([\s\S]*?)\n    readonly property/)[1];
Object.defineProperty(state, 'desiredGameMode', {get: () => vm.runInContext(desired, context)});
state.root = state;
const context = vm.createContext(state);
for (const name of ['toggleGameMode', 'syncGameMode']) {
    const body = source.match(new RegExp(`    function ${name}\\(\\) \\{([\\s\\S]*?)^    \\}`, 'm'))[1];
    vm.runInContext(`function ${name}() {${body}}`, context);
}
const complete = source.match(/id: gameModeProc[\s\S]*?onExited: function\(code\) \{([\s\S]*?)^        \}/m)[1];
vm.runInContext(`function complete(code) {${complete}}`, context);
const reset = source.match(/onGamemodedActiveChanged: \{([\s\S]*?)^    \}/m)[1];
function game(active) {
    state.gamemodedActive = active;
    vm.runInContext(reset, context);
}
function done(enabled, dnd, code = 0) {
    state.gameModeProc.running = false;
    state.gameResult.text = JSON.stringify({gameMode: enabled, dnd});
    state.complete(code);
    while (pending.length) pending.shift()();
}

state.toggleGameMode();
assert.equal(state.desiredGameMode, true);
state.toggleGameMode();
assert.equal(state.gameModeOverride, 'auto'); // manual off must not suppress the next game
// Forced off lasts only until the active game exits.
game(true);
state.toggleGameMode();
assert.equal(state.gameModeOverride, 'off');
game(false);
assert.equal(state.gameModeOverride, 'auto');
game(true);
assert.equal(state.desiredGameMode, true);

// Desired state changes while a command is running: final request wins.
state.syncGameMode();
assert.equal(state.gameModeProc.command[2], 'on');
state.toggleGameMode();
state.syncGameMode();
assert.equal(state.gameModeProc.command[2], 'on'); // in-flight command not overwritten
done(true, true);
assert.equal(state.gameModeProc.command[2], 'off');
assert.equal(state.gameModeProc.running, true);
done(false, false);
assert.equal(state.gameModeProc.running, false);
assert.equal(state.dndEnabled, false);

// No success acknowledgement means no optimistic chip/DND change or busy loop.
game(false);
state.toggleGameMode();
state.syncGameMode();
done(false, false, 1);
assert.equal(state.gameMode, false);
assert.equal(state.dndEnabled, false);
assert.notEqual(state.gameModeError, '');
assert.equal(state.gameModeProc.running, false);
state.syncGameMode(); // next poll retries
assert.equal(state.gameModeProc.running, true);
done(true, true);
assert.equal(state.gameModeError, '');
assert.equal(state.gameMode, true);
console.log('PASS: manual/auto policy, rapid toggles, acknowledged state, failure retry');
