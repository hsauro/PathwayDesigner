unit ufMain;

{
  uMainForm.pas
  =============
  FMX host form.  Owns a TSkPaintBox (the drawing surface), two TScrollBars,
  and the TDiagramView/TBioModel pair.

  All controls are created programmatically in FormCreate so that this unit
  compiles and runs without an accompanying .fmx form file — just set the
  form's "Designer" property to nil and mark it as "auto-create".

  IMPORTANT FOR PROJECT SETUP
  ---------------------------
  1. Add Skia4Delphi to the project via GetIt or the GitHub distribution.
  2. In Project Options → Delphi Compiler → Defines, ensure SKIA is defined
     (Skia4Delphi adds this automatically when installed correctly).
  3. The .fmx file for this form should contain only the bare TForm definition
     — no child controls — because all controls are built in FormCreate.
     Example minimal .fmx content:
       object MainForm: TMainForm
         Left = 0; Top = 0; Width = 1024; Height = 768
         Caption = 'Biochemical Network Editor'
       end

  WHAT IS NOT YET IMPLEMENTED (next steps)
  -----------------------------------------
  - Mouse interaction (click-to-select, drag nodes, rubber-band, drag junction)
  - Toolbar / menu (Add Species, Add Reaction, Save, Load)
  - Zoom (Ctrl+scroll wheel)
  - Full undo / redo
}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.ImageList,
  Skia,
  FMX.Skia,
  FMX.Types,
  FMX.Controls,
  FMX.StdCtrls,
  FMX.Layouts,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.DialogService.Sync,
  FMX.Controls.Presentation,
  FMX.Menus,
  FMX.ImgList,
  uBioModel,
  uDiagramView,
  uAntimonyBridge,
  uRandomNetwork,
  uAppVersion,
  FMX.Objects,
  FMX.Colors,
  FMX.ListBox,
  FMX.Ani, FMX.Edit, FMX.EditBox, FMX.NumberBox, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo;


type
  TfrmMain = class(TForm)
    Layout1: TLayout;
    Layout2: TLayout;
    Layout3: TLayout;
    Layout4: TLayout;
    HScrollBar: TScrollBar;
    VScrollBar: TScrollBar;
    PaintBox: TSkPaintBox;
    btnSelect: TSpeedButton;
    btnAddSpecies: TSpeedButton;
    btnNew: TSpeedButton;
    btnOpen: TSpeedButton;
    btnSave: TSpeedButton;
    bynAddBiBi: TSpeedButton;
    btnAddUniBi: TSpeedButton;
    btnAddBiUni: TSpeedButton;
    btnAddUniUni: TSpeedButton;
    NodePopupMenu: TPopupMenu;
    mnuCreateAlias: TMenuItem;
    mnuRename: TMenuItem;
    mnuSep1: TMenuItem;
    mnuGotoPrimary: TMenuItem;
    mnuSep2: TMenuItem;
    mnuDeleteNode: TMenuItem;
    btnToggleAlias: TSpeedButton;
    ImageList1: TImageList;
    Glyph1: TGlyph;
    Glyph2: TGlyph;
    Glyph3: TGlyph;
    Glyph4: TGlyph;
    Glyph5: TGlyph;
    Glyph6: TGlyph;
    Glyph7: TGlyph;
    Glyph8: TGlyph;
    Glyph9: TGlyph;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    mnuHelp: TMenuItem;
    mnuAbout: TMenuItem;
    mnuQuit: TMenuItem;
    mnuNew: TMenuItem;
    mnuFileOpen: TMenuItem;
    mnuSave: TMenuItem;
    MenuItem1: TMenuItem;
    mnuExport: TMenuItem;
    mnuPrint: TMenuItem;
    mnuExportToPng: TMenuItem;
    mnuExporttoPdf: TMenuItem;
    mnuImportAntimony: TMenuItem;
    MenuItem3: TMenuItem;
    mnuExportAntimony: TMenuItem;
    lblStatus: TLabel;
    btnLayout: TSpeedButton;
    btnLinearUniUni: TSpeedButton;
    btnRandomNetwork: TSpeedButton;
    btnSetBezier: TSpeedButton;
    btnSmoothJunction: TSpeedButton;
    mnuMakeNiceReaction: TMenuItem;
    mnuEdit: TMenuItem;
    mnuUndo: TMenuItem;
    mnuRedo: TMenuItem;
    MenuItem5: TMenuItem;
    btnMakeNice: TSpeedButton;
    Layout5: TLayout;
    ColorAnimation1: TColorAnimation;
    ColorAnimation2: TColorAnimation;
    GroupBox1: TGroupBox;
    ccbSpeciesFillColor: TColorComboBox;
    ccbSpeciesBorderColor: TColorComboBox;
    Label1: TLabel;
    Label2: TLabel;
    mnuSaveToSBML: TMenuItem;
    MenuItem6: TMenuItem;
    Label3: TLabel;
    edtNumConcentration: TNumberBox;
    moAntimony: TMemo;
    btnLoadAnt: TButton;
    chkDeckard: TCheckBox;
    chkRandomize: TCheckBox;
    mnuAlignment: TMenuItem;
    mnuAlignTop: TMenuItem;
    mnuAlignMiddle: TMenuItem;
    mnuAlignBottom: TMenuItem;
    MenuItem8: TMenuItem;
    mnuAlignLeft: TMenuItem;
    mnuAlignCenter: TMenuItem;
    mnuAlignRight: TMenuItem;
    MenuItem2: TMenuItem;
    mnuDistribHorizontally: TMenuItem;
    mnuDistribVertically: TMenuItem;
    mnuLockUnLockNode: TMenuItem;
    Label4: TLabel;
    HoverTimer: TTimer;
    procedure btnAddBiUniClick(Sender: TObject);
    procedure btnAddSpeciesClick(Sender: TObject);
    procedure btnAddUniBiClick(Sender: TObject);
    procedure btnAddUniUniClick(Sender: TObject);
    procedure btnLayoutClick(Sender: TObject);
    procedure btnLinearUniUniClick(Sender: TObject);
    procedure btnLoadAntClick(Sender: TObject);
    procedure btnMakeNiceClick(Sender: TObject);
    procedure btnNewClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnRandomNetworkClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnSelectClick(Sender: TObject);
    procedure btnSetBezierClick(Sender: TObject);
    procedure btnSmoothJunctionClick(Sender: TObject);
    procedure btnToggleAliasClick(Sender: TObject);
    procedure bynAddBiBiClick(Sender: TObject);
    procedure ccbSpeciesBorderColorChange(Sender: TObject);
    procedure ccbSpeciesFillColorChange(Sender: TObject);
    procedure chkDeckardChange(Sender: TObject);
    procedure chkRandomizeChange(Sender: TObject);
    procedure edtNumConcentrationExit(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
        Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure HoverTimerTimer(Sender: TObject);
    procedure HScrollBarChange(Sender: TObject);
    procedure mnuAboutClick(Sender: TObject);
    procedure mnuAlignBottomClick(Sender: TObject);
    procedure mnuAlignCenterClick(Sender: TObject);
    procedure mnuAlignLeftClick(Sender: TObject);
    procedure mnuAlignMiddleClick(Sender: TObject);
    procedure mnuAlignRightClick(Sender: TObject);
    procedure mnuAlignTopClick(Sender: TObject);
    procedure mnuCreateAliasClick(Sender: TObject);
    procedure mnuDeleteNodeClick(Sender: TObject);
    procedure mnuDistribHorizontallyClick(Sender: TObject);
    procedure mnuDistribVerticallyClick(Sender: TObject);
    procedure mnuExportAntimonyClick(Sender: TObject);
    procedure mnuGotoPrimaryClick(Sender: TObject);
    procedure mnuImportAntimonyClick(Sender: TObject);
    procedure mnuLockUnLockNodeClick(Sender: TObject);
    procedure mnuMakeNiceReactionClick(Sender: TObject);
    procedure mnuQuitClick(Sender: TObject);
    procedure mnuRedoClick(Sender: TObject);
    procedure mnuRenameClick(Sender: TObject);
    procedure mnuSaveToSBMLClick(Sender: TObject);
    procedure mnuUndoClick(Sender: TObject);
    procedure PaintBoxDblClick(Sender: TObject);
    procedure PaintBoxDraw(ASender: TObject; const ACanvas: ISkCanvas; const ADest:
        TRectF; const AOpacity: Single);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift:
        TShiftState; X, Y: Single);
    procedure PaintBoxMouseLeave(Sender: TObject);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift:
        TShiftState; X, Y: Single);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta:
        Integer; var Handled: Boolean);
    procedure VScrollBarChange(Sender: TObject);
  private
    { Private declarations }
    // --- Domain objects ---
    FModel : TBioModel;
    FView  : TDiagramView;

    // --- Flag to suppress re-entrant scrollbar updates ---
    FUpdatingScrollBars : Boolean;
    bolDeckard : Boolean;
    bolRandomize : Boolean;

    // The species / reaction that was right-clicked, set in PaintBoxMouseUp.
    FRightClickSpecies  : TSpeciesNode;
    FRightClickReaction : TReaction;

    // Recompute scrollbar Min/Max/ViewportSize from the model's content bounds.
    // Call whenever the diagram changes (add/remove/move).
    procedure UpdateScrollBars;

    // Propagate scrollbar positions into FView.ScrollOffset and repaint.
    procedure ApplyScrollToView;
    procedure SetScrollBarDefaults;

    // Delete all currently selected species and reactions.
    // Each selected species also cascade-deletes its connected reactions.
    procedure DeleteSelected;

    procedure UpdateStatusBar;
    procedure ExportAntimony;
    procedure ImportAntimony;

    procedure ExportSBML;
    procedure ImportSBML;

    procedure DiagramNeedRepaint(Sender: TObject);

  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

Uses Math;



procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FView.Free;
  FModel.Free;
end;

procedure TfrmMain.DiagramNeedRepaint(Sender: TObject);
begin
  PaintBox.Redraw;
end;


procedure TfrmMain.FormCreate(Sender: TObject);
begin
  inherited;
  Caption := 'Biochemical Network Editor';

  // --- Domain objects -----------------------------------------------------
  FModel := TBioModel.Create;
  FView  := TDiagramView.Create(FModel, False {form owns the model separately});
  FView.DefaultBezier := True;
  FView.DefaultSmoothJunction := True;
  FView.LoadTestData;
  bolDeckard := False;
  bolRandomize := False;
  SetScrollBarDefaults;
  btnToggleAlias.Text := 'Alias ✓';
  btnSmoothJunction.Text := 'Smooth J';

  FView.OnNeedRepaint := DiagramNeedRepaint;
end;


procedure TfrmMain.ApplyScrollToView;
begin
  if not Assigned(FView) then Exit;
  // ScrollOffset is a direct pixel translation — no zoom needed here because
  // the world→screen transform in uDiagramView handles zoom separately.
  FView.ScrollOffset := TPointF.Create(-HScrollBar.Value, -VScrollBar.Value);
  PaintBox.Redraw;
end;


procedure TfrmMain.btnAddBiUniClick(Sender: TObject);
begin
  FView.SetModeAddReaction(2, 1);   // 2 reactants, 1 product — click 3 species
end;


procedure TfrmMain.btnAddSpeciesClick(Sender: TObject);
begin
  FView.SetModeAddSpecies;
end;


procedure TfrmMain.btnAddUniBiClick(Sender: TObject);
begin
  FView.SetModeAddReaction(1, 2);   // 1 reactant, 2 products — click 3 species
end;

procedure TfrmMain.btnAddUniUniClick(Sender: TObject);
begin
  FView.SetModeAddReaction(1, 1);   // 1 reactant, 1 product — click 2 species
end;

procedure TfrmMain.btnLayoutClick(Sender: TObject);
var MethodList : TStringList;
    errMsg : String;
    S : TSpeciesNode;
    P : TParticipant;
    SumX, SumY : Single;
    Count : Integer;
begin
  if bolRandomize then
  begin
  for S in FModel.Species do
      S.Center := TPointF.Create(Random(400) + 100, Random(400) + 100);

for var R in FModel.Reactions do
begin
  SumX := 0; SumY := 0; Count := 0;
  for P in R.Reactants do
  begin SumX := SumX + P.Species.Center.X; SumY := SumY + P.Species.Center.Y; Inc(Count); end;
  for P in R.Products do
  begin SumX := SumX + P.Species.Center.X; SumY := SumY + P.Species.Center.Y; Inc(Count); end;
  if Count > 0 then
    R.JunctionPos := TPointF.Create(SumX / Count, SumY / Count);
end;

for var R in FModel.Reactions do
  for P in R.Reactants do P.ResetCtrlPts;
for var R in FModel.Reactions do
  for P in R.Products do P.ResetCtrlPts;
 end;

  FView.AutoLayout (800, bolDeckard);
  UpdateScrollBars;
  PaintBox.Redraw;
end;

procedure TfrmMain.btnLinearUniUniClick(Sender: TObject);
begin
  FView.ToggleLinearSelected;
  PaintBox.Redraw;
end;

procedure TfrmMain.btnLoadAntClick(Sender: TObject);
begin
  FView.ImportAntimony(moAntimony.Text);

  UpdateScrollBars;
  UpdateStatusBar;
  PaintBox.Redraw;
end;

procedure TfrmMain.btnMakeNiceClick(Sender: TObject);
var R : TReaction;
begin
  for R in FModel.SelectedReactions do
    if FModel.FindReactionById(R.Id) <> nil then
      FView.NiceBezierForReaction(R.Id);
  PaintBox.Redraw;
end;

procedure TfrmMain.btnNewClick(Sender: TObject);
begin
  if MessageDlg('Clear the current diagram?', TMsgDlgType.mtConfirmation,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes then
    Exit;

  FView.NewDiagram;
  UpdateScrollBars;
  PaintBox.Redraw;

end;

procedure TfrmMain.btnOpenClick(Sender: TObject);
var
  Dlg : TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title  := 'Load Network';
    Dlg.Filter := 'JSON files (*.json)|*.json|All files (*.*)|*.*';
    if Dlg.Execute then
    begin
      FView.LoadFromFile(Dlg.FileName);
      frmMain.Caption := 'Biochemcal Network Editor:  ' + Dlg.FileName;
      UpdateScrollBars;
      PaintBox.Redraw;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.btnRandomNetworkClick(Sender: TObject);
begin
  TRandomNetwork.Generate(FModel, 10, 12);  // 8 species, 10 reactions
  FView.SyncSpeciesIdCounter;            // keep S-name counter in sync
  //FView.AutoLayout;                        // arrange sensibly
  HScrollBar.Value := 0;
  VScrollBar.Value := 0;
  PaintBox.Redraw;
end;


procedure TfrmMain.btnSaveClick(Sender: TObject);
var
  Dlg : TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title      := 'Save Network';
    Dlg.DefaultExt := 'json';
    Dlg.Filter     := 'JSON files (*.json)|*.json|All files (*.*)|*.*';
    if Dlg.Execute then
      FView.SaveToFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.btnSelectClick(Sender: TObject);
begin
  FView.SetModeSelect;
end;

procedure TfrmMain.btnSetBezierClick(Sender: TObject);
begin
  FView.SetBezierSelected;
  PaintBox.Redraw;
end;

procedure TfrmMain.btnSmoothJunctionClick(Sender: TObject);
begin
  // Toggle IsJunctionSmooth on every selected Bézier reaction independently.
  // Non-Bézier reactions are silently skipped.
  FView.ToggleJunctionSmoothSelected;
  PaintBox.Redraw;   // redraws inner handles in teal when mode is active
end;

procedure TfrmMain.btnToggleAliasClick(Sender: TObject);
begin
  // Toggle the alias indicator and update the button caption to show state.
  FView.ShowAliasIndicator := not FView.ShowAliasIndicator;
  if FView.ShowAliasIndicator then
    btnToggleAlias.Text := 'Alias ✓'
  else
    btnToggleAlias.Text := 'Alias ○';
  PaintBox.Redraw;
end;

procedure TfrmMain.bynAddBiBiClick(Sender: TObject);
begin
  FView.SetModeAddReaction(2, 2);   // 2 reactants, 2 products — click 4 species
end;

procedure TfrmMain.ccbSpeciesBorderColorChange(Sender: TObject);
var S : TSpeciesNode;
begin
  for S in FModel.SelectedSpecies do
      begin
      S.Style.HasCustomStyle := True;
      S.Style.BorderColor := ccbSpeciesBorderColor.Color;
      end;
  PaintBox.Redraw;
end;

procedure TfrmMain.ccbSpeciesFillColorChange(Sender: TObject);
var S : TSpeciesNode;
begin
  for S in FModel.SelectedSpecies do
      begin
      S.Style.HasCustomStyle := True;
      S.Style.FillColor := ccbSpeciesFillColor.Color;
      end;
  PaintBox.Redraw;
end;

procedure TfrmMain.chkDeckardChange(Sender: TObject);
begin
   if chkDeckard.IsChecked then
      bolDeckard := True
   else
      bolDeckard := False;
end;

procedure TfrmMain.chkRandomizeChange(Sender: TObject);
begin
   if chkRandomize.IsChecked then
      bolRandomize := True
   else
      bolRandomize := False;
end;

procedure TfrmMain.SetScrollBarDefaults;
const
  CANVAS_SIZE = 8000;
begin
  HScrollBar.Min          := 0;
  HScrollBar.Max          := CANVAS_SIZE;
  HScrollBar.ViewportSize := 400;
  HScrollBar.SmallChange  := 20;
  HScrollBar.Value        := 0;

  VScrollBar.Min          := 0;
  VScrollBar.Max          := CANVAS_SIZE;
  VScrollBar.ViewportSize := 400;
  VScrollBar.SmallChange  := 20;
  VScrollBar.Value        := 0;
end;


procedure TfrmMain.UpdateScrollBars;
begin
  // With fixed scrollbar ranges, there is nothing to recompute — just
  // propagate the current scrollbar position to the view.
  ApplyScrollToView;
end;



procedure TfrmMain.DeleteSelected;
//
//  Deletion order matters:
//    1. Gather selected species.  Each species deletion cascade-removes its
//       connected reactions (even if those reactions are not in the selection).
//    2. After species are gone, delete any remaining selected reactions
//       (reactions that were selected but not already removed by cascade).
//
//  Note: this currently operates directly on the model.  In the command-
//  pattern phase this will be wrapped in a TDeleteSelectionCmd that captures
//  full before-state so it can be undone atomically.
//
var
  SelSpecies   : TArray<TSpeciesNode>;
  SelReactions : TArray<TReaction>;
  S            : TSpeciesNode;
  R            : TReaction;
  Dummy        : TArray<string>;
begin
  SelSpecies   := FModel.SelectedSpecies;
  SelReactions := FModel.SelectedReactions;

  // Nothing selected → nothing to do
  if (Length(SelSpecies) = 0) and (Length(SelReactions) = 0) then
    Exit;

  // Step 1: delete species (cascade removes connected reactions)
  for S in SelSpecies do
    FModel.DeleteSpecies(S, Dummy);

  // Step 2: delete any remaining selected reactions
  // (a reaction that was selected but whose participants were not deleted
  //  survives step 1 and must be removed explicitly)
  for R in SelReactions do
    if FModel.FindReactionById(R.Id) <> nil then
      FModel.DeleteReaction(R);

  UpdateScrollBars;   // content extent may have changed
  PaintBox.Redraw;
end;

procedure TfrmMain.edtNumConcentrationExit(Sender: TObject);
var S : TSpeciesNode;
begin
  for S in FModel.SelectedSpecies do
      S.InitialValue := edtNumConcentration.Value;
end;


procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar:
    WideChar; Shift: TShiftState);
begin
  FView.KeyDown(Key, KeyChar, Shift);
  if Key = 0 then
  begin
    UpdateScrollBars;   // content may have changed (e.g. Delete key)
    PaintBox.Redraw;
  end;
end;


procedure TfrmMain.FormResize(Sender: TObject);
begin
//
end;


procedure TfrmMain.HScrollBarChange(Sender: TObject);
begin
  if not FUpdatingScrollBars then ApplyScrollToView
end;

procedure TfrmMain.mnuAboutClick(Sender: TObject);
begin
    TDialogServiceSync.MessageDialog(
    'PathwayDesigner Version: ' + APP_VERSION + sLineBreak + 'Build Time: ' + BUILD_DATE, TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbNo, 0);
end;


procedure TfrmMain.PaintBoxDblClick(Sender: TObject);
begin
  // OnDblClick carries no coordinates; TDiagramView uses the stored
  // mouse position from the most recent MouseMove/MouseDown.
  FView.MouseDblClick;
  PaintBox.Redraw;
end;

procedure TfrmMain.PaintBoxDraw(ASender: TObject; const ACanvas: ISkCanvas;
    const ADest: TRectF; const AOpacity: Single);
begin
  FView.Render(ACanvas, ADest.Width, ADest.Height);
end;


procedure TfrmMain.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Single);
var
  Target      : TRightClickTarget;
  HitSpecies  : TSpeciesNode;
  HitReaction : TReaction;
begin
  if Button = TMouseButton.mbLeft then
  begin
    FView.MouseDown(Button, Shift, X, Y);
    UpdateScrollBars;
    PaintBox.Redraw;
    Exit;
  end;

  // --- Right-click: hit-test and show context menu (Steps 3 & 4) ----------
  if Button = TMouseButton.mbRight then
  begin
    Target := FView.RightClickHitTest(X, Y, HitSpecies, HitReaction);

    // Cache the hit objects so menu handlers can use them.
    FRightClickSpecies  := HitSpecies;
    FRightClickReaction := HitReaction;

    // Configure which items are visible/enabled based on what was hit.
    case Target of
      rctPrimary:
      begin
        mnuCreateAlias.Visible := True;
        mnuRename.Visible      := True;
        mnuGoToPrimary.Visible := False;
        mnuSep1.Visible        := True;
        mnuSep2.Visible        := False;
        mnuDeleteNode.Visible  := True;
        mnuDeleteNode.Text     := 'Delete Species';
      end;

      rctAlias:
      begin
        mnuCreateAlias.Visible := False;
        mnuRename.Visible      := True;   // renames the shared primary name
        mnuGoToPrimary.Visible := True;
        mnuSep1.Visible        := True;
        mnuSep2.Visible        := True;
        mnuDeleteNode.Visible  := True;
        mnuDeleteNode.Text     := 'Delete Alias';
      end;

      rctReaction:
      begin
        mnuCreateAlias.Visible := False;
        mnuRename.Visible      := False;
        mnuGoToPrimary.Visible := False;
        mnuSep1.Visible        := False;
        mnuSep2.Visible        := False;
        mnuDeleteNode.Visible  := True;
        mnuDeleteNode.Text     := 'Delete Reaction';
      end;

      rctNone:
        Exit;   // nothing hit — don't show the menu
    end;

    var ScreenPos := PaintBox.LocalToScreen(TPointF.Create(X, Y));
    NodePopupMenu.Popup(Round(ScreenPos.X), Round(ScreenPos.Y));
  end;
end;


procedure TfrmMain.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  FView.MouseMove(Shift, X, Y);

  // Reset the hover timer whenever the mouse moves
  HoverTimer.Enabled := False;
  HoverTimer.Enabled := True;

  PaintBox.Redraw;
end;


procedure TfrmMain.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    FView.MouseUp(Button, Shift, X, Y);
    UpdateScrollBars;
    PaintBox.Redraw;
    Exit;
  end;
end;


procedure TfrmMain.VScrollBarChange(Sender: TObject);
begin
  if not FUpdatingScrollBars then ApplyScrollToView
end;


// ===========================================================================
//  Popup menu handlers  (Steps 4 & 5)
// ===========================================================================


procedure TfrmMain.mnuCreateAliasClick(Sender: TObject);
begin
  if not Assigned(FRightClickSpecies) then Exit;
  FView.CreateAliasAt(FRightClickSpecies);
  UpdateScrollBars;
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuDeleteNodeClick(Sender: TObject);
var
  Dummy : TArray<string>;
begin
  if Assigned(FRightClickSpecies) then
  begin
    FModel.DeleteSpecies(FRightClickSpecies, Dummy);
    FRightClickSpecies := nil;
  end
  else if Assigned(FRightClickReaction) then
  begin
    FModel.DeleteReaction(FRightClickReaction);
    FRightClickReaction := nil;
  end;
  UpdateScrollBars;
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuGotoPrimaryClick(Sender: TObject);
begin
  if not Assigned(FRightClickSpecies) then Exit;
  FView.GoToPrimary(FRightClickSpecies);
  UpdateScrollBars;
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuQuitClick(Sender: TObject);
begin
   Application.Terminate;
end;


procedure TfrmMain.mnuRenameClick(Sender: TObject);
var
  EditTarget : TSpeciesNode;
  NewId    : string;
begin
  if not Assigned(FRightClickSpecies) then Exit;

  // Rename always edits the primary's name so all aliases reflect it.
  if FRightClickSpecies.IsAlias then
    EditTarget := FRightClickSpecies.AliasOf
  else
    EditTarget := FRightClickSpecies;

  NewId := InputBox('Rename Species', 'Id:', EditTarget.Id);
  if (NewId <> '') and (NewId <> EditTarget.Id) then
  begin
    // Route through the view so FitNodeToText and undo are both handled.
    EditTarget.Id := NewId;
    FModel.RenameSpeciesId(EditTarget.Id, NewId);
    FView.FitNodeToText(EditTarget);
    PaintBox.Redraw;
  end;
end;


procedure TfrmMain.UpdateStatusBar;
begin
  if not Assigned(lblStatus) then Exit;
  if FView.HasNonDefaultCompartments then
    lblStatus.Text :=
      '⚠  Model contains non-default compartments ' +
      '(stored in model; compartment visualisation not yet implemented)'
  else
    lblStatus.Text := '';
end;


// ---------------------------------------------------------------------------
//  Antimony import
// ---------------------------------------------------------------------------

procedure TfrmMain.ImportAntimony;
var
  Dlg    : TOpenDialog;
  SL     : TStringList;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title  := 'Import Antimony Model';
    Dlg.Filter := 'Antimony files (*.ant;*.txt)|*.ant;*.txt|All files (*.*)|*.*';
    if not Dlg.Execute then Exit;

    SL := TStringList.Create;
    try
      SL.LoadFromFile(Dlg.FileName, TEncoding.UTF8);
      try
        FView.ImportAntimony(SL.Text);
      except
        on E: Exception do
        begin
          MessageDlg('Error importing Antimony:'#13#10 + E.Message,
                     TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
          Exit;
        end;
      end;
    finally
      SL.Free;
    end;
  finally
    Dlg.Free;
  end;

  UpdateScrollBars;
  UpdateStatusBar;
  PaintBox.Redraw;
end;

// ---------------------------------------------------------------------------
//  Antimony export
// ---------------------------------------------------------------------------

procedure TfrmMain.ExportAntimony;
var
  Dlg  : TSaveDialog;
  SL   : TStringList;
  Text : string;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title      := 'Export Antimony Model';
    Dlg.DefaultExt := 'ant';
    Dlg.Filter     := 'Antimony files (*.ant)|*.ant|Text files (*.txt)|*.txt|All files (*.*)|*.*';
    if not Dlg.Execute then Exit;

    Text := FView.ExportAntimony;
    SL   := TStringList.Create;
    try
      SL.Text := Text;
      SL.SaveToFile(Dlg.FileName, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.mnuExportAntimonyClick(Sender: TObject);
begin
  ExportAntimony;
end;

procedure TfrmMain.mnuImportAntimonyClick(Sender: TObject);
begin
  ImportAntimony;
end;

procedure TfrmMain.mnuMakeNiceReactionClick(Sender: TObject);
begin
  if Assigned(FRightClickReaction) then
    FView.NiceBezierForReaction(FRightClickReaction.Id);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuRedoClick(Sender: TObject);
begin
  FView.Redo;
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuSaveToSBMLClick(Sender: TObject);
begin
   ExportSBML;
end;

procedure TfrmMain.ImportSBML;
var
  Dlg : TOpenDialog;
  SL  : TStringList;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title  := 'Import SBML Model';
    Dlg.Filter := 'SBML files (*.xml;*.sbml)|*.xml;*.sbml|All files (*.*)|*.*';
    if not Dlg.Execute then Exit;

    SL := TStringList.Create;
    try
      SL.LoadFromFile(Dlg.FileName, TEncoding.UTF8);
      try
        FView.ImportSBML(SL.Text);
      except
        on E: Exception do
        begin
          MessageDlg('Error importing SBML:'#13#10 + E.Message,
                     TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
          Exit;
        end;
      end;
    finally
      SL.Free;
    end;
  finally
    Dlg.Free;
  end;
  UpdateScrollBars;
  UpdateStatusBar;
  PaintBox.Redraw;
end;

procedure TfrmMain.ExportSBML;
var
  Dlg  : TSaveDialog;
  SL   : TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title      := 'Export SBML Model';
    Dlg.DefaultExt := 'xml';
    Dlg.Filter     := 'SBML files (*.xml)|*.xml|All files (*.*)|*.*';
    if not Dlg.Execute then Exit;

    SL := TStringList.Create;
    try
      SL.Text := FView.ExportSBML;
      SL.SaveToFile(Dlg.FileName, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.HoverTimerTimer(Sender: TObject);
begin
  HoverTimer.Enabled := False;
  FView.ShowTooltip;
end;

procedure TfrmMain.mnuAlignBottomClick(Sender: TObject);
begin
  FView.AlignSelection(amBottom);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuAlignCenterClick(Sender: TObject);
begin
  FView.AlignSelection(amCenterH);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuAlignLeftClick(Sender: TObject);
begin
  FView.AlignSelection(amLeft);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuAlignMiddleClick(Sender: TObject);
begin
  FView.AlignSelection(amMiddleV);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuAlignRightClick(Sender: TObject);
begin
  FView.AlignSelection(amRight);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuAlignTopClick(Sender: TObject);
begin
  FView.AlignSelection(amTop);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuDistribHorizontallyClick(Sender: TObject);
begin
  FView.AlignSelection(amDistributeH);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuDistribVerticallyClick(Sender: TObject);
begin
  FView.AlignSelection(amDistributeV);
  PaintBox.Redraw;
end;

procedure TfrmMain.mnuLockUnLockNodeClick(Sender: TObject);
begin
//
end;

procedure TfrmMain.mnuUndoClick(Sender: TObject);
begin
  FView.Undo;
  PaintBox.Redraw;
end;

procedure TfrmMain.PaintBoxMouseLeave(Sender: TObject);
begin
  HoverTimer.Enabled := False;
  FView.HideTooltip;
end;

procedure TfrmMain.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
    WheelDelta: Integer; var Handled: Boolean);
var
  MousePos : TPointF;
begin
  if not (ssCtrl in Shift) then Exit;

  MousePos := PaintBox.ScreenToLocal(Screen.MousePos);
  FView.ZoomAtPoint(MousePos, WheelDelta);

  // Sync scrollbar values to match the new ScrollOffset that ZoomAtPoint
  // computed. Without this, the next scrollbar move snaps back to the old
  // position because ApplyScrollToView recomputes offset from the stale values.
  FUpdatingScrollBars := True;
  try
    HScrollBar.Value := -Round(FView.ScrollOffset.X);
    VScrollBar.Value := -Round(FView.ScrollOffset.Y);
  finally
    FUpdatingScrollBars := False;
  end;

  PaintBox.Redraw;
  Handled := True;
end;

end.
