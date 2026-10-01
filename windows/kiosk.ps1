# Windows shell for the moza user: runs Pit House and nothing else. When Pit
# House exits (and isn't just restarting to update), the VM shuts down, which
# hands the wheel back to Linux.
#
# Escape hatch: Ctrl+Alt+Del (virt-viewer: Send key menu) > Task Manager >
# File > Run new task > explorer.exe

$app = 'C:\Program Files (x86)\MOZA Pit House'
$resolution = '@RESOLUTION@'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Native {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);

  public static void SetResolution(int w, int h) {
    var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
    if (!EnumDisplaySettings(null, -1, ref dm)) return;
    if (dm.dmPelsWidth == w && dm.dmPelsHeight == h) return;
    dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000;
    ChangeDisplaySettings(ref dm, 1); // CDS_UPDATEREGISTRY
  }
}
'@

if ($resolution -match '^(\d+)x(\d+)$') {
  try { [Native]::SetResolution([int]$Matches[1], [int]$Matches[2]) } catch {}
}

function PitHouseRunning {
  [bool](Get-Process -Name 'MOZA Pit House', 'MaintenanceTool' -ErrorAction SilentlyContinue)
}

Start-Process "$app\MOZA Pit House.exe" -WorkingDirectory $app

# Maximize the main window once it appears.
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep 1
  $p = Get-Process -Name 'MOZA Pit House' -ErrorAction SilentlyContinue |
       Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) { [Native]::ShowWindow($p.MainWindowHandle, 3) | Out-Null; break }  # SW_MAXIMIZE
}

# Wait until Pit House has been gone for 15s straight; it restarts itself
# after updates, and that shouldn't shut the VM down.
$gone = 0
while ($gone -lt 15) {
  Start-Sleep 1
  if (PitHouseRunning) { $gone = 0 } else { $gone++ }
}

Stop-Computer -Force
