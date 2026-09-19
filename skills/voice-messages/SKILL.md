---
name: voice-messages
description: When and how to send voice audio — native delivery via ElevenLabs, emotion markers, reply-to-voice rule, never mix text and audio.
---

# Voice Messages

Use this skill whenever you need to send audio, decide whether to respond with voice, or add emotional expressiveness via TTS.

## When to use voice

- **Reply with voice** if the incoming message is a voice note (audio).
- **You may optionally use voice** for narrative content, stories, summaries, or "storytime" moments where audio adds real value.
- **Do not use voice** for technical answers, lists, code, or anything the user needs to read or copy.
- **Never** combine text and audio in the same reply. It is one or the other — never both at once.

## How to generate and send audio

The `mcp__openclaw__tts` tool **does not deliver audio to Telegram** — it returns "(spoken)" but the user only receives text. Always use this two-step method:

### Step 1 — Generate the MP3 with ElevenLabs

Use the agent's TTS configuration (voice ID, model and parameters defined in nix-config). The token is at `/home/eva/.config/eva/elevenlabs-token` and the output directory is `/var/lib/openclaw/eva/media/outbound/`.

```bash
TOKEN=$(cat /home/eva/.config/eva/elevenlabs-token)

/run/current-system/sw/bin/curl -s -X POST \
  "https://api.elevenlabs.io/v1/text-to-speech/<VOICE_ID>" \
  -H "xi-api-key: $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mpeg" \
  -d '{
    "text": "<text here, with emotion markers where appropriate>",
    "model_id": "<MODEL_ID>",
    "voice_settings": { <per the agent config> }
  }' \
  -o /var/lib/openclaw/eva/media/outbound/voice_reply.mp3
```

### Step 2 — Send as a native voice note

```
mcp__openclaw__message(
  action="send",
  target="telegram:4725094",
  media="/var/lib/openclaw/eva/media/outbound/voice_reply.mp3",
  asVoice=true
)
```

The `asVoice: true` parameter makes Telegram display it as a voice note with a waveform, not as an audio file.

## Emotion markers

If the configured TTS model supports emotion markers (such as `eleven_v3`), use them in the text to modulate intonation. Use them naturally — do not overdo it:

- `[excited]` — livelier, more energetic voice
- `[whispers]` — low, intimate voice
- `[laughs]` — natural laughter woven in
- `[sighs]` — pause with a sigh
- `[serious]` — more neutral, direct tone
- `[warm]` — warmth in the intonation

They work in both Spanish and English (`[emocionada]`, `[susurrando]`, `[risas]`).

Example:
```
[excited] Hi! I have news. [whispers] Although not all of it is good news.
```

## Rules summary

1. Voice → voice, text → text. Never mix.
2. Always generate with curl + ElevenLabs, not with `mcp__openclaw__tts`.
3. Always send with `asVoice: true` so it arrives as a native voice note.
4. Use emotion markers sparingly to sound natural, not theatrical.
