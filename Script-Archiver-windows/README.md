# MO2 Script Archiver - Windows Version

A tool to consolidate multiple MO2 mods into organized BSA archives for better performance and cleaner mod lists.

**Version:** 2.0-Windows  
**Platform:** Windows (PowerShell 7.5+)

---

## Quick Start

### Prerequisites
- **Mod Organizer 2** (any recent version)
- **Windows** with **PowerShell 7.5+**
- **BSArch.exe** (included in `BSArch/` folder)

### Running the Tool
```batch
# Simply double-click
Run Script Archiver.bat
```

---

## Features

- **Mod Consolidation** - Combine multiple mods within categories
- **BSA Archive Creation** - Automatically create BSA archives
- **Automatic Backups** - Non-destructive with `.copied.mohidden` renaming
- **Configuration Presets** - Customizable workflow settings
- **Cross-Category Conflict Analysis** - Detect and resolve file conflicts
- **Restore Capability** - Full restoration of original files

---

## File Structure

```
Script-archiver/
├── Run Script Archiver.bat          # Main launcher
├── README.md                         # This file
├── MO2_Mod_Order_Explanation.md     # Documentation on MO2 priorities
├── BSArch/
│   ├── BSArch.exe                   # Archive creation tool
│   └── BSArch Documentation.txt
├── scripts/
│   ├── 0_Script-launcher.ps1        # Menu system
│   ├── 1_MainCompiler.ps1           # Workflow 1: Compile & Archive
│   ├── 2_RestoreAndRename.ps1       # Workflow 2: Restore & Cleanup
│   ├── config-presets.json          # Configuration presets
│   └── quick-launch.ps1             # Preset quick-launch
├── compiled_mod_files/              # Temporary compilation folder
├── generated_archives/              # Temporary BSA archive folder
└── mods-backup/                     # Automatic backup storage
    └── [CategoryName]/
        └── [ModName]/
            └── [files.copied.mohidden]
```

---

## How It Works

### Workflow 1: Compile and Archive
1. Select categories to consolidate
2. Files are copied with proper directory structure
3. BSA archives created via BSArch.exe
4. ESP plugins generated
5. Original files renamed to `.copied.mohidden`
6. Backups moved to `mods-backup/`

### Workflow 2: Restore Backups
1. Choose categories to restore
2. Files copied back to original locations
3. `.copied.mohidden` extension removed
4. Empty backup folders cleaned up

---

## Configuration

Edit `scripts/config-presets.json` for custom settings.

**Default settings:**
- Create BSA archives: Yes
- Generate ESP plugins: Yes
- Compression: No (recommended for sound files)
- Conflict analysis: Disabled (faster)
- Original file handling: Rename to `.copied.mohidden`
- Backup management: Automatic

**Available presets:**
- **default**: Balanced settings for most users
- **quick**: Maximum automation, minimal prompts
- **conservative**: Safe settings with conflict analysis enabled
- **manual**: Fine control with manual mod selection

---

## Example Workflow

**Before Consolidation:** 
```
... (20+ individual LOD mods)
+ LOD Enhancement
+ Distant Terrain Fix
+ Improved Cliffs
+ HD Trees  
+ Better Rocks
+ Enhanced Landscapes
```

**After Consolidation:**
```
... (originals renamed and backed up)
- HD Trees (hidden: .copied.mohidden)
- Better Rocks (hidden: .copied.mohidden) 
- Enhanced Landscapes (hidden: .copied.mohidden)
+ LOD Compiled (new consolidated mod)
+ LOD Archive (new BSA with ESP)
```

**Backup Structure:**
```
mods-backup/
└── LOD/
    ├── HD Trees/
    │   └── textures/trees/tree.dds.copied.mohidden
    ├── Better Rocks/
    │   └── meshes/rocks/rock.nif.copied.mohidden
    └── Enhanced Landscapes/
        └── textures/landscape/ground.dds.copied.mohidden
```

**After Restoration:**
```
... (originals restored, consolidated mods removed)
+ HD Trees (restored)
+ Better Rocks (restored)
+ Enhanced Landscapes (restored)
- LOD Compiled (removed/disabled)
- LOD Archive (removed/disabled)
```

---

## File Types Supported

Default file types (extensible):
- `.nif` - 3D meshes
- `.dds` - Textures
- `.kf` - Animations
- `.wav` - Audio files
- `.ogg` - Audio files
- `.lip` - Lip sync files

See https://geckwiki.com/index.php?title=Packing_Assets_in_BSA_Tutorial for what can be packed.

Edit `$FileExtensions` parameter in scripts to add more types.

---

## Important Notes

### Directory Structure
Files MUST maintain proper Fallout/Skyrim directory structure:
```
compiled_folder/
├── meshes/
│   └── weapons/
│       └── rifle.nif
├── sound/
│   └── fx/
│       └── shot.wav
└── textures/
    └── weapons/
        └── rifle.dds
```

### BSA vs Loose Files
- **Loose files always override BSA archives** in-game
- BSA load order follows plugin (ESP) load order
- See [MO2_Mod_Order_Explanation.md](MO2_Mod_Order_Explanation.md) for details

### Backup Safety
- Original files are renamed to `.copied.mohidden` (not deleted)
- Backups organized in `mods-backup/[CategoryName]/[ModName]/`
- Always restorable via Workflow 2

---

## MO2 Setup

Place this tool in your MO2 installation directory:
```
MO2/
├── mods/
├── profiles/
├── downloads/
└── windows-version/    ← This tool
    └── Run Script Archiver.bat
```

The tool uses relative paths to find `../mods` and `../profiles`.

---

## Advanced Usage

### Direct Script Execution
```powershell
# Main compiler
pwsh -File .\scripts\1_MainCompiler.ps1

# Restore backups
pwsh -File .\scripts\2_RestoreAndRename.ps1

# With custom paths
pwsh -File .\scripts\1_MainCompiler.ps1 `
  -ModsPath "C:\path\to\mods" `
  -ModlistPath "C:\path\to\profile\modlist.txt"
```

### Custom Configuration
Edit `scripts/config-presets.json` to modify the "default" preset or create new ones.

---

## Troubleshooting

### BSArch fails to create archive
- Ensure files have proper directory structure (meshes/, sound/, etc.)
- Verify BSArch.exe is in the BSArch folder

### "No valid files found for packing"
- Files aren't in proper subdirectories
- BSArch requires game directory structure (meshes/, textures/, sound/)
- The script automatically preserves directory structure

---

## Third-Party Software

This tool includes **BSArch.exe** for creating BSA archives.

- **BSArch** is part of the TES5Edit project
- **Authors**: Zilav, Sheson, ElminsterAU
- **License**: Mozilla Public License 2.0 (MPL-2.0)
- **Source Code**: https://github.com/TES5Edit/TES5Edit
- **License Text**: See `BSArch/LICENSE-MPL-2.0.txt`

BSArch is distributed unchanged from the original. The MPL-2.0 license permits redistribution of unmodified executables. The complete source code is available at the link above.

---

## Credits

- **Original Tool**: Demitrix@nexusmods.com
- **BSArch**: Zilav, Sheson, ElminsterAU (MPL-2.0)

---

## Support

For MO2 priority system information, see [MO2_Mod_Order_Explanation.md](MO2_Mod_Order_Explanation.md).

**Made for Fallout New Vegas modding, but adaptable to other games.**
