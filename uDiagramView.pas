unit uDiagramView;

{
  uDiagramView.pas
  ================
  View state, Skia render pipeline, and mouse/keyboard interaction state machine.

  All participant iteration now uses TParticipant (P.Species, P.Stoichiometry)
  rather than direct TSpeciesNode references.

  New public methods
  ------------------
  ImportAntimony(ASource)  — parse Antimony string and rebuild the diagram
  ExportAntimony           — return the current model as an Antimony string
  HasNonDefaultCompartments — forwarded from TBioModel for the status-bar hint
}

interface

uses
  System.Types,
  System.Classes,
  System.SysUtils,
  System.UITypes,
  System.Math,
  System.Generics.Collections,
  FMX.Dialogs,
  Skia,
  uBioModel,
  uGeometry,
  uAntimonyBridge,
  uAutoLayout;

// ---------------------------------------------------------------------------
const
  VIEW_NODE_CORNER     = 8.0;
  VIEW_JUNCTION_RADIUS = 5.0;
  VIEW_PRODUCT_GAP     = 6.0;
  VIEW_ARROW_LEN       = 12.0;
  VIEW_ARROW_HALF_BASE = 5.0;
  VIEW_LINE_WIDTH      = 1.5;
  VIEW_BORDER_WIDTH    = 1.5;
  VIEW_FONT_SIZE       = 12.0;

  VIEW_HIT_JUNCTION    = 8.0;
  VIEW_HIT_SEGMENT     = 6.0;

  VIEW_RING_OUTSET     = 4.0;
  VIEW_RING_WIDTH      = 2.5;
  VIEW_ALIAS_OFFSET    = 24.0;

// ---------------------------------------------------------------------------
type
  TInteractionState = (
    isSelect, isAddSpecies, isAddReaction,
    isDraggingNodes, isDraggingJunction, isRubberBand
  );

  TRightClickTarget = (rctNone, rctPrimary, rctAlias, rctReaction);

  TDiagramView = class
  private
    FModel              : TBioModel;
    FOwnsModel          : Boolean;
    FScrollOffset       : TPointF;
    FZoom               : Single;
    FShowAliasIndicator : Boolean;

    FState       : TInteractionState;
    FMouseWorld  : TPointF;
    FMouseScreen : TPointF;

    FDragAnchorWorld  : TPointF;
    FSavedSpeciesPos  : TDictionary<TSpeciesNode, TPointF>;
    FSavedJunctionPos : TDictionary<TReaction,    TPointF>;

    FDraggedJunction : TReaction;

    FRubberAnchorScr : TPointF;
    FRubberCurScr    : TPointF;

    FPendingReactantCount : Integer;
    FPendingProductCount  : Integer;
    FPendingReactants     : TList<TSpeciesNode>;
    FPendingProducts      : TList<TSpeciesNode>;

    FNextSpeciesNum : Integer;

    // Returns the effective junction position for rendering and hit-testing.
    // For UniUni reactions when FLinearUniUni is True, this projects the
    // stored junction onto the line between the reactant and product centres,
    // making the three points collinear.  For all other cases it returns
    // R.JunctionPos unchanged.
    function EffectiveJunctionPos(R: TReaction): TPointF;

    // -----------------------------------------------------------------------
    procedure RenderBackground     (const ACanvas: ISkCanvas; W, H: Single);
    procedure RenderReactions      (const ACanvas: ISkCanvas);
    procedure RenderSpeciesNodes   (const ACanvas: ISkCanvas);
    procedure RenderJunctionHandles(const ACanvas: ISkCanvas);
    procedure RenderPendingReaction(const ACanvas: ISkCanvas);
    procedure RenderRubberBand     (const ACanvas: ISkCanvas);

    procedure DrawFilledTriangle(const ACanvas: ISkCanvas;
                                 const AV    : TArrowheadVertices;
                                 AColor      : TAlphaColor);
    procedure DrawCenteredText(const ACanvas : ISkCanvas;
                               const ACenter : TPointF;
                               const AText   : string;
                               AFontSize     : Single;
                               AColor        : TAlphaColor);
    procedure DrawDashedLine(const ACanvas: ISkCanvas;
                             const A, B   : TPointF;
                             AColor       : TAlphaColor;
                             AWidth       : Single);

    function W2S   (const P: TPointF): TPointF; inline;
    function S2W   (const P: TPointF): TPointF; inline;
    function W2SLen(L: Single)       : Single;  inline;

    function HitTestJunction   (const ScreenPt: TPointF; out R: TReaction   ): Boolean;
    function HitTestSpecies    (const WorldPt:  TPointF; out S: TSpeciesNode ): Boolean;
    function HitTestReactionLeg(const ScreenPt: TPointF; out R: TReaction   ): Boolean;

    procedure SaveDragPositions;
    procedure ApplyDragDelta(const Delta: TPointF);

    procedure FinalizeRubberBandSelection;

    function  IsInPendingList(S: TSpeciesNode): Boolean;
    procedure ClearPendingReaction;
    function  ComputeJunctionPos(Reactants, Products: TList<TSpeciesNode>): TPointF;
    procedure TryCompleteReaction;

    function  NextSpeciesName: string;
    procedure SyncSpeciesNameCounter;

    procedure DeleteSelected;

  public
    constructor Create(AModel: TBioModel; AOwnsModel: Boolean = False);
    destructor  Destroy; override;

    procedure Render(const ACanvas: ISkCanvas; ACanvasW, ACanvasH: Single);

    procedure MouseDown  (Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure MouseMove  (Shift: TShiftState; X, Y: Single);
    procedure MouseUp    (Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure MouseDblClick;

    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);

    procedure SetModeSelect;
    procedure SetModeAddSpecies;
    procedure SetModeAddReaction(ReactantCount, ProductCount: Integer);
    procedure CancelCurrentAction;

    function RightClickHitTest(X, Y: Single;
                               out HitSpecies : TSpeciesNode;
                               out HitReaction: TReaction): TRightClickTarget;

    function  CreateAliasAt(APrimary: TSpeciesNode): TSpeciesNode;
    procedure GoToPrimary  (AAlias: TSpeciesNode);

    // --- Antimony import / export ---
    procedure ImportAntimony(const ASource: string);
    function  ExportAntimony: string;

    // --- Auto-layout ---
    procedure AutoLayout(Iterations: Integer = 200);

    procedure ZoomAtPoint(AScreenPt: TPointF; ADelta: Integer);

    procedure NewDiagram;
    procedure LoadTestData;
    function  ContentBounds: TRectF;
    function  HasNonDefaultCompartments: Boolean;

    procedure SaveToFile (const AFileName: string);
    procedure LoadFromFile(const AFileName: string);

    property Model              : TBioModel         read FModel;
    property ScrollOffset       : TPointF            read FScrollOffset       write FScrollOffset;
    property Zoom               : Single             read FZoom               write FZoom;
    property State              : TInteractionState  read FState;
    property ShowAliasIndicator : Boolean            read FShowAliasIndicator write FShowAliasIndicator;

    // Toggle IsLinear on all currently selected UniUni reactions.
    // Reactions that are not UniUni are silently skipped.
    procedure ToggleLinearSelected;
  end;

implementation

// ===========================================================================
//  Color palette
// ===========================================================================
const
  CLR_BACKGROUND    : TAlphaColor = $FFF8F9FA;
  CLR_NODE_FILL     : TAlphaColor = $FFEEF6FF;
  CLR_NODE_BORDER   : TAlphaColor = $FF4A7FCB;
  CLR_NODE_FILL_SEL : TAlphaColor = $FFCCE0FF;
  CLR_NODE_BORD_SEL : TAlphaColor = $FF1144CC;
  CLR_ALIAS_FILL    : TAlphaColor = $FFF5F0FF;
  CLR_ALIAS_BORDER  : TAlphaColor = $FF7A6FC8;
  CLR_REACTION      : TAlphaColor = $FF444444;
  CLR_REACTION_SEL  : TAlphaColor = $FF1144CC;
  CLR_JCT_FILL      : TAlphaColor = $FFFF8800;
  CLR_JCT_BORDER    : TAlphaColor = $FFA05000;
  CLR_JCT_FILL_SEL  : TAlphaColor = $FF1144CC;
  CLR_JCT_BORD_SEL  : TAlphaColor = $FF0033AA;
  CLR_LABEL         : TAlphaColor = $FF1A1A1A;
  CLR_RING_REACTANT : TAlphaColor = $FF00AA44;
  CLR_RING_PRODUCT  : TAlphaColor = $FFCC3300;
  CLR_GUIDE_LINE    : TAlphaColor = $FF888888;
  CLR_RUBBER_FILL   : TAlphaColor = $330066CC;
  CLR_RUBBER_BORDER : TAlphaColor = $FF0066CC;

// ===========================================================================
//  Construction / destruction
// ===========================================================================

constructor TDiagramView.Create(AModel: TBioModel; AOwnsModel: Boolean);
begin
  inherited Create;
  FModel              := AModel;
  FOwnsModel          := AOwnsModel;
  FScrollOffset       := TPointF.Create(0, 0);
  FZoom               := 1.0;
  FState              := isSelect;
  FShowAliasIndicator := True;
  FNextSpeciesNum     := 1;
  FPendingReactants   := TList<TSpeciesNode>.Create;
  FPendingProducts    := TList<TSpeciesNode>.Create;
  FSavedSpeciesPos    := TDictionary<TSpeciesNode, TPointF>.Create;
  FSavedJunctionPos   := TDictionary<TReaction,    TPointF>.Create;
end;

destructor TDiagramView.Destroy;
begin
  FSavedJunctionPos.Free;
  FSavedSpeciesPos.Free;
  FPendingProducts.Free;
  FPendingReactants.Free;
  if FOwnsModel then FModel.Free;
  inherited;
end;

// ===========================================================================
//  Coordinate helpers
// ===========================================================================

function TDiagramView.W2S(const P: TPointF): TPointF;
begin Result := WorldToScreen(P, FScrollOffset, FZoom); end;

function TDiagramView.S2W(const P: TPointF): TPointF;
begin Result := ScreenToWorld(P, FScrollOffset, FZoom); end;

function TDiagramView.W2SLen(L: Single): Single;
begin Result := WorldLenToScreen(L, FZoom); end;

// ===========================================================================
//  Drawing primitives
// ===========================================================================

procedure TDiagramView.DrawFilledTriangle(const ACanvas: ISkCanvas;
                                          const AV     : TArrowheadVertices;
                                          AColor       : TAlphaColor);
var
  Builder : ISkPathBuilder;
  Path    : ISkPath;
  Paint   : ISkPaint;
begin
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(AV.Tip.X,   AV.Tip.Y);
  Builder.LineTo(AV.Base1.X, AV.Base1.Y);
  Builder.LineTo(AV.Base2.X, AV.Base2.Y);
  Builder.Close;
  Path            := Builder.Detach;
  Paint           := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color     := AColor;
  Paint.Style     := TSkPaintStyle.Fill;
  ACanvas.DrawPath(Path, Paint);
end;

procedure TDiagramView.DrawCenteredText(const ACanvas : ISkCanvas;
                                        const ACenter : TPointF;
                                        const AText   : string;
                                        AFontSize     : Single;
                                        AColor        : TAlphaColor);
var
  Font      : ISkFont;
  Paint     : ISkPaint;
  TextWidth : Single;
  Metrics   : TSkFontMetrics;
  BaselineY : Single;
begin
  Font      := TSkFont.Create(nil, AFontSize);
  TextWidth := Font.MeasureText(AText);
  Font.GetMetrics(Metrics);
  if Metrics.CapHeight > 0 then
    BaselineY := ACenter.Y + Metrics.CapHeight * 0.5
  else
    BaselineY := ACenter.Y + AFontSize * 0.35;
  Paint           := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color     := AColor;
  Paint.Style     := TSkPaintStyle.Fill;
  ACanvas.DrawSimpleText(AText, ACenter.X - TextWidth * 0.5, BaselineY,
                         Font, Paint);
end;

procedure TDiagramView.DrawDashedLine(const ACanvas: ISkCanvas;
                                      const A, B   : TPointF;
                                      AColor       : TAlphaColor;
                                      AWidth       : Single);
var
  Paint     : ISkPaint;
  Intervals : TArray<Single>;
begin
  Intervals         := [8, 4];
  Paint             := TSkPaint.Create;
  Paint.AntiAlias   := True;
  Paint.Color       := AColor;
  Paint.Style       := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := AWidth;
  Paint.PathEffect  := TSkPathEffect.MakeDash(Intervals, 0);
  ACanvas.DrawLine(A, B, Paint);
end;

// ===========================================================================
//  Hit testing
// ===========================================================================

function TDiagramView.HitTestJunction(const ScreenPt: TPointF;
                                      out R: TReaction): Boolean;
var
  Reaction : TReaction;
begin
  Result := False; R := nil;
  for Reaction in FModel.Reactions do
    if PointDist(ScreenPt, W2S(EffectiveJunctionPos(Reaction))) <= VIEW_HIT_JUNCTION then
    begin
      R := Reaction; Result := True; Exit;
    end;
end;

function TDiagramView.HitTestSpecies(const WorldPt: TPointF;
                                     out S: TSpeciesNode): Boolean;
var
  i : Integer;
begin
  Result := False; S := nil;
  for i := FModel.Species.Count - 1 downto 0 do
    if FModel.Species[i].BoundsRect.Contains(WorldPt) then
    begin
      S := FModel.Species[i]; Result := True; Exit;
    end;
end;

function TDiagramView.HitTestReactionLeg(const ScreenPt: TPointF;
                                         out R: TReaction): Boolean;
var
  Reaction : TReaction;
  P        : TParticipant;
  JScr     : TPointF;
  BoundW   : TPointF;
  TipW     : TPointF;
begin
  Result := False; R := nil;
  for Reaction in FModel.Reactions do
  begin
    JScr := W2S(EffectiveJunctionPos(Reaction));

    for P in Reaction.Reactants do
    begin
      BoundW := RectBoundaryIntersect(P.Species.Center, P.Species.HalfW,
                                      P.Species.HalfH, EffectiveJunctionPos(Reaction));
      if PointToSegmentDist(ScreenPt, W2S(BoundW), JScr) <= VIEW_HIT_SEGMENT then
      begin R := Reaction; Result := True; Exit; end;
    end;

    for P in Reaction.Products do
    begin
      TipW := ProductLineTip(P.Species.Center, P.Species.HalfW, P.Species.HalfH,
                              EffectiveJunctionPos(Reaction), VIEW_PRODUCT_GAP);
      if PointToSegmentDist(ScreenPt, JScr, W2S(TipW)) <= VIEW_HIT_SEGMENT then
      begin R := Reaction; Result := True; Exit; end;
    end;
  end;
end;

// ===========================================================================
//  Right-click hit test
// ===========================================================================

function TDiagramView.RightClickHitTest(X, Y: Single;
                                         out HitSpecies : TSpeciesNode;
                                         out HitReaction: TReaction): TRightClickTarget;
var
  ScreenPt : TPointF;
  WorldPt  : TPointF;
  S        : TSpeciesNode;
  R        : TReaction;
begin
  ScreenPt := TPointF.Create(X, Y);
  WorldPt  := S2W(ScreenPt);
  HitSpecies := nil; HitReaction := nil;

  if HitTestSpecies(WorldPt, S) then
  begin
    HitSpecies := S;
    if S.IsAlias then Result := rctAlias else Result := rctPrimary;
    Exit;
  end;

  if HitTestJunction(ScreenPt, R) or HitTestReactionLeg(ScreenPt, R) then
  begin
    HitReaction := R; Result := rctReaction; Exit;
  end;

  Result := rctNone;
end;

// ===========================================================================
//  Alias actions
// ===========================================================================

function TDiagramView.CreateAliasAt(APrimary: TSpeciesNode): TSpeciesNode;
begin
  Result := FModel.AddAlias(APrimary,
    APrimary.Center.X + VIEW_ALIAS_OFFSET,
    APrimary.Center.Y + VIEW_ALIAS_OFFSET);
  FModel.ClearSelection;
  Result.Selected := True;
end;

procedure TDiagramView.GoToPrimary(AAlias: TSpeciesNode);
var
  Primary : TSpeciesNode;
begin
  if not AAlias.IsAlias then Exit;
  Primary := AAlias.AliasOf;
  FModel.ClearSelection;
  Primary.Selected := True;
  FScrollOffset.X := -Primary.Center.X * FZoom;
  FScrollOffset.Y := -Primary.Center.Y * FZoom;
end;

// ===========================================================================
//  Drag helpers
// ===========================================================================

procedure TDiagramView.SaveDragPositions;
var
  SelSet   : TDictionary<TSpeciesNode, Boolean>;
  S        : TSpeciesNode;
  R        : TReaction;
  P        : TParticipant;
  AllInSet : Boolean;
begin
  FSavedSpeciesPos.Clear;
  FSavedJunctionPos.Clear;

  SelSet := TDictionary<TSpeciesNode, Boolean>.Create;
  try
    for S in FModel.Species do
      if S.Selected then
      begin
        FSavedSpeciesPos.AddOrSetValue(S, S.Center);
        SelSet.AddOrSetValue(S, True);
      end;

    for R in FModel.Reactions do
    begin
      if (R.Reactants.Count + R.Products.Count) = 0 then Continue;
      AllInSet := True;
      for P in R.Reactants do
        if not SelSet.ContainsKey(P.Species) then
        begin AllInSet := False; Break; end;
      if AllInSet then
        for P in R.Products do
          if not SelSet.ContainsKey(P.Species) then
          begin AllInSet := False; Break; end;
      if AllInSet then
        FSavedJunctionPos.AddOrSetValue(R, R.JunctionPos);
    end;
  finally
    SelSet.Free;
  end;
end;

procedure TDiagramView.ApplyDragDelta(const Delta: TPointF);
var
  Pair  : TPair<TSpeciesNode, TPointF>;
  RPair : TPair<TReaction,    TPointF>;
begin
  for Pair in FSavedSpeciesPos do
    Pair.Key.Center := TPointF.Create(
      Pair.Value.X + Delta.X, Pair.Value.Y + Delta.Y);
  for RPair in FSavedJunctionPos do
    RPair.Key.JunctionPos := TPointF.Create(
      RPair.Value.X + Delta.X, RPair.Value.Y + Delta.Y);
end;

// ===========================================================================
//  Rubber-band
// ===========================================================================

procedure TDiagramView.FinalizeRubberBandSelection;
var
  WA, WB    : TPointF;
  BandWorld : TRectF;
  S         : TSpeciesNode;
  R         : TReaction;
begin
  WA := S2W(FRubberAnchorScr);
  WB := S2W(FRubberCurScr);
  BandWorld := TRectF.Create(
    Min(WA.X, WB.X), Min(WA.Y, WB.Y),
    Max(WA.X, WB.X), Max(WA.Y, WB.Y));
  for S in FModel.Species do
    if BandWorld.IntersectsWith(S.BoundsRect) then S.Selected := True;
  for R in FModel.Reactions do
    if BandWorld.Contains(R.JunctionPos) then R.Selected := True;
end;

// ===========================================================================
//  Reaction-building helpers
// ===========================================================================

function TDiagramView.IsInPendingList(S: TSpeciesNode): Boolean;
begin
  Result := (FPendingReactants.IndexOf(S) >= 0) or
            (FPendingProducts.IndexOf(S)  >= 0);
end;

procedure TDiagramView.ClearPendingReaction;
begin
  FPendingReactants.Clear;
  FPendingProducts.Clear;
end;

function TDiagramView.ComputeJunctionPos(Reactants,
                                          Products: TList<TSpeciesNode>): TPointF;
var
  S            : TSpeciesNode;
  SumR, SumP   : TPointF;
  CentR, CentP : TPointF;
begin
  SumR := TPointF.Create(0, 0);
  for S in Reactants do
  begin SumR.X := SumR.X + S.Center.X; SumR.Y := SumR.Y + S.Center.Y; end;
  if Reactants.Count > 0 then
    CentR := TPointF.Create(SumR.X / Reactants.Count, SumR.Y / Reactants.Count)
  else
    CentR := TPointF.Create(0, 0);

  SumP := TPointF.Create(0, 0);
  for S in Products do
  begin SumP.X := SumP.X + S.Center.X; SumP.Y := SumP.Y + S.Center.Y; end;
  if Products.Count > 0 then
    CentP := TPointF.Create(SumP.X / Products.Count, SumP.Y / Products.Count)
  else
    CentP := CentR;

  Result := TPointF.Create(
    (CentR.X + CentP.X) * 0.5, (CentR.Y + CentP.Y) * 0.5);
end;

procedure TDiagramView.TryCompleteReaction;
var
  JPos     : TPointF;
  R        : TReaction;
  S        : TSpeciesNode;
  RateLaw  : string;
  KName    : string;
  NumSuffix: string;
  i        : Integer;
begin
  if (FPendingReactants.Count <> FPendingReactantCount) or
     (FPendingProducts.Count  <> FPendingProductCount) then Exit;

  JPos := ComputeJunctionPos(FPendingReactants, FPendingProducts);
  R    := FModel.AddReaction(JPos.X, JPos.Y);

  for S in FPendingReactants do
    R.Reactants.Add(TParticipant.Create(S, 1.0));
  for S in FPendingProducts do
    R.Products.Add(TParticipant.Create(S, 1.0));

  // Auto-generate a mass-action rate law.
  // The rate constant name mirrors the reaction ID suffix, e.g. r3 -> k3.
  // Rate law = k * S1 * S2 * ... (product of all reactant names).
  NumSuffix := Copy(R.Id, 2, MaxInt);  // strip the leading 'r'
  KName     := 'k' + NumSuffix;

  RateLaw := KName;
  for i := 0 to FPendingReactants.Count - 1 do
    RateLaw := RateLaw + '*' + FPendingReactants[i].DisplayName;

  R.KineticLaw := RateLaw;

  // Add the rate constant as a parameter with a default value of 0.1
  // only if a parameter with this name does not already exist.
  if not Assigned(FModel.FindParameterByVar(KName)) then
    FModel.AddParameter(KName, '0.1');

  ClearPendingReaction;
  // Stay in isAddReaction for the next reaction of the same type
end;

// ===========================================================================
//  Species naming
// ===========================================================================

function TDiagramView.NextSpeciesName: string;
begin
  Result := 'S' + IntToStr(FNextSpeciesNum);
  Inc(FNextSpeciesNum);
end;

procedure TDiagramView.SyncSpeciesNameCounter;
var
  S    : TSpeciesNode;
  N    : Integer;
  MaxN : Integer;
  Tail : string;
begin
  MaxN := 0;
  for S in FModel.Species do
    if (Length(S.Name) > 1) and (S.Name[Low(S.Name)] = 'S') then
    begin
      Tail := Copy(S.Name, 2, MaxInt);
      if TryStrToInt(Tail, N) and (N > MaxN) then MaxN := N;
    end;
  FNextSpeciesNum := MaxN + 1;
end;

// ===========================================================================
//  Deletion
// ===========================================================================

procedure TDiagramView.DeleteSelected;
var
  SelSpecies   : TArray<TSpeciesNode>;
  SelReactions : TArray<TReaction>;
  S            : TSpeciesNode;
  R            : TReaction;
  Dummy        : TArray<string>;
begin
  SelSpecies   := FModel.SelectedSpecies;
  SelReactions := FModel.SelectedReactions;
  if (Length(SelSpecies) = 0) and (Length(SelReactions) = 0) then Exit;

  for S in SelSpecies do FModel.DeleteSpecies(S, Dummy);

  for R in SelReactions do
    if FModel.FindReactionById(R.Id) <> nil then
      FModel.DeleteReaction(R);
end;

// ===========================================================================
//  Mode API
// ===========================================================================

procedure TDiagramView.SetModeSelect;
begin ClearPendingReaction; FState := isSelect; end;

procedure TDiagramView.SetModeAddSpecies;
begin
  ClearPendingReaction; FModel.ClearSelection; FState := isAddSpecies;
end;

procedure TDiagramView.SetModeAddReaction(ReactantCount, ProductCount: Integer);
begin
  ClearPendingReaction;
  FModel.ClearSelection;
  FPendingReactantCount := ReactantCount;
  FPendingProductCount  := ProductCount;
  FState                := isAddReaction;
end;

procedure TDiagramView.CancelCurrentAction;
begin
  ClearPendingReaction; FState := isSelect;
end;

// ===========================================================================
//  Keyboard
// ===========================================================================

procedure TDiagramView.KeyDown(var Key: Word; var KeyChar: WideChar;
                                Shift: TShiftState);
begin
  case Key of
    vkDelete:
      if FState = isSelect then
      begin DeleteSelected; Key := 0; end;
    vkEscape:
    begin
      CancelCurrentAction; FModel.ClearSelection; Key := 0;
    end;
  end;
end;

// ===========================================================================
//  Mouse events
// ===========================================================================

procedure TDiagramView.MouseDown(Button: TMouseButton; Shift: TShiftState;
                                  X, Y: Single);
var
  ScreenPt    : TPointF;
  WorldPt     : TPointF;
  HitSpecies  : TSpeciesNode;
  HitReaction : TReaction;
begin
  if Button <> TMouseButton.mbLeft then Exit;
  ScreenPt := TPointF.Create(X, Y);
  WorldPt  := S2W(ScreenPt);
  FMouseScreen := ScreenPt; FMouseWorld := WorldPt;

  case FState of
    isAddSpecies:
      FModel.AddSpecies(NextSpeciesName, WorldPt.X, WorldPt.Y);

    isAddReaction:
    begin
      if HitTestSpecies(WorldPt, HitSpecies) then
      begin
        if not IsInPendingList(HitSpecies) then
        begin
          if FPendingReactants.Count < FPendingReactantCount then
            FPendingReactants.Add(HitSpecies)
          else
            FPendingProducts.Add(HitSpecies);
          TryCompleteReaction;
        end;
      end
      else
        CancelCurrentAction;
    end;

    isSelect:
    begin
      if HitTestJunction(ScreenPt, HitReaction) then
      begin
        if not (ssShift in Shift) then FModel.ClearSelection;
        HitReaction.Selected := True;
        FDraggedJunction     := HitReaction;
        FDragAnchorWorld     := WorldPt;
        FState               := isDraggingJunction;
      end
      else if HitTestSpecies(WorldPt, HitSpecies) then
      begin
        if ssShift in Shift then
          HitSpecies.Selected := not HitSpecies.Selected
        else
        begin
          if not HitSpecies.Selected then
          begin
            FModel.ClearSelection;
            HitSpecies.Selected := True;
          end;
          FDragAnchorWorld := WorldPt;
          SaveDragPositions;
          FState := isDraggingNodes;
        end;
      end
      else if HitTestReactionLeg(ScreenPt, HitReaction) then
      begin
        if ssShift in Shift then
          HitReaction.Selected := not HitReaction.Selected
        else
        begin
          FModel.ClearSelection;
          HitReaction.Selected := True;
        end;
      end
      else
      begin
        if not (ssShift in Shift) then FModel.ClearSelection;
        FRubberAnchorScr := ScreenPt;
        FRubberCurScr    := ScreenPt;
        FState           := isRubberBand;
      end;
    end;
  end;
end;

procedure TDiagramView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  ScreenPt : TPointF;
  WorldPt  : TPointF;
begin
  ScreenPt     := TPointF.Create(X, Y);
  WorldPt      := S2W(ScreenPt);
  FMouseScreen := ScreenPt;
  FMouseWorld  := WorldPt;

  if not (ssLeft in Shift) then Exit;

  case FState of
    isDraggingNodes:
      ApplyDragDelta(TPointF.Create(
        WorldPt.X - FDragAnchorWorld.X, WorldPt.Y - FDragAnchorWorld.Y));
    isDraggingJunction:
      FDraggedJunction.JunctionPos := WorldPt;
    isRubberBand:
      FRubberCurScr := ScreenPt;
  end;
end;

procedure TDiagramView.MouseUp(Button: TMouseButton; Shift: TShiftState;
                                X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then Exit;
  FMouseScreen := TPointF.Create(X, Y);
  FMouseWorld  := S2W(FMouseScreen);
  case FState of
    isDraggingNodes, isDraggingJunction: FState := isSelect;
    isRubberBand:
    begin
      FRubberCurScr := FMouseScreen;
      FinalizeRubberBandSelection;
      FState := isSelect;
    end;
  end;
end;

procedure TDiagramView.MouseDblClick;
var
  HitSpecies : TSpeciesNode;
  EditTarget : TSpeciesNode;
  NewName    : string;
begin
  if FState <> isSelect then Exit;
  if not HitTestSpecies(FMouseWorld, HitSpecies) then Exit;
  EditTarget := HitSpecies;
  if HitSpecies.IsAlias then EditTarget := HitSpecies.AliasOf;
  NewName := InputBox('Rename Species', 'Name:', EditTarget.Name);
  if (NewName <> '') and (NewName <> EditTarget.Name) then
    EditTarget.Name := NewName;
end;

procedure TDiagramView.ToggleLinearSelected;
var
  R    : TReaction;
  A, B : TPointF;
begin
  for R in FModel.Reactions do
    if R.Selected and (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    begin
      R.IsLinear := not R.IsLinear;

      // When switching linearity OFF, place the junction at the midpoint of
      // the current species positions so the handle reappears sensibly
      // regardless of how far the nodes have moved since linearity was set.
      if not R.IsLinear then
      begin
        A := R.Reactants[0].Species.Center;
        B := R.Products[0].Species.Center;
        R.JunctionPos := TPointF.Create(
          (A.X + B.X) * 0.5, (A.Y + B.Y) * 0.5);
      end;
    end;
end;

// ===========================================================================
//  EffectiveJunctionPos
// ===========================================================================

function TDiagramView.EffectiveJunctionPos(R: TReaction): TPointF;
var
  A, B  : TPointF;   // reactant centre, product centre
  AB    : TPointF;   // B - A
  AJ    : TPointF;   // junction - A
  LenSq : Single;
  t     : Single;
begin
  // Only apply collinear constraint when the reaction has IsLinear set.
  if (not R.IsLinear) or
     (R.Reactants.Count <> 1) or
     (R.Products.Count  <> 1) then
  begin
    Result := R.JunctionPos;
    Exit;
  end;

  A := R.Reactants[0].Species.Center;
  B := R.Products [0].Species.Center;

  // Project the stored junction onto the line A→B, clamped to [0.1, 0.9]
  // so it never collapses onto either species node.
  AB.X  := B.X - A.X;
  AB.Y  := B.Y - A.Y;
  LenSq := AB.X * AB.X + AB.Y * AB.Y;

  if LenSq < 1.0 then
  begin
    // Degenerate: species are on top of each other; return midpoint.
    Result := TPointF.Create((A.X + B.X) * 0.5, (A.Y + B.Y) * 0.5);
    Exit;
  end;

  AJ.X := R.JunctionPos.X - A.X;
  AJ.Y := R.JunctionPos.Y - A.Y;

  // Scalar projection parameter along AB
  t := (AJ.X * AB.X + AJ.Y * AB.Y) / LenSq;
  t := Max(0.1, Min(0.9, t));

  Result.X := A.X + t * AB.X;
  Result.Y := A.Y + t * AB.Y;
end;

// ===========================================================================
//  Render passes
// ===========================================================================

procedure TDiagramView.RenderBackground(const ACanvas: ISkCanvas;
                                         W, H: Single);
var
  Paint : ISkPaint;
begin
  Paint       := TSkPaint.Create;
  Paint.Color := CLR_BACKGROUND;
  Paint.Style := TSkPaintStyle.Fill;
  ACanvas.DrawRect(TRectF.Create(0, 0, W, H), Paint);
end;

procedure TDiagramView.RenderReactions(const ACanvas: ISkCanvas);
var
  R         : TReaction;
  P         : TParticipant;
  JScr      : TPointF;
  BoundW    : TPointF;
  TipW      : TPointF;
  TipScr    : TPointF;
  DirW      : TPointF;
  ArrW      : TArrowheadVertices;
  ArrScr    : TArrowheadVertices;
  LinePaint : ISkPaint;
  LineColor : TAlphaColor;
begin
  for R in FModel.Reactions do
  begin
    if R.Selected then LineColor := CLR_REACTION_SEL
    else               LineColor := CLR_REACTION;

    LinePaint             := TSkPaint.Create;
    LinePaint.AntiAlias   := True;
    LinePaint.Color       := LineColor;
    LinePaint.Style       := TSkPaintStyle.Stroke;
    LinePaint.StrokeWidth := W2SLen(VIEW_LINE_WIDTH);
    LinePaint.StrokeCap   := TSkStrokeCap.Round;

    // --- Linear UniUni: single straight line, no junction split -----------
    // Drawing via the junction is skipped entirely for linear UniUni
    // reactions.  The line goes directly from the reactant boundary to the
    // product tip so the two segments can never overlap or overshoot.
    if R.IsLinear and (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    begin
      var Reactant := R.Reactants[0].Species;
      var Product  := R.Products[0].Species;

      // Direction: reactant centre → product centre
      DirW.X := Product.Center.X - Reactant.Center.X;
      DirW.Y := Product.Center.Y - Reactant.Center.Y;
      DirW   := NormalizeVec(DirW);

      // Start: reactant boundary in the direction of the product
      BoundW := RectBoundaryIntersect(Reactant.Center, Reactant.HalfW,
                                      Reactant.HalfH, Product.Center);

      // End: product boundary minus gap, approached from the reactant side
      TipW   := ProductLineTip(Product.Center, Product.HalfW,
                                Product.HalfH, Reactant.Center, VIEW_PRODUCT_GAP);
      TipScr := W2S(TipW);

      ACanvas.DrawLine(W2S(BoundW), TipScr, LinePaint);

      ArrW         := FilledArrowhead(TipW, DirW, VIEW_ARROW_LEN, VIEW_ARROW_HALF_BASE);
      ArrScr.Tip   := W2S(ArrW.Tip);
      ArrScr.Base1 := W2S(ArrW.Base1);
      ArrScr.Base2 := W2S(ArrW.Base2);
      DrawFilledTriangle(ACanvas, ArrScr, LineColor);
      Continue;
    end;

    // --- General case: reactant legs → junction → product legs ------------
    JScr := W2S(EffectiveJunctionPos(R));

    for P in R.Reactants do
    begin
      BoundW := RectBoundaryIntersect(P.Species.Center, P.Species.HalfW,
                                      P.Species.HalfH, EffectiveJunctionPos(R));
      ACanvas.DrawLine(W2S(BoundW), JScr, LinePaint);
    end;

    for P in R.Products do
    begin
      TipW   := ProductLineTip(P.Species.Center, P.Species.HalfW,
                                P.Species.HalfH, EffectiveJunctionPos(R), VIEW_PRODUCT_GAP);
      TipScr := W2S(TipW);
      ACanvas.DrawLine(JScr, TipScr, LinePaint);

      DirW.X := P.Species.Center.X - EffectiveJunctionPos(R).X;
      DirW.Y := P.Species.Center.Y - EffectiveJunctionPos(R).Y;
      DirW   := NormalizeVec(DirW);

      ArrW         := FilledArrowhead(TipW, DirW, VIEW_ARROW_LEN, VIEW_ARROW_HALF_BASE);
      ArrScr.Tip   := W2S(ArrW.Tip);
      ArrScr.Base1 := W2S(ArrW.Base1);
      ArrScr.Base2 := W2S(ArrW.Base2);
      DrawFilledTriangle(ACanvas, ArrScr, LineColor);
    end;
  end;
end;

procedure TDiagramView.RenderSpeciesNodes(const ACanvas: ISkCanvas);
var
  S           : TSpeciesNode;
  SR          : TRectF;
  CornerR     : Single;
  FillColor   : TAlphaColor;
  BorderColor : TAlphaColor;
  FillPaint   : ISkPaint;
  BorderPaint : ISkPaint;
  Intervals   : TArray<Single>;
begin
  CornerR   := W2SLen(VIEW_NODE_CORNER);
  Intervals := [5, 4];

  for S in FModel.Species do
  begin
    if S.Selected then
    begin
      FillColor   := CLR_NODE_FILL_SEL;
      BorderColor := CLR_NODE_BORD_SEL;
    end
    else if S.IsAlias and FShowAliasIndicator then
    begin
      FillColor   := CLR_ALIAS_FILL;
      BorderColor := CLR_ALIAS_BORDER;
    end
    else
    begin
      FillColor   := CLR_NODE_FILL;
      BorderColor := CLR_NODE_BORDER;
    end;

    SR := TRectF.Create(
      W2S(TPointF.Create(S.Center.X - S.HalfW, S.Center.Y - S.HalfH)),
      W2S(TPointF.Create(S.Center.X + S.HalfW, S.Center.Y + S.HalfH)));

    FillPaint           := TSkPaint.Create;
    FillPaint.AntiAlias := True;
    FillPaint.Color     := FillColor;
    FillPaint.Style     := TSkPaintStyle.Fill;
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, FillPaint);

    BorderPaint             := TSkPaint.Create;
    BorderPaint.AntiAlias   := True;
    BorderPaint.Color       := BorderColor;
    BorderPaint.Style       := TSkPaintStyle.Stroke;
    BorderPaint.StrokeWidth := W2SLen(VIEW_BORDER_WIDTH);
    if S.IsAlias and FShowAliasIndicator then
      BorderPaint.PathEffect := TSkPathEffect.MakeDash(Intervals, 0);
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, BorderPaint);

    DrawCenteredText(ACanvas, W2S(S.Center), S.DisplayName,
                     W2SLen(VIEW_FONT_SIZE), CLR_LABEL);
  end;
end;

procedure TDiagramView.RenderJunctionHandles(const ACanvas: ISkCanvas);
var
  R           : TReaction;
  JScr        : TPointF;
  Radius      : Single;
  FillColor   : TAlphaColor;
  BorderColor : TAlphaColor;
  FillPaint   : ISkPaint;
  RingPaint   : ISkPaint;
begin
  Radius := W2SLen(VIEW_JUNCTION_RADIUS);
  for R in FModel.Reactions do
  begin
    // Hide the junction handle for linear UniUni reactions — the handle
    // has no useful function when the junction is constrained to the line.
    if R.IsLinear and (R.Reactants.Count = 1) and (R.Products.Count = 1) then
      Continue;
    if R.Selected then
    begin FillColor := CLR_JCT_FILL_SEL; BorderColor := CLR_JCT_BORD_SEL; end
    else
    begin FillColor := CLR_JCT_FILL;     BorderColor := CLR_JCT_BORDER;   end;

    JScr := W2S(EffectiveJunctionPos(R));

    FillPaint           := TSkPaint.Create;
    FillPaint.AntiAlias := True;
    FillPaint.Color     := FillColor;
    FillPaint.Style     := TSkPaintStyle.Fill;
    ACanvas.DrawCircle(JScr, Radius, FillPaint);

    RingPaint             := TSkPaint.Create;
    RingPaint.AntiAlias   := True;
    RingPaint.Color       := BorderColor;
    RingPaint.Style       := TSkPaintStyle.Stroke;
    RingPaint.StrokeWidth := W2SLen(1.0);
    ACanvas.DrawCircle(JScr, Radius, RingPaint);
  end;
end;

procedure TDiagramView.RenderPendingReaction(const ACanvas: ISkCanvas);
var
  S          : TSpeciesNode;
  SR         : TRectF;
  CornerR    : Single;
  RingPaint  : ISkPaint;
  DotPaint   : ISkPaint;
  DotColor   : TAlphaColor;
  LastPicked : TSpeciesNode;
  Outset     : Single;
begin
  if FState <> isAddReaction then Exit;
  Outset  := VIEW_RING_OUTSET;
  CornerR := W2SLen(VIEW_NODE_CORNER + Outset);

  RingPaint             := TSkPaint.Create;
  RingPaint.AntiAlias   := True;
  RingPaint.Style       := TSkPaintStyle.Stroke;
  RingPaint.StrokeWidth := W2SLen(VIEW_RING_WIDTH);
  LastPicked            := nil;

  RingPaint.Color := CLR_RING_REACTANT;
  for S in FPendingReactants do
  begin
    SR := TRectF.Create(
      W2S(TPointF.Create(S.Center.X - S.HalfW - Outset, S.Center.Y - S.HalfH - Outset)),
      W2S(TPointF.Create(S.Center.X + S.HalfW + Outset, S.Center.Y + S.HalfH + Outset)));
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, RingPaint);
    LastPicked := S;
  end;

  RingPaint.Color := CLR_RING_PRODUCT;
  for S in FPendingProducts do
  begin
    SR := TRectF.Create(
      W2S(TPointF.Create(S.Center.X - S.HalfW - Outset, S.Center.Y - S.HalfH - Outset)),
      W2S(TPointF.Create(S.Center.X + S.HalfW + Outset, S.Center.Y + S.HalfH + Outset)));
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, RingPaint);
    LastPicked := S;
  end;

  if Assigned(LastPicked) then
    DrawDashedLine(ACanvas, W2S(LastPicked.Center), FMouseScreen, CLR_GUIDE_LINE, 1.0);

  if FPendingReactants.Count < FPendingReactantCount then
    DotColor := CLR_RING_REACTANT
  else
    DotColor := CLR_RING_PRODUCT;

  DotPaint           := TSkPaint.Create;
  DotPaint.AntiAlias := True;
  DotPaint.Color     := DotColor;
  DotPaint.Style     := TSkPaintStyle.Fill;
  ACanvas.DrawCircle(FMouseScreen, 5.0, DotPaint);
end;

procedure TDiagramView.RenderRubberBand(const ACanvas: ISkCanvas);
var
  BandRect  : TRectF;
  FillPaint : ISkPaint;
  LinePaint : ISkPaint;
begin
  if FState <> isRubberBand then Exit;
  BandRect := TRectF.Create(
    Min(FRubberAnchorScr.X, FRubberCurScr.X),
    Min(FRubberAnchorScr.Y, FRubberCurScr.Y),
    Max(FRubberAnchorScr.X, FRubberCurScr.X),
    Max(FRubberAnchorScr.Y, FRubberCurScr.Y));

  FillPaint       := TSkPaint.Create;
  FillPaint.Color := CLR_RUBBER_FILL;
  FillPaint.Style := TSkPaintStyle.Fill;
  ACanvas.DrawRect(BandRect, FillPaint);

  LinePaint             := TSkPaint.Create;
  LinePaint.Color       := CLR_RUBBER_BORDER;
  LinePaint.Style       := TSkPaintStyle.Stroke;
  LinePaint.StrokeWidth := 1.0;
  ACanvas.DrawRect(BandRect, LinePaint);
end;

// ===========================================================================
//  Render — entry point
// ===========================================================================

procedure TDiagramView.Render(const ACanvas: ISkCanvas;
                               ACanvasW, ACanvasH: Single);
begin
  RenderBackground     (ACanvas, ACanvasW, ACanvasH);
  RenderReactions      (ACanvas);
  RenderSpeciesNodes   (ACanvas);
  RenderJunctionHandles(ACanvas);
  RenderPendingReaction(ACanvas);
  RenderRubberBand     (ACanvas);
end;

// ===========================================================================
//  Antimony import / export
// ===========================================================================

procedure TDiagramView.ImportAntimony(const ASource: string);
begin
  CancelCurrentAction;
  TAntimonyBridge.ImportFromString(ASource, FModel);
  SyncSpeciesNameCounter;
  FModel.ClearSelection;
  FScrollOffset := TPointF.Create(30, 30);
end;

function TDiagramView.ExportAntimony: string;
begin
  Result := TAntimonyBridge.ExportToString(FModel);
end;

procedure TDiagramView.AutoLayout(Iterations: Integer);
begin
  TAutoLayout.Run(FModel, Iterations);
end;

function TDiagramView.HasNonDefaultCompartments: Boolean;
begin
  Result := FModel.HasNonDefaultCompartments;
end;

// ===========================================================================
//  Utility
// ===========================================================================

procedure TDiagramView.NewDiagram;
begin
  CancelCurrentAction;
  FModel.Clear;
  FNextSpeciesNum := 1;
  FScrollOffset   := TPointF.Create(30, 30);
end;

function TDiagramView.ContentBounds: TRectF;
const
  MARGIN = 60.0;
var
  S    : TSpeciesNode;
  R    : TReaction;
  B    : TRectF;
  Init : Boolean;
begin
  Init := True;
  for S in FModel.Species do
  begin
    B := S.BoundsRect;
    if Init then begin Result := B; Init := False; end
    else
    begin
      Result.Left   := Min(Result.Left,   B.Left);
      Result.Top    := Min(Result.Top,    B.Top);
      Result.Right  := Max(Result.Right,  B.Right);
      Result.Bottom := Max(Result.Bottom, B.Bottom);
    end;
  end;
  for R in FModel.Reactions do
  begin
    if Init then
    begin
      Result := TRectF.Create(R.JunctionPos.X, R.JunctionPos.Y,
                               R.JunctionPos.X, R.JunctionPos.Y);
      Init := False;
    end
    else
    begin
      Result.Left   := Min(Result.Left,   R.JunctionPos.X);
      Result.Top    := Min(Result.Top,    R.JunctionPos.Y);
      Result.Right  := Max(Result.Right,  R.JunctionPos.X);
      Result.Bottom := Max(Result.Bottom, R.JunctionPos.Y);
    end;
  end;
  if Init then begin Result := TRectF.Create(0, 0, 800, 600); Exit; end;
  Result.Left   := Result.Left   - MARGIN;
  Result.Top    := Result.Top    - MARGIN;
  Result.Right  := Result.Right  + MARGIN;
  Result.Bottom := Result.Bottom + MARGIN;
end;

// ===========================================================================
//  Persistence
// ===========================================================================

procedure TDiagramView.SaveToFile(const AFileName: string);
begin
  FModel.SaveToFile(AFileName);
end;

procedure TDiagramView.LoadFromFile(const AFileName: string);
begin
  FModel.LoadFromFile(AFileName);
  SyncSpeciesNameCounter;
  FModel.ClearSelection;
  SetModeSelect;
end;


procedure TDiagramView.ZoomAtPoint(AScreenPt: TPointF; ADelta: Integer);
const
  ZOOM_STEP  = 1.15;   // factor per wheel notch
  ZOOM_MIN   = 0.1;
  ZOOM_MAX   = 8.0;
var
  OldZoom  : Single;
  NewZoom  : Single;
  WorldPt  : TPointF;
begin
  OldZoom := FZoom;

  if ADelta > 0 then
    NewZoom := OldZoom * ZOOM_STEP
  else
    NewZoom := OldZoom / ZOOM_STEP;

  NewZoom := Max(ZOOM_MIN, Min(ZOOM_MAX, NewZoom));
  if NewZoom = OldZoom then Exit;

  // World point currently under the cursor
  WorldPt.X := (AScreenPt.X - FScrollOffset.X) / OldZoom;
  WorldPt.Y := (AScreenPt.Y - FScrollOffset.Y) / OldZoom;

  FZoom := NewZoom;

  // Adjust offset so that same world point stays under cursor
  FScrollOffset.X := AScreenPt.X - WorldPt.X * NewZoom;
  FScrollOffset.Y := AScreenPt.Y - WorldPt.Y * NewZoom;
end;


// ===========================================================================
//  LoadTestData
// ===========================================================================

procedure TDiagramView.LoadTestData;
var
  S1, S2, S3, S4, S5, S6 : TSpeciesNode;
  SAtp1, SAtp2            : TSpeciesNode;
  R1, R2, R3              : TReaction;
begin
  FModel.Clear;
  FNextSpeciesNum := 1;

  // Reaction 1: A + B → C + D  (with a kinetic law for demonstration)
  S1 := FModel.AddSpecies('A', 110, 150, 80, 36);
  S2 := FModel.AddSpecies('B', 110, 250, 80, 36);
  S3 := FModel.AddSpecies('C', 420, 150, 80, 36);
  S4 := FModel.AddSpecies('D', 420, 250, 80, 36);
  S1.InitialValue := 1.0; S2.InitialValue := 1.0;

  R1 := FModel.AddReaction(265, 200);
  R1.KineticLaw := 'k1*A*B';
  R1.Reactants.Add(TParticipant.Create(S1, 1.0));
  R1.Reactants.Add(TParticipant.Create(S2, 1.0));
  R1.Products.Add(TParticipant.Create(S3, 1.0));
  R1.Products.Add(TParticipant.Create(S4, 1.0));

  FModel.AddParameter('k1', '0.1');

  // Reaction 2: E → F (UniUni)
  S5 := FModel.AddSpecies('E', 110, 370, 80, 36);
  S6 := FModel.AddSpecies('F', 420, 370, 80, 36);
  S5.InitialValue := 2.0;

  R2 := FModel.AddReaction(265, 370);
  R2.KineticLaw := 'k2*E';
  R2.Reactants.Add(TParticipant.Create(S5, 1.0));
  R2.Products.Add(TParticipant.Create(S6, 1.0));

  FModel.AddParameter('k2', '0.2');

  // Alias demonstration: ATP appears twice
  SAtp1 := FModel.AddSpecies('ATP', 580, 150, 80, 36);
  SAtp2 := FModel.AddAlias(SAtp1, 580, 370);

  R3 := FModel.AddReaction(500, 260);
  R3.Reactants.Add(TParticipant.Create(S3,    1.0));
  R3.Reactants.Add(TParticipant.Create(SAtp1, 1.0));
  R3.Products.Add (TParticipant.Create(SAtp2, 1.0));
  R3.Products.Add (TParticipant.Create(S6,    1.0));
end;

end.
