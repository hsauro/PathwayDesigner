unit uModelState;

{
  Model State for Runtime Simulation (Performance Optimized)

  This unit provides a runtime state container for simulating Antimony/SBML models.
  It separates the model definition (TAntimonyModel) from the mutable state during
  simulation.

  PERFORMANCE DESIGN:
    - Species and parameter values are stored in contiguous TArray<Double>
    - Direct array access via properties (no copying)
    - Indexed access methods marked inline for inner-loop performance
    - Name lookups use dictionary for O(1) access
    - Named access methods provided for convenience (use outside inner loops)

  SPECIES HANDLING:
    - Floating Species: State variables that change during simulation (integrated)
    - Boundary Species: Fixed external inputs (not integrated, but can be modified)
    - Separate arrays allow integrators to work only with floating species
    - Both are accessible for expression evaluation (kinetic laws)

  Key concepts:
    - Fundamental Parameters: Simple numeric assignments (k1 = 0.5) that can be
      modified during simulation. These are the "knobs" users can adjust.
    - Derived Quantities: Expression-based assignments (k1 = Vmax/Km) that are
      computed from other values. These are read-only during simulation.
    - Floating Species: Concentrations that evolve over time (ODE state variables)
    - Boundary Species: Fixed concentrations (external inputs, not integrated)
    - Compartment Sizes: Current volumes of compartments.
    - Reactions: Tracked for rates array layout in C code generation.

  Usage for integration:
    State := TModelState.Create(Model);

    // Direct array access - floating species only for integration
    Y := State.FloatingSpecies;  // These are your ODE state variables
    P := State.Parameters;
    
    for Step := 1 to NumSteps do
    begin
      ComputeDerivatives(Y, P, State.BoundarySpecies, Dydt);
      // Integrator modifies Y in place
    end;
}

interface

uses
  System.SysUtils,
  System.Math,
  Generics.Collections,
  uAntimonyModelType,
  uExpressionNode,
  DelphiC;

type
  TODEFunc = procedure(t : Double; x, dxdt, rates, params : PDouble); cdecl;

  TModelState = class
  private
    FModel: TAntimonyModel;  // Reference to original model (not owned)
    FTime: Double;

    // Floating species storage (state variables for integration)
    FFloatingSpecies: TArray<Double>;
    FFloatingSpeciesNames: TArray<string>;
    FFloatingSpeciesIndex: TDictionary<string, Integer>;
    FNumFloatingSpecies: Integer;

    // Boundary species storage (fixed inputs, not integrated)
    FBoundarySpecies: TArray<Double>;
    FBoundarySpeciesNames: TArray<string>;
    FBoundarySpeciesIndex: TDictionary<string, Integer>;
    FNumBoundarySpecies: Integer;

    // Fundamental parameter storage (contiguous array)
    FParameters: TArray<Double>;
    FParameterNames: TArray<string>;
    FParameterIndex: TDictionary<string, Integer>;
    FNumParameters: Integer;

    // Derived parameter storage
    FDerivedValues: TArray<Double>;
    FDerivedNames: TArray<string>;
    FDerivedIndex: TDictionary<string, Integer>;
    FDerivedExpressions: TArray<TExpressionNode>;  // References, not owned
    FNumDerived: Integer;
    FDerivedDirty: Boolean;

    // Compartment storage
    FCompartments: TArray<Double>;
    FCompartmentNames: TArray<string>;
    FCompartmentIndex: TDictionary<string, Integer>;
    FNumCompartments: Integer;

    // Reaction storage (for rates array layout)
    FReactionNames: TArray<string>;
    FReactionIndex: TDictionary<string, Integer>;
    FNumReactions: Integer;

    // Initial values for reset
    FInitialFloatingSpecies: TArray<Double>;
    FInitialBoundarySpecies: TArray<Double>;
    FInitialParameters: TArray<Double>;
    FInitialCompartments: TArray<Double>;

    // Reaction rates cache (computed on demand via ODE function)
    FReactionRates: TArray<Double>;
    FScratchDxdt: TArray<Double>;   // Scratch buffer for dxdt output during rate evaluation
    FRatesDirty: Boolean;

    // Runtime components
    FCompiler: TDelphiC;
    FModelFunction: TODEFunc;
    
    FTimeCourseSolver: TObject;
    // Steady state solver - stored as TObject to avoid circular dependency
    // Actual type is TSteadyStateSolver, initialized via uSteadyStateSolver unit
    FSteadyStateSolver: TObject;

    procedure InitializeFromModel;
    procedure RecomputeDerived;
    procedure RecomputeRates;
    function LookupValue(const Name: string): Double;
    function GetNumAssignmentRules: Integer;
  public
    constructor Create(AModel: TAntimonyModel);
    destructor Destroy; override;

    // =========================================================================
    // TIME
    // =========================================================================
    property Time: Double read FTime write FTime;

    // =========================================================================
    // FLOATING SPECIES - State variables for ODE integration
    // =========================================================================
    
    // Direct array access (use in integration loops - no copying)
    property FloatingSpecies: TArray<Double> read FFloatingSpecies write FFloatingSpecies;
    property NumFloatingSpecies: Integer read FNumFloatingSpecies;
    
    // Indexed access (inline for speed)
    function GetFloatingSpeciesByIndex(Index: Integer): Double; inline;
    procedure SetFloatingSpeciesByIndex(Index: Integer; Value: Double); inline;

    // Name/index mapping
    function GetFloatingSpeciesIndex(const Name: string): Integer; inline;
    function GetFloatingSpeciesName(Index: Integer): string; inline;
    property FloatingSpeciesNames: TArray<string> read FFloatingSpeciesNames;
    
    // Named access (convenient but slower - use outside inner loops)
    function GetFloatingSpecies(const Name: string): Double;
    procedure SetFloatingSpecies(const Name: string; Value: Double);
    function HasFloatingSpecies(const Name: string): Boolean;
    function IsFloatingSpecies(const Name: string): Boolean;

    // =========================================================================
    // BOUNDARY SPECIES - Fixed external inputs (not integrated)
    // =========================================================================

    // Direct array access
    property BoundarySpecies: TArray<Double> read FBoundarySpecies write FBoundarySpecies;
    property NumBoundarySpecies: Integer read FNumBoundarySpecies;
    
    // Indexed access (inline for speed)
    function GetBoundarySpeciesByIndex(Index: Integer): Double; inline;
    procedure SetBoundarySpeciesByIndex(Index: Integer; Value: Double); inline;
    
    // Name/index mapping
    function GetBoundarySpeciesIndex(const Name: string): Integer; inline;
    function GetBoundarySpeciesName(Index: Integer): string; inline;
    property BoundarySpeciesNames: TArray<string> read FBoundarySpeciesNames;
    
    // Named access
    function GetBoundarySpecies(const Name: string): Double;
    procedure SetBoundarySpecies(const Name: string; Value: Double);
    function HasBoundarySpecies(const Name: string): Boolean;
    function IsBoundarySpecies(const Name: string): Boolean;

    // =========================================================================
    // ANY SPECIES (checks both floating and boundary)
    // =========================================================================
    
    function GetSpecies(const Name: string): Double;
    procedure SetSpecies(const Name: string; Value: Double);
    function HasSpecies(const Name: string): Boolean;
    function GetTotalSpeciesCount: Integer; inline;

    // =========================================================================
    // FUNDAMENTAL PARAMETERS - Direct array access for performance
    // =========================================================================
    
    // Direct array access (use for parameter sweeps, optimization)
    property Parameters: TArray<Double> read FParameters write FParameters;
    property NumParameters: Integer read FNumParameters;
    
    // Indexed access (inline for speed)
    function GetParameterByIndex(Index: Integer): Double; inline;
    procedure SetParameterByIndex(Index: Integer; Value: Double); inline;
    
    // Name/index mapping
    function GetParameterIndex(const Name: string): Integer; inline;
    function GetParameterName(Index: Integer): string; inline;
    property ParameterNames: TArray<string> read FParameterNames;
    
    // Named access (convenient but slower)
    function GetParameter(const Name: string): Double;
    procedure SetParameter(const Name: string; Value: Double);
    function HasParameter(const Name: string): Boolean;
    function IsFundamental(const Name: string): Boolean;

    // =========================================================================
    // DERIVED PARAMETERS - Read-only, computed from fundamentals
    // =========================================================================
    
    property DerivedValues: TArray<Double> read FDerivedValues;
    property NumDerived: Integer read FNumDerived;
    property DerivedNames: TArray<string> read FDerivedNames;
    
    function GetDerivedByIndex(Index: Integer): Double; inline;
    function GetDerivedIndex(const Name: string): Integer; inline;
    function GetDerived(const Name: string): Double;
    function IsDerived(const Name: string): Boolean;
    
    // Force recomputation of derived values
    procedure UpdateDerived;

    // =========================================================================
    // COMPARTMENTS
    // =========================================================================
    
    property Compartments: TArray<Double> read FCompartments write FCompartments;
    property NumCompartments: Integer read FNumCompartments;
    property CompartmentNames: TArray<string> read FCompartmentNames;
    
    function GetCompartmentByIndex(Index: Integer): Double; inline;
    procedure SetCompartmentByIndex(Index: Integer; Value: Double); inline;
    function GetCompartmentIndex(const Name: string): Integer; inline;

    function GetCompartment(const Name: string): Double;
    procedure SetCompartment(const Name: string; Size: Double);
    function HasCompartment(const Name: string): Boolean;

    // =========================================================================
    // REACTIONS - For rates array layout in C code generation
    // =========================================================================
    
    property ReactionNames: TArray<string> read FReactionNames;
    property NumReactions: Integer read FNumReactions;
    
    function GetReactionIndex(const Name: string): Integer; inline;
    function GetReactionName(Index: Integer): string; inline;
    function HasReaction(const Name: string): Boolean;

    // =========================================================================
    // REACTION RATES - Computed on demand by calling the ODE function.
    // Rates are always consistent with the current floating species, boundary
    // species, and parameter values.  Any setter that modifies state sets
    // FRatesDirty so the next access triggers a fresh ODE evaluation.
    // Requires ModelFunction to be assigned; returns zeros otherwise.
    // =========================================================================

    // Invalidate cached rates (called automatically by setters; also call
    // explicitly when you write to FloatingSpecies[] array directly)
    procedure InvalidateRates; inline;

    // Access rates - triggers ODE recomputation if dirty
    function GetReactionRates: TArray<Double>;
    function GetReactionRate(Index: Integer): Double; inline;
    function GetReactionRateByName(const Name: string): Double;

    // Convenience property (triggers recomputation if dirty)
    property ReactionRates: TArray<Double> read GetReactionRates;

    // =========================================================================
    // ASSIGNMENT RULES - Convenience access (delegates to Model)
    // =========================================================================
    
    property NumAssignmentRules: Integer read GetNumAssignmentRules;

    // =========================================================================
    // ANY VALUE LOOKUP (species, parameters, derived, compartments)
    // =========================================================================
    
    // General lookup - checks all categories, useful for expression evaluation
    function GetValue(const Name: string): Double;
    function HasValue(const Name: string): Boolean;

    // =========================================================================
    // STATE MANAGEMENT
    // =========================================================================

    // Reset to initial values of floating species from model
    procedure Reset;
    // Reset to initial values of all values from model
    procedure ResetAll;
    
    // Copy state back to model (only fundamental parameters and species)
    procedure CopyToModel;

    // Evaluate a kinetic law or expression using current state
    function EvaluateExpression(Expr: TExpressionNode): Double;

    // Mark derived values as needing recomputation
    // Call this after modifying parameters or species if you need derived values
    procedure InvalidateDerived; inline;

    // =========================================================================
    // C CODE INTEROP
    // For use with generated C derivative functions that expect:
    //   x[]      = floating species (use FloatingSpecies property directly)
    //   params[] = [boundary species..., fundamental parameters...]
    // =========================================================================
    
    // Create combined params array for C code
    // Layout: [BoundarySpecies[0..n-1], Parameters[0..m-1]]
    function CreateCombinedParamsArray: TArray<Double>;
    
    // Update state from combined params array (after external modification)
    procedure LoadFromCombinedParamsArray(const Params: TArray<Double>);
    
    // Size of combined params array
    function GetCombinedParamsSize: Integer; inline;

    // =========================================================================
    // DEBUGGING AND INSPECTION
    // =========================================================================
    
    // Print the array layout for debugging
    procedure PrintLayout;

    // Reference to original model
    property Model: TAntimonyModel read FModel;

    // Runtime components
    property ModelFunction: TODEFunc read FModelFunction write FModelFunction;
    property Compiler: TDelphiC read FCompiler write FCompiler;
    
    property TimeCourseSolver: TObject read FTimeCourseSolver write FTimeCourseSolver;
    // Steady state solver - stored as TObject, actual type is TSteadyStateSolver
    // Use TSteadyStateSolverCallBack.InitializeSolver to set up
    property SteadyStateSolver: TObject read FSteadyStateSolver write FSteadyStateSolver;
  end;

  // Exception for state errors
  EModelStateError = class(Exception);

implementation

{ TModelState }

constructor TModelState.Create(AModel: TAntimonyModel);
begin
  inherited Create;
  
  if not Assigned(AModel) then
    raise EModelStateError.Create('Cannot create state from nil model');
    
  FModel := AModel;
  FTime := 0.0;
  FDerivedDirty := True;
  FRatesDirty := True;
  FSteadyStateSolver := nil;
  
  FFloatingSpeciesIndex := TDictionary<string, Integer>.Create;
  FBoundarySpeciesIndex := TDictionary<string, Integer>.Create;
  FParameterIndex := TDictionary<string, Integer>.Create;
  FDerivedIndex := TDictionary<string, Integer>.Create;
  FCompartmentIndex := TDictionary<string, Integer>.Create;
  FReactionIndex := TDictionary<string, Integer>.Create;
  
  InitializeFromModel;
end;

destructor TModelState.Destroy;
begin
  FFloatingSpeciesIndex.Free;
  FBoundarySpeciesIndex.Free;
  FParameterIndex.Free;
  FDerivedIndex.Free;
  FCompartmentIndex.Free;
  FReactionIndex.Free;

  if Assigned(FCompiler) then
    FCompiler.Free;
    
  // Free steady state solver if it was created
  if Assigned(FSteadyStateSolver) then
    FSteadyStateSolver.Free;
  if Assigned(FTimeCourseSolver) then
    FTimeCourseSolver.Free;

  if Assigned (FModel) then
     FModel.Free;

  // Note: FDerivedExpressions contains references, not owned
  inherited Destroy;
end;

procedure TModelState.InitializeFromModel;
var
  I, FloatingIdx, BoundaryIdx, ParamIdx, DerivedIdx: Integer;
  Assignment: TAntimonyAssignment;
  ASpecies: TAntimonySpecies;
  Compartment: TAntimonyCompartment;
  Reaction: TAntimonyReaction;
begin
  // Count floating vs boundary species
  FNumFloatingSpecies := 0;
  FNumBoundarySpecies := 0;
  for I := 0 to FModel.Species.Count - 1 do
  begin
    if FModel.Species[I].IsBoundary then
      Inc(FNumBoundarySpecies)
    else
      Inc(FNumFloatingSpecies);
  end;
  
  // Initialize compartments
  FNumCompartments := FModel.Compartments.Count;
  SetLength(FCompartments, FNumCompartments);
  SetLength(FCompartmentNames, FNumCompartments);
  SetLength(FInitialCompartments, FNumCompartments);
  
  for I := 0 to FModel.Compartments.Count - 1 do
  begin
    Compartment := FModel.Compartments[I];
    FCompartmentNames[I] := Compartment.Id;
    FCompartments[I] := Compartment.Size;
    FInitialCompartments[I] := Compartment.Size;
    FCompartmentIndex.Add(Compartment.Id, I);
  end;
  
  // Initialize floating species
  SetLength(FFloatingSpecies, FNumFloatingSpecies);
  SetLength(FFloatingSpeciesNames, FNumFloatingSpecies);
  SetLength(FInitialFloatingSpecies, FNumFloatingSpecies);
  
  // Initialize boundary species
  SetLength(FBoundarySpecies, FNumBoundarySpecies);
  SetLength(FBoundarySpeciesNames, FNumBoundarySpecies);
  SetLength(FInitialBoundarySpecies, FNumBoundarySpecies);
  
  FloatingIdx := 0;
  BoundaryIdx := 0;
  for I := 0 to FModel.Species.Count - 1 do
  begin
    ASpecies := FModel.Species[I];
    if ASpecies.IsBoundary then
    begin
      FBoundarySpeciesNames[BoundaryIdx] := ASpecies.Id;
      FBoundarySpecies[BoundaryIdx] := ASpecies.InitialValue;
      FInitialBoundarySpecies[BoundaryIdx] := ASpecies.InitialValue;
      FBoundarySpeciesIndex.Add(ASpecies.Id, BoundaryIdx);
      Inc(BoundaryIdx);
    end
    else
    begin
      FFloatingSpeciesNames[FloatingIdx] := ASpecies.Id;
      FFloatingSpecies[FloatingIdx] := ASpecies.InitialValue;
      FInitialFloatingSpecies[FloatingIdx] := ASpecies.InitialValue;
      FFloatingSpeciesIndex.Add(ASpecies.Id, FloatingIdx);
      Inc(FloatingIdx);
    end;
  end;
  
  // Count fundamental vs derived parameters
  FNumParameters := 0;
  FNumDerived := 0;
  for I := 0 to FModel.Assignments.Count - 1 do
  begin
    Assignment := FModel.Assignments[I];
    // Skip species assignments
    if FModel.FindSpecies(Assignment.Variable) >= 0 then
      Continue;
    if Assignment.IsSimpleValue then
      Inc(FNumParameters)
    else
      Inc(FNumDerived);
  end;
  
  // Allocate parameter arrays
  SetLength(FParameters, FNumParameters);
  SetLength(FParameterNames, FNumParameters);
  SetLength(FInitialParameters, FNumParameters);
  SetLength(FDerivedValues, FNumDerived);
  SetLength(FDerivedNames, FNumDerived);
  SetLength(FDerivedExpressions, FNumDerived);
  
  // Fill parameter and derived arrays
  ParamIdx := 0;
  DerivedIdx := 0;
  for I := 0 to FModel.Assignments.Count - 1 do
  begin
    Assignment := FModel.Assignments[I];
    // Skip species assignments
    if FModel.FindSpecies(Assignment.Variable) >= 0 then
      Continue;
      
    if Assignment.IsSimpleValue then
    begin
      FParameterNames[ParamIdx] := Assignment.Variable;
      FParameters[ParamIdx] := Assignment.GetNumericValue;
      FInitialParameters[ParamIdx] := FParameters[ParamIdx];
      FParameterIndex.Add(Assignment.Variable, ParamIdx);
      Inc(ParamIdx);
    end
    else
    begin
      FDerivedNames[DerivedIdx] := Assignment.Variable;
      FDerivedExpressions[DerivedIdx] := Assignment.ExpressionAST;
      FDerivedValues[DerivedIdx] := 0.0;  // Will be computed
      FDerivedIndex.Add(Assignment.Variable, DerivedIdx);
      Inc(DerivedIdx);
    end;
  end;
  
  // Initialize reactions
  FNumReactions := FModel.Reactions.Count;
  SetLength(FReactionNames, FNumReactions);
  for I := 0 to FModel.Reactions.Count - 1 do
  begin
    Reaction := FModel.Reactions[I];
    FReactionNames[I] := Reaction.Id;
    FReactionIndex.Add(Reaction.Id, I);
  end;

  // Allocate reaction rates cache and ODE scratch buffer
  SetLength(FReactionRates, FNumReactions);
  SetLength(FScratchDxdt, FNumFloatingSpecies);
  FRatesDirty := True;
  
  // Compute initial derived values
  RecomputeDerived;
end;

function TModelState.LookupValue(const Name: string): Double;
var
  Idx: Integer;
begin
  // Check floating species
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    Exit(FFloatingSpecies[Idx]);
    
  // Check boundary species
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    Exit(FBoundarySpecies[Idx]);
    
  // Check parameters
  if FParameterIndex.TryGetValue(Name, Idx) then
    Exit(FParameters[Idx]);
    
  // Check derived
  if FDerivedIndex.TryGetValue(Name, Idx) then
    Exit(FDerivedValues[Idx]);
    
  // Check compartments
  if FCompartmentIndex.TryGetValue(Name, Idx) then
    Exit(FCompartments[Idx]);
    
  // Built-in constants
  if SameText(Name, 'pi') then
    Exit(Pi);
  if SameText(Name, 'e') then
    Exit(Exp(1.0));
  if SameText(Name, 'time') or SameText(Name, 't') then
    Exit(FTime);
    
  raise EModelStateError.CreateFmt('Unknown identifier: "%s"', [Name]);
end;

procedure TModelState.RecomputeDerived;
var
  I: Integer;
begin
  if not FDerivedDirty then
    Exit;
    
  for I := 0 to FNumDerived - 1 do
  begin
    try
      FDerivedValues[I] := FDerivedExpressions[I].Evaluate(LookupValue);
    except
      on E: Exception do
        raise EModelStateError.CreateFmt('Error evaluating derived parameter "%s": %s', 
          [FDerivedNames[I], E.Message]);
    end;
  end;
  
  FDerivedDirty := False;
end;

procedure TModelState.RecomputeRates;
var
  CombinedParams: TArray<Double>;
begin
  if not FRatesDirty then
    Exit;

  // Cannot compute without a compiled ODE function
  if not Assigned(FModelFunction) then
    Exit;

  // Guard against degenerate models
  if (FNumReactions = 0) or (FNumFloatingSpecies = 0) then
  begin
    FRatesDirty := False;
    Exit;
  end;

  // Build the combined params array [BoundarySpecies | Parameters] that
  // the generated C function expects as its last argument
  CombinedParams := CreateCombinedParamsArray;

  // Call the ODE function solely to populate FReactionRates.
  // FScratchDxdt receives the derivatives (discarded here).
  FModelFunction(FTime,
                 @FFloatingSpecies[0],
                 @FScratchDxdt[0],
                 @FReactionRates[0],
                 @CombinedParams[0]);

  FRatesDirty := False;
end;

procedure TModelState.InvalidateDerived;
begin
  FDerivedDirty := True;
  FRatesDirty := True;
end;

procedure TModelState.UpdateDerived;
begin
  FDerivedDirty := True;
  FRatesDirty := True;
  RecomputeDerived;
end;

function TModelState.GetNumAssignmentRules: Integer;
begin
  Result := FModel.AssignmentRules.Count;
end;

// =============================================================================
// FLOATING SPECIES ACCESS
// =============================================================================

function TModelState.GetFloatingSpeciesByIndex(Index: Integer): Double;
begin
  Result := FFloatingSpecies[Index];
end;

procedure TModelState.SetFloatingSpeciesByIndex(Index: Integer; Value: Double);
begin
  FFloatingSpecies[Index] := Value;
end;

function TModelState.GetFloatingSpeciesIndex(const Name: string): Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetFloatingSpeciesName(Index: Integer): string;
begin
  Result := FFloatingSpeciesNames[Index];
end;

function TModelState.GetFloatingSpecies(const Name: string): Double;
var
  Idx: Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown floating species: "%s"', [Name]);
  Result := FFloatingSpecies[Idx];
end;

procedure TModelState.SetFloatingSpecies(const Name: string; Value: Double);
var
  Idx: Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown floating species: "%s"', [Name]);
  FFloatingSpecies[Idx] := Value;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.HasFloatingSpecies(const Name: string): Boolean;
begin
  Result := FFloatingSpeciesIndex.ContainsKey(Name);
end;

function TModelState.IsFloatingSpecies(const Name: string): Boolean;
begin
  Result := FFloatingSpeciesIndex.ContainsKey(Name);
end;

// =============================================================================
// BOUNDARY SPECIES ACCESS
// =============================================================================

function TModelState.GetBoundarySpeciesByIndex(Index: Integer): Double;
begin
  Result := FBoundarySpecies[Index];
end;

procedure TModelState.SetBoundarySpeciesByIndex(Index: Integer; Value: Double);
begin
  FBoundarySpecies[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.GetBoundarySpeciesIndex(const Name: string): Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetBoundarySpeciesName(Index: Integer): string;
begin
  Result := FBoundarySpeciesNames[Index];
end;

function TModelState.GetBoundarySpecies(const Name: string): Double;
var
  Idx: Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown boundary species: "%s"', [Name]);
  Result := FBoundarySpecies[Idx];
end;

procedure TModelState.SetBoundarySpecies(const Name: string; Value: Double);
var
  Idx: Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown boundary species: "%s"', [Name]);
  FBoundarySpecies[Idx] := Value;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.HasBoundarySpecies(const Name: string): Boolean;
begin
  Result := FBoundarySpeciesIndex.ContainsKey(Name);
end;

function TModelState.IsBoundarySpecies(const Name: string): Boolean;
begin
  Result := FBoundarySpeciesIndex.ContainsKey(Name);
end;

// =============================================================================
// ANY SPECIES ACCESS (checks both floating and boundary)
// =============================================================================

function TModelState.GetSpecies(const Name: string): Double;
var
  Idx: Integer;
begin
  // Check floating first
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    Exit(FFloatingSpecies[Idx]);
    
  // Check boundary
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    Exit(FBoundarySpecies[Idx]);
    
  raise EModelStateError.CreateFmt('Unknown species: "%s"', [Name]);
end;

procedure TModelState.SetSpecies(const Name: string; Value: Double);
var
  Idx: Integer;
begin
  // Check floating first
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
  begin
    FFloatingSpecies[Idx] := Value;
    FDerivedDirty := True;
  FRatesDirty := True;
    Exit;
  end;
    
  // Check boundary
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
  begin
    FBoundarySpecies[Idx] := Value;
    FDerivedDirty := True;
  FRatesDirty := True;
    Exit;
  end;
    
  raise EModelStateError.CreateFmt('Unknown species: "%s"', [Name]);
end;

function TModelState.HasSpecies(const Name: string): Boolean;
begin
  Result := FFloatingSpeciesIndex.ContainsKey(Name) or 
            FBoundarySpeciesIndex.ContainsKey(Name);
end;

function TModelState.GetTotalSpeciesCount: Integer;
begin
  Result := FNumFloatingSpecies + FNumBoundarySpecies;
end;

// =============================================================================
// FUNDAMENTAL PARAMETER ACCESS
// =============================================================================

function TModelState.GetParameterByIndex(Index: Integer): Double;
begin
  Result := FParameters[Index];
end;

procedure TModelState.SetParameterByIndex(Index: Integer; Value: Double);
begin
  FParameters[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.GetParameterIndex(const Name: string): Integer;
begin
  if not FParameterIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetParameterName(Index: Integer): string;
begin
  Result := FParameterNames[Index];
end;

function TModelState.GetParameter(const Name: string): Double;
var
  Idx: Integer;
begin
  // Check fundamental first
  if FParameterIndex.TryGetValue(Name, Idx) then
    Exit(FParameters[Idx]);
    
  // Check derived
  if FDerivedIndex.TryGetValue(Name, Idx) then
  begin
    RecomputeDerived;
    Exit(FDerivedValues[Idx]);
  end;
  
  raise EModelStateError.CreateFmt('Unknown parameter: "%s"', [Name]);
end;

procedure TModelState.SetParameter(const Name: string; Value: Double);
var
  Idx: Integer;
begin
  if FParameterIndex.TryGetValue(Name, Idx) then
  begin
    FParameters[Idx] := Value;
    FDerivedDirty := True;
  FRatesDirty := True;
  end
  else if FDerivedIndex.ContainsKey(Name) then
    raise EModelStateError.CreateFmt('Cannot set derived parameter "%s". Modify its inputs instead.', [Name])
  else
    raise EModelStateError.CreateFmt('Unknown parameter: "%s"', [Name]);
end;

function TModelState.HasParameter(const Name: string): Boolean;
begin
  Result := FParameterIndex.ContainsKey(Name) or FDerivedIndex.ContainsKey(Name);
end;

function TModelState.IsFundamental(const Name: string): Boolean;
begin
  Result := FParameterIndex.ContainsKey(Name);
end;

// =============================================================================
// DERIVED PARAMETER ACCESS
// =============================================================================

function TModelState.GetDerivedByIndex(Index: Integer): Double;
begin
  RecomputeDerived;
  Result := FDerivedValues[Index];
end;

function TModelState.GetDerivedIndex(const Name: string): Integer;
begin
  if not FDerivedIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetDerived(const Name: string): Double;
var
  Idx: Integer;
begin
  if not FDerivedIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown derived parameter: "%s"', [Name]);
  RecomputeDerived;
  Result := FDerivedValues[Idx];
end;

function TModelState.IsDerived(const Name: string): Boolean;
begin
  Result := FDerivedIndex.ContainsKey(Name);
end;

// =============================================================================
// COMPARTMENT ACCESS
// =============================================================================

function TModelState.GetCompartmentByIndex(Index: Integer): Double;
begin
  Result := FCompartments[Index];
end;

procedure TModelState.SetCompartmentByIndex(Index: Integer; Value: Double);
begin
  FCompartments[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.GetCompartmentIndex(const Name: string): Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetCompartment(const Name: string): Double;
var
  Idx: Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown compartment: "%s"', [Name]);
  Result := FCompartments[Idx];
end;

procedure TModelState.SetCompartment(const Name: string; Size: Double);
var
  Idx: Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown compartment: "%s"', [Name]);
  FCompartments[Idx] := Size;
  FDerivedDirty := True;
  FRatesDirty := True;
end;

function TModelState.HasCompartment(const Name: string): Boolean;
begin
  Result := FCompartmentIndex.ContainsKey(Name);
end;

// =============================================================================
// REACTION ACCESS
// =============================================================================

// =============================================================================
// REACTION RATES - On-demand computation
// =============================================================================

procedure TModelState.InvalidateRates;
begin
  FRatesDirty := True;
end;

function TModelState.GetReactionRates: TArray<Double>;
begin
  RecomputeRates;
  Result := FReactionRates;
end;

function TModelState.GetReactionRate(Index: Integer): Double;
begin
  RecomputeRates;
  Result := FReactionRates[Index];
end;

function TModelState.GetReactionRateByName(const Name: string): Double;
var
  Idx: Integer;
begin
  if not FReactionIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown reaction: "%s"', [Name]);
  Result := GetReactionRate(Idx);
end;

function TModelState.GetReactionIndex(const Name: string): Integer;
begin
  if not FReactionIndex.TryGetValue(Name, Result) then
    Result := -1;
end;

function TModelState.GetReactionName(Index: Integer): string;
begin
  Result := FReactionNames[Index];
end;

function TModelState.HasReaction(const Name: string): Boolean;
begin
  Result := FReactionIndex.ContainsKey(Name);
end;

// =============================================================================
// GENERAL VALUE ACCESS
// =============================================================================

function TModelState.GetValue(const Name: string): Double;
begin
  Result := LookupValue(Name);
end;

function TModelState.HasValue(const Name: string): Boolean;
begin
  Result := FFloatingSpeciesIndex.ContainsKey(Name) or
            FBoundarySpeciesIndex.ContainsKey(Name) or
            FParameterIndex.ContainsKey(Name) or
            FDerivedIndex.ContainsKey(Name) or
            FCompartmentIndex.ContainsKey(Name);
end;

// =============================================================================
// STATE MANAGEMENT
// =============================================================================

procedure TModelState.Reset;
var
  I: Integer;
begin
  FTime := 0.0;

  // Restore floating species
  for I := 0 to FNumFloatingSpecies - 1 do
    FFloatingSpecies[I] := FInitialFloatingSpecies[I];

  FDerivedDirty := True;
  FRatesDirty := True;
  RecomputeDerived;
end;


procedure TModelState.ResetAll;
var
  I: Integer;
begin
  FTime := 0.0;

  // Restore floating species
  for I := 0 to FNumFloatingSpecies - 1 do
    FFloatingSpecies[I] := FInitialFloatingSpecies[I];

  // Restore boundary species
  for I := 0 to FNumBoundarySpecies - 1 do
    FBoundarySpecies[I] := FInitialBoundarySpecies[I];

  // Restore parameters
  for I := 0 to FNumParameters - 1 do
    FParameters[I] := FInitialParameters[I];

  // Restore compartments
  for I := 0 to FNumCompartments - 1 do
    FCompartments[I] := FInitialCompartments[I];

  FDerivedDirty := True;
  FRatesDirty := True;
  RecomputeDerived;
end;


procedure TModelState.CopyToModel;
var
  I, ModelIdx: Integer;
begin
  // Copy fundamental parameters back to model assignments
  for I := 0 to FNumParameters - 1 do
  begin
    ModelIdx := FModel.FindAssignment(FParameterNames[I]);
    if ModelIdx >= 0 then
      FModel.Assignments[ModelIdx].SetNumericValue(FParameters[I]);
  end;
  
  // Copy floating species initial values back to model
  for I := 0 to FNumFloatingSpecies - 1 do
  begin
    ModelIdx := FModel.FindSpecies(FFloatingSpeciesNames[I]);
    if ModelIdx >= 0 then
      FModel.Species[ModelIdx].InitialValue := FFloatingSpecies[I];
  end;
  
  // Copy boundary species initial values back to model
  for I := 0 to FNumBoundarySpecies - 1 do
  begin
    ModelIdx := FModel.FindSpecies(FBoundarySpeciesNames[I]);
    if ModelIdx >= 0 then
      FModel.Species[ModelIdx].InitialValue := FBoundarySpecies[I];
  end;
  
  // Copy compartment sizes back to model
  for I := 0 to FNumCompartments - 1 do
  begin
    ModelIdx := FModel.FindCompartment(FCompartmentNames[I]);
    if ModelIdx >= 0 then
      FModel.Compartments[ModelIdx].Size := FCompartments[I];
  end;
  
  // Note: Derived parameters are NOT copied back - they are computed values
end;

function TModelState.EvaluateExpression(Expr: TExpressionNode): Double;
begin
  if not Assigned(Expr) then
    raise EModelStateError.Create('Cannot evaluate nil expression');
    
  RecomputeDerived;  // Ensure derived values are up to date
  Result := Expr.Evaluate(LookupValue);
end;

// =============================================================================
// C CODE INTEROP
// =============================================================================

function TModelState.GetCombinedParamsSize: Integer;
begin
  Result := FNumBoundarySpecies + FNumParameters;
end;

function TModelState.CreateCombinedParamsArray: TArray<Double>;
var
  i: Integer;
begin
  SetLength(Result, GetCombinedParamsSize);
  
  // First: boundary species values
  for i := 0 to FNumBoundarySpecies - 1 do
    Result[i] := FBoundarySpecies[i];
  
  // Then: fundamental parameter values
  for i := 0 to FNumParameters - 1 do
    Result[FNumBoundarySpecies + i] := FParameters[i];
end;

procedure TModelState.LoadFromCombinedParamsArray(const Params: TArray<Double>);
var
  i: Integer;
begin
  if Length(Params) <> GetCombinedParamsSize then
    raise EModelStateError.CreateFmt('Combined params array size mismatch: expected %d, got %d',
      [GetCombinedParamsSize, Length(Params)]);
  
  // First: boundary species values
  for i := 0 to FNumBoundarySpecies - 1 do
    FBoundarySpecies[i] := Params[i];
  
  // Then: fundamental parameter values
  for i := 0 to FNumParameters - 1 do
    FParameters[i] := Params[FNumBoundarySpecies + i];
  
  FDerivedDirty := True;
  FRatesDirty := True;
end;

// =============================================================================
// DEBUGGING AND INSPECTION
// =============================================================================

procedure TModelState.PrintLayout;
var
  i: Integer;
begin
  WriteLn('=== Model State Layout ===');
  WriteLn;

  WriteLn('Floating Species (x[] array):');
  for i := 0 to FNumFloatingSpecies - 1 do
    WriteLn(Format('  x[%d] = %s', [i, FFloatingSpeciesNames[i]]));
  WriteLn;

  WriteLn('Boundary Species (params[0..', FNumBoundarySpecies - 1, ']):');
  for i := 0 to FNumBoundarySpecies - 1 do
    WriteLn(Format('  params[%d] = %s', [i, FBoundarySpeciesNames[i]]));
  WriteLn;

  WriteLn('Fundamental Parameters (params[', FNumBoundarySpecies, '..', GetCombinedParamsSize - 1, ']):');
  for i := 0 to FNumParameters - 1 do
    WriteLn(Format('  params[%d] = %s', [FNumBoundarySpecies + i, FParameterNames[i]]));
  WriteLn;

  WriteLn('Derived Parameters (computed in C code):');
  for i := 0 to FNumDerived - 1 do
    WriteLn(Format('  %s', [FDerivedNames[i]]));
  WriteLn;

  WriteLn('Assignment Rules (computed each call):');
  for i := 0 to FModel.AssignmentRules.Count - 1 do
    WriteLn(Format('  %s', [FModel.AssignmentRules[i].Variable]));
  WriteLn;

  WriteLn('Reactions (rates[] array):');
  for i := 0 to FNumReactions - 1 do
    WriteLn(Format('  rates[%d] = %s', [i, FReactionNames[i]]));
  WriteLn;

  if Assigned(FModelFunction) then
  begin
    WriteLn('Current Reaction Rates (recomputed from current state):');
    RecomputeRates;
    for i := 0 to FNumReactions - 1 do
      WriteLn(Format('  %s = %g', [FReactionNames[i], FReactionRates[i]]));
  end
  else
    WriteLn('Reaction Rates: (ModelFunction not yet assigned)');
  WriteLn;
end;

end.
