unit uUndoManager;

{
  uUndoManager.pas
  ================
  Command-pattern undo/redo manager for the biochemical network editor.

  Design rules
  ------------
  - NO dependency on uDiagramView or any FMX unit.
  - TSnapshotCmd round-trips the full model via JSON strings plus an
    after-restore callback for TDiagramView-level state (FNextSpeciesNum).
    Use it for structural changes: add, delete, rename, alias, layout, import,
    reaction-mode changes.
  - Lightweight commands (TMoveNodesCmd, TMoveJunctionCmd, TDragCtrlPtCmd)
    store only positions and look up model objects by Id on Undo/Redo.
    These cover the high-frequency drag interactions.
  - TUndoManager owns both stacks; Push always clears the redo stack.
}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  uBioModel;

// ---------------------------------------------------------------------------
// Callback invoked by TSnapshotCmd after restoring the model so that
// TDiagramView can fix up view-only state (FNextSpeciesNum, etc.).
type
  TAfterRestoreProc = reference to procedure(ANextSpeciesNum: Integer);

// ===========================================================================
//  Abstract base
// ===========================================================================

  TDiagramCommand = class abstract
  public
    function  Description: string; virtual; abstract;
    procedure Undo; virtual; abstract;
    procedure Redo; virtual; abstract;
  end;

// ===========================================================================
//  TSnapshotCmd
//  Full model JSON snapshot — structural / mode changes.
// ===========================================================================

  TSnapshotCmd = class(TDiagramCommand)
  private
    FDescription : string;
    FModel       : TBioModel;    // non-owning ref
    FBefore      : string;       // compact JSON before operation
    FAfter       : string;       // compact JSON after operation
    FBeforeNum   : Integer;      // TDiagramView.FNextSpeciesNum before
    FAfterNum    : Integer;      // TDiagramView.FNextSpeciesNum after
    FOnRestore   : TAfterRestoreProc;
    procedure Restore(const AJson: string; ANum: Integer);
  public
    constructor Create(const ADescription : string;
                       AModel             : TBioModel;
                       const ABefore      : string;
                       const AAfter       : string;
                       ABeforeNum         : Integer;
                       AAfterNum          : Integer;
                       AOnRestore         : TAfterRestoreProc);
    function  Description: string; override;
    procedure Undo; override;
    procedure Redo; override;
  end;

// ===========================================================================
//  TMoveNodesCmd
//  Node/junction drag — positions stored by Id string.
// ===========================================================================

  TMoveNodesCmd = class(TDiagramCommand)
  private
    FModel         : TBioModel;
    // Owned dictionaries: species Id -> world position
    FSpeciesBefore : TDictionary<string, TPointF>;
    FSpeciesAfter  : TDictionary<string, TPointF>;
    // Owned dictionaries: reaction Id -> junction position
    FJunctionBefore: TDictionary<string, TPointF>;
    FJunctionAfter : TDictionary<string, TPointF>;
    procedure ApplySpecies  (APos: TDictionary<string, TPointF>);
    procedure ApplyJunctions(APos: TDictionary<string, TPointF>);
  public
    // Takes ownership of all four dictionaries.
    constructor Create(AModel: TBioModel;
                       ASpeciesBefore, ASpeciesAfter   : TDictionary<string, TPointF>;
                       AJunctionBefore, AJunctionAfter : TDictionary<string, TPointF>);
    destructor Destroy; override;
    function  Description: string; override;
    procedure Undo; override;
    procedure Redo; override;
  end;

// ===========================================================================
//  TMoveJunctionCmd
//  Single junction drag.
// ===========================================================================

  TMoveJunctionCmd = class(TDiagramCommand)
  private
    FModel      : TBioModel;
    FReactionId : string;
    FOldPos     : TPointF;
    FNewPos     : TPointF;
    procedure Apply(const APos: TPointF);
  public
    constructor Create(AModel: TBioModel; const AReactionId: string;
                       const AOldPos, ANewPos: TPointF);
    function  Description: string; override;
    procedure Undo; override;
    procedure Redo; override;
  end;

// ===========================================================================
//  TDragCtrlPtCmd
//  Bezier control-point drag.
// ===========================================================================

  TCtrlPtState = record
    Ctrl1      : TPointF;
    Ctrl2      : TPointF;
    CtrlPtsSet : Boolean;
  end;

  TDragCtrlPtCmd = class(TDiagramCommand)
  private
    FModel      : TBioModel;
    FReactionId : string;
    FIsReactant : Boolean;
    FPartIndex  : Integer;
    FOldState   : TCtrlPtState;
    FNewState   : TCtrlPtState;
    function FindParticipant: TParticipant;
    procedure Apply(const AState: TCtrlPtState);
  public
    constructor Create(AModel: TBioModel; const AReactionId: string;
                       AIsReactant: Boolean; APartIndex: Integer;
                       const AOld, ANew: TCtrlPtState);
    function  Description: string; override;
    procedure Undo; override;
    procedure Redo; override;
  end;

// ===========================================================================
//  TUndoManager
// ===========================================================================

  TUndoManager = class
  private
    FUndoStack : TObjectList<TDiagramCommand>;
    FRedoStack : TObjectList<TDiagramCommand>;
    FMaxDepth  : Integer;
  public
    constructor Create(AMaxDepth: Integer = 100);
    destructor  Destroy; override;

    // Takes ownership of ACmd; clears the redo stack.
    procedure Push(ACmd: TDiagramCommand);
    procedure Undo;
    procedure Redo;
    // Clear both stacks (e.g. on file load or new diagram).
    procedure Clear;

    function CanUndo          : Boolean;
    function CanRedo          : Boolean;
    function UndoDescription  : string;
    function RedoDescription  : string;
  end;

implementation

// ===========================================================================
//  TSnapshotCmd
// ===========================================================================

constructor TSnapshotCmd.Create(const ADescription : string;
                                 AModel             : TBioModel;
                                 const ABefore      : string;
                                 const AAfter       : string;
                                 ABeforeNum         : Integer;
                                 AAfterNum          : Integer;
                                 AOnRestore         : TAfterRestoreProc);
begin
  inherited Create;
  FDescription := ADescription;
  FModel       := AModel;
  FBefore      := ABefore;
  FAfter       := AAfter;
  FBeforeNum   := ABeforeNum;
  FAfterNum    := AAfterNum;
  FOnRestore   := AOnRestore;
end;

function TSnapshotCmd.Description: string;
begin
  Result := FDescription;
end;

procedure TSnapshotCmd.Restore(const AJson: string; ANum: Integer);
var
  JObj : TJSONObject;
begin
  JObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Assigned(JObj) then
  try
    FModel.FromJSONObject(JObj);
  finally
    JObj.Free;
  end;
  if Assigned(FOnRestore) then
    FOnRestore(ANum);
end;

procedure TSnapshotCmd.Undo;
begin
  Restore(FBefore, FBeforeNum);
end;

procedure TSnapshotCmd.Redo;
begin
  Restore(FAfter, FAfterNum);
end;

// ===========================================================================
//  TMoveNodesCmd
// ===========================================================================

constructor TMoveNodesCmd.Create(AModel: TBioModel;
                                  ASpeciesBefore, ASpeciesAfter   : TDictionary<string, TPointF>;
                                  AJunctionBefore, AJunctionAfter : TDictionary<string, TPointF>);
begin
  inherited Create;
  FModel          := AModel;
  FSpeciesBefore  := ASpeciesBefore;
  FSpeciesAfter   := ASpeciesAfter;
  FJunctionBefore := AJunctionBefore;
  FJunctionAfter  := AJunctionAfter;
end;

destructor TMoveNodesCmd.Destroy;
begin
  FSpeciesBefore.Free;
  FSpeciesAfter.Free;
  FJunctionBefore.Free;
  FJunctionAfter.Free;
  inherited;
end;

function TMoveNodesCmd.Description: string;
begin
  Result := 'Move';
end;

procedure TMoveNodesCmd.ApplySpecies(APos: TDictionary<string, TPointF>);
var
  Pair    : TPair<string, TPointF>;
  Species : TSpeciesNode;
begin
  for Pair in APos do
  begin
    Species := FModel.FindSpeciesById(Pair.Key);
    if Assigned(Species) then
      Species.Center := Pair.Value;
  end;
end;

procedure TMoveNodesCmd.ApplyJunctions(APos: TDictionary<string, TPointF>);
var
  Pair     : TPair<string, TPointF>;
  Reaction : TReaction;
begin
  for Pair in APos do
  begin
    Reaction := FModel.FindReactionById(Pair.Key);
    if Assigned(Reaction) then
      Reaction.JunctionPos := Pair.Value;
  end;
end;

procedure TMoveNodesCmd.Undo;
begin
  ApplySpecies  (FSpeciesBefore);
  ApplyJunctions(FJunctionBefore);
end;

procedure TMoveNodesCmd.Redo;
begin
  ApplySpecies  (FSpeciesAfter);
  ApplyJunctions(FJunctionAfter);
end;

// ===========================================================================
//  TMoveJunctionCmd
// ===========================================================================

constructor TMoveJunctionCmd.Create(AModel: TBioModel; const AReactionId: string;
                                     const AOldPos, ANewPos: TPointF);
begin
  inherited Create;
  FModel      := AModel;
  FReactionId := AReactionId;
  FOldPos     := AOldPos;
  FNewPos     := ANewPos;
end;

function TMoveJunctionCmd.Description: string;
begin
  Result := 'Move junction';
end;

procedure TMoveJunctionCmd.Apply(const APos: TPointF);
var
  R : TReaction;
begin
  R := FModel.FindReactionById(FReactionId);
  if Assigned(R) then R.JunctionPos := APos;
end;

procedure TMoveJunctionCmd.Undo;
begin Apply(FOldPos); end;

procedure TMoveJunctionCmd.Redo;
begin Apply(FNewPos); end;

// ===========================================================================
//  TDragCtrlPtCmd
// ===========================================================================

constructor TDragCtrlPtCmd.Create(AModel: TBioModel; const AReactionId: string;
                                   AIsReactant: Boolean; APartIndex: Integer;
                                   const AOld, ANew: TCtrlPtState);
begin
  inherited Create;
  FModel      := AModel;
  FReactionId := AReactionId;
  FIsReactant := AIsReactant;
  FPartIndex  := APartIndex;
  FOldState   := AOld;
  FNewState   := ANew;
end;

function TDragCtrlPtCmd.Description: string;
begin
  Result := 'Move control point';
end;

function TDragCtrlPtCmd.FindParticipant: TParticipant;
var
  R    : TReaction;
  List : TObjectList<TParticipant>;
begin
  Result := nil;
  R := FModel.FindReactionById(FReactionId);
  if not Assigned(R) then Exit;
  if FIsReactant then List := R.Reactants else List := R.Products;
  if (FPartIndex >= 0) and (FPartIndex < List.Count) then
    Result := List[FPartIndex];
end;

procedure TDragCtrlPtCmd.Apply(const AState: TCtrlPtState);
var
  P : TParticipant;
begin
  P := FindParticipant;
  if not Assigned(P) then Exit;
  P.Ctrl1      := AState.Ctrl1;
  P.Ctrl2      := AState.Ctrl2;
  P.CtrlPtsSet := AState.CtrlPtsSet;
end;

procedure TDragCtrlPtCmd.Undo;
begin Apply(FOldState); end;

procedure TDragCtrlPtCmd.Redo;
begin Apply(FNewState); end;

// ===========================================================================
//  TUndoManager
// ===========================================================================

constructor TUndoManager.Create(AMaxDepth: Integer);
begin
  inherited Create;
  FMaxDepth  := AMaxDepth;
  FUndoStack := TObjectList<TDiagramCommand>.Create(True);
  FRedoStack := TObjectList<TDiagramCommand>.Create(True);
end;

destructor TUndoManager.Destroy;
begin
  FUndoStack.Free;
  FRedoStack.Free;
  inherited;
end;

procedure TUndoManager.Push(ACmd: TDiagramCommand);
begin
  // Trim undo stack to max depth (remove oldest)
  while FUndoStack.Count >= FMaxDepth do
    FUndoStack.Delete(0);
  FUndoStack.Add(ACmd);
  // Any new action clears the redo history
  FRedoStack.Clear;
end;

procedure TUndoManager.Undo;
var
  Cmd : TDiagramCommand;
begin
  if FUndoStack.Count = 0 then Exit;
  Cmd := FUndoStack.Last;
  FUndoStack.Extract(Cmd);  // remove without freeing
  Cmd.Undo;
  FRedoStack.Add(Cmd);
end;

procedure TUndoManager.Redo;
var
  Cmd : TDiagramCommand;
begin
  if FRedoStack.Count = 0 then Exit;
  Cmd := FRedoStack.Last;
  FRedoStack.Extract(Cmd);
  Cmd.Redo;
  FUndoStack.Add(Cmd);
end;

procedure TUndoManager.Clear;
begin
  FUndoStack.Clear;
  FRedoStack.Clear;
end;

function TUndoManager.CanUndo: Boolean;
begin
  Result := FUndoStack.Count > 0;
end;

function TUndoManager.CanRedo: Boolean;
begin
  Result := FRedoStack.Count > 0;
end;

function TUndoManager.UndoDescription: string;
begin
  if FUndoStack.Count > 0 then
    Result := 'Undo ' + FUndoStack.Last.Description
  else
    Result := 'Undo';
end;

function TUndoManager.RedoDescription: string;
begin
  if FRedoStack.Count > 0 then
    Result := 'Redo ' + FRedoStack.Last.Description
  else
    Result := 'Redo';
end;

end.
