#!/usr/bin/env python3
"""Compile unmodified XCTest-style test bodies using small local assertions.
Used only when XCTest itself is unavailable. Never changes global toolchains.
"""
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
output = root / 'build' / 'clt-tests'
output.mkdir(parents=True, exist_ok=True)
sdk = os.environ.get('MACTVBOX_SDK') or subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
sdk = Path(sdk).resolve()
if not os.environ.get('MACTVBOX_SDK') and 'MacOSX27' in sdk.name and (sdk.parent / 'MacOSX26.5.sdk').exists():
    sdk = sdk.parent / 'MacOSX26.5.sdk'
filter_value = ''
if '--filter' in sys.argv:
    filter_value = sys.argv[sys.argv.index('--filter') + 1]
files = list((root / 'Sources' / 'MacTVBOXCore').glob('*.swift'))
files.append(root / 'scripts' / 'testing' / 'Assertions.swift')
cases = []
for path in sorted((root / 'Tests' / 'MacTVBOXCoreTests').glob('*.swift')):
    text = path.read_text().replace('import XCTest', 'import Foundation').replace('@testable import MacTVBOXCore', '')
    # Keep source paths / line numbers in assertion failures.
    generated = output / path.name
    generated.write_text(text)
    files.append(generated)
    cls = re.search(r'final class (\w+): XCTestCase', text).group(1)
    for match in re.finditer(r'func (test\w+)\(\)([^\{]*)\{', text):
        method, modifiers = match.groups()
        name = f'{cls}/{method}'
        if filter_value and filter_value not in name:
            continue
        prefix = ('try ' if 'throws' in modifiers else '') + ('await ' if 'async' in modifiers else '')
        cases.append(f'await run("{name}") {{ {prefix}{cls}().{method}() }}')
if not cases:
    sys.exit('No matching tests')
runner = output / 'CLTRunner.swift'
runner.write_text('''import Foundation
@main struct CLTRunner {
    static var passed = 0, skipped = 0, failed = 0
    static func run(_ name: String, _ body: () async throws -> Void) async {
        let before = assertionFailures
        do {
            try await body()
            if assertionFailures == before { passed += 1; print("PASS \\(name)") }
            else { failed += 1; print("FAIL \\(name)") }
        } catch let skip as XCTSkip { skipped += 1; print("SKIP \\(name): \\(skip.reason)") }
        catch { failed += 1; print("FAIL \\(name): \\(error)") }
    }
    static func main() async {
''' + '\n'.join(cases) + '''
        print("\\(passed) passed, \\(failed) failed, \\(skipped) skipped (CLT assertion runner)")
        exit(failed == 0 ? 0 : 1)
    }
}
''')
files.append(runner)
print('XCTest unavailable: running the same test bodies with the local CLT assertion runner.', flush=True)
subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-sdk', str(sdk), *map(str, files), '-o', str(output / 'tests')], check=True)
sys.exit(subprocess.run([str(output / 'tests')]).returncode)
