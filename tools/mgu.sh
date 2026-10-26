#!/bin/sh
# Run on the head unit; only manages id8_bench_demo, never Warm-Up or BMW apps.
set -eu
KIT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OAP=/var/opt/public/oap
REG=$OAP/oap_12201/data/apps
UIDS=$OAP/oap_12201/security/uids.txt
MAIN=/usr/lib/oap-mainapp21/src/main.js
PLATFORM=$OAP/_id8_bench_demo
DROPIN=/etc/systemd/system/oapcontroller.service.d/60-id8-bench-demo.conf
export OAP_APPMGMT=/usr/lib/oap-mainapp21/src/AppManagement/AppManagement.js
cmd=${1:-check}; [ $# -eq 0 ] || shift
reuse=0; persist=0
for option in "$@"; do
    case "$option" in --reuse-existing-hook) reuse=1;; --persist) persist=1;; *) echo "Unknown option: $option" >&2; exit 2;; esac
done
die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die 'Root SSH is required'
for tool in node sha256sum setfacl tar mount; do command -v "$tool" >/dev/null || die "Missing $tool"; done
[ -f "$UIDS" ] && [ -d "$REG" ] || die 'ID8 OAP installation not found'
uid_of() { sed -n 's/^\([0-9]*\)=id8_bench_demo$/\1/p' "$UIDS"; }
mounted() { grep -q " $MAIN " /proc/mounts; }
hash_is() { [ "$(sha256sum "$1" | cut -d ' ' -f1)" = "$2" ]; }
rw=0
finish() { if [ "$rw" = 1 ]; then sync; mount -o remount,ro /; fi; }
trap finish EXIT
write_dropin() {
    if ! mkdir -p "$(dirname "$DROPIN")" 2>/dev/null || ! touch "$DROPIN" 2>/dev/null; then
        mount -o remount,rw /; rw=1
        mkdir -p "$(dirname "$DROPIN")"
    fi
    printf '[Service]\nExecStartPre=-+/bin/sh %s/apply.sh\n' "$PLATFORM" > "$DROPIN"
    systemctl daemon-reload
    finish; rw=0
}
backup() {
    mkdir -p "$KIT/backups"
    B=$(mktemp -d "$KIT/backups/state.XXXXXX")
    chmod 700 "$B"
    set -- var/opt/public/oap/oap_12201/security/uids.txt var/opt/public/oap/oap_12201/data/apps
    [ ! -d "$OAP/oap_$u" ] || set -- "$@" "var/opt/public/oap/oap_$u"
    tar czf "$B/before.tgz" -C / "$@"
    tar tzf "$B/before.tgz" >/dev/null
    [ ! -f "$DROPIN" ] || cp -p "$DROPIN" "$B/dropin.conf"
    [ ! -f "$KIT/state.json" ] || cp -p "$KIT/state.json" "$B/state.json"
    echo "Backup: $B"
}
check_identity() {
    node -e 'const fs=require("fs"),p=process.argv[1];if(JSON.parse(fs.readFileSync(p)).name!=="id8_bench_demo")throw Error("Refusing to overwrite another app")' "$OAP/oap_$u/source/package.json"
}
preflight() {
    hash_is "$OAP_APPMGMT" fb9a9b5326264bf68e39db577b6d123b5f7e657b1c8d3abf996511799c1e517a || die 'Unsupported or modified AppManagement'
    hash_is /usr/lib/oap-mainapp21/config/mainapp-base21.json 08211a37cec3d84e3f45a3181f5d6aaabd808126d819b23cac47d17fdade50a5 || die 'Restore the matching stock MainApp configuration first'
    mode=owned
    if mounted; then
        if grep -q ID8_BENCH_TEST_REPO "$MAIN"; then
            [ -f "$PLATFORM/stock-main.js" ] || die 'Owned hook has no original copy'
            hash_is "$PLATFORM/stock-main.js" c96c81653952fd9b24e2718cead75b18c1a1d5be7b336f6f7053ce3c23490b33 || die 'Original MainApp hash mismatch'
        elif [ "$reuse" = 1 ] && grep -q ID8_BENCH_FALLBACK "$MAIN" && grep -q '"id8_bench_demo"' "$MAIN"; then
            mode=reused
            [ "$persist" = 0 ] || die 'Existing shared hook persistence is managed separately'
        else
            die 'Another overlay is active. Current bench: explicitly use --reuse-existing-hook; otherwise restore stock first'
        fi
    else
        hash_is "$MAIN" c96c81653952fd9b24e2718cead75b18c1a1d5be7b336f6f7053ce3c23490b33 || die 'Unsupported/modified MainApp firmware'
        [ "$reuse" = 0 ] || die 'No active existing hook to reuse'
        [ ! -e "$PLATFORM" ] || die 'Inactive hook directory exists; inspect it before installation'
    fi
    node -e 'const fs=require("fs"),p=process.argv[1];const m=JSON.parse(fs.readFileSync(p+"/meta.json"));const a=JSON.parse(fs.readFileSync(p+"/source/package.json"));if(m.id!=="id8_bench_demo"||m.appletId!==20101||a.name!==m.id)throw Error("Unexpected kit app identity")' "$KIT/app"
    u=$(uid_of)
    case "$u" in *[!0-9]*) die 'Ambiguous UID registry';; esac
    if [ -n "$u" ]; then check_identity; else
        u=12450
        while [ "$u" -ge 12351 ]; do
            if ! grep -q "^$u=" "$UIDS" && [ ! -e "$OAP/oap_$u" ]; then break; fi
            u=$((u-1))
        done
        [ "$u" -ge 12351 ] || die 'No free app UID'
    fi
    node -e 'const fs=require("fs"),p=require("path"),root=process.argv[1];for(const d of fs.readdirSync(root)){if(!/^oap_\d+$/.test(d))continue;const f=p.join(root,d,"rhmiData/application.json");if(!fs.existsSync(f))continue;const a=JSON.parse(fs.readFileSync(f)).application;if(a.appletId===20101&&a.name!=="id8_bench_demo")throw Error("Applet 20101 is already used")}' "$OAP"
    work=$(mktemp -d "$KIT/verify.XXXXXX")
    node "$KIT/gen-interfaces.js" /etc/oap/someip/someip-interfaces.json "$KIT/app/source/manifest.json" "$u" "$work/interfaces"
    echo "Preflight passed: uid=$u hook=$mode"
}
case "$cmd" in
    check) preflight;;
    status)
        u=$(uid_of); [ -n "$u" ] || die 'App is not installed'
        check_identity
        echo "id8_bench_demo uid=$u"
        cat "$REG/id8_bench_demo.json"; echo
        [ ! -f "$KIT/state.json" ] || cat "$KIT/state.json"
        [ ! -f "$OAP/oap_$u/data/bench.log" ] || tail -15 "$OAP/oap_$u/data/bench.log" | grep -v 'argv='
        ;;
    install)
        preflight
        backup
        top=$OAP/oap_$u
        mkdir -p "$top/source" "$top/rhmiData" "$top/someipInterfaces" "$top/source/node_modules"
        cp -a "$KIT/app/source/." "$top/source/"
        cp -a "$KIT/app/rhmiData/." "$top/rhmiData/"
        cp -a "$work/interfaces/." "$top/someipInterfaces/"
        for name in certmgr codings ecu nare_logging necemapaths personalization smrf-native-cpp someip wscpp-client; do
            [ ! -e "/usr/lib/$name.node" ] || ln -sfn "/usr/lib/$name.node" "$top/source/node_modules/$name.node"
        done
        for name in data kvs share security; do
            mkdir -p "$top/$name"; chown "12201:$u" "$top/$name"; chmod 770 "$top/$name"
        done
        chown -h "12201:$u" "$top"
        chown -Rh "12201:$u" "$top/source" "$top/rhmiData" "$top/someipInterfaces"
        chmod 750 "$top" "$top/source" "$top/someipInterfaces"
        find "$top/source" -type d -exec chmod 750 {} \;
        find "$top/source" -type f -exec chmod 640 {} \;
        find "$top/someipInterfaces" -type f -exec chmod 640 {} \;
        find "$top/rhmiData" -type d -exec chmod 770 {} \;
        find "$top/rhmiData" -type f -exec chmod 660 {} \;
        setfacl -m g:hmi_resourceaccess:r-x,g:nav_oap:--x,g:sps_necema:r-x,g:dumm_oap:--x "$top"
        setfacl -R -m "g:hmi_resourceaccess:rX,g:12201:rwX,g:$u:rwX" "$top/rhmiData"
        find "$top/rhmiData" -type d -exec setfacl -d -m "g:hmi_resourceaccess:rX,g:12201:rwX,g:$u:rwX" {} \;
        node -e 'const fs=require("fs"),p=process.argv[1],u=Number(process.argv[2]),r=process.argv[3];let s=fs.readFileSync(p,"utf8");if(!s.split(/\r?\n/).includes(u+"=id8_bench_demo"))fs.writeFileSync(p,s.replace(/\s*$/,"")+"\n"+u+"=id8_bench_demo\n");fs.writeFileSync(r,JSON.stringify({userId:u,manifestPath:"manifest.json",installationSource:"PREINSTALLED",provisioningCache:{"-enabled":"true","-allowed":"true","-appStartType":"manually","-userLoginRequired":"false","-updateMechanism":"PLATFORM"}}))' "$UIDS" "$u" "$REG/id8_bench_demo.json"
        chown 12201:12201 "$REG/id8_bench_demo.json"; chmod 660 "$REG/id8_bench_demo.json"
        if [ "$mode" = owned ]; then
            if ! mounted; then
                [ ! -e "$PLATFORM" ] || die 'Inactive hook directory exists; inspect it before installation'
                mkdir "$PLATFORM"
                cp -p "$MAIN" "$PLATFORM/stock-main.js"
                node "$KIT/patch-mainapp.js" "$PLATFORM/stock-main.js" "$PLATFORM/main.js"
                node --check "$PLATFORM/main.js"
                cp "$KIT/apply-hook.sh" "$PLATFORM/apply.sh"
                touch "$PLATFORM/enabled"
                chown -R 0:0 "$PLATFORM"; chmod 755 "$PLATFORM" "$PLATFORM/main.js" "$PLATFORM/apply.sh"
                sh "$PLATFORM/apply.sh"
                mounted || die 'Provisioning bind mount failed'
            fi
            [ "$persist" = 0 ] || write_dropin
        fi
        node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({uid:Number(process.argv[2]),hookMode:process.argv[3],backup:process.argv[4]},null,2)+"\n")' "$KIT/state.json" "$u" "$mode" "$B"
        sh "$KIT/reload-mainapp.sh"
        echo 'Installed. Open ID8 Bench Test in Apps.'
        ;;
    uninstall)
        [ -f "$KIT/state.json" ] || die 'No installation state from this kit; refusing to guess hook ownership'
        u=$(uid_of); [ -n "$u" ] || die 'App is not installed'
        check_identity
        mode=$(node -e 'process.stdout.write(require(process.argv[1]).hookMode)' "$KIT/state.json")
        backup
        mv "$OAP/oap_$u" "$B/oap_$u"
        mv "$REG/id8_bench_demo.json" "$B/app-record.json"
        node -e 'const fs=require("fs"),p=process.argv[1],u=process.argv[2];fs.writeFileSync(p,fs.readFileSync(p,"utf8").split(/\r?\n/).filter(x=>x!==u+"=id8_bench_demo").join("\n"))' "$UIDS" "$u"
        if [ "$mode" = owned ]; then
            while mounted && cmp -s "$MAIN" "$PLATFORM/main.js"; do umount "$MAIN"; done
            [ ! -f "$PLATFORM/enabled" ] || mv "$PLATFORM/enabled" "$B/enabled"
            if [ -f "$DROPIN" ]; then
                mount -o remount,rw /; rw=1
                mv "$DROPIN" "$B/removed-dropin.conf"
                systemctl daemon-reload
                finish; rw=0
            fi
        fi
        sh "$KIT/reload-mainapp.sh"
        echo "App quarantined in $B; unrelated apps and reused hooks preserved."
        ;;
    *) die 'Usage: mgu.sh check|install|status|uninstall [--reuse-existing-hook] [--persist]';;
esac
