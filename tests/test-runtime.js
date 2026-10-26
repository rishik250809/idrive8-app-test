'use strict';
// Exercise the app against an SDK double without native modules or an MGU.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const EventEmitter = require('events');
const source = fs.readFileSync(path.join(__dirname, '../src/main.js'), 'utf8');
const flush = () => new Promise((resolve) => setImmediate(resolve));

async function scenario(reason) {
    let app, opens = 0, updates = 0;
    const texts = [], logs = [];
    const state = new EventEmitter();
    state.getId = () => 1;
    state.updateResources = async () => { updates++; };
    const button = new EventEmitter();
    const message = { setValue: async (row, field, text) => texts.push(text) };
    class OnlineApp extends EventEmitter {
        constructor() {
            super();
            app = this;
            this.startReason = reason;
            this.rhmiApplication = new EventEmitter();
            this.rhmiApplication.getByName = (name) => ({ MAIN: state, BTN_TEST: button, MESSAGE: message })[name];
            this.rhmiApplication.mapEntryState = async () => {};
            this.rhmiApplication.openEntryState = async () => { opens++; };
        }
        async start() {}
        async registerActive() {}
        async initialized() {}
        async registerHmiVisible() {}
        async unregisterHmiVisible() {}
        getLastExecutedEntryPointUuid() { return 'test-entry'; }
    }
    const mockFs = {
        readFileSync: () => JSON.stringify({ application: { entryPoints: [{ uuid: 'test-entry' }] } }),
        appendFileSync: (file, line) => logs.push(line)
    };
    const modules = { fs: mockFs, path, 'oap-sdk': { OnlineApp } };
    vm.runInNewContext(source, {
        require: (name) => { assert(name in modules); return modules[name]; },
        __dirname, console: { log: () => {} }, setTimeout,
        process: { on: () => {}, getuid: () => 12450, exit: (code) => { throw Error('Unexpected exit ' + code); } }
    });
    await flush();
    const cold = reason === 'ENTRY_POINT' ? 1 : 0;
    assert.strictEqual(opens, cold, 'Only a real entry-point start should open a screen');
    app.emit('entryPointExecute', 'test-entry', 'USER', 'bench');
    await flush();
    assert.strictEqual(opens, cold + 1, 'Warm reopening should work');
    assert.strictEqual(updates, opens, 'Resources must be ready before opening');
    button.emit('action');
    button.emit('action');
    await flush();
    assert.deepStrictEqual(texts, ['Button received: 1', 'Button received: 2']);
    assert(!logs.some((line) => /FAILED|FATAL|REJECTION/.test(line)), logs.join(''));
}

(async () => {
    await scenario('ENTRY_POINT');
    await scenario('AUTOSTART');
    console.log('PASS: cold launch, warm reopening, no forced autostart screen, button counter');
})().catch((error) => { console.error(error); process.exitCode = 1; });
