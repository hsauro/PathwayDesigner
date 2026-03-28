unit uColorPicker;
{
  uColorPicker  —  Lightweight FMX colour-picker popup.
  No companion .fmx file required; all controls are built in code.

  USAGE
  -----
    // Create once (e.g. FormCreate):
    FColorPicker := TColorPickerPopup.Create(Self);
    FColorPicker.OnColorChanged := HandleColorChanged;

    // Open it anchored to any swatch control:
    FColorPicker.Color := ASpecies.Style.FillColor;
    FColorPicker.ShowAt(rectFillSwatch);

    // Read the result in the callback:
    procedure TfrmMain.HandleColorChanged(Sender: TObject);
    begin
      rectFillSwatch.Fill.Color    := FColorPicker.Color;
      ASpecies.Style.FillColor     := FColorPicker.Color;
      ASpecies.Style.HasCustomStyle := True;
      PaintBox.Redraw;
    end;

  NOTES
  -----
  * Clicking a palette swatch fires OnColorChanged and closes the popup.
  * Typing a hex value (#RRGGBB) and pressing Enter or clicking Apply
    also fires OnColorChanged and closes the popup.
  * The swatch matching the current Color is highlighted with a blue border.
  * The palette includes every CLR_* colour from uDiagramView so the user
    can easily round-trip back to the renderer defaults.
}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.UIConsts,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics,
  FMX.Objects, FMX.StdCtrls, FMX.Edit, FMX.Layouts,
  FMX.Controls.Presentation;

// ---------------------------------------------------------------------------
//  Palette  —  8 columns × 5 rows = 40 swatches
//
//  Row 1  Neutrals
//  Row 2  Blues      (includes CLR_NODE_FILL, CLR_NODE_BORDER, CLR_REACTION_SEL)
//  Row 3  Purples    (includes CLR_ALIAS_FILL, CLR_ALIAS_BORDER)
//  Row 4  Warm tones (includes CLR_JCT_FILL, CLR_RING_PRODUCT, CLR_RING_REACTANT)
//  Row 5  Diagram-specific defaults + useful light tints
// ---------------------------------------------------------------------------
const
  CP_PALETTE : array[0..39] of TAlphaColor = (
    // Row 1 — Neutrals
    $FFFFFFFF, $FFF0F0F0, $FFD0D0D0, $FFB0B0B0,
    $FF808080, $FF505050, $FF282828, $FF000000,
    // Row 2 — Blues
    $FFEEF6FF,  // CLR_NODE_FILL
    $FFCCE0FF,  // CLR_NODE_FILL_SEL
    $FF9DBFFF,
    $FF4A7FCB,  // CLR_NODE_BORDER
    $FF2255CC,
    $FF1144CC,  // CLR_REACTION_SEL / CLR_NODE_BORD_SEL / CLR_JCT_FILL_SEL
    $FF003399,
    $FF0099CC,
    // Row 3 — Purples
    $FFF5F0FF,  // CLR_ALIAS_FILL
    $FFE8DEFF,
    $FFD4C8FF,
    $FFB39DDB,
    $FF9575CD,
    $FF7A6FC8,  // CLR_ALIAS_BORDER
    $FF553399,
    $FF330066,
    // Row 4 — Warm
    $FF00AA44,  // CLR_RING_REACTANT
    $FF33CC66,
    $FF88CC00,
    $FFFFCC00,
    $FFFF8800,  // CLR_JCT_FILL
    $FFA05000,  // CLR_JCT_BORDER
    $FFCC3300,  // CLR_RING_PRODUCT
    $FFFF4444,
    // Row 5 — Diagram defaults + light tints
    $FFF8F9FA,  // CLR_BACKGROUND
    $FF1A1A1A,  // CLR_LABEL
    $FF444444,  // CLR_REACTION
    $FF888888,  // CLR_GUIDE_LINE
    $FFFFF9C4,  // soft yellow
    $FFFFE0B2,  // soft orange
    $FFE8F5E9,  // soft green
    $FFFFE8E8   // soft red
  );

type
  TColorPickerPopup = class
  private
    FOwner          : TComponent;
    FPopup          : TForm;
    FColor          : TAlphaColor;
    FOnColorChanged : TNotifyEvent;
    FUpdatingUI     : Boolean;

    // UI controls — all owned by FPopup, freed when FPopup is freed
    FCurrentSwatch  : TRectangle;
    FCurrentHexLbl  : TLabel;
    FSwatches       : array[0..39] of TRectangle;
    FHexEdit        : TEdit;
    FApplyBtn       : TButton;

    procedure BuildUI;
    procedure SwatchClick     (Sender: TObject);
    procedure SwatchMouseEnter(Sender: TObject);
    procedure SwatchMouseLeave(Sender: TObject);
    procedure HexEditKeyDown  (Sender: TObject; var Key: Word;
                               var KeyChar: WideChar; Shift: TShiftState);
    procedure ApplyBtnClick   (Sender: TObject);

    procedure SetColor(const AColor: TAlphaColor);
    procedure SyncUI;
    procedure ApplyHexInput;
    procedure FireChanged;
    procedure UpdateSwatchBorders;
    function  ColorToHexStr(AColor: TAlphaColor): string;
    function  TryHexToColor(const S: string; out AColor: TAlphaColor): Boolean;
  public
    constructor Create(AOwner: TComponent);
    destructor  Destroy; override;

    // Open the picker anchored below AControl.
    procedure ShowAt(AControl: TControl);
    procedure Close;

    // Get or set the current colour.  Setting it updates the UI immediately.
    property Color          : TAlphaColor  read FColor write SetColor;

    // Fired after the user confirms a colour (swatch click or Apply).
    // Read the Color property inside the handler.
    property OnColorChanged : TNotifyEvent read FOnColorChanged write FOnColorChanged;
  end;

implementation

// ---------------------------------------------------------------------------
//  Layout constants
// ---------------------------------------------------------------------------
const
  CP_W       = 22;    // swatch width  (px)
  CP_H       = 22;    // swatch height (px)
  CP_GAP     = 3;     // gap between swatches
  CP_COLS    = 8;
  CP_ROWS    = 5;
  CP_PAD     = 10;    // outer padding of the popup card

  // Derived geometry
  // Grid content width  = 8 swatches * (22+3) - 3 trailing gap = 197
  // Grid content height = 5 swatches * (22+3) - 3 trailing gap = 122
  CP_GRID_W   = CP_COLS * (CP_W + CP_GAP) - CP_GAP;  // 197
  CP_GRID_H   = CP_ROWS * (CP_H + CP_GAP) - CP_GAP;  // 122

  CP_HDR_H    = 28;   // header row (current swatch + hex label)
  CP_FOOT_H   = 28;   // footer row (hex edit + apply button)
  CP_SEP_H    = 1;    // thin separator line height
  CP_SP       = 6;    // vertical spacing between sections

  // Total popup dimensions
  CP_POPUP_W  = CP_PAD + CP_GRID_W + CP_PAD;                // 217
  CP_POPUP_H  = CP_PAD                                       // top pad
              + CP_HDR_H  + CP_SP                            // header
              + CP_SEP_H  + CP_SP                            // separator
              + CP_GRID_H + CP_SP                            // grid
              + CP_SEP_H  + CP_SP                            // separator
              + CP_FOOT_H + CP_PAD;                          // footer + bottom pad

  // Colours used for UI chrome
  CP_CLR_SEL_BORDER  : TAlphaColor = $FF1144CC;  // border of selected swatch
  CP_CLR_HOV_BORDER  : TAlphaColor = $FF444444;  // border on hover
  CP_CLR_DEF_BORDER  : TAlphaColor = $FFCCCCCC;  // default swatch border
  CP_CLR_SEP         : TAlphaColor = $FFE0E0E0;  // separator line colour
  CP_CLR_BG          : TAlphaColor = $FFFFFFFF;  // popup background
  CP_CLR_CARD_BORDER : TAlphaColor = $FFC8C8C8;  // popup card border
  CP_CLR_LABEL       : TAlphaColor = $FF666666;  // small label text
  CP_CLR_HEX_TEXT    : TAlphaColor = $FF333333;  // hex edit text
  CP_CLR_HEX_ERR     : TAlphaColor = $FFCC2200;  // hex edit text when invalid

// ---------------------------------------------------------------------------

constructor TColorPickerPopup.Create(AOwner: TComponent);
begin
  inherited Create;
  FOwner      := AOwner;
  FColor      := claWhite;
  FUpdatingUI := False;
  BuildUI;
end;

destructor TColorPickerPopup.Destroy;
begin
  FPopup.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

function TColorPickerPopup.ColorToHexStr(AColor: TAlphaColor): string;
begin
  // Format as #RRGGBB (drop alpha channel for display)
  Result := Format('#%.2x%.2x%.2x',
                   [(AColor shr 16) and $FF,
                    (AColor shr  8) and $FF,
                     AColor         and $FF]);
end;

function TColorPickerPopup.TryHexToColor(const S: string;
                                          out AColor: TAlphaColor): Boolean;
var
  Hex : string;
  V   : Integer;
begin
  Result := False;
  Hex    := Trim(S);
  if (Length(Hex) > 0) and (Hex[1] = '#') then
    Delete(Hex, 1, 1);
  if Length(Hex) <> 6 then Exit;
  // Delphi recognises $ as the hex prefix in StrToInt
  if not TryStrToInt('$' + Hex, V) then Exit;
  // Force full opacity; mask to RGB only to be safe
  AColor := $FF000000 or TAlphaColor(Cardinal(V) and $00FFFFFF);
  Result := True;
end;

// ---------------------------------------------------------------------------
//  Build all controls in code — no .fmx file needed
// ---------------------------------------------------------------------------

procedure TColorPickerPopup.BuildUI;
var
  I         : Integer;
  Col, Row  : Integer;
  Sep       : TRectangle;
  Swatch    : TRectangle;
  BG        : TRectangle;
  // Running Y cursor for each section
  CursorY   : Single;
  HexLbl    : TLabel;
begin
  // ── Popup shell ──────────────────────────────────────────────────────────
  FPopup              := TForm.CreateNew(FOwner);
  FPopup.StyleLookup  := '';        // suppress default theme chrome
  FPopup.BorderStyle      := TFmxFormBorderStyle.None;
  //FPopup.FormStyle        := TFormStyle.Popup;
  //FPopup.Placement    := TPlacement.Bottom;
  FPopup.Width        := CP_POPUP_W;
  FPopup.Height       := CP_POPUP_H;

  // ── Background card ───────────────────────────────────────────────────────
  BG                    := TRectangle.Create(FPopup);
  BG.Parent             := FPopup;
  BG.Align              := TAlignLayout.Client;
  BG.Fill.Color         := CP_CLR_BG;
  BG.Stroke.Color       := CP_CLR_CARD_BORDER;
  BG.Stroke.Thickness   := 1;
  BG.XRadius            := 6;
  BG.YRadius            := 6;
  BG.HitTest            := False;   // let clicks through to children

  // ── Section Y cursor ─────────────────────────────────────────────────────
  CursorY := CP_PAD;

  // ── Header: current-colour swatch + hex string ───────────────────────────
  FCurrentSwatch                  := TRectangle.Create(FPopup);
  FCurrentSwatch.Parent           := FPopup;
  FCurrentSwatch.Position.X       := CP_PAD;
  FCurrentSwatch.Position.Y       := CursorY + (CP_HDR_H - CP_H) / 2;
  FCurrentSwatch.Width            := CP_W * 2 + CP_GAP;  // double-wide
  FCurrentSwatch.Height           := CP_H;
  FCurrentSwatch.XRadius          := 4;
  FCurrentSwatch.YRadius          := 4;
  FCurrentSwatch.Fill.Color       := FColor;
  FCurrentSwatch.Stroke.Color     := $FF888888;
  FCurrentSwatch.Stroke.Thickness := 1.5;
  FCurrentSwatch.HitTest          := False;

  FCurrentHexLbl                  := TLabel.Create(FPopup);
  FCurrentHexLbl.Parent           := FPopup;
  FCurrentHexLbl.Position.X       := CP_PAD + CP_W * 2 + CP_GAP + 8;
  FCurrentHexLbl.Position.Y       := CursorY;
  FCurrentHexLbl.Width            := 90;
  FCurrentHexLbl.Height           := CP_HDR_H;
  FCurrentHexLbl.Text             := ColorToHexStr(FColor);
  FCurrentHexLbl.VertTextAlign    := TTextAlign.Center;
  FCurrentHexLbl.TextSettings.FontColor := CP_CLR_LABEL;
  FCurrentHexLbl.HitTest          := False;

  CursorY := CursorY + CP_HDR_H + CP_SP;

  // ── Separator ─────────────────────────────────────────────────────────────
  Sep               := TRectangle.Create(FPopup);
  Sep.Parent        := FPopup;
  Sep.Position.X    := CP_PAD;
  Sep.Position.Y    := CursorY;
  Sep.Width         := CP_GRID_W;
  Sep.Height        := CP_SEP_H;
  Sep.Fill.Color    := CP_CLR_SEP;
  Sep.Stroke.Kind   := TBrushKind.None;
  Sep.HitTest       := False;

  CursorY := CursorY + CP_SEP_H + CP_SP;

  // ── Swatch grid ───────────────────────────────────────────────────────────
  for I := 0 to 39 do
  begin
    Col := I mod CP_COLS;
    Row := I div CP_COLS;

    Swatch                  := TRectangle.Create(FPopup);
    Swatch.Parent           := FPopup;
    Swatch.Position.X       := CP_PAD + Col * (CP_W + CP_GAP);
    Swatch.Position.Y       := CursorY + Row * (CP_H + CP_GAP);
    Swatch.Width            := CP_W;
    Swatch.Height           := CP_H;
    Swatch.XRadius          := 3;
    Swatch.YRadius          := 3;
    Swatch.Fill.Color       := CP_PALETTE[I];
    Swatch.Stroke.Color     := CP_CLR_DEF_BORDER;
    Swatch.Stroke.Thickness := 1;
    Swatch.Tag              := I;
    Swatch.Cursor           := crHandPoint;
    Swatch.HitTest          := True;
    Swatch.OnClick          := SwatchClick;
    Swatch.OnMouseEnter     := SwatchMouseEnter;
    Swatch.OnMouseLeave     := SwatchMouseLeave;
    FSwatches[I]            := Swatch;
  end;

  CursorY := CursorY + CP_GRID_H + CP_SP;

  // ── Separator ─────────────────────────────────────────────────────────────
  Sep               := TRectangle.Create(FPopup);
  Sep.Parent        := FPopup;
  Sep.Position.X    := CP_PAD;
  Sep.Position.Y    := CursorY;
  Sep.Width         := CP_GRID_W;
  Sep.Height        := CP_SEP_H;
  Sep.Fill.Color    := CP_CLR_SEP;
  Sep.Stroke.Kind   := TBrushKind.None;
  Sep.HitTest       := False;

  CursorY := CursorY + CP_SEP_H + CP_SP;

  // ── Footer: hex edit + Apply button ──────────────────────────────────────
  //  [ #4a7fcb____________________ ]  [ Apply ]
  //  |<--- hex edit -------------->|  |<----->|
  //  Width: grid_w - apply_w - gap      52 px
  HexLbl                   := TLabel.Create(FPopup);
  HexLbl.Parent            := FPopup;
  HexLbl.Position.X        := CP_PAD;
  HexLbl.Position.Y        := CursorY + (CP_FOOT_H - 16) / 2;
  HexLbl.Width             := 16;
  HexLbl.Height            := 16;
  HexLbl.Text              := '#';
  HexLbl.TextSettings.FontColor := CP_CLR_LABEL;
  HexLbl.HitTest           := False;

  FHexEdit                 := TEdit.Create(FPopup);
  FHexEdit.Parent          := FPopup;
  FHexEdit.Position.X      := CP_PAD + 18;
  FHexEdit.Position.Y      := CursorY + (CP_FOOT_H - 22) / 2;
  FHexEdit.Width           := CP_GRID_W - 18 - 6 - 56;
  FHexEdit.Height          := 22;
  FHexEdit.MaxLength       := 7;   // #RRGGBB
  FHexEdit.TextSettings.FontColor := CP_CLR_HEX_TEXT;
  FHexEdit.OnKeyDown       := HexEditKeyDown;

  FApplyBtn                := TButton.Create(FPopup);
  FApplyBtn.Parent         := FPopup;
  FApplyBtn.Position.X     := CP_PAD + CP_GRID_W - 56;
  FApplyBtn.Position.Y     := CursorY + (CP_FOOT_H - 22) / 2;
  FApplyBtn.Width          := 56;
  FApplyBtn.Height         := 22;
  FApplyBtn.Text           := 'Apply';
  FApplyBtn.OnClick        := ApplyBtnClick;
end;

// ---------------------------------------------------------------------------
//  UI synchronisation
// ---------------------------------------------------------------------------

procedure TColorPickerPopup.SyncUI;
begin
  if FUpdatingUI then Exit;
  FUpdatingUI := True;
  try
    FCurrentSwatch.Fill.Color       := FColor;
    FCurrentHexLbl.Text             := ColorToHexStr(FColor);
    FHexEdit.Text                   := ColorToHexStr(FColor);
    FHexEdit.TextSettings.FontColor := CP_CLR_HEX_TEXT;
    UpdateSwatchBorders;
  finally
    FUpdatingUI := False;
  end;
end;

procedure TColorPickerPopup.UpdateSwatchBorders;
var
  I : Integer;
begin
  for I := 0 to 39 do
  begin
    if CP_PALETTE[I] = FColor then
    begin
      FSwatches[I].Stroke.Color     := CP_CLR_SEL_BORDER;
      FSwatches[I].Stroke.Thickness := 2.5;
    end
    else
    begin
      FSwatches[I].Stroke.Color     := CP_CLR_DEF_BORDER;
      FSwatches[I].Stroke.Thickness := 1;
    end;
  end;
end;

procedure TColorPickerPopup.SetColor(const AColor: TAlphaColor);
begin
  FColor := AColor;
  SyncUI;
end;

procedure TColorPickerPopup.FireChanged;
begin
  if Assigned(FOnColorChanged) then
    FOnColorChanged(Self);
end;

procedure TColorPickerPopup.ApplyHexInput;
var
  C   : TAlphaColor;
  Hex : string;
begin
  // Strip the leading # if the user typed it
  Hex := Trim(FHexEdit.Text);
  if (Length(Hex) > 0) and (Hex[1] = '#') then
    Delete(Hex, 1, 1);
  FHexEdit.Text := '#' + Hex;  // normalise display

  if TryHexToColor(FHexEdit.Text, C) then
  begin
    FColor := C;
    SyncUI;
    FireChanged;
    Close;
  end
  else
  begin
    // Highlight the edit to signal invalid input — user must fix it
    FHexEdit.TextSettings.FontColor := CP_CLR_HEX_ERR;
    FHexEdit.SetFocus;
  end;
end;

// ---------------------------------------------------------------------------
//  Event handlers
// ---------------------------------------------------------------------------

procedure TColorPickerPopup.SwatchClick(Sender: TObject);
begin
  FColor := CP_PALETTE[TRectangle(Sender).Tag];
  SyncUI;
  FireChanged;
  Close;
end;

procedure TColorPickerPopup.SwatchMouseEnter(Sender: TObject);
var
  R : TRectangle;
begin
  R := TRectangle(Sender);
  // Don't override the selection highlight
  if CP_PALETTE[R.Tag] <> FColor then
  begin
    R.Stroke.Color     := CP_CLR_HOV_BORDER;
    R.Stroke.Thickness := 1.5;
  end;
end;

procedure TColorPickerPopup.SwatchMouseLeave(Sender: TObject);
var
  R : TRectangle;
begin
  R := TRectangle(Sender);
  if CP_PALETTE[R.Tag] = FColor then
  begin
    R.Stroke.Color     := CP_CLR_SEL_BORDER;
    R.Stroke.Thickness := 2.5;
  end
  else
  begin
    R.Stroke.Color     := CP_CLR_DEF_BORDER;
    R.Stroke.Thickness := 1;
  end;
end;

procedure TColorPickerPopup.HexEditKeyDown(Sender: TObject; var Key: Word;
                                            var KeyChar: WideChar;
                                            Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    ApplyHexInput;
    Key := 0;   // consume the keystroke
  end;
end;

procedure TColorPickerPopup.ApplyBtnClick(Sender: TObject);
begin
  ApplyHexInput;
end;

// ---------------------------------------------------------------------------
//  Public
// ---------------------------------------------------------------------------

procedure TColorPickerPopup.ShowAt(AControl: TControl);
var
  P : TPointF;
begin
  // Convert the bottom-left corner of AControl to screen coordinates
  P := AControl.LocalToScreen(TPointF.Create(0, AControl.Height + 2));
  FPopup.Left := Round(P.X);
  FPopup.Top  := Round(P.Y);
  SyncUI;
  FPopup.Show;
  FPopup.Activate;
end;

procedure TColorPickerPopup.Close;
begin
  FPopup.Hide;
end;

end.
