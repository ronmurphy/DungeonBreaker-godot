# VoxelWorld Game Data

This folder contains all game content as JSON files for easy editing and updating.

## Status Indicators

- **✅ Fully Implemented** - Works in game, has art, fully functional
- **🚧 Partially Implemented** - Code exists but missing art/assets
- **📋 Planned** - In JSON for future implementation

## Files

### `recipes.json`
Kitchen Bench food recipes. Each recipe has:
- `ingredients`: What items are needed
- `result`: Stamina/buffs the food provides
- `status`: Implementation status

### `blueprints.json`
Toolbench crafting blueprints for tools/weapons/equipment.

### `plans.json`
Workbench building plans for placeable structures.

## Updating Content

### To Add a New Recipe:
1. Add entry to `recipes.json` with `status: "📋"`
2. Implement in game code
3. Create/add art assets
4. Update `status` to `"✅"`

### To Balance Existing Items:
Just edit the numbers in JSON and reload the game!

## For Your Writer Friend

When ready, you can add `story.json` here with:
```json
{
  "quests": [...],
  "dialogues": [...],
  "lore": [...]
}
```

## Notes

- DON'T delete entries - mark as `"status": "📋"` instead
- Comment field is for internal notes
- IDs must match what the code expects
- Emoji field is for display in UI
