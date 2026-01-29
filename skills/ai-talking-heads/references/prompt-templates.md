---
name: prompt-templates
description: Full copy-pasteable prompt templates for image and video generation
tags: prompts, templates, image-gen, video-gen
---

# Prompt Templates

Copy-pasteable templates with `{VARIABLE}` placeholders. Replace all variables before using.

## Image Generation Prompt

### Base Character Image

```
Photograph of a {AGE}-year-old {ETHNICITY} {GENDER}, {HAIR_DESCRIPTION},
wearing {CLOTHING}. {EXPRESSION} expression, looking directly at camera.
{POSE} pose, {FRAMING} framing.

Setting: {ENVIRONMENT}. {LIGHTING_DESCRIPTION}.

Shot on iPhone 14 Pro, ISO 800, f/1.9 aperture, natural lighting.
Visible skin pores, natural skin oils, slight under-eye shadows.
No airbrushing, no studio lighting, no beauty filter.
Authentic UGC selfie-style photograph.
```

### Variable Guide

| Variable | Examples |
|----------|---------|
| `{AGE}` | 25, 30, 45 |
| `{ETHNICITY}` | Caucasian, East Asian, South Asian, Black, Latino/a |
| `{GENDER}` | man, woman, person |
| `{HAIR_DESCRIPTION}` | short brown hair, long black hair pulled back, curly red hair |
| `{CLOTHING}` | plain white t-shirt, dark blue button-down, casual gray hoodie |
| `{EXPRESSION}` | Mid-sentence, thoughtful, engaged, slightly smiling |
| `{POSE}` | Seated at desk, standing in kitchen, seated on couch |
| `{FRAMING}` | Chest-up, waist-up, head-and-shoulders |
| `{ENVIRONMENT}` | Home office with bookshelf, modern kitchen, bedroom with natural light |
| `{LIGHTING_DESCRIPTION}` | Warm window light from the left, overhead LED panel, soft afternoon sunlight |

### Negative Prompt (if supported)

```
smooth skin, studio background, professional photography, ring light,
beauty mode, perfect symmetry, airbrushed, HDR, oversaturated,
bokeh background, portrait mode blur
```

## Video Generation Prompt

### Per-Chunk Video Prompt

```
Reference image: [attach base character image]

{SUBJECT_DESCRIPTION} speaks directly to camera in {ENVIRONMENT}.
Script text for this segment: "{CHUNK_TEXT}"
Tone: {TONE}

[0-3s] {ACTION_START}. Natural blink, {OPENING_GESTURE}.

[3-6s] {ACTION_MIDDLE}. {HAND_GESTURE} while emphasizing key point.
{MICRO_EXPRESSION}.

[6-10s] {ACTION_END}. {CLOSING_GESTURE}. Expression settles into
{CLOSING_EXPRESSION}.

Style: Natural, unscripted feel. Subtle movements only. UGC talking-head.
Aspect ratio: 9:16 vertical.
Duration: 10 seconds.
```

### Variable Guide

| Variable | Examples |
|----------|---------|
| `{SUBJECT_DESCRIPTION}` | Young woman with brown hair in white t-shirt |
| `{CHUNK_TEXT}` | The actual script text for this chunk |
| `{TONE}` | Conversational and confident, Excited and energetic, Calm and authoritative |
| `{ACTION_START}` | Subject looks at camera with slight head tilt, Subject pauses then begins speaking |
| `{OPENING_GESTURE}` | right hand adjusts hair, slight shoulder shrug |
| `{ACTION_MIDDLE}` | Leans forward slightly, Straightens posture |
| `{HAND_GESTURE}` | Open palm gesture toward camera, Gentle emphatic gesture, Hand moves to illustrate point |
| `{MICRO_EXPRESSION}` | Eyebrows raise briefly, Corner of mouth quirks up |
| `{ACTION_END}` | Leans back in chair, Nods slowly |
| `{CLOSING_GESTURE}` | Hands return to resting position, Touches chin thoughtfully |
| `{CLOSING_EXPRESSION}` | Relaxed confidence, Thoughtful pause |

## Required: Explicit Lip Movement Cues

Kling will NOT generate lip movement unless you explicitly request it. **Always include:**

- In the intro: "Mouth moves naturally as she talks throughout"
- In each time block: "Lips move as she speaks" or "talking naturally"
- For the final beat: "Lips still moving as she finishes"

**Phrases that STOP lip movement (avoid these):**
- "closed-lip smile" — tells Kling to keep mouth shut
- "holds the pose" / "still" — freezes all motion including lips
- "knowing smile" without speaking cue — defaults to closed mouth

## Gestures to Avoid

AI video generators are unreliable with specific hand poses. **Do not use:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| "holds up three fingers" | Wrong finger count | "emphatic hand gesture" |
| "counting on fingers" | Random finger movements | "illustrative gesture" |
| "thumbs up" / "peace sign" | Often distorted | "positive expression, slight nod" |
| "points at specific object" | Pointing direction wrong | "gestures toward camera" |

Keep gestures vague and emotional rather than specific and script-tied.

## Modification Guide

### Increasing Energy
- Add more hand gestures per time block
- Use "animated" and "enthusiastic" modifiers
- Add "weight shifts forward" for emphasis

### Decreasing Energy (Calm/Authority)
- Reduce gestures to one per 3-second block
- Use "measured" and "deliberate" modifiers
- Add "steady gaze" and "minimal movement"

### Matching Clip Boundaries
For smooth transitions between clips:
- **End of clip N:** Describe a settling pose (hands down, neutral expression)
- **Start of clip N+1:** Begin from that same pose, then introduce new movement

Example continuity pair:
```
Clip 1 ending: [6-10s] Hands return to desk, slight nod, relaxed expression.
Clip 2 opening: [0-3s] From resting position, subject takes a breath and leans forward...
```
