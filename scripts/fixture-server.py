#!/usr/bin/env python3
"""Local-only, synthetic protocol fixtures. No third-party movie content."""
import argparse
import json
import subprocess
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent


class Handler(BaseHTTPRequestHandler):
    def send(self, data, content_type='application/json', status=200):
        if isinstance(data, dict):
            data = json.dumps(data, ensure_ascii=False).encode()
        elif isinstance(data, str):
            data = data.encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def encrypted(self, value):
        key = b'0123456789abcdef'.hex()
        raw = json.dumps(value, ensure_ascii=False).encode()
        encrypted = subprocess.run(['openssl', 'enc', '-aes-128-cbc', '-K', key, '-iv', key], input=raw, capture_output=True, check=True).stdout
        return self.send({'data': base64.b64encode(encrypted).decode()})

    def appget(self, parsed, fields):
        base = f'http://127.0.0.1:{self.server.server_port}'
        video = {'vod_id': 'ag1', 'vod_name': '原生测试影片', 'vod_pic': '', 'vod_content': 'AppGet synthetic fixture'}
        action = parsed.path.split('/')[-1]
        if action == 'initV119':
            return self.encrypted({'config': {'system_search_verify_status': 'captcha' in parsed.path}, 'type_list': [{'type_id': i, 'type_name': name, 'recommend_list': [video]} for i, name in enumerate(['电影','电视剧','综艺'], 1)]})
        if action == 'typeFilterVodList':
            if fields.get('class') != ['全部']: return self.send('bad form', status=400)
            return self.encrypted({'recommend_list': [video]})
        if action == 'searchList':
            if fields.get('keywords') != ['片名 + & 中文']: return self.send('bad keyword encoding', status=400)
            return self.encrypted({'search_list': [video]})
        if action == 'vodDetail':
            return self.encrypted({'vod': video, 'vod_play_list': [
                {'player_info': {'show': '直链', 'parse': '', 'player_parse_type': '0'}, 'urls': [{'name': '1', 'url': base + '/media.mp4'}]},
                {'player_info': {'show': 'JSON解析', 'parse': base + '/resolve?url=', 'player_parse_type': '2'}, 'urls': [{'name': '2', 'url': 'https://example.com/watch?a=1&b=中文'}]},
                {'player_info': {'show': 'AppGet解析', 'parse': 'native', 'player_parse_type': '2'}, 'urls': [{'name': '3', 'url': 'opaque-id', 'token': 'fixture-token'}]}
            ]})
        if action == 'vodParse':
            if fields.get('token') != ['fixture-token']: return self.send('bad token', status=400)
            key = b'0123456789abcdef'.hex()
            encrypted = base64.b64decode(fields['url'][0])
            decoded = subprocess.run(['openssl', 'enc', '-d', '-aes-128-cbc', '-K', key, '-iv', key], input=encrypted, capture_output=True, check=True).stdout
            if decoded != b'opaque-id': return self.send('bad encryption', status=400)
            return self.encrypted({'json': json.dumps({'url': base + '/media.mp4', 'header': {'Referer': base}})})
        return self.send('bad action', status=404)

    def do_POST(self):
        parsed = urlparse(self.path)
        fields = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode())
        if '/api.php/getappapi.index/' in parsed.path: return self.appget(parsed, fields)
        return self.send('not found', status=404)

    def do_GET(self):
        parsed = urlparse(self.path)
        q = parse_qs(parsed.query)
        base = f'http://127.0.0.1:{self.server.server_port}'
        if '/api.php/getappapi.index/' in parsed.path: return self.appget(parsed, q)
        if parsed.path == '/spider':
            if q.get('token') != ['test'] or q.get('extend') != ['fixture']:
                return self.send('missing module options', status=400)
            if any('private-not-sent' in v for values in q.values() for v in values):
                return self.send('unexpected source ext forwarding', status=400)
            if 'play' in q:
                if q.get('play') != ['/opaque?x=1&b=中文+'] or q.get('flag') != ['线路 · 1']:
                    return self.send('bad opaque id or flag', status=400)
                return self.send({'parse': 0, 'url': base + '/media.mp4', 'header': {'Referer': base}})
            if 'wd' in q and q['wd'] != ['片名 + & 中文']:
                return self.send('bad search encoding', status=400)
            if 'ids' in q and (q['ids'] != ['v1'] or q.get('ac') != ['detail']):
                return self.send('bad detail', status=400)
            if 't' in q and (q['t'] != ['cat'] or q.get('ac') != ['detail']):
                return self.send('bad category', status=400)
            return self.send({'class': [{'type_id': 'cat', 'type_name': '测试分类'}], 'page': int(q.get('pg', ['1'])[0]),
                              'list': [{'vod_id': 'v1', 'vod_name': '桥接协议测试', 'vod_play_from': '线路 · 1',
                                        'vod_play_url': '第一集$/opaque?x=1&b=中文+'}]})
        if parsed.path == '/resolve':
            if q.get('url') != ['https://example.com/watch?a=1&b=中文']: return self.send('bad nested URL', status=400)
            return self.send({'url': base + '/media.mp4'})
        if parsed.path == '/appget-host.txt': return self.send(base, 'text/plain')
        if parsed.path == '/config':
            return self.send({'sites': [
                {'key': 'fixture-json', 'name': '本地协议测试 · JSON', 'type': 1, 'api': base + '/json?token=test'},
                {'key': 'fixture-xml', 'name': '本地协议测试 · XML', 'type': 0, 'api': base + '/xml'},
                {'key': 'fixture-spider', 'name': '插件兼容性测试（不可播放）', 'type': 3, 'api': 'csp_TestOnly'}
            ]})
        if parsed.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/config')
            self.end_headers()
            return
        if parsed.path == '/oversize':
            return self.send(b'x' * 4096, 'text/plain')
        if parsed.path == '/html':
            return self.send('<html>not an API</html>', 'text/html')
        if parsed.path == '/media.mp4':
            path = ROOT / 'build' / 'fixtures' / 'media.mp4'
            if not path.exists():
                return self.send('Run create-test-media.swift first.', 'text/plain', 404)
            data = path.read_bytes()
            raw_range = self.headers.get('Range')
            if raw_range and raw_range.startswith('bytes='):
                start, end = raw_range[6:].split('-', 1)
                start = int(start or 0)
                end = min(int(end) if end else len(data) - 1, len(data) - 1)
                part = data[start:end + 1]
                self.send_response(206)
                self.send_header('Content-Type', 'video/mp4')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
                self.send_header('Content-Length', str(len(part)))
                self.end_headers()
                return self.wfile.write(part)
            return self.send(data, 'video/mp4')
        if parsed.path not in ['/json', '/xml']:
            return self.send('not found', 'text/plain', 404)
        expected_ac = 'detail' if parsed.path == '/json' else 'videolist'
        if q.get('ac') != [expected_ac]:
            return self.send('wrong action', 'text/plain', 400)
        if parsed.path == '/json' and q.get('token') != ['test']:
            return self.send('provider parameter lost', 'text/plain', 400)
        page = int(q.get('pg', ['1'])[0])
        names = ['本地协议测试片 · 第一部', '本地协议测试片 · 第二部', '本地协议测试片 · 第三部']
        videos = []
        for i, title in enumerate(names, 1):
            if 'ids' in q and str(i) != q['ids'][0]:
                continue
            if 'wd' in q and q['wd'][0] not in title:
                continue
            if 't' in q and q['t'][0] == '2' and i != 2:
                continue
            videos.append({'vod_id': str(i), 'vod_name': title, 'vod_pic': '', 'vod_remarks': '本地测试 / 非影视资源', 'vod_year': '2026', 'type_name': '协议测试',
                           'vod_content': '<p>这是一条人工编写的本地接口测试数据，不代表第三方片源可以播放。</p>',
                           'vod_play_from': '本地MP4', 'vod_play_url': f'测试片段一${base}/media.mp4#测试片段二${base}/media.mp4?part=2'})
        if parsed.path == '/json':
            return self.send({'page': page, 'pagecount': 2, 'class': [{'type_id': '1', 'type_name': '全部测试'}, {'type_id': '2', 'type_name': '分类测试'}], 'list': videos})
        contents = ''.join('<video>' + ''.join(f'<{target}>{escape(v[source])}</{target}>' for target, source in [('id', 'vod_id'), ('name', 'vod_name'), ('note', 'vod_remarks'), ('year', 'vod_year'), ('des', 'vod_content')]) + f'<dl><dd flag="mp4">{escape(v["vod_play_url"])}</dd></dl></video>' for v in videos)
        return self.send(f'<?xml version="1.0"?><rss><class><ty id="1">协议测试</ty></class><list page="{page}" pagecount="2">{contents}</list></rss>', 'application/xml')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18765)
    args = parser.parse_args()
    print(f'Local test configuration: http://127.0.0.1:{args.port}/config', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
