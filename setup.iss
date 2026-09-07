[Setup]
AppName=Moanui
AppVersion=0.0.2
AppPublisher=CRPM
DefaultDirName={autopf}\Moanui
DefaultGroupName=Moanui
OutputBaseFilename=MoanuiSetup_v0.0.2
Compression=lzma2/ultra64
LZMAUseSeparateProcess=yes
SolidCompression=yes
SetupIconFile=icon.ico
 
[Files]
Source: "global.R"; DestDir: "{app}"
Source: "start.R"; DestDir: "{app}"
Source: "run.R"; DestDir: "{app}"
Source: "launch.bat"; DestDir: "{app}"
Source: "icon.ico"; DestDir: "{app}"
Source: "R\*"; DestDir: "{app}\R"; Flags: recursesubdirs createallsubdirs
Source: "www\*"; DestDir: "{app}\www"; Flags: recursesubdirs createallsubdirs
Source: "R-portable\*"; DestDir: "{app}\R-portable"; Flags: recursesubdirs createallsubdirs
Source: "electron\main.js"; DestDir: "{app}\electron"
Source: "electron\package.json"; DestDir: "{app}\electron"
Source: "electron\package-lock.json"; DestDir: "{app}\electron"
Source: "electron\node_modules\*"; DestDir: "{app}\electron\node_modules"; Flags: recursesubdirs createallsubdirs
Source: "electron\splash.html"; DestDir: "{app}\electron"
Source: "electron\chargement_moanui.png"; DestDir: "{app}\electron"
 
[Icons]
Name: "{group}\Moanui"; Filename: "{app}\launch.bat"; IconFilename: "{app}\icon.ico"
Name: "{commondesktop}\Moanui"; Filename: "{app}\launch.bat"; IconFilename: "{app}\icon.ico"
 
[Run]
Filename: "{app}\launch.bat"; Description: "Lancer Moanui"; Flags: postinstall nowait shellexec