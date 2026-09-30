import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('appcast', ROOT / 'scripts/make-appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.plist = self.directory / 'Info.plist'
        self.info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        self.version = self.info['CFBundleShortVersionString']
        self.tag = f'v{self.version}'
        self.plist.write_bytes(plistlib.dumps(self.info))
        self.archive = self.directory / f'MacTVBOX-{self.version}-universal.zip'
        self.archive.write_bytes(b'synthetic test archive')
        self.signature = base64.b64encode(b'x' * 64).decode()

    def feed(self):
        return appcast.make_appcast(self.plist, self.archive, self.signature, self.tag)

    def test_feed_matches_bundle_and_immutable_release_asset(self):
        root = ET.fromstring(self.feed())
        item = root.find('channel/item')
        self.assertEqual(item.find(f'{{{appcast.SPARKLE}}}version').text, self.info['CFBundleVersion'])
        self.assertEqual(item.find(f'{{{appcast.SPARKLE}}}shortVersionString').text, self.version)
        self.assertEqual(item.find('enclosure').get('length'), str(self.archive.stat().st_size))
        self.assertEqual(item.find('enclosure').get('url'),
                         f'https://github.com/Vonfre/MacTVBOX/releases/download/{self.tag}/{self.archive.name}')
        self.assertEqual(item.find('enclosure').get(f'{{{appcast.SPARKLE}}}edSignature'), self.signature)

    def test_rejects_mismatched_tag(self):
        self.tag = 'v999.0.0'
        with self.assertRaises(ValueError):
            self.feed()

    def test_rejects_invalid_signature(self):
        for signature in ('bad', base64.b64encode(b'x' * 32).decode()):
            self.signature = signature
            with self.assertRaises(ValueError):
                self.feed()

    def test_rejects_empty_archive(self):
        self.archive.write_bytes(b'')
        with self.assertRaises(ValueError):
            self.feed()

    def test_rejects_wrong_asset_name(self):
        self.archive = self.directory / 'OtherApp.zip'
        self.archive.write_bytes(b'zip')
        with self.assertRaises(ValueError):
            self.feed()

    def test_rejects_non_numeric_build(self):
        self.info['CFBundleVersion'] = 'development'
        self.plist.write_bytes(plistlib.dumps(self.info))
        with self.assertRaises(ValueError):
            self.feed()

    def test_sidebar_version_comes_from_bundle_metadata(self):
        source = (ROOT / 'Sources/MacTVBOX/MacTVBOXApp.swift').read_text()
        self.assertIn(
            'Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")',
            source,
        )
        # Never allow a release number to be hard-coded into a SwiftUI Text label.
        for swift_file in (ROOT / 'Sources/MacTVBOX').glob('*.swift'):
            self.assertNotRegex(swift_file.read_text(), r'Text\(\s*"v?\d+\.\d+\.\d+"', str(swift_file))

    def test_production_update_security_defaults(self):
        for key in ('SUEnableAutomaticChecks', 'SUAutomaticallyUpdate',
                    'SUVerifyUpdateBeforeExtraction', 'SURequireSignedFeed'):
            self.assertIs(self.info[key], True)
        self.assertEqual(self.info['SUSignedFeedFailureExpirationInterval'], 0)
        self.assertIs(self.info['SUEnableSystemProfiling'], False)
        self.assertEqual(self.info['SUScheduledCheckInterval'], 3600)
        self.assertEqual(len(base64.b64decode(self.info['SUPublicEDKey'], validate=True)), 32)
        self.assertEqual(self.info['SUFeedURL'],
                         'https://github.com/Vonfre/MacTVBOX/releases/latest/download/appcast.xml')


if __name__ == '__main__':
    unittest.main()
