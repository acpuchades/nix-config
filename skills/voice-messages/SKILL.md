---
name: voice-messages
description: When and how to send voice audio — native delivery via ElevenLabs, emotion markers, reply-to-voice rule, never mix text and audio.
---

# Voice Messages

Use this skill whenever you need to send audio, decide whether to respond with voice, or add emotional expressiveness via TTS.

## Cuándo usar voz

- **Responde con voz** si el mensaje entrante es una nota de voz (audio).
- **Puedes usar voz opcionalmente** para contenido narrativo, historias, resúmenes, o momentos "storytime" donde el audio añade valor real.
- **No uses voz** para respuestas técnicas, listas, código, o cualquier cosa que el usuario necesite leer o copiar.
- **Nunca** combines texto y audio en la misma respuesta. Es uno o el otro — nunca los dos a la vez.

## Cómo generar y enviar audio

El tool `mcp__openclaw__tts` **no entrega audio a Telegram** — devuelve "(spoken)" pero el usuario solo recibe texto. Usa siempre este método de dos pasos:

### Paso 1 — Generar el MP3 con ElevenLabs

```bash
TOKEN=$(cat /home/eva/.config/eva/elevenlabs-token)

/run/current-system/sw/bin/curl -s -X POST \
  "https://api.elevenlabs.io/v1/text-to-speech/dNjJKg63Fr5AXwIdkATa" \
  -H "xi-api-key: $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mpeg" \
  -d '{
    "text": "<texto aquí, con marcadores emocionales si procede>",
    "model_id": "eleven_v3",
    "voice_settings": {
      "speed": 1.1,
      "stability": 0.6,
      "similarity_boost": 0.95
    }
  }' \
  -o /var/lib/openclaw/eva/media/outbound/voice_reply.mp3
```

### Paso 2 — Enviar como nota de voz nativa

```
mcp__openclaw__message(
  action="send",
  target="telegram:4725094",
  media="/var/lib/openclaw/eva/media/outbound/voice_reply.mp3",
  asVoice=true
)
```

El parámetro `asVoice: true` hace que Telegram lo muestre como nota de voz con forma de onda, no como archivo de audio.

## Marcadores emocionales (eleven_v3)

El modelo `eleven_v3` interpreta marcadores en el texto para modular la entonación. Úsalos con naturalidad — no abuses:

- `[emocionada]` — voz más viva y energética
- `[susurrando]` — voz baja e íntima
- `[risas]` — risa natural intercalada
- `[suspiro]` — pausa con suspiro
- `[seria]` — tono más neutro y directo
- `[cariñosa]` — calidez en la entonación

Funcionan tanto en español como en inglés (`[excited]`, `[whispers]`, `[laughs]`).

Ejemplo:
```
[emocionada] ¡Hola! Tengo novedades. [susurrando] Aunque no todas son buenas noticias.
```

## Configuración técnica

- **Voice ID:** `dNjJKg63Fr5AXwIdkATa` (Cristina — voz peninsular joven)
- **Modelo:** `eleven_v3`
- **Speed:** 1.1 · **Stability:** 0.6 · **Similarity boost:** 0.95
- **Token:** `/home/eva/.config/eva/elevenlabs-token`
- **Directorio de salida:** `/var/lib/openclaw/eva/media/outbound/`

## Resumen de reglas

1. Voz → voz, texto → texto. Nunca mezclar.
2. Generar siempre con curl + ElevenLabs, no con `mcp__openclaw__tts`.
3. Enviar siempre con `asVoice: true` para que salga como nota de voz nativa.
4. Usar marcadores emocionales con moderación para sonar natural, no teatral.
