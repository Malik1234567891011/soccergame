#!/usr/bin/env python3
"""Generate game audio with ElevenLabs (key read from ~/seedance-plotbreak/.env.local, never stored here).
  genaudio.py sfx <name> "<prompt>" <seconds> [influence]
  genaudio.py music <name> "<prompt>" <ms>"""
import json, sys, os, urllib.request
key = next(l.split('=', 1)[1].strip() for l in open(os.path.expanduser('~/seedance-plotbreak/.env.local')) if l.startswith('ELEVENLABS_API_KEY='))
mode, name, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
out = os.path.join(os.path.dirname(__file__), '..', 'Panna', 'Resources', 'Audio', name + '.mp3')
if mode == 'sfx':
    body = {'text': prompt, 'duration_seconds': float(sys.argv[4]), 'prompt_influence': float(sys.argv[5]) if len(sys.argv) > 5 else 0.5}
    url = 'https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128'
else:
    body = {'prompt': prompt, 'music_length_ms': int(sys.argv[4])}
    url = 'https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128'
req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={'xi-api-key': key, 'Content-Type': 'application/json'})
try:
    data = urllib.request.urlopen(req, timeout=600).read()
except urllib.error.HTTPError as e:
    print('ERR', name, e.code, e.read().decode()[:300]); sys.exit(1)
open(out, 'wb').write(data)
print('ok', name, len(data))
