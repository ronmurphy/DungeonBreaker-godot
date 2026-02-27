# 🎮 GPU Setup Guide

## Maximize Your Performance

### Quick GPU Check

1. Open Developer Tools: `F12`
2. Look for "**GPU DETECTION REPORT**"
3. Check which GPU is active

**What You'll See:**
```
✅ STATUS: dGPU requested and dGPU detected - MATCH! 🎯
```

✅ **MATCH!** = Using best GPU  
⚠️ **WARNING** = Need to fix (see below)

---

## 🪟 Windows: Force High-Performance GPU

### Method 1: In-Game (Easiest)
1. Open this menu (ESC)
2. Go to **Performance** tab
3. Click **GPU Mode** button
4. Game will auto-reload
5. Check if GPU changed (F12)

### Method 2: Windows Graphics Settings
If in-game doesn't work:

1. **Windows Settings** > **System** > **Display**
2. Scroll down: **Graphics Settings**
3. Click **Browse**
4. Find: `VoxelWorld.exe`
5. Click **Options**
6. Select: **High Performance**
7. Click **Save**
8. Restart game

### Method 3: Desktop Shortcut
1. Right-click `VoxelWorld.exe`
2. **Create shortcut**
3. Right-click shortcut > **Properties**
4. In "Target" add:
   ```
   --force_high_performance_gpu
   ```
5. Should look like:
   ```
   "C:\...\TheLongNights.exe" --force_high_performance_gpu
   ```

---

## 🐧 Linux: Force High-Performance GPU

### Terminal Command:
```bash
./TheLongNights --force_high_performance_gpu
```

Or create launcher script:
```bash
#!/bin/bash
cd /path/to/TheLongNights
./TheLongNights --force_high_performance_gpu
```

---

## Expected Performance

### Integrated GPU (iGPU)
- **Intel UHD, Iris Xe**
- **FPS**: 30-45
- **Best for**: Battery life, casual play

### Dedicated GPU (dGPU)
- **NVIDIA RTX, AMD Radeon**
- **FPS**: 60-120+
- **Best for**: Performance, high settings

---

## Still Having Issues?

See **Command Line** help section for advanced options.
