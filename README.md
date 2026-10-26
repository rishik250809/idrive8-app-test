# IDrive8 App Test

https://github.com/user-attachments/assets/82c34307-01f1-49a4-ae82-f33c334d0bfb

Contributions welcome!

Just a minimal BMW MGU iDrive 8 app: open its tile and press the iDrive button to
increment a counter on a native RHMI screen.

I just built it as a test for my next projects on my testing idrive8/MGU21 unit. Feel free to use it too, just credit me if you feel generous!

**YOU NEED ROOT SSH ACCESS bypassed!**

Requires Python 3 and Node.js 16+ on your computer.
Bench-tested on MGU21 with BMW SDK 50.23.1; the installer checks firmware hashes.

I am not going to publish BMW's SDK because of compatibility and legal reasons. Extract it yourself with the given scripts.

## Build

Extract the SDK from your own unit; as i said it is not included. Replace `<your-mgu-ip>` below:

```sh
mkdir -p .local/firmware
export MGU_HOST='root@<your-mgu-ip>'
scp "$MGU_HOST":/var/opt/public/oap/oap_12204/source/bundle.js .local/firmware/
scp "$MGU_HOST":/var/opt/public/oap/oap_12204/source/package.json .local/firmware/
node tools/extract-sdk.js .local/firmware/bundle.js .local/oap-sdk
python3 tools/build.py
```

The bundle is saved to `dist/id8-bench-test.tar.gz`. Keep it private: it contains
BMW's SDK. `.local/` and `dist/` are ignored by Git.

## Push to the MGU

```sh
sh deploy.sh check
sh deploy.sh install
sh deploy.sh status
```

After that, the app should pop up in your Apps menu.

The provisioning hook lasts until reboot. Use `install --persist` to keep it
across reboots. On the existing bench with the shared Warm-Up hook, add
`--reuse-existing-hook` to both `check` and `install` instead.

Installation backs up the app/registry and adds a provisioning bind mount;
stock signing certificates stay unchanged. Only the MainApp child is reloaded,
without rebooting. Installation and button input were verified on the bench.

## Remove the app

```sh
sh deploy.sh uninstall
```

Keep `/var/opt/id8-bench-demo-kit` on the MGU for removal and backups.
