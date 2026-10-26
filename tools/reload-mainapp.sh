#!/bin/sh
# Run on the MGU. Child-only OAP reload; never stops its supervisor.
set -eu
find_mainapp() {
    for p in $(pidof node); do
        x=$(tr '\000' ' ' < "/proc/$p/cmdline")
        case "$x" in *' /usr/lib/oap-mainapp21/src/main.js '*) echo "$p";; esac
    done
}
mp=$(find_mainapp)
case "$mp" in ''|*[!0-9]*) echo 'MainApp PID absent or ambiguous'; exit 1;; esac
controller=$(systemctl show oapcontroller.service -p MainPID | cut -d= -f2)
[ "$(awk '/^PPid:/{print $2}' "/proc/$mp/status")" = "$controller" ]
boot=$(cat /proc/sys/kernel/random/boot_id)
hmi=$(systemctl show hmi8.service -p MainPID | cut -d= -f2)
echo "Sending SIGTERM only to MainApp child $mp (controller $controller)"
kill -TERM "$mp"
i=0
while [ "$i" -lt 20 ]; do
    sleep 1
    next=$(find_mainapp)
    if [ -n "$next" ] && [ "$next" != "$mp" ]; then
        [ "$(cat /proc/sys/kernel/random/boot_id)" = "$boot" ]
        [ "$(systemctl show oapcontroller.service -p MainPID | cut -d= -f2)" = "$controller" ]
        [ "$(systemctl show hmi8.service -p MainPID | cut -d= -f2)" = "$hmi" ]
        echo "RELOAD_OK old=$mp new=$next controller=$controller hmi=$hmi boot=$boot"
        exit 0
    fi
    i=$((i+1))
done
echo 'No respawn within 20 seconds; inspect without restarting supervisor'
exit 1
