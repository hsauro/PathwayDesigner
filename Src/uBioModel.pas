unit uBioModel;

{
  uBioModel.pas
  =============
  Core data model for the biochemical network diagram editor.

  Version 2 additions
  -------------------
  TSpeciesNode    + InitialValue, IsBoundary, IsConstant, Compartment
  TReaction       + KineticLaw, IsReversible
                  + Reactants/Products are now TObjectList<TParticipant>
                    carrying stoichiometry per participant
  TBioModel       + ModelName, Compartments, Parameters, AssignmentRules

  New classes
  -----------
  TParticipant  — (Species ref, Stoichiometry)  owned by TReaction
  TCompartment          — (Id, Size, Dimensions)
  TParameter            — (Variable, Expression string)
  TAssignmentRule       — (Variable, Expression string)

  Alias nodes
  -----------
  A TSpeciesNode whose AliasOf <> nil is a visual alias of its primary.
  Aliases carry no independent biochemical data — they inherit everything
  from their primary via DisplayName, and biochemical fields are ignored
  on aliases during import/export.

  JSON version history
  --------------------
  v1  plain TSpeciesNode lists in reactants/products (no stoichiometry)
  v2  TParticipant lists; biochemical fields; compartments; parameters
}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  System.Types,
  System.Math;

type
  TSpeciesNode      = class;
  TReaction         = class;
  TParticipant = class;

// ===========================================================================
//  TParticipant
//  Owned by TReaction (via TObjectList with OwnsObjects=True).
//  Holds a non-owning reference to a TSpeciesNode.
// ===========================================================================
  TParticipant = class
  private
    FSpecies       : TSpeciesNode;
    FStoichiometry : Double;
    FCtrl1         : TPointF;   // Bézier control point near the species end
    FCtrl2         : TPointF;   // Bézier control point near the junction end
    FCtrlPtsSet    : Boolean;   // False = auto-compute; True = user-placed
  public
    constructor Create(ASpecies: TSpeciesNode; AStoichiometry: Double = 1.0);
    property Species       : TSpeciesNode read FSpecies       write FSpecies;
    property Stoichiometry : Double       read FStoichiometry write FStoichiometry;
    property Ctrl1         : TPointF      read FCtrl1         write FCtrl1;
    property Ctrl2         : TPointF      read FCtrl2         write FCtrl2;
    property CtrlPtsSet    : Boolean      read FCtrlPtsSet    write FCtrlPtsSet;
    // Clear manual control points — next render auto-computes them
    procedure ResetCtrlPts;
  end;

// ===========================================================================
//  TSpeciesNode
// ===========================================================================
  TSpeciesNode = class
  private
    FId           : string;
    FName         : string;
    FCenter       : TPointF;
    FWidth        : Single;
    FHeight       : Single;
    FSelected     : Boolean;
    FAliasOf      : TSpeciesNode;
    // Biochemical fields (primaries only; ignored on aliases)
    FInitialValue : Double;
    FIsBoundary   : Boolean;
    FIsConstant   : Boolean;
    FCompartment  : string;
  public
    constructor Create(const AId, AName : string;
                       AX, AY, AW, AH   : Single);

    property Id           : string       read FId           write FId;
    property Name         : string       read FName         write FName;
    property Center       : TPointF      read FCenter       write FCenter;
    property Width        : Single       read FWidth        write FWidth;
    property Height       : Single       read FHeight       write FHeight;
    property Selected     : Boolean      read FSelected     write FSelected;
    property AliasOf      : TSpeciesNode read FAliasOf      write FAliasOf;
    property InitialValue : Double       read FInitialValue write FInitialValue;
    property IsBoundary   : Boolean      read FIsBoundary   write FIsBoundary;
    property IsConstant   : Boolean      read FIsConstant   write FIsConstant;
    property Compartment  : string       read FCompartment  write FCompartment;

    function DisplayName : string;
    function IsAlias     : Boolean; inline;
    function HalfW       : Single;  inline;
    function HalfH       : Single;  inline;
    function BoundsRect  : TRectF;

    function  ToJSON: TJSONObject;
    class function FromJSON(AObj: TJSONObject): TSpeciesNode;
  end;

// ===========================================================================
//  TReaction
// ===========================================================================
  TReaction = class
  private
    FId          : string;
    FJunctionPos : TPointF;
    FReactants   : TObjectList<TParticipant>;
    FProducts    : TObjectList<TParticipant>;
    FSelected    : Boolean;
    FKineticLaw  : string;
    FIsReversible    : Boolean;
    FIsLinear        : Boolean;
    FIsBezier        : Boolean;   // True = render legs as cubic Bézier curves
    FIsJunctionSmooth: Boolean;   // True = collinear inner handles (C1 at junction)
  public
    constructor Create(const AId : string; AJX, AJY : Single);
    destructor  Destroy; override;

    property Id           : string                        read FId           write FId;
    property JunctionPos  : TPointF                       read FJunctionPos  write FJunctionPos;
    property Reactants    : TObjectList<TParticipant>     read FReactants;
    property Products     : TObjectList<TParticipant>     read FProducts;
    property Selected     : Boolean                       read FSelected     write FSelected;
    property KineticLaw   : string                        read FKineticLaw   write FKineticLaw;
    property IsReversible    : Boolean read FIsReversible    write FIsReversible;
    property IsLinear        : Boolean read FIsLinear        write FIsLinear;
    property IsBezier        : Boolean read FIsBezier        write FIsBezier;
    property IsJunctionSmooth: Boolean read FIsJunctionSmooth write FIsJunctionSmooth;

    function ReactantSpecies(AIndex: Integer): TSpeciesNode;
    function ProductSpecies (AIndex: Integer): TSpeciesNode;

    function ToJSON: TJSONObject;
  end;

// ===========================================================================
//  TCompartment
// ===========================================================================
  TCompartment = class
  private
    FId         : string;
    FSize       : Double;
    FDimensions : Integer;
  public
    constructor Create(const AId: string; ASize: Double = 1.0;
                       ADimensions: Integer = 3);
    property Id         : string  read FId         write FId;
    property Size       : Double  read FSize       write FSize;
    property Dimensions : Integer read FDimensions write FDimensions;
    function ToJSON: TJSONObject;
    class function FromJSON(AObj: TJSONObject): TCompartment;
  end;

// ===========================================================================
//  TParameter  (variable = expression, e.g. k1 = 0.1)
// ===========================================================================
  TParameter = class
  private
    FVariable   : string;
    FExpression : string;
  public
    constructor Create(const AVariable, AExpression: string);
    property Variable   : string read FVariable   write FVariable;
    property Expression : string read FExpression write FExpression;
    function ToJSON: TJSONObject;
    class function FromJSON(AObj: TJSONObject): TParameter;
  end;

// ===========================================================================
//  TAssignmentRule  (variable := expression, evaluated at each time step)
// ===========================================================================
  TAssignmentRule = class
  private
    FVariable   : string;
    FExpression : string;
  public
    constructor Create(const AVariable, AExpression: string);
    property Variable   : string read FVariable   write FVariable;
    property Expression : string read FExpression write FExpression;
    function ToJSON: TJSONObject;
    class function FromJSON(AObj: TJSONObject): TAssignmentRule;
  end;

// ===========================================================================
//  TBioModel
// ===========================================================================
  TBioModel = class
  private
    FModelName       : string;
    FSpecies         : TObjectList<TSpeciesNode>;
    FReactions       : TObjectList<TReaction>;
    FCompartments    : TObjectList<TCompartment>;
    FParameters      : TObjectList<TParameter>;
    FAssignmentRules : TObjectList<TAssignmentRule>;
    FNextId          : Integer;

    function  GenerateId(const Prefix: string): string;
    procedure SyncNextId;
  public
    constructor Create;
    destructor  Destroy; override;

    property ModelName       : string                        read FModelName       write FModelName;
    property Species         : TObjectList<TSpeciesNode>     read FSpecies;
    property Reactions       : TObjectList<TReaction>        read FReactions;
    property Compartments    : TObjectList<TCompartment>     read FCompartments;
    property Parameters      : TObjectList<TParameter>       read FParameters;
    property AssignmentRules : TObjectList<TAssignmentRule>  read FAssignmentRules;

    // --- Species factory ---
    function AddSpecies(const AName : string;
                        AX, AY      : Single;
                        AW          : Single = 80;
                        AH          : Single = 36): TSpeciesNode;
    function AddAlias  (APrimary: TSpeciesNode; AX, AY: Single): TSpeciesNode;

    // --- Reaction factory ---
    function AddReaction(AJX, AJY: Single): TReaction;

    // --- Biochemical model-level factories ---
    function AddCompartment (const AId: string;
                             ASize: Double = 1.0;
                             ADimensions: Integer = 3): TCompartment;
    function AddParameter   (const AVariable, AExpression: string): TParameter;
    function AddAssignmentRule(const AVariable, AExpression: string): TAssignmentRule;

    // --- Alias helpers ---
    function IsPrimary  (S: TSpeciesNode): Boolean; inline;
    function AliasesOf  (APrimary: TSpeciesNode): TArray<TSpeciesNode>;

    // --- Lookup ---
    function FindSpeciesById      (const AId: string): TSpeciesNode;
    function FindSpeciesByName    (const AName: string): TSpeciesNode;
    function FindReactionById     (const AId: string): TReaction;
    function FindCompartmentById  (const AId: string): TCompartment;
    function FindParameterByVar   (const AVar: string): TParameter;

    // --- Deletion ---
    procedure DeleteSpecies (ANode: TSpeciesNode;
                             out AffectedReactionIds: TArray<string>);
    procedure DeleteReaction(AReaction: TReaction);
    procedure Clear;

    // --- Selection ---
    procedure ClearSelection;
    function  SelectedSpecies  : TArray<TSpeciesNode>;
    function  SelectedReactions: TArray<TReaction>;

    // --- Persistence ---
    function  ToJSONObject  : TJSONObject;
    procedure FromJSONObject(AObj: TJSONObject);
    procedure SaveToFile    (const AFileName: string);
    procedure LoadFromFile  (const AFileName: string);

    // True when the model contains any compartment other than defaultCompartment
    function HasNonDefaultCompartments: Boolean;
  end;

implementation

const
  JSON_VERSION = 2;
  DEFAULT_COMPARTMENT = 'defaultCompartment';

// ===========================================================================
//  TParticipant
// ===========================================================================

constructor TParticipant.Create(ASpecies: TSpeciesNode;
                                        AStoichiometry: Double);
begin
  inherited Create;
  FSpecies       := ASpecies;
  FStoichiometry := AStoichiometry;
  FCtrl1         := TPointF.Create(0, 0);
  FCtrl2         := TPointF.Create(0, 0);
  FCtrlPtsSet    := False;
end;

procedure TParticipant.ResetCtrlPts;
begin
  FCtrl1      := TPointF.Create(0, 0);
  FCtrl2      := TPointF.Create(0, 0);
  FCtrlPtsSet := False;
end;

// ===========================================================================
//  TSpeciesNode
// ===========================================================================

constructor TSpeciesNode.Create(const AId, AName : string;
                                AX, AY, AW, AH   : Single);
begin
  inherited Create;
  FId           := AId;
  FName         := AName;
  FCenter       := TPointF.Create(AX, AY);
  FWidth        := AW;
  FHeight       := AH;
  FSelected     := False;
  FAliasOf      := nil;
  FInitialValue := 0.0;
  FIsBoundary   := False;
  FIsConstant   := False;
  FCompartment  := '';
end;

function TSpeciesNode.DisplayName: string;
begin
  if Assigned(FAliasOf) then Result := FAliasOf.FName
  else                       Result := FName;
end;

function TSpeciesNode.IsAlias: Boolean;
begin
  Result := Assigned(FAliasOf);
end;

function TSpeciesNode.HalfW: Single;
begin Result := FWidth  * 0.5; end;

function TSpeciesNode.HalfH: Single;
begin Result := FHeight * 0.5; end;

function TSpeciesNode.BoundsRect: TRectF;
begin
  Result := TRectF.Create(
    FCenter.X - HalfW, FCenter.Y - HalfH,
    FCenter.X + HalfW, FCenter.Y + HalfH);
end;

function TSpeciesNode.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',           FId);
  Result.AddPair('name',         FName);
  Result.AddPair('x',            TJSONNumber.Create(FCenter.X));
  Result.AddPair('y',            TJSONNumber.Create(FCenter.Y));
  Result.AddPair('w',            TJSONNumber.Create(FWidth));
  Result.AddPair('h',            TJSONNumber.Create(FHeight));
  Result.AddPair('initialValue', TJSONNumber.Create(FInitialValue));
  Result.AddPair('isBoundary',   TJSONBool.Create(FIsBoundary));
  Result.AddPair('isConstant',   TJSONBool.Create(FIsConstant));
  if FCompartment <> '' then
    Result.AddPair('compartment', FCompartment);
  if Assigned(FAliasOf) then
    Result.AddPair('aliasOf', FAliasOf.Id);
end;

class function TSpeciesNode.FromJSON(AObj: TJSONObject): TSpeciesNode;

  function GetFloat(O: TJSONObject; const K: string; Default: Single = 0): Single;
  var V: TJSONValue;
  begin
    V := O.GetValue(K);
    if Assigned(V) then Result := (V as TJSONNumber).AsDouble
    else                Result := Default;
  end;

  function GetBool(O: TJSONObject; const K: string; Default: Boolean = False): Boolean;
  var V: TJSONValue;
  begin
    V := O.GetValue(K);
    if Assigned(V) then Result := (V as TJSONBool).AsBoolean
    else                Result := Default;
  end;

var
  CompartVal : TJSONValue;
begin
  Result := TSpeciesNode.Create(
    AObj.GetValue('id').Value,
    AObj.GetValue('name').Value,
    GetFloat(AObj, 'x'), GetFloat(AObj, 'y'),
    GetFloat(AObj, 'w', 80), GetFloat(AObj, 'h', 36));
  Result.FInitialValue := GetFloat(AObj, 'initialValue');
  Result.FIsBoundary   := GetBool (AObj, 'isBoundary');
  Result.FIsConstant   := GetBool (AObj, 'isConstant');
  CompartVal := AObj.GetValue('compartment');
  if Assigned(CompartVal) then Result.FCompartment := CompartVal.Value;
  // AliasOf resolved in a second pass by TBioModel.FromJSONObject
end;

// ===========================================================================
//  TReaction
// ===========================================================================

constructor TReaction.Create(const AId : string; AJX, AJY : Single);
begin
  inherited Create;
  FId           := AId;
  FJunctionPos  := TPointF.Create(AJX, AJY);
  FReactants    := TObjectList<TParticipant>.Create(True);
  FProducts     := TObjectList<TParticipant>.Create(True);
  FSelected     := False;
  FKineticLaw   := '';
  FIsReversible  := False;
  FIsLinear      := False;
  FIsBezier      := False;
  FIsJunctionSmooth := False;
end;

destructor TReaction.Destroy;
begin
  FReactants.Free;
  FProducts.Free;
  inherited;
end;

function TReaction.ReactantSpecies(AIndex: Integer): TSpeciesNode;
begin
  Result := FReactants[AIndex].Species;
end;

function TReaction.ProductSpecies(AIndex: Integer): TSpeciesNode;
begin
  Result := FProducts[AIndex].Species;
end;

function TReaction.ToJSON: TJSONObject;
var
  Arr : TJSONArray;
  PObj: TJSONObject;
  P   : TParticipant;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',           FId);
  Result.AddPair('jx',           TJSONNumber.Create(FJunctionPos.X));
  Result.AddPair('jy',           TJSONNumber.Create(FJunctionPos.Y));
  Result.AddPair('kineticLaw',   FKineticLaw);
  Result.AddPair('isReversible',     TJSONBool.Create(FIsReversible));
  Result.AddPair('isLinear',         TJSONBool.Create(FIsLinear));
  Result.AddPair('isBezier',         TJSONBool.Create(FIsBezier));
  Result.AddPair('isJunctionSmooth', TJSONBool.Create(FIsJunctionSmooth));

  Arr := TJSONArray.Create;
  for P in FReactants do
  begin
    PObj := TJSONObject.Create;
    PObj.AddPair('id',            P.Species.Id);
    PObj.AddPair('stoichiometry', TJSONNumber.Create(P.Stoichiometry));
    if P.CtrlPtsSet then
    begin
      PObj.AddPair('ctrl1x', TJSONNumber.Create(P.Ctrl1.X));
      PObj.AddPair('ctrl1y', TJSONNumber.Create(P.Ctrl1.Y));
      PObj.AddPair('ctrl2x', TJSONNumber.Create(P.Ctrl2.X));
      PObj.AddPair('ctrl2y', TJSONNumber.Create(P.Ctrl2.Y));
      PObj.AddPair('ctrlSet', TJSONBool.Create(True));
    end;
    Arr.AddElement(PObj);
  end;
  Result.AddPair('reactants', Arr);

  Arr := TJSONArray.Create;
  for P in FProducts do
  begin
    PObj := TJSONObject.Create;
    PObj.AddPair('id',            P.Species.Id);
    PObj.AddPair('stoichiometry', TJSONNumber.Create(P.Stoichiometry));
    if P.CtrlPtsSet then
    begin
      PObj.AddPair('ctrl1x', TJSONNumber.Create(P.Ctrl1.X));
      PObj.AddPair('ctrl1y', TJSONNumber.Create(P.Ctrl1.Y));
      PObj.AddPair('ctrl2x', TJSONNumber.Create(P.Ctrl2.X));
      PObj.AddPair('ctrl2y', TJSONNumber.Create(P.Ctrl2.Y));
      PObj.AddPair('ctrlSet', TJSONBool.Create(True));
    end;
    Arr.AddElement(PObj);
  end;
  Result.AddPair('products', Arr);
end;

// ===========================================================================
//  TCompartment
// ===========================================================================

constructor TCompartment.Create(const AId: string; ASize: Double;
                                ADimensions: Integer);
begin
  inherited Create;
  FId         := AId;
  FSize       := ASize;
  FDimensions := ADimensions;
end;

function TCompartment.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',         FId);
  Result.AddPair('size',       TJSONNumber.Create(FSize));
  Result.AddPair('dimensions', TJSONNumber.Create(FDimensions));
end;

class function TCompartment.FromJSON(AObj: TJSONObject): TCompartment;
begin
  Result := TCompartment.Create(
    AObj.GetValue('id').Value,
    (AObj.GetValue('size')       as TJSONNumber).AsDouble,
    (AObj.GetValue('dimensions') as TJSONNumber).AsInt);
end;

// ===========================================================================
//  TParameter
// ===========================================================================

constructor TParameter.Create(const AVariable, AExpression: string);
begin
  inherited Create;
  FVariable   := AVariable;
  FExpression := AExpression;
end;

function TParameter.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('variable',   FVariable);
  Result.AddPair('expression', FExpression);
end;

class function TParameter.FromJSON(AObj: TJSONObject): TParameter;
begin
  Result := TParameter.Create(
    AObj.GetValue('variable').Value,
    AObj.GetValue('expression').Value);
end;

// ===========================================================================
//  TAssignmentRule
// ===========================================================================

constructor TAssignmentRule.Create(const AVariable, AExpression: string);
begin
  inherited Create;
  FVariable   := AVariable;
  FExpression := AExpression;
end;

function TAssignmentRule.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('variable',   FVariable);
  Result.AddPair('expression', FExpression);
end;

class function TAssignmentRule.FromJSON(AObj: TJSONObject): TAssignmentRule;
begin
  Result := TAssignmentRule.Create(
    AObj.GetValue('variable').Value,
    AObj.GetValue('expression').Value);
end;

// ===========================================================================
//  TBioModel
// ===========================================================================

constructor TBioModel.Create;
begin
  inherited Create;
  FSpecies         := TObjectList<TSpeciesNode>.Create(True);
  FReactions       := TObjectList<TReaction>.Create(True);
  FCompartments    := TObjectList<TCompartment>.Create(True);
  FParameters      := TObjectList<TParameter>.Create(True);
  FAssignmentRules := TObjectList<TAssignmentRule>.Create(True);
  FNextId          := 1;
  FModelName       := '';
end;

destructor TBioModel.Destroy;
begin
  FReactions.Free;       // free edges before nodes
  FSpecies.Free;
  FCompartments.Free;
  FParameters.Free;
  FAssignmentRules.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
//  ID generation
// ---------------------------------------------------------------------------

function TBioModel.GenerateId(const Prefix: string): string;
begin
  Result := Prefix + IntToStr(FNextId);
  Inc(FNextId);
end;

procedure TBioModel.SyncNextId;
var
  S      : TSpeciesNode;
  R      : TReaction;
  Num    : Integer;
  MaxNum : Integer;
  Suffix : string;
begin
  MaxNum := 0;
  for S in FSpecies do
  begin
    Suffix := Copy(S.Id, 2, MaxInt);
    if TryStrToInt(Suffix, Num) and (Num > MaxNum) then MaxNum := Num;
  end;
  for R in FReactions do
  begin
    Suffix := Copy(R.Id, 2, MaxInt);
    if TryStrToInt(Suffix, Num) and (Num > MaxNum) then MaxNum := Num;
  end;
  FNextId := MaxNum + 1;
end;

// ---------------------------------------------------------------------------
//  Factories
// ---------------------------------------------------------------------------

function TBioModel.AddSpecies(const AName : string;
                              AX, AY, AW, AH : Single): TSpeciesNode;
begin
  Result := TSpeciesNode.Create(GenerateId('s'), AName, AX, AY, AW, AH);
  FSpecies.Add(Result);
end;

function TBioModel.AddAlias(APrimary: TSpeciesNode; AX, AY: Single): TSpeciesNode;
var
  Root : TSpeciesNode;
begin
  Root           := APrimary;
  if Root.IsAlias then Root := Root.AliasOf;
  Result         := TSpeciesNode.Create(GenerateId('s'), Root.Name,
                                        AX, AY, Root.Width, Root.Height);
  Result.AliasOf := Root;
  FSpecies.Add(Result);
end;

function TBioModel.AddReaction(AJX, AJY: Single): TReaction;
begin
  Result := TReaction.Create(GenerateId('r'), AJX, AJY);
  FReactions.Add(Result);
end;

function TBioModel.AddCompartment(const AId: string; ASize: Double;
                                  ADimensions: Integer): TCompartment;
begin
  Result := TCompartment.Create(AId, ASize, ADimensions);
  FCompartments.Add(Result);
end;

function TBioModel.AddParameter(const AVariable, AExpression: string): TParameter;
begin
  Result := TParameter.Create(AVariable, AExpression);
  FParameters.Add(Result);
end;

function TBioModel.AddAssignmentRule(const AVariable,
                                     AExpression: string): TAssignmentRule;
begin
  Result := TAssignmentRule.Create(AVariable, AExpression);
  FAssignmentRules.Add(Result);
end;

// ---------------------------------------------------------------------------
//  Alias helpers
// ---------------------------------------------------------------------------

function TBioModel.IsPrimary(S: TSpeciesNode): Boolean;
begin
  Result := not S.IsAlias;
end;

function TBioModel.AliasesOf(APrimary: TSpeciesNode): TArray<TSpeciesNode>;
var
  S    : TSpeciesNode;
  List : TList<TSpeciesNode>;
begin
  List := TList<TSpeciesNode>.Create;
  try
    for S in FSpecies do
      if S.AliasOf = APrimary then List.Add(S);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Lookup
// ---------------------------------------------------------------------------

function TBioModel.FindSpeciesById(const AId: string): TSpeciesNode;
var
  S : TSpeciesNode;
begin
  Result := nil;
  for S in FSpecies do if S.Id = AId then Exit(S);
end;

function TBioModel.FindSpeciesByName(const AName: string): TSpeciesNode;
var
  S : TSpeciesNode;
begin
  // Returns the first PRIMARY node with this name (ignores aliases)
  Result := nil;
  for S in FSpecies do
    if (not S.IsAlias) and SameText(S.Name, AName) then Exit(S);
end;

function TBioModel.FindReactionById(const AId: string): TReaction;
var
  R : TReaction;
begin
  Result := nil;
  for R in FReactions do if R.Id = AId then Exit(R);
end;

function TBioModel.FindCompartmentById(const AId: string): TCompartment;
var
  C : TCompartment;
begin
  Result := nil;
  for C in FCompartments do if SameText(C.Id, AId) then Exit(C);
end;

function TBioModel.FindParameterByVar(const AVar: string): TParameter;
var
  P : TParameter;
begin
  Result := nil;
  for P in FParameters do if SameText(P.Variable, AVar) then Exit(P);
end;

// ---------------------------------------------------------------------------
//  Deletion
// ---------------------------------------------------------------------------

procedure TBioModel.DeleteSpecies(ANode: TSpeciesNode;
                                  out AffectedReactionIds: TArray<string>);
var
  NodesToRemove : TList<TSpeciesNode>;
  Condemned     : TList<TReaction>;
  Aliases       : TArray<TSpeciesNode>;
  R             : TReaction;
  S             : TSpeciesNode;
  P             : TParticipant;
  i             : Integer;

  function ReferencesAny(AReaction: TReaction): Boolean;
  var
    Node : TSpeciesNode;
    Part : TParticipant;
  begin
    for Node in NodesToRemove do
    begin
      for Part in AReaction.Reactants do
        if Part.Species = Node then Exit(True);
      for Part in AReaction.Products do
        if Part.Species = Node then Exit(True);
    end;
    Result := False;
  end;

begin
  NodesToRemove := TList<TSpeciesNode>.Create;
  try
    NodesToRemove.Add(ANode);
    if not ANode.IsAlias then
    begin
      Aliases := AliasesOf(ANode);
      for S in Aliases do NodesToRemove.Add(S);
    end;

    Condemned := TList<TReaction>.Create;
    try
      for R in FReactions do
        if ReferencesAny(R) then Condemned.Add(R);

      SetLength(AffectedReactionIds, Condemned.Count);
      for i := 0 to Condemned.Count - 1 do
        AffectedReactionIds[i] := Condemned[i].Id;

      for R in Condemned do FReactions.Remove(R);
    finally
      Condemned.Free;
    end;

    for S in NodesToRemove do FSpecies.Remove(S);
  finally
    NodesToRemove.Free;
  end;
end;

procedure TBioModel.DeleteReaction(AReaction: TReaction);
begin
  FReactions.Remove(AReaction);
end;

procedure TBioModel.Clear;
begin
  FReactions.Clear;
  FSpecies.Clear;
  FCompartments.Clear;
  FParameters.Clear;
  FAssignmentRules.Clear;
  FNextId    := 1;
  FModelName := '';
end;

// ---------------------------------------------------------------------------
//  Selection
// ---------------------------------------------------------------------------

procedure TBioModel.ClearSelection;
var
  S : TSpeciesNode;
  R : TReaction;
begin
  for S in FSpecies   do S.Selected := False;
  for R in FReactions do R.Selected := False;
end;

function TBioModel.SelectedSpecies: TArray<TSpeciesNode>;
var
  S    : TSpeciesNode;
  List : TList<TSpeciesNode>;
begin
  List := TList<TSpeciesNode>.Create;
  try
    for S in FSpecies do if S.Selected then List.Add(S);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TBioModel.SelectedReactions: TArray<TReaction>;
var
  R    : TReaction;
  List : TList<TReaction>;
begin
  List := TList<TReaction>.Create;
  try
    for R in FReactions do if R.Selected then List.Add(R);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Compartment utility
// ---------------------------------------------------------------------------

function TBioModel.HasNonDefaultCompartments: Boolean;
var
  C : TCompartment;
begin
  for C in FCompartments do
    if not SameText(C.Id, DEFAULT_COMPARTMENT) then Exit(True);
  Result := False;
end;

// ---------------------------------------------------------------------------
//  Persistence
// ---------------------------------------------------------------------------

function TBioModel.ToJSONObject: TJSONObject;
var
  Arr : TJSONArray;
  S   : TSpeciesNode;
  R   : TReaction;
  C   : TCompartment;
  P   : TParameter;
  AR  : TAssignmentRule;
begin
  Result := TJSONObject.Create;
  Result.AddPair('version',   TJSONNumber.Create(JSON_VERSION));
  Result.AddPair('modelName', FModelName);

  Arr := TJSONArray.Create;
  for C in FCompartments do Arr.AddElement(C.ToJSON);
  Result.AddPair('compartments', Arr);

  Arr := TJSONArray.Create;
  for P in FParameters do Arr.AddElement(P.ToJSON);
  Result.AddPair('parameters', Arr);

  Arr := TJSONArray.Create;
  for AR in FAssignmentRules do Arr.AddElement(AR.ToJSON);
  Result.AddPair('assignmentRules', Arr);

  Arr := TJSONArray.Create;
  for S in FSpecies do Arr.AddElement(S.ToJSON);
  Result.AddPair('species', Arr);

  Arr := TJSONArray.Create;
  for R in FReactions do Arr.AddElement(R.ToJSON);
  Result.AddPair('reactions', Arr);
end;

procedure TBioModel.FromJSONObject(AObj: TJSONObject);
var
  Arr     : TJSONArray;
  RctObj  : TJSONObject;
  PObj    : TJSONObject;
  AliasV  : TJSONValue;
  KLVal   : TJSONValue;
  RevVal  : TJSONValue;
  MNVal   : TJSONValue;
  VerVal  : TJSONValue;
  Version : Integer;
  R       : TReaction;
  S       : TSpeciesNode;
  i, j    : Integer;
  Stoich  : Double;
begin
  Clear;

  VerVal  := AObj.GetValue('version');
  Version := 1;
  if Assigned(VerVal) then Version := (VerVal as TJSONNumber).AsInt;

  MNVal := AObj.GetValue('modelName');
  if Assigned(MNVal) then FModelName := MNVal.Value;

  // --- Compartments ---
  Arr := AObj.GetValue('compartments') as TJSONArray;
  if Assigned(Arr) then
    for i := 0 to Arr.Count - 1 do
      FCompartments.Add(TCompartment.FromJSON(Arr.Items[i] as TJSONObject));

  // --- Parameters ---
  Arr := AObj.GetValue('parameters') as TJSONArray;
  if Assigned(Arr) then
    for i := 0 to Arr.Count - 1 do
      FParameters.Add(TParameter.FromJSON(Arr.Items[i] as TJSONObject));

  // --- Assignment rules ---
  Arr := AObj.GetValue('assignmentRules') as TJSONArray;
  if Assigned(Arr) then
    for i := 0 to Arr.Count - 1 do
      FAssignmentRules.Add(TAssignmentRule.FromJSON(Arr.Items[i] as TJSONObject));

  // --- Species pass 1: create nodes ---
  Arr := AObj.GetValue('species') as TJSONArray;
  if Assigned(Arr) then
    for i := 0 to Arr.Count - 1 do
      FSpecies.Add(TSpeciesNode.FromJSON(Arr.Items[i] as TJSONObject));

  // --- Species pass 2: resolve aliasOf pointers ---
  if Assigned(Arr) then
    for i := 0 to Arr.Count - 1 do
    begin
      AliasV := (Arr.Items[i] as TJSONObject).GetValue('aliasOf');
      if Assigned(AliasV) and (AliasV.Value <> '') then
      begin
        S := FindSpeciesById(AliasV.Value);
        if Assigned(S) then FSpecies[i].AliasOf := S;
      end;
    end;

  // --- Reactions ---
  Arr := AObj.GetValue('reactions') as TJSONArray;
  if not Assigned(Arr) then begin SyncNextId; Exit; end;

  for i := 0 to Arr.Count - 1 do
  begin
    RctObj := Arr.Items[i] as TJSONObject;
    R := TReaction.Create(
      RctObj.GetValue('id').Value,
      (RctObj.GetValue('jx') as TJSONNumber).AsDouble,
      (RctObj.GetValue('jy') as TJSONNumber).AsDouble);

    KLVal := RctObj.GetValue('kineticLaw');
    if Assigned(KLVal) then R.KineticLaw := KLVal.Value;

    RevVal := RctObj.GetValue('isReversible');
    if Assigned(RevVal) then R.IsReversible := (RevVal as TJSONBool).AsBoolean;

    var LinVal := RctObj.GetValue('isLinear');
    if Assigned(LinVal) then R.IsLinear := (LinVal as TJSONBool).AsBoolean;

    var BezVal := RctObj.GetValue('isBezier');
    if Assigned(BezVal) then R.IsBezier := (BezVal as TJSONBool).AsBoolean;

    var JSVal := RctObj.GetValue('isJunctionSmooth');
    if Assigned(JSVal) then R.IsJunctionSmooth := (JSVal as TJSONBool).AsBoolean;

    // Helper to load a participant object with optional control points
    var LoadParticipant := procedure(APObj: TJSONObject; AList: TObjectList<TParticipant>)
    var
      Part     : TParticipant;
      ASpecies : TSpeciesNode;
      AStoich  : Double;
      CV       : TJSONValue;
    begin
      ASpecies := FindSpeciesById(APObj.GetValue('id').Value);
      if not Assigned(ASpecies) then Exit;
      AStoich := 1.0;
      CV := APObj.GetValue('stoichiometry');
      if Assigned(CV) then AStoich := (CV as TJSONNumber).AsDouble;
      Part := TParticipant.Create(ASpecies, AStoich);
      CV := APObj.GetValue('ctrlSet');
      if Assigned(CV) and (CV as TJSONBool).AsBoolean then
      begin
        Part.Ctrl1 := TPointF.Create(
          (APObj.GetValue('ctrl1x') as TJSONNumber).AsDouble,
          (APObj.GetValue('ctrl1y') as TJSONNumber).AsDouble);
        Part.Ctrl2 := TPointF.Create(
          (APObj.GetValue('ctrl2x') as TJSONNumber).AsDouble,
          (APObj.GetValue('ctrl2y') as TJSONNumber).AsDouble);
        Part.CtrlPtsSet := True;
      end;
      AList.Add(Part);
    end;

    // Reactants — support both v1 (plain id string) and v2 (object with stoich)
    var ReactArr := RctObj.GetValue('reactants') as TJSONArray;
    for j := 0 to ReactArr.Count - 1 do
    begin
      Stoich := 1.0;
      if Version >= 2 then
      begin
        PObj := ReactArr.Items[j] as TJSONObject;
        LoadParticipant(PObj, R.Reactants);
      end
      else
      begin
        S := FindSpeciesById(ReactArr.Items[j].Value);
        if Assigned(S) then R.Reactants.Add(TParticipant.Create(S, 1.0));
      end;
    end;

    // Products
    var ProdArr := RctObj.GetValue('products') as TJSONArray;
    for j := 0 to ProdArr.Count - 1 do
    begin
      Stoich := 1.0;
      if Version >= 2 then
      begin
        PObj := ProdArr.Items[j] as TJSONObject;
        LoadParticipant(PObj, R.Products);
      end
      else
      begin
        S := FindSpeciesById(ProdArr.Items[j].Value);
        if Assigned(S) then R.Products.Add(TParticipant.Create(S, 1.0));
      end;
    end;

    FReactions.Add(R);
  end;

  SyncNextId;
end;

procedure TBioModel.SaveToFile(const AFileName: string);
var
  JObj : TJSONObject;
  SL   : TStringList;
begin
  JObj := ToJSONObject;
  try
    SL := TStringList.Create;
    try
      SL.Text := JObj.Format(2);
      SL.SaveToFile(AFileName, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    JObj.Free;
  end;
end;

procedure TBioModel.LoadFromFile(const AFileName: string);
var
  SL   : TStringList;
  JObj : TJSONObject;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(AFileName, TEncoding.UTF8);
    JObj := TJSONObject.ParseJSONValue(SL.Text) as TJSONObject;
    if not Assigned(JObj) then
      raise EInvalidOpException.CreateFmt(
        'File "%s" does not contain valid JSON.', [AFileName]);
    try
      FromJSONObject(JObj);
    finally
      JObj.Free;
    end;
  finally
    SL.Free;
  end;
end;

end.
