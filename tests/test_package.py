import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_demo', ROOT / 'tools/build.py')
build_demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_demo)


class PackageTests(unittest.TestCase):
    def test_complete_payload_and_managed_entry_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            sdk = temp / 'sdk'
            sdk.mkdir()
            (sdk / 'index.js').write_text('module.exports = {};\n')
            (sdk / 'package.json').write_text('{"name":"oap-sdk","version":"0.0.0-test"}')
            result = build_demo.build(sdk, temp / 'output')
            with tarfile.open(result) as archive:
                names = set(archive.getnames())
                for filename in ('apply-hook.sh', 'mgu.sh', 'reload-mainapp.sh', 'gen-interfaces.js',
                                 'patch-mainapp.js', 'app/source/javascript/app.js',
                                 'app/source/node_modules/oap-sdk/index.js'):
                    self.assertIn(filename, names)
                app = json.load(archive.extractfile('app/rhmiData/application.json'))['application']
                self.assertEqual(app['appletId'], 20101)
                self.assertEqual(app['entryPoints'][0]['uuid'], '69df8445-44aa-533c-9c59-e5e7288dd5c4')
                package = json.load(archive.extractfile('app/source/package.json'))
                self.assertEqual(package['name'], 'id8_bench_demo')
                self.assertEqual(package['main'], 'javascript/app.js')
                config = json.load(archive.extractfile('app/source/config/base.json'))
                self.assertFalse(config['joynrLoadingEnabled'])
                self.assertFalse(any(name.endswith(('.key', '.pem', '.p12')) for name in names))

    def test_xml_and_data_model_component_ids_match(self):
        xml = ET.parse(ROOT / 'app/application.xml')
        model = json.loads((ROOT / 'app/uiDescription.json').read_text())
        for container in xml.findall('container'):
            components = {item.get('id') for item in container.findall('.//component')}
            self.assertEqual(components, set(model['containers'][container.get('id')]['components']))

    def test_patch_refuses_unknown_firmware(self):
        command = 'try{require(process.argv[1]).patch("unknown firmware");process.exit(1)}catch(e){if(!/Unsupported/.test(e.message))throw e}'
        subprocess.run(['node', '-e', command, str(ROOT / 'tools/patch-mainapp.js')], check=True)

    @unittest.skipUnless(os.environ.get('ID8_FIRMWARE_ROOT'), 'optional local firmware check')
    def test_patch_accepts_only_the_verified_stock_input(self):
        source = Path(os.environ['ID8_FIRMWARE_ROOT']) / 'usr/lib/oap-mainapp21/src/main.js'
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'patched.js'
            subprocess.run(['node', str(ROOT / 'tools/patch-mainapp.js'), str(source), str(output)], check=True)
            subprocess.run(['node', '--check', str(output)], check=True)
            self.assertIn('ID8_BENCH_TEST_REPO', output.read_text())
            self.assertIn('s!=="id8_bench_demo"', output.read_text())


if __name__ == '__main__':
    unittest.main()
