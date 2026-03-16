unit uExpressionNode;

interface

Uses Classes,
     System.SysUtils,
     System.Math,
     Generics.Collections;

type
  // Operator types
  TOperatorType = (
    otAdd, otSubtract, otMultiply, otDivide, otPower,
    otLess, otLessEqual, otGreater, otGreaterEqual,
    otEqual, otNotEqual, otAnd, otOr, otNot
  );

  // Expression node types for AST
  TExpressionNodeType = (
    entNumber,
    entIdentifier,
    entBinaryOp,
    entUnaryOp,
    entFunctionCall
  );

  // Forward declaration for the value lookup function type
  TValueLookupFunc = reference to function(const Name: string): Double;

  // Expression AST node
  TExpressionNode = class
  private
    FNodeType: TExpressionNodeType;
    FValue: string;
    FOperator: TOperatorType;
    FLeft: TExpressionNode;
    FRight: TExpressionNode;
    FFunctionName: string;
    FArguments: TObjectList<TExpressionNode>;
    procedure CollectIdentifiers(AList: TStringList);
  public
    constructor Create(ANodeType: TExpressionNodeType);
    destructor Destroy; override;

    class function GetIdentifiers(AST: TExpressionNode): TArray<string>;
    class function CreateZeroExpression: TExpressionNode;
    class function CreateNumberExpression(AValue: Double): TExpressionNode;

    // Evaluate the expression tree
    // ALookup is called to resolve identifier values
    function Evaluate(ALookup: TValueLookupFunc): Double;
    
    // Check if this node is a simple number (no identifiers or operations)
    function IsNumber: Boolean;
    
    // Get numeric value (only valid if IsNumber returns True)
    function GetNumberValue: Double;

    property NodeType: TExpressionNodeType read FNodeType;
    property Value: string read FValue write FValue;
    property OpValue: TOperatorType read FOperator write FOperator;
    property Left: TExpressionNode read FLeft write FLeft;
    property Right: TExpressionNode read FRight write FRight;
    property FunctionName: string read FFunctionName write FFunctionName;
    property Arguments: TObjectList<TExpressionNode> read FArguments;

    function ToString: string; override;
  end;

  // Exception for evaluation errors
  EExpressionEvalError = class(Exception);

implementation

// TExpressionNode implementation

constructor TExpressionNode.Create(ANodeType: TExpressionNodeType);
begin
  inherited Create;
  FNodeType := ANodeType;
  FArguments := TObjectList<TExpressionNode>.Create(True);
end;

destructor TExpressionNode.Destroy;
begin
  FLeft.Free;
  FRight.Free;
  FArguments.Free;
  inherited Destroy;
end;

// Helper function for OperatorToString (defined here to be accessible)
function OperatorToString(AOperator: TOperatorType): string;
begin
  case AOperator of
    otAdd: Result := '+';
    otSubtract: Result := '-';
    otMultiply: Result := '*';
    otDivide: Result := '/';
    otPower: Result := '^';
    otLess: Result := '<';
    otLessEqual: Result := '<=';
    otGreater: Result := '>';
    otGreaterEqual: Result := '>=';
    otEqual: Result := '==';
    otNotEqual: Result := '!=';
    otAnd: Result := '&&';
    otOr: Result := '||';
    otNot: Result := '!';
  else
    Result := '?';
  end;
end;


function TExpressionNode.ToString: string;
var
  I: Integer;
  Args: string;
begin
  case FNodeType of
    entNumber:
      Result := FValue;
    entIdentifier:
      Result := FValue;
    entBinaryOp:
      Result := Format('(%s %s %s)', [FLeft.ToString, OperatorToString(FOperator), FRight.ToString]);
    entUnaryOp:
      Result := Format('(%s%s)', [OperatorToString(FOperator), FRight.ToString]);
    entFunctionCall:
      begin
        Args := '';
        for I := 0 to FArguments.Count - 1 do
        begin
          if Args <> '' then
            Args := Args + ', ';
          Args := Args + FArguments[I].ToString;
        end;
        Result := Format('%s(%s)', [FFunctionName, Args]);
      end;
  else
    Result := 'Unknown';
  end;
end;


procedure TExpressionNode.CollectIdentifiers(AList: TStringList);
begin
  case FNodeType of
    entIdentifier:
      begin
        // Add identifier if not already in list
        if AList.IndexOf(FValue) = -1 then
          AList.Add(FValue);
      end;
    entBinaryOp:
      begin
        if Assigned(FLeft) then
          FLeft.CollectIdentifiers(AList);
        if Assigned(FRight) then
          FRight.CollectIdentifiers(AList);
      end;
    entUnaryOp:
      begin
        if Assigned(FRight) then
          FRight.CollectIdentifiers(AList);
      end;
    entFunctionCall:
      begin
        // Don't add function name itself, but do traverse arguments
        for var I := 0 to FArguments.Count - 1 do
          FArguments[I].CollectIdentifiers(AList);
      end;
    // entNumber: do nothing, it's not an identifier
  end;
end;


class function TExpressionNode.GetIdentifiers(AST: TExpressionNode): TArray<string>;
var
  Identifiers: TStringList;
begin
  try
    Identifiers := TStringList.Create;
    try
      Identifiers.Duplicates := dupIgnore; // Automatically ignore duplicates
      if Assigned(AST) then   // User might not have included a kinetic law
        AST.CollectIdentifiers(Identifiers);
      Result := Identifiers.ToStringArray;
    finally
      Identifiers.Free;
    end;
  finally
  end;
end;


class function TExpressionNode.CreateZeroExpression: TExpressionNode;
begin
  Result := TExpressionNode.Create(TExpressionNodeType.entNumber);
  Result.FValue := '0';
end;


class function TExpressionNode.CreateNumberExpression(AValue: Double): TExpressionNode;
begin
  Result := TExpressionNode.Create(TExpressionNodeType.entNumber);
  // Use a reasonable precision that avoids floating point noise
  Result.FValue := FloatToStrF(AValue, ffGeneral, 15, 0);
end;


function TExpressionNode.IsNumber: Boolean;
begin
  Result := (FNodeType = entNumber);
end;


function TExpressionNode.GetNumberValue: Double;
begin
  if FNodeType <> entNumber then
    raise EExpressionEvalError.Create('GetNumberValue called on non-number node');
  Result := StrToFloat(FValue);
end;


function TExpressionNode.Evaluate(ALookup: TValueLookupFunc): Double;
var
  LeftVal, RightVal: Double;
  I: Integer;
  Args: array of Double;
  FuncName: string;
begin
  case FNodeType of
    entNumber:
      Result := StrToFloat(FValue);
      
    entIdentifier:
      begin
        if not Assigned(ALookup) then
          raise EExpressionEvalError.CreateFmt('Cannot resolve identifier "%s": no lookup function provided', [FValue]);
        Result := ALookup(FValue);
      end;
      
    entBinaryOp:
      begin
        LeftVal := FLeft.Evaluate(ALookup);
        RightVal := FRight.Evaluate(ALookup);
        
        case FOperator of
          otAdd:          Result := LeftVal + RightVal;
          otSubtract:     Result := LeftVal - RightVal;
          otMultiply:     Result := LeftVal * RightVal;
          otDivide:
            begin
              if RightVal = 0 then
                raise EExpressionEvalError.Create('Division by zero');
              Result := LeftVal / RightVal;
            end;
          otPower:        Result := Power(LeftVal, RightVal);
          otLess:         Result := Ord(LeftVal < RightVal);
          otLessEqual:    Result := Ord(LeftVal <= RightVal);
          otGreater:      Result := Ord(LeftVal > RightVal);
          otGreaterEqual: Result := Ord(LeftVal >= RightVal);
          otEqual:        Result := Ord(LeftVal = RightVal);
          otNotEqual:     Result := Ord(LeftVal <> RightVal);
          otAnd:          Result := Ord((LeftVal <> 0) and (RightVal <> 0));
          otOr:           Result := Ord((LeftVal <> 0) or (RightVal <> 0));
        else
          raise EExpressionEvalError.CreateFmt('Unknown binary operator: %d', [Ord(FOperator)]);
        end;
      end;
      
    entUnaryOp:
      begin
        RightVal := FRight.Evaluate(ALookup);
        
        case FOperator of
          otSubtract: Result := -RightVal;
          otNot:      Result := Ord(RightVal = 0);
        else
          raise EExpressionEvalError.CreateFmt('Unknown unary operator: %d', [Ord(FOperator)]);
        end;
      end;
      
    entFunctionCall:
      begin
        // Evaluate all arguments
        SetLength(Args, FArguments.Count);
        for I := 0 to FArguments.Count - 1 do
          Args[I] := FArguments[I].Evaluate(ALookup);
        
        FuncName := LowerCase(FFunctionName);
        
        // Built-in math functions
        if FuncName = 'sin' then
          Result := Sin(Args[0])
        else if FuncName = 'cos' then
          Result := Cos(Args[0])
        else if FuncName = 'tan' then
          Result := Tan(Args[0])
        else if FuncName = 'exp' then
          Result := Exp(Args[0])
        else if FuncName = 'ln' then
          Result := Ln(Args[0])
        else if FuncName = 'log' then
          Result := Log10(Args[0])
        else if FuncName = 'log10' then
          Result := Log10(Args[0])
        else if FuncName = 'sqrt' then
          Result := Sqrt(Args[0])
        else if FuncName = 'abs' then
          Result := Abs(Args[0])
        else if FuncName = 'floor' then
          Result := Floor(Args[0])
        else if FuncName = 'ceil' then
          Result := Ceil(Args[0])
        else if FuncName = 'pow' then
          Result := Power(Args[0], Args[1])
        else if FuncName = 'min' then
          Result := Min(Args[0], Args[1])
        else if FuncName = 'max' then
          Result := Max(Args[0], Args[1])
        else if FuncName = 'asin' then
          Result := ArcSin(Args[0])
        else if FuncName = 'acos' then
          Result := ArcCos(Args[0])
        else if FuncName = 'atan' then
          Result := ArcTan(Args[0])
        else if FuncName = 'sinh' then
          Result := Sinh(Args[0])
        else if FuncName = 'cosh' then
          Result := Cosh(Args[0])
        else if FuncName = 'tanh' then
          Result := Tanh(Args[0])
        else
          raise EExpressionEvalError.CreateFmt('Unknown function: %s', [FFunctionName]);
      end;
  else
    raise EExpressionEvalError.CreateFmt('Unknown node type: %d', [Ord(FNodeType)]);
  end;
end;

end.
