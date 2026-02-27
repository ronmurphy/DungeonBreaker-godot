# 💾 Save System Guide

## Overview

The game features a **5-slot save system** with screenshot thumbnails. Each save captures:
- Player position, health, hunger, and inventory
- All blocks you've placed or removed
- Crafted objects (campfires, workbenches, etc.)
- Explorer journal pins and navigation waypoints
- Your respawn campfire location

## How to Save

### Method 1: Campfire Save (Recommended)
1. **Craft a Campfire** at a Workbench
2. **Place the Campfire** where you want to save
3. **Interact with the Campfire** (E key)
4. Select **"💾 Save Game"** from the menu
5. Choose a save slot (1-5)
6. A screenshot thumbnail is automatically captured!

### Method 2: Menu Save
1. Press **ESC** to open Adventurer's Menu
2. Go to **"🗺️ World"** tab
3. Click **"💾 Save Game"**
4. Choose a save slot (1-5)

## How to Load

1. Press **ESC** → **"🗺️ World"** tab
2. Click **"📂 Load Game"**
3. Select a save slot
4. Your world, position, and inventory will be restored!

## Save Slot Features

Each save slot displays:
- **📸 Thumbnail**: Screenshot of your game when you saved
- **⏰ Timestamp**: Date and time of save
- **🎮 Playtime**: Total hours played
- **📊 Stats**: Blocks placed, objects crafted, pins created

## Tips

- **Save often!** Especially before exploring dangerous areas
- **Use multiple slots** for different stages of your adventure
- **Campfire saves** are lore-friendly and immersive
- **Desktop builds** have unlimited save file size
- **Web builds** limited to ~5MB per save (use desktop for large worlds)

## Technical Details

- Saves are **compressed** using msgpack + gzip (~60% smaller than JSON)
- Only **player modifications** are saved (not the entire world)
- Saves are stored in your **user data folder** (Electron) or **browser localStorage** (web)
- Compatible across **Windows and Linux** builds

## Troubleshooting

**"Storage limit exceeded"**
- Your world has too many modifications for web storage
- Solution: Download and use the **desktop Electron build**

**"No save data found"**
- The save slot is empty or corrupted
- Try a different slot

**"Failed to capture screenshot"**
- Graphics rendering issue
- Save will still work, but without a thumbnail
- Try saving again

## Future Features

- Auto-save on campfire placement
- Cloud save sync (optional)
- Save file export/import
- Save file encryption
