unit uAntimonyBridge;

{
  uAntimonyBridge.pas
  ===================
  Translates between TAntimonyModel (from the Antimony parser) and TBioModel
  (the application's native model).

  Import pipeline
  ---------------
  1. Call TAntimony.ParseFromString  → TAntimonyModel
  2. Copy compartments, parameters, assignment rules into TBioModel
  3. Create TSpeciesNode for each TAntimonySpecies using auto-layout
  4. Create TReaction for each TAntimonyReaction, wire participants
  5. Auto-layout positions species/junctions sensibly

  Auto-layout strategy
  --------------------
  Reactions are laid out in rows, top to bottom, with a fixed vertical pitch.
  For each reaction:
    - Reactants are placed in a column at X = LEFT_MARGIN, centred on the row.
    - Products  are placed in a column at X = RIGHT_MARGIN, centred on the row.
    - The junction sits at X = MID_X, Y = row centre.
  Species that appear in multiple reactions are placed at their FIRST encounter
  position and reused — alias creation from import is left as a future feature.

  Export pipeline
  ---------------
  Primary species nodes only (aliases have no independent biochemical identity).
  Reactions reference species by DisplayName so aliases resolve correctly.
  Output is a plain Antimony text string.

  Compartment handling
  --------------------
  Compartments are stored in TBioModel but not yet visualised.  On import we
  copy all compartments.  On export we emit them if present.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Math,
  uBioModel,
  uAntimony,
  uAntimonyModelType;

type
  TAntimonyBridge = class
  public
    // Import Antimony source text → populate AModel (clears existing content).
    // Raises EAntimonyParseError on parse failure.
    class procedure ImportFromString(const ASource: string;
                                     AModel: TBioModel);

    // Import from file.
    class procedure ImportFromFile(const AFileName: string;
                                   AModel: TBioModel);

    // Export AModel → Antimony text string.
    class function ExportToString(AModel: TBioModel): string;

    // Export to file.
    class procedure ExportToFile(AModel: TBioModel; const AFileName: string);
  end;

implementation

// ===========================================================================
//  Layout constants (world pixels)
// ===========================================================================
const
  NODE_W          = 80;
  NODE_H          = 36;
  ROW_PITCH       = 120;    // vertical distance between reaction rows
  LEFT_MARGIN     = 100;    // X centre of reactant column
  RIGHT_MARGIN    = 480;    // X centre of product  column
  MID_X           = 290;    // X of junction point
  TOP_MARGIN      = 80;     // Y of first row centre
  SPECIES_PITCH   = 60;     // vertical gap between species in the same column

// ===========================================================================
//  Import helpers
// ===========================================================================

// Place a column of N species centred on RowCentreY, starting at ColX.
// Returns the Y of the topmost node in the column.
function ColumnTopY(N: Integer; RowCentreY: Single): Single;
begin
  // Total height occupied = (N-1) * SPECIES_PITCH
  // Centre of column = RowCentreY  →  top = centre - half of total height
  if N <= 1 then
    Result := RowCentreY
  else
    Result := RowCentreY - ((N - 1) * SPECIES_PITCH * 0.5);
end;

// ===========================================================================
//  TAntimonyBridge — Import
// ===========================================================================

class procedure TAntimonyBridge.ImportFromString(const ASource: string;
                                                  AModel: TBioModel);
var
  AntModel    : TAntimonyModel;
  Placed      : TDictionary<string, TSpeciesNode>;  // name → first-placed node
  RowIndex    : Integer;
  RowCY       : Single;
  i, j        : Integer;
  AntSpec     : TAntimonySpecies;
  AntRct      : TAntimonyReaction;
  AntComp     : TAntimonyCompartment;
  AntAssign   : TAntimonyAssignment;
  AntRule     : TAntimonyAssignmentRule;
  Part        : TParticipant;
  PartNode    : TSpeciesNode;
  Reaction    : TReaction;
  NReact, NProd : Integer;
  CY          : Single;
  Stoich      : Double;
  JX, JY      : Single;
begin
  AntModel := TAntimony.ParseFromString(ASource);
  try
    AModel.Clear;
    AModel.ModelName := AntModel.Name;

    // --- Compartments ---
    for i := 0 to AntModel.Compartments.Count - 1 do
    begin
      AntComp := AntModel.Compartments[i];
      AModel.AddCompartment(AntComp.Id, AntComp.Size, AntComp.Dimensions);
    end;

    // --- Parameters (assignments that are not species initial values) ---
    for i := 0 to AntModel.Assignments.Count - 1 do
    begin
      AntAssign := AntModel.Assignments[i];
      // If the name matches a species it is an initial value, not a parameter
      if AntModel.FindSpecies(AntAssign.Variable) < 0 then
        AModel.AddParameter(AntAssign.Variable, AntAssign.Expression);
    end;

    // --- Assignment rules ---
    for i := 0 to AntModel.AssignmentRules.Count - 1 do
    begin
      AntRule := AntModel.AssignmentRules[i];
      AModel.AddAssignmentRule(AntRule.Variable, AntRule.Expression);
    end;

    // --- Species initial values from Assignments ---
    // We need these later when creating TSpeciesNode objects.
    // Build a quick lookup: speciesName → initial value string
    var SpeciesInitVal := TDictionary<string, Double>.Create;
    try
      for i := 0 to AntModel.Assignments.Count - 1 do
      begin
        AntAssign := AntModel.Assignments[i];
        if AntModel.FindSpecies(AntAssign.Variable) >= 0 then
          if AntAssign.IsSimpleValue then
            SpeciesInitVal.AddOrSetValue(AntAssign.Variable,
                                         AntAssign.GetNumericValue);
      end;

      // --- Species nodes — created lazily during reaction layout ---
      // We lay out species as we encounter them in reactions.
      Placed   := TDictionary<string, TSpeciesNode>.Create;
      RowIndex := 0;

      try
        // First pass: create all species that don't appear in any reaction
        // so they still exist in the model even if isolated.
        for i := 0 to AntModel.Species.Count - 1 do
        begin
          AntSpec := AntModel.Species[i];
          if not Placed.ContainsKey(AntSpec.Id) then
          begin
            RowCY    := TOP_MARGIN + RowIndex * ROW_PITCH;
            //var Node := AModel.AddSpecies(AntSpec.Id, LEFT_MARGIN, RowCY, NODE_W, NODE_H);
            var Node := AModel.AddSpecies(AntSpec.Id, trunc (Random()*600), trunc (Random()*600));
            Node.IsBoundary  := AntSpec.IsBoundary;
            Node.IsConstant  := AntSpec.IsConstant;
            Node.Compartment := AntSpec.Compartment;
            var InitVal: Double;
            if SpeciesInitVal.TryGetValue(AntSpec.Id, InitVal) then
              Node.InitialValue := InitVal;
            Placed.Add(AntSpec.Id, Node);
            Inc (RowIndex);
          end;
        end;

        // Reset row index for reaction layout
        RowIndex := 0;

        // --- Reactions ---
        for i := 0 to AntModel.Reactions.Count - 1 do
        begin
          AntRct  := AntModel.Reactions[i];
          NReact  := AntRct.Reactants.Count;
          NProd   := AntRct.Products.Count;
          RowCY   := TOP_MARGIN + RowIndex * ROW_PITCH;

          // Place any unplaced reactant species
          CY := ColumnTopY(NReact, RowCY);
          for j := 0 to NReact - 1 do
          begin
            var Participant := AntRct.Reactants[j];
            if not Placed.ContainsKey(Participant.SpeciesName) then
            begin
              var Node := AModel.AddSpecies(Participant.SpeciesName,
                            LEFT_MARGIN, CY, NODE_W, NODE_H);
              var AntS := AntModel.FindSpecies(Participant.SpeciesName);
              if AntS >= 0 then
              begin
                Node.IsBoundary  := AntModel.Species[AntS].IsBoundary;
                Node.IsConstant  := AntModel.Species[AntS].IsConstant;
                Node.Compartment := AntModel.Species[AntS].Compartment;
              end;
              var InitVal: Double;
              if SpeciesInitVal.TryGetValue(Participant.SpeciesName, InitVal) then
                Node.InitialValue := InitVal;
              Placed.Add(Participant.SpeciesName, Node);
            end;
            CY := CY + SPECIES_PITCH;
          end;

          // Place any unplaced product species
          CY := ColumnTopY(NProd, RowCY);
          for j := 0 to NProd - 1 do
          begin
            var Participant := AntRct.Products[j];
            if not Placed.ContainsKey(Participant.SpeciesName) then
            begin
              var Node := AModel.AddSpecies(Participant.SpeciesName,
                            RIGHT_MARGIN, CY, NODE_W, NODE_H);
              var AntS := AntModel.FindSpecies(Participant.SpeciesName);
              if AntS >= 0 then
              begin
                Node.IsBoundary  := AntModel.Species[AntS].IsBoundary;
                Node.IsConstant  := AntModel.Species[AntS].IsConstant;
                Node.Compartment := AntModel.Species[AntS].Compartment;
              end;
              var InitVal: Double;
              if SpeciesInitVal.TryGetValue(Participant.SpeciesName, InitVal) then
                Node.InitialValue := InitVal;
              Placed.Add(Participant.SpeciesName, Node);
            end;
            CY := CY + SPECIES_PITCH;
          end;

          // Compute junction position — midpoint between reactant and product centroids
          var SumRX : Single := 0; var SumRY : Single := 0;
          for j := 0 to NReact - 1 do
          begin
            var N := Placed[AntRct.Reactants[j].SpeciesName];
            SumRX := SumRX + N.Center.X;
            SumRY := SumRY + N.Center.Y;
          end;
          var SumPX : Single := 0; var SumPY : Single := 0;
          for j := 0 to NProd - 1 do
          begin
            var N := Placed[AntRct.Products[j].SpeciesName];
            SumPX := SumPX + N.Center.X;
            SumPY := SumPY + N.Center.Y;
          end;
          if NReact > 0 then begin SumRX := SumRX / NReact; SumRY := SumRY / NReact; end
          else begin SumRX := LEFT_MARGIN; SumRY := RowCY; end;
          if NProd > 0  then begin SumPX := SumPX / NProd;  SumPY := SumPY / NProd;  end
          else begin SumPX := RIGHT_MARGIN; SumPY := RowCY; end;

          JX := (SumRX + SumPX) * 0.5;
          JY := (SumRY + SumPY) * 0.5;

          Reaction := AModel.AddReaction(JX, JY);
          Reaction.KineticLaw   := AntRct.KineticLaw;
          Reaction.IsReversible := AntRct.IsReversible;
          if AntRct.Id <> '' then Reaction.Id := AntRct.Id;

          for j := 0 to NReact - 1 do
          begin
            PartNode := Placed[AntRct.Reactants[j].SpeciesName];
            Reaction.Reactants.Add(
              TParticipant.Create(PartNode, AntRct.Reactants[j].Stoichiometry));
          end;
          for j := 0 to NProd - 1 do
          begin
            PartNode := Placed[AntRct.Products[j].SpeciesName];
            Reaction.Products.Add(
              TParticipant.Create(PartNode, AntRct.Products[j].Stoichiometry));
          end;

          Inc(RowIndex);
        end;

      finally
        Placed.Free;
      end;
    finally
      SpeciesInitVal.Free;
    end;
  finally
    AntModel.Free;
  end;
end;

class procedure TAntimonyBridge.ImportFromFile(const AFileName: string;
                                               AModel: TBioModel);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(AFileName, TEncoding.UTF8);
    ImportFromString(SL.Text, AModel);
  finally
    SL.Free;
  end;
end;

// ===========================================================================
//  TAntimonyBridge — Export
// ===========================================================================

class function TAntimonyBridge.ExportToString(AModel: TBioModel): string;
var
  Lines      : TStringList;
  S          : TSpeciesNode;
  R          : TReaction;
  C          : TCompartment;
  P          : TParameter;
  AR         : TAssignmentRule;
  Part       : TParticipant;
  ReactionStr: string;
  i          : Integer;
begin
  Lines := TStringList.Create;
  try
//    if AModel.ModelName <> '' then
//      Lines.Add('model ' + AModel.ModelName)
//    else
//      Lines.Add('model bioNetworkModel');
//    Lines.Add('');

    // --- Compartments (skip defaultCompartment) ---
    var HasComps := False;
    for C in AModel.Compartments do
      if not SameText(C.Id, 'defaultCompartment') then
      begin
        if not HasComps then
        begin
          Lines.Add('  // Compartments');
          HasComps := True;
        end;
        Lines.Add(Format('  compartment %s = %g;', [C.Id, C.Size]));
      end;
    if HasComps then Lines.Add('');

    // --- Species (primary nodes only) ---
    var HasSpec := False;
    for S in AModel.Species do
    begin
      if S.IsAlias then Continue;
      if not HasSpec then
      begin
        Lines.Add('  // Species');
        HasSpec := True;
      end;
      var Prefix := '';
      if S.IsBoundary then Prefix := '$';
      if S.Compartment <> '' then
        Lines.Add(Format('  species %s%s in %s = %g;',
          [Prefix, S.Name, S.Compartment, S.InitialValue]))
      else
        Lines.Add(Format('  species %s%s = %g;',
          [Prefix, S.Name, S.InitialValue]));
    end;
    if HasSpec then Lines.Add('');

    // --- Reactions ---
    if AModel.Reactions.Count > 0 then
    begin
      Lines.Add('  // Reactions');
      for R in AModel.Reactions do
      begin
        // Reaction id
        ReactionStr := '  ' + R.Id + ': ';

        // Reactants
        for i := 0 to R.Reactants.Count - 1 do
        begin
          Part := R.Reactants[i];
          if i > 0 then ReactionStr := ReactionStr + ' + ';
          if Abs(Part.Stoichiometry - 1.0) > 1e-9 then
            ReactionStr := ReactionStr + FloatToStr(Part.Stoichiometry) + ' ';
          ReactionStr := ReactionStr + Part.Species.DisplayName;
        end;

        // Arrow
        if R.IsReversible then
          ReactionStr := ReactionStr + ' -> '
        else
          ReactionStr := ReactionStr + ' => ';

        // Products
        for i := 0 to R.Products.Count - 1 do
        begin
          Part := R.Products[i];
          if i > 0 then ReactionStr := ReactionStr + ' + ';
          if Abs(Part.Stoichiometry - 1.0) > 1e-9 then
            ReactionStr := ReactionStr + FloatToStr(Part.Stoichiometry) + ' ';
          ReactionStr := ReactionStr + Part.Species.DisplayName;
        end;

        // Kinetic law — default to 'v' when none is set
        if R.KineticLaw <> '' then
          ReactionStr := ReactionStr + '; ' + R.KineticLaw
        else
          ReactionStr := ReactionStr + '; v';

        Lines.Add(ReactionStr + ';');
      end;
      Lines.Add('');
    end;

    // --- Parameters ---
    if AModel.Parameters.Count > 0 then
    begin
      Lines.Add('  // Parameters');
      for P in AModel.Parameters do
        Lines.Add(Format('  %s = %s;', [P.Variable, P.Expression]));
      Lines.Add('');
    end;

    // --- Assignment rules ---
    if AModel.AssignmentRules.Count > 0 then
    begin
      Lines.Add('  // Assignment rules');
      for AR in AModel.AssignmentRules do
        Lines.Add(Format('  %s := %s;', [AR.Variable, AR.Expression]));
      Lines.Add('');
    end;

    //Lines.Add('end');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

class procedure TAntimonyBridge.ExportToFile(AModel: TBioModel;
                                             const AFileName: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ExportToString(AModel);
    SL.SaveToFile(AFileName, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

end.
