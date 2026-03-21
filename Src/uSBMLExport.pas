unit uSBMLExport;

{
  uSBMLExport.pas
  ===============
  Pure Delphi SBML Level 3 Version 1 writer.  No libSBML dependency.

  The complete SBML document (core + layout) is built as a Delphi string
  and returned from ExportToString / written by ExportToFile.

  MathML conversion
  -----------------
  Kinetic law strings are stored as infix expressions (e.g. 'k1*S1+k2*S2').
  These are parsed into a TExpressionNode AST using the existing
  TAntimonyLexer + TAntimonyExpressionParser, then walked recursively to
  emit Content MathML.

  Supported MathML constructs:
    Numbers       -> <cn> value </cn>
    Identifiers   -> <ci> name </ci>
    +  -  *  /    -> <plus/> <minus/> <times/> <divide/>
    ^             -> <power/>
    unary minus   -> <minus/> with one argument
    < <= > >= == != -> <lt/> <leq/> <gt/> <geq/> <eq/> <neq/>
    && ||  !      -> <and/> <or/> <not/>
    sin cos tan   -> <sin/> <cos/> <tan/>
    asin acos atan-> <arcsin/> <arccos/> <arctan/>
    sinh cosh tanh-> <sinh/> <cosh/> <tanh/>
    exp           -> <exp/>
    ln            -> <ln/>
    log log10     -> <log/> with explicit <logbase><cn>10</cn></logbase>
    sqrt          -> <root/>
    abs           -> <abs/>
    floor         -> <floor/>
    ceil ceiling  -> <ceiling/>
    pow(x,y)      -> <power/>
    min max       -> <min/> <max/>

  If a kinetic law string is empty or fails to parse, no <kineticLaw>
  element is written for that reaction.

  Layout injection
  ----------------
  Layout XML is appended inside <model> before </model>, identical to the
  approach in uSBMLBridge.pas.  uGeometry is used for boundary intersection
  so arcs connect at node edges rather than centres.

  Alias nodes in layout
  ----------------------
  Every TSpeciesNode (primary and alias) gets its own SpeciesGlyph and
  TextGlyph.  Alias glyphs reference their primary's SBML species id via
  layout:species but sit at the alias's own visual position.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  System.Generics.Collections,
  uBioModel,
  uExpressionNode,
  uAntimonyLexer,
  uAntimonyExpressionParser,
  uGeometry;

type
  TSBMLExport = class
  private
    // -----------------------------------------------------------------------
    //  Helpers
    // -----------------------------------------------------------------------

    // Locale-safe float -> string (always '.' decimal separator)
    class function F(Value: Double): string; inline;

    // Bool -> "true"/"false"
    class function B(Value: Boolean): string; inline;

    // -----------------------------------------------------------------------
    //  MathML
    // -----------------------------------------------------------------------

    // Convert an infix kinetic-law string to a MathML <math> block.
    // Returns '' if AInfix is empty or unparseable.
    class function KineticLawToMathML(const AInfix, AIndent: string): string;

    // Recursively convert a TExpressionNode AST to MathML content.
    class function ASTToMathML(ANode: TExpressionNode;
                                const AIndent: string): string;

    // Map TOperatorType to the MathML operator element name.
    class function OperatorElement(AOp: TOperatorType): string;

    // Map a function name to its MathML element name (lower-case input).
    class function FunctionElement(const AFuncName: string): string;

    // -----------------------------------------------------------------------
    //  Core SBML sections
    // -----------------------------------------------------------------------
    class function BuildCompartments (AModel: TBioModel): string;
    class function BuildSpecies      (AModel: TBioModel): string;
    class function BuildParameters   (AModel: TBioModel): string;
    class function BuildReactions    (AModel: TBioModel): string;

    // -----------------------------------------------------------------------
    //  Layout section (identical logic to uSBMLBridge.BuildLayoutXML)
    // -----------------------------------------------------------------------
    class function BuildLayoutXML(AModel: TBioModel): string;

  public
    // Export AModel to a complete SBML Level 3 Version 1 XML string.
    class function ExportToString(AModel: TBioModel): string;

    // Export to file (UTF-8).
    class procedure ExportToFile(AModel: TBioModel; const AFileName: string);
  end;

implementation

const
  SBML_NS    = 'http://www.sbml.org/sbml/level3/version1/core';
  MATHML_NS  = 'http://www.w3.org/1998/Math/MathML';
  LAYOUT_NS  = 'http://www.sbml.org/sbml/level3/version1/layout/version1';
  XSI_NS     = 'http://www.w3.org/2001/XMLSchema-instance';

  JUNCTION_GLYPH_SIZE = 10;

// ===========================================================================
//  Helpers
// ===========================================================================

class function TSBMLExport.F(Value: Double): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create('en-US');
  Result := FloatToStrF(Value, ffGeneral, 15, 4, FS);
end;

class function TSBMLExport.B(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;

// ===========================================================================
//  MathML conversion
// ===========================================================================

class function TSBMLExport.OperatorElement(AOp: TOperatorType): string;
begin
  case AOp of
    otAdd:          Result := 'plus';
    otSubtract:     Result := 'minus';
    otMultiply:     Result := 'times';
    otDivide:       Result := 'divide';
    otPower:        Result := 'power';
    otLess:         Result := 'lt';
    otLessEqual:    Result := 'leq';
    otGreater:      Result := 'gt';
    otGreaterEqual: Result := 'geq';
    otEqual:        Result := 'eq';
    otNotEqual:     Result := 'neq';
    otAnd:          Result := 'and';
    otOr:           Result := 'or';
    otNot:          Result := 'not';
  else
    Result := 'plus';
  end;
end;

class function TSBMLExport.FunctionElement(const AFuncName: string): string;
var
  N: string;
begin
  N := LowerCase(AFuncName);
  if      N = 'sin'     then Result := 'sin'
  else if N = 'cos'     then Result := 'cos'
  else if N = 'tan'     then Result := 'tan'
  else if N = 'asin'    then Result := 'arcsin'
  else if N = 'acos'    then Result := 'arccos'
  else if N = 'atan'    then Result := 'arctan'
  else if N = 'sinh'    then Result := 'sinh'
  else if N = 'cosh'    then Result := 'cosh'
  else if N = 'tanh'    then Result := 'tanh'
  else if N = 'exp'     then Result := 'exp'
  else if N = 'ln'      then Result := 'ln'
  else if N = 'sqrt'    then Result := 'root'
  else if N = 'abs'     then Result := 'abs'
  else if N = 'floor'   then Result := 'floor'
  else if (N = 'ceil') or
          (N = 'ceiling') then Result := 'ceiling'
  else if N = 'pow'     then Result := 'power'
  else if N = 'min'     then Result := 'min'
  else if N = 'max'     then Result := 'max'
  else                       Result := N;   // pass through unknown names
end;

class function TSBMLExport.ASTToMathML(ANode: TExpressionNode;
                                        const AIndent: string): string;
var
  SB    : TStringBuilder;
  Child : TExpressionNode;
  Inner : string;
  i     : Integer;
begin
  if ANode = nil then Exit('');

  SB := TStringBuilder.Create;
  try
    case ANode.NodeType of

      // ---- number ----------------------------------------------------------
      entNumber:
        SB.AppendLine(AIndent + '<cn> ' + ANode.Value + ' </cn>');

      // ---- identifier ------------------------------------------------------
      entIdentifier:
        SB.AppendLine(AIndent + '<ci> ' + ANode.Value + ' </ci>');

      // ---- binary operator -------------------------------------------------
      entBinaryOp:
      begin
        SB.AppendLine(AIndent + '<apply>');
        SB.AppendLine(AIndent + '  <' + OperatorElement(ANode.OpValue) + '/>');
        SB.Append(ASTToMathML(ANode.Left,  AIndent + '  '));
        SB.Append(ASTToMathML(ANode.Right, AIndent + '  '));
        SB.AppendLine(AIndent + '</apply>');
      end;

      // ---- unary operator --------------------------------------------------
      entUnaryOp:
      begin
        SB.AppendLine(AIndent + '<apply>');
        SB.AppendLine(AIndent + '  <' + OperatorElement(ANode.OpValue) + '/>');
        SB.Append(ASTToMathML(ANode.Right, AIndent + '  '));
        SB.AppendLine(AIndent + '</apply>');
      end;

      // ---- function call ---------------------------------------------------
      entFunctionCall:
      begin
        var FuncLower := LowerCase(ANode.FunctionName);

        SB.AppendLine(AIndent + '<apply>');

        // log / log10 need an explicit logbase qualifier
        if (FuncLower = 'log') or (FuncLower = 'log10') then
        begin
          SB.AppendLine(AIndent + '  <log/>');
          SB.AppendLine(AIndent + '  <logbase>');
          SB.AppendLine(AIndent + '    <cn> 10 </cn>');
          SB.AppendLine(AIndent + '  </logbase>');
        end
        // sqrt needs a <degree><cn>2</cn></degree> qualifier
        else if FuncLower = 'sqrt' then
        begin
          SB.AppendLine(AIndent + '  <root/>');
          SB.AppendLine(AIndent + '  <degree>');
          SB.AppendLine(AIndent + '    <cn> 2 </cn>');
          SB.AppendLine(AIndent + '  </degree>');
        end
        else
          SB.AppendLine(AIndent + '  <' + FunctionElement(FuncLower) + '/>');

        for i := 0 to ANode.Arguments.Count - 1 do
          SB.Append(ASTToMathML(ANode.Arguments[i], AIndent + '  '));

        SB.AppendLine(AIndent + '</apply>');
      end;

    end; // case

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSBMLExport.KineticLawToMathML(const AInfix,
                                               AIndent: string): string;
var
  Lexer  : TAntimonyLexer;
  Parser : TAntimonyExpressionParser;
  AST    : TExpressionNode;
  SB     : TStringBuilder;
begin
  Result := '';
  if Trim(AInfix) = '' then Exit;

  Lexer  := TAntimonyLexer.Create(AInfix);
  try
    Parser := TAntimonyExpressionParser.Create(Lexer);
    try
      try
        AST := Parser.Parse;
      except
        Exit;  // unparseable kinetic law — omit <kineticLaw> entirely
      end;
      try
        SB := TStringBuilder.Create;
        try
          SB.AppendLine(AIndent + '<kineticLaw>');
          SB.AppendLine(AIndent + '  <math xmlns="' + MATHML_NS + '">');
          SB.Append    (ASTToMathML(AST, AIndent + '    '));
          SB.AppendLine(AIndent + '  </math>');
          SB.Append    (AIndent + '</kineticLaw>');
          Result := SB.ToString;
        finally
          SB.Free;
        end;
      finally
        AST.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Lexer.Free;
  end;
end;

// ===========================================================================
//  Core SBML sections
// ===========================================================================

class function TSBMLExport.BuildCompartments(AModel: TBioModel): string;
var
  SB : TStringBuilder;
  C  : TCompartment;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('    <listOfCompartments>');

    // Always emit at least the default compartment
    var HasDefault := False;
    for C in AModel.Compartments do
      if SameText(C.Id, 'defaultCompartment') then begin HasDefault := True; Break; end;

    if not HasDefault then
      SB.AppendLine('      <compartment id="defaultCompartment"'
        + ' name="Default Compartment"'
        + ' spatialDimensions="3" size="1" constant="true"/>');

    for C in AModel.Compartments do
      SB.AppendLine('      <compartment id="' + C.Id + '"'
        + ' name="' + C.Id + '"'
        + ' spatialDimensions="' + IntToStr(C.Dimensions) + '"'
        + ' size="' + F(C.Size) + '"'
        + ' constant="true"/>');

    SB.Append('    </listOfCompartments>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSBMLExport.BuildSpecies(AModel: TBioModel): string;
var
  SB     : TStringBuilder;
  S      : TSpeciesNode;
  CompId : string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('    <listOfSpecies>');
    for S in AModel.Species do
    begin
      if S.IsAlias then Continue;
      CompId := S.Compartment;
      if CompId = '' then CompId := 'defaultCompartment';
      SB.AppendLine('      <species id="' + S.Id + '"'
        + ' name="' + S.Id + '"'
        + ' compartment="' + CompId + '"'
        + ' initialConcentration="' + F(S.InitialValue) + '"'
        + ' hasOnlySubstanceUnits="false"'
        + ' boundaryCondition="' + B(S.IsBoundary) + '"'
        + ' constant="' + B(S.IsConstant) + '"/>');
    end;
    SB.Append('    </listOfSpecies>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSBMLExport.BuildParameters(AModel: TBioModel): string;
var
  SB   : TStringBuilder;
  P    : TParameter;
  PVal : Double;
begin
  if AModel.Parameters.Count = 0 then Exit('');

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('    <listOfParameters>');
    for P in AModel.Parameters do
    begin
      PVal := 0.0;
      if TryStrToFloat(P.Expression, PVal) then
        SB.AppendLine('      <parameter id="' + P.Variable + '"'
          + ' name="' + P.Variable + '"'
          + ' value="' + F(PVal) + '"'
          + ' constant="true"/>');
    end;
    SB.Append('    </listOfParameters>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSBMLExport.BuildReactions(AModel: TBioModel): string;
var
  SB   : TStringBuilder;
  R    : TReaction;
  Part : TParticipant;
  KL   : string;
begin
  if AModel.Reactions.Count = 0 then Exit('');

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('    <listOfReactions>');
    for R in AModel.Reactions do
    begin
      SB.AppendLine('      <reaction id="' + R.Id + '"'
        + ' name="' + R.Id + '"'
        + ' reversible="' + B(R.IsReversible) + '"'
        + ' fast="false">');

      // Reactants
      if R.Reactants.Count > 0 then
      begin
        SB.AppendLine('        <listOfReactants>');
        for Part in R.Reactants do
          SB.AppendLine('          <speciesReference species="' + Part.Species.Id + '"'
            + ' stoichiometry="' + F(Part.Stoichiometry) + '"'
            + ' constant="true"/>');
        SB.AppendLine('        </listOfReactants>');
      end;

      // Products
      if R.Products.Count > 0 then
      begin
        SB.AppendLine('        <listOfProducts>');
        for Part in R.Products do
          SB.AppendLine('          <speciesReference species="' + Part.Species.Id + '"'
            + ' stoichiometry="' + F(Part.Stoichiometry) + '"'
            + ' constant="true"/>');
        SB.AppendLine('        </listOfProducts>');
      end;

      // Kinetic law — convert infix to MathML
      KL := KineticLawToMathML(R.KineticLaw, '        ');
      if KL <> '' then
        SB.AppendLine(KL);

      SB.AppendLine('      </reaction>');
    end;
    SB.Append('    </listOfReactions>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ===========================================================================
//  Layout XML  (mirrors uSBMLBridge.BuildLayoutXML with boundary intersection)
// ===========================================================================

class function TSBMLExport.BuildLayoutXML(AModel: TBioModel): string;
var
  SB         : TStringBuilder;
  GlyphIdMap : TDictionary<string, string>;
  S          : TSpeciesNode;
  R          : TReaction;
  Part       : TParticipant;
  GlyphId    : string;
  SpeciesRef : string;
  JX, JY     : Single;
  MaxX, MaxY : Single;
  BP         : TPointF;

  procedure AppendCurve(const Indent: string;
                        IsBez, BezSet: Boolean;
                        X1, Y1, C1X, C1Y, C2X, C2Y, X2, Y2: Single);
  begin
    SB.AppendLine(Indent + '<layout:curve>');
    SB.AppendLine(Indent + '  <layout:listOfCurveSegments>');
    if IsBez and BezSet then
    begin
      SB.AppendLine(Indent + '    <layout:curveSegment xsi:type="CubicBezier">');
      SB.AppendLine(Indent + '      <layout:start layout:x="'      + F(X1)  + '" layout:y="' + F(Y1)  + '"/>');
      SB.AppendLine(Indent + '      <layout:end layout:x="'        + F(X2)  + '" layout:y="' + F(Y2)  + '"/>');
      SB.AppendLine(Indent + '      <layout:basePoint1 layout:x="' + F(C1X) + '" layout:y="' + F(C1Y) + '"/>');
      SB.AppendLine(Indent + '      <layout:basePoint2 layout:x="' + F(C2X) + '" layout:y="' + F(C2Y) + '"/>');
      SB.AppendLine(Indent + '    </layout:curveSegment>');
    end
    else
    begin
      SB.AppendLine(Indent + '    <layout:curveSegment xsi:type="LineSegment">');
      SB.AppendLine(Indent + '      <layout:start layout:x="' + F(X1) + '" layout:y="' + F(Y1) + '"/>');
      SB.AppendLine(Indent + '      <layout:end layout:x="'   + F(X2) + '" layout:y="' + F(Y2) + '"/>');
      SB.AppendLine(Indent + '    </layout:curveSegment>');
    end;
    SB.AppendLine(Indent + '  </layout:listOfCurveSegments>');
    SB.Append    (Indent + '</layout:curve>');
  end;

begin
  MaxX := 0; MaxY := 0;
  for S in AModel.Species do
  begin
    MaxX := Max(MaxX, S.Center.X + S.HalfW);
    MaxY := Max(MaxY, S.Center.Y + S.HalfH);
  end;
  for R in AModel.Reactions do
  begin
    MaxX := Max(MaxX, R.JunctionPos.X);
    MaxY := Max(MaxY, R.JunctionPos.Y);
  end;
  if (MaxX < 1) and (MaxY < 1) then begin MaxX := 800; MaxY := 600; end;

  GlyphIdMap := TDictionary<string, string>.Create;
  SB         := TStringBuilder.Create;
  try
    for S in AModel.Species do
      GlyphIdMap.AddOrSetValue(S.Id, 'sg_' + S.Id);

    SB.AppendLine('    <layout:listOfLayouts xmlns:xsi="' + XSI_NS + '">');
    SB.AppendLine('      <layout:layout layout:id="layout1">');
    SB.AppendLine('        <layout:dimensions layout:width="'
                    + F(MaxX + 80) + '" layout:height="' + F(MaxY + 80) + '"/>');

    // ---- SpeciesGlyphs ----
    SB.AppendLine('        <layout:listOfSpeciesGlyphs>');
    for S in AModel.Species do
    begin
      GlyphId    := GlyphIdMap[S.Id];
     if S.IsAlias then
        SpeciesRef := S.AliasOf.Id
     else
        SpeciesRef := S.Id;

      SB.AppendLine('          <layout:speciesGlyph layout:id="' + GlyphId
                      + '" layout:species="' + SpeciesRef + '">');
      SB.AppendLine('            <layout:boundingBox>');
      SB.AppendLine('              <layout:position layout:x="'
                      + F(S.Center.X - S.HalfW) + '" layout:y="' + F(S.Center.Y - S.HalfH) + '"/>');
      SB.AppendLine('              <layout:dimensions layout:width="'
                      + F(S.Width) + '" layout:height="' + F(S.Height) + '"/>');
      SB.AppendLine('            </layout:boundingBox>');
      SB.AppendLine('          </layout:speciesGlyph>');
    end;
    SB.AppendLine('        </layout:listOfSpeciesGlyphs>');

    // ---- ReactionGlyphs ----
    SB.AppendLine('        <layout:listOfReactionGlyphs>');
    for R in AModel.Reactions do
    begin
      JX := R.JunctionPos.X;
      JY := R.JunctionPos.Y;

      SB.AppendLine('          <layout:reactionGlyph layout:id="rg_'
                      + R.Id + '" layout:reaction="' + R.Id + '">');
      SB.AppendLine('            <layout:boundingBox>');
      SB.AppendLine('              <layout:position layout:x="'
                      + F(JX - JUNCTION_GLYPH_SIZE * 0.5)
                      + '" layout:y="' + F(JY - JUNCTION_GLYPH_SIZE * 0.5) + '"/>');
      SB.AppendLine('              <layout:dimensions layout:width="'
                      + F(JUNCTION_GLYPH_SIZE) + '" layout:height="' + F(JUNCTION_GLYPH_SIZE) + '"/>');
      SB.AppendLine('            </layout:boundingBox>');

      SB.AppendLine('            <layout:listOfSpeciesReferenceGlyphs>');

      // Reactant arcs (species boundary -> junction)
      for Part in R.Reactants do
      begin
        if not GlyphIdMap.ContainsKey(Part.Species.Id) then Continue;
        BP := RectBoundaryIntersect(Part.Species.Center,
                Part.Species.HalfW, Part.Species.HalfH,
                TPointF.Create(JX, JY));
        SB.AppendLine('              <layout:speciesReferenceGlyph'
          + ' layout:id="srg_' + R.Id + '_sub_' + Part.Species.Id + '"'
          + ' layout:speciesGlyph="' + GlyphIdMap[Part.Species.Id] + '"'
          + ' layout:role="substrate">');
        AppendCurve('              ',
          R.IsBezier, Part.CtrlPtsSet,
          BP.X, BP.Y,
          Part.Ctrl1.X, Part.Ctrl1.Y,
          Part.Ctrl2.X, Part.Ctrl2.Y,
          JX, JY);
        SB.AppendLine('');
        SB.AppendLine('              </layout:speciesReferenceGlyph>');
      end;

      // Product arcs (junction -> species boundary); control points reversed
      for Part in R.Products do
      begin
        if not GlyphIdMap.ContainsKey(Part.Species.Id) then Continue;
        BP := RectBoundaryIntersect(Part.Species.Center,
                Part.Species.HalfW, Part.Species.HalfH,
                TPointF.Create(JX, JY));
        SB.AppendLine('              <layout:speciesReferenceGlyph'
          + ' layout:id="srg_' + R.Id + '_prod_' + Part.Species.Id + '"'
          + ' layout:speciesGlyph="' + GlyphIdMap[Part.Species.Id] + '"'
          + ' layout:role="product">');
        AppendCurve('              ',
          R.IsBezier, Part.CtrlPtsSet,
          JX, JY,
          Part.Ctrl2.X, Part.Ctrl2.Y,
          Part.Ctrl1.X, Part.Ctrl1.Y,
          BP.X, BP.Y);
        SB.AppendLine('');
        SB.AppendLine('              </layout:speciesReferenceGlyph>');
      end;

      SB.AppendLine('            </layout:listOfSpeciesReferenceGlyphs>');
      SB.AppendLine('          </layout:reactionGlyph>');
    end;
    SB.AppendLine('        </layout:listOfReactionGlyphs>');

    // ---- TextGlyphs ----
    SB.AppendLine('        <layout:listOfTextGlyphs>');
    for S in AModel.Species do
    begin
      if S.IsAlias then
         SpeciesRef := S.AliasOf.Id
      else
         SpeciesRef := S.Id;

      SB.AppendLine('          <layout:textGlyph'
        + ' layout:id="tg_' + S.Id + '"'
        + ' layout:graphicalObject="' + GlyphIdMap[S.Id] + '"'
        + ' layout:originOfText="' + SpeciesRef + '">');
      SB.AppendLine('            <layout:boundingBox>');
      SB.AppendLine('              <layout:position layout:x="'
                      + F(S.Center.X - S.HalfW) + '" layout:y="' + F(S.Center.Y - S.HalfH) + '"/>');
      SB.AppendLine('              <layout:dimensions layout:width="'
                      + F(S.Width) + '" layout:height="' + F(S.Height) + '"/>');
      SB.AppendLine('            </layout:boundingBox>');
      SB.AppendLine('          </layout:textGlyph>');
    end;
    SB.AppendLine('        </layout:listOfTextGlyphs>');

    SB.AppendLine('      </layout:layout>');
    SB.Append    ('    </layout:listOfLayouts>');

    Result := SB.ToString;
  finally
    SB.Free;
    GlyphIdMap.Free;
  end;
end;

// ===========================================================================
//  Public export
// ===========================================================================

class function TSBMLExport.ExportToString(AModel: TBioModel): string;
var
  SB      : TStringBuilder;
  ModelId : string;
  Comps   : string;
  Spec    : string;
  Params  : string;
  Rxns    : string;
  Layout  : string;
begin
  ModelId := SanitizeSBMLId(AModel.ModelName);
  if ModelId = '' then ModelId := 'model';

  Comps  := BuildCompartments(AModel);
  Spec   := BuildSpecies     (AModel);
  Params := BuildParameters  (AModel);
  Rxns   := BuildReactions   (AModel);
  Layout := BuildLayoutXML   (AModel);

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendLine('<sbml xmlns="' + SBML_NS + '"'
      + ' level="3" version="1"'
      + ' xmlns:layout="' + LAYOUT_NS + '"'
      + ' layout:required="false">');

    SB.AppendLine('  <model id="' + ModelId + '" name="' + AModel.ModelName + '">');

    if Comps  <> '' then SB.AppendLine(Comps);
    if Spec   <> '' then SB.AppendLine(Spec);
    if Params <> '' then SB.AppendLine(Params);
    if Rxns   <> '' then SB.AppendLine(Rxns);
    if Layout <> '' then SB.AppendLine(Layout);

    SB.AppendLine('  </model>');
    SB.Append    ('</sbml>');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class procedure TSBMLExport.ExportToFile(AModel: TBioModel;
                                         const AFileName: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ExportToString(AModel);
    SL.SaveToFile(AFileName, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

end.
