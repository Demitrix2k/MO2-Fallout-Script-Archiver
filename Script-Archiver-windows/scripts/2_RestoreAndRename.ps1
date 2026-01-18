#=======================================================================
# MO2 BACKUP RESTORE AND RENAME SCRIPT
# Version 2.0
#
# Author: Demitrix@nexusmods.com
# Date: December 24, 2025
#
# This script restores backed-up files to MO2's mods folder and removes
# the .copied.mohidden extension to restore original filenames.
#
# The script will:
# 1. Select categories from mods-backup folder
# 2. Restore files to their original mod locations
# 3. Remove .copied.mohidden extension automatically
# 4. Clean up empty category folders from backup
#=======================================================================

# Define the source and destination paths
$SourcePath = ".\mods-backup" # <--- IMPORTANT: Backup folder (categorized structure expected)
$DestinationPath = "..\mods"  # <--- IMPORTANT: MO2 mods folder
$FileExtension = "*.copied.mohidden"          # <--- File filter

# Configuration
$SCRIPT_VERSION = "2.0"
$SEPARATOR_SUFFIX = "_separator"
$ProfilesBasePath = "..\profiles"
$dryRun = $false  # Set to $true for dry run mode (preview only)

# --- Script Starts Here ---

# Helper functions for color output
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Header { param([string]$Message) Write-Host $Message -ForegroundColor Magenta }

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
        }
    }
    
    return ,$profiles
}

function Select-Profile {
    param([string]$ProfilesBasePath = "..\profiles")
    
    Write-Info "Scanning for available MO2 profiles..."
    $profiles = Get-AvailableProfiles -ProfilesBasePath $ProfilesBasePath
    
    if ($profiles.Count -eq 0) {
        Write-Error "No valid profiles found in $ProfilesBasePath"
        return $null
    }
    
    if ($profiles.Count -eq 1) {
        Write-Success "Found 1 profile: '$($profiles[0].Name)'"
        return $profiles[0].ModlistPath
    }
    
    Write-Success "Found $($profiles.Count) available profiles:"
    Write-Host ""
    
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  $($i + 1). '$($profiles[$i].Name)'" -ForegroundColor White
    }
    
    Write-Host ""
    $selection = Read-Host "Select profile number (1-$($profiles.Count))"
    
    if ($selection -match "^\d+$") {
        $idx = [int]$selection - 1
        if ($idx -ge 0 -and $idx -lt $profiles.Count) {
            return $profiles[$idx].ModlistPath
        }
    }
    
    Write-Error "Invalid selection"
    return $null
}

function Show-Header {
    Clear-Host
    Write-Header "=== MO2 RESTORE AND RENAME SYSTEM ==="
    Write-Header "Version $SCRIPT_VERSION - Restore and Rename Files from Backup"
    Write-Host ""
}

function Get-UserConfirmation {
    param(
        [string]$Question,
        [string]$DefaultAnswer = "y"
    )
    
    $prompt = "$Question (y/n) [$DefaultAnswer]: "
    $response = Read-Host $prompt
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        $response = $DefaultAnswer
    }
    
    return $response.ToLower() -eq "y"
}

function Get-CategoriesFromBackup {
    param([string]$BackupPath)
    
    Write-Info "Scanning backup folder for categories..."
    
    if (-not (Test-Path $BackupPath)) {
        Write-Error "Backup path not found: $BackupPath"
        return @()
    }
    
    $categories = @()
    $categoryDirs = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue
    
    foreach ($dir in $categoryDirs) {
        # Check if this directory contains mod folders
        $modFolders = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
        if ($modFolders.Count -gt 0) {
            # Count files in this category
            $fileCount = (Get-ChildItem -Path $dir.FullName -Filter $FileExtension -Recurse -File -ErrorAction SilentlyContinue).Count
            
            $categories += @{
                Name = $dir.Name
                Path = $dir.FullName
                ModCount = $modFolders.Count
                FileCount = $fileCount
            }
        }
    }
    
    return $categories
}

function Show-Categories {
    param([array]$Categories)
    
    Write-Host ""
    Write-Info "Available categories in backup:"
    Write-Host ""
    
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        $cat = $Categories[$i]
        Write-Host "  $($i + 1). $($cat.Name) - $($cat.ModCount) mod(s), $($cat.FileCount) file(s)" -ForegroundColor White
    }
    
    Write-Host ""
}

function Get-CategorySelection {
    param([array]$Categories)
    
    Show-Categories -Categories $Categories
    
    Write-Info "Select categories to restore (comma-separated numbers, or 'all'):"
    $selection = Read-Host "Selection"
    
    if ($selection.ToLower() -eq "all") {
        return $Categories
    }
    
    $selectedCategories = @()
    $indices = $selection.Split(",") | ForEach-Object { $_.Trim() }
    
    foreach ($index in $indices) {
        if ($index -match "^\d+$") {
            $idx = [int]$index - 1
            if ($idx -ge 0 -and $idx -lt $Categories.Count) {
                $selectedCategories += $Categories[$idx]
            }
        }
    }
    
    return $selectedCategories
}

function Restore-FilesFromBackup {
    param(
        [array]$Categories,
        [string]$BackupPath,
        [string]$DestinationPath,
        [bool]$DryRun = $false
    )
    
    $stats = @{
        TotalFiles = 0
        RestoredFiles = 0
        RenamedFiles = 0
        FailedFiles = 0
    }
    
    Write-Info "`n=== RESTORING FILES FROM BACKUP ==="
    
    # Count total files first
    foreach ($category in $Categories) {
        $files = Get-ChildItem -Path $category.Path -Filter $FileExtension -Recurse -File -ErrorAction SilentlyContinue
        $stats.TotalFiles += $files.Count
    }
    
    if ($stats.TotalFiles -eq 0) {
        Write-Warning "No .copied.mohidden files found in selected categories"
        return $stats
    }
    
    Write-Info "Found $($stats.TotalFiles) file(s) to restore"
    
    if ($DryRun) {
        Write-Warning "[DRY RUN MODE] - Preview only, no files will be modified"
    }
    
    # Progress bar setup
    $showProgressBar = $stats.TotalFiles -gt 20
    $progressParams = @{
        Activity = "Restoring and renaming files"
        Status = "0% Complete"
        PercentComplete = 0
    }
    
    $processedCount = 0
    $lastProgressUpdate = 0
    $progressUpdateInterval = [Math]::Max(1, [Math]::Floor($stats.TotalFiles / 100))
    
    # Pre-create destination directories
    if (-not $DryRun) {
        Write-Info "Pre-creating directory structure..."
        $directoriesToCreate = @{}
        
        foreach ($category in $Categories) {
            $files = Get-ChildItem -Path $category.Path -Filter $FileExtension -Recurse -File -ErrorAction SilentlyContinue
            
            foreach ($file in $files) {
                # Get relative path from backup root (not category folder)
                # File path: BackupPath/CategoryName/ModName/file.copied.mohidden
                # We need: BackupPath as base, parse CategoryName/ModName/file
                $backupRoot = Split-Path $category.Path -Parent
                $relativePath = $file.FullName.Substring($backupRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                
                # Split: [0]=Category, [1]=ModName, [2+]=content path
                $pathParts = $relativePath.Split([IO.Path]::DirectorySeparatorChar)
                
                if ($pathParts.Length -lt 2) { continue }
                
                $modName = $pathParts[1]
                
                # Extract content path (everything after mod folder)
                $contentPath = if ($pathParts.Length -gt 2) {
                    [string]::Join([IO.Path]::DirectorySeparatorChar, $pathParts[2..($pathParts.Length - 1)])
                } else {
                    $file.Name
                }
                
                # Remove .copied.mohidden extension from filename
                $contentPath = $contentPath -replace '\.copied\.mohidden$', ''
                
                # Build destination: mods/ModName/content (skip category)
                $destPath = Join-Path $DestinationPath (Join-Path $modName $contentPath)
                $destDir = Split-Path $destPath -Parent
                $directoriesToCreate[$destDir] = $true
            }
        }
        
        $createdDirs = 0
        foreach ($dir in $directoriesToCreate.Keys) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $createdDirs++
            }
        }
        Write-Success "Pre-created $createdDirs directories"
    }
    
    # Process files
    foreach ($category in $Categories) {
        Write-Host ""
        Write-Info "Processing category: $($category.Name)"
        
        $files = Get-ChildItem -Path $category.Path -Filter $FileExtension -Recurse -File -ErrorAction SilentlyContinue
        
        foreach ($file in $files) {
            $processedCount++
            
            # Update progress
            if ($showProgressBar -and ($processedCount - $lastProgressUpdate) -ge $progressUpdateInterval) {
                $percentComplete = [math]::Min(100, [math]::Round(($processedCount / $stats.TotalFiles) * 100))
                $progressParams.Status = "$percentComplete% Complete ($processedCount/$($stats.TotalFiles) files)"
                $progressParams.PercentComplete = $percentComplete
                Write-Progress @progressParams
                $lastProgressUpdate = $processedCount
            }
            
            try {
                # Get relative path from backup root (matching 4_RestoreBackups.ps1 logic)
                $backupRoot = Split-Path $category.Path -Parent
                $relativePath = $file.FullName.Substring($backupRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                
                # Split: [0]=Category, [1]=ModName, [2+]=content path
                $pathParts = $relativePath.Split([IO.Path]::DirectorySeparatorChar)
                
                if ($pathParts.Length -lt 2) {
                    Write-Warning "Skipping invalid path: $relativePath"
                    continue
                }
                
                $categoryName = $pathParts[0]
                $modName = $pathParts[1]
                
                # Extract content path (everything after mod folder)
                $contentPath = if ($pathParts.Length -gt 2) {
                    [string]::Join([IO.Path]::DirectorySeparatorChar, $pathParts[2..($pathParts.Length - 1)])
                } else {
                    $file.Name
                }
                
                # Remove .copied.mohidden extension
                $contentPath = $contentPath -replace '\.copied\.mohidden$', ''
                
                # Build destination: mods/ModName/content (category is removed)
                $destPath = Join-Path $DestinationPath (Join-Path $modName $contentPath)
                
                if ($DryRun) {
                    if ($processedCount -le 50) {
                        Write-Host "  [DRY RUN] Would restore: $modName\$contentPath" -ForegroundColor DarkGray
                    }
                    $stats.RestoredFiles++
                } else {
                    # Move and rename file (remove .copied.mohidden)
                    Move-Item -Path $file.FullName -Destination $destPath -Force
                    $stats.RestoredFiles++
                    
                    if ($stats.TotalFiles -le 50) {
                        Write-Host "  Restored: $modName\$contentPath" -ForegroundColor DarkGreen
                    }
                }
            } catch {
                Write-Warning "  Failed to restore: $($file.Name) - $($_.Exception.Message)"
                $stats.FailedFiles++
            }
        }
    }
    
    if ($showProgressBar) {
        Write-Progress -Activity $progressParams.Activity -Completed
    }
    
    return $stats
}

function Show-RestoreResults {
    param([hashtable]$Stats, [bool]$DryRun)
    
    Write-Host ""
    Write-Info "=== RESTORE SUMMARY ==="
    Write-Info "Total files found: $($Stats.TotalFiles)"
    
    if ($DryRun) {
        Write-Info "Files that would be restored: $($Stats.RestoredFiles)"
    } else {
        Write-Success "Files restored: $($Stats.RestoredFiles)"
        if ($Stats.FailedFiles -gt 0) {
            Write-Warning "Failed files: $($Stats.FailedFiles)"
        }
    }
}

function Remove-EmptyCategoryFolders {
    param(
        [array]$Categories,
        [string]$BackupPath,
        [bool]$DryRun = $false
    )
    
    Write-Host ""
    Write-Info "=== CLEANING UP BACKUP FOLDERS ==="
    
    $removedCount = 0
    
    foreach ($category in $Categories) {
        $categoryPath = $category.Path
        
        if (Test-Path $categoryPath) {
            # Check if category folder is empty or only contains empty subfolders
            $remainingFiles = Get-ChildItem -Path $categoryPath -Recurse -File -ErrorAction SilentlyContinue
            
            if ($remainingFiles.Count -eq 0) {
                if ($DryRun) {
                    Write-Host "  [DRY RUN] Would remove empty category: $($category.Name)" -ForegroundColor DarkGray
                    $removedCount++
                } else {
                    try {
                        Remove-Item -Path $categoryPath -Recurse -Force -ErrorAction Stop
                        Write-Success "  Removed empty category folder: $($category.Name)"
                        $removedCount++
                    } catch {
                        Write-Warning "  Failed to remove category folder: $($category.Name) - $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Info "  Category '$($category.Name)' still contains $($remainingFiles.Count) file(s), keeping folder"
            }
        }
    }
    
    if ($removedCount -gt 0) {
        if ($DryRun) {
            Write-Info "[DRY RUN] Would remove $removedCount empty category folder(s)"
        } else {
            Write-Success "✅ Removed $removedCount empty category folder(s) from backup"
        }
    } else {
        Write-Info "No empty category folders to remove"
    }
}

# Main execution function
function Main {
    Show-Header
    
    Write-Info "This script will restore .copied.mohidden files from backup and rename them back to original names."
    Write-Host ""
    
    # Check if backup folder exists
    $backupPathResolved = if ([System.IO.Path]::IsPathRooted($SourcePath)) { 
        $SourcePath 
    } else { 
        Join-Path (Get-Location) $SourcePath 
    }
    
    if (-not (Test-Path $backupPathResolved)) {
        Write-Error "Backup folder not found: $backupPathResolved"
        Write-Info "Make sure you have backed up files using the Main Compiler script first."
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    # Get categories from backup
    $categories = Get-CategoriesFromBackup -BackupPath $backupPathResolved
    
    if ($categories.Count -eq 0) {
        Write-Error "No categories found in backup folder"
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    # Category selection
    $selectedCategories = Get-CategorySelection -Categories $categories
    
    if ($selectedCategories.Count -eq 0) {
        Write-Error "No categories selected"
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Success "Selected $($selectedCategories.Count) category(ies) to restore"
    Write-Host ""
    
    # Ask for dry run
    #$dryRun = Get-UserConfirmation "Do you want to run in DRY RUN mode (preview only)?" "n"
    
    if ($dryRun) {
        Write-Warning "DRY RUN MODE - No files will be modified"
    } else {
        Write-Info "LIVE MODE - Files will be restored and renamed"
    }
    
    Write-Host ""
    
    # Confirm before proceeding
    if (-not $dryRun) {
        $proceed = Get-UserConfirmation "Proceed with file restoration?" "y"
        if (-not $proceed) {
            Write-Info "Operation cancelled"
            Read-Host "Press Enter to exit"
            exit 0
        }
    }
    
    # Resolve destination path
    $destPathResolved = if ([System.IO.Path]::IsPathRooted($DestinationPath)) { 
        $DestinationPath 
    } else { 
        Join-Path (Get-Location) $DestinationPath 
    }
    
    # Restore files
    $stats = Restore-FilesFromBackup -Categories $selectedCategories -BackupPath $backupPathResolved -DestinationPath $destPathResolved -DryRun $dryRun
    
    # Show results
    Show-RestoreResults -Stats $stats -DryRun $dryRun
    
    # Cleanup empty category folders after successful restore
    if ($stats.RestoredFiles -gt 0) {
        Remove-EmptyCategoryFolders -Categories $selectedCategories -BackupPath $backupPathResolved -DryRun $dryRun
    }
    
    if ($dryRun) {
        Write-Host ""
        Write-Info "This was a dry run. Run the script again without dry run mode to actually restore files."
    } else {
        Write-Host ""
        Write-Success "✅ Restore operation completed successfully!"
    }
    
    Write-Host ""
    Read-Host "Press Enter to exit"
}

# Execute main function
try {
    Main
} catch {
    Write-Error "Critical error: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    Read-Host "Press Enter to exit"
    exit 1
}
