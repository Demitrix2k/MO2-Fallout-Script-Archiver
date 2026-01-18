# === Script Archiver Runner ===

$SCRIPT1_PATH = ".\scripts\1_MainCompiler.ps1"
$SCRIPT1_DESC = 'Compile and Archive Mods Within Categories - Consolidate mods into archives with automatic backup'

$SCRIPT2_PATH = ".\scripts\2_RestoreAndRename.ps1"
$SCRIPT2_DESC = 'Rename and Restore Backed Up Mods Within Categories - Restore files from backup and remove .copied.mohidden extension'

$SCRIPT3_DESC = 'Exit                   - Close the script archiver utility'

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "Which script do you want to run?" -ForegroundColor Magenta
    Write-Host "====================================" -ForegroundColor Magenta
    Write-Host "`n"
    Write-Host "1. $SCRIPT1_DESC" -ForegroundColor Cyan
    Write-Host "2. $SCRIPT2_DESC" -ForegroundColor Green
    Write-Host "3. $SCRIPT3_DESC" -ForegroundColor Red
    Write-Host "`n"
}

do {
    Show-Menu
    $choice = Read-Host "Enter your choice [1-2]"

    switch ($choice) {
        "1" {
            Write-Host "`nRunning: $SCRIPT1_DESC" -ForegroundColor Green
            & pwsh -ExecutionPolicy Bypass -File $SCRIPT1_PATH
            break
			
			
            # Write-Host "`nRunning: $SCRIPT1_DESC" -ForegroundColor Green
            # Write-Host ""
            # Write-Host "Choose how to run Main Compiler:" -ForegroundColor Magenta
            # Write-Host "  1. With configuration presets" -ForegroundColor Cyan
            # Write-Host "`n"

            # Write-Host "`n"
            # Write-Host "`n"
            # Write-Host "  2. Classic interactive mode" -ForegroundColor Yellow
            # Write-Host "`n"
            # Write-Host ""
            # Write-Host "See config-presets.json for available presets." -ForegroundColor Cyan
            # Write-Host "Preset mode will use preset values and minimize prompts." -ForegroundColor Cyan
            # Write-Host "Interactive mode will prompt for all settings." -ForegroundColor Yellow

            # $runMode = Read-Host "Select mode (1-2) [1]"
            
            # if ([string]::IsNullOrWhiteSpace($runMode) -or $runMode -eq "1") {
                # Run with preset system
                # & pwsh -ExecutionPolicy Bypass -File $SCRIPT1_PATH
            # } else {
                # Run in classic mode (force interactive)
                # $env:FORCE_INTERACTIVE_MODE = "true"
                # & pwsh -ExecutionPolicy Bypass -File $SCRIPT1_PATH
                # $env:FORCE_INTERACTIVE_MODE = $null
            # }
            # break
        }
        "2" {
            Write-Host "`nRunning: $SCRIPT2_DESC" -ForegroundColor Green
            & pwsh -ExecutionPolicy Bypass -File $SCRIPT2_PATH
            break
        }
        "3" {
            Write-Host "`nExiting..." -ForegroundColor Magenta
            break
        }
        Default {
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -notin @("1","2","3"))

Write-Host ""
Pause