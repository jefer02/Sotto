"""Builds long.wav for the following metrics (test/domain/following_metrics_test.dart).

A Spanish presenter reading long_beats.txt (edge-tts, es-MX) with what real
talks have and natural.wav doesn't: two ad-libs that borrow the script's own
words, a long silence with room noise, a slow and a fast passage, and a
skipped stretch (beats 12-15). Every script word's start and end come from
the synthesizer's word boundaries, so the replay knows where the presenter
really was word by word (long_truth.json).

    pip install edge-tts   # 7.3+, and ffmpeg on PATH
    python test/fixtures/speech_es/generate_long.py test/fixtures/speech_es
"""
import asyncio, json, os, random, struct, subprocess, sys, wave

import edge_tts

OUT = sys.argv[1]
TMP = os.path.join(os.environ.get('TEMP', '/tmp'), 'sotto_es_long')
os.makedirs(TMP, exist_ok=True)
BEATS = [l for l in open(os.path.join(OUT, 'long_beats.txt'), encoding='utf-8').read().splitlines() if l.strip()]
VOICE = 'es-MX-JorgeNeural'
RATE = 16000

# (kind, payload, rate): 'beat' reads a script beat, 'adlib' says off-script
# words, 'silence' is a pause with room noise only.
SLOW, FAST, NORMAL = '-22%', '+6%', '-10%'
PLAN = (
    [('beat', b, NORMAL) for b in range(0, 6)]
    + [('adlib', 'Antes de seguir, les cuento que los proyectos nuevos nos tienen muy contentos, y al equipo de ventas también.', NORMAL)]
    + [('beat', b, SLOW) for b in range(6, 10)]
    + [('silence', 6.5, None)]
    + [('beat', b, NORMAL) for b in range(10, 12)]
    # The presenter skips beats 12-15 and goes on from beat 16.
    + [('beat', b, FAST) for b in range(16, 18)]
    + [('adlib', 'Esto de los cursos lo pedían mucho, ¿verdad? Sí, lo pedían mucho.', NORMAL)]
    + [('beat', b, FAST) for b in range(18, 20)]
    + [('beat', b, NORMAL) for b in range(20, 22)]
)


async def clip(text, rate, path):
    mp3 = path + '.mp3'
    words = []
    with open(mp3, 'wb') as f:
        async for chunk in edge_tts.Communicate(text, VOICE, rate=rate, boundary='WordBoundary').stream():
            if chunk['type'] == 'audio':
                f.write(chunk['data'])
            elif chunk['type'] == 'WordBoundary':
                # Offsets are in 100 ns units from the clip's start.
                words.append((chunk['offset'] / 1e7, (chunk['offset'] + chunk['duration']) / 1e7, chunk['text']))
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-ar', str(RATE), '-ac', '1',
                    '-c:a', 'pcm_s16le', path], check=True)
    w = wave.open(path)
    d = w.readframes(w.getnframes())
    w.close()
    return list(struct.unpack('<%dh' % (len(d) // 2), d)), words


async def main():
    random.seed(23)
    out, words, events = [], [], []
    for i, (kind, payload, rate) in enumerate(PLAN):
        start = len(out) / RATE
        if kind == 'silence':
            out += [0] * int(RATE * payload)
            events.append({'kind': 'silence', 'start': round(start, 3), 'end': round(len(out) / RATE, 3)})
            continue
        text = BEATS[payload] if kind == 'beat' else payload
        samples, bounds = await clip(text, rate, os.path.join(TMP, f'c{i}.wav'))
        if kind == 'beat':
            display = text.split()
            if len(bounds) != len(display):
                sys.exit(f'beat {payload}: {len(bounds)} boundaries for {len(display)} words')
            for k, (t0, t1, _) in enumerate(bounds):
                words.append({'beat': payload, 'word': k, 'start': round(start + t0, 3), 'end': round(start + t1, 3)})
        else:
            events.append({'kind': 'adlib', 'start': round(start, 3), 'end': round(start + len(samples) / RATE, 3)})
        out += samples
        out += [0] * int(RATE * random.uniform(0.6, 1.3))
    skipped = [b for b in range(len(BEATS)) if not any(w['beat'] == b for w in words)]
    events.append({'kind': 'skip', 'beats': skipped, 'start': next(w['start'] for w in words if w['beat'] == 16)})
    # Room noise around -50 dBFS.
    noisy = [max(-32768, min(32767, int(s * 0.8 + random.gauss(0, 100)))) for s in out]
    path = os.path.join(OUT, 'long.wav')
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(struct.pack('<%dh' % len(noisy), *noisy))
    w.close()
    with open(os.path.join(OUT, 'long_truth.json'), 'w', encoding='utf-8') as f:
        json.dump({'voice': VOICE, 'seconds': round(len(noisy) / RATE, 3), 'words': words, 'events': events}, f, indent=1)
    print(path, len(noisy) / RATE, 's,', len(words), 'script words')


asyncio.run(main())
