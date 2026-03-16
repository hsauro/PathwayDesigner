unit uLibSBMLHelpers;

{
  Helper functions and classes to make working with LibSBML bindings easier
  This unit provides high-level wrapper classes and utility functions
}

interface

uses
  SysUtils, Classes, uLibSBMLBindings;

type
  // Exception class for SBML-related errors
  ESBMLException = class(Exception);

  // Helper class for managing compartments
  TSBMLCompartment = class
  private
    FCompartment: PCompartment;
    FModel: PModel;

    function  GetId: string;
    procedure SetId(const Value: string);
    function  GetName: string;
    procedure SetName(const Value: string);
    function  GetSize: Double;
    procedure SetSize(const Value: Double);
    function  GetSpatialDimensions: Cardinal;
    procedure SetSpatialDimensions(const Value: Cardinal);
    function  GetConstant: Boolean;
    procedure SetConstant(const Value: Boolean);
  public
    constructor Create(Model: PModel; const Id: string);
    constructor CreateFromExisting(Model: PModel; Compartment: PCompartment);

    procedure SetProperties(const Name: string; Size: Double = 1.0;
                          Dimensions: Cardinal = 3; IsConstant: Boolean = True);

    property Handle: PCompartment read FCompartment;
    property Id: string read GetId write SetId;
    property Name: string read GetName write SetName;
    property Size: Double read GetSize write SetSize;
    property SpatialDimensions: Cardinal read GetSpatialDimensions write SetSpatialDimensions;
    property IsConstant: Boolean read GetConstant write SetConstant;
  end;

  // Helper class for managing species
  TSBMLSpecies = class
  private
    FSpecies: PSpecies;
    FModel: PModel;
    function GetId: string;
    procedure SetId(const Value: string);
    function GetName: string;
    procedure SetName(const Value: string);
    function GetCompartment: string;
    procedure SetCompartment(const Value: string);
    function GetInitialConcentration: Double;
    procedure SetInitialConcentration(const Value: Double);
    function GetInitialAmount: Double;
    procedure SetInitialAmount(const Value: Double);
    function GetHasOnlySubstanceUnits: Boolean;
    procedure SetHasOnlySubstanceUnits(const Value: Boolean);
    function GetBoundaryCondition: Boolean;
    procedure SetBoundaryCondition(const Value: Boolean);
    function GetConstant: Boolean;
    procedure SetConstant(const Value: Boolean);
  public
    constructor Create(Model: PModel; const Id: string);
    constructor CreateFromExisting(Model: PModel; Species: PSpecies);

    procedure SetProperties(const Name, CompartmentId: string;
                          InitialConcentration: Double = 0.0;
                          HasOnlySubstanceUnits: Boolean = False;
                          BoundaryCondition: Boolean = False;
                          IsConstant: Boolean = False);

    property Handle: PSpecies read FSpecies;
    property Id: string read GetId write SetId;
    property Name: string read GetName write SetName;
    property CompartmentId: string read GetCompartment write SetCompartment;
    property InitialConcentration: Double read GetInitialConcentration write SetInitialConcentration;
    property InitialAmount: Double read GetInitialAmount write SetInitialAmount;
    property HasOnlySubstanceUnits: Boolean read GetHasOnlySubstanceUnits write SetHasOnlySubstanceUnits;
    property BoundaryCondition: Boolean read GetBoundaryCondition write SetBoundaryCondition;
    property IsConstant: Boolean read GetConstant write SetConstant;

  end;

  // Helper class for managing parameters (global model parameters only)
  TSBMLParameter = class
  private
    FParameter: PParameter;
    FModel: PModel;
    function GetId: string;
    procedure SetId(const Value: string);
    function GetName: string;
    procedure SetName(const Value: string);
    function GetValue: Double;
    procedure SetValue(const Value: Double);
    function GetUnits: string;
    procedure SetUnits(const Value: string);
    function GetConstant: Boolean;
    procedure SetConstant(const Value: Boolean);
  public
    constructor Create(Model: PModel; const Id: string);
    constructor CreateFromExisting(Model: PModel; Parameter: PParameter);

    procedure SetProperties(const Name: string; Value: Double;
                          const Units: string = ''; IsConstant: Boolean = True);

    property Handle: PParameter read FParameter;
    property Id: string read GetId write SetId;
    property Name: string read GetName write SetName;
    property Value: Double read GetValue write SetValue;
    property Units: string read GetUnits write SetUnits;
    property IsConstant: Boolean read GetConstant write SetConstant;
  end;

  // Helper class for managing reactions
  TSBMLReaction = class
  private
    FReaction: PReaction;
    FModel: PModel;
    function GetId: string;
    procedure SetId(const Value: string);
    function GetName: string;
    procedure SetName(const Value: string);
    function GetReversible: Boolean;
    procedure SetReversible(const Value: Boolean);
    function GetFast: Boolean;
    procedure SetFast(const Value: Boolean);
  public
    constructor Create(Model: PModel; const Id: string);
    constructor CreateFromExisting(Model: PModel; Reaction: PReaction);

    procedure SetProperties(const Name: string; Reversible: Boolean = True; Fast: Boolean = False);

    function AddReactant(const SpeciesId: string; Stoichiometry: Double = 1.0): PSpeciesReference;
    function AddProduct(const SpeciesId: string; Stoichiometry: Double = 1.0): PSpeciesReference;
    function AddModifier(const SpeciesId: string): PSpeciesReference;

    procedure SetKineticLaw(const Formula: string);
    function GetKineticLawFormula: string;

    function GetReactionEquation: string;

    property Handle: PReaction read FReaction;
    property Id: string read GetId write SetId;
    property Name: string read GetName write SetName;
    property Reversible: Boolean read GetReversible write SetReversible;
    property Fast: Boolean read GetFast write SetFast;

  end;

  // Enhanced SBML document class with helper methods
  TSBMLModelManager = class(TSBMLDocument)
  private
    FCompartments: TList;
    FSpeciesList: TList;
    FReactions: TList;
    FParameters: TList;
  public
    constructor Create(Level, Version: Integer);
    destructor Destroy; override;

    // Compartment management
    function CreateCompartment(const Id, Name: string; Size: Double = 1.0): TSBMLCompartment;
    function GetCompartment(const Id: string): TSBMLCompartment;
    function GetCompartmentCount: Integer;
    function GetCompartmentByIndex(Index: Integer): TSBMLCompartment;

    // Species management
    function CreateSpecies(const Id, Name, CompartmentId: string;
                          InitialConcentration: Double = 0.0): TSBMLSpecies;
    function GetSpecies(const Id: string): TSBMLSpecies;
    function GetSpeciesCount: Integer;
    function GetSpeciesByIndex(Index: Integer): TSBMLSpecies;

    // Parameter management
    function CreateParameter(const Id, Name: string; Value: Double;
                           const Units: string = ''): TSBMLParameter;
    function GetParameter(const Id: string): TSBMLParameter;
    function GetParameterCount: Integer;
    function GetParameterByIndex(Index: Integer): TSBMLParameter;

    // Reaction management
    function CreateReaction(const Id, Name: string): TSBMLReaction;
    function GetReaction(const Id: string): TSBMLReaction;
    function GetReactionCount: Integer;
    function GetReactionByIndex(Index: Integer): TSBMLReaction;

    // Utility methods
    function GetModelSummary: string;
    procedure ClearAllObjects;

    function GetSBML : string;
  end;

  // Utility functions
  function SBMLLevelVersionToString(Level, Version: Integer): string;
  function ValidateSBMLId(const Id: string): Boolean;
  function SanitizeSBMLId(const Id: string): string;

implementation

// ============================================================================
// Utility Functions
// ============================================================================

function SBMLLevelVersionToString(Level, Version: Integer): string;
begin
  Result := Format('SBML Level %d Version %d', [Level, Version]);
end;

function ValidateSBMLId(const Id: string): Boolean;
var
  i: Integer;
  c: Char;
begin
  Result := False;

  if Length(Id) = 0 then Exit;

  // First character must be letter or underscore
  c := Id[1];
  if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or (c = '_')) then
    Exit;

  // Remaining characters must be letters, digits, or underscores
  for i := 2 to Length(Id) do
  begin
    c := Id[i];
    if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
            ((c >= '0') and (c <= '9')) or (c = '_')) then
      Exit;
  end;

  Result := True;
end;

function SanitizeSBMLId(const Id: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';

  if Length(Id) = 0 then
  begin
    Result := 'id';
    Exit;
  end;

  for i := 1 to Length(Id) do
  begin
    c := Id[i];
    if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or (c = '_') or
       ((i > 1) and ((c >= '0') and (c <= '9'))) then
      Result := Result + c
    else if c = ' ' then
      Result := Result + '_'
    else if c = '-' then
      Result := Result + '_';
  end;

  // Ensure first character is valid
  if Length(Result) > 0 then
  begin
    c := Result[1];
    if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or (c = '_')) then
      Result := '_' + Result;
  end
  else
    Result := 'id';
end;

// ============================================================================
// TSBMLCompartment Implementation
// ============================================================================

constructor TSBMLCompartment.Create(Model: PModel; const Id: string);
begin
  FModel := Model;
  FCompartment := Model_createCompartment(Model);
  if FCompartment = nil then
    raise ESBMLException.Create('Failed to create compartment');
  SetId(Id);
end;

constructor TSBMLCompartment.CreateFromExisting(Model: PModel; Compartment: PCompartment);
begin
  FModel := Model;
  FCompartment := Compartment;
end;

procedure TSBMLCompartment.SetProperties(const Name: string; Size: Double;
                                        Dimensions: Cardinal; IsConstant: Boolean);
begin
  SetName(Name);
  SetSize(Size);
  SetSpatialDimensions(Dimensions);
  SetConstant(IsConstant);
end;

function TSBMLCompartment.GetId: string;
begin
  Result := PAnsiCharToString(Compartment_getId(FCompartment));
end;

procedure TSBMLCompartment.SetId(const Value: string);
begin
  Compartment_setId(FCompartment, StringToPAnsiChar(Value));
end;

function TSBMLCompartment.GetName: string;
begin
  Result := PAnsiCharToString(Compartment_getName(FCompartment));
end;

procedure TSBMLCompartment.SetName(const Value: string);
begin
  Compartment_setName(FCompartment, StringToPAnsiChar(Value));
end;

function TSBMLCompartment.GetSize: Double;
begin
  Result := Compartment_getSize(FCompartment);
end;

procedure TSBMLCompartment.SetSize(const Value: Double);
begin
  Compartment_setSize(FCompartment, Value);
end;

function TSBMLCompartment.GetSpatialDimensions: Cardinal;
begin
  Result := Compartment_getSpatialDimensions(FCompartment);
end;

procedure TSBMLCompartment.SetSpatialDimensions(const Value: Cardinal);
begin
  Compartment_setSpatialDimensions(FCompartment, Value);
end;

function TSBMLCompartment.GetConstant: Boolean;
begin
  Result := Compartment_getConstant(FCompartment) <> 0;
end;

procedure TSBMLCompartment.SetConstant(const Value: Boolean);
begin
  Compartment_setConstant(FCompartment, Integer(Value));
end;

// ============================================================================
// TSBMLSpecies Implementation
// ============================================================================

constructor TSBMLSpecies.Create(Model: PModel; const Id: string);
begin
  FModel := Model;
  FSpecies := Model_createSpecies(Model);
  if FSpecies = nil then
    raise ESBMLException.Create('Failed to create species');
  SetId(Id);
end;

constructor TSBMLSpecies.CreateFromExisting(Model: PModel; Species: PSpecies);
begin
  FModel := Model;
  FSpecies := Species;
end;

procedure TSBMLSpecies.SetProperties(const Name, CompartmentId: string;
                                    InitialConcentration: Double;
                                    HasOnlySubstanceUnits, BoundaryCondition, IsConstant: Boolean);
begin
  SetName(Name);
  SetCompartment(CompartmentId);
  SetInitialConcentration(InitialConcentration);
  SetHasOnlySubstanceUnits(HasOnlySubstanceUnits);
  SetBoundaryCondition(BoundaryCondition);
  SetConstant(IsConstant);
end;

function TSBMLSpecies.GetId: string;
begin
  Result := PAnsiCharToString(Species_getId(FSpecies));
end;

procedure TSBMLSpecies.SetId(const Value: string);
begin
  Species_setId(FSpecies, StringToPAnsiChar(Value));
end;

function TSBMLSpecies.GetName: string;
begin
  Result := PAnsiCharToString(Species_getName(FSpecies));
end;

procedure TSBMLSpecies.SetName(const Value: string);
begin
  Species_setName(FSpecies, StringToPAnsiChar(Value));
end;

function TSBMLSpecies.GetCompartment: string;
begin
  Result := PAnsiCharToString(Species_getCompartment(FSpecies));
end;

procedure TSBMLSpecies.SetCompartment(const Value: string);
begin
  Species_setCompartment(FSpecies, StringToPAnsiChar(Value));
end;

function TSBMLSpecies.GetInitialConcentration: Double;
begin
  Result := Species_getInitialConcentration(FSpecies);
end;

procedure TSBMLSpecies.SetInitialConcentration(const Value: Double);
begin
  Species_setInitialConcentration(FSpecies, Value);
end;

function TSBMLSpecies.GetInitialAmount: Double;
begin
  Result := Species_getInitialAmount(FSpecies);
end;

procedure TSBMLSpecies.SetInitialAmount(const Value: Double);
begin
  Species_setInitialAmount(FSpecies, Value);
end;

function TSBMLSpecies.GetHasOnlySubstanceUnits: Boolean;
begin
  Result := Species_getHasOnlySubstanceUnits(FSpecies) <> 0;
end;

procedure TSBMLSpecies.SetHasOnlySubstanceUnits(const Value: Boolean);
begin
  Species_setHasOnlySubstanceUnits(FSpecies, Integer(Value));
end;

function TSBMLSpecies.GetBoundaryCondition: Boolean;
begin
  Result := Species_getBoundaryCondition(FSpecies) <> 0;
end;

procedure TSBMLSpecies.SetBoundaryCondition(const Value: Boolean);
begin
  Species_setBoundaryCondition(FSpecies, Integer(Value));
end;

function TSBMLSpecies.GetConstant: Boolean;
begin
  Result := Species_getConstant(FSpecies) <> 0;
end;

procedure TSBMLSpecies.SetConstant(const Value: Boolean);
begin
  Species_setConstant(FSpecies, Integer(Value));
end;

// ============================================================================
// TSBMLParameter Implementation
// ============================================================================

constructor TSBMLParameter.Create(Model: PModel; const Id: string);
begin
  FModel := Model;
  FParameter := Model_createParameter(Model);
  if FParameter = nil then
    raise ESBMLException.Create('Failed to create parameter');
  SetId(Id);
end;

constructor TSBMLParameter.CreateFromExisting(Model: PModel; Parameter: PParameter);
begin
  FModel := Model;
  FParameter := Parameter;
end;

procedure TSBMLParameter.SetProperties(const Name: string; Value: Double;
                                      const Units: string; IsConstant: Boolean);
begin
  SetName(Name);
  SetValue(Value);
  SetUnits(Units);
  SetConstant(IsConstant);
end;

function TSBMLParameter.GetId: string;
begin
  Result := PAnsiCharToString(Parameter_getId(FParameter));
end;

procedure TSBMLParameter.SetId(const Value: string);
begin
  Parameter_setId(FParameter, StringToPAnsiChar(Value));
end;

function TSBMLParameter.GetName: string;
begin
  Result := PAnsiCharToString(Parameter_getName(FParameter));
end;

procedure TSBMLParameter.SetName(const Value: string);
begin
  Parameter_setName(FParameter, StringToPAnsiChar(Value));
end;

function TSBMLParameter.GetValue: Double;
begin
  Result := Parameter_getValue(FParameter);
end;

procedure TSBMLParameter.SetValue(const Value: Double);
begin
  Parameter_setValue(FParameter, Value);
end;

function TSBMLParameter.GetUnits: string;
begin
  Result := PAnsiCharToString(Parameter_getUnits(FParameter));
end;

procedure TSBMLParameter.SetUnits(const Value: string);
begin
  Parameter_setUnits(FParameter, StringToPAnsiChar(Value));
end;

function TSBMLParameter.GetConstant: Boolean;
begin
  Result := Parameter_getConstant(FParameter) <> 0;
end;

procedure TSBMLParameter.SetConstant(const Value: Boolean);
begin
  Parameter_setConstant(FParameter, Integer(Value));
end;

// ============================================================================
// TSBMLReaction Implementation
// ============================================================================

constructor TSBMLReaction.Create(Model: PModel; const Id: string);
begin
  FModel := Model;
  FReaction := Model_createReaction(Model);
  if FReaction = nil then
    raise ESBMLException.Create('Failed to create reaction');
  SetId(Id);
end;

constructor TSBMLReaction.CreateFromExisting(Model: PModel; Reaction: PReaction);
begin
  FModel := Model;
  FReaction := Reaction;
end;

procedure TSBMLReaction.SetProperties(const Name: string; Reversible, Fast: Boolean);
begin
  SetName(Name);
  SetReversible(Reversible);
  SetFast(Fast);
end;

function TSBMLReaction.AddReactant(const SpeciesId: string; Stoichiometry: Double): PSpeciesReference;
begin
  Result := Reaction_createReactant(FReaction);
  SpeciesReference_setSpecies(Result, StringToPAnsiChar(SpeciesId));
  SpeciesReference_setStoichiometry(Result, Stoichiometry);
  SpeciesReference_setConstant(Result, 1);
end;

function TSBMLReaction.AddProduct(const SpeciesId: string; Stoichiometry: Double): PSpeciesReference;
begin
  Result := Reaction_createProduct(FReaction);
  SpeciesReference_setSpecies(Result, StringToPAnsiChar(SpeciesId));
  SpeciesReference_setStoichiometry(Result, Stoichiometry);
  SpeciesReference_setConstant(Result, 1);
end;

function TSBMLReaction.AddModifier(const SpeciesId: string): PSpeciesReference;
begin
  Result := Reaction_createModifier(FReaction);
  SpeciesReference_setSpecies(Result, StringToPAnsiChar(SpeciesId));
end;

procedure TSBMLReaction.SetKineticLaw(const Formula: string);
var
  KineticLaw: PKineticLaw;
begin
  KineticLaw := Reaction_createKineticLaw(FReaction);
  KineticLaw_setFormula(KineticLaw, StringToPAnsiChar(Formula));
end;

function TSBMLReaction.GetKineticLawFormula: string;
var
  KineticLaw: PKineticLaw;
begin
  KineticLaw := Reaction_getKineticLaw(FReaction);
  if KineticLaw <> nil then
    Result := PAnsiCharToString(KineticLaw_getFormula(KineticLaw))
  else
    Result := '';
end;

function TSBMLReaction.GetReactionEquation: string;
var
  i: Cardinal;
  SpeciesRef: PSpeciesReference;
  Stoich: Double;
  SpeciesId: string;
begin
  Result := '';

  // Add reactants
  for i := 0 to Reaction_getNumReactants(FReaction) - 1 do
  begin
    SpeciesRef := Reaction_getReactant(FReaction, i);
    if i > 0 then Result := Result + ' + ';

    Stoich := SpeciesReference_getStoichiometry(SpeciesRef);
    SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SpeciesRef));

    if Stoich <> 1.0 then
      Result := Result + FloatToStr(Stoich) + ' ';
    Result := Result + SpeciesId;
  end;

  // Add arrow
  if GetReversible then
    Result := Result + ' <-> '
  else
    Result := Result + ' -> ';

  // Add products
  for i := 0 to Reaction_getNumProducts(FReaction) - 1 do
  begin
    SpeciesRef := Reaction_getProduct(FReaction, i);
    if i > 0 then Result := Result + ' + ';

    Stoich := SpeciesReference_getStoichiometry(SpeciesRef);
    SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SpeciesRef));

    if Stoich <> 1.0 then
      Result := Result + FloatToStr(Stoich) + ' ';
    Result := Result + SpeciesId;
  end;
end;

function TSBMLReaction.GetId: string;
begin
  Result := PAnsiCharToString(Reaction_getId(FReaction));
end;

procedure TSBMLReaction.SetId(const Value: string);
begin
  Reaction_setId(FReaction, StringToPAnsiChar(Value));
end;

function TSBMLReaction.GetName: string;
begin
  Result := PAnsiCharToString(Reaction_getName(FReaction));
end;

procedure TSBMLReaction.SetName(const Value: string);
begin
  Reaction_setName(FReaction, StringToPAnsiChar(Value));
end;

function TSBMLReaction.GetReversible: Boolean;
begin
  Result := Reaction_getReversible(FReaction) <> 0;
end;

procedure TSBMLReaction.SetReversible(const Value: Boolean);
begin
  Reaction_setReversible(FReaction, Integer(Value));
end;

function TSBMLReaction.GetFast: Boolean;
begin
  Result := Reaction_getFast(FReaction) <> 0;
end;

procedure TSBMLReaction.SetFast(const Value: Boolean);
begin
  Reaction_setFast(FReaction, Integer(Value));
end;

// ============================================================================
// TSBMLModelManager Implementation
// ============================================================================

constructor TSBMLModelManager.Create(Level, Version: Integer);
begin
  inherited Create(Level, Version);
  FCompartments := TList.Create;
  FSpeciesList := TList.Create;
  FReactions := TList.Create;
  FParameters := TList.Create;
end;

destructor TSBMLModelManager.Destroy;
begin
  ClearAllObjects;
  FCompartments.Free;
  FSpeciesList.Free;
  FReactions.Free;
  FParameters.Free;
  inherited Destroy;
end;

procedure TSBMLModelManager.ClearAllObjects;
var
  i: Integer;
begin
  for i := 0 to FCompartments.Count - 1 do
    TSBMLCompartment(FCompartments[i]).Free;
  FCompartments.Clear;

  for i := 0 to FSpeciesList.Count - 1 do
    TSBMLSpecies(FSpeciesList[i]).Free;
  FSpeciesList.Clear;

  for i := 0 to FReactions.Count - 1 do
    TSBMLReaction(FReactions[i]).Free;
  FReactions.Clear;

  for i := 0 to FParameters.Count - 1 do
    TSBMLParameter(FParameters[i]).Free;
  FParameters.Clear;
end;


function TSBMLModelManager.GetSBML : string;
begin
  result := PAnsiCharToString (writeSBMLToString(Document));
end;


function TSBMLModelManager.CreateCompartment(const Id, Name: string; Size: Double): TSBMLCompartment;
begin
  if GetModel = nil then CreateModel;

  Result := TSBMLCompartment.Create(GetModel, Id);
  Result.SetProperties(Name, Size);
  FCompartments.Add(Result);
end;

function TSBMLModelManager.GetCompartment(const Id: string): TSBMLCompartment;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FCompartments.Count - 1 do
  begin
    if TSBMLCompartment(FCompartments[i]).Id = Id then
    begin
      Result := TSBMLCompartment(FCompartments[i]);
      Break;
    end;
  end;
end;

function TSBMLModelManager.GetCompartmentCount: Integer;
begin
  Result := FCompartments.Count;
end;

function TSBMLModelManager.GetCompartmentByIndex(Index: Integer): TSBMLCompartment;
begin
  if (Index >= 0) and (Index < FCompartments.Count) then
    Result := TSBMLCompartment(FCompartments[Index])
  else
    Result := nil;
end;

function TSBMLModelManager.CreateSpecies(const Id, Name, CompartmentId: string;
                                        InitialConcentration: Double): TSBMLSpecies;
begin
  if GetModel = nil then CreateModel;

  Result := TSBMLSpecies.Create(GetModel, Id);
  Result.SetProperties(Name, CompartmentId, InitialConcentration);
  FSpeciesList.Add(Result);
end;

function TSBMLModelManager.GetSpecies(const Id: string): TSBMLSpecies;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FSpeciesList.Count - 1 do
  begin
    if TSBMLSpecies(FSpeciesList[i]).Id = Id then
    begin
      Result := TSBMLSpecies(FSpeciesList[i]);
      Break;
    end;
  end;
end;

function TSBMLModelManager.GetSpeciesCount: Integer;
begin
  Result := FSpeciesList.Count;
end;

function TSBMLModelManager.GetSpeciesByIndex(Index: Integer): TSBMLSpecies;
begin
  if (Index >= 0) and (Index < FSpeciesList.Count) then
    Result := TSBMLSpecies(FSpeciesList[Index])
  else
    Result := nil;
end;

function TSBMLModelManager.CreateParameter(const Id, Name: string; Value: Double;
                                         const Units: string): TSBMLParameter;
begin
  if GetModel = nil then CreateModel;

  Result := TSBMLParameter.Create(GetModel, Id);
  Result.SetProperties(Name, Value, Units);
  FParameters.Add(Result);
end;

function TSBMLModelManager.GetParameter(const Id: string): TSBMLParameter;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FParameters.Count - 1 do
  begin
    if TSBMLParameter(FParameters[i]).Id = Id then
    begin
      Result := TSBMLParameter(FParameters[i]);
      Break;
    end;
  end;
end;

function TSBMLModelManager.GetParameterCount: Integer;
begin
  Result := FParameters.Count;
end;

function TSBMLModelManager.GetParameterByIndex(Index: Integer): TSBMLParameter;
begin
  if (Index >= 0) and (Index < FParameters.Count) then
    Result := TSBMLParameter(FParameters[Index])
  else
    Result := nil;
end;

function TSBMLModelManager.CreateReaction(const Id, Name: string): TSBMLReaction;
begin
  if GetModel = nil then CreateModel;

  Result := TSBMLReaction.Create(GetModel, Id);
  Result.SetProperties(Name);
  FReactions.Add(Result);
end;

function TSBMLModelManager.GetReaction(const Id: string): TSBMLReaction;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FReactions.Count - 1 do
  begin
    if TSBMLReaction(FReactions[i]).Id = Id then
    begin
      Result := TSBMLReaction(FReactions[i]);
      Break;
    end;
  end;
end;

function TSBMLModelManager.GetReactionCount: Integer;
begin
  Result := FReactions.Count;
end;

function TSBMLModelManager.GetReactionByIndex(Index: Integer): TSBMLReaction;
begin
  if (Index >= 0) and (Index < FReactions.Count) then
    Result := TSBMLReaction(FReactions[Index])
  else
    Result := nil;
end;

function TSBMLModelManager.GetModelSummary: string;
var
  i: Integer;
  Comp: TSBMLCompartment;
  Spec: TSBMLSpecies;
  Rxn: TSBMLReaction;
  Param: TSBMLParameter;
begin
  Result := Format('SBML Model Summary'#13#10 +
                   '=================='#13#10 +
                   'Model ID: %s'#13#10 +
                   'Model Name: %s'#13#10#13#10 +
                   'Compartments (%d):'#13#10,
                   [GetModelId, GetModelName, GetCompartmentCount]);

  for i := 0 to GetCompartmentCount - 1 do
  begin
    Comp := GetCompartmentByIndex(i);
    Result := Result + Format('  %s (%s) - Size: %.2f, Dimensions: %d'#13#10,
                              [Comp.Id, Comp.Name, Comp.Size, Comp.SpatialDimensions]);
  end;

  Result := Result + Format(#13#10'Species (%d):'#13#10, [GetSpeciesCount]);
  for i := 0 to GetSpeciesCount - 1 do
  begin
    Spec := GetSpeciesByIndex(i);
    Result := Result + Format('  %s (%s) in %s - Initial: %.3f'#13#10,
                              [Spec.Id, Spec.Name, Spec.CompartmentId, Spec.InitialConcentration]);
  end;

  Result := Result + Format(#13#10'Parameters (%d):'#13#10, [GetParameterCount]);
  for i := 0 to GetParameterCount - 1 do
  begin
    Param := GetParameterByIndex(i);
    if Param.Units <> '' then
      Result := Result + Format('  %s (%s) = %.6g %s'#13#10,
                                [Param.Id, Param.Name, Param.Value, Param.Units])
    else
      Result := Result + Format('  %s (%s) = %.6g'#13#10,
                                [Param.Id, Param.Name, Param.Value]);
  end;

  Result := Result + Format(#13#10'Reactions (%d):'#13#10, [GetReactionCount]);
  for i := 0 to GetReactionCount - 1 do
  begin
    Rxn := GetReactionByIndex(i);
    Result := Result + Format('  %s (%s): %s'#13#10,
                              [Rxn.Id, Rxn.Name, Rxn.GetReactionEquation]);
    if Rxn.GetKineticLawFormula <> '' then
      Result := Result + Format('    Kinetics: %s'#13#10, [Rxn.GetKineticLawFormula]);
  end;
end;

end.
