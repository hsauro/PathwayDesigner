unit uSBMLBridge;

(*
  uSBMLBridge.pas
  ===============
  Translates between an SBML document (via libSBML) and TBioModel.

  Import pipeline
  ---------------
  1. readSBMLFromFile / readSBMLFromString -> PSBMLDocument
  2. Walk compartments, global parameters, species, reactions
  3. Junction positions computed as centroid midpoint (same as Antimony bridge)
  4. Species placed at random positions for subsequent auto-layout

  Export pipeline
  ---------------
  1. Build core SBML Level 3 Version 1 via TSBMLModelManager
  2. Retrieve the XML string via writeSBMLToString
  3. Inject layout data as raw XML into the string:
       - Add layout namespace attributes to the <sbml> element
       - Insert <layout:listOfLayouts> block before </model>

  Layout injection — alias node handling
  ---------------------------------------
  Every TSpeciesNode (primary AND alias) gets its own SpeciesGlyph because
  each occupies a distinct visual position.

    Primary glyph : layout:id="sg_{S.Id}"         layout:species="{S.Id}"
    Alias glyph   : layout:id="sg_{S.Id}"          layout:species="{S.AliasOf.Id}"
                    (S.Id is the alias's unique diagram id)

  The GlyphIdMap is keyed on TSpeciesNode.Id (the diagram id) and covers
  both primaries and aliases.  When a reaction participant is an alias node,
  the arc therefore references that alias's glyph rather than the primary's.

  Bézier arc direction convention
  --------------------------------
  Reactant leg (species -> junction):
    start = species centre, basePoint1 = Ctrl1, basePoint2 = Ctrl2, end = junction
  Product leg  (junction -> species):
    start = junction, basePoint1 = Ctrl2, basePoint2 = Ctrl1, end = species centre
  (Control points are reversed because the direction of travel is reversed.)

  Known limitations
  -----------------
  - SBML AssignmentRules are not imported or exported
  - On import, initialConcentration is preferred; initialAmount used when 0.0
  - Layout import is not implemented (positions are random; run auto-layout)
  - libSBML.dll must be at .\bin\libsbml.dll
*)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  System.Math,
  uBioModel,
  uSBMLExport,
  uGeometry;

type
  TSBMLBridge = class
  private
    // -----------------------------------------------------------------------
    //  Import
    // -----------------------------------------------------------------------
    //class procedure ImportFromDocument(APDoc: PSBMLDocument; AModel: TBioModel);

    // -----------------------------------------------------------------------
    //  Export — core SBML
    // -----------------------------------------------------------------------
    //class function BuildExportDocument(AModel: TBioModel): TSBMLModelManager;

    // -----------------------------------------------------------------------
    //  Export — layout injection
    // -----------------------------------------------------------------------

    // Build the complete <layout:listOfLayouts>...</layout:listOfLayouts> block
    // as a plain string, ready for injection into the SBML document.
    class function BuildLayoutXML(AModel: TBioModel): string;

    // Inject layout namespace attributes into the <sbml> opening tag, and
    // insert the layout block immediately before </model>.
    class function InjectLayout(const ASBML: string; AModel: TBioModel): string;

    // Float -> string always using '.' as decimal separator (locale-safe).
    class function F(Value: Double): string; inline;

  public
    class function  ExportToString  (AModel: TBioModel): string;
    class procedure ExportToFile    (AModel: TBioModel; const AFileName: string);
  end;

implementation

const
  NODE_W              = 80;
  NODE_H              = 36;
  LEFT_MARGIN         = 100;
  RIGHT_MARGIN        = 480;
  JUNCTION_GLYPH_SIZE = 10;

  LAYOUT_NS  = 'http://www.sbml.org/sbml/level3/version1/layout/version1';
  XSI_NS     = 'http://www.w3.org/2001/XMLSchema-instance';

// ---------------------------------------------------------------------------
//  Locale-safe float formatter
// ---------------------------------------------------------------------------

class function TSBMLBridge.F(Value: Double): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create('en-US');
  Result := FloatToStrF(Value, ffGeneral, 10, 4, FS);
end;

// ===========================================================================
//  Import
// ===========================================================================

//class procedure TSBMLBridge.ImportFromDocument(APDoc: PSBMLDocument;
//                                               AModel: TBioModel);
//var
//  M                         : PModel;
//  nComp, nSpec, nParam, nRct: Cardinal;
//  i, j                      : Integer;
//  SComp                     : PCompartment;
//  SSpc                      : PSpecies;
//  SParam                    : PParameter;
//  SRct                      : PReaction;
//  SRef                      : PSpeciesReference;
//  SKL                       : PKineticLaw;
//  CompId, SpecId, SpecName  : string;
//  SpecComp, PId             : string;
//  InitVal                   : Double;
//  IsBoundary, IsConst       : Boolean;
//  PNode                     : TSpeciesNode;
//  Reaction                  : TReaction;
//  Placed                    : TDictionary<string, TSpeciesNode>;
//  PartNode                  : TSpeciesNode;
//  NReact, NProd             : Cardinal;
//  SumRX, SumRY              : Single;
//  SumPX, SumPY              : Single;
//  JX, JY                    : Single;
//  Stoich                    : Double;
//  SpeciesId                 : string;
//begin
//  M := SBMLDocument_getModel(APDoc);
//  if M = nil then
//    raise ESBMLException.Create(
//      'The SBML document contains no model.'#13#10 +
//      'The file may have fatal validation errors.');
//
//  AModel.Clear;
//
//  var MName := PAnsiCharToString(Model_getName(M));
//  if MName = '' then MName := PAnsiCharToString(Model_getId(M));
//  AModel.ModelName := MName;
//
//  // --- Compartments ---
//  nComp := Model_getNumCompartments(M);
//  for i := 0 to Integer(nComp) - 1 do
//  begin
//    SComp  := Model_getCompartment(M, Cardinal(i));
//    CompId := PAnsiCharToString(Compartment_getId(SComp));
//    if SameText(CompId, 'defaultCompartment') then Continue;
//    AModel.AddCompartment(
//      CompId,
//      Compartment_getSize(SComp),
//      Integer(Compartment_getSpatialDimensions(SComp)));
//  end;
//
//  // --- Global parameters ---
//  nParam := Model_getNumParameters(M);
//  for i := 0 to Integer(nParam) - 1 do
//  begin
//    SParam := Model_getParameter(M, Cardinal(i));
//    PId    := PAnsiCharToString(Parameter_getId(SParam));
//    AModel.AddParameter(PId, FloatToStr(Parameter_getValue(SParam)));
//  end;
//
//  // --- Species ---
//  Placed := TDictionary<string, TSpeciesNode>.Create;
//  try
//    nSpec := Model_getNumSpecies(M);
//    for i := 0 to Integer(nSpec) - 1 do
//    begin
//      SSpc       := Model_getSpecies(M, Cardinal(i));
//      SpecId     := PAnsiCharToString(Species_getId(SSpc));
//      SpecName   := PAnsiCharToString(Species_getName(SSpc));
//      if SpecName = '' then SpecName := SpecId;
//      SpecComp   := PAnsiCharToString(Species_getCompartment(SSpc));
//      IsBoundary := Species_getBoundaryCondition(SSpc) <> 0;
//      IsConst    := Species_getConstant(SSpc) <> 0;
//
//      InitVal := Species_getInitialConcentration(SSpc);
//      if InitVal = 0.0 then InitVal := Species_getInitialAmount(SSpc);
//
//      PNode := AModel.AddSpecies(SpecName,
//                 LEFT_MARGIN + Random(500), 80 + Random(400),
//                 NODE_W, NODE_H);
//      PNode.Id           := SpecId;
//      PNode.IsBoundary   := IsBoundary;
//      PNode.IsConstant   := IsConst;
//      PNode.Compartment  := SpecComp;
//      PNode.InitialValue := InitVal;
//      Placed.AddOrSetValue(SpecId, PNode);
//    end;
//
//    // --- Reactions ---
//    nRct := Model_getNumReactions(M);
//    for i := 0 to Integer(nRct) - 1 do
//    begin
//      SRct   := Model_getReaction(M, Cardinal(i));
//      NReact := Reaction_getNumReactants(SRct);
//      NProd  := Reaction_getNumProducts(SRct);
//
//      SumRX := 0; SumRY := 0;
//      for j := 0 to Integer(NReact) - 1 do
//      begin
//        SRef      := Reaction_getReactant(SRct, Cardinal(j));
//        SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SRef));
//        if Placed.TryGetValue(SpeciesId, PartNode) then
//        begin
//          SumRX := SumRX + PartNode.Center.X;
//          SumRY := SumRY + PartNode.Center.Y;
//        end;
//      end;
//      SumPX := 0; SumPY := 0;
//      for j := 0 to Integer(NProd) - 1 do
//      begin
//        SRef      := Reaction_getProduct(SRct, Cardinal(j));
//        SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SRef));
//        if Placed.TryGetValue(SpeciesId, PartNode) then
//        begin
//          SumPX := SumPX + PartNode.Center.X;
//          SumPY := SumPY + PartNode.Center.Y;
//        end;
//      end;
//
//      if NReact > 0 then begin SumRX := SumRX / NReact; SumRY := SumRY / NReact; end
//      else               begin SumRX := LEFT_MARGIN;     SumRY := 80;             end;
//      if NProd  > 0 then begin SumPX := SumPX / NProd;  SumPY := SumPY / NProd;  end
//      else               begin SumPX := RIGHT_MARGIN;    SumPY := 80;             end;
//
//      JX := (SumRX + SumPX) * 0.5;
//      JY := (SumRY + SumPY) * 0.5;
//
//      Reaction              := AModel.AddReaction(JX, JY);
//      Reaction.Id           := PAnsiCharToString(Reaction_getId(SRct));
//      Reaction.IsReversible := Reaction_getReversible(SRct) <> 0;
//      SKL                   := Reaction_getKineticLaw(SRct);
//      if SKL <> nil then
//        Reaction.KineticLaw := PAnsiCharToString(KineticLaw_getFormula(SKL));
//
//      for j := 0 to Integer(NReact) - 1 do
//      begin
//        SRef      := Reaction_getReactant(SRct, Cardinal(j));
//        SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SRef));
//        Stoich    := SpeciesReference_getStoichiometry(SRef);
//        if Stoich = 0.0 then Stoich := 1.0;
//        if Placed.TryGetValue(SpeciesId, PartNode) then
//          Reaction.Reactants.Add(TParticipant.Create(PartNode, Stoich));
//      end;
//      for j := 0 to Integer(NProd) - 1 do
//      begin
//        SRef      := Reaction_getProduct(SRct, Cardinal(j));
//        SpeciesId := PAnsiCharToString(SpeciesReference_getSpecies(SRef));
//        Stoich    := SpeciesReference_getStoichiometry(SRef);
//        if Stoich = 0.0 then Stoich := 1.0;
//        if Placed.TryGetValue(SpeciesId, PartNode) then
//          Reaction.Products.Add(TParticipant.Create(PartNode, Stoich));
//      end;
//
//      Reaction.IsLinear := (NReact = 1) and (NProd = 1);
//      Reaction.IsBezier := False;
//    end;
//
//  finally
//    Placed.Free;
//  end;
//end;

// ===========================================================================
//  Core SBML export
// ===========================================================================

//class function TSBMLBridge.BuildExportDocument(AModel: TBioModel): TSBMLModelManager;
//var
//  C       : TCompartment;
//  S       : TSpeciesNode;
//  R       : TReaction;
//  P       : TParameter;
//  Part    : TParticipant;
//  SBMLRct : TSBMLReaction;
//  Sp      : TSBMLSpecies;
//  ModelId : string;
//  CompId  : string;
//  PVal    : Double;
//begin
//  Result := TSBMLModelManager.Create(3, 1);
//  try
//    ModelId := SanitizeSBMLId(AModel.ModelName);
//    if ModelId = '' then ModelId := 'model';
//    Result.SetModelId(ModelId);
//    Result.SetModelName(AModel.ModelName);
//
//    if AModel.Compartments.Count = 0 then
//      Result.CreateCompartment('defaultCompartment', 'Default Compartment', 1.0)
//    else
//    begin
//      var HasDefault := False;
//      for C in AModel.Compartments do
//      begin
//        Result.CreateCompartment(C.Id, C.Id, C.Size);
//        if SameText(C.Id, 'defaultCompartment') then HasDefault := True;
//      end;
//      if not HasDefault then
//        Result.CreateCompartment('defaultCompartment', 'Default Compartment', 1.0);
//    end;
//
//    // Primary species only — aliases have no independent biochemical identity
//    for S in AModel.Species do
//    begin
//      if S.IsAlias then Continue;
//      CompId := S.Compartment;
//      if CompId = '' then CompId := 'defaultCompartment';
//      Sp                   := Result.CreateSpecies(S.Id, S.Id, CompId, S.InitialValue);
//      Sp.BoundaryCondition := S.IsBoundary;
//      Sp.IsConstant        := S.IsConstant;
//    end;
//
//    for P in AModel.Parameters do
//    begin
//      PVal := 0.0;
//      if TryStrToFloat(P.Expression, PVal) then
//        Result.CreateParameter(P.Variable, P.Variable, PVal);
//    end;
//
//    for R in AModel.Reactions do
//    begin
//      SBMLRct            := Result.CreateReaction(R.Id, R.Id);
//      SBMLRct.Reversible := R.IsReversible;
//      for Part in R.Reactants do
//        SBMLRct.AddReactant(Part.Species.Id, Part.Stoichiometry);
//      for Part in R.Products do
//        SBMLRct.AddProduct(Part.Species.Id, Part.Stoichiometry);
//      if R.KineticLaw <> '' then
//        SBMLRct.SetKineticLaw(R.KineticLaw);
//    end;
//
//  except
//    Result.Free;
//    raise;
//  end;
//end;

// ===========================================================================
//  Layout XML builder
// ===========================================================================

class function TSBMLBridge.BuildLayoutXML(AModel: TBioModel): string;
var
  SB         : TStringBuilder;
  GlyphIdMap : TDictionary<string, string>;  // diagram node Id -> glyph Id
  S          : TSpeciesNode;
  R          : TReaction;
  Part       : TParticipant;
  GlyphId    : string;
  SpeciesRef : string;   // the SBML species id the glyph references
  JX, JY     : Single;
  MaxX, MaxY : Single;

  // Append a curveSegment element — LineSegment or CubicBezier.
  // For a reactant leg the direction is species->junction (Ctrl1 near species,
  // Ctrl2 near junction).  For a product leg the direction is junction->species
  // and the control points are reversed.
  procedure AppendCurve(const Indent: string;
                        IsBezier: Boolean; BezierSet: Boolean;
                        X1, Y1: Single;       // start point
                        C1X, C1Y: Single;     // basePoint1
                        C2X, C2Y: Single;     // basePoint2
                        X2, Y2: Single);      // end point
  begin
    SB.AppendLine(Indent + '      <layout:curve>');
    SB.AppendLine(Indent + '        <layout:listOfCurveSegments>');
    if IsBezier and BezierSet then
    begin
      SB.AppendLine(Indent + '          <layout:curveSegment xsi:type="CubicBezier">');
      SB.AppendLine(Indent + '            <layout:start layout:x="'       + F(X1)  + '" layout:y="' + F(Y1)  + '"/>');
      SB.AppendLine(Indent + '            <layout:end layout:x="'         + F(X2)  + '" layout:y="' + F(Y2)  + '"/>');
      SB.AppendLine(Indent + '            <layout:basePoint1 layout:x="'  + F(C1X) + '" layout:y="' + F(C1Y) + '"/>');
      SB.AppendLine(Indent + '            <layout:basePoint2 layout:x="'  + F(C2X) + '" layout:y="' + F(C2Y) + '"/>');
      SB.AppendLine(Indent + '          </layout:curveSegment>');
    end
    else
    begin
      SB.AppendLine(Indent + '          <layout:curveSegment xsi:type="LineSegment">');
      SB.AppendLine(Indent + '            <layout:start layout:x="' + F(X1) + '" layout:y="' + F(Y1) + '"/>');
      SB.AppendLine(Indent + '            <layout:end layout:x="'   + F(X2) + '" layout:y="' + F(Y2) + '"/>');
      SB.AppendLine(Indent + '          </layout:curveSegment>');
    end;
    SB.AppendLine(Indent + '        </layout:listOfCurveSegments>');
    SB.AppendLine(Indent + '      </layout:curve>');
  end;

begin
  // ------------------------------------------------------------------
  //  Compute canvas size from all node positions
  // ------------------------------------------------------------------
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

  // ------------------------------------------------------------------
  //  Build glyph-id map: every node (primary + alias) gets an entry.
  //  Key = diagram node Id,  Value = layout glyph Id ("sg_" + node.Id)
  // ------------------------------------------------------------------
  GlyphIdMap := TDictionary<string, string>.Create;
  SB         := TStringBuilder.Create;
  try
    for S in AModel.Species do
      GlyphIdMap.AddOrSetValue(S.Id, 'sg_' + S.Id);

    // ------------------------------------------------------------------
    //  Open listOfLayouts
    // ------------------------------------------------------------------
    SB.AppendLine('      <layout:listOfLayouts xmlns:xsi="' + XSI_NS + '">');
    SB.AppendLine('        <layout:layout layout:id="layout1">');
    SB.AppendLine('          <layout:dimensions layout:width="'
                    + F(MaxX + 80) + '" layout:height="' + F(MaxY + 80) + '"/>');

    // ------------------------------------------------------------------
    //  SpeciesGlyphs — one per node, primaries and aliases alike
    // ------------------------------------------------------------------
    SB.AppendLine('          <layout:listOfSpeciesGlyphs>');
    for S in AModel.Species do
    begin
      GlyphId := GlyphIdMap[S.Id];

      // Aliases reference the primary's SBML species id; primaries reference themselves
      if S.IsAlias then SpeciesRef := S.AliasOf.Id
      else              SpeciesRef := S.Id;

      SB.AppendLine('            <layout:speciesGlyph layout:id="' + GlyphId
                      + '" layout:species="' + SpeciesRef + '">');
      SB.AppendLine('              <layout:boundingBox>');
      SB.AppendLine('                <layout:position layout:x="'
                      + F(S.Center.X - S.HalfW) + '" layout:y="' + F(S.Center.Y - S.HalfH) + '"/>');
      SB.AppendLine('                <layout:dimensions layout:width="'
                      + F(S.Width) + '" layout:height="' + F(S.Height) + '"/>');
      SB.AppendLine('              </layout:boundingBox>');
      SB.AppendLine('            </layout:speciesGlyph>');
    end;
    SB.AppendLine('          </layout:listOfSpeciesGlyphs>');

    // ------------------------------------------------------------------
    //  ReactionGlyphs
    // ------------------------------------------------------------------
    SB.AppendLine('          <layout:listOfReactionGlyphs>');
    for R in AModel.Reactions do
    begin
      JX := R.JunctionPos.X;
      JY := R.JunctionPos.Y;

      SB.AppendLine('            <layout:reactionGlyph layout:id="rg_'
                      + R.Id + '" layout:reaction="' + R.Id + '">');

      // Small bounding-box dot centred on the junction handle
      SB.AppendLine('              <layout:boundingBox>');
      SB.AppendLine('                <layout:position layout:x="'
                      + F(JX - JUNCTION_GLYPH_SIZE * 0.5)
                      + '" layout:y="' + F(JY - JUNCTION_GLYPH_SIZE * 0.5) + '"/>');
      SB.AppendLine('                <layout:dimensions layout:width="'
                      + F(JUNCTION_GLYPH_SIZE)
                      + '" layout:height="' + F(JUNCTION_GLYPH_SIZE) + '"/>');
      SB.AppendLine('              </layout:boundingBox>');

      SB.AppendLine('              <layout:listOfSpeciesReferenceGlyphs>');

      // ---- Reactant arcs  (species centre -> junction) ----
      for Part in R.Reactants do
      begin
        if not GlyphIdMap.ContainsKey(Part.Species.Id) then Continue;

        SB.AppendLine('                <layout:speciesReferenceGlyph'
          + ' layout:id="srg_' + R.Id + '_sub_' + Part.Species.Id + '"'
          + ' layout:speciesGlyph="' + GlyphIdMap[Part.Species.Id] + '"'
          + ' layout:role="substrate">');

        var BP := RectBoundaryIntersect(Part.Species.Center,
                    Part.Species.HalfW, Part.Species.HalfH,
                    TPointF.Create(JX, JY));
        AppendCurve('                ',
          R.IsBezier, Part.CtrlPtsSet,
          BP.X, BP.Y,                                    // start at boundary
          Part.Ctrl1.X, Part.Ctrl1.Y,
          Part.Ctrl2.X, Part.Ctrl2.Y,
          JX, JY);

        SB.AppendLine('                </layout:speciesReferenceGlyph>');
      end;

      // ---- Product arcs  (junction -> species) ----
      // Direction reversed: control points also reversed.
      for Part in R.Products do
      begin
        if not GlyphIdMap.ContainsKey(Part.Species.Id) then Continue;

        SB.AppendLine('                <layout:speciesReferenceGlyph'
          + ' layout:id="srg_' + R.Id + '_prod_' + Part.Species.Id + '"'
          + ' layout:speciesGlyph="' + GlyphIdMap[Part.Species.Id] + '"'
          + ' layout:role="product">');

        var BP := RectBoundaryIntersect(Part.Species.Center,
                    Part.Species.HalfW, Part.Species.HalfH,
                    TPointF.Create(JX, JY));
        AppendCurve('                ',
          R.IsBezier, Part.CtrlPtsSet,
          JX, JY,
          Part.Ctrl2.X, Part.Ctrl2.Y,
          Part.Ctrl1.X, Part.Ctrl1.Y,
          BP.X, BP.Y);                                   // end at boundary

        SB.AppendLine('                </layout:speciesReferenceGlyph>');
      end;

      SB.AppendLine('              </layout:listOfSpeciesReferenceGlyphs>');
      SB.AppendLine('            </layout:reactionGlyph>');
    end;
    SB.AppendLine('          </layout:listOfReactionGlyphs>');

    SB.AppendLine('          <layout:listOfTextGlyphs>');
    for S in AModel.Species do
    begin
      // Text glyph references the species glyph and the species itself
      if S.IsAlias then SpeciesRef := S.AliasOf.Id
      else              SpeciesRef := S.Id;

      SB.AppendLine('            <layout:textGlyph'
        + ' layout:id="tg_' + S.Id + '"'
        + ' layout:graphicalObject="' + GlyphIdMap[S.Id] + '"'
        + ' layout:originOfText="' + SpeciesRef + '">');
      SB.AppendLine('              <layout:boundingBox>');
      SB.AppendLine('                <layout:position layout:x="'
        + F(S.Center.X - S.HalfW) + '" layout:y="' + F(S.Center.Y - S.HalfH) + '"/>');
      SB.AppendLine('                <layout:dimensions layout:width="'
        + F(S.Width) + '" layout:height="' + F(S.Height) + '"/>');
      SB.AppendLine('              </layout:boundingBox>');
      SB.AppendLine('            </layout:textGlyph>');
    end;
    SB.AppendLine('          </layout:listOfTextGlyphs>');

    SB.AppendLine('        </layout:layout>');
    SB.Append    ('      </layout:listOfLayouts>');

    Result := SB.ToString;
  finally
    SB.Free;
    GlyphIdMap.Free;
  end;
end;

// ===========================================================================
//  XML injection
// ===========================================================================

class function TSBMLBridge.InjectLayout(const ASBML: string;
                                        AModel: TBioModel): string;
var
  LayoutXML    : string;
  TagEnd       : Integer;
  ModelEnd     : Integer;
  WithNS       : string;
  NSAttributes : string;
begin
  LayoutXML := BuildLayoutXML(AModel);

  // ------------------------------------------------------------------
  //  Step 1 — add layout namespace attributes to the <sbml> opening tag.
  //  libSBML writes the tag on a single line, e.g.:
  //    <sbml xmlns="..." level="3" version="1">
  //  We find the closing '>' of that tag and insert before it.
  // ------------------------------------------------------------------
  var SbmlTagStart := Pos('<sbml', ASBML);
  if SbmlTagStart = 0 then begin Result := ASBML; Exit; end;

  TagEnd := SbmlTagStart;
  while (TagEnd <= Length(ASBML)) and (ASBML[TagEnd] <> '>') do
    Inc(TagEnd);
  // TagEnd now points at '>'

  NSAttributes := ' xmlns:layout="' + LAYOUT_NS + '" layout:required="false"';

  WithNS := Copy(ASBML, 1, TagEnd - 1)
          + NSAttributes
          + Copy(ASBML, TagEnd, MaxInt);

  // ------------------------------------------------------------------
  //  Step 2 — insert the layout block immediately before </model>.
  // ------------------------------------------------------------------
  ModelEnd := Pos('</model>', WithNS);
  if ModelEnd = 0 then begin Result := WithNS; Exit; end;

  Result := Copy(WithNS, 1, ModelEnd - 1)
          + LayoutXML + sLineBreak
          + Copy(WithNS, ModelEnd, MaxInt);
end;

// ===========================================================================
//  Public Export
// ===========================================================================

class function TSBMLBridge.ExportToString(AModel: TBioModel): string;
begin
  Result := TSBMLExport.ExportToString(AModel);
end;

class procedure TSBMLBridge.ExportToFile(AModel: TBioModel; const AFileName: string);
begin
  TSBMLExport.ExportToFile(AModel, AFileName);
end;

end.
