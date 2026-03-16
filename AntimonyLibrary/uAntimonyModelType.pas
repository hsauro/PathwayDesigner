unit uAntimonyModelType;

{
  Antimony Model Type Definitions

  This unit defines the data structures used to represent an Antimony model
  after parsing. The model consists of:
    - Species (floating and boundary)
    - Compartments
    - Reactions with kinetic laws
    - Assignments (parameter value assignments with =)
    - Assignment Rules (computed variables with :=)

  Note: Parameters are stored implicitly through Assignments. In Antimony,
  there is no explicit parameter declaration - parameters are declared
  and initialized through assignment statements (e.g., k1 = 0.1).

  Modified to retain AST (Abstract Syntax Tree) for expressions in:
    - TAntimonyAssignment
    - TAntimonyAssignmentRule
    - TAntimonyReaction (already had AST)

  This allows code generators to traverse the AST directly rather than
  re-parsing expression strings.
}

interface

uses
  Classes, SysUtils,
  Generics.Collections,
  uExpressionNode;

type

  // Species definition
  TAntimonySpecies = class
  private
    FId: string;
    FCompartment: string;
    FInitialValue: Double;
    FIsBoundary: Boolean;
    FIsConstant: Boolean;
  public
    constructor Create(const AId: string);
    property Id: string read FId write FId;
    property Compartment: string read FCompartment write FCompartment;
    property InitialValue: Double read FInitialValue write FInitialValue;
    property IsBoundary: Boolean read FIsBoundary write FIsBoundary;
    property IsConstant: Boolean read FIsConstant write FIsConstant;
  end;

  // Compartment definition
  TAntimonyCompartment = class
  private
    FId: string;
    FSize: Double;
    FDimensions: Integer;
  public
    constructor Create(const AId: string);
    property Id: string read FId write FId;
    property Size: Double read FSize write FSize;
    property Dimensions: Integer read FDimensions write FDimensions;
  end;

  // Reaction participant (reactant or product)
  TReactionParticipant = class
  private
    FSpeciesName: string;
    FStoichiometry: Double;
    FIsBoundary: Boolean;
  public
    constructor Create(const ASpeciesName: string; AStoichiometry: Double = 1.0; AIsBoundary: Boolean = False);
    property SpeciesName: string read FSpeciesName write FSpeciesName;
    property Stoichiometry: Double read FStoichiometry write FStoichiometry;
    property IsBoundary: Boolean read FIsBoundary write FIsBoundary;
  end;

  // Reaction definition
  TAntimonyReaction = class
  private
    FId: string;
    FReactants: TObjectList<TReactionParticipant>;
    FProducts: TObjectList<TReactionParticipant>;
    FIsReversible: Boolean;
    FKineticLaw: string;
    FKineticAST: TExpressionNode;
  public
    constructor Create(const AId: string);
    destructor Destroy; override;
    property Id: string read FId write FId;
    property Reactants: TObjectList<TReactionParticipant> read FReactants;
    property Products: TObjectList<TReactionParticipant> read FProducts;
    property IsReversible: Boolean read FIsReversible write FIsReversible;
    property KineticLaw: string read FKineticLaw write FKineticLaw;
    property KineticAST: TExpressionNode read FKineticAST write FKineticAST;
  end;

  // Assignment (simple assignment with =)
  // Used for parameter values, e.g., k1 = 0.1
  // This serves as both parameter declaration and initialization in Antimony
  //
  // Assignments fall into two categories:
  //   - Fundamental: Simple numeric value (k1 = 0.5) - editable at runtime
  //   - Derived: Expression-based (k1 = Vmax/Km) - computed from other values
  TAntimonyAssignment = class
  private
    FVariable: string;
    FExpression: string;
    FExpressionAST: TExpressionNode;
  public
    constructor Create(const AVariable: string; AExpression: TExpressionNode);
    destructor Destroy; override;
    
    // Check if this is a simple numeric assignment (fundamental parameter)
    function IsSimpleValue: Boolean;
    
    // Get numeric value - only valid if IsSimpleValue returns True
    function GetNumericValue: Double;
    
    // Set numeric value - replaces the AST with a simple number node
    // This is only appropriate for fundamental parameters
    procedure SetNumericValue(AValue: Double);
    
    property Variable: string read FVariable write FVariable;
    property Expression: string read FExpression write FExpression;
    property ExpressionAST: TExpressionNode read FExpressionAST;
  end;

  // Assignment rule (computed variable with :=)
  // These are evaluated at each time step before rate laws
  // e.g., Vtot := Vmax * E_total
  TAntimonyAssignmentRule = class
  private
    FVariable: string;
    FExpression: string;
    FExpressionAST: TExpressionNode;
  public
    constructor Create(const AVariable: string; AExpression: TExpressionNode);
    destructor Destroy; override;
    property Variable: string read FVariable write FVariable;
    property Expression: string read FExpression write FExpression;
    property ExpressionAST: TExpressionNode read FExpressionAST;
  end;

  TListOfAssignments = class(TObjectList<TAntimonyAssignment>)
    function FindAssignment(VariableName: string): Integer;
  end;

  TListOfAssignmentRules = class(TObjectList<TAntimonyAssignmentRule>)
    function FindAssignmentRule(VariableName: string): Integer;
  end;

  // Model definition
  TAntimonyModel = class
  private
    FName: string;
    FSpecies: TObjectList<TAntimonySpecies>;
    FCompartments: TObjectList<TAntimonyCompartment>;
    FReactions: TObjectList<TAntimonyReaction>;
    FAssignments: TListOfAssignments;
    FAssignmentRules: TListOfAssignmentRules;
  public
    constructor Create(const AName: string = '');
    destructor Destroy; override;

    // Find methods return index or -1 if not found
    function FindCompartment(CompartmentId: string): Integer;
    function FindSpecies(Id: string): Integer;
    function FindFloatingSpecies(SpeciesId: string): Integer;
    function FindBoundarySpecies(SpeciesId: string): Integer;
    function FindReaction(Id: string): Integer;
    function FindAssignment(VariableName: string): Integer;
    function FindAssignmentRule(VariableName: string): Integer;

    // Utility methods for counting
    function GetNumFloatingSpecies: Integer;
    function GetNumBoundarySpecies: Integer;
    
    // Parameter-related utilities (parameters are stored as assignments)
    function GetNumParameters: Integer;
    function IsParameter(const AName: string): Boolean;

    property Name: string read FName write FName;
    property Species: TObjectList<TAntimonySpecies> read FSpecies;
    property Compartments: TObjectList<TAntimonyCompartment> read FCompartments;
    property Reactions: TObjectList<TAntimonyReaction> read FReactions;
    property Assignments: TListOfAssignments read FAssignments;
    property AssignmentRules: TListOfAssignmentRules read FAssignmentRules;
  end;

  // Exception class for parser errors
  EAntimonyParserError = class(Exception)
  private
    FLine: Integer;
    FColumn: Integer;
  public
    constructor Create(const AMessage: string; ALine, AColumn: Integer);
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
  end;

implementation

// TAntimonySpecies implementation

constructor TAntimonySpecies.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
  FCompartment := '';
  FInitialValue := 0.0;
  FIsBoundary := False;
  FIsConstant := False;
end;

// TAntimonyCompartment implementation

constructor TAntimonyCompartment.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
  FSize := 1.0;
  FDimensions := 3;
end;

// TReactionParticipant implementation

constructor TReactionParticipant.Create(const ASpeciesName: string;
  AStoichiometry: Double; AIsBoundary: Boolean);
begin
  inherited Create;
  FSpeciesName := ASpeciesName;
  FStoichiometry := AStoichiometry;
  FIsBoundary := AIsBoundary;
end;

// TAntimonyReaction implementation

constructor TAntimonyReaction.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
  FReactants := TObjectList<TReactionParticipant>.Create(True);
  FProducts := TObjectList<TReactionParticipant>.Create(True);
  FIsReversible := False;
  FKineticLaw := '';
  FKineticAST := nil;
end;

destructor TAntimonyReaction.Destroy;
begin
  FReactants.Free;
  FProducts.Free;
  FKineticAST.Free;
  inherited Destroy;
end;

// TAntimonyAssignment implementation

constructor TAntimonyAssignment.Create(const AVariable: string;
  AExpression: TExpressionNode);
begin
  inherited Create;
  FVariable := AVariable;
  FExpressionAST := AExpression;  // Take ownership of AST
  if Assigned(AExpression) then
    FExpression := AExpression.ToString
  else
    FExpression := '';
end;

destructor TAntimonyAssignment.Destroy;
begin
  FExpressionAST.Free;
  inherited Destroy;
end;

function TAntimonyAssignment.IsSimpleValue: Boolean;
begin
  Result := Assigned(FExpressionAST) and FExpressionAST.IsNumber;
end;

function TAntimonyAssignment.GetNumericValue: Double;
begin
  if not IsSimpleValue then
    raise Exception.CreateFmt('Assignment "%s" is not a simple numeric value', [FVariable]);
  Result := FExpressionAST.GetNumberValue;
end;

procedure TAntimonyAssignment.SetNumericValue(AValue: Double);
begin
  // Free the old AST and replace with a simple number node
  FExpressionAST.Free;
  FExpressionAST := TExpressionNode.CreateNumberExpression(AValue);
  FExpression := FExpressionAST.ToString;
end;

// TAntimonyAssignmentRule implementation

constructor TAntimonyAssignmentRule.Create(const AVariable: string;
  AExpression: TExpressionNode);
begin
  inherited Create;
  FVariable := AVariable;
  FExpressionAST := AExpression;  // Take ownership of AST
  if Assigned(AExpression) then
    FExpression := AExpression.ToString
  else
    FExpression := '';
end;

destructor TAntimonyAssignmentRule.Destroy;
begin
  FExpressionAST.Free;
  inherited Destroy;
end;

// TListOfAssignments implementation

function TListOfAssignments.FindAssignment(VariableName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to Count - 1 do
  begin
    if VariableName = Items[i].FVariable then
      Exit(i);
  end;
end;

// TListOfAssignmentRules implementation

function TListOfAssignmentRules.FindAssignmentRule(VariableName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to Count - 1 do
  begin
    if VariableName = Items[i].FVariable then
      Exit(i);
  end;
end;

// TAntimonyModel implementation

constructor TAntimonyModel.Create(const AName: string);
var
  c: TAntimonyCompartment;
begin
  inherited Create;
  FName := AName;
  FSpecies := TObjectList<TAntimonySpecies>.Create(True);
  FCompartments := TObjectList<TAntimonyCompartment>.Create(True);
  FReactions := TObjectList<TAntimonyReaction>.Create(True);
  FAssignments := TListOfAssignments.Create(True);
  FAssignmentRules := TListOfAssignmentRules.Create(True);

  // Create a default compartment
  c := TAntimonyCompartment.Create('defaultCompartment');
  c.Size := 1.0;
  c.Dimensions := 3;
  FCompartments.Add(c);
end;

destructor TAntimonyModel.Destroy;
begin
  FSpecies.Free;
  FCompartments.Free;
  FReactions.Free;
  FAssignments.Free;
  FAssignmentRules.Free;
  inherited Destroy;
end;

function TAntimonyModel.FindCompartment(CompartmentId: string): Integer;
var
  i: Integer;
begin
  for i := 0 to Compartments.Count - 1 do
    if Compartments[i].FId = CompartmentId then
      Exit(i);
  Exit(-1);
end;

function TAntimonyModel.FindSpecies(Id: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to Species.Count - 1 do
    if Id = Species[i].FId then
      Exit(i);
end;

function TAntimonyModel.FindFloatingSpecies(SpeciesId: string): Integer;
var
  i: Integer;
begin
  for i := 0 to Species.Count - 1 do
    if not Species[i].IsBoundary then
      if Species[i].FId = SpeciesId then
        Exit(i);
  Exit(-1);
end;

function TAntimonyModel.FindBoundarySpecies(SpeciesId: string): Integer;
var
  i: Integer;
begin
  for i := 0 to Species.Count - 1 do
    if (Species[i].FId = SpeciesId) and (Species[i].IsBoundary) then
      Exit(i);
  Exit(-1);
end;

function TAntimonyModel.FindReaction(Id: string): Integer;
var
  i: Integer;
begin
  for i := 0 to Reactions.Count - 1 do
    if Reactions[i].FId = Id then
      Exit(i);
  Exit(-1);
end;

function TAntimonyModel.FindAssignment(VariableName: string): Integer;
begin
  Result := FAssignments.FindAssignment(VariableName);
end;

function TAntimonyModel.FindAssignmentRule(VariableName: string): Integer;
begin
  Result := FAssignmentRules.FindAssignmentRule(VariableName);
end;

function TAntimonyModel.GetNumFloatingSpecies: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Species.Count - 1 do
    if not Species[i].IsBoundary then
      Inc(Result);
end;

function TAntimonyModel.GetNumBoundarySpecies: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Species.Count - 1 do
    if Species[i].IsBoundary then
      Inc(Result);
end;

function TAntimonyModel.GetNumParameters: Integer;
var
  i: Integer;
begin
  // Count assignments that are not species (these are parameters)
  Result := 0;
  for i := 0 to Assignments.Count - 1 do
    if FindSpecies(Assignments[i].Variable) = -1 then
      Inc(Result);
end;

function TAntimonyModel.IsParameter(const AName: string): Boolean;
begin
  // A name is a parameter if it has an assignment and is not a species
  Result := (FindAssignment(AName) >= 0) and (FindSpecies(AName) = -1);
end;

// EAntimonyParserError implementation

constructor EAntimonyParserError.Create(const AMessage: string; ALine, AColumn: Integer);
begin
  inherited Create(Format('%s at line %d, column %d', [AMessage, ALine, AColumn]));
  FLine := ALine;
  FColumn := AColumn;
end;

end.
