#!/usr/bin/env python3
"""Real Sparkle update/install tests using throwaway apps, keys and localhost.
Never reads or writes the user's MacTVBOX library, preferences or installed app.
Run with a logged-in macOS GUI session (Sparkle uses XPC / LaunchServices).
"""
import base64
import functools
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/update-tests'
OUT.mkdir(parents=True, exist_ok=True)
TOOLS = Path(subprocess.check_output([str(ROOT / 'scripts/fetch-sparkle-tools.sh')], text=True).strip())
FRAMEWORK = next((ROOT / '.build/artifacts').glob('**/macos-*/Sparkle.framework'))
SDK = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()).resolve()
if 'MacOSX27' in SDK.name and (SDK.parent / 'MacOSX26.5.sdk').exists():
    SDK = SDK.parent / 'MacOSX26.5.sdk'
subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-sdk', str(SDK),
                '-F', str(FRAMEWORK.parent), '-framework', 'Sparkle',
                '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                str(ROOT / 'Sources/MacTVBOX/UpdateController.swift'),
                str(ROOT / 'scripts/testing/UpdateHarness.swift'), '-o', str(OUT / 'UpdateHarness')], check=True)

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run_case(case, installed=1, offered=2, corrupt=None):
    # Keep all test apps outside /Applications, using a fresh bundle ID each time.
    with tempfile.TemporaryDirectory(prefix=f'mactvbox-{case}-') as temporary:
        work = Path(temporary)
        web = work / 'web'
        web.mkdir()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(web)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f'http://127.0.0.1:{server.server_port}'
        bundle_id = f'app.mactvbox.update-test-{uuid.uuid4().hex}'
        key_path = work / 'key'
        keygen = work / 'keygen.swift'
        keygen.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
''')
        public = subprocess.check_output(['swift', '-sdk', str(SDK), str(keygen), str(key_path)], text=True).strip()
        key_path.chmod(0o600)

        def bundle(parent, build):
            app = parent / 'UpdateHarness.app'
            contents = app / 'Contents'
            (contents / 'MacOS').mkdir(parents=True)
            (contents / 'Frameworks').mkdir()
            shutil.copy2(OUT / 'UpdateHarness', contents / 'MacOS/UpdateHarness')
            subprocess.run(['ditto', str(FRAMEWORK), str(contents / 'Frameworks/Sparkle.framework')], check=True)
            info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
            info.update(CFBundleIdentifier=bundle_id, CFBundleName='UpdateHarness',
                        CFBundleExecutable='UpdateHarness', CFBundleShortVersionString=f'1.0.{build}',
                        CFBundleVersion=str(build), SUFeedURL=f'{base}/appcast.xml', SUPublicEDKey=public,
                        LSUIElement=True)
            (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            return app

        old = bundle(work / 'installed', installed)
        new = bundle(work / 'offered', offered)
        archive = web / 'UpdateHarness.zip'
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(new), str(archive)], check=True)
        signature = subprocess.check_output([str(TOOLS / 'sign_update'), '--ed-key-file', str(key_path), '-p', str(archive)], text=True).strip()
        feed = web / 'appcast.xml'
        feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Isolated update test</title><item><title>Version {offered}</title>
<sparkle:version>{offered}</sparkle:version><sparkle:shortVersionString>1.0.{offered}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="{base}/UpdateHarness.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}" />
</item></channel></rss>''')
        subprocess.run([str(TOOLS / 'sign_update'), '--ed-key-file', str(key_path), str(feed)], check=True, capture_output=True)
        if corrupt == 'archive':
            data = bytearray(archive.read_bytes())
            data[100] ^= 1  # Keep the byte count unchanged, invalidate the signature.
            archive.write_bytes(data)
        elif corrupt == 'feed':
            feed.write_bytes(feed.read_bytes().replace(b'Isolated update test', b'TAMPERED update test'))
        log_path = OUT / f'{case}.log'
        try:
            with log_path.open('w') as log:
                process = subprocess.Popen([str(old / 'Contents/MacOS/UpdateHarness')], stdout=log, stderr=subprocess.STDOUT)
                try:
                    process.wait(timeout=55)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    raise AssertionError(f'{case}: timed out; see {log_path}')
            log = log_path.read_text()
            if 'UPDATE_TIMEOUT' in log:
                raise AssertionError(f'{case}: updater stalled; see {log_path}\n{log}')
            target_build = offered if offered > installed and corrupt is None else installed
            for _ in range(100):
                try:
                    actual = int(plistlib.loads((old / 'Contents/Info.plist').read_bytes())['CFBundleVersion'])
                    if actual == target_build:
                        break
                except FileNotFoundError:
                    pass  # Sparkle atomically swaps directories during installation.
                time.sleep(0.2)
            assert actual == target_build, f'{case}: expected build {target_build}, got {actual}\n{log}'
            if corrupt:
                assert '更新检查未完成' in log, f'{case}: expected authentication failure\n{log}'
                assert '将在退出时自动安装' not in log
            elif offered > installed:
                assert '将在退出时自动安装' in log, f'{case}: no automatic installation\n{log}'
                subprocess.run(['codesign', '--verify', '--deep', '--strict', str(old)], check=True)
            else:
                assert '当前已是最新版本' in log, f'{case}: expected no downgrade\n{log}'
            print(f'PASS {case}: bundle build {actual}', flush=True)
        finally:
            server.shutdown()
            server.server_close()
            # Remove only this run's randomly named Sparkle preferences/cache.
            subprocess.run(['defaults', 'delete', bundle_id], capture_output=True)
            for location in ('Caches', 'Application Support'):
                path = Path.home() / 'Library' / location / bundle_id
                if path.is_dir():
                    shutil.rmtree(path)


run_case('automatic-install-on-quit')
run_case('reject-tampered-archive', corrupt='archive')
run_case('reject-tampered-feed', corrupt='feed')
run_case('reject-downgrade', installed=2, offered=1)
print('4 updater integration tests passed')
