unit uAntimonyBridge;

{
  uAntimonyBridge.pas
  ===================
  Translates between TAntimonyModel (from the Antimony parser) and TBioModel
  (the application's native model).

  Id vs Name
  ----------
  In SBML/Antimony, Id is the unique biochemical identifier (e.g. 'S1', 'ATP').
  Name is an optional human-readable label that need not be unique; Antimony
  does not use it.  All export code therefore uses S.Id / Part.Species.Id.

  TBioModel.AddSpecies auto-generates a diagram-internal Id via GenerateId('s')
  and stores the passed string in Name.  On import the bridge immediately
  overwrites Node.Id with the biochemical identifier from the Antimony model,
  which is the correct field for all downstream use.

  Import pipeline
  ---------------
  1. Call TAntimony.ParseFromString  -> TAntimonyModel
  2. Copy compartments, parameters, assignment rules into TBioModel
  3. Create TSpeciesNode for each TAntimonySpecies; fix Id immediately
  4. Create TReaction for each TAntimonyReaction, wire participants
  5. Auto-layout positions species/junctions sensibly

  Case handling
  -------------
  Antimony files sometimes mix the casing of a species declaration
  (e.g. "species s1") with its use in reactions ("S1 => S2").
  CanonicalId() resolves any reaction reference back to the declared
  spelling via a case-insensitive FindSpecies lookup, so the declared
  form is always used as the Id and no identifier is ever renamed.
  NOTE: TAntimonyModel.FindSpecies must use SameText for this to work.

  Export pipeline
  ---------------
  Primary species nodes only (aliases have no independent biochemical identity).
  All identifiers are taken from Id, preserving declared casing exactly.
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
    // Import Antimony source text -> populate AModel (clears existing content).
    // Raises EAntimonyParseError on parse failure.
    class procedure ImportFromString(const ASource: string;
                                     AModel: TBioModel);

    // Import from file.
    class procedure ImportFromFile(const AFileName: string;
                                   AModel: TBioModel);

    // Export AModel -> Antimony text string.
    class function ExportToString(AModel: TBioModel): string;

    // Export to file.
    class procedure ExportToFile(AModel: TBioModel; const AFileName: string);
  end;

implementation

// ===========================================================================
//  Layout constants (world pixels)
// ===========================================================================
const
  NODE_W        = 80;
  NODE_H        = 36;
  ROW_PITCH     = 120;   // vertical distance between reaction rows
  LEFT_MARGIN   = 100;   // X centre of reactant column
  RIGHT_MARGIN  = 480;   // X centre of product column
  MID_X         = 290;   // X of junction point
  TOP_MARGIN    = 80;    // Y of first row centre
  SPECIES_PITCH = 60;    // vertical gap between species in the same column

// ===========================================================================
//  Import helpers
// ===========================================================================

// Place a column of N species centred on RowCentreY.
// Returns the Y of the topmost node in the column.
function ColumnTopY(N: Integer; RowCentreY: Single): Single;
begin
  if N <= 1 then
    Result := RowCentreY
  else
    Result := RowCentreY - ((N - 1) * SPECIES_PITCH * 0.5);
end;

// Returns the canonical (declared) spelling for a species name, using a
// case-insensitive search so that "S1" in a reaction resolves to "s1" from
// a declaration.  If no declaration is found the name is returned unchanged.
function CanonicalId(AntModel: TAntimonyModel; const AName: string): string;
var
  Idx: Integer;
begin
  Idx := AntModel.FindSpecies(AName);   // must use SameText internally
  if Idx >= 0 then
    Result := AntModel.Species[Idx].Id  // declared spelling
  else
    Result := AName;
end;

// ===========================================================================
//  TAntimonyBridge - Import
// ===========================================================================

class procedure TAntimonyBridge.ImportFromString(const ASource: string;
                                                  AModel: TBioModel);
var
  AntModel      : TAntimonyModel;
  Placed        : TDictionary<string, TSpeciesNode>;  // biochemical Id -> node
  RowIndex      : Integer;
  RowCY         : Single;
  i, j          : Integer;
  AntSpec       : TAntimonySpecies;
  AntRct        : TAntimonyReaction;
  AntComp       : TAntimonyCompartment;
  AntAssign     : TAntimonyAssignment;
  AntRule       : TAntimonyAssignmentRule;
  PartNode      : TSpeciesNode;
  Reaction      : TReaction;
  NReact, NProd : Integer;
  CY            : Single;
  JX, JY        : Single;
  AntS          : Integer;
  CanName       : string;
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

    // --- Parameters: assignments whose variable is not a species ---
    for i := 0 to AntModel.Assignments.Count - 1 do
    begin
      AntAssign := AntModel.Assignments[i];
      if AntModel.FindSpecies(AntAssign.Variable) < 0 then
        AModel.AddParameter(AntAssign.Variable, AntAssign.Expression);
    end;

    // --- Assignment rules ---
    for i := 0 to AntModel.AssignmentRules.Count - 1 do
    begin
      AntRule := AntModel.AssignmentRules[i];
      AModel.AddAssignmentRule(AntRule.Variable, AntRule.Expression);
    end;

    // --- Species nodes ---
    // AddSpecies auto-generates a diagram-internal Id via GenerateId('s') and
    // stores our passed string in Name.  We immediately overwrite Node.Id with
    // the biochemical identifier so it is in the correct field for all
    // downstream use (export, JSON persistence, reaction wiring, etc.).
    // The Placed dictionary is keyed on the canonical biochemical Id.
    Placed   := TDictionary<string, TSpeciesNode>.Create;
    RowIndex := 0;
    try
      // First pass: create nodes for all explicitly declared species.
      for i := 0 to AntModel.Species.Count - 1 do
      begin
        AntSpec := AntModel.Species[i];
        if not Placed.ContainsKey(AntSpec.Id) then
        begin
          RowCY    := TOP_MARGIN + RowIndex * ROW_PITCH;
          var Node := AModel.AddSpecies(AntSpec.Id,
                        trunc(Random() * 600), trunc(Random() * 600));
          Node.Id           := AntSpec.Id;   // overwrite auto-generated diagram Id
          Node.IsBoundary   := AntSpec.IsBoundary;
          Node.IsConstant   := AntSpec.IsConstant;
          Node.Compartment  := AntSpec.Compartment;
          Node.InitialValue := AntSpec.InitialValue;
          Placed.Add(AntSpec.Id, Node);
          Inc(RowIndex);
        end;
      end;

      RowIndex := 0;

      // --- Reactions ---
      for i := 0 to AntModel.Reactions.Count - 1 do
      begin
        AntRct := AntModel.Reactions[i];
        NReact := AntRct.Reactants.Count;
        NProd  := AntRct.Products.Count;
        RowCY  := TOP_MARGIN + RowIndex * ROW_PITCH;

        // Place any unplaced reactant species.
        // Resolve each participant name to its declared canonical spelling first.
        CY := ColumnTopY(NReact, RowCY);
        for j := 0 to NReact - 1 do
        begin
          CanName := CanonicalId(AntModel, AntRct.Reactants[j].SpeciesName);
          if not Placed.ContainsKey(CanName) then
          begin
            var Node := AModel.AddSpecies(CanName, LEFT_MARGIN, CY, NODE_W, NODE_H);
            Node.Id := CanName;   // overwrite auto-generated diagram Id
            AntS    := AntModel.FindSpecies(CanName);
            if AntS >= 0 then
            begin
              Node.IsBoundary   := AntModel.Species[AntS].IsBoundary;
              Node.IsConstant   := AntModel.Species[AntS].IsConstant;
              Node.Compartment  := AntModel.Species[AntS].Compartment;
              Node.InitialValue := AntModel.Species[AntS].InitialValue;
            end;
            Placed.Add(CanName, Node);
          end;
          CY := CY + SPECIES_PITCH;
        end;

        // Place any unplaced product species.
        CY := ColumnTopY(NProd, RowCY);
        for j := 0 to NProd - 1 do
        begin
          CanName := CanonicalId(AntModel, AntRct.Products[j].SpeciesName);
          if not Placed.ContainsKey(CanName) then
          begin
            var Node := AModel.AddSpecies(CanName, RIGHT_MARGIN, CY, NODE_W, NODE_H);
            Node.Id := CanName;   // overwrite auto-generated diagram Id
            AntS    := AntModel.FindSpecies(CanName);
            if AntS >= 0 then
            begin
              Node.IsBoundary   := AntModel.Species[AntS].IsBoundary;
              Node.IsConstant   := AntModel.Species[AntS].IsConstant;
              Node.Compartment  := AntModel.Species[AntS].Compartment;
              Node.InitialValue := AntModel.Species[AntS].InitialValue;
            end;
            Placed.Add(CanName, Node);
          end;
          CY := CY + SPECIES_PITCH;
        end;

        // Junction position - midpoint between reactant and product centroids.
        var SumRX: Single := 0;
        var SumRY: Single := 0;
        for j := 0 to NReact - 1 do
        begin
          var N := Placed[CanonicalId(AntModel, AntRct.Reactants[j].SpeciesName)];
          SumRX := SumRX + N.Center.X;
          SumRY := SumRY + N.Center.Y;
        end;
        var SumPX: Single := 0;
        var SumPY: Single := 0;
        for j := 0 to NProd - 1 do
        begin
          var N := Placed[CanonicalId(AntModel, AntRct.Products[j].SpeciesName)];
          SumPX := SumPX + N.Center.X;
          SumPY := SumPY + N.Center.Y;
        end;

        if NReact > 0 then begin SumRX := SumRX / NReact; SumRY := SumRY / NReact; end
        else               begin SumRX := LEFT_MARGIN;     SumRY := RowCY;          end;
        if NProd  > 0 then begin SumPX := SumPX / NProd;  SumPY := SumPY / NProd;  end
        else               begin SumPX := RIGHT_MARGIN;    SumPY := RowCY;          end;

        JX := (SumRX + SumPX) * 0.5;
        JY := (SumRY + SumPY) * 0.5;

        Reaction := AModel.AddReaction(JX, JY);
        Reaction.KineticLaw   := AntRct.KineticLaw;
        Reaction.IsReversible := AntRct.IsReversible;
        if AntRct.Id <> '' then Reaction.Id := AntRct.Id;

        for j := 0 to NReact - 1 do
        begin
          PartNode := Placed[CanonicalId(AntModel, AntRct.Reactants[j].SpeciesName)];
          Reaction.Reactants.Add(
            TParticipant.Create(PartNode, AntRct.Reactants[j].Stoichiometry));
        end;
        for j := 0 to NProd - 1 do
        begin
          PartNode := Placed[CanonicalId(AntModel, AntRct.Products[j].SpeciesName)];
          Reaction.Products.Add(
            TParticipant.Create(PartNode, AntRct.Products[j].Stoichiometry));
        end;

        Inc(RowIndex);
      end;

    finally
      Placed.Free;
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
//  TAntimonyBridge - Export
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
  Prefix     : string;
begin
  Lines := TStringList.Create;
  try
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

    // --- Species declarations (primary nodes only) ---
    // Id is the SBML unique identifier and the correct field for Antimony output.

    // I don't think this is needed

    var HasSpec := False;
    if AModel.Species.Count > 0 then
       Lines.Add('  // Species');
    for S in AModel.Species do
    begin
      if S.IsAlias then Continue;
      if not HasSpec then
      begin
        HasSpec := True;
      end;
      Prefix := '';
      if S.IsBoundary then Prefix := '$';
      if S.Compartment <> '' then
        Lines.Add(Format('  species %s%s in %s;', [Prefix, S.Id, S.Compartment]))
      else
        Lines.Add(Format('  species %s%s;', [Prefix, S.Id]));
    end;
    if HasSpec then Lines.Add('');

    // --- Reactions ---
    // Use Part.Species.Id — the unique SBML identifier, preserved from import.
    if AModel.Reactions.Count > 0 then
    begin
      Lines.Add('  // Reactions');
      for R in AModel.Reactions do
      begin
        ReactionStr := '  ' + R.Id + ': ';

        for i := 0 to R.Reactants.Count - 1 do
        begin
          Part := R.Reactants[i];
          if i > 0 then ReactionStr := ReactionStr + ' + ';
          if Abs(Part.Stoichiometry - 1.0) > 1e-9 then
            ReactionStr := ReactionStr + FloatToStr(Part.Stoichiometry) + ' ';
          Prefix := '';
          if Part.Species.IsBoundary then Prefix := '$';
          ReactionStr := ReactionStr + Prefix + Part.Species.Id;
        end;

        if R.IsReversible then
          ReactionStr := ReactionStr + ' -> '
        else
          ReactionStr := ReactionStr + ' -> ';

        for i := 0 to R.Products.Count - 1 do
        begin
          Part := R.Products[i];
          if i > 0 then ReactionStr := ReactionStr + ' + ';
          if Abs(Part.Stoichiometry - 1.0) > 1e-9 then
            ReactionStr := ReactionStr + FloatToStr(Part.Stoichiometry) + ' ';
          if Part.Species.IsBoundary then Prefix := '$';
          ReactionStr := ReactionStr + Prefix + Part.Species.Id;
        end;

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

    // --- Species initial values ---
    // Guard on Species.Count (the original code incorrectly used Parameters.Count).
    if AModel.Species.Count > 0 then
    begin
      Lines.Add('  // Species initial values');
      for S in AModel.Species do
      begin
        if S.IsAlias then Continue;
        Lines.Add(Format('  %s = %g;', [S.Id, S.InitialValue]));
      end;
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
