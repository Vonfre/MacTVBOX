#!/usr/bin/env python3
"""Build a single-release Sparkle feed. The caller signs the final XML bytes."""
import argparse
import base64
import datetime
import email.utils
import plistlib
import re
from pathlib import Path
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
REPOSITORY = 'https://github.com/Vonfre/MacTVBOX'
ET.register_namespace('sparkle', SPARKLE)


def make_appcast(plist_path, archive, signature, tag):
    with Path(plist_path).open('rb') as f:
        info = plistlib.load(f)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or tag != f'v{version}':
        raise ValueError('Release tag must match the app version (vMAJOR.MINOR.PATCH)')
    if not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('CFBundleVersion must be a positive, monotonically increasing integer')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid Ed25519 signature')
    archive = Path(archive)
    if archive.name != f'MacTVBOX-{version}-universal.zip' or archive.stat().st_size == 0:
        raise ValueError('Expected a non-empty versioned universal archive')
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'MacTVBOX Updates'
    ET.SubElement(channel, 'link').text = REPOSITORY
    ET.SubElement(channel, 'description').text = 'MacTVBOX signed stable releases'
    ET.SubElement(channel, 'language').text = 'zh-cn'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'MacTVBOX {version}'
    ET.SubElement(item, 'link').text = f'{REPOSITORY}/releases/tag/{tag}'
    ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = build
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'enclosure', {
        'url': f'{REPOSITORY}/releases/download/{tag}/{archive.name}',
        'length': str(archive.stat().st_size),
        'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    ET.indent(rss)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('plist', 'archive', 'signature', 'tag', 'output'):
        parser.add_argument(f'--{name}', required=True)
    args = parser.parse_args()
    Path(args.output).write_bytes(make_appcast(args.plist, args.archive, args.signature, args.tag))
