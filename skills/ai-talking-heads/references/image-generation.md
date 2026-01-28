---
name: image-generation
description: Nano Banana Pro and the imperfection principle for realistic AI character images
tags: image-gen, nano-banana, realism, ugc, character
---

# Image Generation for Talking Heads

## The Imperfection Principle

AI-generated images look "off" because they're too perfect. Real UGC (user-generated content) and talking-head videos have:

- Visible skin texture: pores, oils, minor blemishes
- Imperfect lighting: overhead fluorescent, window light, phone flash
- Casual framing: slightly off-center, not studio-posed
- Natural expression: mid-sentence, not smiling at camera

Your image prompt must actively request these imperfections.

## Recommended Tool: Nano Banana Pro

Nano Banana Pro (via fal.ai or similar) produces photorealistic portraits suited to the talking-head use case. Other tools (Flux, DALL-E, Midjourney) can work but typically need more aggressive realism prompting.

## Prompt Structure

Build the image prompt in layers:

1. **Subject description** -- age, ethnicity, hair, clothing
2. **Expression and pose** -- mid-speech, looking at camera, natural posture
3. **Environment** -- home office, bedroom, coffee shop (match the script's tone)
4. **Camera/technical** -- iPhone selfie, ISO 800, natural lighting, shallow depth of field
5. **Realism markers** -- visible pores, skin oils, no airbrushing, no studio lighting
6. **Negative prompt** -- smooth skin, studio background, professional lighting, perfect symmetry

See `prompt-templates.md` for the full copy-pasteable template.

## Character Consistency

When generating multiple clips, the base character image must stay consistent:

- **Use the same reference image** as input to every video generation prompt
- **Lock key attributes** in every prompt: same hair color/style, same clothing, same background
- **Accept minor variation** -- small inconsistencies actually match UGC aesthetic (people shift in their chair, lighting changes slightly)

## Upscaling

Generated images are typically 512x512 or 1024x1024. For 9:16 vertical video (1080x1920), upscale using:

- **Enhancor AI** -- preserves skin texture, doesn't over-smooth
- **Real-ESRGAN** -- open-source alternative, good for faces with `realesrgan-x4plus-anime` model avoided (use `realesrgan-x4plus` for photorealism)

Upscale before feeding to the video generator. Higher-resolution input = better video output.

## Common Mistakes

| Mistake | Why it fails | Fix |
|---------|-------------|-----|
| "Beautiful woman smiling" | Too generic, triggers beauty filter mode | Add specific imperfections + technical params |
| Studio lighting in prompt | Creates obvious AI look | Specify "natural window light" or "overhead fluorescent" |
| Perfect symmetry | Uncanny valley | Add "slightly asymmetric face" or "candid expression" |
| Ignoring background | Generator fills with generic blur | Specify exact environment |
| Portrait orientation crop | Face fills frame unnaturally | Use waist-up or chest-up framing for talking head |
