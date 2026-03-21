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
  System.UIConsts,
  System.JSON,
  System.Math,
  System.Generics.Collections,
  FMX.Dialogs,
  Skia,
  uBioModel,
  uGeometry,
  uAntimonyBridge,
  uSBMLBridge,
  uAutoLayout,
  uUndoManager;

// ---------------------------------------------------------------------------
const
  VIEW_NODE_CORNER     = 8.0;
  VIEW_JUNCTION_RADIUS = 5.0;
  VIEW_PRODUCT_GAP         = 6.0;  // world px gap, straight/linear product legs
  VIEW_BEZIER_PRODUCT_GAP  = 6.0;  // world px gap, Bézier product legs
  VIEW_REACTANT_GAP        = 6.0;  // world px gap, straight/linear reactant legs
  VIEW_BEZIER_REACTANT_GAP = 6.0;  // world px gap, Bézier reactant legs
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
  VIEW_NODE_TEXT_PAD   = 10.0;  // world px padding each side of label inside node

  // Selection halo drawn outside species/compartment nodes
  VIEW_SEL_RING_OUTSET = 6.0;   // world px gap between node border and halo
  VIEW_SEL_RING_WIDTH  = 2.0;   // world px stroke width of halo

// ---------------------------------------------------------------------------
type
  TInteractionState = (
    isSelect, isAddSpecies, isAddReaction,
    isDraggingNodes, isDraggingJunction, isRubberBand,
    isDraggingCtrlPt   // dragging a Bézier control point handle
  );

  TRightClickTarget = (rctNone, rctPrimary, rctAlias, rctReaction);

  // Per-participant drag info: which handles to translate and their saved originals.
  TCtrlPtDragInfo = record
    Orig1  : TPointF;   // Ctrl1 position at drag-start
    Orig2  : TPointF;   // Ctrl2 position at drag-start
    Move1  : Boolean;   // translate Ctrl1 by drag delta
    Move2  : Boolean;   // translate Ctrl2 by drag delta
  end;

  TDiagramView = class
  private
    FModel              : TBioModel;
    FOwnsModel          : Boolean;
    FScrollOffset       : TPointF;
    FZoom               : Single;
    FShowAliasIndicator : Boolean;
    FDefaultBezier      : Boolean;   // new reactions default to Bézier
    FDefaultSmoothJunction : Boolean; // new reactions default to smooth junction

    FState       : TInteractionState;
    FMouseWorld  : TPointF;
    FMouseScreen : TPointF;

    FDragAnchorWorld  : TPointF;
    FSavedSpeciesPos  : TDictionary<TSpeciesNode, TPointF>;
    FSavedJunctionPos : TDictionary<TReaction,    TPointF>;
    // Ctrl pt translation during node-group drag
    FSavedCtrlPts     : TDictionary<TParticipant, TCtrlPtDragInfo>;
    FDragHasCtrlPts   : Boolean;   // any CtrlPtsSet handles need translating
    FDragNodesSnap    : string;    // pre-drag snapshot when ctrl pts are affected
    FDragNodesSnapNum : Integer;

    FDraggedJunction : TReaction;

    // Bezier control point dragging
    FDraggedParticipant  : TParticipant;
    FDraggedCtrlNum      : Integer;    // 1 = Ctrl1, 2 = Ctrl2
    FDragAutoC1          : TPointF;    // auto ctrl pts captured at drag-start
    FDragAutoC2          : TPointF;    //   ensures undragged handle never goes to (0,0)
    // Undo state captured at the start of each drag gesture
    FDragJunctionOldPos  : TPointF;    // junction pos before junction drag
    FDragCtrlPtReactionId: string;     // reaction owning the dragged ctrl pt
    FDragCtrlPtIsReactant: Boolean;
    FDragCtrlPtPartIdx   : Integer;
    FDragCtrlPtOldState  : TCtrlPtState; // ctrl pt state before materialising

    // Per-drag cached values for smooth-junction logic
    FDragCtrlPtIsInner    : Boolean;   // current ctrl-pt drag is an inner (junction-side) handle
    FDragCtrlPtReaction   : TReaction; // reaction that owns the dragged ctrl pt (cached)
    FDragCtrlPtSnapBefore : string;    // pre-drag snapshot (smooth inner drag only)
    FDragCtrlPtSnapNum    : Integer;
    FDragJunctionSmooth        : Boolean; // reaction.IsJunctionSmooth captured at junction drag-start
    FDragJunctionSmoothSnap    : string;  // pre-drag snapshot (smooth junction drag only)
    FDragJunctionSmoothSnapNum : Integer;

    // Undo manager
    FUndoManager         : TUndoManager;
    FRestoreProc         : TAfterRestoreProc;  // cached; created once in constructor

    FRubberAnchorScr : TPointF;
    FRubberCurScr    : TPointF;

    FPendingReactantCount : Integer;
    FPendingProductCount  : Integer;
    FPendingReactants     : TList<TSpeciesNode>;
    FPendingProducts      : TList<TSpeciesNode>;

    FNextSpeciesNum : Integer;

    function EffectiveJunctionPos(R: TReaction): TPointF;

    // Compute auto control points for a Bezier leg.
    // AStart/AEnd are world coords of the two endpoints of the leg.
    // AFanIndex is this leg's index among all legs on the same species node.
    // AFanTotal is the total number of legs on that species node.
    // AJunctionAtEnd: True => AEnd is the junction (reactant leg).
    //                 False => AStart is the junction (product leg).
    // Fan offset is applied ONLY at the junction-end ctrl pt.
    procedure ComputeAutoCtrlPts(const AStart, AEnd: TPointF;
                                 AFanIndex, AFanTotal: Integer;
                                 AJunctionAtEnd: Boolean;
                                 out ACtrl1, ACtrl2: TPointF);

    // Return control points for a participant leg, computing them if not set.
    procedure GetCtrlPts(P: TParticipant;
                         const AStart, AEnd: TPointF;
                         AFanIndex, AFanTotal: Integer;
                         AJunctionAtEnd: Boolean;
                         out ACtrl1, ACtrl2: TPointF);

    // Hit-test a Bezier control point handle.
    // Returns True and sets APart/ACtrlNum when a handle is within tolerance.
    // AAutoC1/AAutoC2 return the auto-computed ctrl pts for pre-drag materialisation.
    function HitTestCtrlPt(const ScreenPt: TPointF;
                           out APart: TParticipant;
                           out ACtrlNum: Integer;
                           out AAutoC1, AAutoC2: TPointF): Boolean;

    // Bezier geometry helpers.
    // Evaluate cubic Bezier at parameter t in [0,1].
    function  BezierEval(const P0, C1, C2, P3: TPointF; t: Single): TPointF;
    // Binary-search for the t where the Bezier crosses the species rectangle.
    // AInsideAtZero: True when t=0 endpoint (P0) is inside the rectangle.
    function  BezierBoundaryT(const P0, C1, C2, P3: TPointF;
                              const Centre: TPointF; HalfW, HalfH: Single;
                              AInsideAtZero: Boolean): Single;
    // De Casteljau split: left sub-curve [0..t] returned as (L0,L1,L2,L3).
    procedure BezierLeftHalf(const P0, C1, C2, P3: TPointF; t: Single;
                             out L0, L1, L2, L3: TPointF);
    // De Casteljau split: right sub-curve [t..1] returned as (R0,R1,R2,R3).
    procedure BezierRightHalf(const P0, C1, C2, P3: TPointF; t: Single;
                              out R0, R1, R2, R3: TPointF);

    // -----------------------------------------------------------------------
    procedure RenderBackground     (const ACanvas: ISkCanvas; W, H: Single);
    procedure RenderReactions      (const ACanvas: ISkCanvas);
    procedure RenderSpeciesNodes   (const ACanvas: ISkCanvas);
    procedure RenderSelectionHalos (const ACanvas: ISkCanvas);
    procedure RenderJunctionHandles(const ACanvas: ISkCanvas);
    procedure RenderCtrlPtHandles  (const ACanvas: ISkCanvas);
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

    procedure DeleteSelected;

    // Undo helpers
    function  TakeSnapshot: string;
    function  MakeRestoreProc: TAfterRestoreProc;
    function  FindParticipantInfo(APart: TParticipant;
                                  out AReactionId: string;
                                  out AIsReactant: Boolean;
                                  out AIndex: Integer): Boolean;
    procedure ClearTransientState;

    // Enforce collinear inner handles through the junction (smooth-junction mode).
    procedure ApplySmoothJunction;

    // Measure the rendered width of AText at VIEW_FONT_SIZE in world units.
    function  MeasureTextWorldWidth(const AText: string): Single;

    // Compute the smooth axis unit vector for reaction R (CentR → CentP direction).
    // Used by MaterialiseSmoothCtrlPts.
    procedure ComputeSmoothAxis(R: TReaction; out AAxisX, AAxisY: Single);

    // Materialise all ctrl pts for R with collinear inner handles along the
    // smooth axis at the current junction position.  Does NOT move the junction
    // or change IsBezier/IsLinear.  Called when toggling smooth mode ON and
    // from NiceBezierForReaction's smooth branch.
    procedure MaterialiseSmoothCtrlPts(R: TReaction);

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

    procedure SyncSpeciesIdCounter;

    function RightClickHitTest(X, Y: Single;
                               out HitSpecies : TSpeciesNode;
                               out HitReaction: TReaction): TRightClickTarget;

    function  CreateAliasAt(APrimary: TSpeciesNode): TSpeciesNode;
    procedure GoToPrimary  (AAlias: TSpeciesNode);

    // --- Antimony import / export ---
    procedure ImportAntimony(const ASource: string);
    function  ExportAntimony: string;

    procedure ImportSBML(const ASource: string);
    function ExportSBML: string;

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
    property DefaultBezier         : Boolean read FDefaultBezier         write FDefaultBezier;
    property DefaultSmoothJunction : Boolean read FDefaultSmoothJunction write FDefaultSmoothJunction;

    // Undo / Redo
    procedure Undo;
    procedure Redo;
    function  CanUndo: Boolean;
    function  CanRedo: Boolean;
    function  UndoDescription: string;
    function  RedoDescription: string;

    // Toggle IsLinear on all currently selected UniUni reactions.
    // Reactions that are not UniUni are silently skipped.
    procedure ToggleLinearSelected;

    // Set IsBezier on all selected reactions (any stoichiometry).
    // Clears IsLinear so the three modes stay mutually exclusive.
    procedure SetBezierSelected;

    // Set straight mode (IsBezier=False, IsLinear=False) on all selected
    // reactions.  Junction is repositioned at the species midpoint for
    // UniUni reactions so the handle appears in a sensible place.
    procedure SetStraightSelected;

    // Toggle IsJunctionSmooth on all selected Bézier reactions.
    // Non-Bézier reactions are silently skipped.
    // Each reaction is toggled independently so a mixed selection gets flipped.
    procedure ToggleJunctionSmoothSelected;

    // Returns the first currently selected reaction, or nil if none are selected.
    // Convenient for menu handlers that operate on the selection.
    function SelectedReaction: TReaction;

    // Expand a species node's width so its label fits with padding on each side.
    // Pass the primary node; alias nodes sharing the same name are also resized.
    // Call after any name change and before taking an undo snapshot.
    procedure FitNodeToText(S: TSpeciesNode);

    // Reset all Bézier control points on the given reaction and reposition the
    // junction at the natural centroid midpoint so the curves look clean.
    // The reaction is set to Bézier mode if it is not already.
    // AReactionId is the reaction's Id string (R.Id).
    procedure NiceBezierForReaction(const AReactionId: string);

    // Select all species and reactions.
    procedure SelectAll;
  end;

implementation

// ===========================================================================
//  Color palette
// ===========================================================================
const
  CLR_BACKGROUND    : TAlphaColor = $FFF8F9FA;
  CLR_NODE_FILL     : TAlphaColor = $FFEEF6FF;
  CLR_NODE_BORDER   : TAlphaColor = $FF4A7FCB;
  CLR_NODE_FILL_SEL : TAlphaColor = $FFCCE0FF;  // kept for any future use
  CLR_NODE_BORD_SEL : TAlphaColor = $FF1144CC;  // kept for any future use
  CLR_SEL_RING      : TAlphaColor = claRed;  // selection halo around nodes
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

  // Bézier control point handles
  CLR_CTRL_FILL         : TAlphaColor = $FFFFFFFF;   // white fill
  CLR_CTRL_BORDER       : TAlphaColor = $FF888800;   // dark yellow
  CLR_CTRL_LINE         : TAlphaColor = $FFAAAAAA;   // grey guide line to endpoint
  CLR_CTRL_INNER_SMOOTH : TAlphaColor = $FF009999;   // teal — inner handle, smooth mode on

  VIEW_CTRL_RADIUS  = 4.0;   // world px, handle circle radius
  VIEW_CTRL_HIT     = 8.0;   // screen px, hit tolerance

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
  FDefaultBezier      := False;
  FDefaultSmoothJunction := False;
  FDraggedParticipant  := nil;
  FDraggedCtrlNum      := 0;
  FDragCtrlPtPartIdx   := -1;
  FDragCtrlPtIsReactant:= False;
  FDragCtrlPtIsInner   := False;
  FDragCtrlPtReaction  := nil;
  FDragCtrlPtSnapNum   := 0;
  FDragJunctionSmooth        := False;
  FDragJunctionSmoothSnapNum := 0;
  FNextSpeciesNum      := 1;
  FPendingReactants    := TList<TSpeciesNode>.Create;
  FPendingProducts     := TList<TSpeciesNode>.Create;
  FSavedSpeciesPos     := TDictionary<TSpeciesNode, TPointF>.Create;
  FSavedJunctionPos    := TDictionary<TReaction,    TPointF>.Create;
  FSavedCtrlPts        := TDictionary<TParticipant, TCtrlPtDragInfo>.Create;
  FDragHasCtrlPts      := False;
  FDragNodesSnapNum    := 0;
  FUndoManager         := TUndoManager.Create;
  // Build the restore callback once; it captures Self via closure.
  FRestoreProc := MakeRestoreProc();
end;

destructor TDiagramView.Destroy;
begin
  FUndoManager.Free;
  FSavedJunctionPos.Free;
  FSavedCtrlPts.Free;
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
const
  BEZIER_SAMPLES = 20;  // number of segments to sample along each Bézier leg
var
  Reaction  : TReaction;
  P         : TParticipant;
  JPos      : TPointF;
  JScr      : TPointF;
  BoundW    : TPointF;
  TipW      : TPointF;
  C1W, C2W  : TPointF;
  FanTotal  : Integer;
  i, k      : Integer;
  t, t1     : Single;
  PrevScr   : TPointF;
  CurrScr   : TPointF;

  // Evaluate a cubic Bézier at parameter t in screen space
  function BezierScr(const P0, P1, P2, P3: TPointF; t: Single): TPointF;
  var
    mt : Single;
  begin
    mt := 1 - t;
    Result.X := mt*mt*mt*P0.X + 3*mt*mt*t*P1.X + 3*mt*t*t*P2.X + t*t*t*P3.X;
    Result.Y := mt*mt*mt*P0.Y + 3*mt*mt*t*P1.Y + 3*mt*t*t*P2.Y + t*t*t*P3.Y;
  end;

  // AJunctionAtEnd: True = reactant (centre->junction), False = product (junction->centre)
  function HitBezierLeg(const StartW, EndW: TPointF;
                        AP: TParticipant; AFanIdx, AFanTotal: Integer;
                        AJunctionAtEnd: Boolean): Boolean;
  var
    PtW  : TPointF;
    k    : Integer;
  begin
    GetCtrlPts(AP, StartW, EndW, AFanIdx, AFanTotal, AJunctionAtEnd, C1W, C2W);
    PrevScr := W2S(StartW);
    for k := 1 to BEZIER_SAMPLES do
    begin
      t    := k / BEZIER_SAMPLES;
      PtW  := BezierEval(StartW, C1W, C2W, EndW, t);
      // Skip segments that lie entirely inside the species rectangle
      // (the node is drawn on top; those parts are invisible anyway).
      if not AP.Species.BoundsRect.Contains(PtW) then
      begin
        CurrScr := W2S(PtW);
        if PointToSegmentDist(ScreenPt, PrevScr, CurrScr) <= VIEW_HIT_SEGMENT then
        begin
          Result := True; Exit;
        end;
        PrevScr := CurrScr;
      end;
    end;
    Result := False;
  end;

begin
  Result := False; R := nil;

  for Reaction in FModel.Reactions do
  begin
    JPos := EffectiveJunctionPos(Reaction);
    JScr := W2S(JPos);

    if Reaction.IsBezier then
    begin
      // Reactant legs — sample along the Bézier curve
      FanTotal := Reaction.Reactants.Count;
      for i := 0 to FanTotal - 1 do
      begin
        P      := Reaction.Reactants[i];
        if HitBezierLeg(P.Species.Center, JPos, P, i, FanTotal, True) then
        begin R := Reaction; Result := True; Exit; end;
      end;

      // Product legs
      FanTotal := Reaction.Products.Count;
      for i := 0 to FanTotal - 1 do
      begin
        P    := Reaction.Products[i];
        if HitBezierLeg(JPos, P.Species.Center, P, i, FanTotal, False) then
        begin R := Reaction; Result := True; Exit; end;
      end;
    end
    else
    begin
      // Straight legs — test against line segment as before
      for P in Reaction.Reactants do
      begin
        BoundW := RectBoundaryIntersect(P.Species.Center, P.Species.HalfW,
                                        P.Species.HalfH, JPos);
        if PointToSegmentDist(ScreenPt, W2S(BoundW), JScr) <= VIEW_HIT_SEGMENT then
        begin R := Reaction; Result := True; Exit; end;
      end;

      for P in Reaction.Products do
      begin
        TipW := ProductLineTip(P.Species.Center, P.Species.HalfW,
                                P.Species.HalfH, JPos, VIEW_PRODUCT_GAP);
        if PointToSegmentDist(ScreenPt, JScr, W2S(TipW)) <= VIEW_HIT_SEGMENT then
        begin R := Reaction; Result := True; Exit; end;
      end;
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
var
  SnapBefore : string;
  SnapNum    : Integer;
begin
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  Result := FModel.AddAlias(APrimary,
    APrimary.Center.X + VIEW_ALIAS_OFFSET,
    APrimary.Center.Y + VIEW_ALIAS_OFFSET);
  FModel.ClearSelection;
  Result.Selected := True;
  FUndoManager.Push(TSnapshotCmd.Create('Create alias', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
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
  Info     : TCtrlPtDragInfo;
  JunctionMoved : Boolean;
  SpeciesMoved  : Boolean;
begin
  FSavedSpeciesPos.Clear;
  FSavedJunctionPos.Clear;
  FSavedCtrlPts.Clear;

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

    // --- Ctrl pt translation ---
    // For each Bézier participant with stored ctrl pts, record which handles
    // need to follow the drag and their pre-drag positions.
    //
    //   Reactant leg: Ctrl1 = outer (species-side), Ctrl2 = inner (junction-side)
    //   Product  leg: Ctrl1 = inner (junction-side), Ctrl2 = outer (species-side)
    //
    // A handle translates when its associated endpoint is in the moved set.
    for R in FModel.Reactions do
    begin
      if not R.IsBezier then Continue;
      JunctionMoved := FSavedJunctionPos.ContainsKey(R);

      for P in R.Reactants do
      begin
        if not P.CtrlPtsSet then Continue;
        SpeciesMoved := SelSet.ContainsKey(P.Species);
        Info.Move1 := SpeciesMoved;   // Ctrl1 = species-side outer
        Info.Move2 := JunctionMoved;  // Ctrl2 = junction-side inner
        if Info.Move1 or Info.Move2 then
        begin
          Info.Orig1 := P.Ctrl1;
          Info.Orig2 := P.Ctrl2;
          FSavedCtrlPts.AddOrSetValue(P, Info);
        end;
      end;

      for P in R.Products do
      begin
        if not P.CtrlPtsSet then Continue;
        SpeciesMoved := SelSet.ContainsKey(P.Species);
        Info.Move1 := JunctionMoved;  // Ctrl1 = junction-side inner
        Info.Move2 := SpeciesMoved;   // Ctrl2 = species-side outer
        if Info.Move1 or Info.Move2 then
        begin
          Info.Orig1 := P.Ctrl1;
          Info.Orig2 := P.Ctrl2;
          FSavedCtrlPts.AddOrSetValue(P, Info);
        end;
      end;
    end;
    FDragHasCtrlPts := FSavedCtrlPts.Count > 0;
  finally
    SelSet.Free;
  end;
end;

procedure TDiagramView.ApplyDragDelta(const Delta: TPointF);
var
  Pair    : TPair<TSpeciesNode, TPointF>;
  RPair   : TPair<TReaction,    TPointF>;
  CPair   : TPair<TParticipant, TCtrlPtDragInfo>;
  Info    : TCtrlPtDragInfo;
  R       : TReaction;
begin
  // Move species and junctions.
  for Pair in FSavedSpeciesPos do
    Pair.Key.Center := TPointF.Create(
      Pair.Value.X + Delta.X, Pair.Value.Y + Delta.Y);
  for RPair in FSavedJunctionPos do
    RPair.Key.JunctionPos := TPointF.Create(
      RPair.Value.X + Delta.X, RPair.Value.Y + Delta.Y);

  // Translate stored Bézier ctrl pts whose associated endpoint(s) moved.
  // Applying saved-original + delta each frame avoids compounding errors.
  for CPair in FSavedCtrlPts do
  begin
    Info := CPair.Value;
    if Info.Move1 then
      CPair.Key.Ctrl1 := TPointF.Create(Info.Orig1.X + Delta.X, Info.Orig1.Y + Delta.Y);
    if Info.Move2 then
      CPair.Key.Ctrl2 := TPointF.Create(Info.Orig2.X + Delta.X, Info.Orig2.Y + Delta.Y);
  end;

  // For smooth reactions whose junction moved, rematerialise all ctrl pts from
  // the updated positions so collinearity through the junction is preserved.
  for RPair in FSavedJunctionPos do
  begin
    R := RPair.Key;
    if R.IsBezier and R.IsJunctionSmooth then
      MaterialiseSmoothCtrlPts(R);
  end;
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

  var SnapBefore := TakeSnapshot;
  var SnapNum    := FNextSpeciesNum;
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
    RateLaw := RateLaw + '*' + FPendingReactants[i].Id;

  R.KineticLaw := RateLaw;

  // When DefaultBezier is on, every new reaction (including UniUni) is Bézier.
  // Otherwise UniUni defaults to a collinear straight line.
  if FDefaultBezier then
    R.IsBezier := True
  else if (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    R.IsLinear := True;
  // else: straight multi-participant -- IsLinear and IsBezier both False

  // When DefaultSmoothJunction is on, new Bézier reactions get smooth junctions
  // with ctrl pts materialised immediately so the layout is correct from the start.
  // Silently skipped if the reaction ended up in linear or straight mode.
  if FDefaultSmoothJunction and R.IsBezier then
  begin
    R.IsJunctionSmooth := True;
    MaterialiseSmoothCtrlPts(R);
  end;

  // Add the rate constant as a parameter with a default value of 0.1
  // only if a parameter with this name does not already exist.
  if not Assigned(FModel.FindParameterByVar(KName)) then
    FModel.AddParameter(KName, '0.1');

  FUndoManager.Push(TSnapshotCmd.Create('Add reaction', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
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

procedure TDiagramView.SyncSpeciesIdCounter;
var
  S    : TSpeciesNode;
  N    : Integer;
  MaxN : Integer;
  Tail : string;
begin
  MaxN := 0;
  for S in FModel.Species do
    if (Length(S.Id) > 1) and (S.Id[Low(S.Id)] = 'S') then
    begin
      Tail := Copy(S.Id, 2, MaxInt);
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
  SnapBefore   : string;
  SnapNum      : Integer;
begin
  SelSpecies   := FModel.SelectedSpecies;
  SelReactions := FModel.SelectedReactions;
  if (Length(SelSpecies) = 0) and (Length(SelReactions) = 0) then Exit;

  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;

  for S in SelSpecies do FModel.DeleteSpecies(S, Dummy);

  for R in SelReactions do
    if FModel.FindReactionById(R.Id) <> nil then
      FModel.DeleteReaction(R);

  FUndoManager.Push(TSnapshotCmd.Create('Delete', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
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
    Ord('A'), Ord('a'):
      if ssCtrl in Shift then
      begin
        SelectAll;
        Key := 0;
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
    begin
      var SnapBefore := TakeSnapshot;
      var SnapNum    := FNextSpeciesNum;
      FModel.AddSpecies(NextSpeciesName, WorldPt.X, WorldPt.Y);
      FUndoManager.Push(TSnapshotCmd.Create('Add species', FModel,
        SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
    end;

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
      // Priority: ctrl pt handle > junction > species > leg > rubber-band
      if HitTestCtrlPt(ScreenPt, FDraggedParticipant, FDraggedCtrlNum,
                        FDragAutoC1, FDragAutoC2) then
      begin
        // Capture old state for undo BEFORE materialising.
        FDragCtrlPtOldState.Ctrl1      := FDraggedParticipant.Ctrl1;
        FDragCtrlPtOldState.Ctrl2      := FDraggedParticipant.Ctrl2;
        FDragCtrlPtOldState.CtrlPtsSet := FDraggedParticipant.CtrlPtsSet;
        FindParticipantInfo(FDraggedParticipant,
                            FDragCtrlPtReactionId,
                            FDragCtrlPtIsReactant,
                            FDragCtrlPtPartIdx);
        // Cache the owning reaction so MouseMove can check IsJunctionSmooth cheaply.
        FDragCtrlPtReaction := FModel.FindReactionById(FDragCtrlPtReactionId);
        // Determine whether this handle is the inner (junction-side) one:
        //   Reactant leg: inner = Ctrl2 (num 2);  Product leg: inner = Ctrl1 (num 1).
        FDragCtrlPtIsInner :=
          ((FDraggedCtrlNum = 2) and  FDragCtrlPtIsReactant) or
          ((FDraggedCtrlNum = 1) and (not FDragCtrlPtIsReactant));
        // If this reaction uses smooth junctions and we are grabbing an inner
        // handle, capture a full model snapshot BEFORE materialisation so that
        // undo covers every participant the constraint will touch.
        if Assigned(FDragCtrlPtReaction) and
           FDragCtrlPtReaction.IsJunctionSmooth and FDragCtrlPtIsInner then
        begin
          FDragCtrlPtSnapBefore := TakeSnapshot;
          FDragCtrlPtSnapNum    := FNextSpeciesNum;
        end;
        // Materialise both ctrl pts from auto values so the undragged handle
        // is never left at (0,0).
        if not FDraggedParticipant.CtrlPtsSet then
        begin
          FDraggedParticipant.Ctrl1      := FDragAutoC1;
          FDraggedParticipant.Ctrl2      := FDragAutoC2;
          FDraggedParticipant.CtrlPtsSet := True;
        end;
        FState := isDraggingCtrlPt;
      end
      else if HitTestJunction(ScreenPt, HitReaction) then
      begin
        if not (ssShift in Shift) then FModel.ClearSelection;
        HitReaction.Selected  := True;
        FDraggedJunction      := HitReaction;
        FDragJunctionOldPos   := HitReaction.JunctionPos;  // for undo
        FDragAnchorWorld      := WorldPt;
        // Capture whether this reaction uses smooth junctions at drag-start so
        // a mid-drag mode toggle cannot create inconsistent undo state.
        FDragJunctionSmooth := HitReaction.IsJunctionSmooth;
        if FDragJunctionSmooth then
        begin
          FDragJunctionSmoothSnap    := TakeSnapshot;
          FDragJunctionSmoothSnapNum := FNextSpeciesNum;
        end;
        FState := isDraggingJunction;
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
          // When stored ctrl pts will be translated with the group, a lightweight
          // TMoveNodesCmd is insufficient for undo — capture a full snapshot.
          if FDragHasCtrlPts then
          begin
            FDragNodesSnap    := TakeSnapshot;
            FDragNodesSnapNum := FNextSpeciesNum;
          end;
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
    begin
      // When smooth mode is on, every materialised inner handle must translate
      // by exactly the same delta as the junction so that their world-space
      // offset from J stays constant — preserving collinearity.
      // Compute delta BEFORE updating JunctionPos.
      if FDragJunctionSmooth then
      begin
        var DX := WorldPt.X - FDraggedJunction.JunctionPos.X;
        var DY := WorldPt.Y - FDraggedJunction.JunctionPos.Y;
        var R  := FDraggedJunction;
        var P  : TParticipant;
        for P in R.Reactants do
          if P.CtrlPtsSet then   // Ctrl2 is the inner (junction-side) handle
            P.Ctrl2 := TPointF.Create(P.Ctrl2.X + DX, P.Ctrl2.Y + DY);
        for P in R.Products do
          if P.CtrlPtsSet then   // Ctrl1 is the inner (junction-side) handle
            P.Ctrl1 := TPointF.Create(P.Ctrl1.X + DX, P.Ctrl1.Y + DY);
      end;
      FDraggedJunction.JunctionPos := WorldPt;
    end;
    isDraggingCtrlPt:
    begin
      // Move the dragged control point to the world position and mark as set.
      if FDraggedCtrlNum = 1 then
        FDraggedParticipant.Ctrl1 := WorldPt
      else
        FDraggedParticipant.Ctrl2 := WorldPt;
      FDraggedParticipant.CtrlPtsSet := True;
      // When this reaction uses smooth junctions and we are dragging an inner
      // handle, enforce collinearity across all inner handles of this reaction.
      if FDragCtrlPtIsInner and
         Assigned(FDragCtrlPtReaction) and
         FDragCtrlPtReaction.IsJunctionSmooth then
        ApplySmoothJunction;
    end;
    isRubberBand:
      FRubberCurScr := ScreenPt;
  end;
end;

procedure TDiagramView.MouseUp(Button: TMouseButton; Shift: TShiftState;
                                X, Y: Single);
var
  SpecBefore, SpecAfter : TDictionary<string, TPointF>;
  JctBefore, JctAfter   : TDictionary<string, TPointF>;
  Pair  : TPair<TSpeciesNode, TPointF>;
  RPair : TPair<TReaction,    TPointF>;
  NewState : TCtrlPtState;
  AnyMoved : Boolean;
begin
  if Button <> TMouseButton.mbLeft then Exit;
  FMouseScreen := TPointF.Create(X, Y);
  FMouseWorld  := S2W(FMouseScreen);

  case FState of
    isDraggingNodes:
    begin
      // Build before/after position dicts keyed by string Id.
      SpecBefore := TDictionary<string, TPointF>.Create;
      SpecAfter  := TDictionary<string, TPointF>.Create;
      JctBefore  := TDictionary<string, TPointF>.Create;
      JctAfter   := TDictionary<string, TPointF>.Create;
      AnyMoved   := False;
      for Pair in FSavedSpeciesPos do
      begin
        SpecBefore.AddOrSetValue(Pair.Key.Id, Pair.Value);
        SpecAfter.AddOrSetValue (Pair.Key.Id, Pair.Key.Center);
        if (Pair.Value.X <> Pair.Key.Center.X) or
           (Pair.Value.Y <> Pair.Key.Center.Y) then AnyMoved := True;
      end;
      for RPair in FSavedJunctionPos do
      begin
        JctBefore.AddOrSetValue(RPair.Key.Id, RPair.Value);
        JctAfter.AddOrSetValue (RPair.Key.Id, RPair.Key.JunctionPos);
        if (RPair.Value.X <> RPair.Key.JunctionPos.X) or
           (RPair.Value.Y <> RPair.Key.JunctionPos.Y) then AnyMoved := True;
      end;
      if AnyMoved then
      begin
        if FDragHasCtrlPts then
          // Ctrl pts also moved — only a snapshot covers all changes for undo.
          FUndoManager.Push(TSnapshotCmd.Create('Move', FModel,
            FDragNodesSnap, TakeSnapshot,
            FDragNodesSnapNum, FNextSpeciesNum, FRestoreProc))
        else
          FUndoManager.Push(TMoveNodesCmd.Create(FModel,
            SpecBefore, SpecAfter, JctBefore, JctAfter));
      end;
      if FDragHasCtrlPts or not AnyMoved then
      begin
        SpecBefore.Free; SpecAfter.Free;
        JctBefore.Free;  JctAfter.Free;
      end;
      FState := isSelect;
    end;

    isDraggingJunction:
    begin
      if (FDragJunctionOldPos.X <> FDraggedJunction.JunctionPos.X) or
         (FDragJunctionOldPos.Y <> FDraggedJunction.JunctionPos.Y) then
      begin
        if FDragJunctionSmooth then
          // Smooth mode moved inner handles too — only a snapshot covers all changes.
          FUndoManager.Push(TSnapshotCmd.Create('Move junction', FModel,
            FDragJunctionSmoothSnap, TakeSnapshot,
            FDragJunctionSmoothSnapNum, FNextSpeciesNum, FRestoreProc))
        else
          FUndoManager.Push(TMoveJunctionCmd.Create(FModel,
            FDraggedJunction.Id,
            FDragJunctionOldPos, FDraggedJunction.JunctionPos));
      end;
      FState := isSelect;
    end;

    isDraggingCtrlPt:
    begin
      if Assigned(FDraggedParticipant) then
      begin
        if FDragCtrlPtIsInner and
           Assigned(FDragCtrlPtReaction) and
           FDragCtrlPtReaction.IsJunctionSmooth then
        begin
          // Smooth mode may have updated several participants — snapshot undo.
          var SnapAfter := TakeSnapshot;
          if SnapAfter <> FDragCtrlPtSnapBefore then
            FUndoManager.Push(TSnapshotCmd.Create('Move control point', FModel,
              FDragCtrlPtSnapBefore, SnapAfter,
              FDragCtrlPtSnapNum, FNextSpeciesNum, FRestoreProc));
        end
        else
        begin
          // Standard mode: only the dragged participant changed.
          NewState.Ctrl1      := FDraggedParticipant.Ctrl1;
          NewState.Ctrl2      := FDraggedParticipant.Ctrl2;
          NewState.CtrlPtsSet := FDraggedParticipant.CtrlPtsSet;
          // Only push if something actually changed.
          if (NewState.Ctrl1.X    <> FDragCtrlPtOldState.Ctrl1.X) or
             (NewState.Ctrl1.Y    <> FDragCtrlPtOldState.Ctrl1.Y) or
             (NewState.Ctrl2.X    <> FDragCtrlPtOldState.Ctrl2.X) or
             (NewState.Ctrl2.Y    <> FDragCtrlPtOldState.Ctrl2.Y) or
             (NewState.CtrlPtsSet <> FDragCtrlPtOldState.CtrlPtsSet) then
            FUndoManager.Push(TDragCtrlPtCmd.Create(FModel,
              FDragCtrlPtReactionId, FDragCtrlPtIsReactant, FDragCtrlPtPartIdx,
              FDragCtrlPtOldState, NewState));
        end;
      end;
      FState := isSelect;
    end;

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
  NewId    : string;
begin
  if FState <> isSelect then Exit;
  if not HitTestSpecies(FMouseWorld, HitSpecies) then Exit;
  EditTarget := HitSpecies;
  if HitSpecies.IsAlias then EditTarget := HitSpecies.AliasOf;
  NewId := InputBox('Rename Species', 'Id:', EditTarget.Id);
  if (NewId <> '') and (NewId <> EditTarget.Id) then
  begin
    var SnapBefore := TakeSnapshot;
    var SnapNum    := FNextSpeciesNum;
    EditTarget.Id := NewId;
    FitNodeToText(EditTarget);   // widen node if new name is longer
    FUndoManager.Push(TSnapshotCmd.Create('Rename', FModel,
      SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
  end;
end;

procedure TDiagramView.SelectAll;
var
  S : TSpeciesNode;
  R : TReaction;
begin
  for S in FModel.Species   do S.Selected := True;
  for R in FModel.Reactions do R.Selected := True;
end;

procedure TDiagramView.ToggleLinearSelected;
var
  R          : TReaction;
  A, B       : TPointF;
  SnapBefore : string;
  SnapNum    : Integer;
begin
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;

  for R in FModel.Reactions do
    if R.Selected and (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    begin
      R.IsLinear := not R.IsLinear;

      if R.IsLinear then
      begin
        // Switching TO linear: Bezier mode and its handles must be hidden.
        R.IsBezier := False;
      end
      else
      begin
        // Switching OFF linear: place the junction at the midpoint so the
        // handle reappears sensibly regardless of how far nodes have moved.
        A := R.Reactants[0].Species.Center;
        B := R.Products[0].Species.Center;
        R.JunctionPos := TPointF.Create(
          (A.X + B.X) * 0.5, (A.Y + B.Y) * 0.5);
      end;
    end;

  FUndoManager.Push(TSnapshotCmd.Create('Toggle linear', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.SetBezierSelected;
var
  R          : TReaction;
  SnapBefore : string;
  SnapNum    : Integer;
begin
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  for R in FModel.Reactions do
    if R.Selected then
    begin
      R.IsBezier := True;
      R.IsLinear := False;
    end;
  FUndoManager.Push(TSnapshotCmd.Create('Set Bezier', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.SetStraightSelected;
var
  R          : TReaction;
  A, B       : TPointF;
  SnapBefore : string;
  SnapNum    : Integer;
begin
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  for R in FModel.Reactions do
    if R.Selected then
    begin
      R.IsBezier := False;
      R.IsLinear := False;
      if (R.Reactants.Count = 1) and (R.Products.Count = 1) then
      begin
        A := R.Reactants[0].Species.Center;
        B := R.Products[0].Species.Center;
        R.JunctionPos := TPointF.Create((A.X + B.X) * 0.5, (A.Y + B.Y) * 0.5);
      end;
    end;
  FUndoManager.Push(TSnapshotCmd.Create('Set straight', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.ToggleJunctionSmoothSelected;
// Toggle IsJunctionSmooth on every selected Bézier reaction independently.
// Non-Bézier reactions are silently skipped.
// When turning smooth ON, all ctrl pts are immediately materialised with
// collinear inner handles so the user sees the correct layout right away.
var
  R          : TReaction;
  SnapBefore : string;
  SnapNum    : Integer;
  AnyChanged : Boolean;
begin
  AnyChanged := False;
  for R in FModel.Reactions do
    if R.Selected and R.IsBezier then
    begin
      AnyChanged := True; Break;
    end;
  if not AnyChanged then Exit;

  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  for R in FModel.Reactions do
    if R.Selected and R.IsBezier then
    begin
      R.IsJunctionSmooth := not R.IsJunctionSmooth;
      // When turning smooth ON, materialise all ctrl pts collinearly at once
      // so handles are in the correct position immediately — not deferred to
      // the next drag.
      if R.IsJunctionSmooth then
        MaterialiseSmoothCtrlPts(R);
    end;

  FUndoManager.Push(TSnapshotCmd.Create('Toggle smooth junction', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
end;

// ---------------------------------------------------------------------------

function TDiagramView.SelectedReaction: TReaction;
// Return the first selected reaction, or nil.
var
  R : TReaction;
begin
  Result := nil;
  for R in FModel.Reactions do
    if R.Selected then begin Result := R; Exit; end;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.NiceBezierForReaction(const AReactionId: string);
// Produce a clean Bézier layout for the named reaction.
//
// The method is aware of IsJunctionSmooth and behaves differently in each case:
//
// Non-smooth (IsJunctionSmooth=False):
//   • Clears all ctrl pts (CtrlPtsSet := False) so ComputeAutoCtrlPts takes
//     over at render time — the standard fan-spread layout that self-adapts
//     when species are later moved.
//
// Smooth (IsJunctionSmooth=True):
//   • Explicitly materialises ALL ctrl pts (CtrlPtsSet := True) with
//     collinear inner handles from the outset so the user immediately sees
//     the correct smooth layout without needing to drag.
//
//   The inner (junction-side) handle of every leg is placed along the
//   "smooth axis" — the unit vector from the reactant centroid to the
//   product centroid through the junction.  Distance from the junction is
//   proportional to the individual leg length so curves scale naturally
//   for asymmetric networks.
//
//   The outer (species-side) handle uses the standard 35%-along-leg formula
//   with no fan offset so curves leave/arrive at each species node cleanly.
//
// In both cases:
//   • Junction is placed at the midpoint of (reactant centroid, product centroid).
//   • IsLinear is cleared; IsBezier is set.
//   • The change is fully undoable.
const
  CTRL_FRAC = 0.35;
var
  R          : TReaction;
  P          : TParticipant;
  SumRX, SumRY : Single;
  SumPX, SumPY : Single;
  CentR, CentP : TPointF;
  JPos         : TPointF;
  SnapBefore   : string;
  SnapNum      : Integer;
begin
  R := FModel.FindReactionById(AReactionId);
  if not Assigned(R) then Exit;

  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;

  // --- Ensure Bézier mode ---
  R.IsLinear := False;
  R.IsBezier := True;

  // --- Compute centroids ---
  SumRX := 0; SumRY := 0;
  for P in R.Reactants do
  begin
    SumRX := SumRX + P.Species.Center.X;
    SumRY := SumRY + P.Species.Center.Y;
  end;
  if R.Reactants.Count > 0 then
    CentR := TPointF.Create(SumRX / R.Reactants.Count, SumRY / R.Reactants.Count)
  else
    CentR := R.JunctionPos;

  SumPX := 0; SumPY := 0;
  for P in R.Products do
  begin
    SumPX := SumPX + P.Species.Center.X;
    SumPY := SumPY + P.Species.Center.Y;
  end;
  if R.Products.Count > 0 then
    CentP := TPointF.Create(SumPX / R.Products.Count, SumPY / R.Products.Count)
  else
    CentP := CentR;

  // --- Place junction at centroid midpoint ---
  JPos := TPointF.Create((CentR.X + CentP.X) * 0.5, (CentR.Y + CentP.Y) * 0.5);
  R.JunctionPos := JPos;

  // --- Non-smooth: reset to auto so ComputeAutoCtrlPts drives everything ---
  if not R.IsJunctionSmooth then
  begin
    for P in R.Reactants do P.ResetCtrlPts;
    for P in R.Products  do P.ResetCtrlPts;
  end
  else
    // --- Smooth: materialise collinear inner handles along the smooth axis ---
    MaterialiseSmoothCtrlPts(R);

  FUndoManager.Push(TSnapshotCmd.Create('Nice Bézier', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
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
//  Bézier helpers
// ===========================================================================

procedure TDiagramView.ComputeAutoCtrlPts(const AStart, AEnd: TPointF;
                                           AFanIndex, AFanTotal: Integer;
                                           AJunctionAtEnd: Boolean;
                                           out ACtrl1, ACtrl2: TPointF);
// AStart/AEnd are the conceptual leg endpoints:
//   Reactant leg (AJunctionAtEnd=True):  AStart = species.Centre, AEnd = junction
//   Product  leg (AJunctionAtEnd=False): AStart = junction, AEnd  = species.Centre
//
// Fan offset is applied ONLY at the junction-end control point so that
// the curve leaves/arrives at the species node tangent to the centre-junction
// direction, eliminating the "corner" artefact.
const
  CTRL_DIST_FRAC = 0.35;
  FAN_SPREAD     = 50.0;
var
  Dir    : TPointF;
  Perp   : TPointF;
  Len    : Single;
  Offset : Single;
begin
  Dir.X := AEnd.X - AStart.X;
  Dir.Y := AEnd.Y - AStart.Y;
  Len   := Sqrt(Dir.X * Dir.X + Dir.Y * Dir.Y);

  if Len < 1.0 then
  begin
    ACtrl1 := AStart;
    ACtrl2 := AEnd;
    Exit;
  end;

  Dir.X := Dir.X / Len;
  Dir.Y := Dir.Y / Len;

  // Perpendicular (CCW)
  Perp.X := -Dir.Y;
  Perp.Y :=  Dir.X;

  if AFanTotal <= 1 then
    Offset := 0
  else
    Offset := (AFanIndex - (AFanTotal - 1) * 0.5) * FAN_SPREAD;

  if AJunctionAtEnd then
  begin
    // Reactant: AStart = species centre, AEnd = junction.
    // Ctrl1 no offset (clean exit from centre), Ctrl2 fan offset at junction.
    ACtrl1.X := AStart.X + Dir.X * Len * CTRL_DIST_FRAC;
    ACtrl1.Y := AStart.Y + Dir.Y * Len * CTRL_DIST_FRAC;
    ACtrl2.X := AEnd.X   - Dir.X * Len * CTRL_DIST_FRAC + Perp.X * Offset;
    ACtrl2.Y := AEnd.Y   - Dir.Y * Len * CTRL_DIST_FRAC + Perp.Y * Offset;
  end
  else
  begin
    // Product: AStart = junction, AEnd = species centre.
    // Ctrl1 fan offset at junction, Ctrl2 no offset (clean arrival at centre).
    ACtrl1.X := AStart.X + Dir.X * Len * CTRL_DIST_FRAC + Perp.X * Offset;
    ACtrl1.Y := AStart.Y + Dir.Y * Len * CTRL_DIST_FRAC + Perp.Y * Offset;
    ACtrl2.X := AEnd.X   - Dir.X * Len * CTRL_DIST_FRAC;
    ACtrl2.Y := AEnd.Y   - Dir.Y * Len * CTRL_DIST_FRAC;
  end;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.GetCtrlPts(P: TParticipant;
                                   const AStart, AEnd: TPointF;
                                   AFanIndex, AFanTotal: Integer;
                                   AJunctionAtEnd: Boolean;
                                   out ACtrl1, ACtrl2: TPointF);
begin
  if P.CtrlPtsSet then
  begin
    ACtrl1 := P.Ctrl1;
    ACtrl2 := P.Ctrl2;
  end
  else
    ComputeAutoCtrlPts(AStart, AEnd, AFanIndex, AFanTotal, AJunctionAtEnd, ACtrl1, ACtrl2);
end;

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

procedure TDiagramView.ComputeSmoothAxis(R: TReaction;
                                          out AAxisX, AAxisY: Single);
// Returns the unit vector from the centroid of reactants to the centroid of
// products — the line along which all inner handles must lie.
var
  P              : TParticipant;
  SumRX, SumRY   : Single;
  SumPX, SumPY   : Single;
  CentR, CentP   : TPointF;
  Len            : Single;
begin
  SumRX := 0; SumRY := 0;
  for P in R.Reactants do
  begin SumRX := SumRX + P.Species.Center.X; SumRY := SumRY + P.Species.Center.Y; end;
  if R.Reactants.Count > 0 then
    CentR := TPointF.Create(SumRX / R.Reactants.Count, SumRY / R.Reactants.Count)
  else
    CentR := R.JunctionPos;

  SumPX := 0; SumPY := 0;
  for P in R.Products do
  begin SumPX := SumPX + P.Species.Center.X; SumPY := SumPY + P.Species.Center.Y; end;
  if R.Products.Count > 0 then
    CentP := TPointF.Create(SumPX / R.Products.Count, SumPY / R.Products.Count)
  else
    CentP := CentR;

  AAxisX := CentP.X - CentR.X;
  AAxisY := CentP.Y - CentR.Y;
  Len    := Sqrt(AAxisX * AAxisX + AAxisY * AAxisY);
  if Len > 0.5 then begin AAxisX := AAxisX / Len; AAxisY := AAxisY / Len; end
  else               begin AAxisX := 1.0;          AAxisY := 0.0; end;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.MaterialiseSmoothCtrlPts(R: TReaction);
// Explicitly set Ctrl1/Ctrl2 for every participant so that all inner handles
// lie on the smooth axis through the junction.
//
//   Reactant inner = Ctrl2 → J − axis × legLen × CTRL_FRAC  (reactant side)
//   Product  inner = Ctrl1 → J + axis × legLen × CTRL_FRAC  (product side)
//   Outer handles  → 35% along leg from species, no fan offset.
//
// Does NOT move the junction or change IsBezier/IsLinear.
const
  CTRL_FRAC = 0.35;
var
  AxisX, AxisY   : Single;
  JPos           : TPointF;
  P              : TParticipant;
  LegDX, LegDY  : Single;
  LegLen         : Single;
  LegUX, LegUY  : Single;
  C1, C2         : TPointF;
  i              : Integer;
begin
  ComputeSmoothAxis(R, AxisX, AxisY);
  JPos := R.JunctionPos;

  for i := 0 to R.Reactants.Count - 1 do
  begin
    P      := R.Reactants[i];
    LegDX  := JPos.X - P.Species.Center.X;
    LegDY  := JPos.Y - P.Species.Center.Y;
    LegLen := Sqrt(LegDX * LegDX + LegDY * LegDY);
    if LegLen < 1.0 then begin P.ResetCtrlPts; Continue; end;
    LegUX  := LegDX / LegLen; LegUY := LegDY / LegLen;
    C1.X := P.Species.Center.X + LegUX * LegLen * CTRL_FRAC; // outer
    C1.Y := P.Species.Center.Y + LegUY * LegLen * CTRL_FRAC;
    C2.X := JPos.X - AxisX * LegLen * CTRL_FRAC;              // inner (−axis)
    C2.Y := JPos.Y - AxisY * LegLen * CTRL_FRAC;
    P.Ctrl1 := C1; P.Ctrl2 := C2; P.CtrlPtsSet := True;
  end;

  for i := 0 to R.Products.Count - 1 do
  begin
    P      := R.Products[i];
    LegDX  := P.Species.Center.X - JPos.X;
    LegDY  := P.Species.Center.Y - JPos.Y;
    LegLen := Sqrt(LegDX * LegDX + LegDY * LegDY);
    if LegLen < 1.0 then begin P.ResetCtrlPts; Continue; end;
    LegUX  := LegDX / LegLen; LegUY := LegDY / LegLen;
    C1.X := JPos.X + AxisX * LegLen * CTRL_FRAC;              // inner (+axis)
    C1.Y := JPos.Y + AxisY * LegLen * CTRL_FRAC;
    C2.X := P.Species.Center.X - LegUX * LegLen * CTRL_FRAC;  // outer
    C2.Y := P.Species.Center.Y - LegUY * LegLen * CTRL_FRAC;
    P.Ctrl1 := C1; P.Ctrl2 := C2; P.CtrlPtsSet := True;
  end;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.ApplySmoothJunction;
// Enforce collinear inner handles whenever an inner handle is dragged.
//
// Inner handles:
//   Reactant leg → Ctrl2  (nearest the junction)
//   Product  leg → Ctrl1  (nearest the junction)
//
// Arm vector D = draggedInnerPos − J.  Sign convention:
//
//   Same role as dragged participant → SAME direction (+D):
//     Dragging a reactant inner handle places other reactant inner handles
//     at J + D̂ × their arm length — all reactant handles on the same side.
//
//   Opposite role → OPPOSITE direction (−D):
//     Product inner handles go to J − D̂ × their arm length, and vice-versa.
//
// Each handle's distance from J is preserved while collinearity is enforced.
var
  R              : TReaction;
  JPos           : TPointF;
  DraggedInner   : TPointF;
  ArmX, ArmY    : Single;
  ArmLen         : Single;
  P              : TParticipant;
  OtherInner     : TPointF;
  OtherArmLen    : Single;
  i              : Integer;
  AutoC1, AutoC2 : TPointF;
  SignedLen      : Single;
begin
  R := FDragCtrlPtReaction;
  if not Assigned(R) then Exit;

  JPos := R.JunctionPos;

  if FDragCtrlPtIsReactant then
    DraggedInner := FDraggedParticipant.Ctrl2
  else
    DraggedInner := FDraggedParticipant.Ctrl1;

  ArmX   := DraggedInner.X - JPos.X;
  ArmY   := DraggedInner.Y - JPos.Y;
  ArmLen := Sqrt(ArmX * ArmX + ArmY * ArmY);
  if ArmLen < 0.5 then Exit;
  ArmX := ArmX / ArmLen;
  ArmY := ArmY / ArmLen;

  for i := 0 to R.Reactants.Count - 1 do
  begin
    P := R.Reactants[i];
    if P = FDraggedParticipant then Continue;
    if not P.CtrlPtsSet then
    begin
      ComputeAutoCtrlPts(P.Species.Center, JPos, i, R.Reactants.Count, True, AutoC1, AutoC2);
      P.Ctrl1 := AutoC1; P.Ctrl2 := AutoC2; P.CtrlPtsSet := True;
    end;
    OtherInner  := P.Ctrl2;
    OtherArmLen := Sqrt(Sqr(OtherInner.X - JPos.X) + Sqr(OtherInner.Y - JPos.Y));
    if OtherArmLen < 0.5 then OtherArmLen := ArmLen;
    // Same role as dragged (reactant–reactant) → same direction (+ArmDir)
    // Opposite role (dragged is product) → opposite direction (−ArmDir)
    if FDragCtrlPtIsReactant then SignedLen :=  OtherArmLen
    else                          SignedLen := -OtherArmLen;
    P.Ctrl2 := TPointF.Create(JPos.X + ArmX * SignedLen, JPos.Y + ArmY * SignedLen);
  end;

  for i := 0 to R.Products.Count - 1 do
  begin
    P := R.Products[i];
    if P = FDraggedParticipant then Continue;
    if not P.CtrlPtsSet then
    begin
      ComputeAutoCtrlPts(JPos, P.Species.Center, i, R.Products.Count, False, AutoC1, AutoC2);
      P.Ctrl1 := AutoC1; P.Ctrl2 := AutoC2; P.CtrlPtsSet := True;
    end;
    OtherInner  := P.Ctrl1;
    OtherArmLen := Sqrt(Sqr(OtherInner.X - JPos.X) + Sqr(OtherInner.Y - JPos.Y));
    if OtherArmLen < 0.5 then OtherArmLen := ArmLen;
    // Same role as dragged (product–product) → same direction (+ArmDir)
    // Opposite role (dragged is reactant) → opposite direction (−ArmDir)
    if not FDragCtrlPtIsReactant then SignedLen :=  OtherArmLen
    else                               SignedLen := -OtherArmLen;
    P.Ctrl1 := TPointF.Create(JPos.X + ArmX * SignedLen, JPos.Y + ArmY * SignedLen);
  end;
end;


// ---------------------------------------------------------------------------
//  Bezier geometry helpers
// ---------------------------------------------------------------------------

function TDiagramView.BezierEval(const P0, C1, C2, P3: TPointF;
                                  t: Single): TPointF;
var
  mt : Single;
begin
  mt := 1.0 - t;
  Result.X := mt*mt*mt*P0.X + 3*mt*mt*t*C1.X + 3*mt*t*t*C2.X + t*t*t*P3.X;
  Result.Y := mt*mt*mt*P0.Y + 3*mt*mt*t*C1.Y + 3*mt*t*t*C2.Y + t*t*t*P3.Y;
end;

// ---------------------------------------------------------------------------

function TDiagramView.BezierBoundaryT(const P0, C1, C2, P3: TPointF;
                                       const Centre: TPointF;
                                       HalfW, HalfH: Single;
                                       AInsideAtZero: Boolean): Single;
// Binary search for the parameter t in [0,1] where the cubic Bezier
// transitions between inside and outside the axis-aligned rectangle.
//
// For a reactant leg (AInsideAtZero=True):
//   P0 = species centre (inside), P3 = junction (outside).
//   Returns the t where the curve first exits the rectangle.
//
// For a product leg (AInsideAtZero=False):
//   P0 = junction (outside), P3 = species centre (inside).
//   Returns the t where the curve enters the rectangle.
//
// Result is clamped to [0.001, 0.999] to avoid degenerate tip positions.
const
  BISECT_STEPS = 24;
  T_MIN        = 0.001;
  T_MAX        = 0.999;
var
  tLo, tHi, tMid : Single;
  Pt              : TPointF;

  function IsInside(const P: TPointF): Boolean;
  begin
    Result := (Abs(P.X - Centre.X) <= HalfW) and
              (Abs(P.Y - Centre.Y) <= HalfH);
  end;

  var step : Integer;
begin
  tLo := 0.0;
  tHi := 1.0;
  for step := 0 to BISECT_STEPS - 1 do
  begin
    tMid := (tLo + tHi) * 0.5;
    Pt   := BezierEval(P0, C1, C2, P3, tMid);
    if IsInside(Pt) = AInsideAtZero then
      tLo := tMid
    else
      tHi := tMid;
  end;
  Result := Max(T_MIN, Min(T_MAX, (tLo + tHi) * 0.5));
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.BezierLeftHalf(const P0, C1, C2, P3: TPointF;
                                       t: Single;
                                       out L0, L1, L2, L3: TPointF);
// De Casteljau split — returns the LEFT sub-curve [0..t]: (L0, L1, L2, L3).
// L3 is the point on the original curve at parameter t.
// Tangent at L3 is proportional to (L3 - L2).
var
  P01, P12, P23 : TPointF;
  P012, P123    : TPointF;

  function Lerp(const A, B: TPointF; s: Single): TPointF; inline;
  begin
    Result.X := A.X + s * (B.X - A.X);
    Result.Y := A.Y + s * (B.Y - A.Y);
  end;
begin
  P01  := Lerp(P0, C1, t);
  P12  := Lerp(C1, C2, t);
  P23  := Lerp(C2, P3, t);
  P012 := Lerp(P01, P12, t);
  P123 := Lerp(P12, P23, t);
  L0 := P0;
  L1 := P01;
  L2 := P012;
  L3 := Lerp(P012, P123, t);   // point on curve at t
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.BezierRightHalf(const P0, C1, C2, P3: TPointF;
                                        t: Single;
                                        out R0, R1, R2, R3: TPointF);
// De Casteljau split — returns the RIGHT sub-curve [t..1]: (R0, R1, R2, R3).
// R0 is the point on the original curve at parameter t.
// Tangent at R0 is proportional to (R1 - R0).
var
  P01, P12, P23 : TPointF;
  P012, P123    : TPointF;

  function Lerp(const A, B: TPointF; s: Single): TPointF; inline;
  begin
    Result.X := A.X + s * (B.X - A.X);
    Result.Y := A.Y + s * (B.Y - A.Y);
  end;
begin
  P01  := Lerp(P0, C1, t);
  P12  := Lerp(C1, C2, t);
  P23  := Lerp(C2, P3, t);
  P012 := Lerp(P01, P12, t);
  P123 := Lerp(P12, P23, t);
  R0 := Lerp(P012, P123, t);   // point on curve at t
  R1 := P123;
  R2 := P23;
  R3 := P3;
end;

// ---------------------------------------------------------------------------

function TDiagramView.HitTestCtrlPt(const ScreenPt: TPointF;
                                     out APart: TParticipant;
                                     out ACtrlNum: Integer;
                                     out AAutoC1, AAutoC2: TPointF): Boolean;
// Endpoints are centre-based (matching RenderReactions and RenderCtrlPtHandles).
// Always computes auto ctrl pts via ComputeAutoCtrlPts (not GetCtrlPts) so that
// AAutoC1/AAutoC2 are available for pre-drag materialisation regardless of
// whether CtrlPtsSet is already True.
var
  R          : TReaction;
  P          : TParticipant;
  C1W, C2W   : TPointF;
  StartW     : TPointF;
  EndW       : TPointF;
  FanTotal   : Integer;
  i          : Integer;

  function TryHit(const AC1, AC2: TPointF): Boolean;
  begin
    if PointDist(ScreenPt, W2S(AC1)) <= VIEW_CTRL_HIT then
    begin
      ACtrlNum := 1; Result := True;
    end
    else if PointDist(ScreenPt, W2S(AC2)) <= VIEW_CTRL_HIT then
    begin
      ACtrlNum := 2; Result := True;
    end
    else
      Result := False;
  end;

begin
  Result   := False;
  APart    := nil;
  ACtrlNum := 0;
  AAutoC1  := TPointF.Create(0, 0);
  AAutoC2  := TPointF.Create(0, 0);

  for R in FModel.Reactions do
  begin
    if not (R.Selected and R.IsBezier) then Continue;

    // Reactant legs: Start = species centre, End = junction
    FanTotal := R.Reactants.Count;
    for i := 0 to FanTotal - 1 do
    begin
      P      := R.Reactants[i];
      StartW := P.Species.Center;
      EndW   := R.JunctionPos;
      ComputeAutoCtrlPts(StartW, EndW, i, FanTotal, True, C1W, C2W);
      // Test stored positions when already set, otherwise test auto positions
      if P.CtrlPtsSet then
      begin
        if TryHit(P.Ctrl1, P.Ctrl2) then
        begin APart := P; AAutoC1 := C1W; AAutoC2 := C2W; Result := True; Exit; end;
      end
      else
      begin
        if TryHit(C1W, C2W) then
        begin APart := P; AAutoC1 := C1W; AAutoC2 := C2W; Result := True; Exit; end;
      end;
    end;

    // Product legs: Start = junction, End = species centre
    FanTotal := R.Products.Count;
    for i := 0 to FanTotal - 1 do
    begin
      P      := R.Products[i];
      StartW := R.JunctionPos;
      EndW   := P.Species.Center;
      ComputeAutoCtrlPts(StartW, EndW, i, FanTotal, False, C1W, C2W);
      if P.CtrlPtsSet then
      begin
        if TryHit(P.Ctrl1, P.Ctrl2) then
        begin APart := P; AAutoC1 := C1W; AAutoC2 := C2W; Result := True; Exit; end;
      end
      else
      begin
        if TryHit(C1W, C2W) then
        begin APart := P; AAutoC1 := C1W; AAutoC2 := C2W; Result := True; Exit; end;
      end;
    end;
  end;
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
  R          : TReaction;
  P          : TParticipant;
  JPos       : TPointF;
  JScr       : TPointF;
  BoundW     : TPointF;
  TipW       : TPointF;
  TipScr     : TPointF;
  DirW       : TPointF;
  ArrW       : TArrowheadVertices;
  ArrScr     : TArrowheadVertices;
  LinePaint  : ISkPaint;
  LineColor  : TAlphaColor;
  C1W, C2W   : TPointF;
  FanIdx     : Integer;
  FanTotal   : Integer;
  i          : Integer;
  Builder    : ISkPathBuilder;
  Path       : ISkPath;
  tClip      : Single;
  LA, LB, LC, LD : TPointF;   // left  sub-curve (product, junction→boundary)
  RA, RB, RC, RD : TPointF;   // right sub-curve (reactant, boundary→junction)
begin
  for R in FModel.Reactions do
  begin
    // Custom style takes priority; selection always overrides line color.
    if R.Style.HasCustomStyle then
      LineColor := R.Style.LineColor
    else
      LineColor := CLR_REACTION;

    var EffLineWidth := VIEW_LINE_WIDTH;
    if R.Style.HasCustomStyle and (R.Style.LineWidth > 0) then
      EffLineWidth := R.Style.LineWidth;
    if R.Selected then
      EffLineWidth := EffLineWidth * 1.5;

    LinePaint             := TSkPaint.Create;
    LinePaint.AntiAlias   := True;
    LinePaint.Color       := LineColor;
    LinePaint.Style       := TSkPaintStyle.Stroke;
    LinePaint.StrokeWidth := W2SLen(EffLineWidth);
    LinePaint.StrokeCap   := TSkStrokeCap.Round;

    // --- Linear UniUni: single straight line, no junction -----------------
    if R.IsLinear and (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    begin
      var Reactant := R.Reactants[0].Species;
      var Product  := R.Products[0].Species;
      DirW.X := Product.Center.X - Reactant.Center.X;
      DirW.Y := Product.Center.Y - Reactant.Center.Y;
      DirW   := NormalizeVec(DirW);
      BoundW := RectBoundaryIntersect(Reactant.Center, Reactant.HalfW,
                                      Reactant.HalfH, Product.Center);
      // Back the reactant start off the border by VIEW_REACTANT_GAP.
      var StartW : TPointF;
      StartW.X := BoundW.X + DirW.X * VIEW_REACTANT_GAP;
      StartW.Y := BoundW.Y + DirW.Y * VIEW_REACTANT_GAP;
      TipW   := ProductLineTip(Product.Center, Product.HalfW,
                                Product.HalfH, Reactant.Center, VIEW_PRODUCT_GAP);
      TipScr := W2S(TipW);
      ACanvas.DrawLine(W2S(StartW), TipScr, LinePaint);
      ArrW         := FilledArrowhead(TipW, DirW, VIEW_ARROW_LEN, VIEW_ARROW_HALF_BASE);
      ArrScr.Tip   := W2S(ArrW.Tip);
      ArrScr.Base1 := W2S(ArrW.Base1);
      ArrScr.Base2 := W2S(ArrW.Base2);
      DrawFilledTriangle(ACanvas, ArrScr, LineColor);
      Continue;
    end;

    JPos := EffectiveJunctionPos(R);
    JScr := W2S(JPos);

    // --- Bezier reaction --------------------------------------------------
    if R.IsBezier then
    begin
      // Reactant legs.
      // Conceptual curve: species.Centre (inside node) --> junction.
      // We clip it at the rectangle boundary and render only the exterior
      // portion, so the curve exits the node face tangent to the centre-
      // junction direction regardless of control point positions.
      FanTotal := R.Reactants.Count;
      for i := 0 to FanTotal - 1 do
      begin
        P := R.Reactants[i];
        // Conceptual endpoints: centre --> junction
        GetCtrlPts(P, P.Species.Center, JPos, i, FanTotal, True, C1W, C2W);
        // Find t where the curve exits the species rectangle
        tClip := BezierBoundaryT(P.Species.Center, C1W, C2W, JPos,
                                  P.Species.Center, P.Species.HalfW,
                                  P.Species.HalfH, True {inside at t=0});
        // Right sub-curve [tClip..1]: RA is on the boundary, RD = junction.
        // Shift the start forward by VIEW_BEZIER_REACTANT_GAP along the curve
        // tangent at RA (direction RB − RA) to leave a gap at the species border.
        BezierRightHalf(P.Species.Center, C1W, C2W, JPos, tClip,
                        RA, RB, RC, RD);
        var TangX := RB.X - RA.X;
        var TangY := RB.Y - RA.Y;
        var TangLen := Sqrt(TangX * TangX + TangY * TangY);
        var BezStartW : TPointF;
        if TangLen > 0.5 then
        begin
          BezStartW.X := RA.X + (TangX / TangLen) * VIEW_BEZIER_REACTANT_GAP;
          BezStartW.Y := RA.Y + (TangY / TangLen) * VIEW_BEZIER_REACTANT_GAP;
        end
        else
          BezStartW := RA;
        Builder := TSkPathBuilder.Create;
        Builder.MoveTo(W2S(BezStartW));
        Builder.CubicTo(W2S(RB), W2S(RC), JScr);
        Path := Builder.Detach;
        ACanvas.DrawPath(Path, LinePaint);
      end;

      // Product legs.
      // Conceptual curve: junction --> species.Centre (inside node).
      // Clip at rectangle boundary; arrowhead tangent follows the curve
      // at the crossing point, so it always "rotates about the centre".
      FanTotal := R.Products.Count;
      for i := 0 to FanTotal - 1 do
      begin
        P := R.Products[i];
        // Conceptual endpoints: junction --> centre
        GetCtrlPts(P, JPos, P.Species.Center, i, FanTotal, False, C1W, C2W);
        // Find t where the curve enters the species rectangle
        tClip := BezierBoundaryT(JPos, C1W, C2W, P.Species.Center,
                                  P.Species.Center, P.Species.HalfW,
                                  P.Species.HalfH, False {outside at t=0});
        // Left sub-curve [0..tClip]: LA = junction, LD is on the boundary.
        // The curve is redrawn below, shortened to TipW, so only compute the split.
        BezierLeftHalf(JPos, C1W, C2W, P.Species.Center, tClip,
                       LA, LB, LC, LD);

        // Arrowhead: tangent at the boundary crossing = (LD - LC) direction.
        // This naturally "rotates about the species centre" as ctrl pts move.
        // Back the tip off by VIEW_BEZIER_PRODUCT_GAP along that tangent so
        // the gap matches the straight/linear product-leg behaviour.
        DirW.X := LD.X - LC.X;
        DirW.Y := LD.Y - LC.Y;
        DirW   := NormalizeVec(DirW);
        TipW.X := LD.X - DirW.X * VIEW_BEZIER_PRODUCT_GAP;
        TipW.Y := LD.Y - DirW.Y * VIEW_BEZIER_PRODUCT_GAP;
        Builder := TSkPathBuilder.Create;
        Builder.MoveTo(JScr);
        Builder.CubicTo(W2S(LB), W2S(LC), W2S(TipW));
        Path := Builder.Detach;
        ACanvas.DrawPath(Path, LinePaint);
        ArrW         := FilledArrowhead(TipW, DirW, VIEW_ARROW_LEN, VIEW_ARROW_HALF_BASE);
        ArrScr.Tip   := W2S(ArrW.Tip);
        ArrScr.Base1 := W2S(ArrW.Base1);
        ArrScr.Base2 := W2S(ArrW.Base2);
        DrawFilledTriangle(ACanvas, ArrScr, LineColor);
      end;
      Continue;
    end;

    // --- Straight reaction ------------------------------------------------
    for P in R.Reactants do
    begin
      BoundW := RectBoundaryIntersect(P.Species.Center, P.Species.HalfW,
                                      P.Species.HalfH, JPos);
      // Direction from boundary toward junction; back start off the border.
      var RDirX := JPos.X - BoundW.X;
      var RDirY := JPos.Y - BoundW.Y;
      var RDirLen := Sqrt(RDirX * RDirX + RDirY * RDirY);
      var StraightStart : TPointF;
      if RDirLen > 0.5 then
      begin
        StraightStart.X := BoundW.X + (RDirX / RDirLen) * VIEW_REACTANT_GAP;
        StraightStart.Y := BoundW.Y + (RDirY / RDirLen) * VIEW_REACTANT_GAP;
      end
      else
        StraightStart := BoundW;
      ACanvas.DrawLine(W2S(StraightStart), JScr, LinePaint);
    end;

    for P in R.Products do
    begin
      TipW   := ProductLineTip(P.Species.Center, P.Species.HalfW,
                                P.Species.HalfH, JPos, VIEW_PRODUCT_GAP);
      TipScr := W2S(TipW);
      ACanvas.DrawLine(JScr, TipScr, LinePaint);
      DirW.X := P.Species.Center.X - JPos.X;
      DirW.Y := P.Species.Center.Y - JPos.Y;
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
    // --- Determine colors (custom style takes priority over palette) ---
    // Selection is indicated purely by the halo — no color overrides here.
    if S.Style.HasCustomStyle then
    begin
      if S.Style.FillColor   <> 0 then FillColor   := S.Style.FillColor;
      if S.Style.BorderColor <> 0 then BorderColor := S.Style.BorderColor;
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

    var EffBorderWidth := VIEW_BORDER_WIDTH;
    if S.Style.HasCustomStyle and (S.Style.BorderWidth > 0) then
      EffBorderWidth := S.Style.BorderWidth;

    BorderPaint             := TSkPaint.Create;
    BorderPaint.AntiAlias   := True;
    BorderPaint.Color       := BorderColor;
    BorderPaint.Style       := TSkPaintStyle.Stroke;
    BorderPaint.StrokeWidth := W2SLen(EffBorderWidth);
    if S.IsAlias and FShowAliasIndicator then
      BorderPaint.PathEffect := TSkPathEffect.MakeDash(Intervals, 0);
    if S.IsBoundary then BorderPaint.StrokeWidth := BorderPaint.StrokeWidth*2.4;
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, BorderPaint);

    var LabelColor := CLR_LABEL;
    if S.Style.HasCustomStyle and (S.Style.LabelColor <> 0) then
      LabelColor := S.Style.LabelColor;

    var EffFontSize := VIEW_FONT_SIZE;
    if S.Style.HasCustomStyle and (S.Style.FontSize > 0) then
      EffFontSize := S.Style.FontSize;

    DrawCenteredText(ACanvas, W2S(S.Center), S.Id,
                     W2SLen(EffFontSize), LabelColor);
  end;
end;

procedure TDiagramView.RenderSelectionHalos(const ACanvas: ISkCanvas);
// Draw a rounded-rectangle halo just outside each selected species node.
// This is the sole visual indicator of selection for species/compartments,
// so node fill and border colors are never touched by selection state.
var
  S         : TSpeciesNode;
  SR        : TRectF;
  CornerR   : Single;
  Outset    : Single;
  RingPaint : ISkPaint;
  LDashPattern: TArray<Single>;
begin
  Outset  := VIEW_SEL_RING_OUTSET;
  CornerR := W2SLen(VIEW_NODE_CORNER + Outset);

  RingPaint             := TSkPaint.Create;
  RingPaint.AntiAlias   := True;
  RingPaint.Style       := TSkPaintStyle.Stroke;
  RingPaint.StrokeWidth := W2SLen(VIEW_SEL_RING_WIDTH);
  RingPaint.Color       := CLR_SEL_RING;

  SetLength(LDashPattern, 2);
  LDashPattern[0] := 10;
  LDashPattern[1] := 5;
  RingPaint.PathEffect := TSkPathEffect.MakeDash(LDashPattern, 2);

  for S in FModel.Species do
  begin
    if not S.Selected then Continue;
    SR := TRectF.Create(
      W2S(TPointF.Create(S.Center.X - S.HalfW - Outset,
                         S.Center.Y - S.HalfH - Outset)),
      W2S(TPointF.Create(S.Center.X + S.HalfW + Outset,
                         S.Center.Y + S.HalfH + Outset)));
    ACanvas.DrawRoundRect(SR, CornerR, CornerR, RingPaint);
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

    // Resolve fill color once regardless of selection state.
    if R.Style.HasCustomStyle and (R.Style.JunctionColor <> 0) then
      FillColor := R.Style.JunctionColor
    else
      FillColor := CLR_JCT_FILL;

    if R.Selected then
    begin
      Radius      := W2SLen(VIEW_JUNCTION_RADIUS * 1.6);
      BorderColor := CLR_JCT_BORD_SEL;
    end
    else
    begin
      Radius      := W2SLen(VIEW_JUNCTION_RADIUS);
      BorderColor := CLR_JCT_BORDER;
    end;

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

procedure TDiagramView.RenderCtrlPtHandles(const ACanvas: ISkCanvas);
// Draw small circles at each Bézier control point for selected Bézier reactions,
// plus dashed lines from the handle to its respective endpoint (tangent arm).
// When a reaction has IsJunctionSmooth set, its inner (junction-side) handles
// are drawn in teal so the user can easily distinguish the coupled pair.
var
  R          : TReaction;
  P          : TParticipant;
  C1W, C2W   : TPointF;
  StartW     : TPointF;
  EndW       : TPointF;
  FanTotal   : Integer;
  i          : Integer;
  FillPaint  : ISkPaint;
  RingPaint  : ISkPaint;
  InnerPaint : ISkPaint;
  Radius     : Single;
  SmoothThis : Boolean;   // IsJunctionSmooth for the current reaction

  // AIsInner: True when this handle is the junction-side (inner) one.
  procedure DrawHandle(const CW: TPointF; const AnchorW: TPointF; AIsInner: Boolean);
  begin
    DrawDashedLine(ACanvas, W2S(AnchorW), W2S(CW), CLR_CTRL_LINE, 1.0);
    ACanvas.DrawCircle(W2S(CW), Radius, FillPaint);
    if AIsInner and SmoothThis then
      ACanvas.DrawCircle(W2S(CW), Radius, InnerPaint)
    else
      ACanvas.DrawCircle(W2S(CW), Radius, RingPaint);
  end;

begin
  Radius := W2SLen(VIEW_CTRL_RADIUS);

  FillPaint           := TSkPaint.Create;
  FillPaint.AntiAlias := True;
  FillPaint.Color     := CLR_CTRL_FILL;
  FillPaint.Style     := TSkPaintStyle.Fill;

  RingPaint             := TSkPaint.Create;
  RingPaint.AntiAlias   := True;
  RingPaint.Color       := CLR_CTRL_BORDER;
  RingPaint.Style       := TSkPaintStyle.Stroke;
  RingPaint.StrokeWidth := W2SLen(1.0);

  InnerPaint             := TSkPaint.Create;
  InnerPaint.AntiAlias   := True;
  InnerPaint.Color       := CLR_CTRL_INNER_SMOOTH;
  InnerPaint.Style       := TSkPaintStyle.Stroke;
  InnerPaint.StrokeWidth := W2SLen(1.5);

  for R in FModel.Reactions do
  begin
    if not (R.Selected and R.IsBezier) then Continue;

    SmoothThis := R.IsJunctionSmooth;
    var JPos   := R.JunctionPos;

    // Reactant handles: inner = Ctrl2 (nearest junction).
    FanTotal := R.Reactants.Count;
    for i := 0 to FanTotal - 1 do
    begin
      P      := R.Reactants[i];
      StartW := P.Species.Center;
      EndW   := JPos;
      GetCtrlPts(P, StartW, EndW, i, FanTotal, True, C1W, C2W);
      DrawHandle(C1W, StartW, False);  // Ctrl1 — outer (species side)
      DrawHandle(C2W, EndW,   True);   // Ctrl2 — inner (junction side)
    end;

    // Product handles: inner = Ctrl1 (nearest junction).
    FanTotal := R.Products.Count;
    for i := 0 to FanTotal - 1 do
    begin
      P      := R.Products[i];
      StartW := JPos;
      EndW   := P.Species.Center;
      GetCtrlPts(P, StartW, EndW, i, FanTotal, False, C1W, C2W);
      DrawHandle(C1W, StartW, True);   // Ctrl1 — inner (junction side)
      DrawHandle(C2W, EndW,   False);  // Ctrl2 — outer (species side)
    end;
  end;
end;

// ===========================================================================
//  Undo helpers
// ===========================================================================

function TDiagramView.TakeSnapshot: string;
var
  JObj : TJSONObject;
begin
  JObj := FModel.ToJSONObject;
  try
    Result := JObj.ToJSON;  // compact — no indentation needed for undo snapshots
  finally
    JObj.Free;
  end;
end;

// ---------------------------------------------------------------------------

function TDiagramView.MakeRestoreProc: TAfterRestoreProc;
begin
  // Capture FModel and self by reference so the lambda is self-contained.
  Result := procedure(ANextSpeciesNum: Integer)
  begin
    FNextSpeciesNum := ANextSpeciesNum;
    SyncSpeciesIdCounter;   // re-sync from model in case it disagrees
    FModel.ClearSelection;
  end;
end;

// ---------------------------------------------------------------------------

function TDiagramView.FindParticipantInfo(APart: TParticipant;
                                           out AReactionId  : string;
                                           out AIsReactant  : Boolean;
                                           out AIndex       : Integer): Boolean;
var
  R : TReaction;
  i : Integer;
begin
  Result     := False;
  AReactionId := '';
  AIsReactant := False;
  AIndex      := -1;
  for R in FModel.Reactions do
  begin
    for i := 0 to R.Reactants.Count - 1 do
      if R.Reactants[i] = APart then
      begin
        AReactionId := R.Id; AIsReactant := True; AIndex := i;
        Result := True; Exit;
      end;
    for i := 0 to R.Products.Count - 1 do
      if R.Products[i] = APart then
      begin
        AReactionId := R.Id; AIsReactant := False; AIndex := i;
        Result := True; Exit;
      end;
  end;
end;

// ---------------------------------------------------------------------------

function TDiagramView.MeasureTextWorldWidth(const AText: string): Single;
var
  Font : ISkFont;
begin
  // Create the font at VIEW_FONT_SIZE (world units).  Skia returns MeasureText
  // in the same unit as the font size, so the result is directly comparable
  // to S.Width which is also stored in world units.
  Font   := TSkFont.Create(nil, VIEW_FONT_SIZE);
  Result := Font.MeasureText(AText);
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.FitNodeToText(S: TSpeciesNode);
// Widen S so that its DisplayName fits inside the node with VIEW_NODE_TEXT_PAD
// on each side.  Shrinking is intentionally not done — the user may have set a
// deliberately wide node.  All alias nodes of the same primary are also resized
// so they stay visually consistent.
var
  Required : Single;
  Alias    : TSpeciesNode;
  Primary  : TSpeciesNode;
begin
  // Always operate on the primary so DisplayName is correct.
  if S.IsAlias then Primary := S.AliasOf else Primary := S;

  Required := MeasureTextWorldWidth(Primary.Id) + 2 * VIEW_NODE_TEXT_PAD;

  if Required > Primary.Width then
    Primary.Width := Required;

  // Resize aliases to match the primary's (possibly new) width.
  for Alias in FModel.Species do
    if Alias.IsAlias and (Alias.AliasOf = Primary) then
      if Required > Alias.Width then
        Alias.Width := Required;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.ClearTransientState;
begin
  FDraggedParticipant   := nil;
  FDraggedJunction      := nil;
  FDraggedCtrlNum       := 0;
  FDragCtrlPtPartIdx    := -1;
  FDragCtrlPtReaction   := nil;
end;

// ---------------------------------------------------------------------------

procedure TDiagramView.Undo;
begin
  ClearTransientState;
  FUndoManager.Undo;
end;

procedure TDiagramView.Redo;
begin
  ClearTransientState;
  FUndoManager.Redo;
end;

function TDiagramView.CanUndo: Boolean;
begin Result := FUndoManager.CanUndo; end;

function TDiagramView.CanRedo: Boolean;
begin Result := FUndoManager.CanRedo; end;

function TDiagramView.UndoDescription: string;
begin Result := FUndoManager.UndoDescription; end;

function TDiagramView.RedoDescription: string;
begin Result := FUndoManager.RedoDescription; end;

// ===========================================================================
//  Render — entry point
// ===========================================================================

procedure TDiagramView.Render(const ACanvas: ISkCanvas;
                               ACanvasW, ACanvasH: Single);
begin
  RenderBackground     (ACanvas, ACanvasW, ACanvasH);
  RenderReactions      (ACanvas);
  RenderSpeciesNodes   (ACanvas);
  RenderSelectionHalos (ACanvas);
  RenderJunctionHandles(ACanvas);
  RenderCtrlPtHandles  (ACanvas);   // on top of junction handles
  RenderPendingReaction(ACanvas);
  RenderRubberBand     (ACanvas);
end;

// ===========================================================================
//  Antimony import / export
// ===========================================================================

procedure TDiagramView.ImportAntimony(const ASource: string);
var
  SnapBefore : string;
  SnapNum    : Integer;
begin
  CancelCurrentAction;
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  TAntimonyBridge.ImportFromString(ASource, FModel);
  SyncSpeciesIdCounter;
  FModel.ClearSelection;
  FScrollOffset := TPointF.Create(30, 30);
  FUndoManager.Push(TSnapshotCmd.Create('Import Antimony', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
end;

function TDiagramView.ExportAntimony: string;
begin
  Result := TAntimonyBridge.ExportToString(FModel);
end;

procedure TDiagramView.AutoLayout(Iterations: Integer);
var
  SnapBefore : string;
  SnapNum    : Integer;
  R          : TReaction;
begin
  SnapBefore := TakeSnapshot;
  SnapNum    := FNextSpeciesNum;
  TAutoLayout.Run(FModel, Iterations);
  // Auto-layout moves species centres and junction positions but leaves stored
  // control points at their old absolute coordinates.  For any reaction that
  // uses smooth junctions, rematerialise the ctrl pts from the new positions
  // so the inner handles remain collinear through the (now-moved) junction.
  for R in FModel.Reactions do
    if R.IsBezier and R.IsJunctionSmooth then
      MaterialiseSmoothCtrlPts(R);
  FUndoManager.Push(TSnapshotCmd.Create('Auto layout', FModel,
    SnapBefore, TakeSnapshot, SnapNum, FNextSpeciesNum, FRestoreProc));
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
  FUndoManager.Clear;
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
  SyncSpeciesIdCounter;
  FModel.ClearSelection;
  SetModeSelect;
  FUndoManager.Clear;
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


procedure TDiagramView.ImportSBML(const ASource: string);
begin
end;

function TDiagramView.ExportSBML: string;
begin
  Result := TSBMLBridge.ExportToString(FModel);
end;


end.
