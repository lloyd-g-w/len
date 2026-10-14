; Len — Windows installer (Inno Setup 6). Built by .github/workflows/release.yml:
;   iscc /DAppVersion=X.Y.Z /DSourceDir=<flutter build windows output> /DOutputDir=<dir> len.iss
; Installs per user by default (no administrator rights; "Install for all
; users" is offered in a dialog), adds Start menu / optional desktop
; shortcuts, registers Len for PDFs and images ("Open with" list and the
; Default apps settings; it never takes over an existing default), opens
; its own .len files (notebooks, folders and backups) and adds an
; uninstaller. Files opened while Len runs reach the running window
; (single instance, windows/runner/single_instance.cpp).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

#define AppName "Len"
#define AppExe "len.exe"
#define ProgId "Len.Document"
#define LenFileProgId "Len.File"

[Setup]
; Never change AppId: it identifies the installation for upgrades.
AppId={{5C85836A-1E53-41A2-A65C-495925C9AFF6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Len
AppPublisherURL=https://github.com/lloyd-g-w/len
AppSupportURL=https://github.com/lloyd-g-w/len/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
ChangesAssociations=yes
; Upgrades close a running Len (Restart Manager) before replacing files.
CloseApplications=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
#ifdef Sign
; Code signing (docs/PACKAGING.md "Windows"): iscc /DSign "/Slen=<signing command> $f"
; signs the setup and the uninstaller with the sign tool named "len".
SignTool=len
SignedUninstaller=yes
#endif
OutputDir={#OutputDir}
OutputBaseFilename=len-{#AppVersion}-windows-x64-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; HKA = HKCU for per-user installs, HKLM for all users. (Len itself keeps
; its window placement in HKCU\Software\Len.)
Root: HKA; Subkey: "Software\Len"; Flags: uninsdeletekeyifempty
; The document type Len opens.
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueName: ""; ValueData: "Len document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
; Len's own files (.len): Len is their handler.
Root: HKA; Subkey: "Software\Classes\{#LenFileProgId}"; ValueType: string; ValueName: ""; ValueData: "Len file"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#LenFileProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\{#LenFileProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.len"; ValueType: string; ValueName: ""; ValueData: "{#LenFileProgId}"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.len"; ValueType: string; ValueName: "Content Type"; ValueData: "application/x-len"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.len\OpenWithProgids"; ValueType: string; ValueName: "{#LenFileProgId}"; ValueData: ""; Flags: uninsdeletevalue
; len://sync?… setup links (Settings → Sync → Set up another device).
Root: HKA; Subkey: "Software\Classes\len"; ValueType: string; ValueName: ""; ValueData: "URL:Len link"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\len"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\len\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
; "Open with" lists for each extension (not the default handler).
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.png\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.jpg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.jpeg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.webp\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
; The application itself (friendly name and supported types in "Open with").
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".png"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".jpg"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".jpeg"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".webp"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".len"; ValueData: ""
; Settings → Apps → Default apps: Len can be chosen for these types.
Root: HKA; Subkey: "Software\Len\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Len\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Handwriting-first notes with an infinite canvas and self-hosted sync"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".pdf"; ValueData: "{#ProgId}"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".png"; ValueData: "{#ProgId}"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpg"; ValueData: "{#ProgId}"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpeg"; ValueData: "{#ProgId}"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".webp"; ValueData: "{#ProgId}"
Root: HKA; Subkey: "Software\Len\Capabilities\FileAssociations"; ValueType: string; ValueName: ".len"; ValueData: "{#LenFileProgId}"
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "{#AppName}"; ValueData: "Software\Len\Capabilities"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
