unit uAntimonyLexer;

interface

uses
  Classes, SysUtils,
  Generics.Collections,
  uAntimonyModelType;

type
  // Token types for lexical analysis
  TTokenType = (
    ttIdentifier,     // Variable/species names
    ttNumber,         // Numeric values
    ttString,         // String literals
    ttArrow,          // -> (irreversible reaction arrow)
    ttIrreversibleArrow, // => (reversible reaction)
    ttSemicolon,      // ; (statement separator)
    ttColon,          // : (assignment)
    ttColonEquals,    // := (assignment rule)
    ttComma,          // , (parameter separator)
    ttEquals,         // = (assignment)
    ttDollar,         // $ (boundary species)
    ttKeyword,        // Reserved keywords
    ttModel,
    ttConst,
    ttCompartment,
    ttSpecies,
    ttVar,
    ttAnd,        // and
    ttOr,         // or
    ttNot,        // not
    ttLT,
    ttGT,
    ttEQ,
    ttNE,
    ttLE,
    ttGE,
    ttPlus,       // +
    ttMinus,      // -
    ttMultiply,   // *
    ttDivide,     // /
    ttPower,      // ^
    ttLParen,     // (
    ttRParen,     // )
    ttEOF,        // End of file
    ttUnknown,    // Unknown token

    // Layout-specific tokens
    ttLayout,     // layout
    ttMetaData,
    ttCanvas,
    ttIn,
    ttAt,         // at
    ttCenter,     // center
    ttLBrace,     // {
    ttRBrace,     // }
    ttSize,       // size
    ttStyle,      // style
    ttAs,         // as
    ttHasAlias,   // hasalias
    ttBackgroundColor, // backgroundcolor
    ttCompartmentStyle, // global style
    ttSpeciesStyle,  // species-style
    ttReactionStyle, // reaction-style
    ttCurveType,  // curve-type
    ttFill,       // fill
    ttStroke,     // stroke
    ttShape,      // shape
    ttBothEnds,   // both-ends (for arrows)
    ttLabel,      // label
    ttWidth,      // width
    ttRectangle,  // rectangle
    ttEllipse,    // ellipse
    ttCircle,     // circle
    ttPolygon,    // polygon
    ttReaction,   // reaction
    ttJunction,   // junction
    ttDirect,     // direct
    ttReactants,  // reactants
    ttProducts,   // products
    ttGap,        // gap
    ttCp,         // cp
    ttStraight,   // straight
    ttBezier,     // bezier
    ttNonColinear, // non-colinear
    ttArrowKw,    // arrow  keyword
    ttRegulator,  // regulator
    ttFrom,       // from
    ttTo,         // to
    ttArrowStealth, // Stealth arrow from tikz
    ttArrowBlunt,  // Blunt end arrow
    ttArrowLatex, // Latex arrow from tikz.
    ttNone,       // none
    ttStringLiteral,  // "quoted string"
    ttHash,       // # for hex colors

    // New label-related tokens
    ttAnchor,     // anchor
    ttOffset,     // offset
    ttFontColor,  // fontColor
    ttFontSize,   // fontSize
    ttFontFamily, // fontFamily
    ttFontStyle,  // fontStyle
    ttVisible,    // visible
    ttDisplayName,// displayName
    ttTrue,       // true
    ttFalse,      // false
    ttTop,        // top
    ttBottom,     // bottom
    ttLeft,       // left
    ttRight,      // right
    ttTopLeft,    // top-left
    ttTopRight,   // top-right
    ttBottomLeft, // bottom-left
    ttBottomRight,// bottom-right
    ttOutsideTop, // outside-top
    ttOutsideBottom, // outside-bottom
    ttOutsideLeft,   // outside-left
    ttOutsideRight,  // outside-right
    ttNormal,     // normal
    ttBold,       // bold
    ttItalic,     // italic
    ttText,        // text

    // Metadata tokens
    ttStandard,
    ttVersion,
    ttCreated,
    ttAuthor,
    ttTitle,
    ttDescription,
    ttKeywords,
    ttFunding,   // funding
    ttAbstract,
    ttDOI,
    ttLicense
  );

  // Antimony keywords
  TAntimonyKeyword = (
    kwFunction,
    kwEnd,
    kwAt,
    kwIn
  );

  // Token record
  TToken = record
    TokenType: TTokenType;
    TokenValue: string;
    LineNumber: Integer;
    ColumnNumber: Integer;
    Keyword: TAntimonyKeyword;
  end;

  // Lexical analyzer for Antimony language
  TAntimonyLexer = class
  private
    FSource: string;
    FPosition: Integer;
    FLine: Integer;
    FColumn: Integer;
    FCurrentChar: Char;
    FTokens: TArray<TToken>;
    FCurrentToken: TToken;

    procedure NextChar;
    procedure SkipWhitespaceAndComments;
    function ReadString: string;
    function ReadNumber: string;
    function ReadIdentifier: string;
    function GetCompoundIdentifier: string;
    function GetHexColor: string;
    function IsAlpha(C: Char): Boolean;
    function IsAlphaNum(C: Char): Boolean;
    function IsDigit(C: Char): Boolean;
    function IsWhitespace(C: Char): Boolean;
    function CurrentChar: Char;
    function PeekChar: Char;
    function IsAtEnd: Boolean;
    function GetNextToken: TToken;
    function Tokenize: TArray<TToken>;
  public
    constructor Create(const ASource: string);
    procedure NextToken;
    function  PeekToken: TToken;
    property  CurrentToken: TToken read FCurrentToken write FCurrentToken;
    property  LineNumber: Integer read FLine;
    property  ColumnNumber: Integer read FColumn;
    property  Tokens: TArray<TToken> read FTokens;
    property  Position: integer read FPosition write FPosition;
  end;

implementation

constructor TAntimonyLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FPosition := 1;
  FLine := 1;
  FColumn := 1;
  if Length(FSource) > 0 then
    FCurrentChar := FSource[1]
  else
    FCurrentChar := #0;
  FTokens  := Tokenize;
  FPosition := 0;
  FCurrentToken := FTokens[FPosition];
end;

function TAntimonyLexer.IsAtEnd: Boolean;
begin
  Result := (FPosition > Length (FSource)) or (FCurrentChar = #0);
end;


procedure TAntimonyLexer.NextToken;
begin
  Inc(FPosition);
  if FPosition < Length(FTokens) then
    FCurrentToken := FTokens[FPosition];
end;


function TAntimonyLexer.PeekToken: TToken;
begin
  if FPosition + 1 < Length(Tokens) then
    Result := Tokens[FPosition + 1]
  else
  begin
    // Return EOF token
    Result.TokenType := ttEOF;
    Result.TokenValue := '';
    Result.LineNumber := 0;
    Result.ColumnNumber := 0;
  end;
end;


procedure TAntimonyLexer.NextChar;
begin
if FPosition <= Length(FSource) then
   begin
   if FCurrentChar = #10 then
      begin
      Inc(FLine);
      FColumn := 1;
      end
    else
      Inc(FColumn);

   Inc(FPosition);
   if FPosition <= Length(FSource) then
      FCurrentChar := FSource[FPosition]
   else
      FCurrentChar := #0;
   end;
end;

function TAntimonyLexer.CurrentChar: Char;
begin
  Result := FCurrentChar;
end;

function TAntimonyLexer.PeekChar: Char;
begin
  if FPosition + 1 <= Length(FSource) then
    Result := FSource[FPosition + 1]
  else
    Result := #0;
end;

function TAntimonyLexer.IsAlpha(C: Char): Boolean;
begin
  Result := C in ['a'..'z', 'A'..'Z', '_'];
end;

function TAntimonyLexer.IsAlphaNum(C: Char): Boolean;
begin
  Result := C in ['a'..'z', 'A'..'Z', '0'..'9', '_'];
end;

function TAntimonyLexer.IsDigit(C: Char): Boolean;
begin
  Result := C in ['0'..'9'];
end;

function TAntimonyLexer.IsWhitespace(C: Char): Boolean;
begin
  Result := C in [' ', #9, #10, #13];
end;

procedure TAntimonyLexer.SkipWhitespaceAndComments;
begin
  while not IsAtEnd do
  begin
    if FCurrentChar in [#9, #10, #13, ' '] then
    begin
      NextChar;
    end
    else if (FCurrentChar = '/') and (Position < length (FSource)) and (FSource[FPosition + 1] = '/') then
    begin
      // Skip single line comment starting with //
      NextChar; // skip first /
      NextChar; // skip second /

      // Skip until end of line
      while not IsAtEnd and not (FCurrentChar in [#10, #13]) do
        NextChar;
    end
    else if FCurrentChar = '#' then
    begin
      // Check if this is a hex color (# followed by hex digits)
      if (FPosition < length (FSource)) and ((FSource[FPosition + 1] in ['0'..'9', 'a'..'f', 'A'..'F'])) then
        Break; // This is a hex color, not a comment

      // Skip single line comment starting with #
      NextChar; // skip #

      // Skip until end of line
      while not IsAtEnd and not (FCurrentChar in [#10, #13]) do
        NextChar;
    end
    else
      Break;
  end;
end;


function TAntimonyLexer.ReadString: string;
var
  Quote: Char;
begin
  Result := '';
  Quote := CurrentChar; // " or '
  NextChar; // skip opening quote

  while (CurrentChar <> Quote) and (CurrentChar <> #0) do
  begin
    if CurrentChar = '\' then
    begin
      NextChar;
      case CurrentChar of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
        '\': Result := Result + '\';
        '"': Result := Result + '"';
        '''': Result := Result + '''';
      else
        Result := Result + CurrentChar;
      end;
    end
    else
      Result := Result + CurrentChar;
    NextChar;
  end;

  if CurrentChar = Quote then
    NextChar; // skip closing quote
end;


function TAntimonyLexer.ReadNumber: string;
var
  HasDot: Boolean;
begin
  Result := '';
  HasDot := False;

  if CurrentChar = '-' then
     begin
     Result := '-';
     NextChar;
     end;

  while IsDigit(CurrentChar) or ((CurrentChar = '.') and not HasDot) do
  begin
    if CurrentChar = '.' then
      HasDot := True;
    Result := Result + CurrentChar;
    NextChar;
  end;

  // Scientific notation
  if CurrentChar in ['e', 'E'] then
  begin
    Result := Result + CurrentChar;
    NextChar;
    if CurrentChar in ['+', '-'] then
    begin
      Result := Result + CurrentChar;
      NextChar;
    end;
    while IsDigit(CurrentChar) do
    begin
      Result := Result + CurrentChar;
      NextChar;
    end;
  end;
end;


function TAntimonyLexer.ReadIdentifier: string;
begin
  Result := '';
  while IsAlphaNum(CurrentChar) do
  begin
    Result := Result + CurrentChar;
    NextChar;
  end;
end;


function TAntimonyLexer.GetHexColor: string;
var
  LStart: Integer;
  Count: Integer;
begin
  LStart := FPosition;
  NextChar; // skip #
  Count := 0;

  while not IsAtEnd and (FCurrentChar in ['0'..'9', 'a'..'f', 'A'..'F']) and (Count < 8) do
  begin
    NextChar;
    Inc(Count);
  end;

  Result := Copy(FSource, LStart, FPosition - LStart);
end;


function TAntimonyLexer.GetCompoundIdentifier: string;
var
  LStart: Integer;
begin
  LStart := FPosition;

  while not IsAtEnd and (FCurrentChar in ['a'..'z', 'A'..'Z', '_', '0'..'9', '-']) do
    NextChar;

  Result := Copy(FSource, LStart, FPosition - LStart);
end;


function TAntimonyLexer.GetNextToken: TToken;
var
  IdentifierValue: string;
begin
  SkipWhitespaceAndComments;

  Result.TokenType := ttEOF;
  Result.TokenValue := '';

  if IsAtEnd then
    Exit;

  Result.LineNumber := FLine;
  Result.ColumnNumber := FColumn;

  // Check for string literals
  if FCurrentChar = '"' then
  begin
    Result.TokenValue := ReadString;
    Result.TokenType := ttString;
    Exit;
  end;

  // Check for hex colors
  if (FCurrentChar = '#') and (FPosition < Length (FSource)) and
     (FSource[FPosition + 1] in ['0'..'9', 'a'..'f', 'A'..'F']) then
  begin
    Result.TokenValue := GetHexColor;
    Result.TokenType := ttHash; // We'll treat the whole hex color as ttHash
    Exit;
  end;

  // Check for multi-character tokens first
  if (FCurrentChar = '-') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '>') then
  begin
    Result.TokenType := ttArrow;
    Result.TokenValue := '->';
    NextChar;
    NextChar;
    Exit;
  end;

  // Check for multi-character tokens first
  if (FCurrentChar = '=') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '>') then
  begin
    Result.TokenType := ttIrreversibleArrow;
    Result.TokenValue := '=>';
    NextChar;
    NextChar;
    Exit;
  end;

  if (FCurrentChar = '=') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '=') then
  begin
    Result.TokenType := ttEQ;
    Result.TokenValue := '==';
    NextChar;
    NextChar;
    Exit;
  end;

  if (FCurrentChar = '!') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '=') then
  begin
    Result.TokenType := ttNE;
    Result.TokenValue := '!=';
    NextChar;
    NextChar;
    Exit;
  end;

  if (FCurrentChar = '<') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '=') then
  begin
    Result.TokenType := ttLE;
    Result.TokenValue := '<=';
    NextChar;
    NextChar;
    Exit;
  end;

  if (FCurrentChar = '>') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] = '=') then
  begin
    Result.TokenType := ttGE;
    Result.TokenValue := '>=';
    NextChar;
    NextChar;
    Exit;
  end;

  // Identifiers and keywords
  if (FCurrentChar in ['a'..'z', 'A'..'Z', '_']) then
  begin
    // Check if this might be a compound identifier (containing hyphens)
    if (FPosition + 1 <= Length (FSource)) then
    begin
      // Look ahead to see if we might have a compound identifier
      var TempPos := FPosition;
      var HasHyphen := False;
      while (TempPos <= Length (FSource)) and (FSource[TempPos] in ['a'..'z', 'A'..'Z', '_', '0'..'9', '-']) do
      begin
        if FSource[TempPos] = '-' then
          HasHyphen := True;
        Inc(TempPos);
      end;

      if HasHyphen then
        IdentifierValue := GetCompoundIdentifier
      else
        IdentifierValue := ReadIdentifier;
    end
    else
      IdentifierValue := ReadIdentifier;

    Result.TokenValue := IdentifierValue;

    // Original Antimony keywords
    if SameText(IdentifierValue, 'model') then
      Result.TokenType := ttModel
    else if SameText(IdentifierValue, 'compartment') then
      Result.TokenType := ttCompartment
    else if SameText(IdentifierValue, 'species') then
      Result.TokenType := ttSpecies
    else if SameText(IdentifierValue, 'var') then
      Result.TokenType := ttVar
    else if SameText(IdentifierValue, 'const') then
      Result.TokenType := ttConst
    else if SameText(IdentifierValue, 'in') then
      Result.TokenType := ttIn
    else if SameText(IdentifierValue, 'at') then
      Result.TokenType := ttAt
    else if SameText(IdentifierValue, 'center') then
      Result.TokenType := ttCenter
    else if SameText(IdentifierValue, 'and') then
      Result.TokenType := ttAnd
    else if SameText(IdentifierValue, 'or') then
      Result.TokenType := ttOr
    else if SameText(IdentifierValue, 'not') then
      Result.TokenType := ttNot
    // Layout keywords
    else if SameText(IdentifierValue, 'layout') then
      Result.TokenType := ttLayout
    else if SameText(IdentifierValue, 'metadata') then
      Result.TokenType := ttMetaData
    else if SameText(IdentifierValue, 'canvas') then
      Result.TokenType := ttCanvas
    else if SameText(IdentifierValue, 'size') then
      Result.TokenType := ttSize
    else if SameText(IdentifierValue, 'style') then
      Result.TokenType := ttStyle
    else if SameText(IdentifierValue, 'as') then
      Result.TokenType := ttAs
    else if SameText(IdentifierValue, 'has-alias') then
      Result.TokenType := ttHasAlias
    else if SameText(IdentifierValue, 'backgroundcolor') then
      Result.TokenType := ttBackgroundColor
    else if SameText(IdentifierValue, 'compartment-style') then
      Result.TokenType := ttCompartmentStyle
    else if SameText(IdentifierValue, 'species-style') then
      Result.TokenType := ttSpeciesStyle
    else if SameText(IdentifierValue, 'reaction-style') then
      Result.TokenType := ttReactionStyle
    else if SameText(IdentifierValue, 'curve-type') then
      Result.TokenType := ttCurveType
    else if SameText(IdentifierValue, 'fill') then
      Result.TokenType := ttFill
    else if SameText(IdentifierValue, 'stroke') then
      Result.TokenType := ttStroke
    else if SameText(IdentifierValue, 'shape') then
      Result.TokenType := ttShape
    else if SameText(IdentifierValue, 'both-ends') then
      Result.TokenType := ttBothEnds
    else if SameText(IdentifierValue, 'label') then
      Result.TokenType := ttLabel
    else if SameText(IdentifierValue, 'width') then
      Result.TokenType := ttWidth
    else if SameText(IdentifierValue, 'rectangle') then
      Result.TokenType := ttRectangle
    else if SameText(IdentifierValue, 'ellipse') then
      Result.TokenType := ttEllipse
    else if SameText(IdentifierValue, 'circle') then
      Result.TokenType := ttCircle
    else if SameText(IdentifierValue, 'polygon') then
      Result.TokenType := ttPolygon
    else if SameText(IdentifierValue, 'reaction') then
      Result.TokenType := ttReaction
    else if SameText(IdentifierValue, 'junction') then
      Result.TokenType := ttJunction
    else if SameText(IdentifierValue, 'direct') then
      Result.TokenType := ttDirect
    else if SameText(IdentifierValue, 'reactants') then
      Result.TokenType := ttReactants
    else if SameText(IdentifierValue, 'products') then
      Result.TokenType := ttProducts
    else if SameText(IdentifierValue, 'cp') then
      Result.TokenType := ttCp
    else if SameText(IdentifierValue, 'straight') then
      Result.TokenType := ttStraight
    else if SameText(IdentifierValue, 'bezier') then
      Result.TokenType := ttBezier
    else if SameText(IdentifierValue, 'non-colinear') then
      Result.TokenType := ttNonColinear
    else if SameText(IdentifierValue, 'arrow') then
      Result.TokenType := ttArrowKw
    else if SameText(IdentifierValue, 'regulator') then
      Result.TokenType := ttRegulator
    else if SameText(IdentifierValue, 'from') then
      Result.TokenType := ttFrom
    else if SameText(IdentifierValue, 'to') then
      Result.TokenType := ttTo
    else if SameText(IdentifierValue, 'node-gap') then
      Result.TokenType := ttGap
    else if SameText(IdentifierValue, 'none') then
      Result.TokenType := ttNone
    // New label keywords
    else if SameText(IdentifierValue, 'anchor') then
      Result.TokenType := ttAnchor
    else if SameText(IdentifierValue, 'offset') then
      Result.TokenType := ttOffset
    else if SameText(IdentifierValue, 'fontColor') then
      Result.TokenType := ttFontColor
    else if SameText(IdentifierValue, 'fontSize') then
      Result.TokenType := ttFontSize
    else if SameText(IdentifierValue, 'fontFamily') then
      Result.TokenType := ttFontFamily
    else if SameText(IdentifierValue, 'fontStyle') then
      Result.TokenType := ttFontStyle
    else if SameText(IdentifierValue, 'visible') then
      Result.TokenType := ttVisible
    else if SameText(IdentifierValue, 'displayName') then
      Result.TokenType := ttDisplayName
    else if SameText(IdentifierValue, 'true') then
      Result.TokenType := ttTrue
    else if SameText(IdentifierValue, 'false') then
      Result.TokenType := ttFalse
    else if SameText(IdentifierValue, 'center') then
      Result.TokenType := ttCenter
    else if SameText(IdentifierValue, 'top') then
      Result.TokenType := ttTop
    else if SameText(IdentifierValue, 'bottom') then
      Result.TokenType := ttBottom
    else if SameText(IdentifierValue, 'left') then
      Result.TokenType := ttLeft
    else if SameText(IdentifierValue, 'right') then
      Result.TokenType := ttRight
    else if SameText(IdentifierValue, 'top-left') then
      Result.TokenType := ttTopLeft
    else if SameText(IdentifierValue, 'top-right') then
      Result.TokenType := ttTopRight
    else if SameText(IdentifierValue, 'bottom-left') then
      Result.TokenType := ttBottomLeft
    else if SameText(IdentifierValue, 'bottom-right') then
      Result.TokenType := ttBottomRight
    else if SameText(IdentifierValue, 'outside-top') then
      Result.TokenType := ttOutsideTop
    else if SameText(IdentifierValue, 'outside-bottom') then
      Result.TokenType := ttOutsideBottom
    else if SameText(IdentifierValue, 'outside-left') then
      Result.TokenType := ttOutsideLeft
    else if SameText(IdentifierValue, 'outside-right') then
      Result.TokenType := ttOutsideRight
    else if SameText(IdentifierValue, 'normal') then
      Result.TokenType := ttNormal
    else if SameText(IdentifierValue, 'bold') then
      Result.TokenType := ttBold
    else if SameText(IdentifierValue, 'italic') then
      Result.TokenType := ttItalic
    else if SameText(IdentifierValue, 'text') then
      Result.TokenType := ttText
    // Metadata keywords
    else if SameText(IdentifierValue, 'version') then
      Result.TokenType := ttVersion
    else if SameText(IdentifierValue, 'standard') then
      Result.TokenType := ttStandard
    else if SameText(IdentifierValue, 'author') then
      Result.TokenType := ttAuthor
    else if SameText(IdentifierValue, 'title') then
      Result.TokenType := ttTitle
    else if SameText(IdentifierValue, 'description') then
      Result.TokenType := ttDescription
    else if SameText(IdentifierValue, 'keywords') then
      Result.TokenType := ttKeywords
    else if SameText(IdentifierValue, 'funding') then
      Result.TokenType := ttFunding
    else if SameText(IdentifierValue, 'abstract') then
      Result.TokenType := ttAbstract
    else if SameText(IdentifierValue, 'doi') then
      Result.TokenType := ttDOI
    else if SameText(IdentifierValue, 'license') then
      Result.TokenType := ttLicense
    else
      Result.TokenType := ttIdentifier;
    Exit;
  end;

  // Numbers (including negative numbers)
  if (FCurrentChar in ['0'..'9']) or
     ((FCurrentChar = '-') and (FPosition < Length (FSource)) and (FSource[FPosition + 1] in ['0'..'9'])) then
  begin
    Result.TokenValue := ReadNumber;
    Result.TokenType := ttNumber;
    Exit;
  end;

  // Single-character tokens
  Result.TokenValue := FCurrentChar;
  case FCurrentChar of
    '+': Result.TokenType := ttPlus;
    '-': Result.TokenType := ttMinus;  // Only when not part of a negative number
    '*': Result.TokenType := ttMultiply;
    '/': Result.TokenType := ttDivide;
    '^': Result.TokenType := ttPower;
    '(': Result.TokenType := ttLParen;
    ')': Result.TokenType := ttRParen;
    '{': Result.TokenType := ttLBrace;
    '}': Result.TokenType := ttRBrace;
    '=': Result.TokenType := ttEquals;
    '<': Result.TokenType := ttLT;
    '>': Result.TokenType := ttGT;
    ':': Result.TokenType := ttColon;
    ';': Result.TokenType := ttSemiColon;
    ',': Result.TokenType := ttComma;
    '$': Result.TokenType := ttDollar;
    '#': Result.TokenType := ttHash;
  else
    Result.TokenType := ttUnknown;
  end;
  NextChar;
end;


//function TAntimonyLexer.NextToken: TToken;
//var
//  Keyword: TAntimonyKeyword;
//begin
//  // Skip whitespace and comments
//  repeat
//    SkipWhitespace;
//    if (CurrentChar = '/') or (CurrentChar = '#') then
//      SkipComment
//    else
//      Break;
//  until False;
//
//  Result.Line := FLine;
//  Result.Column := FColumn;
//  Result.Keyword := kwFunction; // default value
//
//  case CurrentChar of
//    #0:
//      begin
//        Result.TokenType := ttEOF;
//        Result.Value := '';
//      end;
//    '"', '''':
//      begin
//        Result.TokenType := ttString;
//        Result.Value := ReadString;
//      end;
//    '0'..'9':
//      begin
//        Result.TokenType := ttNumber;
//        Result.Value := ReadNumber;
//      end;
//    'a'..'z', 'A'..'Z', '_':
//      begin
//        Result.Value := ReadIdentifier;
//        if IsAntimonyKeyword(Result.Value, Keyword) then
//        begin
//          Result.TokenType := ttKeyword;
//          Result.Keyword := Keyword;
//        end
//        else
//          Result.TokenType := ttIdentifier;
//      end;
//    '-':
//      begin
//        if PeekChar = '>' then
//        begin
//          Result.TokenType := ttArrow;
//          Result.Value := '->';
//          NextChar;
//          NextChar;
//        end
//        else
//        begin
//          Result.TokenType := ttMinus;
//          Result.Value := '-';
//          NextChar;
//        end;
//      end;
//    '<':
//      begin
//        if PeekChar = '-' then
//        begin
//          NextChar; // skip <
//          if PeekChar = '>' then
//          begin
//            Result.TokenType := ttBiArrow;
//            Result.Value := '<->';  // Reversible arrow
//            NextChar; // skip -
//            NextChar; // skip >
//          end
//          else
//          begin
//            Result.TokenType := ttUnknown;
//            Result.Value := '<';
//            NextChar;
//          end;
//        end
//        else
//        begin
//          Result.TokenType := ttUnknown;
//          Result.Value := '<';
//          NextChar;
//        end;
//      end;
//    ';':
//      begin
//        Result.TokenType := ttSemicolon;
//        Result.Value := ';';
//        NextChar;
//      end;
//    ':':
//      begin
//        if PeekChar = '=' then
//        begin
//          Result.TokenType := ttColonEquals;
//          Result.Value := ':=';
//          NextChar; // skip :
//          NextChar; // skip =
//        end
//        else
//        begin
//          Result.TokenType := ttColon;
//          Result.Value := ':';
//          NextChar;
//        end;
//      end;
//    ',':
//      begin
//        Result.TokenType := ttComma;
//        Result.Value := ',';
//        NextChar;
//      end;
//    '+':
//      begin
//        Result.TokenType := ttPlus;
//        Result.Value := '+';
//        NextChar;
//      end;
//    '*':
//      begin
//        Result.TokenType := ttAsterisk;
//        Result.Value := '*';
//        NextChar;
//      end;
//    '(':
//      begin
//        Result.TokenType := ttLeftParen;
//        Result.Value := '(';
//        NextChar;
//      end;
//    ')':
//      begin
//        Result.TokenType := ttRightParen;
//        Result.Value := ')';
//        NextChar;
//      end;
//    '=':
//      begin
//        Result.TokenType := ttEquals;
//        Result.Value := '=';
//        NextChar;
//      end;
//    '$':
//      begin
//        Result.TokenType := ttDollar;
//        Result.Value := '$';
//        NextChar;
//      end;
//  else
//    Result.TokenType := ttUnknown;
//    Result.Value := CurrentChar;
//    NextChar;
//  end;
//end;

function TAntimonyLexer.Tokenize: TArray<TToken>;
var
  TokenList: TList<TToken>;
  Token: TToken;
begin
  TokenList := TList<TToken>.Create;
  try
    repeat
      Token := GetNextToken;
      TokenList.Add(Token);
    until Token.TokenType = ttEOF;

    Result := TokenList.ToArray;
  finally
    TokenList.Free;
  end;
end;

end.
