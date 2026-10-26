'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const LOG = path.join(ROOT, 'data', 'bench.log');
function log(message) {
    const line = new Date().toISOString() + ' ' + message;
    try { fs.appendFileSync(LOG, line + '\n'); } catch (_) {}
    console.log(line);
}
process.on('uncaughtException', (e) => { log('FATAL ' + (e.stack || e)); process.exit(1); });
process.on('unhandledRejection', (e) => log('REJECTION ' + (e.stack || e)));
// Do not log argv: the launcher includes the vehicle's VIN there.
log('PROCESS_START uid=' + process.getuid());
const { OnlineApp } = require('oap-sdk');
const app = new OnlineApp();
const description = JSON.parse(fs.readFileSync(path.join(ROOT, 'rhmiData', 'application.json')));
const entry = description.application.entryPoints[0].uuid;
let opening = null;
let openCount = 0;
let buttonCount = 0;

async function showScreen(uuid, source) {
    if (opening) return opening;
    opening = (async () => {
        const state = app.rhmiApplication.getByName('MAIN');
        await app.rhmiApplication.mapEntryState(uuid, state);
        await state.updateResources();
        await app.rhmiApplication.openEntryState(uuid);
        openCount++;
        log('OPEN_OK source=' + source + ' entry=' + uuid + ' count=' + openCount);
    })().catch((e) => log('OPEN_FAILED ' + (e.stack || e))).then(() => { opening = null; });
    return opening;
}
function bindLifecycle() {
    app.on('appStatusProxyReady', () => app.registerActive()
        .then(() => log('ACTIVE')).catch((e) => log('ACTIVE_FAILED ' + e)));
    app.on('shutdown', () => {
        log('SHUTDOWN');
        setTimeout(() => process.exit(0), 100);
    });
    app.on('entryPointExecute', (uuid, reason, name) => {
        log('ENTRY_EXECUTE uuid=' + uuid + ' reason=' + reason + ' name=' + name);
        if (app.rhmiApplication) showScreen(uuid, 'event');
    });
}

async function updateCounter(rhmi) {
    buttonCount++;
    log('BUTTON_ACTION count=' + buttonCount);
    try {
        await rhmi.getByName('MESSAGE').setValue(0, 'Text', 'Button received: ' + buttonCount, 'Text');
    } catch (error) {
        log('TEXT_FAILED ' + (error.stack || error));
    }
}

function bindScreen(rhmi, state) {
    state.on('visible', (event) => log('STATE_VISIBLE ' + JSON.stringify(event)));
    rhmi.on('applicationStackChanged', (stack) => {
        log('STACK ' + JSON.stringify(stack));
        const visible = stack && Object.keys(stack).length > 0 && ('ROOT_APP' in stack);
        const p = visible ? app.registerHmiVisible() : app.unregisterHmiVisible();
        Promise.resolve(p).catch((e) => log('VISIBILITY_FAILED ' + e));
    });
    rhmi.getByName('BTN_TEST').on('action', () => updateCounter(rhmi));
}

async function main() {
    bindLifecycle();
    await app.start();
    log('SDK_STARTED reason=' + app.startReason);
    const rhmi = app.rhmiApplication;
    if (!rhmi) throw Error('SDK returned without RHMI application');
    const state = rhmi.getByName('MAIN');
    await rhmi.mapEntryState(entry, state);
    log('MAP_OK entry=' + entry + ' state=' + state.getId());
    bindScreen(rhmi, state);
    await app.registerActive();
    await app.initialized();
    log('INITIALIZED');
    const initial = app.getLastExecutedEntryPointUuid();
    if (initial && ['ENTRY_POINT', 'BOOKMARK', 'LUM'].indexOf(String(app.startReason)) >= 0) {
        await showScreen(initial, 'cold-start');
    }
    // Deliberately no timer or diagnostic auto-open: success needs a real execute.
}
main().catch((e) => { log('START_FAILED ' + (e.stack || e)); process.exit(1); });
