; ============================================================================
; Bakta for Windows (native port) - one-click installer
;
; Builds a single self-contained Setup .exe that bundles:
;   * the ported static tool stack (bin\): amrfinder, hmmsearch, cmscan/cmsearch,
;     tRNAscan-SE.exe + Perl script + trnascan-lib, eufindtRNA/trnascan-1.4/
;     covels-SE/coves-SE, aragorn, pilercr, diamond, blast\ (trimmed)
;   * a bundled Strawberry Perl runtime (perl\) for tRNAscan-SE
;   * an embedded Python with Bakta + all its packages (python\) - no system Python
;   * a graphical front-end (gui\) + a "Bakta Command Prompt" + `bakta`/`bakta_db`
;
; The Bakta DATABASE is NOT bundled (~1.5 GB); the app/CLI download it on first use.
;
; Invoked by build_bakta_installer.ps1, which passes the payload location:
;   ISCC.exe /DPayloadDir=<dir> /DOutputDir=<dir> /DAppVersion=<ver> bakta_windows.iss
;
; Per-user install by default (no admin), can elevate to all-users.
; ============================================================================

#ifndef PayloadDir
  #define PayloadDir "..\..\..\bakta-dist\payload"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef AppVersion
  #define AppVersion "1.12.0"
#endif

#define MyAppName "Bakta for Windows"
#define MyAppPublisher "Bakta native-Windows port"
#define MyAppURL "https://github.com/MrMufasii/Bakta-for-Windows"

[Setup]
AppId={{B4A7C2E9-6F31-4D8A-9E2C-1A5B7D3F6C84}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\Bakta-Windows
DefaultGroupName=Bakta for Windows
DisableProgramGroupPage=yes
DisableDirPage=no
LicenseFile={#PayloadDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=Bakta-Windows-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
ChangesEnvironment=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={sys}\cmd.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut for the Bakta app"; GroupDescription: "Shortcuts:"
Name: "addtopath"; Description: "Add Bakta to my PATH (run 'bakta' from any terminal)"; GroupDescription: "Integration:"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Graphical app (primary entry point for non-technical users) - console-less via the VBS shim.
Name: "{group}\Bakta for Windows (app)"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Bakta-GUI.vbs"""; WorkingDir: "{app}\gui"; IconFilename: "{sys}\shell32.dll"; IconIndex: 13; Comment: "Annotate a bacterial genome with a simple graphical interface"
Name: "{autodesktop}\Bakta for Windows"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Bakta-GUI.vbs"""; WorkingDir: "{app}\gui"; IconFilename: "{sys}\shell32.dll"; IconIndex: 13; Tasks: desktopicon
Name: "{group}\Bakta Command Prompt"; Filename: "{app}\bakta-shell.bat"; WorkingDir: "{userdocs}"; IconFilename: "{sys}\cmd.exe"; Comment: "Open a terminal with Bakta ready to use"
Name: "{group}\Bakta Read Me"; Filename: "{app}\README-WINDOWS.txt"
Name: "{group}\Uninstall Bakta"; Filename: "{uninstallexe}"

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Bakta-GUI.vbs"""; Description: "Launch the Bakta app now"; Flags: postinstall skipifsilent nowait
Filename: "{app}\bakta-shell.bat"; Description: "Open the Bakta Command Prompt instead"; Flags: postinstall skipifsilent nowait unchecked

[Code]
const EnvironmentKey = 'Environment';

function PathContains(const Paths, Dir: string): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') > 0;
end;

procedure AddToUserPath(const Dir: string);
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    Paths := '';
  if PathContains(Paths, Dir) then
    exit;
  if (Paths <> '') and (Paths[Length(Paths)] <> ';') then
    Paths := Paths + ';';
  Paths := Paths + Dir;
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths);
end;

procedure RemoveFromUserPath(const Dir: string);
var
  Paths, Rebuilt, Part: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    exit;
  if not PathContains(Paths, Dir) then
    exit;
  Rebuilt := '';
  Paths := Paths + ';';
  repeat
    P := Pos(';', Paths);
    Part := Copy(Paths, 1, P - 1);
    Paths := Copy(Paths, P + 1, Length(Paths));
    if (Part <> '') and (Uppercase(Part) <> Uppercase(Dir)) then
    begin
      if Rebuilt <> '' then
        Rebuilt := Rebuilt + ';';
      Rebuilt := Rebuilt + Part;
    end;
  until Paths = '';
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Rebuilt);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    if WizardIsTaskSelected('addtopath') then
      AddToUserPath(ExpandConstant('{app}\bin'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveFromUserPath(ExpandConstant('{app}\bin'));
end;
