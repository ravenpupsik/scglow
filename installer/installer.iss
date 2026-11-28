; scglow installer (Inno Setup 6.3 or newer).
; Build it with tool\build_release.ps1, which passes the pubspec version:
;   ISCC /DAppVersion=1.6.5+31 /DAppVersionNumeric=1.6.5.31 /DReleaseDir=... /DOutputDir=... installer\installer.iss
; /DIsolatedTest builds a setup for install tests in a developer's own profile:
; no shortcuts, no AUMID key, no shortcut retargeting and no lines in scglow.log.

#if VER < EncodeVer(6, 3, 0)
  #error Inno Setup 6.3 or newer is required
#endif
#ifndef AppVersion
  #error Pass /DAppVersion=<pubspec version>; use tool\build_release.ps1
#endif
#ifndef AppVersionNumeric
  #error Pass /DAppVersionNumeric=<major.minor.patch.build>
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif
#define AppExe "scglow.exe"
; Must match kAppUserModelId in windows\runner\app_identity.h.
#define AppUserModelId "io.github.scglow.app"

[Setup]
; NEVER change AppId. Windows and Inno Setup find the existing install by it,
; so a new version installs over the old one instead of next to it.
AppId={{C674E000-9041-45CB-B4FE-0AADB09D6D33}
AppName=scglow
AppVersion={#AppVersion}
AppVerName=scglow {#AppVersion}
AppPublisher=tennesyst
AppPublisherURL=https://github.com/ravenpupsik/scglow
AppSupportURL=https://github.com/ravenpupsik/scglow/issues
AppUpdatesURL=https://github.com/ravenpupsik/scglow/releases
VersionInfoVersion={#AppVersionNumeric}
VersionInfoProductVersion={#AppVersionNumeric}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoDescription=scglow setup
; Per-user install: no admin rights and no UAC prompt, so updates run silently.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\scglow
DisableDirPage=auto
DisableProgramGroupPage=yes
DefaultGroupName=scglow
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=scglow-setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=scglow
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
UsePreviousTasks=yes
SetupLogging=yes
ShowLanguageDialog=auto

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[CustomMessages]
en.DeleteUserData=Also delete your scglow data (sign-in, settings and cache) in:%n%1%n%nChoose No to keep it for a later install.
ru.DeleteUserData=Удалить также данные scglow (вход, настройки и кэш) в папке:%n%1%n%nВыберите «Нет», чтобы сохранить их для следующей установки.
en.WebView2Failed=scglow needs the Microsoft Edge WebView2 Runtime for sign-in, and it could not be installed. Install it from https://go.microsoft.com/fwlink/p/?LinkId=2124703
ru.WebView2Failed=Для входа scglow нужен Microsoft Edge WebView2 Runtime, но установить его не удалось. Установите его отсюда: https://go.microsoft.com/fwlink/p/?LinkId=2124703

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Assets are fully replaced on every build; drop the old set so no stale files remain.
Type: filesandordirs; Name: "{app}\data\flutter_assets"
Type: filesandordirs; Name: "{app}\data\data"
Type: filesandordirs; Name: "{app}\.scglow_update"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "\.scglow_update\,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

#ifndef IsolatedTest
[Icons]
Name: "{autoprograms}\scglow"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\scglow"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\AppUserModelId\{#AppUserModelId}"; Flags: dontcreatekey uninsdeletekey
#endif

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,scglow}"; Flags: nowait postinstall skipifsilent
; Silent updates from the app pass /RELAUNCH=1 to start the new version afterwards.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: RelaunchRequested

[UninstallDelete]
Type: files; Name: "{app}\scglow.installed"
Type: filesandordirs; Name: "{app}"

[Code]
const
  WebView2ClientKey = 'Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  WebView2Bootstrapper = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703';
  Synchronize = $00100000;

function OpenProcess(dwDesiredAccess: Cardinal; bInheritHandle: BOOL; dwProcessId: Cardinal): Cardinal;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(hHandle: Cardinal; dwMilliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(hObject: Cardinal): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';

procedure AppLog(const Msg: String);
var
  Line: String;
begin
  Log(Msg);
#ifdef IsolatedTest
  Exit;
#endif
  // Same file and prefix as the app's own diagnostic log.
  Line := GetDateTimeString('yyyy-mm-dd', '-', ':') + 'T' + GetDateTimeString('hh:nn:ss', '-', ':') +
    ' update: setup: ' + Msg + #13#10;
  SaveStringToFile(AddBackslash(GetEnv('TEMP')) + 'scglow.log', Line, True);
end;

function RelaunchRequested: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

// 1.6.5+31 started this setup through a detached PowerShell that opened a
// console window and never exited; close any such launcher left behind.
procedure CloseStuckLaunchers;
var
  Locator, Services, Found, Item: Variant;
  I: Integer;
begin
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('.', 'root\CIMV2');
    Found := Services.ExecQuery('SELECT * FROM Win32_Process WHERE Name = ''powershell.exe'' ' +
      'AND CommandLine LIKE ''%Win32[_]ProcessStartup%'' AND CommandLine LIKE ''%scglow-setup%''');
    for I := 0 to Found.Count - 1 do
    begin
      Item := Found.ItemIndex(I);
      Item.Terminate(0);
      AppLog('closed a stuck updater launcher');
    end;
  except
    Log('Could not look for stuck updater launchers: ' + GetExceptionMessage);
  end;
end;

function InitializeSetup: Boolean;
var
  Pid: Integer;
  H: Cardinal;
begin
  Result := True;
  // The app passes its PID and quits; wait for it so its files are free.
  Pid := StrToIntDef(ExpandConstant('{param:WAITPID|0}'), 0);
  if Pid > 0 then
  begin
    H := OpenProcess(Synchronize, False, Pid);
    if H <> 0 then
    begin
      WaitForSingleObject(H, 60000);
      CloseHandle(H);
    end;
  end;
  if WizardSilent then CloseStuckLaunchers;
end;

function WebView2Installed: Boolean;
var
  V: String;
begin
  Result :=
    (RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\' + WebView2ClientKey, 'pv', V) and (V <> '') and (V <> '0.0.0.0')) or
    (RegQueryStringValue(HKLM, 'SOFTWARE\' + WebView2ClientKey, 'pv', V) and (V <> '') and (V <> '0.0.0.0')) or
    (RegQueryStringValue(HKCU, 'Software\' + WebView2ClientKey, 'pv', V) and (V <> '') and (V <> '0.0.0.0'));
end;

procedure EnsureWebView2;
var
  Code: Integer;
  Setup: String;
begin
  if WebView2Installed then Exit;
  AppLog('WebView2 Runtime missing, downloading the bootstrapper');
  try
    DownloadTemporaryFile(WebView2Bootstrapper, 'MicrosoftEdgeWebview2Setup.exe', '', nil);
    Setup := ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe');
    // Without admin rights the bootstrapper installs the runtime for this user.
    if Exec(Setup, '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, Code) and WebView2Installed then
      AppLog('WebView2 Runtime installed')
    else
    begin
      AppLog('WebView2 Runtime install failed, code ' + IntToStr(Code));
      if not WizardSilent then MsgBox(CustomMessage('WebView2Failed'), mbError, MB_OK);
    end;
  except
    AppLog('WebView2 Runtime download failed: ' + GetExceptionMessage);
    if not WizardSilent then MsgBox(CustomMessage('WebView2Failed'), mbError, MB_OK);
  end;
end;

function ShortcutFolders: TArrayOfString;
begin
  SetArrayLength(Result, 5);
  Result[0] := ExpandConstant('{userdesktop}');
  Result[1] := ExpandConstant('{userprograms}');
  Result[2] := ExpandConstant('{userstartmenu}');
  Result[3] := ExpandConstant('{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar');
  Result[4] := ExpandConstant('{userappdata}\Microsoft\Internet Explorer\Quick Launch');
end;

// Retargets shortcuts to another scglow.exe (a portable copy) at the installed one,
// or with Remove set, deletes shortcuts to the installed one.
function FixShortcuts(Remove: Boolean): Integer;
var
  Folders: TArrayOfString;
  Rec: TFindRec;
  Shell, Lnk: Variant;
  I: Integer;
  Path, Target, Exe: String;
begin
  Result := 0;
  Exe := ExpandConstant('{app}\{#AppExe}');
  Folders := ShortcutFolders;
  try
    Shell := CreateOleObject('WScript.Shell');
  except
    Log('WScript.Shell unavailable; shortcuts left as they are');
    Exit;
  end;
  for I := 0 to GetArrayLength(Folders) - 1 do
  begin
    if not DirExists(Folders[I]) then Continue;
    if FindFirst(AddBackslash(Folders[I]) + '*.lnk', Rec) then
    try
      repeat
        Path := AddBackslash(Folders[I]) + Rec.Name;
        try
          Lnk := Shell.CreateShortcut(Path);
          Target := Lnk.TargetPath;
          if CompareText(ExtractFileName(Target), '{#AppExe}') <> 0 then
            Target := ''
          else if Remove then
          begin
            if (CompareText(Target, Exe) = 0) and DeleteFile(Path) then Result := Result + 1;
          end
          else if CompareText(Target, Exe) <> 0 then
          begin
            Lnk.TargetPath := Exe;
            Lnk.WorkingDirectory := ExpandConstant('{app}');
            Lnk.IconLocation := Exe + ',0';
            Lnk.Save;
            Result := Result + 1;
            Log('Retargeted ' + Path + ' from ' + Target);
          end;
        except
          Log('Could not update shortcut ' + Path + ': ' + GetExceptionMessage);
        end;
      until not FindNext(Rec);
    finally
      FindClose(Rec);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Tells the app it runs from the installer (no self-migration, no own Start menu shortcut).
    SaveStringToFile(ExpandConstant('{app}\scglow.installed'), '{#AppVersion}', False);
    AppLog('installed {#AppVersion} in ' + ExpandConstant('{app}'));
#ifndef IsolatedTest
    AppLog('shortcuts retargeted: ' + IntToStr(FixShortcuts(False)));
#endif
    EnsureWebView2;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
#ifndef IsolatedTest
  if CurUninstallStep = usUninstall then
    FixShortcuts(True);
#endif
  if CurUninstallStep = usPostUninstall then
  begin
    // User data lives in %APPDATA%\scglow, not next to the exe; keep it unless asked.
    Data := ExpandConstant('{userappdata}\scglow');
    if DirExists(Data) and not UninstallSilent then
      if MsgBox(FmtMessage(CustomMessage('DeleteUserData'), [Data]), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Data, True, True, True);
  end;
end;
