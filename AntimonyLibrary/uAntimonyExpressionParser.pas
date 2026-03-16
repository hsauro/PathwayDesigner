unit uAntimonyExpressionParser;

interface

uses
  Classes, SysUtils, Math,
  Generics.Collections,
  uAntimonyLexer,
  uAntimonyModelType,
  uExpressionNode;

type
  // Expression parser
  TAntimonyExpressionParser = class
    Lexer : TAntimonyLexer;
  private
    function Match(ATokenType: TTokenType): Boolean;
    function IsAtEnd: Boolean;
    procedure Error(const AMessage: string);
    function Consume(ATokenType: TTokenType; const AErrorMsg: string = ''): TToken;

    // Expression parsing methods (recursive descent)
    function ParseExpression: TExpressionNode;
    function ParseLogicalOr: TExpressionNode;
    function ParseLogicalAnd: TExpressionNode;
    function ParseEquality: TExpressionNode;
    function ParseComparison: TExpressionNode;
    function ParseTerm: TExpressionNode;
    function ParseFactor: TExpressionNode;
    function ParsePower: TExpressionNode;
    function ParseUnary: TExpressionNode;
    function ParsePrimary: TExpressionNode;
    function ParseFunctionCall(const AFunctionName: string): TExpressionNode;

    function GetOperatorPrecedence(AOperator: TOperatorType): Integer;
    function TokenToOperator(AToken: TToken): TOperatorType;

  public
    constructor Create(ALexer : TAntimonyLexer);
    function Parse: TExpressionNode;
    function ParseToString: string;
  end;

  // Exception for expression parsing errors
  EAntimonyExpressionError = class(Exception)
  private
    FLine: Integer;
    FColumn: Integer;
  public
    constructor Create(const AMessage: string; ALine, AColumn: Integer);
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
  end;

implementation


// TAntimonyExpressionParser implementation

constructor TAntimonyExpressionParser.Create(ALexer : TAntimonyLexer);
begin
  inherited Create;
  Lexer := ALexer;
end;

function TAntimonyExpressionParser.Match(ATokenType: TTokenType): Boolean;
begin
  Result := Lexer.CurrentToken.TokenType = ATokenType;
end;

function TAntimonyExpressionParser.IsAtEnd: Boolean;
begin
  Result := Match(ttEOF) or Match(ttSemicolon);
end;

procedure TAntimonyExpressionParser.Error(const AMessage: string);
begin
  raise EAntimonyExpressionError.Create(AMessage, Lexer.CurrentToken.LineNumber, Lexer.CurrentToken.ColumnNumber);
end;

function TAntimonyExpressionParser.Consume(ATokenType: TTokenType; const AErrorMsg: string): TToken;
begin
  if Match(ATokenType) then
  begin
    Result := Lexer.CurrentToken;
    Lexer.NextToken;
  end
  else
  begin
    if AErrorMsg <> '' then
      Error(AErrorMsg)
    else
      Error(Format('Expected token type, got %s', [Lexer.CurrentToken.TokenValue]));
    Result := Lexer.CurrentToken;
  end;
end;

function TAntimonyExpressionParser.Parse: TExpressionNode;
begin
  Result := ParseExpression;
end;

function TAntimonyExpressionParser.ParseToString: string;
var
  Node: TExpressionNode;
begin
  Node := Parse;
  try
    Result := Node.ToString;
  finally
    Node.Free;
  end;
end;

function TAntimonyExpressionParser.ParseExpression: TExpressionNode;
begin
  Result := ParseLogicalOr;
end;

function TAntimonyExpressionParser.ParseLogicalOr: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParseLogicalAnd;

  while Lexer.CurrentToken.TokenValue = '||' do
  begin
    Op := otOr;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParseLogicalAnd;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseLogicalAnd: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParseEquality;

  while Lexer.CurrentToken.TokenValue = '&&' do
  begin
    Op := otAnd;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParseEquality;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseEquality: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParseComparison;

  while (Lexer.CurrentToken.TokenValue = '==') or (Lexer.CurrentToken.TokenValue = '!=') do
  begin
    if Lexer.CurrentToken.TokenValue = '==' then
      Op := otEqual
    else
      Op := otNotEqual;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParseComparison;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseComparison: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParseTerm;

  while (Lexer.CurrentToken.TokenValue = '<') or (Lexer.CurrentToken.TokenValue = '<=') or
        (Lexer.CurrentToken.TokenValue = '>') or (Lexer.CurrentToken.TokenValue = '>=') do
  begin
    if Lexer.CurrentToken.TokenValue = '<' then
      Op := otLess
    else if Lexer.CurrentToken.TokenValue = '<=' then
      Op := otLessEqual
    else if Lexer.CurrentToken.TokenValue = '>' then
      Op := otGreater
    else
      Op := otGreaterEqual;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParseTerm;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseTerm: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParseFactor;

  while Match(ttPlus) or Match(ttMinus) do
  begin
    if Match(ttPlus) then
      Op := otAdd
    else
      Op := otSubtract;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParseFactor;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseFactor: TExpressionNode;
var
  Node: TExpressionNode;
  Op: TOperatorType;
begin
  Result := ParsePower;

  while Match(ttMultiply) or Match(ttDivide) do
  begin
    if Match(ttMultiply) then
      Op := otMultiply
    else
      Op := otDivide;
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := Op;
    Node.Left := Result;
    Node.Right := ParsePower;
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParsePower: TExpressionNode;
var
  Node: TExpressionNode;
begin
  Result := ParseUnary;

  // Right associative
  if Lexer.CurrentToken.TokenValue = '^' then
  begin
    Lexer.NextToken;
    Node := TExpressionNode.Create(entBinaryOp);
    Node.OpValue := otPower;
    Node.Left := Result;
    Node.Right := ParsePower; // Right associative recursion
    Result := Node;
  end;
end;

function TAntimonyExpressionParser.ParseUnary: TExpressionNode;
var
  Op: TOperatorType;
begin
  if Match(ttMinus) or (Lexer.CurrentToken.TokenValue = '!') then
  begin
    if Match(ttMinus) then
      Op := otSubtract
    else
      Op := otNot;
    Lexer.NextToken;
    Result := TExpressionNode.Create(entUnaryOp);
    Result.OpValue := Op;
    Result.Right := ParseUnary;
  end
  else
    Result := ParsePrimary;
end;

function TAntimonyExpressionParser.ParsePrimary: TExpressionNode;
var
  FuncName: string;
begin
  if Match(ttNumber) then
  begin
    Result := TExpressionNode.Create(entNumber);
    Result.Value := Lexer.CurrentToken.TokenValue;
    Lexer.NextToken;
  end
  else if Match(ttIdentifier) then
  begin
    FuncName := Lexer.CurrentToken.TokenValue;
    Lexer.NextToken;

    // Check if this is a function call
    if Match(ttLParen) then
      Result := ParseFunctionCall(FuncName)
    else
    begin
      // Just an identifier
      Result := TExpressionNode.Create(entIdentifier);
      Result.Value := FuncName;
    end;
  end
  else if Match(ttLParen) then
  begin
    Lexer.NextToken; // consume '('
    Result := ParseExpression;
    Consume(ttRParen, 'Expected ")" after expression');
  end
  else
  begin
    Error('Expected number, identifier, or "("');
    Result := nil; // This won't be reached due to Error raising exception
  end;
end;

function TAntimonyExpressionParser.ParseFunctionCall(const AFunctionName: string): TExpressionNode;
begin
  Result := TExpressionNode.Create(entFunctionCall);
  Result.FunctionName := AFunctionName;

  Consume(ttLParen, 'Expected "(" after function name');

  // Parse arguments
  if not Match(ttRParen) then
  begin
    repeat
      Result.Arguments.Add(ParseExpression);
      if Match(ttComma) then
        Lexer.NextToken
      else
        Break;
    until False;
  end;

  Consume(ttRParen, 'Expected ")" after function arguments');
end;

function TAntimonyExpressionParser.GetOperatorPrecedence(AOperator: TOperatorType): Integer;
begin
  case AOperator of
    otOr: Result := 1;
    otAnd: Result := 2;
    otEqual, otNotEqual: Result := 3;
    otLess, otLessEqual, otGreater, otGreaterEqual: Result := 4;
    otAdd, otSubtract: Result := 5;
    otMultiply, otDivide: Result := 6;
    otPower: Result := 7;
    otNot: Result := 8; // Unary operators have high precedence
  else
    Result := 0;
  end;
end;

function TAntimonyExpressionParser.TokenToOperator(AToken: TToken): TOperatorType;
begin
  case AToken.TokenType of
    ttPlus: Result := otAdd;
    ttMinus: Result := otSubtract;
    ttMultiply: Result := otMultiply;
  else
    if AToken.TokenValue = '/' then Result := otDivide
    else if AToken.TokenValue = '^' then Result := otPower
    else if AToken.TokenValue = '<' then Result := otLess
    else if AToken.TokenValue = '<=' then Result := otLessEqual
    else if AToken.TokenValue = '>' then Result := otGreater
    else if AToken.TokenValue = '>=' then Result := otGreaterEqual
    else if AToken.TokenValue = '==' then Result := otEqual
    else if AToken.TokenValue = '!=' then Result := otNotEqual
    else if AToken.TokenValue = '&&' then Result := otAnd
    else if AToken.TokenValue = '||' then Result := otOr
    else if AToken.TokenValue = '!' then Result := otNot
    else Result := otAdd; // Default fallback
  end;
end;

// EAntimonyExpressionError implementation

constructor EAntimonyExpressionError.Create(const AMessage: string; ALine, AColumn: Integer);
begin
  inherited Create(Format('%s at line %d, column %d', [AMessage, ALine, AColumn]));
  FLine := ALine;
  FColumn := AColumn;
end;

end.
