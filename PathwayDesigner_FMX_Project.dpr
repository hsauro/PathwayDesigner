program PathwayDesigner_FMX_Project;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  ufMain in 'ufMain.pas' {frmMain},
  uBioModel in 'uBioModel.pas',
  uGeometry in 'uGeometry.pas',
  uDiagramView in 'uDiagramView.pas',
  uAntimonyBridge in 'uAntimonyBridge.pas',
  uLibSBNW in 'uLibSBNW.pas',
  uSBMLLayout in 'uSBMLLayout.pas',
  uAutoLayout in 'uAutoLayout.pas',
  uAntimony in 'AntimonyLibrary\uAntimony.pas',
  uAntimonyExpressionParser in 'AntimonyLibrary\uAntimonyExpressionParser.pas',
  uAntimonyLexer in 'AntimonyLibrary\uAntimonyLexer.pas',
  uAntimonyModelType in 'AntimonyLibrary\uAntimonyModelType.pas',
  uAntimonyParser in 'AntimonyLibrary\uAntimonyParser.pas',
  uExpressionNode in 'AntimonyLibrary\uExpressionNode.pas';

{$R *.res}

begin
  GlobalUseSkia := False;// False speeds things up True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
