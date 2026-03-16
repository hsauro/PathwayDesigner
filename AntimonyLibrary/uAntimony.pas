unit uAntimony;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  uAntimonyLexer,
  uAntimonyParser,
  uAntimonyModelType;

type
  TAntimony = class
  public
    // Parse from string
    class function ParseFromString(const ASource: string): TAntimonyModel;

    // Parse from file
    class function ParseFromFile(const AFilename: string): TAntimonyModel;

    // Parse from stream
    class function ParseFromStream(AStream: TStream): TAntimonyModel;

    // Validate syntax without creating full model (returns error message or empty string if valid)
    class function ValidateFromString(const ASource: string): string;
    class function ValidateFromFile(const AFilename: string): string;
    class function ValidateModel(AModel: TAntimonyModel): Boolean;
    class function GetValidationErrors(AModel: TAntimonyModel): TArray<string>;

    // Utility methods for model inspection
    class procedure PrintModelSummary(AModel: TAntimonyModel);
    class function GetModelStats(AModel: TAntimonyModel): string;
    class function ModelToString(AModel: TAntimonyModel): string;
  end;

  // Exception class for Antimony parsing errors
  EAntimonyParseError = class(Exception)
  private
    FLineNumber: Integer;
    FColumnNumber: Integer;
    FToken: string;
  public
    constructor Create(const AMessage: string; const AToken: string = ''; ALineNumber: Integer = -1; AColumnNumber: Integer = -1);
    property LineNumber: Integer read FLineNumber;
    property ColumnNumber: Integer read FColumnNumber;
    property Token: string read FToken;
  end;


implementation

{ TAntimonyFacade }

class function TAntimony.GetValidationErrors(AModel: TAntimonyModel): TArray<string>;
var
  Errors: TStringList;
  I, J: Integer;
  Species: TAntimonySpecies;
  Reaction: TAntimonyReaction;
  Participant: TReactionParticipant;
  SpeciesNames: TStringList;

  function FindSpecies(const AId: string): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to AModel.Species.Count - 1 do
    begin
      if SameText(AModel.Species[K].Id, AId) then
      begin
        Result := True;
        Break;
      end;
    end;
  end;


begin
  Errors := TStringList.Create;
  SpeciesNames := TStringList.Create;
  try
    // Collect species names
    for I := 0 to AModel.Species.Count - 1 do
      SpeciesNames.Add(AModel.Species[I].Id);

    // Check for duplicate species names
    for I := 0 to SpeciesNames.Count - 1 do
    begin
      for J := I + 1 to SpeciesNames.Count - 1 do
      begin
        if SameText(SpeciesNames[I], SpeciesNames[J]) then
          Errors.Add('Duplicate species name: ' + SpeciesNames[I]);
      end;
    end;

    // Check species properties
    for I := 0 to AModel.Species.Count - 1 do
    begin
      Species := AModel.Species[I];
      if Species.id = '' then
        Errors.Add('Species with empty name at index ' + IntToStr(I));
      if Species.InitialValue < 0 then
        Errors.Add('Negative initial value for species: ' + Species.Id);
    end;

    // Check reactions
    for I := 0 to AModel.Reactions.Count - 1 do
    begin
      Reaction := AModel.Reactions[I];

      // Check reactants
      for J := 0 to Reaction.Reactants.Count - 1 do
      begin
        Participant := Reaction.Reactants[J];
        if not FindSpecies(Participant.SpeciesName) then
          Errors.Add(Format('Unknown species "%s" in reaction "%s" reactants',
            [Participant.SpeciesName, Reaction.Id]));
        if Participant.Stoichiometry <= 0 then
          Errors.Add(Format('Invalid stoichiometry %g for species "%s" in reaction "%s"',
            [Participant.Stoichiometry, Participant.SpeciesName, Reaction.Id]));
      end;

      // Check products
      for J := 0 to Reaction.Products.Count - 1 do
      begin
        Participant := Reaction.Products[J];
        if not FindSpecies(Participant.SpeciesName) then
          Errors.Add(Format('Unknown species "%s" in reaction "%s" products',
            [Participant.SpeciesName, Reaction.id]));
        if Participant.Stoichiometry <= 0 then
          Errors.Add(Format('Invalid stoichiometry %g for species "%s" in reaction "%s"',
            [Participant.Stoichiometry, Participant.SpeciesName, Reaction.Id]));
      end;
    end;

    Result := Errors.ToStringArray;
  finally
    Errors.Free;
    SpeciesNames.Free;
  end;
end;


class function TAntimony.ValidateModel(AModel: TAntimonyModel): Boolean;
var
  Errors: TArray<string>;
begin
  Errors := GetValidationErrors(AModel);
  Result := Length(Errors) = 0;
end;



class function TAntimony.ParseFromString(const ASource: string): TAntimonyModel;
var
  Lexer: TAntimonyLexer;
  Parser: TAntimonyParser;
begin
  Result := nil;
  Lexer := TAntimonyLexer.Create(ASource);
  try
    Parser := TAntimonyParser.Create(Lexer);
    try
      Result := Parser.Parse;
    except
      on E: Exception do
      begin
        Result.Free;
        Result := nil;
        raise EAntimonyParseError.Create('Parse error: ' + E.Message);
      end;
    end;
  finally
    Parser.Free;
    Lexer.Free;
  end;
end;

class function TAntimony.ParseFromFile(const AFilename: string): TAntimonyModel;
var
  Source: string;
begin
  if not TFile.Exists(AFilename) then
    raise EAntimonyParseError.Create('File not found: ' + AFilename);

  try
    Source := TFile.ReadAllText(AFilename, TEncoding.UTF8);
    Result := ParseFromString(Source);
  except
    on E: EAntimonyParseError do
      raise; // Re-raise Antimony errors as-is
    on E: Exception do
      raise EAntimonyParseError.Create('Error reading file "' + AFilename + '": ' + E.Message);
  end;
end;

class function TAntimony.ParseFromStream(AStream: TStream): TAntimonyModel;
var
  StringList: TStringList;
  Source: string;
begin
  StringList := TStringList.Create;
  try
    AStream.Position := 0;
    StringList.LoadFromStream(AStream, TEncoding.UTF8);
    Source := StringList.Text;
    Result := ParseFromString(Source);
  finally
    StringList.Free;
  end;
end;

class function TAntimony.ValidateFromString(const ASource: string): string;
var
  Model: TAntimonyModel;
begin
  Result := ''; // Empty string means valid
  try
    Model := ParseFromString(ASource);
    try
      // Additional validation could be added here
      // (e.g., check for undefined species in reactions, etc.)
    finally
      Model.Free;
    end;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

class function TAntimony.ValidateFromFile(const AFilename: string): string;
var
  Source: string;
begin
  Result := '';
  if not TFile.Exists(AFilename) then
  begin
    Result := 'File not found: ' + AFilename;
    Exit;
  end;

  try
    Source := TFile.ReadAllText(AFilename, TEncoding.UTF8);
    Result := ValidateFromString(Source);
  except
    on E: Exception do
      Result := 'Error reading file: ' + E.Message;
  end;
end;

class procedure TAntimony.PrintModelSummary(AModel: TAntimonyModel);
var NumberOfBoundarySpecies : integer;
begin
  if AModel = nil then
  begin
    WriteLn('Model is nil');
    Exit;
  end;

  WriteLn('=== Antimony Model Summary ===');
  WriteLn('Compartments: ', AModel.Compartments.Count);
  for var i := 0 to AModel.Compartments.Count - 1 do
    WriteLn('  - ', AModel.Compartments[i].Id);

  WriteLn('Floating Species: ', AModel.Species.Count);
  for var i := 0 to AModel.Species.Count - 1 do
  begin
    Write('  - ', AModel.Species[i].Id);
    if AModel.Species[i].Compartment <> '' then
      Write(' (in ', AModel.Species[i].Compartment, ')');
    WriteLn;
  end;

  NumberOfBoundarySpecies := 0;
  for var i := 0 to AModel.Species.Count - 1 do
      if AModel.Species[i].IsBoundary then
         inc (NumberOfBoundarySpecies);

  WriteLn('Boundary Species: ' + inttostr (NumberOfBoundarySpecies));
  for var i := 0 to AModel.Species.Count - 1 do
     if AModel.Species[i].IsBoundary then
        WriteLn('  - ', AModel.Species[i].Id);

  WriteLn('Reactions: ', AModel.Reactions.Count);
  for var i := 0 to AModel.Reactions.Count - 1 do
  begin
    Write('  - ');
    if AModel.Reactions[i].Id <> '' then
      Write(AModel.Reactions[i].Id, ': ');
    WriteLn('(', AModel.Reactions[i].Reactants.Count, ' -> ', AModel.Reactions[i].Products.Count, ')');
  end;

  WriteLn('Parameters: ', AModel.GetNumParameters);
  WriteLn('Assignments: ', AModel.Assignments.Count);
  WriteLn('==============================');
end;


class function TAntimony.GetModelStats(AModel: TAntimonyModel): string;
begin
  if AModel = nil then
  begin
    Result := 'Model is nil';
    Exit;
  end;

  Result := Format('Compartments: %d, Species: %d (%d floating, %d boundary), ' +
                   'Reactions: %d, Parameters: %d, Assignments: %d',
    [AModel.Compartments.Count, 
     AModel.Species.Count, 
     AModel.GetNumFloatingSpecies, 
     AModel.GetNumBoundarySpecies,
     AModel.Reactions.Count, 
     AModel.GetNumParameters, 
     AModel.Assignments.Count]);
end;


class function TAntimony.ModelToString(AModel: TAntimonyModel): string;
var
  Output: TStringList;
  I, J: Integer;
  Species: TAntimonySpecies;
  Compartment: TAntimonyCompartment;
  Reaction: TAntimonyReaction;
  Assignment: TAntimonyAssignment;
  Participant: TReactionParticipant;
begin
  Output := TStringList.Create;
  try
    // Model header
    if AModel.Name <> '' then
      Output.Add('model ' + AModel.Name);
    Output.Add('');

    // Compartments
    if AModel.Compartments.Count > 0 then
    begin
      Output.Add('// Compartments');
      for I := 0 to AModel.Compartments.Count - 1 do
      begin
        Compartment := AModel.Compartments[I];
        Output.Add(Format('compartment %s = %g;', [Compartment.id, Compartment.Size]));
      end;
      Output.Add('');
    end;

    // Species
    if AModel.Species.Count > 0 then
    begin
      Output.Add('// Species');
      for I := 0 to AModel.Species.Count - 1 do
      begin
        Species := AModel.Species[I];
        if Species.IsBoundary then
          Output.Add(Format('species %s = %g;', ['$' + Species.Id, Species.InitialValue]))
        else
        begin
          if Species.Compartment <> '' then
            Output.Add(Format('species %s in %s = %g;', [Species.Id, Species.Compartment, Species.InitialValue]))
          else
            Output.Add(Format('species %s = %g;', [Species.Id, Species.InitialValue]));
        end;
      end;
      Output.Add('');
    end;

    // Reactions
    if AModel.Reactions.Count > 0 then
    begin
      Output.Add('// Reactions');
      for I := 0 to AModel.Reactions.Count - 1 do
      begin
        Reaction := AModel.Reactions[I];

        // Build reaction string
        var ReactionStr := Reaction.Id + ': ';

        // Reactants
        for J := 0 to Reaction.Reactants.Count - 1 do
        begin
          Participant := Reaction.Reactants[J];
          if J > 0 then
            ReactionStr := ReactionStr + ' + ';
          if Participant.Stoichiometry <> 1.0 then
            ReactionStr := ReactionStr + FloatToStr(Participant.Stoichiometry) + ' * ';
          ReactionStr := ReactionStr + Participant.SpeciesName;
        end;

        // Arrow
        if Reaction.IsReversible then
          ReactionStr := ReactionStr + ' -> '
        else
          ReactionStr := ReactionStr + ' <-> ';

        // Products
        for J := 0 to Reaction.Products.Count - 1 do
        begin
          Participant := Reaction.Products[J];
          if J > 0 then
            ReactionStr := ReactionStr + ' + ';
          if Participant.Stoichiometry <> 1.0 then
            ReactionStr := ReactionStr + FloatToStr(Participant.Stoichiometry) + ' * ';
          ReactionStr := ReactionStr + Participant.SpeciesName;
        end;

        // Kinetic law
        if Reaction.KineticLaw <> '' then
          ReactionStr := ReactionStr + '; ' + Reaction.KineticLaw;

        Output.Add(ReactionStr + ';');
      end;
      Output.Add('');
    end;

    // Assignments (which include parameters)
    if AModel.Assignments.Count > 0 then
    begin
      Output.Add('// Parameters and Assignments');
      for I := 0 to AModel.Assignments.Count - 1 do
      begin
        Assignment := AModel.Assignments[I];
        Output.Add(Format('%s = %s;', [Assignment.Variable, Assignment.Expression]));
      end;
      Output.Add('');
    end;

    if AModel.Name <> '' then
      Output.Add('end');

    Result := Output.Text;
  finally
    Output.Free;
  end;
end;


{ EAntimonyParseError }

constructor EAntimonyParseError.Create(const AMessage: string; const AToken: string = ''; ALineNumber: Integer = -1; AColumnNumber: Integer = -1);
begin
  inherited Create(AMessage);
  FToken := AToken;
  FLineNumber := ALineNumber;
  FColumnNumber := AColumnNumber;
end;

end.
