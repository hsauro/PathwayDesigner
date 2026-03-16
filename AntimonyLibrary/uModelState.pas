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

  MOIETY CONSERVATION:
    When the stoichiometry matrix N has rank r < m (m = number of floating
    species), SetMoietyData stores the reduced-system description.  After that:
      - NumIndependentSpecies = r  (the ODE dimension passed to CVODE/KINSOL)
      - NumDependentSpecies   = m - r
      - IndependentSpeciesIdx / DependentSpeciesIdx index into FloatingSpecies
      - L0Flat stores the (m-r) x r link matrix, row-major
      - ConservationConstants T[] satisfies:
            FloatingSpecies[DependentIdx[i]] =
                T[i] + sum_j(L0[i,j] * FloatingSpecies[IndependentIdx[j]])
    Call ComputeConservationConstants after any reset.
    Call ApplyConservationLaws after writing independent species values to
    reconstruct the dependent ones.

  params[] layout (as seen by the generated C function):
    params[0 .. nb-1]           boundary species
    params[nb .. nb+np-1]       fundamental parameters
    params[nb+np .. nb+np+nc-1] conservation constants T[0..nc-1]
}

interface

uses
  System.SysUtils,
  System.Math,
  Generics.Collections,
  uAntimonyModelType,
  uExpressionNode,
  uMatrixObj,
  uMoietyAnalysis,
  DelphiC;

type
  TODEFunc = procedure(t: Double; x, dxdt, rates, params: PDouble); cdecl;

  TModelState = class
  private
    FModel: TAntimonyModel;

    FTime: Double;

    // Floating species
    // Floating species concentrations in natural (declaration) order.
    // Use IndependentSpeciesToNaturalIdx / DependentSpeciesToNaturalIdx to
    // access values in MCA independent-first order.
    // This is the only place species concentrations are stored
    FFloatingSpecies:      TArray<Double>;
    FFloatingSpeciesNamesNatural: TArray<string>;
    // Returns the natural order index
    FFloatingSpeciesIndex: TDictionary<string, Integer>;
    FNumFloatingSpecies:   Integer;

    // Boundary species
    FBoundarySpecies:      TArray<Double>;
    FBoundarySpeciesNames: TArray<string>;
    FBoundarySpeciesIndex: TDictionary<string, Integer>;
    FNumBoundarySpecies:   Integer;

    // Fundamental parameters
    FParameters:      TArray<Double>;
    FParameterNames:  TArray<string>;
    FParameterIndex:  TDictionary<string, Integer>;
    FNumParameters:   Integer;

    // Derived parameters
    FDerivedValues:      TArray<Double>;
    FDerivedNames:       TArray<string>;
    FDerivedIndex:       TDictionary<string, Integer>;
    FDerivedExpressions: TArray<TExpressionNode>;  // references, not owned
    FNumDerived:         Integer;
    FDerivedDirty:       Boolean;

    // Compartments
    FCompartments:      TArray<Double>;
    FCompartmentNames:  TArray<string>;
    FCompartmentIndex:  TDictionary<string, Integer>;
    FNumCompartments:   Integer;

    // Reactions
    FReactionNames: TArray<string>;
    FReactionIndex: TDictionary<string, Integer>;
    FNumReactions:  Integer;

    // Initial values for reset
    FInitialFloatingSpecies: TArray<Double>;
    FInitialBoundarySpecies: TArray<Double>;
    FInitialParameters:      TArray<Double>;
    FInitialCompartments:    TArray<Double>;

    // Reaction rates cache
    FReactionRates: TArray<Double>;
    FScratchDxdt:   TArray<Double>;  // scratch for ODE calls; length = r
    FRatesDirty:    Boolean;

    // Runtime components
    FCompiler:          TDelphiC;
    FModelFunction:     TODEFunc;
    FTimeCourseSolver:  TObject;
    FSteadyStateSolver: TObject;

    // -----------------------------------------------------------------------
    // Moiety conservation
    // -----------------------------------------------------------------------
    FHasMoietyConservation: Boolean;
    FNumIndependentSpecies: Integer;        // r = rank(N)
    FNumDependentSpecies:   Integer;        // m - r
    FIndependentSpeciesToNaturalIdx: TArray<Integer>;
    FDependentSpeciesToNaturalIdx:   TArray<Integer>;
    FL0Flat:                TArray<Double>; // (m-r) x r, row-major
    FConservationConstants: TArray<Double>; // T[], length m-r
    FScratchIndepSpecies:   TArray<Double>; // size r, for ODE calls

    // Cached structural matrices (owned; built by SetMoietyData)
    FCachedN:     TMatrixObj;
    FCachedNr:    TMatrixObj;
    FCachedL:     TMatrixObj;
    FCachedGamma: TMatrixObj;

    procedure InitializeFromModel;
    procedure RecomputeDerived;
    procedure RecomputeRates;
    function  LookupValue(const Name: string): Double;
    function  GetNumAssignmentRules: Integer;

  public
    constructor Create(AModel: TAntimonyModel);
    destructor  Destroy; override;

    // =========================================================================
    // TIME
    // =========================================================================
    property Time: Double read FTime write FTime;

    // =========================================================================
    // FLOATING SPECIES
    // =========================================================================
    property FloatingSpecies:      TArray<Double> read FFloatingSpecies write FFloatingSpecies;
    property NumFloatingSpecies:   Integer        read FNumFloatingSpecies;
    property FloatingSpeciesNamesNatural: TArray<string> read FFloatingSpeciesNamesNatural;

    function GetFloatingSpeciesByIndex(Index: Integer): Double; inline;
    procedure SetFloatingSpeciesByIndex(Index: Integer; Value: Double); inline;
    function GetFloatingSpeciesIndex(const Name: string): Integer; inline;
    function GetFloatingSpeciesName(Index: Integer): string; inline;

    function  GetFloatingSpecies(const Name: string): Double;
    procedure SetFloatingSpecies(const Name: string; Value: Double);
    function  HasFloatingSpecies(const Name: string): Boolean;
    function  IsFloatingSpecies(const Name: string): Boolean;

    function GetFloatingSpeciesNamesOrdered: TArray<string>;

    function GetIndependentSpeciesNames: TArray<string>;
    function GetDependentSpeciesNames: TArray<string>;

    // =========================================================================
    // BOUNDARY SPECIES
    // =========================================================================
    property BoundarySpecies:      TArray<Double> read FBoundarySpecies write FBoundarySpecies;
    property NumBoundarySpecies:   Integer        read FNumBoundarySpecies;
    property BoundarySpeciesNames: TArray<string> read FBoundarySpeciesNames;

    function GetBoundarySpeciesByIndex(Index: Integer): Double; inline;
    procedure SetBoundarySpeciesByIndex(Index: Integer; Value: Double); inline;
    function GetBoundarySpeciesIndex(const Name: string): Integer; inline;
    function GetBoundarySpeciesName(Index: Integer): string; inline;

    function  GetBoundarySpecies(const Name: string): Double;
    procedure SetBoundarySpecies(const Name: string; Value: Double);
    function  HasBoundarySpecies(const Name: string): Boolean;
    function  IsBoundarySpecies(const Name: string): Boolean;

    // =========================================================================
    // ANY SPECIES
    // =========================================================================
    function  GetSpecies(const Name: string): Double;
    procedure SetSpecies(const Name: string; Value: Double);
    function  HasSpecies(const Name: string): Boolean;
    function  GetTotalSpeciesCount: Integer; inline;

    // =========================================================================
    // FUNDAMENTAL PARAMETERS
    // =========================================================================
    property Parameters:     TArray<Double> read FParameters write FParameters;
    property NumParameters:  Integer        read FNumParameters;
    property ParameterNames: TArray<string> read FParameterNames;

    function GetParameterByIndex(Index: Integer): Double; inline;
    procedure SetParameterByIndex(Index: Integer; Value: Double); inline;
    function GetParameterIndex(const Name: string): Integer; inline;
    function GetParameterName(Index: Integer): string; inline;

    function  GetParameter(const Name: string): Double;
    procedure SetParameter(const Name: string; Value: Double);
    function  HasParameter(const Name: string): Boolean;
    function  IsFundamental(const Name: string): Boolean;

    // =========================================================================
    // DERIVED PARAMETERS
    // =========================================================================
    property DerivedValues: TArray<Double> read FDerivedValues;
    property NumDerived:    Integer        read FNumDerived;
    property DerivedNames:  TArray<string> read FDerivedNames;

    function GetDerivedByIndex(Index: Integer): Double; inline;
    function GetDerivedIndex(const Name: string): Integer; inline;
    function GetDerived(const Name: string): Double;
    function IsDerived(const Name: string): Boolean;
    procedure UpdateDerived;

    // =========================================================================
    // COMPARTMENTS
    // =========================================================================
    property Compartments:      TArray<Double> read FCompartments write FCompartments;
    property NumCompartments:   Integer        read FNumCompartments;
    property CompartmentNames:  TArray<string> read FCompartmentNames;

    function GetCompartmentByIndex(Index: Integer): Double; inline;
    procedure SetCompartmentByIndex(Index: Integer; Value: Double); inline;
    function GetCompartmentIndex(const Name: string): Integer; inline;
    function  GetCompartment(const Name: string): Double;
    procedure SetCompartment(const Name: string; Size: Double);
    function  HasCompartment(const Name: string): Boolean;

    // =========================================================================
    // REACTIONS
    // =========================================================================
    property ReactionNames: TArray<string> read FReactionNames;
    property NumReactions:  Integer        read FNumReactions;

    function GetReactionIndex(const Name: string): Integer; inline;
    function GetReactionName(Index: Integer): string; inline;
    function HasReaction(const Name: string): Boolean;

    // =========================================================================
    // REACTION RATES
    // =========================================================================
    procedure InvalidateRates; inline;
    function  GetReactionRates: TArray<Double>;
    function  GetReactionRate(Index: Integer): Double; inline;
    function  GetReactionRateByName(const Name: string): Double;
    property  ReactionRates: TArray<Double> read GetReactionRates;

    // =========================================================================
    // ASSIGNMENT RULES
    // =========================================================================
    property NumAssignmentRules: Integer read GetNumAssignmentRules;

    // =========================================================================
    // GENERAL VALUE LOOKUP
    // =========================================================================
    function GetValue(const Name: string): Double;
    function HasValue(const Name: string): Boolean;

    // =========================================================================
    // STATE MANAGEMENT
    // =========================================================================
    procedure Reset;
    procedure ResetAll;
    procedure CopyToModel;
    function  EvaluateExpression(Expr: TExpressionNode): Double;
    procedure InvalidateDerived; inline;

    // =========================================================================
    // C CODE INTEROP
    // params[] layout: [boundary species | parameters | conservation T[]]
    // =========================================================================
    function  CreateCombinedParamsArray: TArray<Double>;
    procedure LoadFromCombinedParamsArray(const Params: TArray<Double>);
    function  GetCombinedParamsSize: Integer; inline;

    // =========================================================================
    // MOIETY CONSERVATION
    // =========================================================================

    { Store moiety analysis results from uBuildRunTimeModel.
      Resizes scratch buffers to r.  Call ComputeConservationConstants
      immediately after to initialise T[]. }
    procedure SetMoietyData(NumInd: Integer;
                            const IndIdx, DepIdx: TArray<Integer>;
                            const AL0Flat: TArray<Double>);

    { Recompute T[i] = S_dep[i] - sum_j(L0[i,j]*S_ind[j])
      from the current FloatingSpecies values.
      Must be called after SetMoietyData and after any Reset. }
    procedure ComputeConservationConstants;

    { Reconstruct dependent species from independent ones and T[]:
        S_dep[i] := T[i] + sum_j(L0[i,j]*S_ind[j])
      Call after writing new independent values into FloatingSpecies. }
    procedure ApplyConservationLaws;

    { Returns TArray of length NumIndependentSpecies with the current
      independent-species values (convenience for solver initialisation). }
    function GetIndependentSpeciesValues: TArray<Double>;

    { Structural matrices — each returns a new TMatrixObj; caller must free.
      Requires BuildRunTimeModel to have been called first (which runs the
      stoichiometry and moiety analysis and caches the data here).
        GetStoichiometryMatrix        -> N       m x n
        GetReducedStoichiometryMatrix -> Nr      r x n   (N = L * Nr)
        GetLinkMatrix                 -> L       m x r   (N = L * Nr)
        GetConservationMatrix         -> Gamma  (m-r) x m  (Gamma * S = T) }
    function GetStoichiometryMatrix: TMatrixObj;
    function GetReducedStoichiometryMatrix: TMatrixObj;
    function GetLinkMatrix: TMatrixObj;
    function GetConservationMatrix: TMatrixObj;

    property HasMoietyConservation: Boolean         read FHasMoietyConservation;
    property NumIndependentSpecies: Integer         read FNumIndependentSpecies;
    property NumDependentSpecies:   Integer         read FNumDependentSpecies;
    property IndependentSpeciesToNaturalIdx: TArray<Integer> read FIndependentSpeciesToNaturalIdx;
    property DependentSpeciesToNaturalIdx:   TArray<Integer> read FDependentSpeciesToNaturalIdx;
    property L0Flat:                TArray<Double>  read FL0Flat;
    property ConservationConstants: TArray<Double>  read FConservationConstants;

    // =========================================================================
    // DEBUGGING
    // =========================================================================
    procedure PrintLayout;

    // =========================================================================
    // RUNTIME COMPONENTS
    // =========================================================================
    property Model:             TAntimonyModel read FModel;
    property ModelFunction:     TODEFunc       read FModelFunction write FModelFunction;
    property Compiler:          TDelphiC       read FCompiler      write FCompiler;
    property TimeCourseSolver:  TObject        read FTimeCourseSolver  write FTimeCourseSolver;
    property SteadyStateSolver: TObject        read FSteadyStateSolver write FSteadyStateSolver;
  end;

  EModelStateError = class(Exception);

implementation

Uses  uStoichiometryMatrix;

{ TModelState }

// =============================================================================
// Constructor / Destructor
// =============================================================================

constructor TModelState.Create(AModel: TAntimonyModel);
begin
  inherited Create;

  if not Assigned(AModel) then
    raise EModelStateError.Create('Cannot create state from nil model');

  FModel        := AModel;
  FTime         := 0.0;
  FDerivedDirty := True;
  FRatesDirty   := True;

  FSteadyStateSolver    := nil;
  FTimeCourseSolver     := nil;
  FHasMoietyConservation := False;
  FNumIndependentSpecies := 0;
  FNumDependentSpecies   := 0;

  FFloatingSpeciesIndex := TDictionary<string, Integer>.Create;
  FBoundarySpeciesIndex := TDictionary<string, Integer>.Create;
  FParameterIndex       := TDictionary<string, Integer>.Create;
  FDerivedIndex         := TDictionary<string, Integer>.Create;
  FCompartmentIndex     := TDictionary<string, Integer>.Create;
  FReactionIndex        := TDictionary<string, Integer>.Create;

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

  if Assigned(FCompiler) then          FCompiler.Free;
  if Assigned(FSteadyStateSolver) then FSteadyStateSolver.Free;
  if Assigned(FTimeCourseSolver)  then FTimeCourseSolver.Free;
  if Assigned(FModel)             then FModel.Free;

  FCachedN.Free;
  FCachedNr.Free;
  FCachedL.Free;
  FCachedGamma.Free;

  inherited Destroy;
end;

// =============================================================================
// Initialisation
// =============================================================================

procedure TModelState.InitializeFromModel;
var
  I, FloatingIdx, BoundaryIdx, ParamIdx, DerivedIdx: Integer;
  Assignment: TAntimonyAssignment;
  ASpecies:   TAntimonySpecies;
  Compartment: TAntimonyCompartment;
  Reaction:   TAntimonyReaction;
begin
  // Count floating vs boundary
  FNumFloatingSpecies := 0;
  FNumBoundarySpecies := 0;
  for I := 0 to FModel.Species.Count - 1 do
    if FModel.Species[I].IsBoundary then
      Inc(FNumBoundarySpecies)
    else
      Inc(FNumFloatingSpecies);

  // Compartments
  FNumCompartments := FModel.Compartments.Count;
  SetLength(FCompartments,        FNumCompartments);
  SetLength(FCompartmentNames,    FNumCompartments);
  SetLength(FInitialCompartments, FNumCompartments);
  for I := 0 to FModel.Compartments.Count - 1 do
  begin
    Compartment := FModel.Compartments[I];
    FCompartmentNames[I]    := Compartment.Id;
    FCompartments[I]        := Compartment.Size;
    FInitialCompartments[I] := Compartment.Size;
    FCompartmentIndex.Add(Compartment.Id, I);
  end;

  // Floating species arrays
  SetLength(FFloatingSpecies,        FNumFloatingSpecies);
  SetLength(FFloatingSpeciesNamesNatural,   FNumFloatingSpecies);
  SetLength(FInitialFloatingSpecies, FNumFloatingSpecies);

  // Boundary species arrays
  SetLength(FBoundarySpecies,        FNumBoundarySpecies);
  SetLength(FBoundarySpeciesNames,   FNumBoundarySpecies);
  SetLength(FInitialBoundarySpecies, FNumBoundarySpecies);

  FloatingIdx := 0;
  BoundaryIdx := 0;
  for I := 0 to FModel.Species.Count - 1 do
  begin
    ASpecies := FModel.Species[I];
    if ASpecies.IsBoundary then
    begin
      FBoundarySpeciesNames[BoundaryIdx]    := ASpecies.Id;
      FBoundarySpecies[BoundaryIdx]         := ASpecies.InitialValue;
      FInitialBoundarySpecies[BoundaryIdx]  := ASpecies.InitialValue;
      FBoundarySpeciesIndex.Add(ASpecies.Id, BoundaryIdx);
      Inc(BoundaryIdx);
    end
    else
    begin
      FFloatingSpeciesNamesNatural[FloatingIdx]    := ASpecies.Id;
      FFloatingSpecies[FloatingIdx]         := ASpecies.InitialValue;
      FInitialFloatingSpecies[FloatingIdx]  := ASpecies.InitialValue;
      FFloatingSpeciesIndex.Add(ASpecies.Id, FloatingIdx);
      Inc(FloatingIdx);
    end;
  end;

  // Count fundamental vs derived parameters
  FNumParameters := 0;
  FNumDerived    := 0;
  for I := 0 to FModel.Assignments.Count - 1 do
  begin
    Assignment := FModel.Assignments[I];
    if FModel.FindSpecies(Assignment.Variable) >= 0 then Continue;
    if Assignment.IsSimpleValue then
      Inc(FNumParameters)
    else
      Inc(FNumDerived);
  end;

  SetLength(FParameters,       FNumParameters);
  SetLength(FParameterNames,   FNumParameters);
  SetLength(FInitialParameters, FNumParameters);
  SetLength(FDerivedValues,    FNumDerived);
  SetLength(FDerivedNames,     FNumDerived);
  SetLength(FDerivedExpressions, FNumDerived);

  ParamIdx  := 0;
  DerivedIdx := 0;
  for I := 0 to FModel.Assignments.Count - 1 do
  begin
    Assignment := FModel.Assignments[I];
    if FModel.FindSpecies(Assignment.Variable) >= 0 then Continue;

    if Assignment.IsSimpleValue then
    begin
      FParameterNames[ParamIdx]    := Assignment.Variable;
      FParameters[ParamIdx]        := Assignment.GetNumericValue;
      FInitialParameters[ParamIdx] := FParameters[ParamIdx];
      FParameterIndex.Add(Assignment.Variable, ParamIdx);
      Inc(ParamIdx);
    end
    else
    begin
      FDerivedNames[DerivedIdx]        := Assignment.Variable;
      FDerivedExpressions[DerivedIdx]  := Assignment.ExpressionAST;
      FDerivedValues[DerivedIdx]       := 0.0;
      FDerivedIndex.Add(Assignment.Variable, DerivedIdx);
      Inc(DerivedIdx);
    end;
  end;

  // Reactions
  FNumReactions := FModel.Reactions.Count;
  SetLength(FReactionNames, FNumReactions);
  for I := 0 to FModel.Reactions.Count - 1 do
  begin
    Reaction := FModel.Reactions[I];
    FReactionNames[I] := Reaction.Id;
    FReactionIndex.Add(Reaction.Id, I);
  end;

  // Scratch buffers — sized to full m until SetMoietyData reduces them to r
  SetLength(FReactionRates, FNumReactions);
  SetLength(FScratchDxdt,   FNumFloatingSpecies);
  FRatesDirty := True;

  // Default moiety state: all species independent (no conservation)
  FNumIndependentSpecies := FNumFloatingSpecies;
  FNumDependentSpecies   := 0;
  SetLength(FIndependentSpeciesToNaturalIdx, FNumFloatingSpecies);
  for I := 0 to FNumFloatingSpecies - 1 do
    FIndependentSpeciesToNaturalIdx[I] := I;
  FDependentSpeciesToNaturalIdx   := nil;
  FL0Flat                := nil;
  FConservationConstants := nil;
  SetLength(FScratchIndepSpecies, 0);

  RecomputeDerived;
end;

// =============================================================================
// Private helpers
// =============================================================================

function TModelState.LookupValue(const Name: string): Double;
var Idx: Integer;
begin
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then Exit(FFloatingSpecies[Idx]);
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then Exit(FBoundarySpecies[Idx]);
  if FParameterIndex.TryGetValue(Name, Idx)       then Exit(FParameters[Idx]);
  if FDerivedIndex.TryGetValue(Name, Idx)         then Exit(FDerivedValues[Idx]);
  if FCompartmentIndex.TryGetValue(Name, Idx)     then Exit(FCompartments[Idx]);
  if SameText(Name, 'pi')                         then Exit(Pi);
  if SameText(Name, 'e')                          then Exit(Exp(1.0));
  if SameText(Name, 'time') or SameText(Name, 't') then Exit(FTime);
  raise EModelStateError.CreateFmt('Unknown identifier: "%s"', [Name]);
end;

procedure TModelState.RecomputeDerived;
var I: Integer;
begin
  if not FDerivedDirty then Exit;
  for I := 0 to FNumDerived - 1 do
  begin
    try
      FDerivedValues[I] := FDerivedExpressions[I].Evaluate(LookupValue);
    except
      on E: Exception do
        raise EModelStateError.CreateFmt(
          'Error evaluating derived parameter "%s": %s', [FDerivedNames[I], E.Message]);
    end;
  end;
  FDerivedDirty := False;
end;

procedure TModelState.RecomputeRates;
var
  CombinedParams: TArray<Double>;
  IndepPtr: PDouble;
  I: Integer;
begin
  if not FRatesDirty then Exit;
  if not Assigned(FModelFunction) then Exit;
  if (FNumReactions = 0) or (FNumFloatingSpecies = 0) then
  begin
    FRatesDirty := False;
    Exit;
  end;

  CombinedParams := CreateCombinedParamsArray;

  // When conservation is present, the ODE function expects r independent
  // species in x[].  Extract them into the scratch buffer.
  if FHasMoietyConservation then
  begin
    for I := 0 to FNumIndependentSpecies - 1 do
      FScratchIndepSpecies[I] := FFloatingSpecies[FIndependentSpeciesToNaturalIdx[I]];
    IndepPtr := @FScratchIndepSpecies[0];
  end
  else
    IndepPtr := @FFloatingSpecies[0];

  FModelFunction(FTime, IndepPtr, @FScratchDxdt[0],
                 @FReactionRates[0], @CombinedParams[0]);

  FRatesDirty := False;
end;

function TModelState.GetNumAssignmentRules: Integer;
begin
  Result := FModel.AssignmentRules.Count;
end;

// =============================================================================
// FLOATING SPECIES
// =============================================================================

function TModelState.GetFloatingSpeciesByIndex(Index: Integer): Double;
begin Result := FFloatingSpecies[Index]; end;

procedure TModelState.SetFloatingSpeciesByIndex(Index: Integer; Value: Double);
begin FFloatingSpecies[Index] := Value; end;

function TModelState.GetFloatingSpeciesIndex(const Name: string): Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetFloatingSpeciesName(Index: Integer): string;
begin Result := FFloatingSpeciesNamesNatural[Index]; end;

function TModelState.GetFloatingSpecies(const Name: string): Double;
var Idx: Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown floating species: "%s"', [Name]);
  Result := FFloatingSpecies[Idx];
end;

procedure TModelState.SetFloatingSpecies(const Name: string; Value: Double);
var Idx: Integer;
begin
  if not FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown floating species: "%s"', [Name]);
  FFloatingSpecies[Idx] := Value;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.HasFloatingSpecies(const Name: string): Boolean;
begin Result := FFloatingSpeciesIndex.ContainsKey(Name); end;

function TModelState.IsFloatingSpecies(const Name: string): Boolean;
begin Result := FFloatingSpeciesIndex.ContainsKey(Name); end;


// In TModelState
function TModelState.GetFloatingSpeciesNamesOrdered: TArray<string>;
var i, r: Integer;
begin
  r := FNumIndependentSpecies;
  SetLength(Result, FNumFloatingSpecies);
  for i := 0 to r - 1 do
    Result[i] := FFloatingSpeciesNamesNatural[FIndependentSpeciesToNaturalIdx[i]];
  for i := 0 to FNumDependentSpecies - 1 do
    Result[r + i] := FFloatingSpeciesNamesNatural[FDependentSpeciesToNaturalIdx[i]];
end;


function TModelState.GetIndependentSpeciesNames: TArray<string>;
var i: Integer;
begin
  SetLength(Result, FNumIndependentSpecies);
  for i := 0 to FNumIndependentSpecies - 1 do
    Result[i] := FFloatingSpeciesNamesNatural[IndependentSpeciesToNaturalIdx[i]];
end;


function TModelState.GetDependentSpeciesNames: TArray<string>;
var i: Integer;
begin
  SetLength(Result, FNumDependentSpecies);
  for i := 0 to FNumDependentSpecies - 1 do
    Result[i] := FFloatingSpeciesNamesNatural[DependentSpeciesToNaturalIdx[i]];
end;

// =============================================================================
// BOUNDARY SPECIES
// =============================================================================

function TModelState.GetBoundarySpeciesByIndex(Index: Integer): Double;
begin Result := FBoundarySpecies[Index]; end;

procedure TModelState.SetBoundarySpeciesByIndex(Index: Integer; Value: Double);
begin
  FBoundarySpecies[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.GetBoundarySpeciesIndex(const Name: string): Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetBoundarySpeciesName(Index: Integer): string;
begin Result := FBoundarySpeciesNames[Index]; end;

function TModelState.GetBoundarySpecies(const Name: string): Double;
var Idx: Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown boundary species: "%s"', [Name]);
  Result := FBoundarySpecies[Idx];
end;

procedure TModelState.SetBoundarySpecies(const Name: string; Value: Double);
var Idx: Integer;
begin
  if not FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown boundary species: "%s"', [Name]);
  FBoundarySpecies[Idx] := Value;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.HasBoundarySpecies(const Name: string): Boolean;
begin Result := FBoundarySpeciesIndex.ContainsKey(Name); end;

function TModelState.IsBoundarySpecies(const Name: string): Boolean;
begin Result := FBoundarySpeciesIndex.ContainsKey(Name); end;

// =============================================================================
// ANY SPECIES
// =============================================================================

function TModelState.GetSpecies(const Name: string): Double;
var Idx: Integer;
begin
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then Exit(FFloatingSpecies[Idx]);
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then Exit(FBoundarySpecies[Idx]);
  raise EModelStateError.CreateFmt('Unknown species: "%s"', [Name]);
end;

procedure TModelState.SetSpecies(const Name: string; Value: Double);
var Idx: Integer;
begin
  if FFloatingSpeciesIndex.TryGetValue(Name, Idx) then
  begin
    FFloatingSpecies[Idx] := Value;
    FDerivedDirty := True;
    FRatesDirty   := True;
    Exit;
  end;
  if FBoundarySpeciesIndex.TryGetValue(Name, Idx) then
  begin
    FBoundarySpecies[Idx] := Value;
    FDerivedDirty := True;
    FRatesDirty   := True;
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
begin Result := FNumFloatingSpecies + FNumBoundarySpecies; end;

// =============================================================================
// FUNDAMENTAL PARAMETERS
// =============================================================================

function TModelState.GetParameterByIndex(Index: Integer): Double;
begin Result := FParameters[Index]; end;

procedure TModelState.SetParameterByIndex(Index: Integer; Value: Double);
begin
  FParameters[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.GetParameterIndex(const Name: string): Integer;
begin
  if not FParameterIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetParameterName(Index: Integer): string;
begin Result := FParameterNames[Index]; end;

function TModelState.GetParameter(const Name: string): Double;
var Idx: Integer;
begin
  if FParameterIndex.TryGetValue(Name, Idx) then Exit(FParameters[Idx]);
  if FDerivedIndex.TryGetValue(Name, Idx) then
  begin
    RecomputeDerived;
    Exit(FDerivedValues[Idx]);
  end;
  raise EModelStateError.CreateFmt('Unknown parameter: "%s"', [Name]);
end;

procedure TModelState.SetParameter(const Name: string; Value: Double);
var Idx: Integer;
begin
  if FParameterIndex.TryGetValue(Name, Idx) then
  begin
    FParameters[Idx] := Value;
    FDerivedDirty := True;
    FRatesDirty   := True;
  end
  else if FDerivedIndex.ContainsKey(Name) then
    raise EModelStateError.CreateFmt(
      'Cannot set derived parameter "%s". Modify its inputs instead.', [Name])
  else
    raise EModelStateError.CreateFmt('Unknown parameter: "%s"', [Name]);
end;

function TModelState.HasParameter(const Name: string): Boolean;
begin
  Result := FParameterIndex.ContainsKey(Name) or FDerivedIndex.ContainsKey(Name);
end;

function TModelState.IsFundamental(const Name: string): Boolean;
begin Result := FParameterIndex.ContainsKey(Name); end;

// =============================================================================
// DERIVED PARAMETERS
// =============================================================================

function TModelState.GetDerivedByIndex(Index: Integer): Double;
begin
  RecomputeDerived;
  Result := FDerivedValues[Index];
end;

function TModelState.GetDerivedIndex(const Name: string): Integer;
begin
  if not FDerivedIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetDerived(const Name: string): Double;
var Idx: Integer;
begin
  if not FDerivedIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown derived parameter: "%s"', [Name]);
  RecomputeDerived;
  Result := FDerivedValues[Idx];
end;

function TModelState.IsDerived(const Name: string): Boolean;
begin Result := FDerivedIndex.ContainsKey(Name); end;

procedure TModelState.InvalidateDerived;
begin
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

procedure TModelState.UpdateDerived;
begin
  FDerivedDirty := True;
  FRatesDirty   := True;
  RecomputeDerived;
end;

// =============================================================================
// COMPARTMENTS
// =============================================================================

function TModelState.GetCompartmentByIndex(Index: Integer): Double;
begin Result := FCompartments[Index]; end;

procedure TModelState.SetCompartmentByIndex(Index: Integer; Value: Double);
begin
  FCompartments[Index] := Value;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.GetCompartmentIndex(const Name: string): Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetCompartment(const Name: string): Double;
var Idx: Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown compartment: "%s"', [Name]);
  Result := FCompartments[Idx];
end;

procedure TModelState.SetCompartment(const Name: string; Size: Double);
var Idx: Integer;
begin
  if not FCompartmentIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown compartment: "%s"', [Name]);
  FCompartments[Idx] := Size;
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

function TModelState.HasCompartment(const Name: string): Boolean;
begin Result := FCompartmentIndex.ContainsKey(Name); end;

// =============================================================================
// REACTIONS
// =============================================================================

function TModelState.GetReactionIndex(const Name: string): Integer;
begin
  if not FReactionIndex.TryGetValue(Name, Result) then Result := -1;
end;

function TModelState.GetReactionName(Index: Integer): string;
begin Result := FReactionNames[Index]; end;

function TModelState.HasReaction(const Name: string): Boolean;
begin Result := FReactionIndex.ContainsKey(Name); end;

// =============================================================================
// REACTION RATES
// =============================================================================

procedure TModelState.InvalidateRates;
begin FRatesDirty := True; end;

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
var Idx: Integer;
begin
  if not FReactionIndex.TryGetValue(Name, Idx) then
    raise EModelStateError.CreateFmt('Unknown reaction: "%s"', [Name]);
  Result := GetReactionRate(Idx);
end;

// =============================================================================
// GENERAL VALUE LOOKUP
// =============================================================================

function TModelState.GetValue(const Name: string): Double;
begin Result := LookupValue(Name); end;

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
var I: Integer;
begin
  FTime := 0.0;
  for I := 0 to FNumFloatingSpecies - 1 do
    FFloatingSpecies[I] := FInitialFloatingSpecies[I];
  FDerivedDirty := True;
  FRatesDirty   := True;
  RecomputeDerived;
  if FHasMoietyConservation then
    ComputeConservationConstants;
end;

procedure TModelState.ResetAll;
var I: Integer;
begin
  FTime := 0.0;
  for I := 0 to FNumFloatingSpecies - 1 do
    FFloatingSpecies[I] := FInitialFloatingSpecies[I];
  for I := 0 to FNumBoundarySpecies - 1 do
    FBoundarySpecies[I] := FInitialBoundarySpecies[I];
  for I := 0 to FNumParameters - 1 do
    FParameters[I] := FInitialParameters[I];
  for I := 0 to FNumCompartments - 1 do
    FCompartments[I] := FInitialCompartments[I];
  FDerivedDirty := True;
  FRatesDirty   := True;
  RecomputeDerived;
  if FHasMoietyConservation then
    ComputeConservationConstants;
end;

procedure TModelState.CopyToModel;
var I, ModelIdx: Integer;
begin
  for I := 0 to FNumParameters - 1 do
  begin
    ModelIdx := FModel.FindAssignment(FParameterNames[I]);
    if ModelIdx >= 0 then
      FModel.Assignments[ModelIdx].SetNumericValue(FParameters[I]);
  end;
  for I := 0 to FNumFloatingSpecies - 1 do
  begin
    ModelIdx := FModel.FindSpecies(FFloatingSpeciesNamesNatural[I]);
    if ModelIdx >= 0 then
      FModel.Species[ModelIdx].InitialValue := FFloatingSpecies[I];
  end;
  for I := 0 to FNumBoundarySpecies - 1 do
  begin
    ModelIdx := FModel.FindSpecies(FBoundarySpeciesNames[I]);
    if ModelIdx >= 0 then
      FModel.Species[ModelIdx].InitialValue := FBoundarySpecies[I];
  end;
  for I := 0 to FNumCompartments - 1 do
  begin
    ModelIdx := FModel.FindCompartment(FCompartmentNames[I]);
    if ModelIdx >= 0 then
      FModel.Compartments[ModelIdx].Size := FCompartments[I];
  end;
end;

function TModelState.EvaluateExpression(Expr: TExpressionNode): Double;
begin
  if not Assigned(Expr) then
    raise EModelStateError.Create('Cannot evaluate nil expression');
  RecomputeDerived;
  Result := Expr.Evaluate(LookupValue);
end;

// =============================================================================
// C CODE INTEROP
// params[] = [boundary species | parameters | conservation constants T[]]
// =============================================================================

function TModelState.GetCombinedParamsSize: Integer;
begin
  Result := FNumBoundarySpecies + FNumParameters + FNumDependentSpecies;
end;

function TModelState.CreateCombinedParamsArray: TArray<Double>;
var
  I, Offset: Integer;
begin
  SetLength(Result, GetCombinedParamsSize);

  for I := 0 to FNumBoundarySpecies - 1 do
    Result[I] := FBoundarySpecies[I];

  for I := 0 to FNumParameters - 1 do
    Result[FNumBoundarySpecies + I] := FParameters[I];

  // Conservation constants T[] — zero-length array when no conservation
  Offset := FNumBoundarySpecies + FNumParameters;
  for I := 0 to FNumDependentSpecies - 1 do
    Result[Offset + I] := FConservationConstants[I];
end;

procedure TModelState.LoadFromCombinedParamsArray(const Params: TArray<Double>);
var I: Integer;
begin
  // Accept an array with or without the T[] tail
  if (Length(Params) <> FNumBoundarySpecies + FNumParameters) and
     (Length(Params) <> GetCombinedParamsSize) then
    raise EModelStateError.CreateFmt(
      'Combined params array size mismatch: expected %d (or %d), got %d',
      [FNumBoundarySpecies + FNumParameters, GetCombinedParamsSize, Length(Params)]);

  for I := 0 to FNumBoundarySpecies - 1 do
    FBoundarySpecies[I] := Params[I];

  for I := 0 to FNumParameters - 1 do
    FParameters[I] := Params[FNumBoundarySpecies + I];

  // T[] is NOT loaded — it is always recomputed from FloatingSpecies via
  // ComputeConservationConstants.
  FDerivedDirty := True;
  FRatesDirty   := True;
end;

// =============================================================================
// MOIETY CONSERVATION
// =============================================================================

procedure TModelState.SetMoietyData(NumInd: Integer;
                                    const IndIdx, DepIdx: TArray<Integer>;
                                    const AL0Flat: TArray<Double>);
var
  nc: Integer;
  StoichResult: TStoichiometryResult;
  Analysis: TMoietyAnalysis;
begin
  FNumIndependentSpecies := NumInd;
  FNumDependentSpecies   := Length(DepIdx);
  nc := FNumDependentSpecies;

  FIndependentSpeciesToNaturalIdx := Copy(IndIdx);
  FDependentSpeciesToNaturalIdx   := Copy(DepIdx);
  FL0Flat                := Copy(AL0Flat);

  FHasMoietyConservation := nc > 0;

  SetLength(FConservationConstants, nc);

  // Resize scratch buffers to the reduced system dimension r
  SetLength(FScratchDxdt,         NumInd);
  SetLength(FScratchIndepSpecies, NumInd);

  // Build and cache structural matrices using a fresh analysis pass.
  // This is inexpensive (no LAPACK call; matrices computed from stored data).
  FCachedN.Free;     FCachedN     := nil;
  FCachedNr.Free;    FCachedNr    := nil;
  FCachedL.Free;     FCachedL     := nil;
  FCachedGamma.Free; FCachedGamma := nil;

  StoichResult := TStoichiometryMatrixBuilder.Build(FModel);
  try
    Analysis := TMoietyAnalysis.Create;
    try
      Analysis.Analyse(StoichResult.Matrix);
      FCachedN     := Analysis.GetN;
      FCachedNr    := Analysis.GetNr;
      FCachedL     := Analysis.GetL;
      FCachedGamma := Analysis.GetGamma;
    finally
      Analysis.Free;
    end;
  finally
    StoichResult.Matrix.Free;
  end;
end;

procedure TModelState.ComputeConservationConstants;
var
  I, J, R: Integer;
  Sum: Double;
begin
  if not FHasMoietyConservation then Exit;

  R := FNumIndependentSpecies;
  for I := 0 to FNumDependentSpecies - 1 do
  begin
    // T[i] = S_dep[i] - sum_j(L0[i,j] * S_ind[j])
    Sum := FFloatingSpecies[FDependentSpeciesToNaturalIdx[I]];
    for J := 0 to R - 1 do
      Sum := Sum - FL0Flat[I * R + J] * FFloatingSpecies[FIndependentSpeciesToNaturalIdx[J]];
    FConservationConstants[I] := Sum;
  end;
end;

procedure TModelState.ApplyConservationLaws;
var
  I, J, R: Integer;
  Sum: Double;
begin
  if not FHasMoietyConservation then Exit;

  R := FNumIndependentSpecies;
  for I := 0 to FNumDependentSpecies - 1 do
  begin
    // S_dep[i] = T[i] + sum_j(L0[i,j] * S_ind[j])
    Sum := FConservationConstants[I];
    for J := 0 to R - 1 do
      Sum := Sum + FL0Flat[I * R + J] * FFloatingSpecies[FIndependentSpeciesToNaturalIdx[J]];
    FFloatingSpecies[FDependentSpeciesToNaturalIdx[I]] := Sum;
  end;

  FRatesDirty := True;
end;

function TModelState.GetIndependentSpeciesValues: TArray<Double>;
var I: Integer;
begin
  SetLength(Result, FNumIndependentSpecies);
  for I := 0 to FNumIndependentSpecies - 1 do
    Result[I] := FFloatingSpecies[FIndependentSpeciesToNaturalIdx[I]];
end;

// =============================================================================
// DEBUGGING
// =============================================================================

procedure TModelState.PrintLayout;
var
  I, Offset: Integer;
begin
  WriteLn('=== Model State Layout ===');
  WriteLn;

  if FHasMoietyConservation then
  begin
    WriteLn(Format('Moiety conservation: %d independent, %d dependent species.',
      [FNumIndependentSpecies, FNumDependentSpecies]));
    WriteLn;

    WriteLn('Independent species (x[] in ODE):');
    for I := 0 to FNumIndependentSpecies - 1 do
      WriteLn(Format('  x[%d] = %s  (FloatingSpecies[%d])',
        [I, FFloatingSpeciesNamesNatural[FIndependentSpeciesToNaturalIdx[I]], FIndependentSpeciesToNaturalIdx[I]]));
    WriteLn;

    WriteLn('Dependent species (reconstructed from conservation laws):');
    for I := 0 to FNumDependentSpecies - 1 do
      WriteLn(Format('  %s  (FloatingSpecies[%d])',
        [FFloatingSpeciesNamesNatural[FDependentSpeciesToNaturalIdx[I]], FDependentSpeciesToNaturalIdx[I]]));
    WriteLn;
  end
  else
  begin
    WriteLn('Floating Species (x[] array):');
    for I := 0 to FNumFloatingSpecies - 1 do
      WriteLn(Format('  x[%d] = %s', [I, FFloatingSpeciesNamesNatural[I]]));
    WriteLn;
  end;

  WriteLn(Format('Boundary Species (params[0..%d]):', [FNumBoundarySpecies - 1]));
  for I := 0 to FNumBoundarySpecies - 1 do
    WriteLn(Format('  params[%d] = %s', [I, FBoundarySpeciesNames[I]]));
  WriteLn;

  WriteLn(Format('Fundamental Parameters (params[%d..%d]):',
    [FNumBoundarySpecies, FNumBoundarySpecies + FNumParameters - 1]));
  for I := 0 to FNumParameters - 1 do
    WriteLn(Format('  params[%d] = %s', [FNumBoundarySpecies + I, FParameterNames[I]]));
  WriteLn;

  if FHasMoietyConservation then
  begin
    Offset := FNumBoundarySpecies + FNumParameters;
    WriteLn(Format('Conservation Constants T[] (params[%d..%d]):',
      [Offset, Offset + FNumDependentSpecies - 1]));
    for I := 0 to FNumDependentSpecies - 1 do
      WriteLn(Format('  params[%d] = T[%d]  (for %s)',
        [Offset + I, I, FFloatingSpeciesNamesNatural[FDependentSpeciesToNaturalIdx[I]]]));
    WriteLn;
  end;

  WriteLn('Derived Parameters (computed in C code):');
  for I := 0 to FNumDerived - 1 do
    WriteLn(Format('  %s', [FDerivedNames[I]]));
  WriteLn;

  WriteLn('Assignment Rules (computed each call):');
  for I := 0 to FModel.AssignmentRules.Count - 1 do
    WriteLn(Format('  %s', [FModel.AssignmentRules[I].Variable]));
  WriteLn;

  WriteLn('Reactions (rates[] array):');
  for I := 0 to FNumReactions - 1 do
    WriteLn(Format('  rates[%d] = %s', [I, FReactionNames[I]]));
  WriteLn;

  if Assigned(FModelFunction) then
  begin
    WriteLn('Current Reaction Rates:');
    RecomputeRates;
    for I := 0 to FNumReactions - 1 do
      WriteLn(Format('  %s = %g', [FReactionNames[I], FReactionRates[I]]));
  end
  else
    WriteLn('Reaction Rates: (ModelFunction not yet assigned)');
  WriteLn;
end;

// =============================================================================
// STRUCTURAL MATRICES
// =============================================================================

function TModelState.GetStoichiometryMatrix: TMatrixObj;
begin
  if not Assigned(FCachedN) then
    raise EModelStateError.Create(
      'GetStoichiometryMatrix: call BuildRunTimeModel first.');
  Result := FCachedN.Clone;
end;

function TModelState.GetReducedStoichiometryMatrix: TMatrixObj;
begin
  if not Assigned(FCachedNr) then
    raise EModelStateError.Create(
      'GetReducedStoichiometryMatrix: call BuildRunTimeModel first.');
  Result := FCachedNr.Clone;
end;

function TModelState.GetLinkMatrix: TMatrixObj;
begin
  if not Assigned(FCachedL) then
    raise EModelStateError.Create(
      'GetLinkMatrix: call BuildRunTimeModel first.');
  Result := FCachedL.Clone;
end;

function TModelState.GetConservationMatrix: TMatrixObj;
begin
  if not Assigned(FCachedGamma) then
    raise EModelStateError.Create(
      'GetConservationMatrix: call BuildRunTimeModel first.');

  Result := FCachedGamma.Clone;
end;

end.
