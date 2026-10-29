'use strict';
/**
 * Generate ID8 interfaces and ACL using the unit's own firmware generators.
 *
 *   node gen-interfaces.js <someip-interfaces.json> <manifest.json> <userId> <outDir>
 *
 * On the head unit the catalog is /etc/oap/someip/someip-interfaces.json.
 * Node 8 compatible (runs on the unit at install time).
 */
const fs = require('fs');
const path = require('path');

// BMW's generators live inside MainApp's AppManagement bundle on the unit.
// No local BMW generator modules need to be distributed with this kit.
const APPMGMT = process.env.OAP_APPMGMT || '/usr/lib/oap-mainapp21/src/AppManagement/AppManagement.js';
let bundleReq = null, bundleText = null;
function fromFirmware(name) {
    if (!bundleText) bundleText = fs.readFileSync(APPMGMT, 'utf8');
    const m = new RegExp('"someip-interfaces-generator/' + name + '(?:\\.js)?":(\\d+)').exec(bundleText);
    if (!m) throw new Error(name + ' not found in ' + APPMGMT);
    if (!bundleReq) {
        const tail = /,\{\},\[\d+\]\)\s*;?\s*$/;
        if (!tail.test(bundleText)) throw new Error('unexpected AppManagement bundle format');
        // same bundle, but with no entry module, so only what we ask for runs
        bundleReq = new Function('require', 'return ' + bundleText.replace(tail, ',{},[])'))(require);
    }
    return bundleReq(m[1]);
}

function main(argv) {
    if (argv.length !== 4 || !/^\d+$/.test(argv[2])) {
        console.error('usage: node gen-interfaces.js <someip-interfaces.json> <manifest.json> <numeric UID> <outDir>');
        process.exit(2);
    }
    const [dbPath, manifestPath, userId, outDir] = argv;
    const db = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8').replace(/\${userId}/g, String(userId)));
    const ifs = fromFirmware('IFConfigGenerator').generate(db, manifest);
    const acl = fromFirmware('AclGenerator').generate(db, manifest);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);
    let n = 0;
    Object.keys(ifs).forEach((id) => {
        fs.writeFileSync(path.join(outDir, id.replace(/\./g, '_') + '.json'), JSON.stringify(ifs[id]));
        n++;
    });
    fs.writeFileSync(path.join(outDir, 'acl.json'), JSON.stringify(acl));
    console.log('generated ' + n + ' interface configs + acl.json (' + acl.offers.length + ' offers, ' + acl.requests.length + ' requests)');
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { main };
