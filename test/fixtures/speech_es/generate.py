"""Builds natural.wav for test/integration/sherpa_following_es_test.dart.

A Spanish presenter reading beats.txt: one clip per beat (edge-tts, es-MX),
pauses between beats, an ad-lib after beat 7, light room noise.
natural_marks.txt lists when each beat starts (-1 = the ad-lib).

    pip install edge-tts   # and ffmpeg on PATH
    python test/fixtures/speech_es/generate.py test/fixtures/speech_es
"""
import asyncio, subprocess, sys, os, wave, struct, random
import edge_tts

OUT = sys.argv[1]
TMP = os.path.join(os.environ['TEMP'], 'sotto_es_tts')
os.makedirs(TMP, exist_ok=True)
BEATS = open(os.path.join(OUT, 'beats.txt'), encoding='utf-8').read().splitlines()
AD_LIB_AFTER = 7  # after beat 7 the presenter ad-libs
AD_LIB = "Bueno, perdón, déjenme tomar un poquito de agua. Ya, listo, sigo."

async def clip(text, path):
    mp3 = path + '.mp3'
    await edge_tts.Communicate(text, "es-MX-JorgeNeural", rate="-12%").save(mp3)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-ar", "16000", "-ac", "1",
                    "-c:a", "pcm_s16le", path], check=True)
    w = wave.open(path); d = w.readframes(w.getnframes()); w.close()
    return list(struct.unpack('<%dh' % (len(d) // 2), d))

async def main():
    random.seed(7)
    out = []
    marks = []
    for i, b in enumerate(BEATS):
        marks.append((len(out) / 16000, i))
        out += await clip(b, os.path.join(TMP, f'b{i}.wav'))
        out += [0] * int(16000 * random.uniform(0.6, 1.4))
        if i == AD_LIB_AFTER:
            marks.append((len(out) / 16000, -1))
            out += await clip(AD_LIB, os.path.join(TMP, 'adlib.wav'))
            out += [0] * int(16000 * 1.5)
    # Room noise around -50 dBFS.
    noisy = [max(-32768, min(32767, int(s * 0.8 + random.gauss(0, 100)))) for s in out]
    path = os.path.join(OUT, 'natural.wav')
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(struct.pack('<%dh' % len(noisy), *noisy)); w.close()
    with open(os.path.join(OUT, 'natural_marks.txt'), 'w') as f:
        f.write('\n'.join(f'{t:.2f} {b}' for t, b in marks))
    print(path, len(noisy) / 16000)

asyncio.run(main())
