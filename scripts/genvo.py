#!/usr/bin/env python3
"""Street-football hype barks via ElevenLabs v3 (key read from ~/seedance-plotbreak/.env.local, never stored here).
Writes Panna/Resources/Audio/vo/<event>_<n>.mp3."""
import json, os, sys, urllib.request, concurrent.futures as cf
key = next(l.split('=', 1)[1].strip() for l in open(os.path.expanduser('~/seedance-plotbreak/.env.local')) if l.startswith('ELEVENLABS_API_KEY='))
OUT = os.path.join(os.path.dirname(__file__), '..', 'Panna', 'Resources', 'Audio', 'vo')
LIAM, JACK, CHUKU, CALLUM, HARRY, CHARLIE, LAURA, AIDAN = 'TX3LPaxmHKxFdv7VOQHJ', 'VMoEI0grEcRsMCQYvD6A', 'XALcFq0WF65uNKzmpcZW', 'N2lVS1w4EtoT3dr4eOWO', 'SOYHLrjzK2X1ezoPC6cr', 'IKne3meq5aSn9XLyUdCD', 'FGY2WhTYpPnrIDTdsKH5', 'EOVAuWqgSZN2Oel78Psj'
LINES = {
    'panna': [(JACK, '[shouting] PANNAAA!'), (CHUKU, '[excited] Through the legs!'), (LIAM, "[shouting] C'est filmé! C'est FILMÉ!"),
              (CALLUM, '[laughing] Wesh, il l’a humilié!'), (CHARLIE, '[shouting] ¡Caño! ¡Caño!')],
    'ankles': [(CHUKU, '[shouting] COOK HIM!'), (JACK, '[excited] Ankles GONE!'), (AIDAN, '[amazed] Sheeeesh!'),
               (LIAM, '[shouting] Olé!'), (CALLUM, '[laughing] Ça c’est sale, frère!')],
    'goal': [(HARRY, '[shouting] GOLAZOOO!'), (CHUKU, '[shouting] GET IN!'), (LIAM, '[shouting] Allez! ALLEZ!'),
             (JACK, '[excited] Oh my DAYS, what a finish!')],
    'perfect': [(HARRY, '[shouting] ROCKET!'), (CHARLIE, '[excited] Laser!'), (AIDAN, '[shouting] Top bins!')],
    'flow': [(HARRY, '[intense] Flow state.'), (LIAM, '[excited] Il est en feu!'), (CHUKU, "[intense] He's in the zone now.")],
    'tackle': [(CHUKU, '[shouting] DENIED!'), (JACK, '[confident] Not today!'), (CALLUM, '[laughing] Nah, nah, nah!')],
}
def gen(ev, i, voice, text):
    body = {'text': text, 'model_id': 'eleven_v3', 'voice_settings': {'stability': 0.3, 'similarity_boost': 0.8}}
    req = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128', data=json.dumps(body).encode(),
                                 headers={'xi-api-key': key, 'Content-Type': 'application/json'})
    try:
        data = urllib.request.urlopen(req, timeout=120).read()
    except urllib.error.HTTPError as e:
        return f'ERR {ev}_{i} {e.code} {e.read().decode()[:200]}'
    open(os.path.join(OUT, f'{ev}_{i}.mp3'), 'wb').write(data)
    return f'ok {ev}_{i} {len(data)}'
with cf.ThreadPoolExecutor(2) as ex:   # plan allows 3 concurrent; leave headroom
    jobs = [ex.submit(gen, ev, i, v, t) for ev, ls in LINES.items() for i, (v, t) in enumerate(ls)
            if not os.path.exists(os.path.join(OUT, f'{ev}_{i}.mp3'))]
    for j in jobs: print(j.result())
