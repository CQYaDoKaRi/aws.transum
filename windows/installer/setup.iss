; Inno Setup Script for AudioTranscriptionSummary
; Download Inno Setup 6 from https://jrsoftware.org/isinfo.php

#define MyAppName "AudioTranscriptionSummary"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AudioTranscriptionSummary"
#define MyAppExeName "AudioTranscriptionSummary.exe"
#define MyAppBuildDir "..\AudioTranscriptionSummary\bin\x64\Release\net8.0-windows10.0.19041.0"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=AudioTranscriptionSummary_Setup_{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest
DisableProgramGroupPage=yes

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main executable
Source: "{#MyAppBuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Application DLLs
Source: "{#MyAppBuildDir}\AudioTranscriptionSummary.dll"; DestDir: "{app}"; Flags: ignoreversion

; Config files
Source: "{#MyAppBuildDir}\AudioTranscriptionSummary.deps.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\AudioTranscriptionSummary.runtimeconfig.json"; DestDir: "{app}"; Flags: ignoreversion

; WinUI resources
Source: "{#MyAppBuildDir}\AudioTranscriptionSummary.pri"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\App.xbf"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\MainWindow.xbf"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Views\*.xbf"; DestDir: "{app}\Views"; Flags: ignoreversion

; AWS SDK
Source: "{#MyAppBuildDir}\AWSSDK.Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\AWSSDK.S3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\AWSSDK.TranscribeService.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\AWSSDK.TranscribeStreaming.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\AWSSDK.Translate.dll"; DestDir: "{app}"; Flags: ignoreversion

; MVVM Toolkit
Source: "{#MyAppBuildDir}\CommunityToolkit.Mvvm.dll"; DestDir: "{app}"; Flags: ignoreversion

; NAudio
Source: "{#MyAppBuildDir}\NAudio.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.Asio.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.Midi.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.Wasapi.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.WinForms.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\NAudio.WinMM.dll"; DestDir: "{app}"; Flags: ignoreversion

; WinUI / Windows App SDK
Source: "{#MyAppBuildDir}\Microsoft.WinUI.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.WindowsAppRuntime.Bootstrap.Net.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.InteractiveExperiences.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Web.WebView2.Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Web.WebView2.Core.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.ApplicationModel.DynamicDependency.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.ApplicationModel.Resources.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.ApplicationModel.WindowsAppRuntime.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.AppLifecycle.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.AppNotifications.Builder.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.AppNotifications.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.Management.Deployment.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.PushNotifications.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.SDK.NET.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.Security.AccessControl.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.Storage.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.System.Power.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.System.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppBuildDir}\Microsoft.Windows.Widgets.Projection.dll"; DestDir: "{app}"; Flags: ignoreversion

; WinRT Runtime
Source: "{#MyAppBuildDir}\WinRT.Runtime.dll"; DestDir: "{app}"; Flags: ignoreversion

; Native runtimes
Source: "{#MyAppBuildDir}\runtimes\*"; DestDir: "{app}\runtimes"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
