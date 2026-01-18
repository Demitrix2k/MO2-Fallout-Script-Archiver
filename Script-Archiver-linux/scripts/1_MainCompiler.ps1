#=======================================================================
# MO2 MOD CONSOLIDATION AND ARCHIVING SCRIPT
# Version 2.0 Linux
#
# Author: Demitrix@nexusmods.com
# Date: December 24, 2025
# Linux Port: January 18, 2026
#
# This script provides a complete workflow for consolidating multiple mods
# into organized archives with automatic backup management.
#
# The script will:
# 1. Select categories from your MO2 profile
# 2. Consolidate files from selected mods
# 3. Create BSA archives with ESP plugins (using Wine for BSArch.exe)
# 4. Manage original files (keep/delete/rename to .copied.mohidden)
# 5. Automatically backup renamed files to mods-backup folder
#
# Linux Requirements:
# - PowerShell Core (pwsh)
# - Wine (for BSArch.exe execution)
#=======================================================================

param(
    [string]$ModlistPath = "",
    [string]$ModsPath = "../mods",
    [string]$OutputPath = "compiled_mod_files",
    [string]$ArchivePath = "generated_archives",
    [string]$BSArchPath = "BSArch/BSArch.exe",
    [string[]]$FileExtensions = @(".nif", ".dds", ".kf" , ".wav" , ".ogg" , ".lip")
)

# Configuration
$SCRIPT_VERSION = "2.0-Linux"
$SEPARATOR_SUFFIX = "_separator"

# Platform detection and Wine support
$global:IsLinux = $PSVersionTable.Platform -eq 'Unix' -or $PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows
$global:UseWine = $false

# Check for Wine on Linux
if ($global:IsLinux) {
    $wineCheck = Get-Command wine -ErrorAction SilentlyContinue
    if ($wineCheck) {
        $global:UseWine = $true
        Write-Host "🐧 Linux detected - Wine will be used for BSArch.exe" -ForegroundColor Cyan
    } else {
        Write-Warning "⚠️  Wine not found. BSArch.exe requires Wine on Linux."
        Write-Warning "Install Wine: sudo apt install wine64 (Debian/Ubuntu) or equivalent"
    }
}

# Wine wrapper function for BSArch execution
function Invoke-BSArch {
    param(
        [string]$BSArchPath,
        [string[]]$Arguments
    )
    
    if ($global:UseWine) {
        # On Linux with Wine - convert Unix paths to Windows format
        # BSArch.exe expects Windows-style paths even when running under Wine
        $convertedArgs = @()
        foreach ($arg in $Arguments) {
            if ($arg -match '^-') {
                # This is a flag, keep as-is
                $convertedArgs += $arg
            } elseif ($arg -eq 'pack' -or $arg -eq 'unpack') {
                # This is a command, keep as-is
                $convertedArgs += $arg
            } else {
                # Assume this is a path - convert to Windows format using winepath
                # Remove any trailing slashes first
                $cleanPath = $arg.TrimEnd('/', '\')
                
                try {
                    $windowsPath = & winepath -w $cleanPath 2>&1 | Where-Object { $_ -notmatch '^wine:' }
                    if ($LASTEXITCODE -eq 0 -and $windowsPath) {
                        $convertedArgs += $windowsPath.Trim()
                        Write-Verbose "Converted path: $cleanPath -> $windowsPath"
                    } else {
                        # Fallback: use path as-is
                        $convertedArgs += $arg
                        Write-Verbose "Path conversion failed for: $arg, using as-is"
                    }
                } catch {
                    $convertedArgs += $arg
                    Write-Verbose "Exception converting path: $arg"
                }
            }
        }
        
        $result = & wine $BSArchPath @convertedArgs 2>&1
        return @{
            Output = $result
            ExitCode = $LASTEXITCODE
        }
    } else {
        # On Windows or without Wine
        $result = & $BSArchPath @Arguments 2>&1
        return @{
            Output = $result
            ExitCode = $LASTEXITCODE
        }
    }
}

# Global configuration variables
$global:ConfigPreset = $null
$global:ConfigPath = Join-Path $PSScriptRoot "config-presets.json"

# Configuration Management Functions
function Load-ConfigPresets {
    if (Test-Path $global:ConfigPath) {
        try {
            $configContent = Get-Content $global:ConfigPath -Raw | ConvertFrom-Json
            return $configContent
        }
        catch {
            Write-Warning "Failed to load configuration file: $_"
            return $null
        }
    } else {
        Write-Warning "Configuration file not found: $global:ConfigPath"
        return $null
    }
}

function Select-ConfigPreset {
    # Check if forced to interactive mode (from Script-archiver-run.ps1)
    if ($env:FORCE_INTERACTIVE_MODE -eq "true") {
        Write-Host ""
        Write-Host ("=" * 50) -ForegroundColor Cyan
        Write-Info "Running in Classic Interactive Mode (no presets)"
        Write-Host ("=" * 50) -ForegroundColor Cyan
        return $null
    }
    
    # Check if preset was specified via environment variable (from quick-launch script)
    if ($env:SCRIPT_ARCHIVER_PRESET) {
        $config = Load-ConfigPresets
        if ($config -and $config.presets -and $config.presets.PSObject.Properties.Name -contains $env:SCRIPT_ARCHIVER_PRESET) {
            $selectedPreset = $config.presets.($env:SCRIPT_ARCHIVER_PRESET)
            Write-Host ""
            Write-Host ("=" * 50) -ForegroundColor Cyan
            Write-Success "Using preset from quick-launch: $($selectedPreset.name)"
            Write-Info "Description: $($selectedPreset.description)"
            Write-Host ("=" * 50) -ForegroundColor Cyan
            
            # Clear the environment variable
            $env:SCRIPT_ARCHIVER_PRESET = $null
            
            return $selectedPreset
        } else {
            Write-Warning "Preset '$env:SCRIPT_ARCHIVER_PRESET' not found. Falling back to interactive selection."
            $env:SCRIPT_ARCHIVER_PRESET = $null
        }
    }
    
    $config = Load-ConfigPresets
    if (-not $config -or -not $config.presets) {
        Write-Info "No configuration presets available. Using interactive mode."
        return $null
    }
    
    # Auto-select first preset (typically "default")
    $presetNames = $config.presets.PSObject.Properties.Name
    $selectedPresetName = $presetNames[0]
    $selectedPreset = $config.presets.$selectedPresetName
    
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Success "Auto-selected preset: $($selectedPreset.name)"
    Write-Info "Description: $($selectedPreset.description)"
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    return $selectedPreset
    
    # Original interactive selection code (disabled)
    <# 
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Info "Configuration Presets Available:"
    Write-Host ""
    
    $presetNames = $config.presets.PSObject.Properties.Name
    for ($i = 0; $i -lt $presetNames.Count; $i++) {
        $presetName = $presetNames[$i]
        $preset = $config.presets.$presetName
        Write-Host ("  {0}. {1}" -f ($i + 1), $preset.name) -ForegroundColor Yellow
        Write-Host ("     {0}" -f $preset.description) -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "  0. Interactive mode (no preset)" -ForegroundColor Green
    Write-Host ""
    
    $attempts = 0
    while ($attempts -lt 3) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Warning "Attempt $attempts of 3. Please enter a valid number."
        }
        
        $selection = Read-Host "Select a preset (0-$($presetNames.Count)) [1]"
        
        if ([string]::IsNullOrWhiteSpace($selection)) {
            $selection = "1"
        }
        
        if ($selection -eq "0") {
            Write-Info "Using interactive mode"
            return $null
        }
        
        $selectionNum = 0
        if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $presetNames.Count) {
            $selectedPresetName = $presetNames[$selectionNum - 1]
            $selectedPreset = $config.presets.$selectedPresetName
            Write-Success "Using preset: $($selectedPreset.name)"
            return $selectedPreset
        } else {
            Write-Warning "Invalid selection '$selection'. Valid options: 0-$($presetNames.Count)"
        }
    }
    
    Write-Warning "Max attempts reached. Using interactive mode."
    return $null
    #>
}

function Get-ConfigValue {
    param(
        [string]$Key,
        $DefaultValue = $null
    )
    
    if ($global:ConfigPreset -and $global:ConfigPreset.settings -and $global:ConfigPreset.settings.PSObject.Properties.Name -contains $Key) {
        return $global:ConfigPreset.settings.$Key
    }
    
    return $DefaultValue
}

# Helper for selection with retry and skip option
function Get-SelectionWithRetry {
    param(
        [string]$Prompt,
        [string[]]$ValidItems,
        [string]$ItemType = "items",
        [int]$MaxAttempts = 3
    )
    
    $attempts = 0
    while ($attempts -lt $MaxAttempts) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Host ""
            Write-Info "Attempt $attempts of $MaxAttempts"
        }
        
        Write-Info "Valid options are 1-$($ValidItems.Count), 'skip' to skip this step"
        $selection = Read-Host $Prompt
        
        # Handle skip option
        if ($selection.ToLower() -eq "skip") {
            Write-Info "Skipping selection - will use default behavior"
            return @()
        }
        
        # Handle none option
        if ($selection.ToLower() -eq "none") {
            Write-Info "None selected - will use default behavior"
            return @()
        }
        
        if (-not [string]::IsNullOrWhiteSpace($selection)) {
            $selectedIndices = $selection.Split(",") | ForEach-Object { $_.Trim() }
            $validItems = @()
            $invalidSelections = @()
            
            foreach ($index in $selectedIndices) {
                if ($index -match "^\d+$") {
                    $idx = [int]$index - 1
                    if ($idx -ge 0 -and $idx -lt $ValidItems.Count) {
                        $validItems += $ValidItems[$idx]
                    } else {
                        $invalidSelections += $index
                    }
                } else {
                    $invalidSelections += $index
                }
            }
            
            # Show warnings for invalid selections
            if ($invalidSelections.Count -gt 0) {
                Write-Warning "Invalid selections: $($invalidSelections -join ', ')"
                Write-Info "Valid range: 1-$($ValidItems.Count)"
                continue
            }
            
            if ($validItems.Count -gt 0) {
                return $validItems
            }
        }
        
        Write-Warning "Please enter valid $ItemType numbers (1-$($ValidItems.Count)), 'skip', or 'none'"
    }
    
    Write-Warning "Max attempts reached. Using default behavior (none selected)"
    return @()
}

# Enhanced input validation function for numeric choices
function Get-ValidatedChoice {
    param(
        [string]$Prompt,
        [int[]]$ValidOptions,
        [int]$DefaultValue = $null,
        [string]$ConfigKey = $null,
        [int]$MaxAttempts = 5
    )
    
    # Check if we have a preset value for this setting
    if ($ConfigKey -and $global:ConfigPreset) {
        $presetValue = Get-ConfigValue -Key $ConfigKey
        if ($null -ne $presetValue) {
            Write-Host "$Prompt [$($DefaultValue -or 'no default')]: " -NoNewline
            Write-Host $presetValue -ForegroundColor Cyan -NoNewline
            Write-Host " (from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
            return $presetValue
        }
    }
    
    $attempts = 0
    while ($attempts -lt $MaxAttempts) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Host ""
            Write-Warning "Attempt $attempts of $MaxAttempts"
            Write-Info "Valid options: $($ValidOptions -join ', ')"
        }
        
        $fullPrompt = if ($DefaultValue) { 
            "$Prompt [$DefaultValue]: " 
        } else { 
            "${Prompt}: " 
        }
        
        $response = Read-Host $fullPrompt
        
        # Handle empty input (use default)
        if ([string]::IsNullOrWhiteSpace($response) -and $DefaultValue) {
            return $DefaultValue
        }
        
        # Try to parse as integer
        $parsedValue = 0
        if ([int]::TryParse($response, [ref]$parsedValue) -and $ValidOptions -contains $parsedValue) {
            return $parsedValue
        }
        
        Write-Warning "Invalid input '$response'. Please enter one of: $($ValidOptions -join ', ')"
        if ($DefaultValue) {
            Write-Info "Or press Enter for default: $DefaultValue"
        }
    }
    
    if ($DefaultValue) {
        Write-Warning "Max attempts reached. Using default value: $DefaultValue"
        return $DefaultValue
    } else {
        Write-Warning "Max attempts reached. Using first valid option: $($ValidOptions[0])"
        return $ValidOptions[0]
    }
}

# Enhanced profile selection with retry logic
function Get-ValidatedProfileSelection {
    param(
        [array]$Profiles,
        [int]$MaxAttempts = 5
    )
    
    $attempts = 0
    while ($attempts -lt $MaxAttempts) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Host ""
            Write-Warning "Attempt $attempts of $MaxAttempts"
            Write-Info "Valid options: 1-$($Profiles.Count)"
        }
        
        $selection = Read-Host "Select profile number (1-$($Profiles.Count))"
        
        # Handle empty input
        if ([string]::IsNullOrWhiteSpace($selection)) {
            Write-Warning "Please enter a profile number"
            continue
        }
        
        # Try to parse and validate
        if ($selection -match "^\d+$") {
            $idx = [int]$selection - 1
            if ($idx -ge 0 -and $idx -lt $Profiles.Count) {
                $selectedProfile = $Profiles[$idx]
                Write-Success "Selected profile: '$($selectedProfile.Name)'"
                return $selectedProfile.ModlistPath
            } else {
                Write-Warning "Invalid profile number. Please select between 1 and $($Profiles.Count)"
            }
        } else {
            Write-Warning "Please enter a valid number"
        }
    }
    
    Write-Warning "Max attempts reached. Cannot continue without a valid profile selection."
    return $null
}

# Original function with enhanced retry logic
function Get-SelectionWithRetry {
    param(
        [string]$Prompt,
        [string[]]$ValidItems,
        [string]$ItemType = "items",
        [int]$MaxAttempts = 5  # Increased from 3
    )
    
    $attempts = 0
    while ($attempts -lt $MaxAttempts) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Host ""
            Write-Info "Attempt $attempts of $MaxAttempts"
        }
        
        Write-Info "Valid options are 1-$($ValidItems.Count), 'skip' to skip this step"
        $selection = Read-Host $Prompt
        
        # Handle skip option
        if ($selection.ToLower() -eq "skip") {
            Write-Info "Skipping selection - will use default behavior"
            return @()
        }
        
        # Handle none option
        if ($selection.ToLower() -eq "none") {
            Write-Info "None selected - will use default behavior"
            return @()
        }
        
        if (-not [string]::IsNullOrWhiteSpace($selection)) {
            $selectedIndices = $selection.Split(",") | ForEach-Object { $_.Trim() }
            $validItems = @()
            $invalidSelections = @()
            
            foreach ($index in $selectedIndices) {
                if ($index -match "^\d+$") {
                    $idx = [int]$index - 1
                    if ($idx -ge 0 -and $idx -lt $ValidItems.Count) {
                        $validItems += $ValidItems[$idx]
                    } else {
                        $invalidSelections += $index
                    }
                } else {
                    $invalidSelections += $index
                }
            }
            
            # Show warnings for invalid selections
            if ($invalidSelections.Count -gt 0) {
                Write-Warning "Invalid selections: $($invalidSelections -join ', ')"
                Write-Info "Valid range: 1-$($ValidItems.Count)"
                
                if ($attempts -lt $MaxAttempts) {
                    Write-Info "Please try again or enter 'skip' to skip this step"
                    continue
                } else {
                    Write-Warning "Maximum attempts reached - using default behavior"
                    return @()
                }
            }
            
            if ($validItems.Count -gt 0) {
                return $validItems
            } else {
                Write-Warning "No valid $ItemType selected"
                if ($attempts -lt $MaxAttempts) {
                    Write-Info "Please try again or enter 'skip' to skip this step"
                    continue
                } else {
                    Write-Warning "Maximum attempts reached - using default behavior"
                    return @()
                }
            }
        } else {
            Write-Warning "Empty input"
            if ($attempts -lt $MaxAttempts) {
                Write-Info "Please try again or enter 'skip' to skip this step"
                continue
            } else {
                Write-Warning "Maximum attempts reached - using default behavior"
                return @()
            }
        }
    }
    
    return @()
}

# Color output functions
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Header { param([string]$Message) Write-Host $Message -ForegroundColor Magenta }

# Global variables to track processed files
$global:ProcessedFiles = @()
$global:CopiedFiles = @()

function Get-AvailableProfiles {
    param([string]$ProfilesBasePath = "..\profiles")
    
    if (-not (Test-Path $ProfilesBasePath)) {
        Write-Warning "Profiles directory not found: $ProfilesBasePath"
        return @()
    }
    
    $profiles = @()
    $profileDirs = Get-ChildItem -Path $ProfilesBasePath -Directory -ErrorAction SilentlyContinue
    
    foreach ($dir in $profileDirs) {
        $modlistPath = Join-Path $dir.FullName "modlist.txt"
        if (Test-Path $modlistPath) {
            $profileInfo = @{
                Name = $dir.Name
                Path = $dir.FullName
                ModlistPath = $modlistPath
            }
            $profiles += $profileInfo
            Write-Host "  Found profile: '$($dir.Name)' at $($dir.FullName)" -ForegroundColor DarkGray
        } else {
            Write-Host "  Skipping directory (no modlist.txt): '$($dir.Name)'" -ForegroundColor DarkRed
        }
    }
    
    # Force return as array to prevent PowerShell from unrolling hashtable properties
    return ,$profiles
}

function Select-Profile {
    param([string]$ProfilesBasePath = "..\profiles")
    
    Write-Info "Scanning for available MO2 profiles..."
    $profiles = Get-AvailableProfiles -ProfilesBasePath $ProfilesBasePath
    
    if ($profiles.Count -eq 0) {
        Write-Error "No valid profiles found in $ProfilesBasePath"
        Write-Info "Make sure you're running this script from the correct directory"
        return $null
    }
    
    if ($profiles.Count -eq 1) {
        Write-Success "Found 1 profile: '$($profiles[0].Name)'"
        $useProfile = Get-UserConfirmation "Use profile '$($profiles[0].Name)'?" "y"
        if ($useProfile) {
            return $profiles[0].ModlistPath
        } else {
            return $null
        }
    }
    
    Write-Success "Found $($profiles.Count) available profiles:"
    Write-Host ""
    
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  $($i + 1). '$($profiles[$i].Name)'" -ForegroundColor White
    }
    
    Write-Host ""
    $selectedModlistPath = Get-ValidatedProfileSelection -Profiles $profiles
    
    if (-not $selectedModlistPath) {
        Write-Error "No valid profile selected. Exiting."
        return $null
    }
    
    return $selectedModlistPath
}

function Show-Header {
    Clear-Host
    Write-Header "=== MOD ORGANIZER 2 INTERACTIVE CONSOLIDATION SYSTEM ==="
    Write-Header "Version $SCRIPT_VERSION - Complete Workflow Manager"
    Write-Host ""
}

function Get-UserConfirmation {
    param(
        [string]$Question,
        [string]$DefaultAnswer = "n",
        [string]$ConfigKey = $null
    )
    
    # Check if we have a preset value for this setting
    if ($ConfigKey -and $global:ConfigPreset) {
        $presetValue = Get-ConfigValue -Key $ConfigKey
        if ($null -ne $presetValue) {
            $answer = if ($presetValue) { "y" } else { "n" }
            Write-Host "$Question (y/n) [$DefaultAnswer]: " -NoNewline
            Write-Host $answer -ForegroundColor Cyan -NoNewline
            Write-Host " (from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
            return $presetValue
        }
    }
    
    $attempts = 0
    while ($attempts -lt 3) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Warning "Attempt $attempts of 3. Please enter 'y' or 'n'."
        }
        
        $prompt = "$Question (y/n) [$DefaultAnswer]: "
        $response = Read-Host $prompt
        
        if ([string]::IsNullOrWhiteSpace($response)) {
            $response = $DefaultAnswer
        }
        
        if ($response.ToLower() -match "^(y|yes|n|no)$") {
            return $response.ToLower() -match "^(y|yes)$"
        } else {
            Write-Warning "Invalid input '$response'. Please enter 'y' or 'n'."
        }
    }
    
    Write-Warning "Max attempts reached. Using default: $DefaultAnswer"
    return $DefaultAnswer.ToLower() -eq "y"
}

function Get-UserChoice {
    param(
        [string]$Question,
        [string]$DefaultAnswer = "",
        [string]$ConfigKey = $null
    )
    
    # Check if we have a preset value for this setting
    if ($ConfigKey -and $global:ConfigPreset) {
        $presetValue = Get-ConfigValue -Key $ConfigKey
        if ($null -ne $presetValue) {
            Write-Host "$Question [$DefaultAnswer]: " -NoNewline
            Write-Host $presetValue -ForegroundColor Cyan -NoNewline
            Write-Host " (from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
            return $presetValue
        }
    }
    
    $prompt = if ($DefaultAnswer) { "$Question [$DefaultAnswer]`: " } else { "$Question`: " }
    $response = Read-Host $prompt
    
    if ([string]::IsNullOrWhiteSpace($response) -and $DefaultAnswer) {
        $response = $DefaultAnswer
    }
    
    return $response
}

function Debug-ModlistStructure {
    param([string]$ModlistPath)
    
    Write-Info "Debugging modlist structure..."
    $modlistContent = Get-Content -Path $ModlistPath -Encoding UTF8
    
    Write-Host "First 20 lines of modlist:" -ForegroundColor Yellow
    for ($i = 0; $i -lt [Math]::Min(20, $modlistContent.Length); $i++) {
        $line = $modlistContent[$i].Trim()
        if ($line.EndsWith($SEPARATOR_SUFFIX)) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Magenta
        } elseif ($line.StartsWith("+")) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Green
        } elseif ($line.StartsWith("-")) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Red
        } else {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Gray
        }
    }
    
    Write-Host "`nLast 20 lines of modlist:" -ForegroundColor Yellow
    $startIndex = [Math]::Max(0, $modlistContent.Length - 20)
    for ($i = $startIndex; $i -lt $modlistContent.Length; $i++) {
        $line = $modlistContent[$i].Trim()
        if ($line.EndsWith($SEPARATOR_SUFFIX)) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Magenta
        } elseif ($line.StartsWith("+")) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Green
        } elseif ($line.StartsWith("-")) {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Red
        } else {
            Write-Host "  Line $($i+1): $line" -ForegroundColor Gray
        }
    }
}

function Get-AvailableCategories {
    param([string]$ModlistPath)
    
    Write-Info "Scanning modlist for available categories..."
    
    if (-not (Test-Path $ModlistPath)) {
        Write-Error "Modlist file not found: $ModlistPath"
        return @()
    }
    
    $modlistContent = Get-Content -Path $ModlistPath -Encoding UTF8
    $categories = @()
    
    foreach ($line in $modlistContent) {
        $line = $line.Trim()
        
        if ($line.StartsWith("-") -and $line.EndsWith($SEPARATOR_SUFFIX)) {
            $categoryName = $line.Substring(1, $line.Length - 1 - $SEPARATOR_SUFFIX.Length)
            
            if ($categoryName -ne "" -and $categoryName -notmatch "^(ML |Viva New Vegas|Base |Extended )") {
                $categories += $categoryName
            }
        }
    }
    
    # Reverse the array to match MO2's bottom-to-top load order
    # This ensures categories are displayed in the correct priority order (high priority first)
    [array]::Reverse($categories)
    
    Write-Success "Found $($categories.Count) available categories"
    return $categories
}

function Show-Categories {
    param([string[]]$Categories)
    
    Write-Info "Available Categories:"
    Write-Host ("=" * 30) -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        Write-Host "  $($i + 1). $($Categories[$i])" -ForegroundColor White
    }
    
    Write-Host "  $($Categories.Count + 1). ALL CATEGORIES" -ForegroundColor Red
    Write-Host ""
}

function Get-CategorySelection {
    param([string[]]$Categories)
    
    $attempts = 0
    while ($attempts -lt 3) {
        $attempts++
        
        Show-Categories -Categories $Categories

        Write-Info "Category Selection Options:"
        Write-Host "- Single category: Enter number (e.g., 1)"
        Write-Host "- Multiple categories: Enter numbers separated by commas (e.g., 1,3,5)"
        Write-Host "- All categories: Enter $($Categories.Count + 1) or 'all'"
        Write-Host "- Cancel and exit: Enter 'n'"
        Write-Host ""
        
        if ($attempts -gt 1) {
            Write-Warning "Attempt $attempts of 3. Please make a valid selection."
        }

        $selection = Read-Host "Select categories"

        # Handle null or empty input
        if ([string]::IsNullOrWhiteSpace($selection)) {
            Write-Warning "No selection made. Please try again."
            continue
        }

        if ($selection.ToLower() -eq "n") {
            Write-Info "Operation cancelled by user."
            exit 0
        }

        if ($selection.ToLower() -eq "all" -or $selection -eq ($Categories.Count + 1).ToString()) {
            return $Categories
        }

        $selectedCategories = @()
        $indices = $selection.Split(",") | ForEach-Object { $_.Trim() }
        $hasValidSelection = $false

        foreach ($index in $indices) {
            if ($index -match "^\d+$") {
                $idx = [int]$index - 1
                if ($idx -ge 0 -and $idx -lt $Categories.Count) {
                    $selectedCategories += $Categories[$idx]
                    $hasValidSelection = $true
                } else {
                    Write-Warning "Invalid category number: $index"
                }
            } else {
                Write-Warning "Invalid input: $index"
            }
        }

        if ($hasValidSelection) {
            return $selectedCategories
        }
        
        Write-Warning "No valid categories selected. Please try again."
    }
    
    Write-Warning "Max attempts reached. Exiting."
    exit 1
}

function Get-ModsInCategory {
    param(
        [string]$CategoryName,
        [string]$ModlistPath
    )
    
    # Make sure ModlistPath is a file, not a directory
    if ((Test-Path -Path $ModlistPath -PathType Container)) {
        Write-Error "Invalid modlist path: $ModlistPath is a directory, not a file"
        return @()
    }
    
    $modlistContent = Get-Content -Path $ModlistPath -Encoding UTF8
    $categoryStart = "-$CategoryName$SEPARATOR_SUFFIX"
    $mods = @()
    
    Write-Info "  Looking for category separator: $CategoryName"
    
    # Find the category separator first
    $categoryLineIndex = -1
    for ($i = 0; $i -lt $modlistContent.Length; $i++) {
        $line = $modlistContent[$i].Trim()
        if ($line -eq $categoryStart) {
            $categoryLineIndex = $i
            Write-Info "  Found category start: $CategoryName at line $($i + 1)"
            break
        }
    }
    
    if ($categoryLineIndex -eq -1) {
        Write-Warning "  Category '$CategoryName' not found in modlist"
        return $mods
    }
    
    # Since MO2 is bottom-to-top, mods ABOVE the separator belong to this category
    # We need to go backwards from the separator until we hit another separator
    
    for ($i = $categoryLineIndex - 1; $i -ge 0; $i--) {
        $line = $modlistContent[$i].Trim()
        
        # Stop if we hit another separator (going backwards)
        if ($line.StartsWith("-") -and $line.EndsWith($SEPARATOR_SUFFIX)) {
            Write-Info "  Found previous category separator at line $($i + 1): $line"
            break
        }
        
        # Collect enabled mods
        if ($line.StartsWith("+")) {
            $modName = $line.Substring(1).Trim()
            if ($modName -ne "") {
                # Skip mods with [skip] in their name
                if ($modName -match "\[skip\]") {
                    Write-Host "    Skipping mod marked with [skip]: $modName" -ForegroundColor DarkGray
                } else {
                    $mods += $modName
                    Write-Host "    Found enabled mod: $modName" -ForegroundColor Green
                }
            }
        } elseif ($line.StartsWith("-") -and -not $line.EndsWith($SEPARATOR_SUFFIX)) {
            # Disabled mod
            $modName = $line.Substring(1).Trim()
            Write-Host "    Skipping disabled mod: $modName" -ForegroundColor DarkGray
        }
    }
    
    # Since we collected mods in reverse order (high priority to low priority),
    # we need to reverse the list so we copy from low priority to high priority
    # This ensures high priority mods override low priority mods
    # DON'T REVERSE - we want to keep the order as: low priority first, high priority last
    # [array]::Reverse($mods) # REMOVED - this was causing incorrect load order
    
    Write-Info "  Total mods found in category: ${CategoryName}: $($mods.Count)"
    Write-Info "  Processing order: Low priority → High priority (correct for file overwriting)"
    return $mods
}

function Find-TargetFiles {
    param(
        [string]$ModPath,
        [string[]]$FileExtensions
    )
    
    $files = @()
    
    if (-not (Test-Path -LiteralPath $ModPath)) {
        return $files
    }
    
    foreach ($extension in $FileExtensions) {
        try {
            # Ensure the extension starts with a dot
            if (-not $extension.StartsWith(".")) {
                $extension = ".$extension"
            }
            
            # Use -Filter for better performance and accuracy
            $foundFiles = Get-ChildItem -LiteralPath $ModPath -Recurse -File -Filter "*$extension" -ErrorAction SilentlyContinue
            
            foreach ($file in $foundFiles) {
                # Double-check the extension matches exactly (case-insensitive)
                if ($file.Extension.ToLower() -eq $extension.ToLower() -and $file.FullName -notlike "*mohidden*") {
                    $files += $file
                }
            }
        }
        catch {
            # Handle any path issues silently
            continue
        }
    }
    
    return $files
}

function Get-RelativePathFromMod {
    param(
        [string]$FullPath,
        [string]$ModPath
    )
    
    # Convert ModPath to absolute path for proper comparison
    $absoluteModPath = Resolve-Path -LiteralPath $ModPath -ErrorAction SilentlyContinue
    if (-not $absoluteModPath) {
        # Fallback: just use the filename
        return Split-Path $FullPath -Leaf
    }
    
    $absoluteModPath = $absoluteModPath.Path
    
    # Ensure ModPath ends with a path separator for proper path trimming
    # Use platform-appropriate separator
    $pathSeparator = [System.IO.Path]::DirectorySeparatorChar
    if (-not $absoluteModPath.EndsWith($pathSeparator)) {
        $absoluteModPath = $absoluteModPath + $pathSeparator
    }
    
    # Check if the full path actually starts with the mod path
    if (-not $FullPath.StartsWith($absoluteModPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        # Fallback: just use the filename
        return Split-Path $FullPath -Leaf
    }
    
    $relativePath = $FullPath.Substring($absoluteModPath.Length)
    return $relativePath
}

function Get-ModPriorityOrder {
    param([string]$ModlistPath)
    
    $modlistContent = Get-Content -Path $ModlistPath -Encoding UTF8
    $modPriorities = @{}
    $priority = 0
    
    # Process from bottom to top (MO2's load order)
    for ($i = $modlistContent.Length - 1; $i -ge 0; $i--) {
        $line = $modlistContent[$i].Trim()
        
        # Only enabled mods get priority
        if ($line.StartsWith("+")) {
            $modName = $line.Substring(1).Trim()
            if ($modName -ne "") {
                $modPriorities[$modName] = $priority
                $priority++
            }
        }
    }
    
    return $modPriorities
}

function Get-AllModsAfterCategory {
    param(
        [string]$CategoryName,
        [string]$ModlistPath
    )
    
    $modlistContent = Get-Content -Path $ModlistPath -Encoding UTF8
    $categoryStart = "-$CategoryName$SEPARATOR_SUFFIX"
    $modsAfterCategory = @()
    
    # Find the category separator
    $categoryLineIndex = -1
    for ($i = 0; $i -lt $modlistContent.Length; $i++) {
        $line = $modlistContent[$i].Trim()
        if ($line -eq $categoryStart) {
            $categoryLineIndex = $i
            break
        }
    }
    
    if ($categoryLineIndex -eq -1) {
        return $modsAfterCategory
    }
    
    # Collect all enabled mods ABOVE the separator (higher priority in MO2's bottom-to-top order)
    # In modlist.txt, line 0 is top = highest priority, bottom = lowest priority
    for ($i = 0; $i -lt $categoryLineIndex; $i++) {
        $line = $modlistContent[$i].Trim()
        
        # Collect enabled mods regardless of separators
        if ($line.StartsWith("+")) {
            $modName = $line.Substring(1).Trim()
            if ($modName -ne "") {
                $modsAfterCategory += $modName
            }
        }
    }
    
    return $modsAfterCategory
}

function Test-CrossCategoryConflicts {
    param(
        [string[]]$SelectedCategories,
        [string]$ModsPath,
        [string]$ModlistPath,
        [string[]]$FileExtensions,
        [hashtable]$SelectedModsByCategory = @{}
    )
    
    Write-Info "Analyzing cross-category file conflicts..."
    
    $modPriorities = Get-ModPriorityOrder -ModlistPath $ModlistPath
    $conflictReport = @{
        HasConflicts = $false
        ConflictsByCategory = @{}
        TotalLosingFiles = 0
    }
    
    foreach ($category in $SelectedCategories) {
        Write-Info "  Checking conflicts for category: $category"
        
        # Get mods in this category - use selected mods if available
        if ($SelectedModsByCategory.Count -gt 0 -and $SelectedModsByCategory.ContainsKey($category)) {
            $categoryMods = $SelectedModsByCategory[$category]
            Write-Info "    Using selected mods for conflict analysis ($($categoryMods.Count) mods)"
        } else {
            $categoryMods = Get-ModsInCategory -CategoryName $category -ModlistPath $ModlistPath
            Write-Info "    Using all mods for conflict analysis ($($categoryMods.Count) mods)"
        }
        
        # Get all mods that load after this category (higher priority)
        $allHigherPriorityMods = Get-AllModsAfterCategory -CategoryName $category -ModlistPath $ModlistPath
        
        # If we're using mod selection, filter higher priority mods to only include selected ones
        if ($SelectedModsByCategory.Count -gt 0) {
            $higherPriorityMods = @()
            foreach ($modName in $allHigherPriorityMods) {
                # Check if this mod is in any of the selected categories
                $isSelected = $false
                foreach ($otherCategory in $SelectedCategories) {
                    if ($otherCategory -ne $category -and $SelectedModsByCategory.ContainsKey($otherCategory)) {
                        if ($SelectedModsByCategory[$otherCategory] -contains $modName) {
                            $isSelected = $true
                            break
                        }
                    }
                }
                if ($isSelected) {
                    $higherPriorityMods += $modName
                }
            }
            Write-Info "    Filtered to $($higherPriorityMods.Count) selected higher priority mods (from $($allHigherPriorityMods.Count) total)"
        } else {
            $higherPriorityMods = $allHigherPriorityMods
            Write-Info "    Using all $($higherPriorityMods.Count) higher priority mods (no mod selection active)"
        }
        
        if ($higherPriorityMods.Count -eq 0) {
            Write-Info "    No higher priority mods found - no conflicts possible"
            continue
        }
        
        Write-Info "    Found $($higherPriorityMods.Count) higher priority mods to check against"
        
        # Build file registry for higher priority mods
        $higherPriorityFiles = @{}
        foreach ($modName in $higherPriorityMods) {
            # Skip if this mod is in the current category (to avoid self-conflicts)
            if ($categoryMods -contains $modName) {
                continue
            }
            
            $modPath = Join-Path $ModsPath $modName
            if (-not (Test-Path -LiteralPath $modPath)) { continue }
            
            $targetFiles = Find-TargetFiles -ModPath $modPath -FileExtensions $FileExtensions
            foreach ($file in $targetFiles) {
                $relativePath = Get-RelativePathFromMod -FullPath $file.FullName -ModPath $modPath
                $relativePath = $relativePath.Replace('\', '/').ToLower()  # Normalize path
                
                if (-not $higherPriorityFiles.ContainsKey($relativePath)) {
                    $higherPriorityFiles[$relativePath] = @()
                }
                
                $higherPriorityFiles[$relativePath] += @{
                    ModName = $modName
                    Priority = $modPriorities[$modName]
                    FullPath = $file.FullName
                }
            }
        }
        
        # Check category mods for conflicts
        $categoryConflicts = @()
        foreach ($modName in $categoryMods) {
            $modPath = Join-Path $ModsPath $modName
            if (-not (Test-Path -LiteralPath $modPath)) { continue }
            
            $targetFiles = Find-TargetFiles -ModPath $modPath -FileExtensions $FileExtensions
            foreach ($file in $targetFiles) {
                $relativePath = Get-RelativePathFromMod -FullPath $file.FullName -ModPath $modPath
                $normalizedPath = $relativePath.Replace('\', '/').ToLower()  # Normalize path
                
                # Check if this file conflicts with higher priority mods
                if ($higherPriorityFiles.ContainsKey($normalizedPath)) {
                    $conflictingMods = $higherPriorityFiles[$normalizedPath]
                    
                    # Find the highest priority conflicting mod
                    $winner = $conflictingMods | Sort-Object Priority -Descending | Select-Object -First 1
                    
                    # Debug: Ensure winner has valid data
                    if (-not $winner -or [string]::IsNullOrEmpty($winner.ModName)) {
                        Write-Warning "    Debug: Invalid winner for file $normalizedPath"
                        continue
                    }
                    
                    $categoryConflicts += @{
                        FilePath = $relativePath
                        LosingMod = $modName
                        LosingModPriority = $modPriorities[$modName]
                        WinningMod = $winner.ModName
                        WinningModPriority = $winner.Priority
                        FullPath = $file.FullName
                    }
                }
            }
        }
        
        if ($categoryConflicts.Count -gt 0) {
            $conflictReport.HasConflicts = $true
            $conflictReport.ConflictsByCategory[$category] = $categoryConflicts
            $conflictReport.TotalLosingFiles += $categoryConflicts.Count
            
            Write-Warning "    Found $($categoryConflicts.Count) losing conflicts in category: $category"
        } else {
            Write-Success "    No losing conflicts found in category '$category'"
        }
    }
    
    return $conflictReport
}

function Show-CrossCategoryConflictReport {
    param([hashtable]$ConflictReport)
    
    if (-not $ConflictReport.HasConflicts) {
        Write-Success "`n✅ No cross-category conflicts detected!"
        Write-Info "All files in selected categories will be the winners in the final load order."
        return $false
    }
    
    Write-Warning "`n⚠️  CROSS-CATEGORY CONFLICTS DETECTED!"
    Write-Info "Total files that would lose conflicts: $($ConflictReport.TotalLosingFiles)"
    Write-Host ""
    
    foreach ($category in $ConflictReport.ConflictsByCategory.Keys) {
        $conflicts = $ConflictReport.ConflictsByCategory[$category]
        Write-Host "Category: $category ($($conflicts.Count) losing files)" -ForegroundColor Yellow
        
        # Show first few conflicts as examples
        $displayCount = [Math]::Min(10, $conflicts.Count)
        for ($i = 0; $i -lt $displayCount; $i++) {
            $conflict = $conflicts[$i]
            Write-Host "  📄 $($conflict.FilePath)" -ForegroundColor Gray
            Write-Host "     ❌ Will be overridden by: $($conflict.WinningMod)" -ForegroundColor Red
            Write-Host "     📂 From mod: $($conflict.LosingMod)" -ForegroundColor DarkGray
            Write-Host ""
        }
        
        if ($conflicts.Count -gt $displayCount) {
            Write-Host "     ... and $($conflicts.Count - $displayCount) more files" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    
    Write-Warning "These files would be compiled but immediately overridden by higher priority mods!"
    return $true
}

function Copy-FilesToCompilation {
    param(
        [string[]]$Categories,
        [string]$ModsPath,
        [string]$OutputPath,
        [string]$ModlistPath,
        [string[]]$FileExtensions,
        [bool]$DryRun,
        [hashtable]$ConflictReport = @{},
        [bool]$SkipLosingFiles = $false,
        [hashtable]$SelectedModsByCategory = @{}
    )
    
    $allStats = @{
        TotalMods = 0
        TotalFiles = 0
        TotalSize = 0
        CategoryStats = @{}
    }
    
    # Pre-calculate total files for progress tracking
    Write-Info "Calculating total files to process..."
    $totalFilesToProcess = 0
    $processedFiles = 0
    
    foreach ($category in $Categories) {
        # Use selected mods if available, otherwise get all mods
        if ($SelectedModsByCategory.Count -gt 0 -and $SelectedModsByCategory.ContainsKey($category)) {
            $mods = $SelectedModsByCategory[$category]
        } else {
            $mods = Get-ModsInCategory -CategoryName $category -ModlistPath $ModlistPath
        }
        foreach ($modName in $mods) {
            $modPath = Join-Path $ModsPath $modName
            if (Test-Path -LiteralPath $modPath) {
                $targetFiles = Find-TargetFiles -ModPath $modPath -FileExtensions $FileExtensions
                $totalFilesToProcess += $targetFiles.Count
            }
        }
    }
    
    Write-Info "Found $totalFilesToProcess total files to process"
    
    # Show progress info for large file counts
    $showProgressBar = $totalFilesToProcess -gt 20
    $progressParams = @{
        Activity = "Copying files to compilation folders"
        Status = "0% Complete"
        PercentComplete = 0
    }
    
    # Performance optimization: Calculate progress update interval for main processing
    $progressUpdateInterval = [Math]::Max(1, [Math]::Floor($totalFilesToProcess / 100)) # Update progress at most 100 times
    $lastProgressUpdate = 0
    
    foreach ($category in $Categories) {
        Write-Info "`nProcessing category: $category"
        Write-Host ("=" * 50) -ForegroundColor Yellow
        
        # Use selected mods if available, otherwise get all mods
        if ($SelectedModsByCategory.Count -gt 0 -and $SelectedModsByCategory.ContainsKey($category)) {
            $mods = $SelectedModsByCategory[$category]
            Write-Info "Using selected mods for category '$category'"
        } else {
            $mods = Get-ModsInCategory -CategoryName $category -ModlistPath $ModlistPath
            Write-Info "Using all mods for category '$category' (no selection made)"
        }
        
        if ($mods.Count -eq 0) {
            Write-Warning "No mods found in category '$category'"
            continue
        }
        
        Write-Success "Found $($mods.Count) mods in category '$category'"
        
        $compilationPath = Join-Path $OutputPath "$category`_Compiled"
        
        if (-not $DryRun) {
            if (Test-Path $compilationPath) {
                Remove-Item -Path $compilationPath -Recurse -Force
            }
            New-Item -Path $compilationPath -ItemType Directory -Force | Out-Null
        }
        
        $categoryFiles = 0
        $categorySize = 0
        $prevTotalMods = $allStats.TotalMods
        
        foreach ($modName in $mods) {
            $modPath = Join-Path $ModsPath $modName
            
            # Use -LiteralPath to handle special characters properly
            if (-not (Test-Path -LiteralPath $modPath)) {
                Write-Warning "  Mod directory not found: $modName (skipping)"
                continue
            }
            
            $targetFiles = Find-TargetFiles -ModPath $modPath -FileExtensions $FileExtensions
            
            if ($targetFiles.Count -eq 0) {
                continue
            }
            
            Write-Info "  Processing mod: $modName ($($targetFiles.Count) files)"
            
            # Debug: Show file extensions being copied (only for verbose mode or very small file counts)
            if ($targetFiles.Count -gt 0 -and $targetFiles.Count -le 50) {
                $extensionCounts = $targetFiles | Group-Object Extension | ForEach-Object { "$($_.Count) $($_.Name)" }
                Write-Host "    Extensions: $($extensionCounts -join ', ')" -ForegroundColor DarkGreen
            } elseif ($targetFiles.Count -gt 50) {
                Write-Host "    Extensions: $($targetFiles.Count) files (details skipped for performance)" -ForegroundColor DarkGreen
            }
            
            foreach ($file in $targetFiles) {
                $relativePath = Get-RelativePathFromMod -FullPath $file.FullName -ModPath $modPath
                
                # Check for conflicts first
                $matchingConflict = $null
                if ($ConflictReport.ContainsKey('ConflictsByCategory') -and $ConflictReport.ConflictsByCategory.ContainsKey($category)) {
                    $categoryConflicts = $ConflictReport.ConflictsByCategory[$category]
                    $matchingConflict = $categoryConflicts | Where-Object { 
                        $_.LosingMod -eq $modName -and 
                        $_.FilePath -eq $relativePath 
                    }
                }
                
                # Handle deletion and renaming of losing files if requested
                if ($matchingConflict) {
                    if ($ConflictReport.ContainsKey('DeleteLosingFiles') -and $ConflictReport.DeleteLosingFiles) {
                        if (-not $DryRun) {
                            try {
                                Remove-Item -Path $file.FullName -Force
                                # Only show individual deletes for small operations to reduce console spam
                                if ($totalFilesToProcess -le 100) {
                                    Write-Host "    🗑️  Deleted losing file: $relativePath" -ForegroundColor Red
                                }
                            } catch {
                                Write-Warning "    ❌ Failed to delete: $relativePath - $_"
                            }
                        } else {
                            # Always show dry run output
                            Write-Host "    🗑️  [DRY RUN] Would delete: $relativePath" -ForegroundColor Red
                        }
                        continue
                    }
                    
                    if ($ConflictReport.ContainsKey('RenameLosingFiles') -and $ConflictReport.RenameLosingFiles) {
                        $newFileName = "$($file.FullName).copied.mohidden"
                        if (-not $DryRun) {
                            try {
                                Move-Item -Path $file.FullName -Destination $newFileName -Force
                                # Only show individual renames for small operations to reduce console spam
                                if ($totalFilesToProcess -le 100) {
                                    Write-Host "    📝 Renamed losing file: $relativePath → $($file.Name).copied.mohidden" -ForegroundColor Magenta
                                }
                            } catch {
                                Write-Warning "    ❌ Failed to rename: $relativePath - $_"
                            }
                        } else {
                            # Always show dry run output
                            Write-Host "    📝 [DRY RUN] Would rename: $relativePath → $($file.Name).copied.mohidden" -ForegroundColor Magenta
                        }
                        continue
                    }
                }
                
                # Check if we should skip this file due to conflicts
                $shouldSkipFile = $false
                $conflictReason = ""
                
                if ($SkipLosingFiles -and $matchingConflict) {
                    # Check if this category is excluded from skipping
                    $categoryExcluded = $ConflictReport.ContainsKey('CategoriesExcludedFromSkipping') -and 
                                      ($ConflictReport.CategoriesExcludedFromSkipping -contains $category)
                    
                    # Check if this mod is excluded from skipping
                    $modExcluded = $ConflictReport.ContainsKey('ModsExcludedFromSkipping') -and 
                                 ($ConflictReport.ModsExcludedFromSkipping -contains $modName)
                    
                    if (-not $categoryExcluded -and -not $modExcluded) {
                        $shouldSkipFile = $true
                        $conflictReason = "loses to $($matchingConflict.WinningMod)"
                    } else {
                        if ($categoryExcluded) {
                            $conflictReason = "category excluded from skipping"
                        } elseif ($modExcluded) {
                            $conflictReason = "mod excluded from skipping"
                        }
                        Write-Host "    ⚠️  Copying losing file: $relativePath ($conflictReason)" -ForegroundColor Yellow
                    }
                }
                
                if ($shouldSkipFile) {
                    Write-Host "    ⏭️  Skipping: $relativePath ($conflictReason)" -ForegroundColor DarkYellow
                    continue
                }
                
                $destinationPath = Join-Path $compilationPath $relativePath
                $destinationDir = Split-Path $destinationPath -Parent
                
                if (-not $DryRun) {
                    if (-not (Test-Path $destinationDir)) {
                        New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -Path $file.FullName -Destination $destinationPath -Force
                    
                    # Track copied files for later processing
                    $global:CopiedFiles += @{
                        OriginalPath = $file.FullName
                        DestinationPath = $destinationPath
                        RelativePath = $relativePath
                        ModName = $modName
                        Category = $category
                    }
                }
                
                $categoryFiles++
                $categorySize += $file.Length
                $processedFiles++
                
                # Update progress less frequently for better performance
                if ($showProgressBar -and ($processedFiles - $lastProgressUpdate) -ge $progressUpdateInterval) {
                    $percentComplete = [math]::Min(100, [math]::Round(($processedFiles / $totalFilesToProcess) * 100))
                    $progressParams.Status = "$percentComplete% Complete ($processedFiles/$totalFilesToProcess files)"
                    $progressParams.PercentComplete = $percentComplete
                    Write-Progress @progressParams
                    $lastProgressUpdate = $processedFiles
                }
            }
            
            $allStats.TotalMods++
        }
        
        $allStats.TotalFiles += $categoryFiles
        $allStats.TotalSize += $categorySize
        $allStats.CategoryStats[$category] = @{
            Files = $categoryFiles
            Size = $categorySize
            ModsProcessed = $allStats.TotalMods - $prevTotalMods
            SkippedMods = if ($allStats.CategoryStats.ContainsKey($category) -and $allStats.CategoryStats[$category].ContainsKey('SkippedMods')) { 
                $allStats.CategoryStats[$category]['SkippedMods'] 
            } else { 
                0 
            }
        }
        
        $totalModsInCategory = $mods.Count
        $processedModsInCategory = $allStats.TotalMods - $prevTotalMods
        $skippedModsInCategory = $totalModsInCategory - $processedModsInCategory
        
        Write-Success "Category '$category': $categoryFiles files, $(Format-FileSize $categorySize)"
        if ($skippedModsInCategory -gt 0) {
            Write-Warning "  Note: $skippedModsInCategory of $totalModsInCategory mods were skipped (no target files or directory not found)"
        }
    }
    
    # Complete the progress bar
    if ($showProgressBar) {
        Write-Progress -Activity $progressParams.Activity -Completed
    }
    
    return $allStats
}

function Format-FileSize {
    param([long]$Size)
    
    if ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "$Size bytes"
    }
}

function Show-CopyResults {
    param(
        [hashtable]$Stats,
        [hashtable]$ConflictReport = @{},
        [bool]$SkippedLosingFiles = $false
    )
    
    Write-Info "`n=== CONSOLIDATION RESULTS ==="
    Write-Info "Total Mods Processed: $($Stats.TotalMods)"
    Write-Info "Total Files Copied: $($Stats.TotalFiles)"
    Write-Info "Total Size: $(Format-FileSize $Stats.TotalSize)"
    
    if ($ConflictReport.ContainsKey('TotalLosingFiles') -and $ConflictReport.TotalLosingFiles -gt 0) {
        if ($SkippedLosingFiles) {
            Write-Success "✅ Skipped $($ConflictReport.TotalLosingFiles) files that would lose conflicts"
            Write-Info "   Only copied files that will actually be used in the final load order"
        } else {
            Write-Warning "⚠️  Copied $($ConflictReport.TotalLosingFiles) files that will lose conflicts"
            Write-Info "   These files will be overridden by higher priority mods"
        }
    }
    
    Write-Info "`nBy Category:"
    foreach ($category in $Stats.CategoryStats.Keys) {
        $categoryStats = $Stats.CategoryStats[$category]
        Write-Host "  $category : $($categoryStats.Files) files, $(Format-FileSize $categoryStats.Size)" -ForegroundColor Green
    }
}

function Move-RenamedFilesToBackup {
    param(
        [array]$CopiedFiles,
        [string]$ModlistPath,
        [string]$BackupPath = ".\mods-backup"
    )
    
    if ($CopiedFiles.Count -eq 0) {
        Write-Info "No files to move to backup"
        return 0
    }
    
    Write-Info "`n=== MOVING RENAMED FILES TO BACKUP ==="
    Write-Info "Moving $($CopiedFiles.Count) .copied.mohidden files to backup location..."
    
    # Ensure backup path exists
    $backupPathResolved = if ([System.IO.Path]::IsPathRooted($BackupPath)) { 
        $BackupPath 
    } else { 
        Join-Path (Get-Location) $BackupPath 
    }
    
    if (-not (Test-Path $backupPathResolved)) {
        New-Item -ItemType Directory -Path $backupPathResolved -Force | Out-Null
        Write-Success "Created backup directory: $backupPathResolved"
    }
    
    $movedCount = 0
    $showProgressBar = $CopiedFiles.Count -gt 20
    $progressParams = @{
        Activity = "Moving renamed files to backup"
        Status = "0% Complete"
        PercentComplete = 0
    }
    
    # Pre-create directory structure
    $DirectoriesToCreate = @{}
    foreach ($fileInfo in $CopiedFiles) {
        # Get the original path with .copied.mohidden extension
        $renamedPath = "$($fileInfo.OriginalPath).copied.mohidden"
        
        if (Test-Path $renamedPath) {
            # Use the category that was stored during the copy operation
            $category = if ($fileInfo.Category) { $fileInfo.Category } else { "Uncategorized" }
            $modName = $fileInfo.ModName
            $relativePath = $fileInfo.RelativePath
            
            # RelativePath is already relative to the mod folder ("e.g., meshes\file.nif")
            # We just need to add it to: "backup/category/modname/relativepath"
            $destRelativePath = Join-Path $category (Join-Path $modName $relativePath)
            $destPath = Join-Path $backupPathResolved $destRelativePath
            $destDir = Split-Path $destPath -Parent
            $DirectoriesToCreate[$destDir] = $true
        }
    }
    
    # Create all directories
    $createdDirs = 0
    foreach ($dir in $DirectoriesToCreate.Keys) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $createdDirs++
        }
    }
    Write-Success "Pre-created $createdDirs directories"
    
    # Move files
    $processedCount = 0
    $lastProgressUpdate = 0
    $progressUpdateInterval = [Math]::Max(1, [Math]::Floor($CopiedFiles.Count / 100))
    
    foreach ($fileInfo in $CopiedFiles) {
        $processedCount++
        
        if ($showProgressBar -and ($processedCount - $lastProgressUpdate) -ge $progressUpdateInterval) {
            $percentComplete = [math]::Min(100, [math]::Round(($processedCount / $CopiedFiles.Count) * 100))
            $progressParams.Status = "$percentComplete% Complete ($processedCount/$($CopiedFiles.Count) files)"
            $progressParams.PercentComplete = $percentComplete
            Write-Progress @progressParams
            $lastProgressUpdate = $processedCount
        }
        
        try {
            $renamedPath = "$($fileInfo.OriginalPath).copied.mohidden"
            
            if (Test-Path $renamedPath) {
                # Use stored category and mod name from the copy operation
                $category = if ($fileInfo.Category) { $fileInfo.Category } else { "Uncategorized" }
                $modName = $fileInfo.ModName
                $relativePath = $fileInfo.RelativePath
                
                # RelativePath is already relative to the mod folder (e.g., meshes\file.nif)
                # We just need to add it to: backup/category/modname/relativepath.copied.mohidden
                $destRelativePath = Join-Path $category (Join-Path $modName $relativePath)
                $destPath = Join-Path $backupPathResolved "$destRelativePath.copied.mohidden"
                
                # Move file
                Move-Item -Path $renamedPath -Destination $destPath -Force
                $movedCount++
                
                if ($CopiedFiles.Count -le 50) {
                    Write-Host "  Moved to [$category/$modName]: $modRelativePath" -ForegroundColor DarkGray
                }
            }
        } catch {
            Write-Warning "  Failed to move: $($fileInfo.RelativePath) - $($_.Exception.Message)"
        }
    }
    
    if ($showProgressBar) {
        Write-Progress -Activity $progressParams.Activity -Completed
    }
    
    Write-Success "✅ Moved $movedCount files to backup location: $backupPathResolved"
    return $movedCount
}

function Handle-OriginalFiles {
    param(
        [array]$CopiedFiles,
        [int]$Action = 1,  # 1 = Do nothing, 2 = Delete, 3 = Rename
        [bool]$MoveToBackup = $false,
        [string]$ModlistPath = "",
        [string]$BackupPath = ".\mods-backup"
    )
    
    if ($CopiedFiles.Count -eq 0) {
        return
    }
    
    Write-Info "`n=== ORIGINAL FILE MANAGEMENT ==="
    
    # Show progress info for large file counts
    $showProgressBar = $CopiedFiles.Count -gt 20
    $progressParams = @{
        Activity = "Managing original files"
        Status = "0% Complete"
        PercentComplete = 0
    }
    
    switch ($Action) {
        1 {
            Write-Info "Keeping original files unchanged"
            return
        }
        2 {
            Write-Info "Deleting original files..."
            $deletedCount = 0
            $processedCount = 0
            $lastProgressUpdate = 0
            
            # Performance optimization: Calculate progress update interval
            $progressUpdateInterval = [Math]::Max(1, [Math]::Floor($CopiedFiles.Count / 100)) # Update progress at most 100 times
            
            # Start performance timing
            $deleteStartTime = Get-Date
            
            foreach ($fileInfo in $CopiedFiles) {
                $processedCount++
                
                # Update progress less frequently for better performance
                if ($showProgressBar -and ($processedCount - $lastProgressUpdate) -ge $progressUpdateInterval) {
                    $percentComplete = [math]::Min(100, [math]::Round(($processedCount / $CopiedFiles.Count) * 100))
                    $progressParams.Status = "$percentComplete% Complete ($processedCount/$($CopiedFiles.Count) files)"
                    $progressParams.PercentComplete = $percentComplete
                    Write-Progress @progressParams
                    $lastProgressUpdate = $processedCount
                }
                
                try {
                    # Remove-Item handles non-existent files gracefully with -ErrorAction SilentlyContinue
                    Remove-Item $fileInfo.OriginalPath -Force -ErrorAction SilentlyContinue
                    if ($?) {
                        # Silent success for performance - only show individual files for small operations
                        if ($CopiedFiles.Count -le 50) {
                            Write-Host "  Deleted: $($fileInfo.RelativePath)" -ForegroundColor DarkGray
                        }
                        $deletedCount++
                    }
                } catch {
                    Write-Warning "  Failed to delete: $($fileInfo.RelativePath) - $($_.Exception.Message)"
                }
                
                # Show periodic checkpoint for very large operations
                if ($processedCount % 1000 -eq 0 -and $processedCount -lt $CopiedFiles.Count) {
                    Write-Host "  Checkpoint: $processedCount/$($CopiedFiles.Count) files processed" -ForegroundColor Yellow
                }
            }
            
            # Complete the progress bar
            if ($showProgressBar) {
                Write-Progress -Activity $progressParams.Activity -Completed
            }
            
            # Calculate performance metrics
            $deleteEndTime = Get-Date
            $deleteDuration = $deleteEndTime - $deleteStartTime
            $filesPerSecond = if ($deleteDuration.TotalSeconds -gt 0) { 
                [math]::Round($deletedCount / $deleteDuration.TotalSeconds, 1) 
            } else { 
                $deletedCount 
            }
            
            # Show completion with performance info
            if ($deletedCount -gt 50) {
                Write-Success "✅ Deleted $deletedCount original files ($filesPerSecond files/sec)"
            } else {
                Write-Success "Deleted $deletedCount original files"
            }
        }
        3 {
            Write-Info "Renaming original files to .copied.mohidden..."
            $renamedCount = 0
            $processedCount = 0
            $lastProgressUpdate = 0
            
            # Performance optimization: Calculate progress update interval
            $progressUpdateInterval = [Math]::Max(1, [Math]::Floor($CopiedFiles.Count / 100)) # Update progress at most 100 times
            
            # Start performance timing
            $renameStartTime = Get-Date
            
            foreach ($fileInfo in $CopiedFiles) {
                $processedCount++
                
                # Update progress less frequently for better performance
                if ($showProgressBar -and ($processedCount - $lastProgressUpdate) -ge $progressUpdateInterval) {
                    $percentComplete = [math]::Min(100, [math]::Round(($processedCount / $CopiedFiles.Count) * 100))
                    $progressParams.Status = "$percentComplete% Complete ($processedCount/$($CopiedFiles.Count) files)"
                    $progressParams.PercentComplete = $percentComplete
                    Write-Progress @progressParams
                    $lastProgressUpdate = $processedCount
                }
                
                try {
                    if (Test-Path $fileInfo.OriginalPath) {
                        $newPath = "$($fileInfo.OriginalPath).copied.mohidden"
                        
                        # Rename-Item with -Force will overwrite existing files automatically
                        Rename-Item $fileInfo.OriginalPath $newPath -Force
                        
                        # Silent success for performance - only show individual files for small operations
                        if ($CopiedFiles.Count -le 50) {
                            Write-Host "  Renamed: $($fileInfo.RelativePath)" -ForegroundColor DarkYellow
                        }
                        $renamedCount++
                    }
                } catch {
                    Write-Warning "  Failed to rename: $($fileInfo.RelativePath) - $($_.Exception.Message)"
                }
                
                # Show periodic checkpoint for very large operations
                if ($processedCount % 1000 -eq 0 -and $processedCount -lt $CopiedFiles.Count) {
                    Write-Host "  Checkpoint: $processedCount/$($CopiedFiles.Count) files processed" -ForegroundColor Yellow
                }
            }
            
            # Complete the progress bar
            if ($showProgressBar) {
                Write-Progress -Activity $progressParams.Activity -Completed
            }
            
            # Calculate performance metrics
            $renameEndTime = Get-Date
            $renameDuration = $renameEndTime - $renameStartTime
            $filesPerSecond = if ($renameDuration.TotalSeconds -gt 0) { 
                [math]::Round($renamedCount / $renameDuration.TotalSeconds, 1) 
            } else { 
                $renamedCount 
            }
            
            # Show completion with performance info
            if ($renamedCount -gt 50) {
                Write-Success "✅ Renamed $renamedCount original files ($filesPerSecond files/sec)"
            } else {
                Write-Success "Renamed $renamedCount original files"
            }
            
            # After renaming, move to backup if requested
            if ($MoveToBackup -and $renamedCount -gt 0) {
                Move-RenamedFilesToBackup -CopiedFiles $CopiedFiles -ModlistPath $ModlistPath -BackupPath $BackupPath
            }
        }
        default {
            Write-Info "Keeping original files unchanged"
        }
    }
}

function Test-BSASizeLimit {
    param(
        [string]$FolderPath,
        [long]$MaxSizeBytes = 2147483648  # 2GB in bytes
    )
    
    if (-not (Test-Path $FolderPath)) {
        return @{ WithinLimit = $false; Size = 0; SizeFormatted = "0 bytes" }
    }
    
    $folderSize = (Get-ChildItem -Path $FolderPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $sizeFormatted = Format-FileSize $folderSize
    
    return @{
        WithinLimit = $folderSize -lt $MaxSizeBytes
        Size = $folderSize
        SizeFormatted = $sizeFormatted
        PercentOfLimit = [math]::Round(($folderSize / $MaxSizeBytes) * 100, 1)
    }
}

function Split-LargeCategoryForBSA {
    param(
        [string]$CategoryPath,
        [string]$CategoryName,
        [long]$MaxSizeBytes = 2000000000  # 2GB - small buffer for BSA overhead
    )
    
    Write-Warning "  Category '$CategoryName' is too large for a single BSA archive"
    Write-Info "  Analyzing folder structure for optimal splitting..."
    
    # Get all files with their sizes
    $allFiles = Get-ChildItem -Path $CategoryPath -Recurse -File
    $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
    
    # Strategy 1: Split by top-level directories (meshes, textures, etc.)
    $topLevelDirs = Get-ChildItem -Path $CategoryPath -Directory
    $dirSizes = @{
    }
    
    foreach ($dir in $topLevelDirs) {
        $dirSize = (Get-ChildItem -Path $dir.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        
        if ($dirSize -gt 0) {
            $dirSizes[$dir.Name] = @{
                Path = $dir.FullName
                Size = $dirSize
                SizeFormatted = Format-FileSize $dirSize
            }
        }
    }
    
    Write-Info "  Top-level directory sizes:"
    foreach ($dirName in $dirSizes.Keys | Sort-Object) {
        $dirInfo = $dirSizes[$dirName]
        Write-Host "    $dirName : $($dirInfo.SizeFormatted)" -ForegroundColor Gray
    }
    
    # Calculate how many archives we need
    $estimatedArchives = [math]::Ceiling($totalSize / $MaxSizeBytes)
    
    Write-Info "  Estimated archives needed: $estimatedArchives"
    Write-Info "  Total size: $(Format-FileSize $totalSize)"
    
    # Suggest splitting strategies
    Write-Host "`n  Splitting Options:" -ForegroundColor Yellow
    Write-Host "  1. Split by file type (meshes, textures, animations)" -ForegroundColor Gray
    Write-Host "  2. Create multiple numbered archives (Part1, Part2, etc.)" -ForegroundColor Gray
    Write-Host "  3. Skip archiving this category (keep as loose files)" -ForegroundColor Gray
    Write-Host "  4. Manual splitting (you choose directories)" -ForegroundColor Gray
    
    $choice = Read-Host "  Select splitting strategy (1-4)"
    
    switch ($choice) {
        "1" {
            return Split-ByFileType -CategoryPath $CategoryPath -CategoryName $CategoryName -MaxSizeBytes $MaxSizeBytes
        }
        "2" {
            return Split-BySize -CategoryPath $CategoryPath -CategoryName $CategoryName -MaxSizeBytes $MaxSizeBytes
        }
        "3" {
            Write-Info "  Skipping archive creation for '$CategoryName'"
            return @()
        }
        "4" {
            return Split-Manual -CategoryPath $CategoryPath -CategoryName $CategoryName -DirSizes $dirSizes -MaxSizeBytes $MaxSizeBytes
        }
        default {
            Write-Warning "  Invalid choice. Skipping archive creation for '$CategoryName'"
            return @()
        }
    }
}

function Split-ByFileType {
    param(
        [string]$CategoryPath,
        [string]$CategoryName,
        [long]$MaxSizeBytes
    )
    
    Write-Info "  Splitting by file type..."
    
    $splitArchives = @()
    $topLevelDirs = Get-ChildItem -Path $CategoryPath -Directory
    
    foreach ($dir in $topLevelDirs) {
        $dirSize = (Get-ChildItem -Path $dir.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        
        if ($dirSize -gt 0) {
            $archiveName = "$CategoryName - $($dir.Name).bsa"

            if ($dirSize -lt $MaxSizeBytes) {
                $splitArchives += @{
                    Name = $archiveName
                    SourcePath = $dir.FullName
                    Size = $dirSize
                    SizeFormatted = Format-FileSize $dirSize
                }
                Write-Info "    Archive: $archiveName ($(Format-FileSize $dirSize))"
            } else {
                Write-Warning "    Directory '$($dir.Name)' is still too large ($(Format-FileSize $dirSize))"
                Write-Info "    Auto-splitting '$($dir.Name)' directory into numbered parts..."
                
                # Get all files in this directory and split them by size
                $allFiles = Get-ChildItem -Path $dir.FullName -Recurse -File | Sort-Object Length -Descending
                $currentPart = 1
                $currentSize = 0
                $currentFiles = @()
                
                foreach ($file in $allFiles) {
                    if (($currentSize + $file.Length) -gt $MaxSizeBytes -and $currentFiles.Count -gt 0) {
                        # Create current archive
                        $partArchiveName = "$CategoryName - $($dir.Name) - Part $currentPart.bsa"
                        $splitArchives += @{
                            Name = $partArchiveName
                            Files = $currentFiles
                            Size = $currentSize
                            SizeFormatted = Format-FileSize $currentSize
                        }
                        Write-Info "    Archive: $partArchiveName ($(Format-FileSize $currentSize), $($currentFiles.Count) files)"
                        
                        # Start new archive
                        $currentPart++
                        $currentFiles = @()
                        $currentSize = 0
                    }
                    
                    $currentFiles += $file
                    $currentSize += $file.Length
                }
                
                # Add final archive if there are remaining files
                if ($currentFiles.Count -gt 0) {
                    $partArchiveName = "$CategoryName - $($dir.Name) - Part $currentPart.bsa"
                    $splitArchives += @{
                        Name = $partArchiveName
                        Files = $currentFiles
                        Size = $currentSize
                        SizeFormatted = Format-FileSize $currentSize
                    }
                    Write-Info "    Archive: $partArchiveName ($(Format-FileSize $currentSize), $($currentFiles.Count) files)"
                }
            }
        }
    }
    
    return $splitArchives
}

function Split-BySize {
    param(
        [string]$CategoryPath,
        [string]$CategoryName,
        [long]$MaxSizeBytes
    )
    
    Write-Info "  Splitting by size into multiple parts..."
    
    $allFiles = Get-ChildItem -Path $CategoryPath -Recurse -File | Sort-Object Length -Descending
    $splitArchives = @()
    $currentPart = 1
    $currentSize = 0
    $currentFiles = @()
    
    foreach ($file in $allFiles) {
        if (($currentSize + $file.Length) -gt $MaxSizeBytes -and $currentFiles.Count -gt 0) {
            # Create current archive
            $archiveName = "$CategoryName - Part $currentPart.bsa"
            $splitArchives += @{
                Name = $archiveName
                Files = $currentFiles
                Size = $currentSize
                SizeFormatted = Format-FileSize $currentSize
            }
            Write-Info "    Archive: $archiveName ($(Format-FileSize $currentSize), $($currentFiles.Count) files)"
            
            # Start new archive
            $currentPart++
            $currentFiles = @()
            $currentSize = 0
        }
        
        $currentFiles += $file
        $currentSize += $file.Length
    }
    
    # Add final archive if there are remaining files
    if ($currentFiles.Count -gt 0) {
        $archiveName = "$CategoryName - Part $currentPart.bsa"
        $splitArchives += @{
            Name = $archiveName
            Files = $currentFiles
            Size = $currentSize
            SizeFormatted = Format-FileSize $currentSize
        }
        Write-Info "    Archive: $archiveName ($(Format-FileSize $currentSize), $($currentFiles.Count) files)"
    }
    
    return $splitArchives
}

function Split-Manual {
    param(
        [string]$CategoryPath,
        [string]$CategoryName,
        [hashtable]$DirSizes,
        [long]$MaxSizeBytes
    )
    
    Write-Info "  Manual splitting - select directories for each archive"
    
    $splitArchives = @()
    $availableDirs = $DirSizes.Keys | Sort-Object
    $archiveNum = 1
    
    while ($availableDirs.Count -gt 0) {
        Write-Host "`n  Creating Archive $archiveNum for '$CategoryName':" -ForegroundColor Yellow
        Write-Host "  Available directories:" -ForegroundColor Gray
        
        for ($i = 0; $i -lt $availableDirs.Count; $i++) {
            $dirName = $availableDirs[$i]
            $dirInfo = $DirSizes[$dirName]
            Write-Host "    $($i + 1). $dirName ($(Format-FileSize $dirInfo.Size))" -ForegroundColor Gray
        }
        
        $selection = Read-Host "  Select directories (comma-separated numbers, or 'done' to finish)"
        
        if ($selection.ToLower() -eq "done") {
            break
        }
        
        $selectedDirs = @()
        $totalSize = 0
        
        $indices = $selection.Split(",") | ForEach-Object { $_.Trim() }
        foreach ($index in $indices) {
            if ($index -match "^\d+$") {
                $idx = [int]$index - 1
                if ($idx -ge 0 -and $idx -lt $availableDirs.Count) {
                    $dirName = $availableDirs[$idx]
                    $selectedDirs += $dirName
                    $totalSize += $DirSizes[$dirName].Size
                }
            }
        }
        
        if ($selectedDirs.Count -gt 0) {
            if ($totalSize -lt $MaxSizeBytes) {
                $archiveName = "$CategoryName - Archive $archiveNum.bsa"
                $splitArchives += @{
                    Name = $archiveName
                    Directories = $selectedDirs
                    Size = $totalSize
                    SizeFormatted = Format-FileSize $totalSize
                }
                
                Write-Success "    Archive: $archiveName ($(Format-FileSize $totalSize))"
                Write-Info "    Directories: $($selectedDirs -join ', ')"
                
                # Remove selected directories from available list
                $availableDirs = $availableDirs | Where-Object { $_ -notin $selectedDirs }
                $archiveNum++
            } else {
                Write-Warning "    Selected directories total $(Format-FileSize $totalSize) - exceeds 2GB limit"
            }
        }
    }
    
    return $splitArchives
}

function Create-BSAArchives {
    param(
        [string[]]$Categories,
        [string]$OutputPath,
        [string]$ArchivePath,
        [string]$BSArchPath,
        [bool]$AutomaticMode = $true,
        [bool]$CompressArchives = $false,
        [string]$GameFormat = "fnv"
    )
    
    Write-Info "`n=== BSA ARCHIVE CREATION ==="
    
    # Check if BSArch is available
    if (-not (Test-Path $BSArchPath)) {
        Write-Error "BSArch not found at: $BSArchPath"
        Write-Info "Please ensure BSArch.exe is available in the Tools\BSArch folder"
        return $false
    }
    
    # Create archive directory if it doesn't exist
    if (-not (Test-Path $ArchivePath)) {
        New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
        Write-Success "Created archive directory: $ArchivePath"
    }
    
    # Get absolute paths
    $bsArchFullPath = if ([System.IO.Path]::IsPathRooted($BSArchPath)) { $BSArchPath } else { Join-Path (Get-Location) $BSArchPath }
    $archiveFullPath = if ([System.IO.Path]::IsPathRooted($ArchivePath)) { $ArchivePath } else { Join-Path (Get-Location) $ArchivePath }
    $outputFullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path (Get-Location) $OutputPath }
    
    Write-Info "BSArch Path: $bsArchFullPath"
    Write-Info "Archive Output: $archiveFullPath"
    Write-Info "Game Format: $GameFormat"
    Write-Info "Compression: $CompressArchives"
    Write-Info "Mode: $(if ($AutomaticMode) { 'Automatic' } else { 'Manual' })"
    Write-Host ""
    
    $successCount = 0
    $totalCategories = $Categories.Count
    
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        $category = $Categories[$i]
        Write-Info "Processing category $($i + 1) of $totalCategories : $category"
        
        $compilationPath = Join-Path $OutputPath "$category`_Compiled"
        
        if (-not (Test-Path $compilationPath)) {
            Write-Warning "Compilation folder not found for category: $category"
            continue
        }
        
        $fileCount = (Get-ChildItem -Path $compilationPath -Recurse -File).Count
        if ($fileCount -eq 0) {
            Write-Warning "No files found in compilation folder for category: $category"
            continue
        }
        
        # Check BSA size limit (2GB)
        $sizeCheck = Test-BSASizeLimit -FolderPath $compilationPath
        
        Write-Info "  Source: $compilationPath"
        Write-Info "  Files: $fileCount ($($sizeCheck.SizeFormatted))"
        Write-Info "  Size limit check: $($sizeCheck.PercentOfLimit)% of 2GB limit"
        
        if (-not $sizeCheck.WithinLimit) {
            Write-Warning "  ⚠️  Category exceeds 2GB BSA limit!"
            Write-Info "  Current size: $($sizeCheck.SizeFormatted)"
            Write-Info "  BSA limit: 2.00 GB"
            Write-Host ""
            
            # Handle large category splitting
            $splitArchives = Split-LargeCategoryForBSA -CategoryPath $compilationPath -CategoryName $category
            
            if ($splitArchives.Count -eq 0) {
                Write-Warning "  Skipping archive creation for '$category'"
                continue
            }
            
            # Process split archives
            foreach ($splitArchive in $splitArchives) {
                $splitSuccess = Create-SingleBSAArchive -ArchiveInfo $splitArchive -CompilationPath $compilationPath -ArchivePath $ArchivePath -BSArchPath $BSArchPath -GameFormat $GameFormat -CompressArchives $CompressArchives -AutomaticMode $AutomaticMode
                if ($splitSuccess) {
                    $successCount++
                }
            }
            
            continue
        }
        
        # Create safe archive name (remove invalid characters)
        $safeCategory = $category -replace '[<>:"/\\|?*]', '_'
        $archiveName = "$safeCategory.bsa"
        $archiveDestination = Join-Path $archiveFullPath $archiveName
        
        # Ensure absolute path
        if (-not [System.IO.Path]::IsPathRooted($archiveDestination)) {
            $archiveDestination = Join-Path (Get-Location) $archiveDestination
        }
        
        Write-Info "  Archive: $archiveName"
        
        # Make sure the archive destination directory exists
        $archiveDir = Split-Path $archiveDestination -Parent
        if (-not (Test-Path $archiveDir)) {
            New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
        }
        
        if ($AutomaticMode) {
            Write-Info "  Creating BSA archive automatically..."
            
            # Build command arguments for BSArch
            # Use absolute paths to avoid path resolution issues
            $arguments = @("pack", "`"$compilationPath`"", "`"$archiveDestination`"")
            
            # Add game format (fnv for Fallout New Vegas)
            $arguments += "-$GameFormat"
            
            # Add compression if enabled
            if ($CompressArchives) {
                $arguments += "-z"
                Write-Warning "  Compression enabled - ensure no sound/voice files are included!"
            }
            
            # Add optimizations
            $arguments += "-share"  # Share identical files
            $arguments += "-mt"     # Multi-threaded
            
            $commandLine = "$BSArchPath $($arguments -join ' ')"
            Write-Info "  Command: $commandLine"
            
            try {
                Write-Info "  Executing BSArch... This may take a while for large archives."
                # Execute BSArch using Wine wrapper on Linux or directly on Windows
                if ($CompressArchives) {
                    $bsarchResult = Invoke-BSArch -BSArchPath $BSArchPath -Arguments @("pack", $compilationPath, $archiveDestination, "-$GameFormat", "-z", "-share", "-mt")
                } else {
                    $bsarchResult = Invoke-BSArch -BSArchPath $BSArchPath -Arguments @("pack", $compilationPath, $archiveDestination, "-$GameFormat", "-share", "-mt")
                }
                $result = $bsarchResult.Output
                $LASTEXITCODE = $bsarchResult.ExitCode
                
                if ($LASTEXITCODE -eq 0) {
                    if (Test-Path $archiveDestination) {
                        $archiveSize = (Get-Item $archiveDestination).Length
                        $archiveSizeFormatted = Format-FileSize $archiveSize
                        
                        $compressionRatio = [math]::Round(($sizeCheck.Size - $archiveSize) / $sizeCheck.Size * 100, 1)
                        
                        Write-Success "  ✅ Archive created successfully!"
                        Write-Success "  📁 Archive size: $archiveSizeFormatted"
                        Write-Success "  📊 Compression: $compressionRatio% size reduction"
                        $successCount++
                    } else {
                        Write-Error "  ❌ Archive creation reported success but file not found"
                    }
                } else {
                    Write-Error "  ❌ Failed to create archive"
                    Write-Error "  Output: $result"
                    
                    # Offer manual fallback
                    if (Get-UserConfirmation "  Would you like to try manual archive creation for '$category'?" "n") {
                        Show-ManualBSArchInstructions -CompilationPath $compilationPath -ArchivePath $archiveDestination
                        if (Get-UserConfirmation "  Have you created the BSA archive manually?" "n") {
                            $successCount++
                            Write-Success "  ✅ Manual archive creation completed for '$category'"
                        }
                    }
                }
            } catch {
                Write-Error "  ❌ Error running BSArch: $_"
                
                # Offer manual fallback
                if (Get-UserConfirmation "  Would you like to try manual archive creation for '$category'?" "n") {
                    Show-ManualBSArchInstructions -CompilationPath $compilationPath -ArchivePath $archiveDestination
                    if (Get-UserConfirmation "  Have you created the BSA archive manually?" "n") {
                        $successCount++
                        Write-Success "  ✅ Manual archive creation completed for '$category'"
                    }
                }
            }
        } else {
            # Manual mode
            Show-ManualBSArchInstructions -CompilationPath $compilationPath -ArchivePath $archiveDestination
            
            if (Get-UserConfirmation "  Have you created the BSA archive for '$category'?" "n") {
                $successCount++
                Write-Success "  ✅ Manual archive creation completed for '$category'"
            } else {
                Write-Warning "  ⚠️ Archive creation skipped for '$category'"
            }
        }
        
        Write-Host ""
    }
    
    # Show final archive results
    Write-Info "=== ARCHIVE CREATION SUMMARY ==="
    Write-Info "Categories processed: $totalCategories"
    Write-Info "Archives created: $successCount"
    if ($totalCategories -gt 0) {
        $successfulCategories = if ($successCount -gt 0) { $totalCategories } else { 0 }
        Write-Info "Success rate: $([math]::Round($successfulCategories / $totalCategories * 100, 1))%"
    } else {
        Write-Info "Success rate: 0%"
    }
    
    if ($successCount -gt 0) {
        Write-Success "`nArchive creation completed!"
        Write-Info "Archives location: $ArchivePath"
        Write-Info "`nNext steps:"
        Write-Info "1. Copy the .bsa files to your Fallout New Vegas Data folder"
        Write-Info "2. Ensure they're loaded by your mod manager or plugin"
        Write-Info "3. Test in-game to verify everything works correctly"
        Write-Info "4. Consider backing up your original mod files"
    }
    
    return $successCount -gt 0
}

function Create-SingleBSAArchive {
    param(
        [hashtable]$ArchiveInfo,
        [string]$CompilationPath,
        [string]$ArchivePath,
        [string]$BSArchPath,
        [string]$GameFormat,
        [bool]$CompressArchives,
        [bool]$AutomaticMode
    )
    
    $archiveDestination = Join-Path $ArchivePath $ArchiveInfo.Name
    
    Write-Info "  Creating split archive: $($ArchiveInfo.Name)"
    Write-Info "  Size: $($ArchiveInfo.SizeFormatted)"
    
    if ($AutomaticMode) {
        # Determine source path based on archive type
        $sourcePath = if ($ArchiveInfo.ContainsKey('SourcePath')) {
            $ArchiveInfo.SourcePath
        } elseif ($ArchiveInfo.ContainsKey('Directories')) {
            # For manual splitting, we need to create a temporary directory
            $tempDir = Join-Path $env:TEMP "BSA_Temp_$([System.IO.Path]::GetRandomFileName())"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            
            # Copy selected directories to temp location
            foreach ($dirName in $ArchiveInfo.Directories) {
                $sourceDir = Join-Path $CompilationPath $dirName
                $destDir = Join-Path $tempDir $dirName
                Copy-Item -Path $sourceDir -Destination $destDir -Recurse -Force
            }
            
            $tempDir
        } else {
            # For size-based splitting, create temp directory with specific files
            $tempDir = Join-Path $env:TEMP "BSA_Temp_$([System.IO.Path]::GetRandomFileName())"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            
            foreach ($file in $ArchiveInfo.Files) {
                $relativePath = $file.FullName.Substring($CompilationPath.Length + 1)
                $destPath = Join-Path $tempDir $relativePath
                $destDir = Split-Path $destPath -Parent
                
                if (-not (Test-Path $destDir)) {
                    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
                }
                
                Copy-Item -Path $file.FullName -Destination $destPath -Force
            }
            
            $tempDir
        }
        
        # Build command arguments for BSArch
        # Use absolute paths to avoid BSArch path issues
        # Note: Wine handles Unix paths natively, no conversion needed on Linux
        if (-not $global:UseWine) {
            # Only convert to Windows paths when NOT using Wine
            $sourcePath = $sourcePath.Replace('/', '\')
        }
        
        # Convert archive destination to absolute path
        if (-not [System.IO.Path]::IsPathRooted($archiveDestination)) {
            $archiveDestination = Join-Path (Get-Location) $archiveDestination
        }
        if (-not $global:UseWine) {
            # Only convert to Windows paths when NOT using Wine
            $archiveDestination = $archiveDestination.Replace('/', '\')
        }
        
        # Make sure the archive destination directory exists
        $archiveDir = Split-Path $archiveDestination -Parent
        if (-not (Test-Path $archiveDir)) {
            New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
        }
        
        try {
            Write-Info "  Executing BSArch for split archive..."
            Write-Info "  Source path: $sourcePath"
            Write-Info "  Archive destination: $archiveDestination"
            
            # Use Wine wrapper for cross-platform execution
            if ($CompressArchives) {
                $bsarchResult = Invoke-BSArch -BSArchPath $BSArchPath -Arguments @("pack", $sourcePath, $archiveDestination, "-$GameFormat", "-z", "-share", "-mt")
            } else {
                $bsarchResult = Invoke-BSArch -BSArchPath $BSArchPath -Arguments @("pack", $sourcePath, $archiveDestination, "-$GameFormat", "-share", "-mt")
            }
            $result = $bsarchResult.Output
            $LASTEXITCODE = $bsarchResult.ExitCode
            
            if ($LASTEXITCODE -eq 0) {
                if (Test-Path $archiveDestination) {
                    $archiveSize = (Get-Item $archiveDestination).Length
                    $archiveSizeFormatted = Format-FileSize $archiveSize
                    
                    Write-Success "  ✅ Split archive created successfully!"
                    Write-Success "  📁 Archive size: $archiveSizeFormatted"
                    
                    # Clean up temporary directory if we created one
                    if ($sourcePath -like "*BSA_Temp_*") {
                        Remove-Item -Path $sourcePath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                    return $true
                } else {
                    Write-Error "  ❌ Split archive creation reported success but file not found"
                    return $false
                }
            } else {
                Write-Error "  ❌ Failed to create split archive"
                Write-Error "  Output: $result"
                return $false
            }
        } catch {
            Write-Error "  ❌ Error creating split archive: $_"
            return $false
        } finally {
            # Clean up temporary directory if we created one
            if ($sourcePath -like "*BSA_Temp_*" -and (Test-Path $sourcePath)) {
                Remove-Item -Path $sourcePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        # Manual mode for split archives
        Write-Host "  === MANUAL SPLIT ARCHIVE CREATION ===" -ForegroundColor Yellow
        Write-Host "  Archive: $($ArchiveInfo.Name)" -ForegroundColor Cyan
        Write-Host "  Size: $($ArchiveInfo.SizeFormatted)" -ForegroundColor Cyan
        
        if ($ArchiveInfo.ContainsKey('SourcePath')) {
            Write-Host "  Source: $($ArchiveInfo.SourcePath)" -ForegroundColor Gray
        } elseif ($ArchiveInfo.ContainsKey('Directories')) {
            Write-Host "  Directories: $($ArchiveInfo.Directories -join ', ')" -ForegroundColor Gray
        }
        
        Write-Host "  Command: BSArch.exe pack [source] `"$archiveDestination`" -$GameFormat -share -mt" -ForegroundColor Cyan
        
        if (Get-UserConfirmation "  Have you created this split archive?" "n") {
            Write-Success "  ✅ Manual split archive creation completed"
            return $true
        } else {
            Write-Warning "  ⚠️ Split archive creation skipped"
            return $false
        }
    }
}

function Show-ManualBSArchInstructions {
    param(
        [string]$CompilationPath,
        [string]$ArchivePath
    )
    
    Write-Host "  === MANUAL BSA CREATION INSTRUCTIONS ===" -ForegroundColor Yellow
    Write-Host "  1. Navigate to: Tools\BSArch\" -ForegroundColor Gray
    Write-Host "  2. Run: BSArch.exe" -ForegroundColor Gray
    Write-Host "  3. Use the 'pack' command:" -ForegroundColor Gray
    Write-Host "     BSArch.exe pack `"$CompilationPath`" `"$ArchivePath`" -fnv -share -mt" -ForegroundColor Cyan
    Write-Host "  4. Or use the GUI version if available" -ForegroundColor Gray
    Write-Host "  5. Verify the archive was created successfully" -ForegroundColor Gray
    Write-Host ""
}

function Show-FinalSummary {
    param(
        [hashtable]$Stats,
        [string[]]$Categories,
        [bool]$ArchivesCreated
    )
    
    Write-Info "`n=== FINAL SUMMARY ==="
    Write-Info "Categories Processed: $($Categories.Count)"
    Write-Info "Total Files Consolidated: $($Stats.TotalFiles)"
    Write-Info "Total Size Processed: $(Format-FileSize $Stats.TotalSize)"
    
    if ($ArchivesCreated) {
        Write-Success "BSA archives created successfully"
        Write-Info "`nNext Steps:"
        Write-Info "1. Ensure the dummy ESP plugins are enabled in your load order"
        Write-Info "2. The dummy plugins will ensure your BSA archives are loaded"
        Write-Info "3. Test your game to ensure everything works correctly"
        Write-Info "4. Consider backing up your original mod files before final deployment"
    } else {
        Write-Info "`nYou can create BSA archives later using BSArch or BSArchPro:"
    }
}

function Get-ModlistInsertPosition {
    param(
        [string]$ModlistPath,
        [string]$CategoryName
    )
    
    $modlistContent = Get-Content $ModlistPath
    $separatorName = "-$CategoryName$SEPARATOR_SUFFIX"
    
    # Find the separator line for this category
    $separatorIndex = -1
    for ($i = 0; $i -lt $modlistContent.Count; $i++) {
        if ($modlistContent[$i] -eq $separatorName) {
            $separatorIndex = $i
            break
        }
    }
    
    if ($separatorIndex -eq -1) {
        Write-Warning "Could not find separator '$separatorName' in modlist"
        
        # Check if this is a split category (e.g. "Visuals - Weapons-textures")
        # Try to find the parent category instead
        if ($CategoryName -match "^(.+?)-\w+") {
            $parentCategory = $matches[1]
            Write-Info "Trying parent category: $parentCategory"
            
            $parentSeparatorName = "-$parentCategory$SEPARATOR_SUFFIX"
            for ($i = 0; $i -lt $modlistContent.Count; $i++) {
                if ($modlistContent[$i] -eq $parentSeparatorName) {
                    $separatorIndex = $i
                    Write-Success "Found parent category separator: $parentSeparatorName"
                    break
                }
            }
            
            if ($separatorIndex -eq -1) {
                Write-Warning "Could not find parent separator '$parentSeparatorName' in modlist"
                return -1
            }
        } else {
            return -1
        }
    }
    
    # Since modlist is bottom-to-top, find the highest priority position in this category
    # The highest priority is the first mod entry BEFORE the separator
    # We need to find the first non-separator line above the separator
    
    # Start from just before the separator and go backwards to find the top of category
    for ($i = $separatorIndex - 1; $i -ge 0; $i--) {
        $line = $modlistContent[$i]
        # If we hit another separator, the highest priority is the line after it
        if ($line.StartsWith("-") -and $line.EndsWith("$SEPARATOR_SUFFIX")) {
            return $i + 1
        }
        # If we hit the comment line at the top, highest priority is line 1 (after comment)
        if ($line.StartsWith("#")) {
            return $i + 1
        }
    }
    
    # If we reached the beginning without finding a separator or comment, insert at position 0
    return 0
}

function Add-ToModlist {
    param(
        [string]$ModlistPath,
        [string]$ModName,
        [string]$CategoryName
    )
    
    try {
        $modlistContent = Get-Content $ModlistPath
        $insertPosition = Get-ModlistInsertPosition -ModlistPath $ModlistPath -CategoryName $CategoryName
        
        if ($insertPosition -eq -1) {
            Write-Error "Cannot add to modlist - separator not found for '$CategoryName' or its parent category"
            return $false
        }
        
        # Insert the new mod entry at the calculated position (highest priority in category)
        $newEntry = "+$ModName"
        $newContent = @()
        
        for ($i = 0; $i -lt $modlistContent.Count; $i++) {
            if ($i -eq $insertPosition) {
                # Insert our new mod at the highest priority position in the category
                $newContent += $newEntry
            }
            $newContent += $modlistContent[$i]
        }
        
        # If insertPosition is at the end of the array, we need to append the new entry
        if ($insertPosition -eq $modlistContent.Count) {
            $newContent += $newEntry
        }
        
        # Write back to file
        $newContent | Set-Content $ModlistPath
        Write-Success "Added '$ModName' to modlist in $CategoryName section (highest priority)"
        return $true
        
    } catch {
        Write-Error "Failed to update modlist: $($_.Exception.Message)"
        return $false
    }
}

function Move-CompiledFolderToMods {
    param(
        [string]$CompiledFolderPath,
        [string]$CategoryName,
        [string]$ModsPath,
        [string]$ModlistPath
    )
    
    if (-not (Test-Path $CompiledFolderPath)) {
        Write-Error "Compiled folder not found: $CompiledFolderPath"
        return $false
    }
    
    $folderName = "$CategoryName Compiled"
    $destinationPath = Join-Path $ModsPath $folderName
    
    Write-Info "Moving compiled folder to MO2 mods directory..."
    Write-Info "Source: $CompiledFolderPath"
    Write-Info "Destination: $destinationPath"
    
    try {
        # Check if destination already exists
        if (Test-Path $destinationPath) {
            if (Get-UserConfirmation "Destination folder already exists. Overwrite?" "n") {
                Remove-Item $destinationPath -Recurse -Force
            } else {
                Write-Info "Operation cancelled"
                return $false
            }
        }
        
        # Move the folder
        Move-Item $CompiledFolderPath $destinationPath -Force
        Write-Success "Compiled folder moved successfully"
        
        # Update modlist.txt
        $success = Add-ToModlist -ModlistPath $ModlistPath -ModName $folderName -CategoryName $CategoryName
        
        if ($success) {
            Write-Success "✅ '$folderName' has been added to your MO2 setup!"
            Write-Info "The mod is now available in Mod Organizer 2"
            
            # Clean up the original compiled folder since it's been moved
            Write-Info "Compiled folder successfully moved to MO2"
            
            return $true
        } else {
            Write-Warning "Folder moved but modlist update failed"
            return $false
        }
        
    } catch {
        Write-Error "Failed to move compiled folder: $($_.Exception.Message)"
        return $false
    }
}

function Move-BSAArchivesToMods {
    param(
        [System.IO.FileInfo[]]$Archives,
        [string]$CategoryName,
        [string]$ModsPath,
        [string]$ModlistPath,
        [bool]$CreateESP = $true,
        [bool]$DeleteOriginalArchive = $true,
        [string]$ParentCategory = ""
    )
    
    if ($Archives.Count -eq 0) {
        Write-Error "No archives provided"
        return $false
    }
    
    # Create a unified folder name for all archives in this category
    $folderName = "$CategoryName Archive"
    $destinationFolder = Join-Path $ModsPath $folderName
    
    Write-Info "Creating mod folder for BSA archive(s)..."
    Write-Info "Category: $CategoryName"
    Write-Info "Archives: $($Archives.Name -join ', ')"
    Write-Info "Destination: $destinationFolder"
    
    try {
        # Create destination folder if it doesn't exist
        if (-not (Test-Path $destinationFolder)) {
            New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
        }
        
        $copiedArchives = @()
        
        # Copy all BSA files to destination
        foreach ($archive in $Archives) {
            $bsaDestination = Join-Path $destinationFolder $archive.Name
            Copy-Item $archive.FullName $bsaDestination -Force
            $copiedArchives += $archive.Name
            
            # Check for and copy corresponding .override file
            $overrideSourcePath = [System.IO.Path]::ChangeExtension($archive.FullName, ".override")
            if (Test-Path $overrideSourcePath) {
                $overrideDestination = Join-Path $destinationFolder ([System.IO.Path]::GetFileName($overrideSourcePath))
                Copy-Item $overrideSourcePath $overrideDestination -Force
                Write-Success "Override file copied: $([System.IO.Path]::GetFileName($overrideSourcePath))"
            }
        }
        
        Write-Success "BSA archive(s) copied to mod folder: $($copiedArchives -join ', ')"
        
        # Create a simple text file to document the archives (instead of invalid ESP)
        if ($CreateESP) {
            # Create dummy ESP plugin to ensure BSA is loaded
            $pluginName = "$CategoryName.esp"
            $pluginPath = Join-Path $destinationFolder $pluginName
            
            # Copy the genuine plugin.esp template instead of creating an empty container
            $templateESP = Join-Path $PSScriptRoot "..\BSArch\plugin.esp"
            if (Test-Path $templateESP) {
                Copy-Item $templateESP $pluginPath -Force
                Write-Success "Created ESP plugin from template: $pluginName"
            } else {
                # Fallback to creating a minimal ESP file if template is not found
                $emptyPlugin = New-Object byte[] 12
                # HEDR structure
                $emptyPlugin[0] = 84 # 'T'
                $emptyPlugin[1] = 69 # 'E'
                $emptyPlugin[2] = 83 # 'S'
                $emptyPlugin[3] = 52 # '4'
                
                # Write the ESP file
                [System.IO.File]::WriteAllBytes($pluginPath, $emptyPlugin)
                Write-Warning "Template ESP not found, created minimal ESP plugin: $pluginName"
            }
        }
        
        # Update modlist.txt - first try with the specific category name
        $success = Add-ToModlist -ModlistPath $ModlistPath -ModName $folderName -CategoryName $CategoryName
        
        # If that failed and we have a parent category, try with the parent category
        if (-not $success -and -not [string]::IsNullOrEmpty($ParentCategory)) {
            Write-Info "Trying to add to parent category: $ParentCategory"
            $success = Add-ToModlist -ModlistPath $ModlistPath -ModName $folderName -CategoryName $ParentCategory
        }
        
        # If still failed, try to extract parent category from the category name
        if (-not $success) {
            if ($CategoryName -match "^(.+?) - (meshes|textures|sound|animations?)") {
                $extractedParent = $matches[1]
                Write-Info "Trying to add to extracted parent category: $extractedParent"
                $success = Add-ToModlist -ModlistPath $ModlistPath -ModName $folderName -CategoryName $extractedParent
            }
        }
        
        if ($success) {
            Write-Success "✅ '$folderName' has been added to your MO2 setup!"
            Write-Info "The BSA archive(s) are now available in Mod Organizer 2"
            Write-Info "BSA Location: $destinationFolder"
            
            # Clean up the original BSA archives since they've been copied
            if ($DeleteOriginalArchive) {
                try {
                    foreach ($archive in $Archives) {
                        Remove-Item $archive.FullName -Force
                        
                        # Also delete the .override file if it exists
                        $overrideSourcePath = [System.IO.Path]::ChangeExtension($archive.FullName, ".override")
                        if (Test-Path $overrideSourcePath) {
                            Remove-Item $overrideSourcePath -Force
                        }
                    }
                    Write-Success "Original BSA archive(s) deleted"
                } catch {
                    Write-Warning "Failed to delete some original BSA archives: $($_.Exception.Message)"
                }
            }
            
            return $true
        } else {
            Write-Warning "Archive(s) copied but modlist update failed"
            return $false
        }
        
    } catch {
        Write-Error "Failed to create BSA mod: $($_.Exception.Message)"
        return $false
    }
}

function Move-BSAArchiveToMods {
    param(
        [string]$ArchivePath,
        [string]$CategoryName,
        [string]$ModsPath,
        [string]$ModlistPath,
        [bool]$CreateESP = $true,
        [bool]$DeleteOriginalArchive = $true
    )
    
    if (-not (Test-Path $ArchivePath)) {
        Write-Error "Archive not found: $ArchivePath"
        return $false
    }
    
    $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    $folderName = "$CategoryName Archive"
    $destinationFolder = Join-Path $ModsPath $folderName
    
    Write-Info "Creating mod folder for BSA archive..."
    Write-Info "Archive: $ArchivePath"
    Write-Info "Destination: $destinationFolder"
    
    try {
        # Create destination folder if it doesn't exist
        if (-not (Test-Path $destinationFolder)) {
            New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
        }
        
        # Copy BSA to destination (keep original)
        $bsaDestination = Join-Path $destinationFolder ([System.IO.Path]::GetFileName($ArchivePath))
        Copy-Item $ArchivePath $bsaDestination -Force
        
        Write-Success "BSA archive copied to mod folder"
        
        # Check for and copy corresponding .override file
        $overrideSourcePath = [System.IO.Path]::ChangeExtension($ArchivePath, ".override")
        if (Test-Path $overrideSourcePath) {
            $overrideDestination = Join-Path $destinationFolder ([System.IO.Path]::GetFileName($overrideSourcePath))
            Copy-Item $overrideSourcePath $overrideDestination -Force
            Write-Success "Override file copied to mod folder"
        }
        
        # Create a simple plugin file if needed
        if ($CreateESP) {
            # Create dummy ESP plugin to ensure BSA is loaded
            $pluginName = "$CategoryName.esp"
            $pluginPath = Join-Path $destinationFolder $pluginName
            
            # Create a minimal ESP file - 12 bytes for a valid empty plugin
            $emptyPlugin = New-Object byte[] 12
            # HEDR structure
            $emptyPlugin[0] = 84 # 'T'
            $emptyPlugin[1] = 69 # 'E'
            $emptyPlugin[2] = 83 # 'S'
            $emptyPlugin[3] = 52 # '4'
            
            # Write the ESP file
            [System.IO.File]::WriteAllBytes($pluginPath, $emptyPlugin)
            Write-Success "Created dummy ESP plugin: $pluginName"
        }
        
        # Update modlist.txt
        $success = Add-ToModlist -ModlistPath $ModlistPath -ModName $folderName -CategoryName $CategoryName
        
        if ($success) {
            Write-Success "✅ '$folderName' has been added to your MO2 setup!"
            Write-Info "The BSA archive is now available in Mod Organizer 2"
            Write-Info "BSA Location: $bsaDestination"
            
            # Clean up the original BSA archive since it's been copied
            if ($DeleteOriginalArchive) {
                try {
                    Remove-Item $ArchivePath -Force
                    Write-Success "Original BSA archive deleted"
                    
                    # Also delete the .override file if it exists
                    $overrideSourcePath = [System.IO.Path]::ChangeExtension($ArchivePath, ".override")
                    if (Test-Path $overrideSourcePath) {
                        Remove-Item $overrideSourcePath -Force
                        Write-Success "Original .override file deleted"
                    }
                } catch {
                    Write-Warning "Failed to delete original BSA archive: $($_.Exception.Message)"
                }
            }
            
            return $true
        } else {
            Write-Warning "Archive copied but modlist update failed"
            return $false
        }
        
    } catch {
        Write-Error "Failed to create BSA mod: $($_.Exception.Message)"
        return $false
    }
}

function Offer-ModIntegration {
    param(
        [string[]]$Categories,
        [string]$OutputPath,
        [string]$ArchivePath,
        [string]$ModsPath,
        [string]$ModlistPath
    )
    
    Write-Info "`n=== MOD ORGANIZER 2 INTEGRATION ==="
    Write-Info "You can integrate your consolidated files directly into MO2"
    Write-Host ""
    
    foreach ($category in $Categories) {
        Write-Host "Category: $category" -ForegroundColor Yellow
        
        # Check for compiled folder
        $compiledPath = Join-Path $OutputPath "$category`_Compiled"
        $hasCompiledFolder = Test-Path $compiledPath
        
        # Check for BSA archive
        $safeCategory = $category -replace '[<>:"/\\|?*]', '_'
        $archiveFile = Join-Path $ArchivePath "$safeCategory.bsa"
        $hasArchive = Test-Path $archiveFile
        
        if ($hasCompiledFolder) {
            $fileCount = (Get-ChildItem -Path $compiledPath -Recurse -File).Count
            $folderSize = (Get-ChildItem -Path $compiledPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $sizeFormatted = Format-FileSize $folderSize
            
            Write-Info "  📁 Compiled folder: $fileCount files ($sizeFormatted)"
            if (Get-UserConfirmation "    Move compiled folder '$category Compiled' to MO2 mods?" "n") {
                Move-CompiledFolderToMods -CompiledFolderPath $compiledPath -CategoryName $category -ModsPath $ModsPath -ModlistPath $ModlistPath
            }
        }
        
        if ($hasArchive) {
            $archiveSize = (Get-Item $archiveFile).Length
            $archiveSizeFormatted = Format-FileSize $archiveSize
            
            Write-Info "  📦 BSA archive: $archiveSizeFormatted"
            if (Get-UserConfirmation "    Create MO2 mod for BSA archive '$safeCategory.bsa'?" "n") {
                Move-BSAArchiveToMods -ArchivePath $archiveFile -CategoryName $category -ModsPath $ModsPath -ModlistPath $ModlistPath
            }
        }
        
        if (-not $hasCompiledFolder -and -not $hasArchive) {
            Write-Warning "  ❌ No compiled folder or archive found for this category"
        }
        
        Write-Host ""
    }
    
    Write-Info "Integration complete! Check Mod Organizer 2 to see your new mods."
}

function Create-OverrideFiles {
    param(
        [string[]]$Categories,
        [string]$ArchivePath
    )
    
    Write-Info "`n=== BSA OVERRIDE FILE CREATION ==="
    Write-Info ".override file allows the relevant archive file to overwrite contents in archives loaded before this one"
    Write-Host ""
    
    $overrideCount = 0
    
    foreach ($category in $Categories) {
        # Create safe archive name (remove invalid characters)
        $safeCategory = $category -replace '[<>:"/\\|?*]', '_'
        
        # Find all BSA archives for this category (using wildcard)
        $archivePattern = "$safeCategory*.bsa"
        $archiveFiles = Get-ChildItem -Path $ArchivePath -Filter $archivePattern -ErrorAction SilentlyContinue
        
        if ($archiveFiles.Count -eq 0) {
            Write-Warning "  ⚠️  No BSA archives found for category: $category"
            continue
        }
        
        # Process each archive file
        foreach ($archiveFile in $archiveFiles) {
            $archiveName = $archiveFile.Name
            $archiveBaseName = $archiveFile.BaseName
            $overrideName = "$archiveBaseName.override"
            $overridePath = Join-Path $ArchivePath $overrideName
            
            Write-Info "Creating override file for: $archiveName"
            
            try {
                # Create empty .override file
                New-Item -Path $overridePath -ItemType File -Force | Out-Null
                
                # Add a comment to the override file for clarity
                "# Override file for $archiveName" | Out-File $overridePath -Encoding UTF8
                "# This .override file allows the relevant archive file to overwrite contents in archives loaded before this one" | Add-Content $overridePath -Encoding UTF8
                "# Created by MO2 Consolidation Script on $(Get-Date)" | Add-Content $overridePath -Encoding UTF8
                
                Write-Success "  ✅ Created: $overrideName"
                $overrideCount++
                
            } catch {
                Write-Error "  ❌ Failed to create override file: $($_.Exception.Message)"
            }
        }
    }
    
    # Summary
    Write-Info "`n=== OVERRIDE FILE CREATION SUMMARY ==="
    Write-Info "Categories processed: $($Categories.Count)"
    Write-Info "Override files created: $overrideCount"
    
    if ($overrideCount -gt 0) {
        Write-Success "`nOverride files created successfully!"
        Write-Info "Override files location: $ArchivePath"
        Write-Info "`nBenefits of .override files:"
        Write-Info "• .override file allows the relevant archive file to overwrite contents in archives loaded before this one"
        Write-Info "• Useful for custom load orders in Mod Organizer 2"
    }
    
    return $overrideCount -gt 0
}

# Main execution function
function Main {
    Show-Header
    
    # Step 0: Configuration Preset Selection
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 0: Configuration Preset Selection"
    $global:ConfigPreset = Select-ConfigPreset
    
    # Step 1: Profile Selection and Path Initialization
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 1: Profile Selection and Path Initialization"
    
    # Always use profile selection - simplified workflow
    $selectedModlistPath = Select-Profile
    if (-not $selectedModlistPath) {
        Write-Error "No valid profile selected. Exiting."
        exit 1
    }
    $modlistFullPath = $selectedModlistPath
    
    Write-Success "Using modlist: $modlistFullPath"
    
    $modsFullPath = Join-Path (Get-Location) $ModsPath
    $outputFullPath = Join-Path (Get-Location) $OutputPath
    $archiveFullPath = if ([System.IO.Path]::IsPathRooted($ArchivePath)) { $ArchivePath } else { Join-Path (Get-Location) $ArchivePath }
    
    # Validate paths
    if (-not (Test-Path $modlistFullPath)) {
        Write-Error "Modlist file not found: $modlistFullPath"
        exit 1
    }
    
    if (-not (Test-Path $modsFullPath)) {
        Write-Error "Mods directory not found: $modsFullPath"
        exit 1
    }
    
    Write-Success "System initialized successfully"
    Write-Host ("=" * 30) -ForegroundColor Yellow
    
    # Step 2: Execution mode - Live mode enabled
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 2: Execution mode"
    $isDryRun = $false
    Write-Info "LIVE MODE - Files will be copied and modified"
    
    # Old dry run option (commented out):
    # $isDryRun = Get-UserConfirmation "Do you want to run in DRY RUN mode (preview only)?" "y"
    # if ($isDryRun) {
    #     Write-Warning "DRY RUN MODE - No files will be actually copied or modified"
    # } else {
    #     Write-Info "LIVE MODE - Files will be copied and modified"
    # }
    
    # Step 3: Scan for categories
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 3: Scanning for available categories..."
    
    # Debug option - uncomment next line to see modlist structure
    # Debug-ModlistStructure -ModlistPath $modlistFullPath
    
    $availableCategories = Get-AvailableCategories -ModlistPath $modlistFullPath
    
    if ($availableCategories.Count -eq 0) {
        Write-Error "No categories found in modlist"
        exit 1
    }
    
    # Step 4: Category selection
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 4: Category selection"
    $selectedCategories = Get-CategorySelection -Categories $availableCategories
    
    if ($selectedCategories.Count -eq 0) {
        Write-Error "No categories selected"
        exit 1
    }
    
    Write-Success "Selected categories: $($selectedCategories -join ', ')"
    Write-Info "Target file extensions: $($FileExtensions -join ', ')"

    # --- MOD SELECTION PER CATEGORY ---
    $modSelectionPrompt = $false 
    $selectedModsByCategory = @{}
    
    # Check preset for mod selection mode
    $modSelectionMode = Get-ConfigValue -Key "modSelectionMode" -DefaultValue "prompt"
    if ($modSelectionMode -eq "manual") {
        $modSelectionPrompt = $true
    } elseif ($modSelectionMode -eq "all") {
        $modSelectionPrompt = $false
    } else {
        # Interactive prompt
        $modSelectionInput = Get-UserChoice "Do you want to manually select mods to copy in each separator or select all?" "n" -ConfigKey "modSelectionMode"
        $modSelectionPrompt = $modSelectionInput -match '^(y|yes|manual)$'
    }
    if ($modSelectionPrompt) {
        foreach ($category in $selectedCategories) {
            # Get mods in this category (replace with your actual function to get mods)
            $mods = Get-ModsInCategory $category $modlistFullPath
            if (-not $mods -or $mods.Count -eq 0) {
                Write-Info "No mods found in category: $category"
                continue
            }
            Write-Host "`nSelect mods to copy for category: $category"
            
            # Interactive checkbox selection method
            $selectedMods = @()
            $selectedIndices = New-Object System.Collections.ArrayList
            
            # Display mods with checkboxes
            for ($i = 0; $i -lt $mods.Count; $i++) {
                Write-Host ("[{0}] [ ] {1}" -f ($i+1), $mods[$i])
            }
            
            # Instructions
            Write-Host "`nSelection commands:" -ForegroundColor Yellow
            Write-Host " - Enter numbers to toggle selection (e.g., 1, 3, 5)"
            Write-Host " - Type 'all' to select all mods"
            Write-Host " - Type 'none' to clear selection"
            Write-Host " - Type 'done' to finish selection"
            Write-Host " - Type 'quit' to skip this category"
            
            # Keep track of selected indices
            $quit = $false
            
            while (-not $quit) {
                # Show current selection status
                if ($selectedIndices.Count -gt 0) {
                    Write-Host "`nCurrently selected: $($selectedIndices.Count) mod(s)" -ForegroundColor Cyan
                } else {
                    Write-Host "`nNo mods selected yet" -ForegroundColor DarkGray
                }
                
                # Get user input
                $input = Read-Host "Selection"
                
                switch -Regex ($input.Trim().ToLower()) {
                    '^all$' {
                        $selectedIndices.Clear()
                        for ($i = 0; $i -lt $mods.Count; $i++) {
                            [void]$selectedIndices.Add($i)
                        }
                        Write-Host "Selected all $($mods.Count) mods" -ForegroundColor Green
                        
                        # Re-draw the list with selected items
                        Write-Host "`nCurrent selection:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $mods.Count; $i++) {
                            $check = if ($selectedIndices -contains $i) { "[X]" } else { "[ ]" }
                            Write-Host ("[{0}] {1} {2}" -f ($i+1), $check, $mods[$i])
                        }
                    }
                    '^none$' {
                        $selectedIndices.Clear()
                        Write-Host "Cleared all selections" -ForegroundColor Yellow
                        
                        # Re-draw the list with no selected items
                        Write-Host "`nCurrent selection:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $mods.Count; $i++) {
                            Write-Host ("[{0}] [ ] {1}" -f ($i+1), $mods[$i])
                        }
                    }
                    '^done$' {
                        $selectedMods = $selectedIndices | ForEach-Object { $mods[$_] }
                        Write-Host "Selection complete: $($selectedMods.Count) mod(s) selected" -ForegroundColor Green
                        $quit = $true
                    }
                    '^quit$' {
                        Write-Warning "Skipping category $category"
                        $selectedMods = @()
                        $quit = $true
                    }
                    '^\d+(?:,\s*\d+)*$' {
                        # Handle comma-separated list of numbers
                        $numbers = $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
                        
                        foreach ($num in $numbers) {
                            $idx = [int]$num - 1
                            
                            if ($idx -ge 0 -and $idx -lt $mods.Count) {
                                # Toggle selection
                                if ($selectedIndices -contains $idx) {
                                    $selectedIndices.Remove($idx)
                                } else {
                                    [void]$selectedIndices.Add($idx)
                                }
                            } else {
                                Write-Warning "Invalid number: $num (must be between 1 and $($mods.Count))"
                            }
                        }
                        
                        # Re-draw the list with updated selections
                        Write-Host "`nCurrent selection:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $mods.Count; $i++) {
                            $check = if ($selectedIndices -contains $i) { "[X]" } else { "[ ]" }
                            Write-Host ("[{0}] {1} {2}" -f ($i+1), $check, $mods[$i])
                        }
                    }
                    default {
                        Write-Warning "Invalid input. Please enter numbers, 'all', 'none', 'done', or 'quit'"
                    }
                }
            }
            
            $selectedModsByCategory[$category] = $selectedMods
            Write-Info ("Selected mods for {0}: {1}" -f $category, ($selectedMods -join ', '))
        }
    } else {
        # Default: select all mods in each category
        foreach ($category in $selectedCategories) {
            $mods = Get-ModsInCategory $category $modlistFullPath
            $selectedModsByCategory[$category] = $mods
        }
    }
    # You can now use $selectedModsByCategory in your file copying logic
    
    # Step 4.5: Cross-Category Conflict Analysis

    Write-Info ""
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 4.5: Cross-Category Conflict Analysis(Optional)"
    Write-Info ""
    Write-Info "This step scans for files that would lose conflicts to higher priority mods in other categories with a higher priority in modlist."
    Write-Info "This is useful to avoid copying files that will be immediately overridden by higher priority mods in other categories."
    Write-Info "You can choose to skip copying these losing files, copy them anyway, or choose specific categories/mods to keep copying."
    Write-Info "This step is optional but can be useful if you intend to compile multiple categories with file conflicts into an archive, would help reduce total file size."
    Write-Info ""
    $enableConflictAnalysis = Get-UserConfirmation "Do you want to perform cross-category conflict analysis?" "n" -ConfigKey "enableConflictAnalysis"
    
    $conflictReport = @{}
    $skipLosingFiles = $false
    
    if ($enableConflictAnalysis) {
        Write-Info "`nStep 4.5: Cross-Category Conflict Analysis"
        Write-Info "Checking for files that would lose conflicts to higher priority mods in other categories..."
        
        $conflictReport = Test-CrossCategoryConflicts -SelectedCategories $selectedCategories -ModsPath $modsFullPath -ModlistPath $modlistFullPath -FileExtensions $FileExtensions -SelectedModsByCategory $selectedModsByCategory
        $hasConflicts = Show-CrossCategoryConflictReport -ConflictReport $conflictReport
        
        if ($hasConflicts) {
            Write-Host ""
            Write-Warning "IMPORTANT: The files shown above would be compiled but immediately overridden by higher priority mods in other categories!"
            Write-Info "This means you'd be wasting time and space copying files that won't actually be used given this modlist order."
            Write-Host ""
            
            # Check if we have a preset value for conflict analysis action
            $presetConflictAction = Get-ConfigValue -Key "ConflictAnalysisAction"
            if ($null -ne $presetConflictAction) {
                $skipChoice = $presetConflictAction
                $actionText = switch ($skipChoice) {
                    "1" { "Skip copying all losing files" }
                    "2" { "Copy all files" }
                    "3" { "Choose categories to exclude from skipping" }
                    "4" { "Choose specific mods to exclude from skipping" }
                    "5" { "Delete all files that lose conflicts" }
                    "6" { "Rename all losing files to '*.copied.mohidden'" }
                    default { "Skip copying all losing files" }
                }
                Write-Host "Conflict analysis action: $actionText " -NoNewline -ForegroundColor Cyan
                Write-Host "(from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
            } else {
                Write-Info "Skip Options:"
                Write-Host "1. Skip Copying all losing files" -ForegroundColor Green
                Write-Host "2. Copy all files" -ForegroundColor Red
                Write-Host "3. Choose categories to exclude from skipping" -ForegroundColor Yellow
                Write-Host "4. Choose specific mods to exclude from skipping" -ForegroundColor Cyan
                Write-Host "5. Delete all files that lose conflicts against mods in other categories" -ForegroundColor DarkRed
                Write-Host "6. Rename all losing files to '*.copied.mohidden'" -ForegroundColor Magenta
                Write-Host ""
                
                $attempts = 0
                while ($attempts -lt 3) {
                    $attempts++
                    
                    if ($attempts -gt 1) {
                        Write-Warning "Attempt $attempts of 3. Please enter 1, 2, 3, 4, 5, or 6."
                    }
                    
                    $skipChoice = Read-Host "Select option (1-6) [1]"
                    
                    if ([string]::IsNullOrWhiteSpace($skipChoice)) {
                        $skipChoice = "1"
                    }
                    
                    if ($skipChoice -match "^[1-6]$") {
                        break
                    } else {
                        Write-Warning "Invalid input '$skipChoice'. Please enter 1, 2, 3, 4, 5, or 6."
                    }
                }
                
                if ($attempts -eq 3 -and -not ($skipChoice -match "^[1-6]$")) {
                    Write-Warning "Max attempts reached. Using default: 1 (Skip all losing files)"
                    $skipChoice = "1"
                }
            }
            
            switch ($skipChoice) {
                "2" {
                    $skipLosingFiles = $false
                    Write-Warning "⚠️  Will copy all files including those that lose conflicts"
                }
                "3" {
                    # Let user choose categories to exclude from skipping
                    $categoriesWithConflicts = @($conflictReport.ConflictsByCategory.Keys)
                    if ($categoriesWithConflicts.Count -gt 1) {
                        Write-Info "`nCategories with conflicts:"
                        for ($i = 0; $i -lt $categoriesWithConflicts.Count; $i++) {
                            $cat = $categoriesWithConflicts[$i]
                            $conflictCount = $conflictReport.ConflictsByCategory[$cat].Count
                            Write-Host "  $($i + 1). $cat ($conflictCount losing files)" -ForegroundColor White
                        }
                        Write-Host ""
                        Write-Info "Select categories where you want to COPY losing files anyway:"
                        Write-Info "(Enter numbers separated by commas, 'none' to skip all, or 'skip' to use default)"
                        
                        $categoriesToKeepCopying = Get-SelectionWithRetry -Prompt "Categories to keep copying" -ValidItems $categoriesWithConflicts -ItemType "categories"
                        
                        if ($categoriesToKeepCopying.Count -gt 0) {
                            # Store the categories we should NOT skip
                            $conflictReport.CategoriesExcludedFromSkipping = $categoriesToKeepCopying
                            Write-Success "✅ Will copy losing files from: $($categoriesToKeepCopying -join ', ')"
                            Write-Info "✅ Will skip losing files from other categories"
                        } else {
                            Write-Info "Using default behavior - will skip all losing files"
                        }
                        
                        $skipLosingFiles = $true
                    } else {
                        Write-Warning "Only one category has conflicts. Using normal skip mode."
                        $skipLosingFiles = $true
                    }
                }
                "4" {
                    # Let user choose specific mods to exclude from skipping
                    $allLosingMods = @()
                    foreach ($category in $conflictReport.ConflictsByCategory.Keys) {
                        $conflicts = $conflictReport.ConflictsByCategory[$category]
                        $categoryMods = $conflicts | Select-Object -ExpandProperty LosingMod -Unique
                        foreach ($mod in $categoryMods) {
                            if ($allLosingMods -notcontains $mod) {
                                $allLosingMods += $mod
                            }
                        }
                    }
                    
                    if ($allLosingMods.Count -gt 0) {
                        Write-Info "`nMods with losing files:"
                        for ($i = 0; $i -lt $allLosingMods.Count; $i++) {
                            $mod = $allLosingMods[$i]
                            $modConflictCount = 0
                            foreach ($category in $conflictReport.ConflictsByCategory.Keys) {
                                $modConflictCount += ($conflictReport.ConflictsByCategory[$category] | Where-Object { $_.LosingMod -eq $mod }).Count
                            }
                            Write-Host "  $($i + 1). $mod ($modConflictCount losing files)" -ForegroundColor White
                        }
                        Write-Host ""
                        Write-Info "Select mods where you want to COPY losing files anyway:"
                        Write-Info "(Enter numbers separated by commas, 'none' to skip all, or 'skip' to use default)"
                        
                        $modsToKeepCopying = Get-SelectionWithRetry -Prompt "Mods to keep copying" -ValidItems $allLosingMods -ItemType "mods"
                        
                        if ($modsToKeepCopying.Count -gt 0) {
                            # Store the mods we should NOT skip
                            $conflictReport.ModsExcludedFromSkipping = $modsToKeepCopying
                            Write-Success "✅ Will copy losing files from: $($modsToKeepCopying -join ', ')"
                            Write-Info "✅ Will skip losing files from other mods"
                        } else {
                            Write-Info "Using default behavior - will skip all losing files"
                        }
                        
                        $skipLosingFiles = $true
                    } else {
                        Write-Warning "No mods with losing files found. Using normal skip mode."
                        $skipLosingFiles = $true
                    }
                }
                "5" {
                    # Delete all files that lose conflicts against mods in other categories
                    Write-Warning "⚠️  Will DELETE all losing files from the file system!"
                    Write-Info "This will permanently remove files that would lose conflicts to higher priority mods in other categories."
                    if (Get-UserConfirmation "Are you sure you want to DELETE all losing files? This cannot be undone!" "n") {
                        $conflictReport.DeleteLosingFiles = $true
                        $skipLosingFiles = $true
                        Write-Success "✅ Will delete all losing files"
                    } else {
                        Write-Info "Cancelled deletion. Using default behavior - will skip all losing files"
                        $skipLosingFiles = $true
                    }
                }
                "6" {
                    # Rename all losing files to *.copied.mohidden
                    Write-Info "Will rename all losing files by adding '.copied.mohidden' extension"
                    Write-Info "This will preserve the files but hide them from Mod Organizer 2"
                    if (Get-UserConfirmation "Rename all losing files to '*.copied.mohidden'?" "y") {
                        $conflictReport.RenameLosingFiles = $true
                        $skipLosingFiles = $true
                        Write-Success "✅ Will rename all losing files to '*.copied.mohidden'"
                    } else {
                        Write-Info "Cancelled renaming. Using default behavior - will skip all losing files"
                        $skipLosingFiles = $true
                    }
                }
                default {
                    $skipLosingFiles = $true
                    Write-Success "✅ Will skip all losing files - only copying files that will actually be used"
                }
            }
        }
    } else {
        Write-Info "Skipping cross-category conflict analysis"
    }
    
    # Step 5: Copy files
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 5: File consolidation"
    if (-not $isDryRun -and -not (Get-UserConfirmation "Proceed with file consolidation?" "y" -ConfigKey "proceedWithConsolidation")) {
        Write-Info "Returning to category selection..."
        # Step 4: Category selection (repeat)
        $selectedCategories = Get-CategorySelection -Categories $availableCategories
        if ($selectedCategories.Count -eq 0) {
            Write-Error "No categories selected"
            exit 1
        }
        Write-Success "Selected categories: $($selectedCategories -join ', ')"
        Write-Info "Target file extensions: $($FileExtensions -join ', ')"
    }
    
    # Pass $selectedModsByCategory to your copy function if you want to filter by selected mods
    $stats = Copy-FilesToCompilation -Categories $selectedCategories -ModsPath $modsFullPath -OutputPath $outputFullPath -ModlistPath $modlistFullPath -FileExtensions $FileExtensions -DryRun $isDryRun -ConflictReport $conflictReport -SkipLosingFiles $skipLosingFiles -SelectedModsByCategory $selectedModsByCategory
    
    Show-CopyResults -Stats $stats -ConflictReport $conflictReport -SkippedLosingFiles $skipLosingFiles
    
    if ($isDryRun) {
        Write-Warning "`nDRY RUN COMPLETED - No files were actually copied"
        Write-Info "Run the script again without dry run mode to perform actual consolidation"
        exit 0
    }
    
    # Step 6: Handle original files
    # Write-Host ("=" * 30) -ForegroundColor Magenta
    # Original file handling moved to Step 7 (Workflow Configuration)
    
    # Step 7: Workflow Configuration (Global Settings)
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`nStep 7: Workflow Configuration (Global Settings)"
    Write-Info "Configure options that will apply to all selected categories"
    Write-Host ""
    
    # BSA Archive Creation Settings
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Write-Info "`n"
    $createESP = $true
    $createOverrides = $true
    $createArchives = Get-UserConfirmation "Do you want to create BSA archives from compiled files?" "y" -ConfigKey "createArchives"
    if ($createArchives) {
         $createESP = Get-UserConfirmation "Create dummy ESP plugins to load the BSA archives? (recommended)" "y" -ConfigKey "createESP"
    }
    if ($createArchives) {
        $createOverrides = Get-UserConfirmation "Do you want to create .override files for BSA archives? (recommended)" "y" -ConfigKey "createOverrides"
    }
    
    $automaticMode = $true
    $compressArchives = $false
    $gameFormat = "fnv"

    
    if ($createArchives) {
        Write-Info "`nArchive Creation Options:"
        Write-Info "1. Automatic (recommended) - Uses BSArch command-line directly"
        Write-Info "2. Manual - Provides instructions for manual creation"
        Write-Host ""
        
        $archiveMode = Get-UserChoice "Select archive creation mode (1-2)" "1" -ConfigKey "archiveMode"
        $automaticMode = ($archiveMode -ne "2")
        
        if ($automaticMode) {
            Write-Host ""
            $compressArchives = Get-UserConfirmation "Enable archive compression? (reduces size but may cause issues with sounds)" "n" -ConfigKey "compressArchives"
            
            Write-Host ""
            Write-Info "Game format options:"
            Write-Info "1. fnv (Fallout New Vegas) - Recommended"
            Write-Info "2. fo3 (Fallout 3)"
            Write-Info "3. tes5 (Skyrim LE)"
            Write-Host ""
            
            $gameFormatChoice = Get-UserChoice "Select game format (1-3)" "1" -ConfigKey "gameFormat"
            $gameFormat = switch ($gameFormatChoice) {
                "2" { "fo3" }
                "3" { "tes5" }
                default { "fnv" }
            }
            
            Write-Info "Selected format: $gameFormat"
            if ($compressArchives) {
                Write-Warning "Compression enabled - ensure no sound/voice files are included!"
            }
        }
    }
        

    
    # MO2 Integration Settings
    Write-Host ""
    $moveCompiled = $false
    $moveArchives = $false
    <# $createESP = $true #>
    $deleteOriginalArchives = $true
    
    # Original File Handling Settings
    $originalFileAction = 3 # Default to renaming originals to .copied.mohidden
    $moveToBackup = $false  # Default to not moving to backup
    
    if (-not $isDryRun -and $global:CopiedFiles.Count -gt 0) {
        # Check if we have a preset value for original file action
        $presetOriginalFileAction = Get-ConfigValue -Key "originalFileAction"
        if ($null -ne $presetOriginalFileAction) {
            $originalFileAction = [int]$presetOriginalFileAction
            Write-Host ("=" * 30) -ForegroundColor Magenta
            Write-Info "`nOriginal File Handling Options:"
            Write-Info "You have copied $($global:CopiedFiles.Count) files."
            $actionText = switch ($originalFileAction) {
                1 { "Do nothing (keep originals as-is)" }
                2 { "Delete original files" }
                3 { "Rename originals to .copied.mohidden" }
                default { "Rename originals to .copied.mohidden" }
            }
            Write-Host "Selected action: $actionText " -NoNewline -ForegroundColor Cyan
            Write-Host "(from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
            
            # Check preset for moveToBackup setting
            if ($originalFileAction -eq 3) {
                $presetMoveToBackup = Get-ConfigValue -Key "moveToBackup"
                if ($null -ne $presetMoveToBackup) {
                    $moveToBackup = $presetMoveToBackup
                    $backupText = if ($moveToBackup) { "Yes" } else { "No" }
                    Write-Host "Move to backup: $backupText " -NoNewline -ForegroundColor Cyan
                    Write-Host "(from preset: $($global:ConfigPreset.name))" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Host ("=" * 30) -ForegroundColor Magenta
            Write-Info "`nOriginal File Handling Options:"
            Write-Info "You have copied $($global:CopiedFiles.Count) files. What would you like to do with the original files?"
            Write-Host ""
            Write-Host "1. Do nothing (keep originals as-is)" -ForegroundColor Green
            Write-Host "2. Delete original files" -ForegroundColor Red
            Write-Host "3. Rename originals to .copied.mohidden" -ForegroundColor Yellow
            Write-Host ""
            
            $attempts = 0
            while ($attempts -lt 3) {
                $attempts++
                
                if ($attempts -gt 1) {
                    Write-Warning "Attempt $attempts of 3. Please enter 1, 2, or 3."
                }
                
                $originalFileChoice = Read-Host "Select option (1-3) [3]"
                
                if ([string]::IsNullOrWhiteSpace($originalFileChoice)) {
                    $originalFileAction = 3
                    break
                } elseif ($originalFileChoice -match "^[1-3]$") {
                    $originalFileAction = [int]$originalFileChoice
                    break
                } else {
                    Write-Warning "Invalid input '$originalFileChoice'. Please enter 1, 2, or 3."
                }
            }
            
            if ($attempts -eq 3 -and -not ($originalFileChoice -match "^[1-3]$")) {
                Write-Warning "Max attempts reached. Using default: 3 (Rename to .copied.mohidden)"
                $originalFileAction = 3
            }
            
            # If renaming, ask about moving to backup
            if ($originalFileAction -eq 3) {
                Write-Host ""
                $moveToBackup = Get-UserConfirmation "Do you want to move renamed files to backup location (mods-backup folder)?" "y" -ConfigKey "moveToBackup"
            }
        }
    }
    
    if (-not $isDryRun) {
        $moveCompiled = Get-UserConfirmation "Do you want to install compiled mod folders into MO2?" "y" -ConfigKey "moveCompiled"
        
        if ($createArchives) {
            $moveArchives = Get-UserConfirmation "Do you want to install archives into MO2?" "y" -ConfigKey "moveArchives"
        }
    }
    
    # Cleanup Settings
    Write-Host ""
    $cleanup = $false
    if (-not $isDryRun) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        $cleanup = Get-UserConfirmation "Do you want to cleanup compiled files and archives from script-archiver folder after processing?" "y" -ConfigKey "cleanup"
    }
    
    Write-Host ""
    Write-Success "Configuration complete! Processing will now begin..."
    Write-Host ""
    

    
    # Step 8: BSA Archive Creation
    $archivesCreated = $false
    if ($createArchives) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        Write-Info "`nStep 8: BSA Archive Creation"
        $archivesCreated = Create-BSAArchives -Categories $selectedCategories -OutputPath $outputFullPath -ArchivePath $ArchivePath -BSArchPath $BSArchPath -AutomaticMode $automaticMode -CompressArchives $compressArchives -GameFormat $gameFormat
        
        # Create .override files if archives were created
        if ($archivesCreated -and $createOverrides) {
            Write-Host ("=" * 30) -ForegroundColor Magenta
            Write-Info "`nStep 8a: Override File Creation"
            Create-OverrideFiles -Categories $selectedCategories -ArchivePath $ArchivePath
        }
    }
    
    # Step 9: Move Compiled Mods to MO2 (Optional)
    if ($moveCompiled -and (-not $isDryRun)) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        Write-Info "`nStep 9: Move Compiled Mods to MO2"
        Write-Info "`n=== MOVING COMPILED MODS TO MO2 ==="
        foreach ($category in $selectedCategories) {
            $compiledPath = Join-Path $outputFullPath "$category`_Compiled"
            if (Test-Path $compiledPath) {
                $result = Move-CompiledFolderToMods -CompiledFolderPath $compiledPath -CategoryName $category -ModsPath $modsFullPath -ModlistPath $modlistFullPath
                if ($result) {
                    Write-Success "✅ '$category Compiled' moved to MO2 successfully!"
                } else {
                    Write-Error "❌ Failed to move '$category Compiled' to MO2"
                }
            } else {
                Write-Warning "⚠️ Compiled folder not found: $compiledPath"
            }
        }
    } else {
        Write-Info "Skipping compiled mod integration."
    }
    
    # Step 10: Move Archive Mods to MO2 (Optional)
    if ($createArchives -and $archivesCreated -and $moveArchives -and (-not $isDryRun)) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        Write-Info "`nStep 10: Move Archive Mods to MO2"
        Write-Info "`n=== MOVING ARCHIVE MODS TO MO2 ==="
        
        # Get all BSA files from the archive directory
        $allBSAFiles = Get-ChildItem -Path $archiveFullPath -Filter "*.bsa" -ErrorAction SilentlyContinue
        
        if ($allBSAFiles.Count -eq 0) {
            Write-Warning "⚠️ No BSA archives found in: $archiveFullPath"
        } else {
            Write-Info "Found $($allBSAFiles.Count) BSA archive(s) to process"
            
            # Group archives by category (handle split archives)
            $archivesByCategory = @{}
            foreach ($bsaFile in $allBSAFiles) {
                $baseName = $bsaFile.BaseName
                
                # For all archives derived from the same category, we'll put them all in one mod folder
                $baseCategory = ""
                
                # Extract the base category name for all archive types
                if ($baseName -match "^(.+ - .+) - (meshes|textures|sound|animations?) - Part \d+$") {
                    # Type + part split (e.g. "Visuals - Textures - textures - Part 1")
                    $baseCategory = $matches[1]
                } elseif ($baseName -match "^(.+ - .+) - (meshes|textures|sound|animations?)$") {
                    # Type split (e.g. "Visuals - Textures - textures")
                    $baseCategory = $matches[1]
                } elseif ($baseName -match "^(.+) - Part \d+$") {
                    # Simple part split (e.g. "Visuals - Textures - Part 1")
                    $baseCategory = $matches[1]
                } else {
                    # No split pattern, use as is
                    $baseCategory = $baseName
                }
                
                # Use the base category as the group key for all archive types
                $groupKey = $baseCategory
                
                if (-not $archivesByCategory.ContainsKey($groupKey)) {
                    $archivesByCategory[$groupKey] = @{
                        BaseCategory = $baseCategory
                        DisplayName = $baseCategory # Use the base category name for the display name
                        Archives = @()
                    }
                }
                $archivesByCategory[$groupKey].Archives += $bsaFile
            }
            
            # For each base category, collect all archives
            $baseCategories = @{}
            foreach ($groupKey in $archivesByCategory.Keys) {
                $categoryInfo = $archivesByCategory[$groupKey]
                $baseCategory = $categoryInfo.BaseCategory
                
                if (-not $baseCategories.ContainsKey($baseCategory)) {
                    $baseCategories[$baseCategory] = @()
                }
                $baseCategories[$baseCategory] += $categoryInfo.Archives
            }
            
            # Process each base category with all its archives together
            foreach ($baseCategory in $baseCategories.Keys) {
                $allArchives = $baseCategories[$baseCategory]
                
                Write-Host ("=" * 30) -ForegroundColor Magenta
                Write-Info "`nProcessing archives for category: $baseCategory"
                Write-Info "  Archives: $($allArchives.Name -join ', ')"
                
                $result = Move-BSAArchivesToMods -Archives $allArchives -CategoryName $baseCategory -ModsPath $modsFullPath -ModlistPath $modlistFullPath -CreateESP $createESP -DeleteOriginalArchive $deleteOriginalArchives -ParentCategory $baseCategory
                if ($result) {
                    Write-Success "✅ '$baseCategory Archive' moved to MO2 successfully!"
                } else {
                    Write-Error "❌ Failed to move '$baseCategory Archive' to MO2"
                }
            }
        }
    } else {
        Write-Info "Skipping archive mod integration."
    }
    
    # Step 11: Handle original files based on user's configuration
    if (-not $isDryRun -and $global:CopiedFiles.Count -gt 0) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        Write-Info "`nStep 11: Handle Original Files"
        Handle-OriginalFiles -CopiedFiles $global:CopiedFiles -Action $originalFileAction -MoveToBackup $moveToBackup -ModlistPath $modlistFullPath -BackupPath ".\mods-backup"
    }

    # Step 12: Cleanup Script-Archiver Folders (Optional)
    if (-not $isDryRun) {
        Write-Host ("=" * 30) -ForegroundColor Magenta
        Write-Info "`nStep 12: Cleanup Script-Archiver Folder (Optional)"
        
        if ($cleanup) {
            Write-Info "`n=== CLEANING UP SCRIPT-ARCHIVER FOLDER ==="
            
            # Remove compiled folders
            if (Test-Path $outputFullPath) {
                Write-Info "Removing compiled folders..."
                Remove-Item -Path $outputFullPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "✅ Compiled folders removed"
            }
            
            # Remove archive folders
            if (Test-Path $archiveFullPath) {
                Write-Info "Removing archive folders..."
                Remove-Item -Path $archiveFullPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "✅ Archive folders removed"
            }
            
            Write-Success "🧹 Script-archiver folder cleaned up!"
        } else {
            Write-Info "Keeping compiled files and archives in script-archiver folder."
        }
    }
    
    # Step 12: Final summary
    Write-Host ("=" * 30) -ForegroundColor Magenta
    Show-FinalSummary -Stats $stats -Categories $selectedCategories -ArchivesCreated $archivesCreated
    
    Write-Success "`nInteractive consolidation completed successfully!"
    Write-Host ""
    Read-Host "Press Enter to exit"
}

# Execute main function
try {
    Main
}
catch {
    Write-Error "Critical error: $($_.Exception.Message)"
    Read-Host "Press Enter to exit"
    Write-Error $_.ScriptStackTrace
    exit 1
}

# Script complete
