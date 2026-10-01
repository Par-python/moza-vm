# Runs once, elevated, at the first Windows logon (from autounattend.xml).
# Installs Pit House from the offline package on the setup ISO, turns the VM
# into a Pit House-only kiosk, then shuts down.
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
New-Item -ItemType Directory -Force C:\moza | Out-Null
Start-Transcript -Path C:\moza\setup.log -Append

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

try {
  Step 'Extracting MOZA Pit House (takes a few minutes)...'
  $dest = 'C:\Program Files (x86)'
  $app  = Join-Path $dest 'MOZA Pit House'
  if (-not (Test-Path "$app\bin\MOZA Pit House.exe")) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory("$src\pithouse.zip", $dest)
  }

  Step 'Installing Visual C++ runtimes...'
  $vc = "$app\vcredist"
  if (Test-Path "$vc\2015_2022\vc_redist.x86.exe") {
    Start-Process "$vc\2015_2022\vc_redist.x86.exe" '/install /quiet /norestart' -Wait
  }
  if (Test-Path "$vc\2010\vcredist_x86.exe") {
    Start-Process "$vc\2010\vcredist_x86.exe" '/q /norestart' -Wait
  }

  Step 'Installing MOZA drivers...'
  # Same drivers Pit House's own install.bat / installUsbDriver.bat add.
  # Trusting the signer first stops Windows from popping a confirm dialog.
  $drv = "$app\bin\drivers\win10\x64"
  foreach ($cat in Get-ChildItem "$drv\*.cat") {
    $cert = (Get-AuthenticodeSignature $cat.FullName).SignerCertificate
    if ($cert) {
      $store = New-Object Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
      $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
    }
  }
  foreach ($inf in 'MOZAWindowsDriver.inf', 'MOZAUSBDriver.inf') {
    & "$env:windir\System32\pnputil.exe" /add-driver "$drv\$inf" /install
  }

  Step 'Start menu shortcut...'
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\MOZA Pit House.lnk")
  $lnk.TargetPath = "$app\MOZA Pit House.exe"
  $lnk.WorkingDirectory = $app
  $lnk.Save()

  Step 'Setting up kiosk mode...'
  Copy-Item "$src\kiosk.ps1" C:\moza\kiosk.ps1 -Force
  # Per-user shell: Pit House (via kiosk.ps1) replaces the Windows desktop.
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' Shell `
    'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\moza\kiosk.ps1'

  # Log in automatically every boot (the unattend AutoLogon only lasts a few).
  $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $wl AutoAdminLogon '1'
  Set-ItemProperty $wl DefaultUserName 'moza'
  Set-ItemProperty $wl DefaultPassword ''
  Remove-ItemProperty $wl AutoLogonCount -ErrorAction SilentlyContinue

  Step 'Trimming Windows for a small VM...'
  # Elevate without a prompt, so firmware/driver updates don't stall on UAC.
  Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' ConsentPromptBehaviorAdmin 0
  # No automatic Windows Update downloads/reboots eating RAM, CPU and disk.
  $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
  New-Item -Force $wu | Out-Null
  Set-ItemProperty $wu NoAutoUpdate 1
  # Real shutdowns (no hibernate file), and never sleep mid-firmware-update.
  powercfg /hibernate off
  powercfg /change standby-timeout-ac 0
  powercfg /change monitor-timeout-ac 0

  Set-Content C:\moza\setup-done 'ok'
  Step 'Done. Shutting down; use "moza-vm" on Linux from now on.'
  Stop-Transcript
  shutdown /s /t 10
} catch {
  Write-Host "`nSETUP FAILED: $_" -ForegroundColor Red
  Write-Host 'Log: C:\moza\setup.log. Press Enter to close.'
  Stop-Transcript
  Read-Host | Out-Null
}
