unit uPreferencesObject;

interface

Uses System.IOUtils, System.JSON.Serializers;

type
  TPreferences = class
     ConvertCatalyticReactions : Boolean;

     constructor Create;

  end;

var PreferencesObject:TPreferences;

procedure SavePreferences;
procedure LoadPreferences;

implementation

constructor TPreferences.Create;
begin
  inherited Create;

  ConvertCatalyticReactions := True;
end;


function GetSettingsFilePath: string;
var
  BaseDir: string;
begin
  {$IFDEF MSWINDOWS}
  // Standard AppData/Roaming on Windows
  BaseDir := TPath.GetHomePath;
  {$ENDIF}

  {$IFDEF MACOS}
  // Standard ~/Library/Application Support on macOS
  BaseDir := TPath.Combine(TPath.GetLibraryPath, 'Application Support');
  {$ENDIF}

  // Create your specific subfolder
  BaseDir := TPath.Combine(BaseDir, 'PathwayDesigner');

  if not TDirectory.Exists(BaseDir) then
    TDirectory.CreateDirectory(BaseDir);

  Result := TPath.Combine(BaseDir, 'settings.json');
end;


procedure SavePreferences;
var
  Serializer: TJsonSerializer;
  Json: string;
begin
  Serializer := TJsonSerializer.Create;
  try
    Json := Serializer.Serialize(PreferencesObject);

    TFile.WriteAllText(GetSettingsFilePath, Json);
  finally
    Serializer.Free;
  end;
end;


procedure LoadPreferences;
var
  Serializer: TJsonSerializer;
  Json: string;
  FilePath : String;
begin
  FilePath := GetSettingsFilePath;
  if  TFile.Exists(FilePath) then
      begin
      Serializer := TJsonSerializer.Create;
      try
        Json := TFile.ReadAllText(Filepath);
        PreferencesObject := Serializer.Deserialize<TPreferences>(Json);
      finally
        Serializer.Free;
      end;
      end
  else
     PreferencesObject := TPreferences.Create;
end;

end.
