# BASANS Windows Installer

This directory contains tools to create Windows installation packages for BASANS.

## Options

### 1. Portable Package (Recommended for quick distribution)

A zip file that users can extract and run directly without installation.

**Build:**
```batch
build_portable.bat
```

**Output:** `BASANS-Portable-1.0.0.zip`

**Features:**
- No installation required
- Users extract and run `basketball_analyzer.exe`
- Easy to distribute via email, USB, or download

### 2. NSIS Installer (Recommended for professional distribution)

A traditional Windows installer with Start Menu shortcuts, desktop shortcut, and uninstaller.

**Prerequisites:**
- Install NSIS from https://nsis.sourceforge.io/Download
- Add NSIS to your PATH or run from NSIS installation directory

**Build:**
```batch
build_installer.bat
```

**Output:** `BASANS-Setup-1.0.0.exe`

**Features:**
- Professional installation experience
- Start Menu and Desktop shortcuts
- Add/Remove Programs entry
- Clean uninstaller
- Supports silent installation (`/S` flag)

## Distribution

### GitHub Release
Upload the installer/portable zip to GitHub Releases:
1. Go to https://github.com/T1per07/basketball-analyzer/releases
2. Create a new release or edit existing one
3. Upload `BASANS-Setup-1.0.0.exe` or `BASANS-Portable-1.0.0.zip`
4. Update release notes

### Website
Update the download links on https://basans.surge.sh to point to the new installer.

## File Structure

```
installer/
├── basans_installer.nsi    # NSIS installer script
├── build_installer.bat     # Build NSIS installer
├── build_portable.bat      # Build portable package
├── LICENSE.txt             # License for installer
└── README.md               # This file
```

## Notes

- The NSIS script assumes the Flutter build output is in `../BASANS/`
- Make sure to build the Flutter app first: `flutter build windows`
- The installer includes all required DLLs and the ONNX model
- Silent installation is supported for automated deployments
