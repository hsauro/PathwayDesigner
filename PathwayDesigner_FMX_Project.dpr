program PathwayDesigner_FMX_Project;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  uAntimony in 'AntimonyLibrary\uAntimony.pas',
  uAntimonyExpressionParser in 'AntimonyLibrary\uAntimonyExpressionParser.pas',
  uAntimonyLexer in 'AntimonyLibrary\uAntimonyLexer.pas',
  uAntimonyModelType in 'AntimonyLibrary\uAntimonyModelType.pas',
  uAntimonyParser in 'AntimonyLibrary\uAntimonyParser.pas',
  uExpressionNode in 'AntimonyLibrary\uExpressionNode.pas',
  uAntimonyBridge in 'Src\uAntimonyBridge.pas',
  uAppVersion in 'Src\uAppVersion.pas',
  uAutoLayout in 'Src\uAutoLayout.pas',
  uBioModel in 'Src\uBioModel.pas',
  uDiagramView in 'Src\uDiagramView.pas',
  ufMain in 'Src\ufMain.pas' {frmMain},
  uGeometry in 'Src\uGeometry.pas',
  uRandomNetwork in 'Src\uRandomNetwork.pas',
  uUndoManager in 'Src\uUndoManager.pas',
  uSBMLExport in 'src\uSBMLExport.pas',
  uSBMLBridge in 'src\uSBMLBridge.pas',
  uColorPicker in 'src\uColorPicker.pas';

{$R *.res}

begin
  GlobalUseSkia := False;// False speeds things up True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
