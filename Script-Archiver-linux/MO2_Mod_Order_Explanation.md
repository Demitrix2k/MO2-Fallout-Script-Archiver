# Mod Organizer 2: Mod List Order & File Conflict Resolution

## Overview

Mod Organizer 2 (MO2) uses a **priority-based system** where mods are arranged in a specific order. When multiple mods contain the same file, the mod with the **higher priority number** (lower in the list) wins the conflict.

## Visual Representation

```
┌─────────────────────────────────────────────────────────────┐
│                    MOD ORGANIZER 2                          │
│                     MOD LIST                                │
├─────────────────────────────────────────────────────────────┤
│ Priority │ Mod Name              │ Status │ Files           │
├─────────────────────────────────────────────────────────────┤
│    1     │ Base Game Files       │   ✓    │ weapon.nif      │
│    2     │ Bug Fix Pack          │   ✓    │ misc_fixes.esp  │
│    3     │ Texture Overhaul      │   ✓    │ weapon.nif      │ ← Overwrites #1
│    4     │ Weapon Replacer       │   ✓    │ weapon.nif      │ ← Overwrites #1,#3
│    5     │ HD Graphics Pack      │   ✓    │ ui_textures.dds │
│    6     │ Custom Weapon Mod     │   ✓    │ weapon.nif      │ ← WINNER! (Highest Priority)
│    7     │ Sound Overhaul        │   ✓    │ ambient.wav     │
└─────────────────────────────────────────────────────────────┘
                         ↑
                    HIGHER PRIORITY
                   (Lower in the list)
```

## File Conflict Resolution Example

### Scenario: Multiple mods contain `weapon.nif`

```
📁 weapon.nif file exists in:
├── Priority 1: Base Game Files        ❌ Overwritten
├── Priority 3: Texture Overhaul       ❌ Overwritten  
├── Priority 4: Weapon Replacer        ❌ Overwritten
└── Priority 6: Custom Weapon Mod      ✅ ACTIVE (Highest Priority)
```

### What happens in-game:
- The game loads `weapon.nif` from **"Custom Weapon Mod"** (Priority 6)
- All other versions are ignored, even though they exist in their respective mods
- Priority 6 > Priority 4 > Priority 3 > Priority 1

## Key Rules

### Priority Numbers
- **Higher number = Higher priority**
- **Lower position in list = Higher priority**
- **Last mod wins** the file conflict

### Conflict Indicators
```
🟢 Green+  = Mod provides unique files (no conflicts)
🟡 Yellow± = Mod has conflicts but some files are active
🔴 Red-    = Mod is completely overridden by higher priority mods
```

## Practical Example

Let's say you have these texture mods:

```
┌─────────────────────────────────────────────────────────┐
│ Priority │ Mod Name           │ Files                   │
├─────────────────────────────────────────────────────────┤
│    10    │ Vanilla Textures   │ rock.dds, tree.dds     │
│    15    │ Nature Overhaul    │ tree.dds, grass.dds    │ 🟡
│    20    │ Rock Replacer      │ rock.dds               │ 🟢
│    25    │ Ultimate Nature    │ tree.dds, rock.dds     │ 🟢
└─────────────────────────────────────────────────────────┘
```

### Final Result:
- `rock.dds` comes from **Ultimate Nature** (Priority 25) ✅
- `tree.dds` comes from **Ultimate Nature** (Priority 25) ✅  
- `grass.dds` comes from **Nature Overhaul** (Priority 15) ✅
- Vanilla textures are completely overridden ❌

## BSA Archive Priority

BSA archives follow the same rules but with additional considerations:

```
┌─────────────────────────────────────────────────────────┐
│ BSA Loading Order (Plugin-based)                       │
├─────────────────────────────────────────────────────────┤
│ 1. Fallout - Textures.bsa    (Base Game)              │
│ 2. CustomMod.bsa             (Mod Plugin: Priority 5)  │
│ 3. AnotherMod.bsa            (Mod Plugin: Priority 10) │
│ 4. Loose Files               (Always highest priority) │
└─────────────────────────────────────────────────────────┘
```

### Important Notes:
- **Loose files always win** over BSA archives
- BSA load order follows the plugin load order
- `.override` files can force BSA priority changes


