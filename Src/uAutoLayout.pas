unit uAutoLayout;

{
  uAutoLayout.pas
  ===============
  ForceAtlas2-style force-directed layout adapted for biochemical networks.

  Key differences from standard ForceAtlas2
  ------------------------------------------
  Reactions are hyperedges, not simple edges.  The junction point of each
  reaction is treated as a full layout node with its own mass and position.
  This keeps reaction lines tidy — the junction naturally sits between its
  participants rather than being dragged to an arbitrary midpoint.

  Forces
  ------
  Repulsion  (all node pairs)
    F = Kr * (mass_i * mass_j) / distance²  * direction

  Attraction  (each spring: species ↔ junction)
    F = Ka * distance  * direction

  Gravity
    F = Kg * mass * distance_from_centre

  Cooling schedule
  ----------------
  A global step-size (speed) starts at SpeedStart and is multiplied by
  SpeedDecay each iteration.

  Alias nodes
  -----------
  Alias nodes are excluded from the layout.

  Bézier control point pass  (TBezierCtrlPts)
  --------------------------------------------
  After the force-directed positions have settled, TBezierCtrlPts.Compute
  calculates Ctrl1/Ctrl2 for every reaction whose IsBezier flag is set.
  It is called automatically at the end of TAutoLayout.Run and can also
  be called stand-alone after a manual node move.

  Convention for stored control points
  -------------------------------------
  This exactly matches ComputeAutoCtrlPts / SaveDragPositions / MaterialiseSmoothCtrlPts:

    Reactant leg  (conceptual curve: Species.Center → JunctionPos)
      Ctrl1 = outer handle, species-side  (≈ 35% from species toward junction)
      Ctrl2 = inner handle, junction-side (Deckard/Bergmann substrate guide)

    Product leg   (conceptual curve: JunctionPos → Species.Center)
      Ctrl1 = inner handle, junction-side (Deckard/Bergmann product guide)
      Ctrl2 = outer handle, species-side  (≈ 35% from species toward junction)

  The renderer (RenderReactions) already draws the full conceptual curve from
  Species.Center to JunctionPos and clips it dynamically at the species
  rectangle boundary using BezierBoundaryT + BezierRightHalf/BezierLeftHalf.
  No pre-computed boundary point is needed or stored in the model.

  Interaction with TDiagramView.AutoLayout
  ----------------------------------------
  TAutoLayout.Run ends with TBezierCtrlPts.Compute, which freshly computes
  ctrl pts for all IsBezier reactions, overwriting any stale pre-layout values.
  TDiagramView.AutoLayout then calls MaterialiseSmoothCtrlPts for
  IsJunctionSmooth reactions, overwriting those ctrl pts with proper collinear
  handles.  The two passes do not conflict:
    non-smooth Bézier → gets Deckard/Bergmann ctrl pts from TBezierCtrlPts
    smooth Bézier     → gets collinear ctrl pts from MaterialiseSmoothCtrlPts

  Required change in TDiagramView.AutoLayout (uDiagramView.pas)
  --------------------------------------------------------------
  Update the comment before the MaterialiseSmoothCtrlPts loop to reflect that
  non-smooth Bézier ctrl pts are now freshly computed by TAutoLayout.Run,
  so only the smooth-junction rematerialisation still needs to happen here:

    TAutoLayout.Run(FModel, Iterations);
    // TAutoLayout.Run freshly computes Bézier ctrl pts for all non-smooth
    // reactions.  Smooth reactions need MaterialiseSmoothCtrlPts on top to
    // enforce collinear inner handles through the (now-moved) junction.
    for R in FModel.Reactions do
      if R.IsBezier and R.IsJunctionSmooth then
        MaterialiseSmoothCtrlPts(R);

  No other changes to uDiagramView.pas or uBioModel.pas are required.

  Usage
  -----
    TAutoLayout.Run(FModel);           // full layout + Bézier ctrl pts
    TBezierCtrlPts.Compute(FModel);    // ctrl pts only, after a manual drag
}

interface

uses
  System.Types,
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  uBioModel;

type
  TAutoLayout = class
  public
    // Run force-directed layout on AModel, then compute Bézier control points
    // for every reaction whose IsBezier flag is True.
    class procedure Run(AModel     : TBioModel;
                        Iterations : Integer = 200;
                        Kr         : Single  = 8000.0;
                        Ka         : Single  = 0.02;
                        Kg         : Single  = 0.02;
                        SpeedStart : Single  = 4.0;
                        SpeedDecay : Single  = 0.98;
                        ComputeBezierCtrlPts : Boolean = True);
  end;

  // ---------------------------------------------------------------------------
  //  TBezierCtrlPts
  //  Post-layout pass: computes Ctrl1/Ctrl2 for all IsBezier reactions.
  //  Based on the Deckard/Bergmann AutoLayout algorithm (2006).
  //  Safe to call stand-alone after any node or junction move.
  // ---------------------------------------------------------------------------
  TBezierCtrlPts = class
  public
    class procedure Compute(AModel: TBioModel);
  end;

implementation

// ===========================================================================
//  File-private geometry helpers
// ===========================================================================

const
  MIN_DIST = 1.0;

function SafeDist(const A, B: TPointF): Single; inline;
begin
  Result := Max(MIN_DIST, Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y)));
end;

function GeoDistance(const A, B: TPointF): Single; inline;
begin
  Result := Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y));
end;

// ---------------------------------------------------------------------------
//  WalkAlongLine
//  Returns a point reached by starting at First, aiming toward Second,
//  rotating the direction by Degrees (counter-clockwise), and travelling
//  the original distance plus Distance pixels.
//
//  When RelativeDist = True, Distance is a fraction of the original length
//  (1.0 = go twice as far, placing the result on the far side of Second from
//  First at the same distance — this is how product inner handles are reflected
//  through the junction).
//
//  Translated from CalcNew2ndPos (Deckard/Bergmann, geometrycalc.cs).
// ---------------------------------------------------------------------------
function WalkAlongLine(const First, Second : TPointF;
                       Degrees, Distance   : Double;
                       RelativeDist        : Boolean): TPointF;
var
  O, A, H, HNew : Double;
  BaseAngle      : Double;
  ONew, ANew     : Double;
begin
  O := Second.Y - First.Y;
  A := Second.X - First.X;
  H := Sqrt(A * A + O * O);

  if RelativeDist then
    HNew := H + H * Distance
  else
    HNew := H + Distance;

  if A = 0 then A := 1e-10;   // guard vertical lines

  BaseAngle := ArcTan(O / A);
  ONew := HNew * Sin(BaseAngle + DegToRad(Degrees));
  ANew := HNew * Cos(BaseAngle + DegToRad(Degrees));

  // ArcTan returns values in (−π/2, +π/2].  When Second is to the left of
  // First we must flip both components to land in the correct half-plane.
  if Second.X >= First.X then
  begin
    Result.X := First.X + ANew;
    Result.Y := First.Y + ONew;
  end
  else
  begin
    Result.X := First.X - ANew;
    Result.Y := First.Y - ONew;
  end;
end;


// ===========================================================================
//  TAutoLayout.Run
// ===========================================================================

type
  TLayoutNode = record
    Pos    : TPointF;
    Force  : TPointF;
    Mass   : Single;
    IsFree : Boolean;
  end;

class procedure TAutoLayout.Run(AModel     : TBioModel;
                                Iterations : Integer;
                                Kr, Ka, Kg : Single;
                                SpeedStart : Single;
                                SpeedDecay : Single;
                                ComputeBezierCtrlPts : Boolean);
var
  Nodes    : array of TLayoutNode;
  NS, NR   : Integer;
  Total    : Integer;
  i, j     : Integer;
  Iter     : Integer;
  Speed    : Single;
  S        : TSpeciesNode;
  R        : TReaction;
  P        : TParticipant;
  SI, JI   : Integer;
  DX, DY   : Single;
  Dist     : Single;
  Mag      : Single;
  CentreX,
  CentreY  : Single;
  SpeciesIdx : TDictionary<string, Integer>;
  AliasMap   : TDictionary<Integer, Integer>;
  PrimaryIdx : Integer;
begin
  NS    := AModel.Species.Count;
  NR    := AModel.Reactions.Count;
  Total := NS + NR;
  if Total = 0 then Exit;

  SetLength(Nodes, Total);

  SpeciesIdx := TDictionary<string, Integer>.Create;
  AliasMap   := TDictionary<Integer, Integer>.Create;
  try
    for i := 0 to NS - 1 do
    begin
      S               := AModel.Species[i];
      Nodes[i].Pos    := S.Center;
      Nodes[i].Force  := TPointF.Create(0, 0);
      Nodes[i].Mass   := 1.0;
      Nodes[i].IsFree := not S.Locked;
      SpeciesIdx.AddOrSetValue(S.Id, i);
    end;

    for i := 0 to NS - 1 do
    begin
      S := AModel.Species[i];
      if S.IsAlias then
        if SpeciesIdx.TryGetValue(S.AliasOf.Id, PrimaryIdx) then
           begin
              if SpeciesIdx.TryGetValue(S.AliasOf.Id, PrimaryIdx) then
                AliasMap.AddOrSetValue(i, PrimaryIdx);
              // Alias inherits locked state from its primary
              if S.AliasOf.Locked then
                Nodes[i].IsFree := False;
            end;
    end;

    for i := 0 to NR - 1 do
    begin
      JI                  := NS + i;
      R                   := AModel.Reactions[i];
      Nodes[JI].Pos       := R.JunctionPos;
      Nodes[JI].Force     := TPointF.Create(0, 0);
      Nodes[JI].Mass      := 1.0 + R.Reactants.Count + R.Products.Count;
      Nodes[JI].IsFree    := True;
    end;

    for i := 0 to NR - 1 do
    begin
      R := AModel.Reactions[i];
      for P in R.Reactants do
        if SpeciesIdx.TryGetValue(P.Species.Id, SI) then
          Nodes[SI].Mass := Nodes[SI].Mass + 1.0;
      for P in R.Products do
        if SpeciesIdx.TryGetValue(P.Species.Id, SI) then
          Nodes[SI].Mass := Nodes[SI].Mass + 1.0;
    end;

    CentreX := 0; CentreY := 0;
    for i := 0 to Total - 1 do
    begin
      CentreX := CentreX + Nodes[i].Pos.X;
      CentreY := CentreY + Nodes[i].Pos.Y;
    end;
    CentreX := CentreX / Total;
    CentreY := CentreY / Total;

    // Auto-scale SpeedStart from the initial bounding box diagonal.
    // Targets roughly 5% of the diagonal as the opening step, which gives
    // enough travel budget to converge from a fully randomized layout while
    // still settling cleanly on a tight pre-laid network.
    var BoxMinX, BoxMaxX, BoxMinY, BoxMaxY : Single;
    BoxMinX :=  1e9; BoxMaxX := -1e9;
    BoxMinY :=  1e9; BoxMaxY := -1e9;
    for i := 0 to Total - 1 do
    begin
      BoxMinX := Min(BoxMinX, Nodes[i].Pos.X);
      BoxMaxX := Max(BoxMaxX, Nodes[i].Pos.X);
      BoxMinY := Min(BoxMinY, Nodes[i].Pos.Y);
      BoxMaxY := Max(BoxMaxY, Nodes[i].Pos.Y);
    end;
    var Diagonal := Sqrt(Sqr(BoxMaxX - BoxMinX) + Sqr(BoxMaxY - BoxMinY));
    Speed := Max(SpeedStart, Diagonal * 0.05);

    for Iter := 1 to Iterations do
    begin
      // Reset forces
      for i := 0 to Total - 1 do
        Nodes[i].Force := TPointF.Create(0, 0);

      // Repulsion: all pairs O(n²)
      for i := 0 to Total - 2 do
      begin
        if not Nodes[i].IsFree then Continue;
        for j := i + 1 to Total - 1 do
        begin
          DX   := Nodes[i].Pos.X - Nodes[j].Pos.X;
          DY   := Nodes[i].Pos.Y - Nodes[j].Pos.Y;
          Dist := Max(MIN_DIST, Sqrt(DX * DX + DY * DY));
          Mag  := Kr * Nodes[i].Mass * Nodes[j].Mass / (Dist * Dist);
          DX   := DX / Dist;
          DY   := DY / Dist;
          Nodes[i].Force.X := Nodes[i].Force.X + Mag * DX;
          Nodes[i].Force.Y := Nodes[i].Force.Y + Mag * DY;
          if Nodes[j].IsFree then
          begin
            Nodes[j].Force.X := Nodes[j].Force.X - Mag * DX;
            Nodes[j].Force.Y := Nodes[j].Force.Y - Mag * DY;
          end;
        end;
      end;

      // Attraction: species ↔ junction springs
      for i := 0 to NR - 1 do
      begin
        JI := NS + i;
        R  := AModel.Reactions[i];
        for P in R.Reactants do
        begin
          if not SpeciesIdx.TryGetValue(P.Species.Id, SI) then Continue;
          DX   := Nodes[JI].Pos.X - Nodes[SI].Pos.X;
          DY   := Nodes[JI].Pos.Y - Nodes[SI].Pos.Y;
          Dist := Max(MIN_DIST, Sqrt(DX * DX + DY * DY));
          Mag  := Ka * Dist;
          DX   := DX / Dist;
          DY   := DY / Dist;
          if Nodes[SI].IsFree then
          begin
            Nodes[SI].Force.X := Nodes[SI].Force.X + Mag * DX;
            Nodes[SI].Force.Y := Nodes[SI].Force.Y + Mag * DY;
          end;
          Nodes[JI].Force.X := Nodes[JI].Force.X - Mag * DX;
          Nodes[JI].Force.Y := Nodes[JI].Force.Y - Mag * DY;
        end;
        for P in R.Products do
        begin
          if not SpeciesIdx.TryGetValue(P.Species.Id, SI) then Continue;
          DX   := Nodes[JI].Pos.X - Nodes[SI].Pos.X;
          DY   := Nodes[JI].Pos.Y - Nodes[SI].Pos.Y;
          Dist := Max(MIN_DIST, Sqrt(DX * DX + DY * DY));
          Mag  := Ka * Dist;
          DX   := DX / Dist;
          DY   := DY / Dist;
          if Nodes[SI].IsFree then
          begin
            Nodes[SI].Force.X := Nodes[SI].Force.X + Mag * DX;
            Nodes[SI].Force.Y := Nodes[SI].Force.Y + Mag * DY;
          end;
          Nodes[JI].Force.X := Nodes[JI].Force.X - Mag * DX;
          Nodes[JI].Force.Y := Nodes[JI].Force.Y - Mag * DY;
        end;
      end;

      // Gravity: pull toward canvas centre
      for i := 0 to Total - 1 do
      begin
        if not Nodes[i].IsFree then Continue;
        DX := CentreX - Nodes[i].Pos.X;
        DY := CentreY - Nodes[i].Pos.Y;
        Nodes[i].Force.X := Nodes[i].Force.X + Kg * Nodes[i].Mass * DX;
        Nodes[i].Force.Y := Nodes[i].Force.Y + Kg * Nodes[i].Mass * DY;
      end;

      // Apply forces, clamped to Speed to prevent explosions
      for i := 0 to Total - 1 do
      begin
        if not Nodes[i].IsFree then Continue;
        DX   := Nodes[i].Force.X;
        DY   := Nodes[i].Force.Y;
        Dist := Sqrt(DX * DX + DY * DY);
        if Dist > Speed then
        begin
          DX := DX / Dist * Speed;
          DY := DY / Dist * Speed;
        end;
        Nodes[i].Pos.X := Nodes[i].Pos.X + DX;
        Nodes[i].Pos.Y := Nodes[i].Pos.Y + DY;
      end;

      // Alias tracking: each alias copies the displacement of its primary
      for var Pair in AliasMap do
      begin
        var AliasI   := Pair.Key;
        var PrimaryI := Pair.Value;
        if not Nodes[AliasI].IsFree then Continue;   // <<< add this guard
        var DispX := Nodes[PrimaryI].Pos.X - AModel.Species[PrimaryI].Center.X;
        var DispY := Nodes[PrimaryI].Pos.Y - AModel.Species[PrimaryI].Center.Y;
        Nodes[AliasI].Pos.X := AModel.Species[AliasI].Center.X + DispX;
        Nodes[AliasI].Pos.Y := AModel.Species[AliasI].Center.Y + DispY;
      end;

      Speed := Speed * SpeedDecay;
    end;

    // Recentre: translate so the centroid returns to its original position.
    var NewCX : Single := 0;
    var NewCY : Single := 0;
    for i := 0 to Total - 1 do
    begin
      NewCX := NewCX + Nodes[i].Pos.X;
      NewCY := NewCY + Nodes[i].Pos.Y;
    end;
    NewCX := NewCX / Total;
    NewCY := NewCY / Total;
    var ShiftX := CentreX - NewCX;
    var ShiftY := CentreY - NewCY;
    for i := 0 to Total - 1 do
    begin
      Nodes[i].Pos.X := Nodes[i].Pos.X + ShiftX;
      Nodes[i].Pos.Y := Nodes[i].Pos.Y + ShiftY;
    end;

    // Write positions back into the model.
    for i := 0 to NS - 1 do
      AModel.Species[i].Center := Nodes[i].Pos;
    for i := 0 to NR - 1 do
      AModel.Reactions[i].JunctionPos := Nodes[NS + i].Pos;

  finally
    AliasMap.Free;
    SpeciesIdx.Free;
  end;

  // -----------------------------------------------------------------------
  //  Bézier control point pass.
  //  Freshly computes Ctrl1/Ctrl2 for all IsBezier reactions now that
  //  positions are final.  Overwrites any stale pre-layout ctrl pts.
  //  TDiagramView.AutoLayout subsequently calls MaterialiseSmoothCtrlPts
  //  for IsJunctionSmooth reactions, replacing these with collinear handles.
  // -----------------------------------------------------------------------
  if ComputeBezierCtrlPts then
    TBezierCtrlPts.Compute(AModel);

  // -----------------------------------------------------------------------
  //  Final recentre — done AFTER TBezierCtrlPts.Compute so that junction
  //  repositioning is included in the centroid calculation.  Without this,
  //  each repeated layout call drifts because the post-Compute centroid
  //  differs from the pre-simulation centroid we saved in CentreX/CentreY.
  //  Ctrl pts are shifted too since they are stored in world coordinates.
  // -----------------------------------------------------------------------
  var FinalCX : Single := 0;
  var FinalCY : Single := 0;
  for i := 0 to NS - 1 do
  begin
    FinalCX := FinalCX + AModel.Species[i].Center.X;
    FinalCY := FinalCY + AModel.Species[i].Center.Y;
  end;
  for i := 0 to NR - 1 do
  begin
    FinalCX := FinalCX + AModel.Reactions[i].JunctionPos.X;
    FinalCY := FinalCY + AModel.Reactions[i].JunctionPos.Y;
  end;
  FinalCX := FinalCX / Total;
  FinalCY := FinalCY / Total;

  var Shift2X := CentreX - FinalCX;
  var Shift2Y := CentreY - FinalCY;

  if (Abs(Shift2X) > 0.01) or (Abs(Shift2Y) > 0.01) then
  begin
    for i := 0 to NS - 1 do
      AModel.Species[i].Center := TPointF.Create(
        AModel.Species[i].Center.X + Shift2X,
        AModel.Species[i].Center.Y + Shift2Y);

    for i := 0 to NR - 1 do
    begin
      AModel.Reactions[i].JunctionPos := TPointF.Create(
        AModel.Reactions[i].JunctionPos.X + Shift2X,
        AModel.Reactions[i].JunctionPos.Y + Shift2Y);

      // Shift stored ctrl pts — they are absolute world coordinates.
      if AModel.Reactions[i].IsBezier then
        for P in AModel.Reactions[i].Reactants do
          if P.CtrlPtsSet then
          begin
            P.Ctrl1 := TPointF.Create(P.Ctrl1.X + Shift2X, P.Ctrl1.Y + Shift2Y);
            P.Ctrl2 := TPointF.Create(P.Ctrl2.X + Shift2X, P.Ctrl2.Y + Shift2Y);
          end;
      if AModel.Reactions[i].IsBezier then
        for P in AModel.Reactions[i].Products do
          if P.CtrlPtsSet then
          begin
            P.Ctrl1 := TPointF.Create(P.Ctrl1.X + Shift2X, P.Ctrl1.Y + Shift2Y);
            P.Ctrl2 := TPointF.Create(P.Ctrl2.X + Shift2X, P.Ctrl2.Y + Shift2Y);
          end;
    end;
  end;
end;


// ===========================================================================
//  TBezierCtrlPts.Compute
//  Post-layout Bézier control point computation.
//
//  Derived from CalcCtrlPoints (Deckard/Bergmann, geometrycalc.cs, 2006).
//
//  The algorithm's key insight is the "substrate guide" (CentreCtrl):
//  the weighted centroid of (all reactant centres + junction).  Using this
//  as the junction-side inner handle biases the curve toward the reactant
//  cluster.  Reflecting CentreCtrl through the junction places product
//  inner handles on the opposite side — exactly the layout you want for a
//  biochemical network diagram.
//
//  Ctrl1/Ctrl2 stored convention (must match ComputeAutoCtrlPts,
//  SaveDragPositions, and MaterialiseSmoothCtrlPts in uDiagramView.pas):
//
//    Reactant  (conceptual curve P0=Species.Center → P3=JunctionPos)
//      Ctrl1 = outer/species-side  = CTRL_FRAC along leg from species
//      Ctrl2 = inner/junction-side = CentreCtrl
//
//    Product   (conceptual curve P0=JunctionPos → P3=Species.Center)
//      Ctrl1 = inner/junction-side = CentreCtrl reflected through junction
//      Ctrl2 = outer/species-side  = CTRL_FRAC along leg from species
// ===========================================================================

class procedure TBezierCtrlPts.Compute(AModel: TBioModel);
const
  // 35% of leg length for outer (species-side) ctrl pt placement.
  // Matches CTRL_DIST_FRAC in ComputeAutoCtrlPts and CTRL_FRAC in
  // MaterialiseSmoothCtrlPts so all code paths give consistent tangent exits.
  CTRL_FRAC = 0.35;

  // -------------------------------------------------------------------------
  procedure ComputeForReaction(R: TReaction);
  var
    CentreCtrl   : TPointF;
    nReactants   : Integer;
    IsLooped     : Boolean;
    LoopedPt     : TPointF;
    UniUniDist   : Double;
    ReactCenter,
    ProdCenter   : TPointF;
    P, Q         : TParticipant;
    Pi, Pj       : TParticipant;
    ii, jj       : Integer;
    LegX, LegY   : Single;
    SumRX, SumRY, SumPX, SumPY : Single;
    CentR, CentP : TPointF;
  begin
    // --- Reposition junction to the midpoint between reactant and product
    //     centroids.  The force layout places junctions by mass-spring forces
    //     which don't guarantee they end up on the reactant→product axis.
    //     A junction sitting to one side always produces a bulging curve
    //     regardless of control point placement.
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

    R.JunctionPos := TPointF.Create((CentR.X + CentP.X) * 0.5,
                                     (CentR.Y + CentP.Y) * 0.5);
    // ------------------------------------------------------------------
    //  Step 1.  Substrate guide (CentreCtrl)
    //  Centroid of (all reactant centres + junction).
    //  Points in the direction from which reactants arrive at the junction.
    // ------------------------------------------------------------------
    CentreCtrl := TPointF.Zero;
    nReactants := 0;
    IsLooped   := False;
    LoopedPt   := TPointF.Zero;

    for P in R.Reactants do
    begin
      CentreCtrl.X := CentreCtrl.X + P.Species.Center.X;
      CentreCtrl.Y := CentreCtrl.Y + P.Species.Center.Y;
      Inc(nReactants);
    end;
    CentreCtrl.X := (CentreCtrl.X + R.JunctionPos.X) / (nReactants + 1);
    CentreCtrl.Y := (CentreCtrl.Y + R.JunctionPos.Y) / (nReactants + 1);

    // ------------------------------------------------------------------
    //  Step 2.  Self-loop detection.
    //  When the same species appears as both reactant and product the two
    //  legs would coincide if laid straight.  Rotate CentreCtrl 90° around
    //  the junction to break the degeneracy.
    //  (The X/Y index swap in the intermediate assignment is the compact
    //  90° rotation used in the original C# source.)
    // ------------------------------------------------------------------
    for P in R.Reactants do
      for Q in R.Products do
        if P.Species = Q.Species then
        begin
          IsLooped := True;
          LoopedPt := P.Species.Center;
        end;

    if IsLooped then
    begin
      CentreCtrl.Y := R.JunctionPos.Y + (R.JunctionPos.Y - LoopedPt.X);
      CentreCtrl.X := R.JunctionPos.X + (R.JunctionPos.X - LoopedPt.Y);
      CentreCtrl   := WalkAlongLine(LoopedPt, R.JunctionPos, 0, -25, False);
      CentreCtrl   := WalkAlongLine(R.JunctionPos, CentreCtrl, -90, 0, False);
    end;

    // ------------------------------------------------------------------
    //  Step 3.  Uni-uni correction (exactly 1 reactant + 1 product).
    //  Align CentreCtrl along the reactant→product axis so the resulting
    //  curve forms a clean arc between the two species rather than a
    //  diagonal tangle.
    // ------------------------------------------------------------------
    if (R.Reactants.Count = 1) and (R.Products.Count = 1) then
    begin
      UniUniDist  := -GeoDistance(R.JunctionPos, CentreCtrl);
      ReactCenter := R.Reactants[0].Species.Center;
      ProdCenter  := R.Products[0].Species.Center;
      CentreCtrl.X := R.JunctionPos.X + (ReactCenter.X - ProdCenter.X);
      CentreCtrl.Y := R.JunctionPos.Y + (ReactCenter.Y - ProdCenter.Y);
      CentreCtrl   := WalkAlongLine(CentreCtrl, R.JunctionPos, 0, UniUniDist, False);
    end;

    // ------------------------------------------------------------------
    //  Step 4.  Pull CentreCtrl 25 px back from the junction so inner
    //  handles don't sit right on top of the junction marker.
    // ------------------------------------------------------------------
    CentreCtrl := WalkAlongLine(CentreCtrl, R.JunctionPos, 0, -25, False);

    // ------------------------------------------------------------------
    //  Step 5.  Reactant legs.
    //  Conceptual curve: Species.Center (P0) → JunctionPos (P3).
    //
    //    Ctrl2 (inner, junction-side) = CentreCtrl
    //      Pulls the curve toward the reactant cluster.
    //
    //    Ctrl1 (outer, species-side) = 35% along leg from species centre
    //      Identical to the auto ctrl pt convention in ComputeAutoCtrlPts,
    //      giving a tangent exit from the species node face.
    // ------------------------------------------------------------------
    for P in R.Reactants do
    begin
      P.Ctrl2 := CentreCtrl;

      LegX    := R.JunctionPos.X - P.Species.Center.X;
      LegY    := R.JunctionPos.Y - P.Species.Center.Y;
      P.Ctrl1 := TPointF.Create(P.Species.Center.X + LegX * CTRL_FRAC,
                                 P.Species.Center.Y + LegY * CTRL_FRAC);
      P.CtrlPtsSet := True;
    end;

    // ------------------------------------------------------------------
    //  Step 6.  Product legs.
    //  Conceptual curve: JunctionPos (P0) → Species.Center (P3).
    //
    //    Ctrl1 (inner, junction-side) = CentreCtrl reflected through junction.
    //      WalkAlongLine with RelativeDist=True, Distance=1.0 doubles the
    //      First→Second length, placing the result on the far side of
    //      JunctionPos from CentreCtrl at the same distance.  This puts
    //      product handles opposite the reactants — the natural biochemical
    //      layout where substrates enter from one side and products leave
    //      from the other.
    //
    //    Ctrl2 (outer, species-side) = 35% along leg from species centre.
    //      Same formula as reactant Ctrl1; both outer handles use the same
    //      35%-from-species convention for consistent tangent entry/exit.
    // ------------------------------------------------------------------
    for P in R.Products do
    begin
      P.Ctrl1 := WalkAlongLine(CentreCtrl, R.JunctionPos, 0, 1.0, True);

      LegX    := R.JunctionPos.X - P.Species.Center.X;
      LegY    := R.JunctionPos.Y - P.Species.Center.Y;
      P.Ctrl2 := TPointF.Create(P.Species.Center.X + LegX * CTRL_FRAC,
                                 P.Species.Center.Y + LegY * CTRL_FRAC);
      P.CtrlPtsSet := True;
    end;

    // ------------------------------------------------------------------
    //  Step 7.  Duplicate-species fan-out.
    //  Two reactant legs (or two product legs) to the same species would
    //  completely overlap.  Fan their outer handles ±20° so they separate.
    //  Only the outer handle is moved: Ctrl1 for reactants, Ctrl2 for
    //  products.  Inner handles and junction geometry are unaffected.
    // ------------------------------------------------------------------
    for ii := 0 to R.Reactants.Count - 1 do
    begin
      Pi := R.Reactants[ii];
      for jj := ii + 1 to R.Reactants.Count - 1 do
      begin
        Pj := R.Reactants[jj];
        if Pi.Species = Pj.Species then
        begin
          Pi.Ctrl1 := WalkAlongLine(Pi.Species.Center, Pi.Ctrl1,  20, 10, False);
          Pj.Ctrl1 := WalkAlongLine(Pj.Species.Center, Pj.Ctrl1, -20, 10, False);
        end;
      end;
    end;

    for ii := 0 to R.Products.Count - 1 do
    begin
      Pi := R.Products[ii];
      for jj := ii + 1 to R.Products.Count - 1 do
      begin
        Pj := R.Products[jj];
        if Pi.Species = Pj.Species then
        begin
          Pi.Ctrl2 := WalkAlongLine(Pi.Species.Center, Pi.Ctrl2,  20, 10, False);
          Pj.Ctrl2 := WalkAlongLine(Pj.Species.Center, Pj.Ctrl2, -20, 10, False);
        end;
      end;
    end;
  end; // ComputeForReaction

var
  R : TReaction;
begin
  for R in AModel.Reactions do
    if R.IsBezier then
      ComputeForReaction(R);
end;


end.
