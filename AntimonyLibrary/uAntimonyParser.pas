unit uAntimonyParser;

interface

uses
  Classes, SysUtils,
  System.TypInfo,
  Generics.Collections,
  uAntimonyModelType,
  uAntimonyLexer,
  uAntimonyExpressionParser,
  uExpressionNode;

type
  // Parser for Antimony language
  TAntimonyParser = class
  private
    FLexer: TAntimonyLexer;

    function Match(ATokenType: TTokenType): Boolean; overload;
    function Match(AKeyword: TAntimonyKeyword): Boolean; overload;
    function Consume(ATokenType: TTokenType; const AErrorMsg: string = ''): TToken; overload;
    function Consume(AKeyword: TAntimonyKeyword; const AErrorMsg: string = ''): TToken; overload;
    function IsAtEnd: Boolean;
    procedure Error(const AMessage: string);

    // Expression parsing helper
    function ParseExpression : TExpressionNode;

    // Parsing methods
    function ParseModel: TAntimonyModel;
    procedure ParseStatement(AModel: TAntimonyModel);
    procedure ParseSpeciesDeclaration(AModel: TAntimonyModel; AIsBoundaryPrefix: Boolean = False);
    procedure ParseCompartmentDeclaration(AModel: TAntimonyModel);
    procedure ParseReaction(AModel: TAntimonyModel);
    procedure ParseAssignment(AModel: TAntimonyModel);
    procedure ParseAssignmentRule(AModel: TAntimonyModel);
    function  ParseReactionParticipants: TArray<TReactionParticipant>;
    function  ParseNumber: Double;
    function  ParseIdentifierList: TArray<string>;

    procedure ExtractParametersFromKineticLaws (AModel : TAntimonyModel);
  public
    constructor Create(ALexer: TAntimonyLexer);
    destructor Destroy; override;
    function Parse: TAntimonyModel;
  end;

implementation

constructor TAntimonyParser.Create(ALexer: TAntimonyLexer);
begin
  inherited Create;
  FLexer := ALexer;
  //if Length(ALexer.Tokens) > 0 then
  //  FLexer.CurrentToken := ALexer.Tokens[0];
end;

destructor TAntimonyParser.Destroy;
begin
  // Note: FLexer is not owned by parser
  inherited Destroy;
end;

//procedure TAntimonyParser.NextToken;
//begin
//  Inc(FPosition);
//  if FPosition < Length(FLexer.Tokens) then
//    FCurrentToken := FLexer.Tokens[FPosition];
//end;

//function TAntimonyParser.CurrentToken: TToken;
//begin
//  if FPosition < Length(FLexer.Tokens) then
//    Result := FLexer.Tokens[FPosition]
//  else
//  begin
//    // Return EOF token
//    Result.TokenType := ttEOF;
//    Result.TokenValue := '';
//    Result.Line := 0;
//    Result.Column := 0;
//  end;
//end;


function TAntimonyParser.Match(ATokenType: TTokenType): Boolean;
begin
  Result := FLexer.CurrentToken.TokenType = ATokenType;
end;

function TAntimonyParser.Match(AKeyword: TAntimonyKeyword): Boolean;
begin
  Result := (FLexer.CurrentToken.TokenType = ttKeyword) and (FLexer.CurrentToken.Keyword = AKeyword);
end;

function TAntimonyParser.Consume(ATokenType: TTokenType; const AErrorMsg: string): TToken;
begin
  if Match(ATokenType) then
  begin
    Result := FLexer.CurrentToken;
    FLexer.NextToken;
  end
  else
  begin
    if AErrorMsg <> '' then
      Error(AErrorMsg)
    else
      Error(Format('Expected token type %s, got %s', [GetEnumName(TypeInfo(TTokenType), Ord(ATokenType)), FLexer.CurrentToken.TokenValue]));
    Result := FLexer.CurrentToken; // fallback
  end;
end;

function TAntimonyParser.Consume(AKeyword: TAntimonyKeyword; const AErrorMsg: string): TToken;
begin
  if Match(AKeyword) then
  begin
    Result := FLexer.CurrentToken;
    FLexer.NextToken;
  end
  else
  begin
    if AErrorMsg <> '' then
      Error(AErrorMsg)
    else
      Error(Format('Expected keyword %s', [GetEnumName(TypeInfo(TAntimonyKeyword), Ord(AKeyword))]));
    Result := FLexer.CurrentToken; // fallback
  end;
end;

function TAntimonyParser.IsAtEnd: Boolean;
begin
  Result := Match(ttEOF);
end;

procedure TAntimonyParser.Error(const AMessage: string);
begin
  raise EAntimonyParserError.Create(AMessage, FLexer.CurrentToken.LineNumber, FLexer.CurrentToken.ColumnNumber);
end;



function TAntimonyParser.ParseExpression : TExpressionNode;
var
  ExprParser: TAntimonyExpressionParser;
begin
  try
    ExprParser := TAntimonyExpressionParser.Create(FLexer);
    try
      result := ExprParser.Parse;
    finally
      ExprParser.Free;
    end;
  except
    on E: EAntimonyExpressionError do
    begin
      // Re-raise with adjusted line/column information
      raise EAntimonyParserError.Create('Expression error: ' + E.Message,
                                       FLexer.CurrentToken.LineNumber, FLexer.CurrentToken.ColumnNumber);
    end;
  end;
end;

function AppendStringArray(const ATarget, ASource: TArray<string>): TArray<string>;
var
  TargetLen, SourceLen, I: Integer;
begin
  TargetLen := Length(ATarget);
  SourceLen := Length(ASource);

  SetLength(Result, TargetLen + SourceLen);

  // Copy target array
  for I := 0 to TargetLen - 1 do
    Result[I] := ATarget[I];

  // Append source array
  for I := 0 to SourceLen - 1 do
    Result[TargetLen + I] := ASource[I];
end;


procedure TAntimonyParser.ExtractParametersFromKineticLaws (AModel : TAntimonyModel);
var arr : TArray<string>;
    parr : TArray<string>;
    numSpecies, Count : integer;
    Assignment : TAntimonyAssignment;
begin
  Setlength (arr, 0);
  for var i := 0 to AModel.Reactions.Count - 1 do
      arr := AppendStringArray(arr, TExpressionNode.GetIdentifiers(AModel.Reactions[i].KineticAST));
  numSpecies := 0;
  for var i := 0 to length (arr) - 1 do
      if AModel.FindSpecies(arr[i]) <> -1 then
         inc (numSpecies);

  SetLength (parr, length (arr) - numSpecies);

  // Extract the parameter names
  Count := 0;
  for var i := 0 to length (arr) - 1 do
      begin
      if AModel.FindSpecies(arr[i]) = -1 then
         begin
         parr[Count] := arr[i];
         inc (Count);
         end;
      end;
  // Add any uninitialized parameter values to the assignemnt list.
  for var i := 0 to length (parr) - 1 do
      if AModel.Assignments.FindAssignment(parr[i]) = -1 then
         begin
         Assignment := TAntimonyAssignment.Create(parr[i], TExpressionNode.CreateZeroExpression);
         AModel.Assignments.Add(Assignment);
         end;
end;


function TAntimonyParser.Parse: TAntimonyModel;
begin
  Result := ParseModel;
  // Check if all parameters have been initialzed
  ExtractParametersFromKineticLaws (Result);
end;


function TAntimonyParser.ParseModel: TAntimonyModel;
var
  ModelName: string;
begin
  // Optional model declaration
  if Match(ttModel) then
  begin
    FLexer.NextToken; // consume 'model'
    if Match(ttIdentifier) then
    begin
      ModelName := FLexer.CurrentToken.TokenValue;
      FLexer.NextToken;
    end
    else
      ModelName := 'anonymous';
  end
  else
    ModelName := 'anonymous';

  Result := TAntimonyModel.Create(ModelName);

  try
    // Parse statements
    while not IsAtEnd do
    begin
      ParseStatement(Result);
    end;
  except
    Result.Free;
    raise;
  end;
end;


 procedure TAntimonyParser.ParseStatement(AModel: TAntimonyModel);

  function IsReactionStart: Boolean;
  var
    SavePos: Integer;
    Token: TToken;
  begin
    Result := False;
    SavePos := FLexer.Position;

    try
      // Handle stoichiometry at the start
      if Match(ttNumber) then
      begin
        FLexer.NextToken;
        // Optional '*' after stoichiometry
        if Match(ttMultiply) then
          FLexer.NextToken;
      end;

      // Handle $ prefix for boundary species in reactions
      if Match(ttDollar) then
        FLexer.NextToken;

      // Look ahead to find if this is a reaction
      // Skip the current identifier
      if Match(ttIdentifier) then
      begin
        FLexer.NextToken;

        // Check for optional reaction name with colon
        if Match(ttColon) then
        begin
          Result := True;
          Exit;
        end;

        // Look for reaction pattern: species [+ species]* arrow
        while not IsAtEnd do
        begin
          Token := FLexer.CurrentToken;

          if (Token.TokenType = ttArrow) or (Token.TokenType = ttIrreversibleArrow) then
          begin
            Result := True;
            Exit;
          end
          else if (Token.TokenType = ttEquals) or (Token.TokenType = ttColonEquals) then
          begin
            Result := False;
            Exit;
          end
          else if (Token.TokenType = ttSemicolon) or (Token.TokenType = ttEOF) then
          begin
            Result := False;
            Exit;
          end;

          FLexer.NextToken;
        end;
      end;
    finally
      // Restore position
      FLexer.Position := SavePos;
      if FLexer.Position < Length(FLexer.Tokens) then
        FLexer.CurrentToken := FLexer.Tokens[FLexer.Position];
    end;
  end;

  function IsSpeciesDeclarationStart: Boolean;
  var
    SavePos: Integer;
  begin
    Result := False;
    SavePos := FLexer.Position;

    try
      // Skip $ if present
      if Match(ttDollar) then
        FLexer.NextToken;

      // Check for 'species' keyword or identifier followed by assignment/in clause
      if Match(ttSpecies) then
      begin
        Result := True;
        Exit;
      end;

      if Match(ttIdentifier) then
      begin
        FLexer.NextToken;
        // Check for patterns that indicate species declaration:
        // identifier = value
        // identifier in compartment
        if Match(ttEquals) or Match(kwIn) then
        begin
          Result := True;
          Exit;
        end;
      end;
    finally
      // Restore position
      FLexer.Position := SavePos;
      if FLexer.Position < Length(FLexer.Tokens) then
        FLexer.CurrentToken := FLexer.Tokens[FLexer.Position];
    end;
  end;


begin
  case FLexer.CurrentToken.TokenType of
    ttCompartment: ParseCompartmentDeclaration(AModel);
    ttSpecies: ParseSpeciesDeclaration(AModel, False);
    ttIdentifier:
      begin
        // Use lookahead to determine if this is a reaction, assignment, or assignment rule
        if IsReactionStart then
          ParseReaction(AModel)
        else if FLexer.PeekToken.TokenType = ttEquals then
          ParseAssignment(AModel)
        else if FLexer.PeekToken.TokenType = ttColonEquals then
          ParseAssignmentRule(AModel)
        else
          Error('Unexpected identifier: ' + FLexer.CurrentToken.TokenValue);
      end;
    ttDollar:
      begin
        // Use lookahead to determine if this is a species declaration or reaction
        if IsSpeciesDeclarationStart then
        begin
          FLexer.NextToken; // consume '$'
          ParseSpeciesDeclaration(AModel, True);  // Pass True to indicate boundary species
        end
        else if IsReactionStart then
          ParseReaction(AModel)
        else
          Error('Unexpected $ token: cannot determine if species declaration or reaction');
      end;
    ttNumber:
      begin
        // Numbers at the start of a statement are likely stoichiometry in reactions
        if IsReactionStart then
          ParseReaction(AModel)
        else
          Error('Unexpected number: ' + FLexer.CurrentToken.TokenValue + ' (numbers must be part of reactions, assignments, or parameter declarations)');
      end;
  else
    if not IsAtEnd then
      Error('Unexpected token: ' + FLexer.CurrentToken.TokenValue);
  end;

  // Optional semicolon
  if Match(ttSemicolon) then
    FLexer.NextToken;
end;




procedure TAntimonyParser.ParseSpeciesDeclaration(AModel: TAntimonyModel; AIsBoundaryPrefix: Boolean = False);
var
  Species: TAntimonySpecies;
  IsBoundary: Boolean;
  CurrentCompartment: string;
  HasInitialValue: Boolean;
  InitialValue: Double;
begin
  // Use the passed-in boundary flag (in case $ was already consumed by caller)
  IsBoundary := AIsBoundaryPrefix;

  // Optional 'species' keyword
  if Match(ttSpecies) then
    FLexer.NextToken;

  // Parse comma-separated list of species
  repeat
   // Check if preceded by $ (for species declared within the list)
    if Match(ttDollar) then
       begin
       IsBoundary := True;
       FLexer.NextToken;
       end;

    if not Match(ttIdentifier) then
      Error('Expected species name');

    Species := TAntimonySpecies.Create(FLexer.CurrentToken.TokenValue);
    Species.IsBoundary := IsBoundary;
    FLexer.NextToken;

    CurrentCompartment := '';
    HasInitialValue := False;
    InitialValue := 0.0;

    // Check for 'in' clause (compartment assignment)
    if Match(ttIn) then
    begin
      FLexer.NextToken;
      if Match(ttIdentifier) then
      begin
        CurrentCompartment := FLexer.CurrentToken.TokenValue;
        Species.Compartment := CurrentCompartment;
        FLexer.NextToken;
      end
      else
        Error('Expected compartment name after "in"');
    end;

    // Check for initial value assignment
    if Match(ttEquals) then
    begin
      FLexer.NextToken;
      InitialValue := ParseNumber;
      HasInitialValue := True;
      Species.InitialValue := InitialValue;
    end;

    // Add the species to the model
    AModel.Species.Add(Species);

    // Check for comma to continue with more species
    if Match(ttComma) then
    begin
      FLexer.NextToken;
      // Continue loop to parse next species
    end
    else
      Break; // No more species in the list

  until False;
end;


procedure TAntimonyParser.ParseCompartmentDeclaration(AModel: TAntimonyModel);
var
  Compartment: TAntimonyCompartment;
  CompName: string;
begin
  // Optional 'compartment' keyword
  if Match(ttCompartment) then
    FLexer.NextToken;

  repeat
  if not Match(ttIdentifier) then
    Error('Expected compartment name');

  CompName := FLexer.CurrentToken.TokenValue;
  FLexer.NextToken;

  Compartment := TAntimonyCompartment.Create(CompName);

  // Optional size assignment
  if Match(ttEquals) then
  begin
    FLexer.NextToken;
    Compartment.Size := ParseNumber;
  end;

  AModel.Compartments.Add(Compartment);

  // Check for comma to continue with more species
  if Match(ttComma) then
     begin
     FLexer.NextToken;
     // Continue loop to parse next species
     end
  else
    Break; // No more species in the list

  until False;
end;



// Updated ParseReaction method with proper boundary species handling:
procedure TAntimonyParser.ParseReaction(AModel: TAntimonyModel);
var
  Reaction: TAntimonyReaction;
  ReactionName: string;
  Reactants, Products: TArray<TReactionParticipant>;
  IsReversible: Boolean;
  I: Integer;

  // Helper function to ensure species exists in model
  procedure EnsureSpeciesExists(const ASpeciesName: string; AIsBoundary: Boolean);
  var
    J: Integer;
    Found: Boolean;
    NewSpecies: TAntimonySpecies;
    ExistingSpecies: TAntimonySpecies;
  begin
    Found := False;
    ExistingSpecies := nil;

    // Check if species already exists
    for J := 0 to AModel.Species.Count - 1 do
    begin
      if SameText(AModel.Species[J].Id, ASpeciesName) then
      begin
        Found := True;
        ExistingSpecies := AModel.Species[J];
        Break;
      end;
    end;

    if Found then
    begin
      // Update boundary status if this reference indicates it's a boundary species
      if AIsBoundary then
        ExistingSpecies.IsBoundary := True;
    end
    else
    begin
      // Create new species
      NewSpecies := TAntimonySpecies.Create(ASpeciesName);
      NewSpecies.InitialValue := 0.0; // Default initial value for implicit species
      NewSpecies.IsBoundary := AIsBoundary;
      AModel.Species.Add(NewSpecies);
    end;
  end;

begin
  // Optional reaction name with colon
  if Match(ttIdentifier) and (FLexer.PeekToken.TokenType = ttColon) then
  begin
    ReactionName := FLexer.CurrentToken.TokenValue;
    FLexer.NextToken; // consume name
    FLexer.NextToken; // consume ':'
  end
  else
    ReactionName := 'R' + IntToStr(AModel.Reactions.Count + 1);

  Reaction := TAntimonyReaction.Create(ReactionName);

  try
    // Parse reactants
    if not (Match(ttArrow) or Match(ttIrreversibleArrow)) then
    begin
      Reactants := ParseReactionParticipants;
      for I := 0 to High(Reactants) do
      begin
        // Ensure each reactant species exists in the model, respecting boundary status
        EnsureSpeciesExists(Reactants[I].SpeciesName, Reactants[I].IsBoundary);
        Reaction.Reactants.Add(Reactants[I]);
      end;
    end;

    // Parse arrow
    if Match(ttArrow) then
    begin
      IsReversible := False;
      FLexer.NextToken;
    end
    else if Match(ttIrreversibleArrow) then
    begin
      IsReversible := True;
      FLexer.NextToken;
    end
    else
      Error('Expected irreversible reaction arrow (=>) or reversible arrow (->)');

    Reaction.IsReversible := IsReversible;

    // Parse products - check if there are any products before parsing
    if not (Match(ttSemicolon) or IsAtEnd) and (Match(ttIdentifier) or Match (ttNumber) or Match (ttDollar)) then
    begin
      Products := ParseReactionParticipants;
      for I := 0 to High(Products) do
      begin
        // Ensure each product species exists in the model, respecting boundary status
        EnsureSpeciesExists(Products[I].SpeciesName, Products[I].IsBoundary);
        Reaction.Products.Add(Products[I]);
      end;
    end;
    // If no products (empty right side), Products array remains empty

    // Optional kinetic law
    if Match(ttSemicolon) then
    begin
      FLexer.NextToken;
      if not (Match(ttSemicolon) or IsAtEnd) then
         begin
         Reaction.KineticAST := ParseExpression;
         Reaction.KineticLaw := Reaction.KineticAST.ToString;
         // Strip the surrounding brackets
         if Reaction.KineticLaw[1] = '(' then
            Reaction.KineticLaw := Copy(Reaction.KineticLaw, 2, Length(Reaction.KineticLaw) - 2);
         end;
    end;

    AModel.Reactions.Add(Reaction);
  except
    Reaction.Free;
    raise;
  end;
end;


procedure TAntimonyParser.ParseAssignment(AModel: TAntimonyModel);
var
  Assignment: TAntimonyAssignment;
  Variable: string;
  Expression : TExpressionNode;
  value : double;
begin
  if not Match(ttIdentifier) then
    Error('Expected variable name');

  Variable := FLexer.CurrentToken.TokenValue;
  FLexer.NextToken;

  Consume(ttEquals, 'Expected "=" in assignment');

  Expression := ParseExpression;

  // Check if its a species or a compartment, treat these differently.
  for var i := 0 to AModel.Compartments.Count - 1 do
      if AModel.Compartments[i].Id = Variable then
         begin
         if Expression.NodeType <> TExpressionNodeType.entNumber then
            Error('Variables can only be assigned numerical values not expressiond');
         value := strtofloat (Expression.ToString);
         AModel.Compartments[i].Size := value;
         Expression.Free;  // Free the expression since we're not passing it to an Assignment
         exit;
         end;

  for var i := 0 to AModel.Species.Count - 1 do
      if AModel.Species[i].Id = Variable then
         begin
         if Expression.NodeType <> TExpressionNodeType.entNumber then
            Error('Variables can only be assigned numerical values not expressiond');
         value := strtofloat (Expression.ToString);
         AModel.Species[i].InitialValue := value;
         Expression.Free;  // Free the expression since we're not passing it to an Assignment
         exit;
         end;

  Assignment := TAntimonyAssignment.Create(Variable, Expression);
  AModel.Assignments.Add(Assignment);
end;

procedure TAntimonyParser.ParseAssignmentRule(AModel: TAntimonyModel);
var
  AssignmentRule: TAntimonyAssignmentRule;
  Variable: string;
begin
  if not Match(ttIdentifier) then
    Error('Expected variable name');

  Variable := FLexer.CurrentToken.TokenValue;
  FLexer.NextToken;

  Consume(ttColonEquals, 'Expected ":=" in assignment rule');

  AssignmentRule := TAntimonyAssignmentRule.Create(Variable, ParseExpression);
  AModel.AssignmentRules.Add(AssignmentRule);
end;


// Updated ParseReactionParticipants method in uAntimonyParser.pas:
function TAntimonyParser.ParseReactionParticipants: TArray<TReactionParticipant>;
var
  Participants: TList<TReactionParticipant>;
  Participant: TReactionParticipant;
  Stoichiometry: Double;
  SpeciesName: string;
  IsBoundary: Boolean;
begin
  Participants := TList<TReactionParticipant>.Create;
  try
    repeat
      Stoichiometry := 1.0;
      IsBoundary := False;

      // Optional stoichiometry
      if Match(ttNumber) then
      begin
        Stoichiometry := StrToFloat(FLexer.CurrentToken.TokenValue);
        FLexer.NextToken;

        // Optional '*' after stoichiometry
        if Match(ttMultiply) then
          FLexer.NextToken;
      end;

      // Check for boundary species marker ($)
      if Match(ttDollar) then
      begin
        IsBoundary := True;
        FLexer.NextToken;
      end;

      // Species name
      if Match(ttIdentifier) then
      begin
        SpeciesName := FLexer.CurrentToken.TokenValue;
        FLexer.NextToken;

        Participant := TReactionParticipant.Create(SpeciesName, Stoichiometry, IsBoundary);
        Participants.Add(Participant);
      end
      else
        Error('Expected species name');

      // Continue if there's a '+'
      if Match(ttPlus) then
        FLexer.NextToken
      else
        Break;

    until False;

    Result := Participants.ToArray;
  finally
    Participants.Free;
  end;
end;



function TAntimonyParser.ParseNumber: Double;
begin
  if Match(ttNumber) then
  begin
    try
      Result := StrToFloat(FLexer.CurrentToken.TokenValue);
      FLexer.NextToken;
    except
      Error('Invalid number format: ' + FLexer.CurrentToken.TokenValue);
      Result := 0.0;
    end;
  end
  else if Match(ttMinus) then
  begin
    FLexer.NextToken;
    if Match(ttNumber) then
    begin
      try
        Result := -StrToFloat(FLexer.CurrentToken.TokenValue);
        FLexer.NextToken;
      except
        Error('Invalid number format: -' + FLexer.CurrentToken.TokenValue);
        Result := 0.0;
      end;
    end
    else
    begin
      Error('Expected number after minus sign');
      Result := 0.0;
    end;
  end
  else
  begin
    Error('Expected number');
    Result := 0.0;
  end;
end;

function TAntimonyParser.ParseIdentifierList: TArray<string>;
var
  Identifiers: TStringList;
begin
  Identifiers := TStringList.Create;
  try
    repeat
      if Match(ttIdentifier) then
      begin
        Identifiers.Add(FLexer.CurrentToken.TokenValue);
        FLexer.NextToken;
      end
      else
        Error('Expected identifier');

      if Match(ttComma) then
        FLexer.NextToken
      else
        Break;

    until False;

    Result := Identifiers.ToStringArray;
  finally
    Identifiers.Free;
  end;
end;

end.
