; Installateur Windows de Moanui (Inno Setup 6), par utilisateur, sans droits administrateur.
; Les fichiers copies par l'installateur ne portent pas la marque "telecharge depuis Internet"
; (Mark of the Web) : Windows ne bloque donc plus python312.dll comme dans un zip extrait.
; Construction : ISCC /DMyVersion=0.2.0 /DSourceDir=..\dist\Moanui /DOutDir=..\ packaging\moanui.iss
; Programme : %LOCALAPPDATA%\Programs\Moanui ; donnees (inchangees, jamais supprimees) : %LOCALAPPDATA%\Moanui

#ifndef MyVersion
  #define MyVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\Moanui"
#endif
#ifndef OutDir
  #define OutDir ".."
#endif

[Setup]
AppId={{6E3A7C2B-4F1D-4B8E-9C55-2D7A1F0B9E41}
AppName=Moanui
AppVersion={#MyVersion}
AppVerName=Moanui {#MyVersion}
AppPublisher=Moanui
DefaultDirName={localappdata}\Programs\Moanui
DefaultGroupName=Moanui
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutDir}
OutputBaseFilename=Moanui-installation
SetupIconFile=moanui.ico
UninstallDisplayIcon={app}\Moanui.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; mise a jour : on repart d'un dossier programme propre (les donnees sont ailleurs)
Type: filesandordirs; Name: "{app}\_internal"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Moanui"; Filename: "{app}\Moanui.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,Moanui}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Moanui"; Filename: "{app}\Moanui.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Moanui.exe"; Description: "{cm:LaunchProgram,Moanui}"; Flags: nowait postinstall skipifsilent
