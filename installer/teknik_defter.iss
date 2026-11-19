; Teknik Defter — Windows kurulum betiği (Inno Setup 6)
#define AppName "Teknik Defter"
#define AppVersion GetEnv("APP_VERSION")
#if AppVersion == ""
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{6B1E3F52-9C1A-4D7E-9B0A-7E54C1D2A0F1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Vagabundo Apps
DefaultDirName={autopf}\Teknik Defter
DefaultGroupName=Teknik Defter
UninstallDisplayIcon={app}\teknik_defter.exe
OutputDir=..\dist
OutputBaseFilename=TeknikDefter-Kurulum-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstü kısayolu oluştur"; GroupDescription: "Ek görevler:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Teknik Defter"; Filename: "{app}\teknik_defter.exe"
Name: "{group}\Kaldır"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Teknik Defter"; Filename: "{app}\teknik_defter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\teknik_defter.exe"; Description: "Teknik Defter'i başlat"; Flags: nowait postinstall skipifsilent

[Registry]
; "Birlikte aç" listesinde görün (varsayılan uygulamayı değiştirmez)
Root: HKA; Subkey: "Software\Classes\TeknikDefter.Dosya"; ValueType: string; ValueName: ""; ValueData: "Teknik Defter"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\TeknikDefter.Dosya\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\teknik_defter.exe,0"
Root: HKA; Subkey: "Software\Classes\TeknikDefter.Dosya\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\teknik_defter.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "TeknikDefter.Dosya"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.png\OpenWithProgids"; ValueType: string; ValueName: "TeknikDefter.Dosya"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.jpg\OpenWithProgids"; ValueType: string; ValueName: "TeknikDefter.Dosya"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.jpeg\OpenWithProgids"; ValueType: string; ValueName: "TeknikDefter.Dosya"; ValueData: ""; Flags: uninsdeletevalue
