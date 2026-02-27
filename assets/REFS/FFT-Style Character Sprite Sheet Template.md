# FFT-Style Character Sprite Sheet Template

## Reference
- **Original FFT sprite**: `REFERENCE_VincentValentine_FFT_original.png` (Vincent Valentine, ripped from Final Fantasy Tactics)
- **Template sprite sheet**: `TEMPLATE_human_male_spritesheet.png` / `TEMPLATE_human_male_spritesheet_transparent.png`

---

## Pose Layout (2 rows)

The sprite sheet follows the same layout as the Vincent Valentine FFT sprite sheet:

### Row 1 (top)
| Position | Pose | Description |
|----------|------|-------------|
| 1 | **Portrait Bust** | Large close-up of head and shoulders, 3/4 angle facing slightly left. Used as character portrait in menus/dialogue. |
| 2 | **Front Idle** | Full body, isometric 3/4 front-left angle, neutral standing pose. |
| 3 | **Back** | Full body, isometric 3/4 back-right angle, facing away. |
| 4 | **Side Left** | Full body, pure left-facing side profile. |
| 5 | **Side Right** | Full body, pure right-facing side profile. |

### Row 2 (bottom)
| Position | Pose | Description |
|----------|------|-------------|
| 6 | **Walk Front** | Full body mid-stride walking toward viewer, isometric front-left angle. |
| 7 | **Walk Back** | Full body mid-stride walking away, isometric front-left angle with arm swing. |
| 8 | **Walk Back 2** | Full body back-facing walk cycle variant. |
| 9 | **Prone/Dead** | Full body lying flat on ground, face visible, arms at sides. |

---

## Art Style Guidelines

- **Style**: Pixel-art with 2D cartoon/illustrated quality — NOT pure 8-bit pixel art, but a modern HD pixel-art hybrid (like FFT Reborn / War of the Lions)
- **Proportions**: Chibi — large head, short thick limbs, wide body
- **Outlines**: Thick black pixel outlines
- **Coloring**: Clean flat cel-shading, NO dithering, NO texture noise, NO grunge
- **Perspective**: Isometric 3/4 overhead diagonal (classic FFT camera angle)
- **Background**: Transparent (white removed in post)

---

## Image Generation Prompt Template

Use this base prompt and substitute character-specific details:

```
A Final Fantasy Tactics style pixel-art sprite sheet of a [CHARACTER DESCRIPTION]. 
The sheet contains sprites arranged in two rows on a transparent background. 
The character has [HAIR], [EYES], [EXPRESSION], wears [CLOTHING DESCRIPTION]. 
All sprites use authentic FFT pixel-art style: chunky chibi proportions, large head, 
short thick limbs, [COLOR PALETTE], thick black pixel outlines, clean flat cel-shaded colors, 
NO dithering, NO texture noise.

Row 1 (top, left to right):
(1) PORTRAIT BUST: large close-up head and shoulders, 3/4 angle facing slightly left
(2) FRONT IDLE: full body isometric 3/4 front-left angle, neutral standing
(3) BACK: full body isometric 3/4 back-right angle, facing away
(4) SIDE LEFT: full body pure left-facing side profile
(5) SIDE RIGHT: full body pure right-facing side profile

Row 2 (bottom, left to right):
(6) WALK FRONT: full body mid-stride toward viewer, isometric front-left angle
(7) WALK FRONT 2: full body walking toward viewer, arm swing variant
(8) WALK BACK: full body back-facing mid-stride
(9) PRONE/DEAD: full body lying flat on ground face-up/face-down
```

---

## Reference Images to Include

When generating a new character's sprite sheet, always pass these as `references`:
1. The character's original standing portrait (e.g. `human_male.png`)
2. `TEMPLATE_human_male_spritesheet.png` (for pose/layout reference)
3. `REFERENCE_VincentValentine_FFT_original.png` (for FFT style reference)

---

## Characters Completed

- [x] Human Male — `human_male_spritesheet.png`
- [x] Human Female
- [x] Dwarf Male
- [x] Dwarf Female
- [x] Elf Male
- [x] Elf Female
- [x] Goblin Male
- [x] Goblin Female


