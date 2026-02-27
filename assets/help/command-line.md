# 💻 Command-Line Switches

## Advanced Performance Options

### 🪟 Windows Syntax

**Shortcut Target:**
```
"C:\Path\To\TheLongNights.exe" --switch1 --switch2
```

**Important:**
- Switches go **OUTSIDE** the quotes
- Use **double dash** (--) not single (-)
- Space-separated

---

### 🐧 Linux Syntax

**Terminal:**
```bash
./TheLongNights --switch1 --switch2
```

**Important:**
- Use `./TheLongNights` (dot-slash)
- Use **double dash** (--)
- Space-separated

---

## Available Switches

### GPU Performance

**`--force_high_performance_gpu`**
- Forces use of dedicated GPU (dGPU)
- **Recommended for all gaming laptops**

**`--disable-gpu-vsync`**
- Disables V-Sync for uncapped FPS
- Good for performance testing

**`--ignore-gpu-blacklist`**
- Uses GPU even if flagged problematic
- For older GPUs with driver issues

**`--enable-gpu-rasterization`**
- GPU-accelerated 2D rendering
- Better overall performance

---

## Recommended Combinations

### Gaming Laptop (Best Performance)
```
--force_high_performance_gpu --disable-gpu-vsync
```

### Maximum Performance Testing
```
--force_high_performance_gpu --disable-gpu-vsync --enable-gpu-rasterization
```

### Troubleshooting GPU Issues
```
--force_high_performance_gpu --ignore-gpu-blacklist --enable-logging
```

---

## Debugging Switches

**`--enable-logging`**
- Shows detailed console logs
- For troubleshooting crashes

**`--disable-gpu`**
- Software rendering only
- Testing without GPU

**`--remote-debugging-port=9222`**
- Chrome DevTools remote debugging
- Advanced debugging

---

## Real Examples

### ✅ CORRECT

**Windows:**
```
"C:\Games\TheLongNights.exe" --force_high_performance_gpu
```

**Linux:**
```bash
./TheLongNights --force_high_performance_gpu
```

### ❌ WRONG

**Windows (switches inside quotes):**
```
"C:\Games\TheLongNights.exe --force_high_performance_gpu"
```

**Linux (no dot-slash):**
```bash
TheLongNights --force_high_performance_gpu
```

---

## Verify It Worked

1. Launch game with switches
2. Press `F12` (Developer Tools)
3. Look for GPU Detection Report
4. Should show: **"MATCH! 🎯"**

---

## Need More Help?

- Check **GPU Setup** for simpler methods
- See full docs in `docs/` folder
- Ask in community forums
