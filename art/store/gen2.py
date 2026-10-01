import os, sys, base64, requests
key = next(l.split('=',1)[1].strip() for l in open('/Users/malik/soccergame/.env.local') if l.startswith('OPENAI_API_KEY='))
out, prompt, refs = sys.argv[1], sys.argv[2], sys.argv[3:]
files = [('image[]', (os.path.basename(r), open(r, 'rb'), 'image/png')) for r in refs]
r = requests.post('https://api.openai.com/v1/images/edits', headers={'Authorization': f'Bearer {key}'}, files=files,
    data={'model': 'gpt-image-1', 'prompt': prompt, 'size': '1536x1024', 'quality': 'high', 'input_fidelity': 'high'}, timeout=500)
if r.status_code != 200: print(r.text[:400]); sys.exit(1)
open(out, 'wb').write(base64.b64decode(r.json()['data'][0]['b64_json'])); print('ok', out)
