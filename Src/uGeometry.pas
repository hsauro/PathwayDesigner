unit uGeometry;

{
  uGeometry.pas
  =============
  Pure 2-D geometry helpers for the biochemical network diagram editor.

  Design rules enforced here:
    - No FMX, Skia, VCL or model references — arithmetic only.
    - All routines operate in whichever coordinate space the caller uses;
      no implicit assumption about world vs. screen.
    - Every public routine has a contract comment explaining its inputs,
      outputs and any preconditions.
}

interface

uses
  System.Types,   // TPointF, TRectF
  System.Math;

// ===========================================================================
//  Types
// ===========================================================================

type
  // The three vertices of a filled arrowhead triangle.
  // Tip is the sharp point; Base1 and Base2 form the wide end.
  TArrowheadVertices = record
    Tip   : TPointF;
    Base1 : TPointF;
    Base2 : TPointF;
  end;

// ===========================================================================
//  Vector arithmetic
// ===========================================================================

// Return the Euclidean length of V.
function VecLen(const V: TPointF): Single;

// Return a unit vector in the same direction as V.
// Returns (0, 0) when |V| < epsilon (degenerate input).
function NormalizeVec(const V: TPointF): TPointF;

// Return a vector perpendicular to V, rotated 90° counter-clockwise.
// Works for any length; does not normalise the result.
function PerpVec(const V: TPointF): TPointF;

// ===========================================================================
//  Distances
// ===========================================================================

// Euclidean distance between two points.
function PointDist(const A, B: TPointF): Single;

// Minimum distance from point P to the finite line segment [A, B].
// Returns 0 when P lies on the segment.
function PointToSegmentDist(const P, A, B: TPointF): Single;

// ===========================================================================
//  Boundary intersection
// ===========================================================================

// Given an axis-aligned rectangle defined by its Centre and half-extents
// (HalfW, HalfH), return the point on the rectangle's *boundary* that lies
// on the ray from Centre toward ExternalPt.
//
// Precondition: ExternalPt is assumed to be outside (or on) the rectangle.
// If ExternalPt == Centre (degenerate), Centre is returned unchanged.
//
// Note: The rectangle is treated as having sharp corners even if it will be
//       rendered with rounded corners.  The error is negligible at typical
//       zoom levels and far simpler than arc/segment intersection.
function RectBoundaryIntersect(const Centre    : TPointF;
                               HalfW, HalfH    : Single;
                               const ExternalPt: TPointF): TPointF;

// ===========================================================================
//  Arrowhead
// ===========================================================================

// Build the three vertices of a filled isoceles-triangle arrowhead.
//
//   Tip      – the sharp end of the arrow (lies exactly on the product line
//              endpoint, which is already set back from the species boundary
//              by the caller's chosen gap).
//   Dir      – unit vector pointing in the direction of travel, i.e.
//              from the reaction junction toward the species node.  The
//              arrow points along +Dir.
//   ArrowLen – length of the triangle measured along Dir (world px).
//   HalfBase – half the width of the triangle's base (world px).
//
// The triangle therefore has:
//   Tip    = Tip
//   Base1  = Tip - Dir*ArrowLen + Perp(Dir)*HalfBase
//   Base2  = Tip - Dir*ArrowLen - Perp(Dir)*HalfBase
function FilledArrowhead(const Tip      : TPointF;
                         const Dir      : TPointF;
                         ArrowLen       : Single = 12.0;
                         HalfBase       : Single = 5.0): TArrowheadVertices;

// ===========================================================================
//  Product-line endpoint (tip with gap)
// ===========================================================================

// Compute the endpoint of a product reaction line.
//
//   Species  – world-coordinate centre of the target species node.
//   HalfW,
//   HalfH    – half-extents of the species rectangle.
//   Junction – world-coordinate junction point of the reaction.
//   Gap      – distance (world px) to leave between the arrowhead tip and
//              the species boundary.
//
// Returns the arrowhead tip position.  The caller draws the product line
// from Junction to this point and then draws FilledArrowhead at this point
// using the same direction vector.
function ProductLineTip(const SpeciesCentre : TPointF;
                        HalfW, HalfH        : Single;
                        const Junction      : TPointF;
                        Gap                 : Single = 6.0): TPointF;

// ===========================================================================
//  View-transform helpers
// ===========================================================================

// Map a world-space point to screen (canvas) space.
//
//   screen = world * Zoom + ScrollOffset
//
// ScrollOffset is the canvas origin expressed in screen pixels; it shifts
// when the user scrolls or pans.
function WorldToScreen(const WorldPt     : TPointF;
                       const ScrollOffset: TPointF;
                       Zoom              : Single): TPointF;

// Inverse of WorldToScreen:  screen -> world.
function ScreenToWorld(const ScreenPt    : TPointF;
                       const ScrollOffset: TPointF;
                       Zoom              : Single): TPointF;

// Scale a scalar distance from world to screen space.
function WorldLenToScreen(WorldLen, Zoom: Single): Single; inline;

// Scale a scalar distance from screen to world space.
function ScreenLenToWorld(ScreenLen, Zoom: Single): Single; inline;

implementation

const
  GEO_EPSILON = 1.0e-7;

// ===========================================================================
//  Vector arithmetic
// ===========================================================================

function VecLen(const V: TPointF): Single;
begin
  Result := Sqrt(V.X * V.X + V.Y * V.Y);
end;

function NormalizeVec(const V: TPointF): TPointF;
var
  Len: Single;
begin
  Len := VecLen(V);
  if Len < GEO_EPSILON then
    Result := TPointF.Create(0.0, 0.0)
  else
  begin
    Result.X := V.X / Len;
    Result.Y := V.Y / Len;
  end;
end;

function PerpVec(const V: TPointF): TPointF;
begin
  // CCW rotation by 90°: (x, y) -> (-y, x)
  Result.X := -V.Y;
  Result.Y :=  V.X;
end;

// ===========================================================================
//  Distances
// ===========================================================================

function PointDist(const A, B: TPointF): Single;
var
  DX, DY: Single;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  Result := Sqrt(DX * DX + DY * DY);
end;

function PointToSegmentDist(const P, A, B: TPointF): Single;
var
  ABX, ABY   : Single;  // B - A
  APX, APY   : Single;  // P - A
  LenSq, t   : Single;
  ClosestX,
  ClosestY   : Single;
  DX, DY     : Single;
begin
  ABX := B.X - A.X;
  ABY := B.Y - A.Y;
  APX := P.X - A.X;
  APY := P.Y - A.Y;

  LenSq := ABX * ABX + ABY * ABY;

  if LenSq < GEO_EPSILON then
  begin
    // Degenerate segment: A == B; return distance to A.
    Result := Sqrt(APX * APX + APY * APY);
    Exit;
  end;

  // Parameter t of the projection of P onto line AB, clamped to [0, 1].
  t := (APX * ABX + APY * ABY) / LenSq;
  t := Max(0.0, Min(1.0, t));

  ClosestX := A.X + t * ABX;
  ClosestY := A.Y + t * ABY;

  DX := P.X - ClosestX;
  DY := P.Y - ClosestY;
  Result := Sqrt(DX * DX + DY * DY);
end;

// ===========================================================================
//  Boundary intersection
// ===========================================================================

function RectBoundaryIntersect(const Centre    : TPointF;
                               HalfW, HalfH    : Single;
                               const ExternalPt: TPointF): TPointF;
var
  Dir    : TPointF;
  tX, tY : Single;
  t      : Single;
begin
  // Vector from centre toward the external point.
  Dir.X := ExternalPt.X - Centre.X;
  Dir.Y := ExternalPt.Y - Centre.Y;

  if (Abs(Dir.X) < GEO_EPSILON) and (Abs(Dir.Y) < GEO_EPSILON) then
  begin
    Result := Centre;
    Exit;
  end;

  Dir := NormalizeVec(Dir);

  // How far along Dir do we travel before hitting the left/right edge?
  if Abs(Dir.X) > GEO_EPSILON then
    tX := HalfW / Abs(Dir.X)
  else
    tX := MaxSingle;

  // How far along Dir do we travel before hitting the top/bottom edge?
  if Abs(Dir.Y) > GEO_EPSILON then
    tY := HalfH / Abs(Dir.Y)
  else
    tY := MaxSingle;

  // The boundary is hit at the smaller of the two distances.
  t := Min(tX, tY);

  Result.X := Centre.X + Dir.X * t;
  Result.Y := Centre.Y + Dir.Y * t;
end;

// ===========================================================================
//  Arrowhead
// ===========================================================================

function FilledArrowhead(const Tip      : TPointF;
                         const Dir      : TPointF;
                         ArrowLen       : Single;
                         HalfBase       : Single): TArrowheadVertices;
var
  D       : TPointF;  // normalised direction
  P       : TPointF;  // perpendicular to D
  BaseCX,
  BaseCY  : Single;   // centre of the arrowhead base
begin
  D := NormalizeVec(Dir);
  P := PerpVec(D);   // unit perp because |D| = 1

  // Centre of the wide end, ArrowLen behind the tip.
  BaseCX := Tip.X - D.X * ArrowLen;
  BaseCY := Tip.Y - D.Y * ArrowLen;

  Result.Tip   := Tip;

  Result.Base1.X := BaseCX + P.X * HalfBase;
  Result.Base1.Y := BaseCY + P.Y * HalfBase;

  Result.Base2.X := BaseCX - P.X * HalfBase;
  Result.Base2.Y := BaseCY - P.Y * HalfBase;
end;

// ===========================================================================
//  Product-line tip
// ===========================================================================

function ProductLineTip(const SpeciesCentre : TPointF;
                        HalfW, HalfH        : Single;
                        const Junction      : TPointF;
                        Gap                 : Single): TPointF;
var
  BoundaryPt : TPointF;
  Dir        : TPointF;
begin
  // Where the line from the junction hits the species boundary.
  BoundaryPt := RectBoundaryIntersect(SpeciesCentre, HalfW, HalfH, Junction);

  // Unit direction FROM junction TOWARD species.
  Dir.X := SpeciesCentre.X - Junction.X;
  Dir.Y := SpeciesCentre.Y - Junction.Y;
  Dir   := NormalizeVec(Dir);

  // Step back by Gap from the boundary: arrowhead tip sits just outside.
  Result.X := BoundaryPt.X - Dir.X * Gap;
  Result.Y := BoundaryPt.Y - Dir.Y * Gap;
end;

// ===========================================================================
//  View transform
// ===========================================================================

function WorldToScreen(const WorldPt     : TPointF;
                       const ScrollOffset: TPointF;
                       Zoom              : Single): TPointF;
begin
  Result.X := WorldPt.X * Zoom + ScrollOffset.X;
  Result.Y := WorldPt.Y * Zoom + ScrollOffset.Y;
end;

function ScreenToWorld(const ScreenPt    : TPointF;
                       const ScrollOffset: TPointF;
                       Zoom              : Single): TPointF;
begin
  if Abs(Zoom) < GEO_EPSILON then Zoom := 1.0;
  Result.X := (ScreenPt.X - ScrollOffset.X) / Zoom;
  Result.Y := (ScreenPt.Y - ScrollOffset.Y) / Zoom;
end;

function WorldLenToScreen(WorldLen, Zoom: Single): Single;
begin
  Result := WorldLen * Zoom;
end;

function ScreenLenToWorld(ScreenLen, Zoom: Single): Single;
const
  GEO_EPSILON = 1.0e-7;
begin
  if Abs(Zoom) < GEO_EPSILON then Zoom := 1.0;
  Result := ScreenLen / Zoom;
end;

end.
