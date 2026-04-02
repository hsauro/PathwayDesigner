unit uFontHandling;


interface

Uses System.SysUtils, FMX.Graphics, FMX.Platform;

implementation

type
  TMacFontService = class(TInterfacedObject, IFMXSystemFontService)
  public
    function GetDefaultFontFamilyName: string;
    function GetDefaultFontSize: Single;
  end;


function TMacFontService.GetDefaultFontFamilyName: string;
begin
  Result := 'Helvetica'; // Or your preferred font
  {$IFDEF MACOS}
  Result := '.AppleSystemUIFont';
  {$ENDIF}
end;


procedure RegisterFontService;
begin
  // Check if the service exists and remove it before adding yours
  if TPlatformServices.Current.SupportsPlatformService(IFMXSystemFontService) then
    TPlatformServices.Current.RemovePlatformService(IFMXSystemFontService);

  TPlatformServices.Current.AddPlatformService(IFMXSystemFontService, TMacFontService.Create);
end;


function TMacFontService.GetDefaultFontSize: Single;
begin
  Result := 11.0; // Set your preferred smaller size for Mac here
end;

initialization
  {$IFDEF MACOS}
  RegisterFontService;
  {$ENDIF}
end.
