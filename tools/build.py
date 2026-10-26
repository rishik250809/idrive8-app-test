#!/usr/bin/env python3
"""Build the demo and a deployable kit. Python standard library only."""
import argparse
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
NS = uuid.UUID('6b1d3a52-8f0e-4c4b-9a77-0d0c4d4e5f10')
LANGUAGES = 'ar_AE cs_CZ da_DK de_DE el_GR en_GB en_US es_ES fi_FI fr_FR he_IL hu_HU id_ID it_IT ja_JP ko_KR nb_NO nl_NL no_NO pl_PL pt_PT pt_BR ro_RO ru_RU sk_SK sl_SI sv_SE th_TH tr_TR uk_UA vi_VN zh_CN zh_TW'.split()


def build(sdk, output=None):
    sdk = Path(sdk).resolve()
    for filename in ('index.js', 'package.json'):
        if not (sdk / filename).is_file():
            raise SystemExit('SDK missing: ' + str(sdk / filename) + '; extract it from your own unit first')
    spec = json.loads((ROOT / 'app/app.json').read_text())
    make_uuid = lambda kind: str(uuid.uuid5(NS, spec['id'] + ':' + kind))
    dist = Path(output) if output else ROOT / 'dist'
    dist.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='id8-build-', dir=dist) as temporary:
        kit = Path(temporary)
        app = kit / 'app'
        src = app / 'source'
        (src / 'javascript').mkdir(parents=True)
        (src / 'config').mkdir()
        (src / 'node_modules/oap-sdk').mkdir(parents=True)
        shutil.copy2(ROOT / 'src/main.js', src / 'javascript/app.js')
        shutil.copy2(ROOT / 'app/manifest.json', src / 'manifest.json')
        for filename in ('index.js', 'package.json'):
            shutil.copy2(sdk / filename, src / 'node_modules/oap-sdk' / filename)
        dump = lambda filename, data: filename.write_text(json.dumps(data, indent=2) + '\n')
        dump(src / 'package.json', {
            'name': spec['id'], 'version': spec['version'], 'main': 'javascript/app.js',
            'private': True, 'engines': {'node': '>=8.7.0'},
            'oapAppSettings': {'loggingId': spec['loggingId'], 'someipManifest': 'manifest.json',
                'maxDiskUsage': 20971520, 'cpuLimit': 60, 'memoryThresholdKB': 196608,
                'priority': 'PRIO_LOW', 'visibility': 'FOREGROUND', 'latencyClass': 'FOREGROUND',
                'userLoginRequired': False, 'backgroundPriority': 200}})
        dump(src / 'config/base.json', {'joynrLoadingEnabled': False})
        dump(src / 'permissions.json', {'permissions': []})
        dump(src / 'npm-shrinkwrap.json', {'name': spec['id'], 'version': spec['version'], 'lockfileVersion': 1})
        rhmi = app / 'rhmiData'
        for folder in ('uiDescription', 'strings', 'resources'):
            (rhmi / folder).mkdir(parents=True)
        shutil.copy2(ROOT / 'app/application.xml', rhmi / 'uiDescription/application.xml')
        shutil.copy2(ROOT / 'app/uiDescription.json', rhmi / 'uiDescription/uiDescription.json')
        for lang in LANGUAGES:
            shutil.copy2(ROOT / 'app/strings.json', rhmi / 'strings' / (lang + '.json'))
        shutil.copy2(ROOT / 'app/icon.png', rhmi / 'resources/id8_bench_demo_icon.png')
        description = {'schemaVersion': '1.3.0', 'application': {
            'uuid': make_uuid('app'), 'type': 'OnlineApp', 'name': spec['id'],
            'vendor': 'Bench research', 'version': spec['version'], 'defaultLanguage': 'en_GB',
            'appletId': spec['appletId'], 'stringBundleUuid': make_uuid('strings'),
            'resourceBundleUuid': make_uuid('resources'),
            'entryPointsStringBundleUuid': make_uuid('ep-strings'),
            'entryPointsResourceBundleUuid': make_uuid('ep-resources'),
            'externalDialogStringBundleUuid': make_uuid('ed-strings'),
            'bookmarkUuidPool': [make_uuid('bookmarks'), 1, 2, 3, 4, 5, 6, 7],
            'entryPoints': [{'name': 'ID8_BENCH_DEMO_ENTRY', 'uuid': make_uuid('entry'),
                'textId': 'SID_ID8_BENCH_DEMO_TITLE', 'icon': 'id8_bench_demo_icon.png',
                'uri': 'state:/base/startmenu/menudrawer', 'insertionMode': 'INSERT_BELOW',
                'insertionOrder': 0, 'insertionPriority': 0, 'insertionGroup': 0,
                'isGroupHeader': False, 'private': False, 'appearance': 'DEFAULT',
                'previewType': 'NONE', 'bookmarkable': True}]}}
        dump(rhmi / 'application.json', description)
        # Preserve both packaged and installed RHMI representations, as in the tested kit.
        packaged = src / 'rhmiData'
        (packaged / 'uiDescriptions/ID8').mkdir(parents=True)
        (packaged / 'variantGroups/Common/texts').mkdir(parents=True)
        (packaged / 'variantGroups/Common/images').mkdir()
        for filename in ('application.xml', 'uiDescription.json'):
            shutil.copy2(rhmi / 'uiDescription' / filename, packaged / 'uiDescriptions/ID8' / filename)
        shutil.copy2(ROOT / 'app/strings.json', packaged / 'variantGroups/Common/texts/en_GB.json')
        shutil.copy2(ROOT / 'app/icon.png', packaged / 'variantGroups/Common/images/id8_bench_demo_icon.png')
        raw = json.loads(json.dumps(description))
        for key in ('entryPointsStringBundleUuid', 'entryPointsResourceBundleUuid', 'externalDialogStringBundleUuid', 'bookmarkUuidPool'):
            raw['application'].pop(key)
        raw['application']['uiDescriptions'] = [{'applicationFilePath': './uiDescriptions/ID8/application.xml',
            'uiDescriptionFilePath': './uiDescriptions/ID8/uiDescription.json', 'hmi': ['ID8']}]
        raw['application']['variantGroups'] = [{'stringsPath': './variantGroups/Common/texts',
            'resourcesPath': './variantGroups/Common/images', 'hmi': ['ID8'], 'brands': ['BMW']}]
        dump(packaged / 'application.json', raw)
        dump(app / 'meta.json', spec)
        for filename in ('mgu.sh', 'gen-interfaces.js', 'patch-mainapp.js', 'reload-mainapp.sh', 'apply-hook.sh'):
            shutil.copy2(ROOT / 'tools' / filename, kit / filename)
        output = dist / 'id8-bench-test.tar.gz'
        with tarfile.open(output, 'w:gz') as archive:
            for filename in sorted(kit.iterdir()):
                archive.add(filename, arcname=filename.name)
    print(output)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', default=str(ROOT / '.local/oap-sdk'))
    build(parser.parse_args().sdk)
