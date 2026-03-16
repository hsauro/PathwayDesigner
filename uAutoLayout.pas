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
    Pushes every node away from every other node.  Mass of a species node
    is 1 + its degree (number of reaction legs it participates in).  Mass
    of a junction node is 1 + number of participants.

  Attraction  (each spring: species ↔ junction)
    F = Ka * distance  * direction
    Pulls each species toward the junction of every reaction it belongs to,
    and the junction toward each of its species.

  Gravity
    F = Kg * mass * distance_from_centre
    Weak pull toward the canvas centre to prevent the network drifting or
    exploding.  Applied per-node proportional to its mass.

  Cooling schedule
  ----------------
  A global step-size (speed) starts at SpeedStart and is multiplied by
  SpeedDecay each iteration.  This replaces the full ForceAtlas2 adaptive
  swing/traction mechanism.  Simple and works well for small-medium networks.

  Alias nodes
  -----------
  Alias nodes are excluded from the layout — they have visually independent
  positions that the user places deliberately.

  Usage
  -----
    TAutoLayout.Run(FModel);                       // defaults
    TAutoLayout.Run(FModel, 300, 2.0, 0.5, 0.02); // custom
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
    // Run force-directed layout on AModel.
    //
    //   Iterations  — number of simulation steps (100–500 typical)
    //   Kr          — repulsion coefficient       (default 800000)
    //   Ka          — attraction coefficient      (default 0.02)
    //   Kg          — gravity coefficient         (default 0.02)
    //   SpeedStart  — initial step size           (default 4.0)
    //   SpeedDecay  — step multiplier per iter    (default 0.98)
    //
    // Equilibrium distance between two unit-mass nodes:
    //   dist = (Kr / Ka) ^ (1/3)
    // With the defaults above: (800000 / 0.02)^(1/3) = 40000000^(1/3) ≈ 342 px
    // Increase Kr or decrease Ka to spread nodes further apart.
    // Decrease Kr or increase Ka to pull them closer together.
    class procedure Run(AModel     : TBioModel;
                        Iterations : Integer = 200;
                        Kr         : Single  = 8000.0;
                        Ka         : Single  = 0.02;
                        Kg         : Single  = 0.02;
                        SpeedStart : Single  = 4.0;
                        SpeedDecay : Single  = 0.98);
  end;

implementation

// ---------------------------------------------------------------------------
//  Internal node record used during simulation
// ---------------------------------------------------------------------------
type
  TLayoutNode = record
    Pos    : TPointF;   // current position (world)
    Force  : TPointF;   // accumulated force this iteration
    Mass   : Single;    // used in repulsion and gravity
    IsFree : Boolean;   // False = externally pinned node (reserved for future use)
  end;

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

const
  MIN_DIST = 1.0;   // prevents division by zero

function SafeDist(const A, B: TPointF): Single; inline;
begin
  Result := Max(MIN_DIST, Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y)));
end;

// ===========================================================================
//  TAutoLayout.Run
// ===========================================================================

class procedure TAutoLayout.Run(AModel     : TBioModel;
                                Iterations : Integer;
                                Kr, Ka, Kg : Single;
                                SpeedStart : Single;
                                SpeedDecay : Single);
var
  // ---- layout node arrays ------------------------------------------------
  //  Indices 0 .. NS-1   → species nodes  (parallel to AModel.Species)
  //  Indices NS .. NS+NR-1 → junction nodes (parallel to AModel.Reactions)
  Nodes    : array of TLayoutNode;
  NS, NR   : Integer;   // species count, reaction count
  Total    : Integer;   // NS + NR

  i, j     : Integer;
  Iter     : Integer;
  Speed    : Single;
  S        : TSpeciesNode;
  R        : TReaction;
  P        : TParticipant;
  SI, JI   : Integer;   // species index, junction index
  DX, DY   : Single;
  Dist     : Single;
  Mag      : Single;
  CentreX,
  CentreY  : Single;

  // Map species ID → node index for O(1) lookup during spring application
  SpeciesIdx : TDictionary<string, Integer>;
  // Map alias node index → primary node index for tracking
  AliasMap   : TDictionary<Integer, Integer>;
  PrimaryIdx : Integer;

begin
  NS := AModel.Species.Count;
  NR := AModel.Reactions.Count;
  Total := NS + NR;
  if Total = 0 then Exit;

  SetLength(Nodes, Total);

  // -----------------------------------------------------------------------
  //  1. Initialise node array from current model positions
  // -----------------------------------------------------------------------
  SpeciesIdx := TDictionary<string, Integer>.Create;
  AliasMap   := TDictionary<Integer, Integer>.Create;
  try
    for i := 0 to NS - 1 do
    begin
      S              := AModel.Species[i];
      Nodes[i].Pos   := S.Center;
      Nodes[i].Force := TPointF.Create(0, 0);
      Nodes[i].Mass  := 1.0;    // base mass; degree added below
      Nodes[i].IsFree := True;  // all nodes move; aliases track their primary
      SpeciesIdx.AddOrSetValue(S.Id, i);
    end;

    // Build alias → primary index map after all species are indexed
    for i := 0 to NS - 1 do
    begin
      S := AModel.Species[i];
      if S.IsAlias then
      begin
        if SpeciesIdx.TryGetValue(S.AliasOf.Id, PrimaryIdx) then
          AliasMap.AddOrSetValue(i, PrimaryIdx);
      end;
    end;

    for i := 0 to NR - 1 do
    begin
      JI                 := NS + i;
      R                  := AModel.Reactions[i];
      Nodes[JI].Pos      := R.JunctionPos;
      Nodes[JI].Force    := TPointF.Create(0, 0);
      // Junction mass = participant count + 1 so dense reactions repel strongly
      Nodes[JI].Mass     := 1.0 + R.Reactants.Count + R.Products.Count;
      Nodes[JI].IsFree   := True;
    end;

    // Accumulate degree into species mass
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

    // -----------------------------------------------------------------------
    //  2. Compute canvas centre for gravity
    // -----------------------------------------------------------------------
    CentreX := 0; CentreY := 0;
    for i := 0 to Total - 1 do
    begin
      CentreX := CentreX + Nodes[i].Pos.X;
      CentreY := CentreY + Nodes[i].Pos.Y;
    end;
    CentreX := CentreX / Total;
    CentreY := CentreY / Total;

    // -----------------------------------------------------------------------
    //  3. Main iteration loop
    // -----------------------------------------------------------------------
    Speed := SpeedStart;

    for Iter := 1 to Iterations do
    begin
      // --- Reset forces ---
      for i := 0 to Total - 1 do
        Nodes[i].Force := TPointF.Create(0, 0);

      // --- Repulsion: all pairs O(n²) ------------------------------------
      for i := 0 to Total - 2 do
      begin
        if not Nodes[i].IsFree then Continue;
        for j := i + 1 to Total - 1 do
        begin
          DX   := Nodes[i].Pos.X - Nodes[j].Pos.X;
          DY   := Nodes[i].Pos.Y - Nodes[j].Pos.Y;
          Dist := Max(MIN_DIST, Sqrt(DX * DX + DY * DY));

          // ForceAtlas2 repulsion: Kr * Mi * Mj / dist²
          Mag  := Kr * Nodes[i].Mass * Nodes[j].Mass / (Dist * Dist);

          // Normalise direction
          DX := DX / Dist;
          DY := DY / Dist;

          Nodes[i].Force.X := Nodes[i].Force.X + Mag * DX;
          Nodes[i].Force.Y := Nodes[i].Force.Y + Mag * DY;
          if Nodes[j].IsFree then
          begin
            Nodes[j].Force.X := Nodes[j].Force.X - Mag * DX;
            Nodes[j].Force.Y := Nodes[j].Force.Y - Mag * DY;
          end;
        end;
      end;

      // --- Attraction: species ↔ junction springs -------------------------
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

      // --- Gravity: pull toward canvas centre ----------------------------
      for i := 0 to Total - 1 do
      begin
        if not Nodes[i].IsFree then Continue;
        DX := CentreX - Nodes[i].Pos.X;
        DY := CentreY - Nodes[i].Pos.Y;
        Nodes[i].Force.X := Nodes[i].Force.X + Kg * Nodes[i].Mass * DX;
        Nodes[i].Force.Y := Nodes[i].Force.Y + Kg * Nodes[i].Mass * DY;
      end;

      // --- Apply forces with cooling -------------------------------------
      for i := 0 to Total - 1 do
      begin
        if not Nodes[i].IsFree then Continue;

        // Clamp the displacement to Speed to prevent explosions
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

      // --- Alias tracking: each alias copies the displacement of its primary
      // This keeps alias nodes spatially coherent with their primary without
      // participating independently in the force simulation.
      for var Pair in AliasMap do
      begin
        var AliasI   := Pair.Key;
        var PrimaryI := Pair.Value;
        var DispX := Nodes[PrimaryI].Pos.X - AModel.Species[PrimaryI].Center.X;
        var DispY := Nodes[PrimaryI].Pos.Y - AModel.Species[PrimaryI].Center.Y;
        Nodes[AliasI].Pos.X := AModel.Species[AliasI].Center.X + DispX;
        Nodes[AliasI].Pos.Y := AModel.Species[AliasI].Center.Y + DispY;
      end;

      // Decay speed each iteration
      Speed := Speed * SpeedDecay;
    end;

    // -----------------------------------------------------------------------
    //  4. Recentre: translate all nodes so the centroid returns to where it
    //     started.  This makes repeated layout calls idempotent — the network
    //     relaxes in place without drifting across the canvas.
    // -----------------------------------------------------------------------
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

    // -----------------------------------------------------------------------
    //  5. Write results back into the model
    // -----------------------------------------------------------------------
    for i := 0 to NS - 1 do
      AModel.Species[i].Center := Nodes[i].Pos;

    for i := 0 to NR - 1 do
      AModel.Reactions[i].JunctionPos := Nodes[NS + i].Pos;

  finally
    AliasMap.Free;
    SpeciesIdx.Free;
  end;
end;

end.
