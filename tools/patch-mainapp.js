'use strict';
// A scoped provisioning fallback, derived from idrive7-apps' patch design.
const fs = require('fs');
const crypto = require('crypto');
const STOCK = 'c96c81653952fd9b24e2718cead75b18c1a1d5be7b336f6f7053ce3c23490b33';
const ANCHOR = 'this.isMainapp&&section===this.mainappSection&&(newProvisioning.installable_apps=this.modifyInstallableApps(newProvisioning.installable_apps))';
function patch(source) {
    if (crypto.createHash('sha256').update(source).digest('hex') !== STOCK) throw Error('Unsupported/modified MainApp21; refusing to patch');
    if (source.split(ANCHOR).length !== 2) throw Error('Provisioning anchor must occur once');
    const helper = '/*ID8_BENCH_TEST_REPO*/const __id8RepoProvisioning=s=>{if(s!=="id8_bench_demo")return null;try{return require("fs").existsSync("/var/opt/public/oap/_id8_bench_demo/enabled")?{"-enabled":"true","-allowed":"true","-appStartType":"manually","-userLoginRequired":"false","-updateMechanism":"PLATFORM"}:null}catch(e){return null}};\n';
    const hook = 'if(this.isMainapp&&(!newProvisioning||Object.keys(newProvisioning).length===0)){const __id8p=__id8RepoProvisioning(section);if(__id8p)newProvisioning=__id8p}';
    return helper + source.replace(ANCHOR, hook + ANCHOR);
}
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length !== 2) throw Error('usage: node patch-mainapp.js stock.js output.js');
    fs.writeFileSync(args[1], patch(fs.readFileSync(args[0], 'utf8')));
}
module.exports = { patch, STOCK };
