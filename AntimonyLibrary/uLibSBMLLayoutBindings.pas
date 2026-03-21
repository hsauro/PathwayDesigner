unit uLibSBMLLayoutBindings;

{
  uLibSBMLLayoutBindings.pas
  ==========================
  Delphi declarations for the libSBML Layout extension C API
  (SBML Level 3 Layout package, version 1).

  These declarations are kept in a separate unit so that the core
  uLibSBMLBindings.pas is not disturbed.

  Add this unit to the uses clause of any unit that needs to build
  or query layout information.  The same DLL (.\bin\libsbml.dll) is
  used; no additional library is required — libSBML bundles the
  layout package by default.

  Opaque pointer types
  --------------------
  All libSBML objects are represented as opaque Pointer values, matching
  the convention in uLibSBMLBindings.pas.  The distinct type aliases
  (PLayout, PSpeciesGlyph, etc.) are all Pointer underneath; they exist
  only to make call sites readable.

  Conventions for arc curves
  --------------------------
  A SpeciesReferenceGlyph arc flows from the SOURCE end to the TARGET end:
    Reactant leg  : source = species node centre, target = junction centre
    Product leg   : source = junction centre,     target = species node centre
  When the reaction uses Bézier mode and the control points have been set by
  the user (TParticipant.CtrlPtsSet = True), a CubicBezier segment is written.
  Otherwise a plain LineSegment is used.

  For reactant CubicBezier  (species -> junction):
    Start      = species centre
    BasePoint1 = TParticipant.Ctrl1  (handle near species)
    BasePoint2 = TParticipant.Ctrl2  (handle near junction)
    End        = junction centre

  For product CubicBezier   (junction -> species):
    Start      = junction centre
    BasePoint1 = TParticipant.Ctrl2  (reversed: handle near junction)
    BasePoint2 = TParticipant.Ctrl1  (reversed: handle near species)
    End        = species centre
}

interface

uses
  Windows, SysUtils, uLibSBMLBindings;

const
  // Same DLL as the core bindings.
  // Defined again here so this unit can also be used stand-alone.
  LIBSBML_LAYOUT_DLL = '.\bin\libsbml.dll';

  // SBML Layout Level 3 package URI and namespace prefix
  LAYOUT_PKG_URI    = 'http://www.sbml.org/sbml/level3/version1/layout/version1';
  LAYOUT_PKG_PREFIX = 'layout';

  // SpeciesReferenceGlyph role constants (SpeciesReferenceRole_t enum)
  SPECIES_ROLE_UNDEFINED     = 0;
  SPECIES_ROLE_SUBSTRATE     = 1;   // reactant
  SPECIES_ROLE_PRODUCT       = 2;   // product
  SPECIES_ROLE_SIDESUBSTRATE = 3;
  SPECIES_ROLE_SIDEPRODUCT   = 4;
  SPECIES_ROLE_MODIFIER      = 5;
  SPECIES_ROLE_ACTIVATOR     = 6;
  SPECIES_ROLE_INHIBITOR     = 7;
  SPECIES_ROLE_INVALID       = 8;

type
  // ---------------------------------------------------------------------------
  //  Opaque pointer types for layout objects
  //  (all are Pointer; aliases improve readability only)
  // ---------------------------------------------------------------------------
  PLayoutPlugin          = Pointer;   // SBasePlugin_t* cast to layout plugin
  PLayout                = Pointer;   // Layout_t*
  PSpeciesGlyph          = Pointer;   // SpeciesGlyph_t*
  PReactionGlyph         = Pointer;   // ReactionGlyph_t*
  PSpeciesReferenceGlyph = Pointer;   // SpeciesReferenceGlyph_t*
  PBoundingBox           = Pointer;   // BoundingBox_t*
  PDimensions            = Pointer;   // Dimensions_t*
  PLayoutPoint           = Pointer;   // Point_t*  (renamed to avoid clash with TPoint)
  PCurve                 = Pointer;   // Curve_t*
  PLineSegment           = Pointer;   // LineSegment_t*
  PCubicBezier           = Pointer;   // CubicBezier_t*

// ============================================================================
//  Package enable/disable
// ============================================================================

// Enable or disable an SBML Level 3 package.
// flag = 1 to enable, 0 to disable.
// Returns LIBSBML_OPERATION_SUCCESS (0) on success.
function SBMLDocument_enablePackage(document: PSBMLDocument;
    const pkgURI   : PAnsiChar;
    const pkgPrefix: PAnsiChar;
    flag           : Integer): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  SBase plugin access  (used to retrieve the layout plugin from a PModel)
// ============================================================================

// Returns the named plugin attached to an SBase object, or nil if the
// package is not enabled.  Cast the model pointer (PModel) directly to
// Pointer when passing it here — both are Pointer underneath.
function SBase_getPlugin(sbase: Pointer;
    const packageName: PAnsiChar): PLayoutPlugin; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  LayoutModelPlugin
// ============================================================================

// Create and attach a new empty Layout to the model's layout plugin.
function LayoutModelPlugin_createLayout(plugin: PLayoutPlugin): PLayout; cdecl;
    external LIBSBML_LAYOUT_DLL;

function LayoutModelPlugin_getNumLayouts(plugin: PLayoutPlugin): Cardinal; cdecl;
    external LIBSBML_LAYOUT_DLL;

function LayoutModelPlugin_getLayout(plugin: PLayoutPlugin;
    index: Cardinal): PLayout; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  Layout
// ============================================================================

function Layout_setId(layout: PLayout; const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

function Layout_getId(layout: PLayout): PAnsiChar; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Returns the Dimensions object owned by the layout (always non-nil for
// a layout created by LayoutModelPlugin_createLayout).
function Layout_getDimensions(layout: PLayout): PDimensions; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Create a new SpeciesGlyph inside the layout and return it.
function Layout_createSpeciesGlyph(layout: PLayout): PSpeciesGlyph; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Create a new ReactionGlyph inside the layout and return it.
function Layout_createReactionGlyph(layout: PLayout): PReactionGlyph; cdecl;
    external LIBSBML_LAYOUT_DLL;

function Layout_getNumSpeciesGlyphs(layout: PLayout): Cardinal; cdecl;
    external LIBSBML_LAYOUT_DLL;

function Layout_getNumReactionGlyphs(layout: PLayout): Cardinal; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  Dimensions
// ============================================================================

function Dimensions_setWidth (dims: PDimensions; w: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Dimensions_setHeight(dims: PDimensions; h: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Dimensions_getWidth (dims: PDimensions): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Dimensions_getHeight(dims: PDimensions): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  GraphicalObject  (common base of SpeciesGlyph, ReactionGlyph, SRGlyph)
//  Pass any of the glyph pointer types directly; they are all Pointer.
// ============================================================================

function GraphicalObject_setId(go: Pointer; const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

function GraphicalObject_getId(go: Pointer): PAnsiChar; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Returns the BoundingBox owned by the glyph.  Always non-nil after creation.
function GraphicalObject_getBoundingBox(go: Pointer): PBoundingBox; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  BoundingBox  (position + size; used for both species and reaction glyphs)
// ============================================================================

function BoundingBox_setX     (bb: PBoundingBox; x: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_setY     (bb: PBoundingBox; y: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_setWidth (bb: PBoundingBox; w: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_setHeight(bb: PBoundingBox; h: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_getX     (bb: PBoundingBox): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_getY     (bb: PBoundingBox): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_getWidth (bb: PBoundingBox): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;
function BoundingBox_getHeight(bb: PBoundingBox): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  SpeciesGlyph
// ============================================================================

function SpeciesGlyph_setSpeciesId(sg: PSpeciesGlyph;
    const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

function SpeciesGlyph_getSpeciesId(sg: PSpeciesGlyph): PAnsiChar; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  ReactionGlyph
// ============================================================================

function ReactionGlyph_setReactionId(rg: PReactionGlyph;
    const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

function ReactionGlyph_getReactionId(rg: PReactionGlyph): PAnsiChar; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Create and attach a new SpeciesReferenceGlyph (an arc) to this reaction glyph.
function ReactionGlyph_createSpeciesReferenceGlyph(rg: PReactionGlyph)
    : PSpeciesReferenceGlyph; cdecl;
    external LIBSBML_LAYOUT_DLL;

function ReactionGlyph_getNumSpeciesReferenceGlyphs(rg: PReactionGlyph)
    : Cardinal; cdecl;
    external LIBSBML_LAYOUT_DLL;

// The Curve on the reaction glyph itself (usually left empty; arcs are on SRGs).
function ReactionGlyph_getCurve(rg: PReactionGlyph): PCurve; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  SpeciesReferenceGlyph  (the arc connecting a species glyph to a reaction glyph)
// ============================================================================

// Set the Id of the SpeciesGlyph this arc connects to.
function SpeciesReferenceGlyph_setSpeciesGlyphId(srg: PSpeciesReferenceGlyph;
    const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Optionally link this arc to a specific SpeciesReference (reactant/product) in
// the reaction.  Omit (leave empty) if the SBMLBridge does not track SRef IDs.
function SpeciesReferenceGlyph_setSpeciesReferenceId(srg: PSpeciesReferenceGlyph;
    const id: PAnsiChar): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Set the role: use the SPECIES_ROLE_* constants above.
function SpeciesReferenceGlyph_setRole(srg: PSpeciesReferenceGlyph;
    role: Integer): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Returns the Curve that carries this arc's geometry.
function SpeciesReferenceGlyph_getCurve(srg: PSpeciesReferenceGlyph)
    : PCurve; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  Curve  (holds an ordered list of LineSegment or CubicBezier segments)
// ============================================================================

// Append a new straight-line segment and return it.
function Curve_createLineSegment(curve: PCurve): PLineSegment; cdecl;
    external LIBSBML_LAYOUT_DLL;

// Append a new cubic-Bézier segment and return it.
function Curve_createCubicBezier(curve: PCurve): PCubicBezier; cdecl;
    external LIBSBML_LAYOUT_DLL;

function Curve_getNumCurveSegments(curve: PCurve): Cardinal; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  LineSegment
// ============================================================================

// getStart / getEnd return the Point objects owned by the segment.
// Modify them in place via Point_setX / Point_setY.
function LineSegment_getStart(ls: PLineSegment): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;

function LineSegment_getEnd(ls: PLineSegment): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  CubicBezier
// ============================================================================

function CubicBezier_getStart     (cb: PCubicBezier): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;
function CubicBezier_getEnd       (cb: PCubicBezier): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;
function CubicBezier_getBasePoint1(cb: PCubicBezier): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;
function CubicBezier_getBasePoint2(cb: PCubicBezier): PLayoutPoint; cdecl;
    external LIBSBML_LAYOUT_DLL;

// ============================================================================
//  Point  (used for LineSegment endpoints and CubicBezier control points)
// ============================================================================

function Point_setX(p: PLayoutPoint; x: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Point_setY(p: PLayoutPoint; y: Double): Integer; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Point_getX(p: PLayoutPoint): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;
function Point_getY(p: PLayoutPoint): Double; cdecl;
    external LIBSBML_LAYOUT_DLL;

implementation

end.