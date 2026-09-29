#!/usr/bin/env python3
"""Generate an image with OpenAI gpt-image-1. Usage: genimage.py out.png "prompt" [size] [quality] [background]"""
import json, os, sys, base64, urllib.request
key = None
for line in open(os.path.join(os.path.dirname(__file__), '..', '.env.local')):
    if line.startswith('OPENAI_API_KEY='): key = line.split('=', 1)[1].strip()
out, prompt = sys.argv[1], sys.argv[2]
size = sys.argv[3] if len(sys.argv) > 3 else '1024x1024'
quality = sys.argv[4] if len(sys.argv) > 4 else 'high'
bg = sys.argv[5] if len(sys.argv) > 5 else 'opaque'
body = {'model': 'gpt-image-1', 'prompt': prompt, 'size': size, 'quality': quality, 'n': 1, 'background': bg}
req = urllib.request.Request('https://api.openai.com/v1/images/generations', data=json.dumps(body).encode(),
                             headers={'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'})
try:
    res = json.load(urllib.request.urlopen(req, timeout=300))
except urllib.error.HTTPError as e:
    print(e.read().decode()); sys.exit(1)
open(out, 'wb').write(base64.b64decode(res['data'][0]['b64_json']))
print(out)
