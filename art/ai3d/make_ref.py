#!/usr/bin/env python3
"""Make an image-to-3D reference sheet from an existing illustration via gpt-image-1 edits.
Usage: make_ref.py ref.png out.png "prompt" [size]"""
import os, sys, base64, requests
key = next(l.split('=',1)[1].strip() for l in open(os.path.join(os.path.dirname(__file__), '..', '..', '.env.local')) if l.startswith('OPENAI_API_KEY='))
ref, out, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
size = sys.argv[4] if len(sys.argv) > 4 else '1024x1536'
r = requests.post('https://api.openai.com/v1/images/edits', headers={'Authorization': f'Bearer {key}'},
    files=[('image[]', (os.path.basename(ref), open(ref,'rb'), 'image/png'))],
    data={'model':'gpt-image-1','prompt':prompt,'size':size,'quality':'high','input_fidelity':'high'}, timeout=400)
if r.status_code != 200: print(r.text[:500]); sys.exit(1)
open(out,'wb').write(base64.b64decode(r.json()['data'][0]['b64_json'])); print(out)
