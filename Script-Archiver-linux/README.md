# MO2 Script Archiver - Linux Version

A tool to consolidate multiple MO2 mods into organized BSA archives for better performance and cleaner mod lists.

**Version:** 2.0-Linux  
**Platform:** Linux (PowerShell Core + Wine)

---

## Quick Start

### Prerequisites
```bash
# Install PowerShell Core
sudo apt install powershell          # Debian/Ubuntu
yay -S powershell-bin                # Arch Linux

# Install Wine (for BSArch.exe)
sudo apt install wine64              # Debian/Ubuntu
sudo pacman -S wine                  # Arch Linux

# Verify installation
pwsh --version    # Should be 7.0+
wine --version    # Should be 6.0+
```

### Running the Tool
```bash
# Make launcher executable (first time only)
chmod +x run-script-archiver.sh

# Run
./run-script-archiver.sh
```

---

## Features

- **Mod Consolidation** - Combine multiple mods within categories
- **BSA Archive Creation** - Automatically create BSA archives via Wine
- **Automatic Backups** - Non-destructive with `.copied.mohidden` renaming
- **Configuration Presets** - Customizable workflow settings
- **Cross-Category Conflict Analysis** - Detect and resolve file conflicts
- **Restore Capability** - Full restoration of original files

---

## File Structure

```
Script-archiver/
├── run-script-archiver.sh           # Main launcher
├── README.md                         # This file
├── MO2_Mod_Order_Explanation.md     # Documentation on MO2 priorities
├── BSArch/
│   ├── BSArch.exe                   # Archive creation tool (runs via Wine)
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
1. Select MO2 profile
2. Choose categories to consolidate
3. Files are copied with proper directory structure
4. BSA archives created via Wine + BSArch.exe
5. ESP plugins generated
6. Original files renamed to `.copied.mohidden`
7. Backups moved to `mods-backup/`

### Workflow 2: Restore Backups
1. Select MO2 profile
2. Choose categories to restore
3. Files copied back to original locations
4. `.copied.mohidden` extension removed
5. Empty backup folders cleaned up

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

---

## Wine Integration

The tool automatically detects Linux and uses Wine for BSArch.exe:
- Unix paths are converted to Windows format (`Z:\path\to\files`)
- BSArch.exe runs transparently through Wine
- Directory structure is preserved (meshes/, sound/, textures/)
- No manual Wine commands needed

---

## Troubleshooting

### Permission denied
```bash
chmod +x run-script-archiver.sh
```

### PowerShell not found
```bash
sudo apt install powershell
```

### Wine not found
```bash
sudo apt install wine64
```

### BSArch fails to create archive
- Ensure files have proper directory structure (meshes/, sound/, etc.)
- Check that `winepath` command works: `winepath -w /tmp`
- Verify Wine can run BSArch: `wine BSArch/BSArch.exe`
- Install dependencies if needed: `winetricks vcrun2019`

### "No valid files found for packing"
- This usually means files aren't in proper subdirectories
- BSArch requires game directory structure (meshes/, textures/, sound/)
- The script now automatically preserves directory structure

---

## File Types Supported

Default file types (extensible):
- `.nif` - 3D meshes
- `.dds` - Textures
- `.kf` - Animations
- `.wav` - Audio files
- `.ogg` - Audio files
- `.lip` - Lip sync files

Edit `$FileExtensions` parameter in scripts to add more types.

---

## Performance

- **BSArch via Wine**: ~95% of native Windows performance
- **Small archives** (<500 files): 10-30 seconds
- **Medium archives** (500-1000 files): 1-2 minutes
- **Large archives** (2000+ files): 3-5 minutes

Multi-threaded processing is enabled by default (`-mt` flag).

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

Flat directory structure will cause "No valid files found for packing" error.

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
└── linux-version/    ← This tool
    └── run-script-archiver.sh
```

The tool uses relative paths to find `../mods` and `../profiles`.

---

## Advanced Usage

### Direct Script Execution
```bash
# Main compiler
pwsh -File ./scripts/1_MainCompiler.ps1

# Restore backups
pwsh -File ./scripts/2_RestoreAndRename.ps1

# With custom paths
pwsh -File ./scripts/1_MainCompiler.ps1 \
  -ModsPath "/path/to/mods" \
  -ModlistPath "/path/to/profile/modlist.txt"
```

### Custom Configuration
Edit `scripts/config-presets.json` to modify the "default" preset or create new ones.

---

## What's Different from Windows Version

| Aspect | Windows | Linux |
|--------|---------|-------|
| Launcher | `.bat` file | `.sh` file |
| BSArch | Direct execution | Via Wine (automatic) |
| Paths | Backslashes | Forward slashes |
| Preset selection | Interactive | Auto-selects first |

All features and functionality are identical.

---

## Third-Party Software

This tool includes **BSArch.exe** for creating BSA archives (runs via Wine on Linux).

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
- **Linux Port**: Community contribution (2026)

---

## Support

For MO2 priority system information, see [MO2_Mod_Order_Explanation.md](MO2_Mod_Order_Explanation.md).

For issues:
1. Verify prerequisites are installed
2. Test BSArch with Wine: `wine BSArch/BSArch.exe`
3. Check file permissions: `chmod +x run-script-archiver.sh`
4. Ensure proper directory structure in mod folders
