unit uLibSBNW;

{ Copyright 2013-14 Herbert M Sauro

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

   In plain english this means:

   You CAN freely download and use this software, in whole or in part, for personal,
   company internal, or commercial purposes;

   You CAN use the software in packages or distributions that you create.

   You SHOULD include a copy of the license in any redistribution you may make;

   You are NOT required include the source of software, or of any modifications you may
   have made to it, in any redistribution you may assemble that includes it.

   YOU CANNOT:

   redistribute any piece of this software without proper attribution;
}

interface

Uses SysUtils, Classes, Windows, System.Types, IOUtils;

const
   DEFAULT_STIFFNESS = 10;
   DEFAULT_GRAVITY = 0;
   DEFAULT_USEBOUNDARY = False;
   DEFAULT_USEMAGNETISM = False;

type
   TGFPoint = record
       x, y : double;
   end;

   TArrayGFPoint = array of TGFPoint;

   TInternalGFBezier = record
     s, c1, c2, e : TGFPoint;
   end;

   TGFBezier = record
     s, c1, c2, e : TPointF;
   end;

   TGF_Options = record
    // Stiffness measure (determines closness of nodes)
    stiffness : double;
    // Constrain to boundary?
    useBoundary : integer;
    /// Use magnetism? (forces bridge reactions)
    useMagnetism : integer;
    // Amount of gravity
    gravity : double;
    // Center of gravitational force
    baryx, baryy : double;
    // Should the barycenter be set automatically from layout info?
    autobary : integer;
    // Enable compartment force calc?
    enable_comps : integer;
    // Randomize node positions before doing layout algo (library code DOES NOT call srand for reproducibility reasons)
    prerandomize : integer;
    // Padding on compartments.
    compartmentPadding : double;
   end;
   PGF_Options = ^TGF_Options;

   TGFSpeciesRole = (rSubstrate, rProduct, rSideSubstrate, rSideProduct, rModifier, rActivator, rInhibitor);

   PGF_SBMLModel = pointer;
   PGF_Compartment = pointer;
   PGF_Node = pointer;
   PGF_Reaction = pointer;
   PGF_Curve = pointer;
   PGF_layoutInfo = pointer;
   PGF_Network = pointer;

   function SetDllDirectory(lpPathName:PWideChar): Bool; stdcall; external 'kernel32.dll' name 'SetDllDirectoryW';

var
   grapgfabDLLLoaded : boolean;


function  gf_getVersion : AnsiString;
function  gf_loadSBMLString (value : AnsiString; errMsg : AnsiString) : PGF_SBMLModel;
function  gf_getSBMLWithLayout (model : PGF_SBMLModel; layout : PGF_layoutInfo) : AnsiString;
function  gf_getId (network : PGF_Network) : AnsiString;
function  gf_renderTikZ (layout : PGF_layoutInfo) : AnsiString;

function  gf_processLayout (currentModel : PGF_SBMLModel) : PGF_layoutInfo;
function  gf_getNetwork (layout : PGF_layoutInfo) : PGF_Network;
function 	gf_getNumberOfMasterNodes (network : PGF_Network) : Integer;  // Only master nodes
function  gf_getNumberOfNodes (network : PGF_Network) : integer;  // Alias plus master nodes
function  gf_getNumberOfReactions (network : pointer) : integer;
function  gf_getNumberOfCompartments (network : PGF_Network) : integer;

function  gf_getCompartment (network : PGF_Network; index : integer) : PGF_Compartment;
function  gf_getCompartmentId (network : PGF_Network; index : integer) : AnsiString;
function  gf_getCompartmentIdFromCompartment (compartment : PGF_Compartment) : AnsiString;
function  gf_getCompartmentWidth (network : PGF_Network; index : integer) : double;
function  gf_getCompartmentHeight (network : PGF_Network; index : integer) : double;
function  gf_getCompartmentMinCorner (network : PGF_Network; index : integer) : TPointF;
function  gf_getCompartmentMaxCorner (network : PGF_Network; index : integer) : TPointF;
function  gf_getCompartmentById (network : PGF_Network; id : PAnsiChar) : PGF_Compartment;
function  gf_getDefaultCompartmentId : AnsiString;
function  gf_setDefaultCompartmentId (id : AnsiString) : Boolean;
function  gf_getNodeGetCompartment (network : PGF_Network; node : PGF_Node) : PGF_Compartment;

function  gf_getMasterNode (network : PGF_Network; index : integer) : PGF_Node;
function  gf_getNodeId (node : PGF_Node) : AnsiString;
function  gf_getNodeDisplayName (node : PGF_Node) : AnsiString;

function  gf_getNodeCentroid (layout : PGF_layoutInfo; nodeId : PAnsiChar) : TPointF; overload;
function  gf_getNodeCentroid (node : PGF_Node) : TPointF; overload;
procedure gf_setNodeCentroid (node : PGF_Node; pt : TPointF);

function  gf_getNodeWidth (node : PGF_Node) : double;
function  gf_getNodeHeight (node : PGF_Node) : double;
procedure gf_setNodeWidth (node : PGF_Node; width : double);
procedure gf_setNodeHeight (node : PGF_Node; height : double);

function  gf_getReaction (network : PGF_Network; index : integer) : PGF_Reaction;
function  gf_getNumberOfCurves (reaction : PGF_Reaction) : integer;
function  gf_getReactionCurve (reaction : PGF_Reaction; index : integer) : PGF_Curve;
function  gf_getCurveControlPoints (curve : PGF_Curve) : TGFBezier;
function  gf_getCurveRole (curve : PGF_Curve; reaction : PGF_Reaction) : TGFSpeciesRole;
function  gf_getReactionCentroid (reaction : PGF_Reaction) : TPointF;
function  gf_getReactionSpecGeti (reaction : PGF_Reaction; index: Integer) : integer;
function  gf_reaction_getNumSpec	(reaction : PGF_Reaction) : integer;

function  gf_CurveHasArrowHead  (curve : PGF_Curve) : Boolean;
function  gf_getArrowVertices (curve : PGF_Curve; var n : integer; var pts : TArrayGFPoint) : integer;
function  gf_hasArrowHead (curve : PGF_Curve) : integer;

procedure gf_randomizeLayout (layout : PGF_layoutInfo);
procedure gf_lockNode (node : PGF_Node);
procedure gf_unLockNode (node : PGF_Node);
function  gf_isNodeLocked (node : PGF_Node) : boolean;

function  gf_node_isAliased	(node : PGF_Node) : Integer;
procedure gf_aliasNodeWithDegree (layout : PGF_layoutInfo; minDegree : integer);
function  gf_getNumberOfAliasNodes (network : PGF_Network; masterNode : PGF_Node) : integer;
function  gf_getAliasNodep (network : PGF_Network; masterNode : PGF_Node; index : integer) : PGF_Node;
// Not sure what this method does:
//function  gf_make_alias_node	(node : PGF_Node; network : PGF_Network) : integer;

procedure gf_computeLayout (opt : TGF_Options; layout : PGF_layoutInfo);
procedure gf_getLayoutOptDefaults (opt : PGF_Options);
procedure gf_getLayoutOpts (opt : PGF_Options);
procedure gf_setCompartmentMinCorner (compartment : PGF_Compartment; pt : TPointF);
procedure gf_setCompartmentMaxCorner (compartment : PGF_Compartment; pt : TPointF);
procedure gf_fitToWindow (layout : PGF_layoutInfo; left, top, right, bottom : double);
function  gf_IsThereALayout (network : PGF_Network) : boolean;
procedure gf_moveNetworkToFirstQuad	(layout : PGF_layoutInfo; left, top : double);

function  gf_createNewSBMLModel : PGF_SBMLModel;
function  gf_createLayout (level, version : UInt64; width, height : UInt64) : PGF_layoutInfo;
function  gf_createCompartment (network : PGF_Network; id, name : PAnsiChar) : PGF_Compartment;
function  gf_createNode (network : PGF_Network; id, name : PAnsiChar; compartment : PGF_Compartment) : PGF_Node;
function  gf_createAliasNode (network : PGF_Network; sourceNode : PGF_Node) : PGF_Node;
function  gf_createReaction (network : PGF_Network; id, name : PAnsiChar) : PGF_Reaction;
function  gf_connectNodeToReaction (network : PGF_Network; node : PGF_Node; reaction : PGF_Reaction; role : TGFSpeciesRole) : Integer;

procedure gf_freeModelAndLayout (sbmlModel : PGF_SBMLModel; layout : PGF_layoutInfo);

function  gf_getLastError : AnsiString;
procedure gf_free (ptr : pointer);
procedure gf_strFree (ptr : PAnsiChar);
procedure gf_freeModel (currentModel : PGF_SBMLModel);


function  loadlibSBNW (var errMsg : string; methodList : TStringList) : boolean;
procedure releaseSBNWLibrary;

implementation

type
   ArrayOfPAnsiChar = array[0..1000] of PAnsiChar;
   PAnsiCharArray = ^ArrayOfPAnsiChar;
   PPAnsiCharArray = PAnsiCharArray;

   PPPAnsiCharArray = ^PPAnsiCharArray;

var DLLHandle : NativeInt;
    libName : AnsiString = 'sbnw.dll';

    libGetLastError : function : PAnsiChar; cdecl;
    libHaveError : function : integer; cdecl;

    libGetVersion : function : PAnsiChar; cdecl;
    libLoadSBMLbuf : function (buf : PAnsiChar) : PGF_SBMLModel; cdecl;
    libGetId: function (network : PGF_Network) : PAnsiChar; cdecl;

    libLoadSBMLWithLayout : function (model : PGF_SBMLModel; layout : PGF_layoutInfo) : PAnsiChar; cdecl;
    libGetTikZ : function (layout : PGF_layoutInfo) : PAnsiChar; cdecl;

    libProcessLayout : function (model : PGF_SBMLModel) : PGF_layoutInfo; cdecl;
    libFreeCondorModel : procedure (model : PGF_SBMLModel); cdecl;
    libGetNetwork : function (model : PGF_layoutInfo) : PGF_Network; cdecl;
    libGetNumberOfCompartments : function (network : PGF_Network) : UINT64; cdecl;
    libGetNumberOfUniqueNodes : function (network : PGF_Network) : UINT64; cdecl; // Only master nodes
    libGetNumberOfNodes : function (network : PGF_Network) : UINT64; cdecl;  // Master and alias nodes
    libGetNumberOfReactions : function (network : PGF_Network) : UINT64; cdecl;
    libGetCompartment : function (network : PGF_Network; index : UINT64) : PGF_Compartment; cdecl;
    libNodeGetCompartmant : function (network : PGF_Network; node : PGF_Node) : PGF_Compartment; cdecl;
    libGetUniqueNode : function (network : PGF_Network; index : UINT64) : PGF_Node; cdecl;
    libGetNodeCentroid : procedure (layout : PGF_layoutInfo; nodeId : PAnsiChar; var pts : TGFPoint); cdecl;
    libSetNodeCentroid : procedure (node : PGF_Node; pt : TGFPoint); cdecl;
    libNodeGetCentroid : function (node : PGF_Node) : TGFPoint; cdecl;
    libGetNodeWidth : function (node : PGF_Node) : double; cdecl;
    libGetNodeHeight : function (node : PGF_Node) : double; cdecl;
    libSetNodeWidth : procedure (node : PGF_Node; width : double); cdecl;
    libSetNodeHeight : procedure (node : PGF_Node; height : double); cdecl;

    libGetNodeId : function (node : PGF_Node) : PAnsiChar; cdecl;
    libGetNodeDisplayName : function (node : PGF_Node) : PAnsiChar; cdecl;

    libGetCompartmentId : function (compartment : PGF_Compartment) : PAnsiChar; cdecl;
    libCompartmentGetId : function (compartment : PGF_Compartment) : PAnsiChar; cdecl;

    libGetCompartmentWidth : function (compartment : PGF_Compartment) : double; cdecl;
    libGetCompartmentHeight : function (compartment : PGF_Compartment) : double; cdecl;
    libGetCompartmentMinCorner : function (compartment : PGF_Compartment) : TGFPoint; cdecl;
    libGetCompartmentMaxCorner : function (compartment : PGF_Compartment) : TGFPoint; cdecl;
    libGetCompartmentById : function (network : PGF_Network; id : PAnsiChar) : PGF_Compartment; cdecl;
    libSetDefaultCompartmentId : function (id : PAnsiChar) : Boolean; cdecl;
    libGetDefaultCompartmentId : function : PAnsiChar; cdecl;

    libGetReaction : function (network : PGF_Network; index : integer) : PGF_Reaction; cdecl;
    libGetNumberOfCurves : function (reaction : PGF_Reaction) : integer; cdecl;
    libGetReactionCurve : function (reaction : PGF_Reaction; index : integer) : PGF_Curve; cdecl;
    libGetCurveControlPoints : function (curve : PGF_Curve) : TInternalGFBezier; cdecl;
    libGetRoleOfCurve : function (curve : PGF_Curve; reaction : PGF_Reaction) : TGFSpeciesRole; cdecl;
    libGetReactionCentroid : function (reaction : PGF_Curve) : TGFPoint; cdecl;
    libGetReactionSpecGeti : function (reaction : PGF_Reaction; index : integer) : integer; cdecl;
    libGetReactionGetNumSpec : function (reaction : PGF_Reaction) : integer; cdecl;
    libCurveHasArrowHead : function (curve : PGF_Curve) : integer; cdecl;
    libGetArrowheadVertices : function (curve : PGF_Curve; var n : integer; var gfPoint : TArrayGFPoint) : integer; cdecl;
    libHasArrowHead : function (curve : PGF_Curve) : Integer; cdecl;

    libRandomizeLayout : procedure (layout : PGF_layoutInfo); cdecl;
    libLockNode : function (node: PGF_Node) : integer; cdecl;
    libUnLockNode : function (node: PGF_Node) : integer; cdecl;
    libIsLocked : function (node : PGF_Node) : integer; cdecl;
    libMoveNetworkToFirstQuad : procedure (layout  : PGF_layoutInfo; x_disp, y_disp : double); cdecl;

    libMakeAliasNode : function (node : PGF_Node; network : PGF_Network) : integer; cdecl;
    libNodeIsAliased : function  (node : PGF_Node) : Integer; cdecl;
    libAliasNodeWithDegree : procedure (layout : PGF_layoutInfo; minDegree : integer); cdecl;
    libGetNumAliasInstances	: function (network : PGF_Network; masterNode : PGF_Node) : integer; cdecl;
    libGetAliasNodep : function (network : PGF_Network; masterNode : PGF_Node; index : UInt64) : PGF_Node; cdecl;

    libDoLayoutAlgorithm : procedure (opt : TGF_Options; layout : PGF_layoutInfo); cdecl;
    libGetLayoutOptDefaults : procedure (opt : PGF_Options); cdecl;
    libSetCompartmentMinCorner : procedure (compartment : PGF_Compartment; pt : TGFPoint); cdecl;
    libSetCompartmentMaxCorner : procedure (compartment : PGF_Compartment; pt : TGFPoint); cdecl;
    libFitToWindow : procedure (layout : PGF_layoutInfo; left, top, roght, bottom : double); cdecl;
    libIsLayoutSpecified : function (network : PGF_Network) : integer; cdecl;

    libCreateSBMLModel : function : PGF_SBMLModel; cdecl;
    libCreateLayout : function (level, version : UInt64; width, height : UInt64) : PGF_layoutInfo; cdecl;
    libCreateCompartment : function (network : PGF_Network; id, name : PAnsiChar) : PGF_Compartment; cdecl;
    libCreateNode : function (network : PGF_Network; id, name : PAnsiChar; compartment : PGF_Compartment) : PGF_Node; cdecl;
    libCreateAliasNode : function (network : PGF_Network; sourceNode : PGF_Node) : PGF_Node; cdecl;
    libCreateReaction : function (network : PGF_Network; id, name : PAnsiChar) : PGF_Reaction; cdecl;
    libConnectNode : function (network : PGF_Network; node : PGF_Node; reaction : PGF_Reaction; role : integer): integer; cdecl;
    libFreeModelAndLayout : procedure (sbmlModel : PGF_SBMLModel; layout : PGF_layoutInfo); cdecl;

    libFree : procedure (ptr : pointer); cdecl;
    libStrFree : procedure (ptr : PAnsiChar); cdecl;


function gf_loadSBMLString (value : AnsiString; errMsg : AnsiString) : PGF_SBMLModel;
var str : AnsiString;
     p : PAnsiChar;
begin
  result := nil;
  errMsg := '';
  str := AnsiString (value);
  p := PAnsiChar (str);

  result := libLoadSBMLbuf (p);
  if result = nil then
     errMsg := gf_getLastError;
end;


function  gf_getId (network : PGF_Network) : AnsiString;
var str : AnsiString;
     p : PAnsiChar;
begin
  p := libGetId (network);
  str := AnsiString (p);
  result := str;
end;


function gf_getSBMLWithLayout (model : PGF_SBMLModel; layout : PGF_layoutInfo) : AnsiString;
var p : PAnsiChar;
    str : AnsiString;
begin
  p := libLoadSBMLWithLayout (model, layout);
  str := AnsiString (p);
  result := str;
end;

function gf_renderTikZ (layout : PGF_layoutInfo) : AnsiString;
var p : PAnsiChar;
    str : AnsiString;
begin
  p := libGetTikZ (layout);
  str := AnsiString (p);
  result := str;
end;


function gf_getVersion : AnsiString;
var p : PAnsiChar;
    str : AnsiString;
begin
  p := libGetVersion;
  str := AnsiString (p);
  result := str;
end;


procedure gf_freeModel (currentModel : PGF_SBMLModel);
begin
  libFreeCondorModel (currentModel);
end;

function gf_getLastError : AnsiString;
var p : PAnsiChar;
begin
  p := libGetLastError;
  result := AnsiString (p);
end;

procedure gf_free (ptr : pointer);
begin
  libFree (ptr);
end;

procedure gf_strFree (ptr : PAnsiChar);
begin
  libStrFree (ptr);
end;

function gf_processLayout (currentModel : PGF_SBMLModel) : PGF_layoutInfo;
begin
  result := libProcessLayout (currentModel);
end;

function gf_getNetwork (layout : PGF_layoutInfo) : PGF_Network;
begin
  result := libGetNetwork (layout);
end;

function gf_getNumberOfCompartments (network : PGF_Network) : integer;
begin
  result := libGetNumberOfCompartments (network);
end;

function gf_getCompartment (network : PGF_Network; index : integer) : PGF_Compartment;
begin
  result := libGetCompartment (network, index);
end;

// Alias plus master nodes
function gf_getNumberOfNodes (network : PGF_Network) : integer;
begin
  result := libGetNumberOfNodes (network);
end;

// Just master nodes
function 	gf_getNumberOfMasterNodes (network : PGF_Network) : Integer;  // Only master nodes
begin
  result := libGetNumberOfUniqueNodes (network);
end;


function gf_getMasterNode (network : PGF_Network; index : integer) : PGF_Node;
begin
  result := libGetUniqueNode (network, UINT64 (index));
end;


function gf_getNodeGetCompartment (network : PGF_Network; node : PGF_Node) : PGF_Compartment;
begin
  result := libNodeGetCompartmant (network, node);
end;


function gf_getNumberOfReactions (network : pointer) : integer;
begin
  result := libGetNumberOfReactions (network);
end;

function gf_getReaction (network : PGF_Network; index : integer) : PGF_Reaction;
begin
  result := libGetReaction (network, index);
end;


function gf_getCompartmentId (network : PGF_Network; index : integer) : AnsiString;
var str : AnsiString;
    p : PAnsiChar;
    compartment : PGF_Compartment;
begin
  compartment := libGetCompartment (network, index);
  p := libGetCompartmentId (compartment);
  str := AnsiString (p);
  result := str;
end;

function gf_getCompartmentIdFromCompartment (compartment : PGF_Compartment) : AnsiString;
var str : AnsiString;
    p : PAnsiChar;
begin
   p := libCompartmentGetId (compartment);
   str := AnsiString (p);
   result := str;
end;


function gf_getCompartmentWidth (network : PGF_Network; index : integer) : double;
var compartment : PGF_Compartment;
begin
  compartment := libGetCompartment (network, index);
  result := libGetCompartmentWidth (compartment);
end;


function gf_getCompartmentHeight (network : PGF_Network; index : integer) : double;
var compartment : PGF_Compartment;
begin
  compartment := libGetCompartment (network, index);
  result := libGetCompartmentHeight (compartment);
end;


function gf_getCompartmentMinCorner (network : PGF_Network; index : integer) : TPointF;
var compartment : PGF_Compartment;
    p : TGFPoint;
begin
  compartment := libGetCompartment (network, index);
  p := libGetCompartmentMinCorner (compartment);
  result.x := p.x;
  result.y := p.y;
end;


function gf_getCompartmentMaxCorner (network : PGF_Network;  index : integer) : TPointF;
var compartment : PGF_Compartment;
    p : TGFPoint;
begin
  compartment := libGetCompartment (network, index);
  p := libGetCompartmentMaxCorner (compartment);
  result.x := p.x;
  result.y := p.y;
end;


function  gf_getCompartmentById (network : PGF_Network; id : PAnsiChar) : PGF_Compartment;
begin
  result := libGetCompartmentById (network, id);
end;


function  gf_getDefaultCompartmentId : AnsiString;
var p : PAnsiChar;
    aStr : AnsiString;
begin
  p := libGetDefaultCompartmentId;
  aStr := AnsiString (p);
  result := aStr;
end;

function  gf_setDefaultCompartmentId (id : AnsiString) : Boolean;
var p : PAnsiChar;
begin
  p := PAnsiChar (id);
  libSetDefaultCompartmentId (p);
  result := true;
end;


// ----------------------------------------------------------------------------------------------
function gf_getNodeCentroid (layout : PGF_layoutInfo; nodeId : PAnsiChar) : TPointF;
var  p : TGFPoint;
begin
  libGetNodeCentroid (layout, nodeId, p);
  result.x := p.x; result.y := p.y;
end;

function gf_getNodeCentroid (node : PGF_Node) : TPointF;
var  p : TGFPoint;
begin
  p := libNodeGetCentroid (node);
  result.x := p.x; result.y := p.y;
end;


procedure gf_setNodeCentroid (node : PGF_Node; pt : TPointF);
var ptfab : TGFPoint;
begin
  ptfab.x := pt.X;
  ptfab.y := pt.Y;
  libSetNodeCentroid (node, ptfab);
end;


function gf_getNodeWidth (node : PGF_Node) : double;
begin
  result := libGetNodeWidth (node);
end;

function gf_getNodeHeight (node : PGF_Node) : double;
begin
  result := libGetNodeHeight (node);
end;

procedure gf_setNodeWidth (node : PGF_Node; width : double);
begin
  libSetNodeWidth (node, width);
end;


procedure gf_setNodeHeight (node : PGF_Node; height : double);
begin
  libSetNodeHeight (node, height);
end;

function gf_getNodeId (node : PGF_Node) : AnsiString;
var p : PAnsiChar;
begin
  p := libGetNodeId (node);
  result := AnsiString (p);
  libStrFree (p);
end;

function gf_getNodeDisplayName (node : PGF_Node) : AnsiString;
var p : PAnsiChar;
begin
  p := libGetNodeDisplayName (node);
  result := AnsiString (p);
  libStrFree (p);
end;

//function gf_getCompartmentMinCorner (compartment : PGF_Compartment) : TPointF;
//var  p : TGFPoint;
//begin
//  p := libGetCompartmentMinCorner (compartment);
//  result.X := p.x; result.Y := p.y;
//end;
//
//function gf_getCompartmentMaxCorner (compartment : PGF_Compartment) : TPointF;
//var  p : TGFPoint;
//begin
//  p := libGetCompartmentMaxCorner (compartment);
//  result.X := p.x; result.Y := p.y;
//end;

function gf_getNumberOfCurves (reaction : PGF_Reaction) : integer;
begin
  result := libGetNumberOfCurves (reaction);
end;

function gf_getReactionCurve (reaction : PGF_Reaction; index : integer) : PGF_Curve;
begin
  result := libGetReactionCurve (reaction, index);
end;


function gf_getCurveControlPoints (curve : PGF_Curve) : TGFBezier;
var b : TInternalGFBezier;
begin
  b := libGetCurveControlPoints (curve);
  result.s.x  := b.s.x;   result.s.y  := b.s.y;
  result.c1.x := b.c1.x;  result.c1.y := b.c1.y;
  result.c2.x := b.c2.x;  result.c2.y := b.c2.y;
  result.e.x  := b.e.x;   result.e.y  := b.e.y;
end;

function gf_getCurveRole (curve : PGF_Curve; reaction : PGF_Reaction) : TGFSpeciesRole;
begin
  result := libGetRoleOfCurve (curve, reaction);
end;

function  gf_getReactionCentroid (reaction : PGF_Reaction) : TPointF;
var p : TGFPoint;
begin
  p := libGetReactionCentroid (reaction);
  result.X := p.x;
  result.Y := p.y;
end;


function  gf_getReactionSpecGeti (reaction : PGF_Reaction; index: Integer) : integer;
begin
  result := libGetReactionSpecGeti (reaction, index);
end;


function  gf_reaction_getNumSpec	(reaction : PGF_Reaction) : integer;
begin
  result := libGetReactionGetNumSpec (reaction);
end;

function gf_CurveHasArrowHead  (curve : PGF_Curve) : Boolean;
begin
  result := boolean (libCurveHasArrowHead (curve));
end;

function gf_getArrowVertices (curve : PGF_Curve; var n : integer; var pts : TArrayGFPoint) : integer;
var _n : integer;
    _pts : TArrayGFPoint;
begin
  _n := n;
  _pts := pts;
  result := libGetArrowheadVertices (curve, _n, _pts);
  n := _n;
  pts := _pts;
end;

function gf_hasArrowHead (curve : PGF_Curve) : integer;
begin
  result := libHasArrowHead (curve);
end;

procedure gf_randomizeLayout (layout : PGF_layoutInfo);
begin
  libRandomizeLayout (layout);
end;

procedure gf_lockNode (node : PGF_Node);
begin
  libLockNode (node);
end;


procedure gf_unLockNode (node : PGF_Node);
begin
  libUnLockNode (node);
end;

function gf_isNodeLocked (node : PGF_Node) : boolean;
begin
  result := boolean (libIsLocked (node));
end;

// Alias Node Methods
// -----------------------------------------------------------------------


// Note sure what this one is for
function gf_make_alias_node	(node : PGF_Node; network : PGF_Network) : integer;
begin
   result := libMakeAliasNode (node, network);
end;

function  gf_createAliasNode (network : PGF_Network; sourceNode : PGF_Node) : PGF_Node;
begin
  result := libCreateAliasNode (network, sourceNode);
end;

function  gf_node_isAliased	(node : PGF_Node) : Integer;
begin
  result := libNodeIsAliased (node);
end;

procedure gf_aliasNodeWithDegree (layout : PGF_layoutInfo; minDegree : integer);
begin
  libAliasNodeWithDegree (layout, minDegree);
end;

function  gf_getNumAliasInstances (network : PGF_Network; masterNode : PGF_Node) : integer;
begin
  result := libGetNumAliasInstances (network, masterNode);
end;

function gf_getNumberOfAliasNodes (network : PGF_Network; masterNode : PGF_Node) : integer;
begin
  result := gf_getNumAliasInstances(network, masterNode);
end;

function gf_getAliasNodep (network : PGF_Network; masterNode : PGF_Node; index : integer) : PGF_Node;
begin
   result := libGetAliasNodep (network, masterNode, index);
end;

// -----------------------------------------------------------------------

procedure gf_moveNetworkToFirstQuad	(layout : PGF_layoutInfo; left, top : double);
begin
  libMoveNetworkToFirstQuad (layout, left, top);
end;


procedure gf_computeLayout (opt : TGF_Options; layout : PGF_layoutInfo);
begin
  libDoLayoutAlgorithm (opt, layout);
end;

procedure gf_getLayoutOptDefaults (opt : PGF_Options);
begin
  libGetLayoutOptDefaults (opt);
end;

procedure gf_getLayoutOpts (opt : PGF_Options);
begin
  opt.stiffness := DEFAULT_STIFFNESS;
  opt.gravity := DEFAULT_GRAVITY;
  opt.useBoundary := integer (DEFAULT_USEBOUNDARY);
  opt.useMagnetism := integer (DEFAULT_USEMAGNETISM);
end;


procedure gf_setCompartmentMinCorner (compartment : PGF_Compartment; pt : TPointF);
var cpt : TGFPoint;
begin
  cpt.x := pt.x; cpt.y := pt.y;
  libSetCompartmentMinCorner (compartment, cpt);
end;


procedure gf_setCompartmentMaxCorner (compartment : PGF_Compartment; pt : TPointF);
var cpt : TGFPoint;
begin
  cpt.x := pt.x; cpt.y := pt.y;
  libSetCompartmentMaxCorner (compartment, cpt);
end;

procedure gf_fitToWindow (layout : PGF_layoutInfo; left, top, right, bottom : double);
begin
  libFitToWindow (layout, left, top, right, bottom);
end;


function gf_IsThereALayout (network : PGF_Network) : boolean;
begin
  result := boolean (libIsLayoutSpecified (network));
end;

function  gf_createNewSBMLModel : PGF_SBMLModel;
begin
  result := libCreateSBMLModel;
end;

function  gf_createLayout (level, version : UInt64; width, height : UInt64) : PGF_layoutInfo;
begin
  result := libCreateLayout (level, version, width, height);
end;

function  gf_createCompartment (network : PGF_Network; id, name : PAnsiChar) : PGF_Compartment;
begin
  result := libCreateCompartment (network, id, name);
end;

function  gf_createNode (network : PGF_Network; id, name : PAnsiChar; compartment : PGF_Compartment) : PGF_Node;
begin
  result := libCreateNode (network, id, name, compartment);
end;

function  gf_createReaction (network : PGF_Network; id, name : PAnsiChar) : PGF_Reaction;
begin
  result := libCreateReaction (network, id, name);
end;

function  gf_connectNodeToReaction (network : PGF_Network; node : PGF_Node; reaction : PGF_Reaction; role : TGFSpeciesRole) : Integer;
begin
  result := libConnectNode (network, node, reaction, integer (role));
end;

procedure gf_freeModelAndLayout (sbmlModel : PGF_SBMLModel; layout : PGF_layoutInfo);
begin
  libFreeModelAndLayout (sbmlModel, layout);
end;

// ------------------------------------------------------------------------------

function loadSingleMethod (methodName : AnsiString; var errMsg : string; var success : boolean; methodList : TStringList) : Pointer;
begin
   result := GetProcAddress(dllHandle, PAnsiChar (methodName));
   if not Assigned (result) then
      begin
      errMsg := 'Failed to load method: ' + methodName;
      errMsg := errMsg + sLineBreak + sLineBreak + 'You may have an out of date layout library. Current Version: ' + gf_getVersion;;
      errMsg := errMsg + sLineBreak + 'Error Message Number: ' + inttostr (windows.GetLastError);
      methodList.Add (errMsg);
      success := false;
      end
   else
      methodList.Add (methodName + ': found');
end;


function loadMethods (var errMsg : string; methodList : TStringList) : boolean;
begin
  result := true;
  try
   @libGetVersion              := loadSingleMethod ('gf_getCurrentLibraryVersion', errMsg, result, methodList);
   @libLoadSBMLbuf             := loadSingleMethod ('gf_loadSBMLbuf', errMsg, result, methodList);
   @libLoadSBMLWithLayout      := loadSingleMethod ('gf_getSBMLwithLayoutStr', errMsg, result, methodList);
   @libGetTikZ                 := loadSingleMethod ('gf_renderTikZ', errMsg, result, methodList);
   @libGetId                   := loadSingleMethod ('gf_nw_getId', errMsg, result, methodList);
   @libProcessLayout           := loadSingleMethod ('gf_processLayout', errMsg, result, methodList);
   @libFreeCondorModel         := loadSingleMethod ('gf_freeSBMLModel', errMsg, result, methodList);
   @libGetNetwork              := loadSingleMethod ('gf_getNetworkp', errMsg, result, methodList);
   @libGetNumberOfCompartments := loadSingleMethod ('gf_nw_getNumComps', errMsg, result, methodList);
   @libGetNumberOfUniqueNodes  := loadSingleMethod ('gf_nw_getNumUniqueNodes', errMsg, result, methodList);
   @libGetNumberOfNodes        := loadSingleMethod ('gf_nw_getNumNodes', errMsg, result, methodList);
   @libGetNumberOfReactions    := loadSingleMethod ('gf_nw_getNumRxns', errMsg, result, methodList);

   @libGetCompartment          := loadSingleMethod ('gf_nw_getCompartmentp', errMsg, result, methodList);
   @libGetCompartmentId        := loadSingleMethod ('gf_compartment_getID', errMsg, result, methodList);
   @libCompartmentGetId        := loadSingleMethod ('gf_compartment_getID', errMsg, result, methodList);
   @libGetCompartmentWidth     := loadSingleMethod ('gf_compartment_getWidth', errMsg, result, methodList);
   @libGetCompartmentHeight    := loadSingleMethod ('gf_compartment_getHeight', errMsg, result, methodList);
   @libGetCompartmentMinCorner := loadSingleMethod ('gf_compartment_getMinCorner', errMsg, result, methodList);
   @libGetCompartmentMaxCorner := loadSingleMethod ('gf_compartment_getMaxCorner', errMsg, result, methodList);
   @libGetCompartmentById      := loadSingleMethod ('gf_nw_findCompartmentById', errMsg, result, methodList);
   @libSetDefaultCompartmentId := loadSingleMethod ('gf_setDefaultCompartmentId', errMsg, result, methodList);
   @libGetDefaultCompartmentId := loadSingleMethod ('gf_getDefaultCompartmentId', errMsg, result, methodList);
   @libNodeGetCompartmant      := loadSingleMethod ('gf_nw_nodeGetCompartment', errMsg, result, methodList);

   @libGetUniqueNode           := loadSingleMethod ('gf_nw_getUniqueNodep', errMsg, result, methodList);
   @libGetNodeCentroid         := loadSingleMethod ('gf_getNodeCentroid', errMsg, result, methodList);
   @libSetNodeCentroid         := loadSingleMethod ('gf_node_setCentroid', errMsg, result, methodList);
   @libNodeGetCentroid         := loadSingleMethod ('gf_node_getCentroid', errMsg, result, methodList);
   @libGetNodeWidth            := loadSingleMethod ('gf_node_getWidth', errMsg, result, methodList);
   @libGetNodeHeight           := loadSingleMethod ('gf_node_getHeight', errMsg, result, methodList);

   @libSetNodeWidth            := loadSingleMethod ('gf_node_setWidth', errMsg, result, methodList);
   @libSetNodeHeight           := loadSingleMethod ('gf_node_setHeight', errMsg, result, methodList);

   @libGetNodeId               := loadSingleMethod ('gf_node_getID', errMsg, result, methodList);
   @libGetNodeDisplayName      := loadSingleMethod ('gf_node_getName', errMsg, result, methodList);

   @libGetReaction             := loadSingleMethod ('gf_nw_getRxnp', errMsg, result, methodList);
   @libGetNumberOfCurves       := loadSingleMethod ('gf_reaction_getNumCurves', errMsg, result, methodList);
   @libGetReactionCurve        := loadSingleMethod ('gf_reaction_getCurvep', errMsg, result, methodList);
   @libGetCurveControlPoints   := loadSingleMethod ('gf_getCurveCPs', errMsg, result, methodList);
   @libGetRoleOfCurve          := loadSingleMethod ('gf_curve_getRole', errMsg, result, methodList);
   @libGetReactionCentroid     := loadSingleMethod ('gf_reaction_getCentroid', errMsg, result, methodList);
   @libGetReactionSpecGeti     := loadSingleMethod ('gf_reaction_specGeti', errMsg, result, methodList);
   @libGetReactionGetNumSpec   := loadSingleMethod ('gf_reaction_getNumSpec', errMsg, result, methodList);
   @libCurveHasArrowHead       := loadSingleMethod ('gf_curve_hasArrowhead', errMsg, result, methodList);
   @libGetArrowheadVertices    := loadSingleMethod ('gf_curve_getArrowheadVerts', errMsg, result, methodList);
   @libHasArrowHead            := loadSingleMethod ('gf_curve_hasArrowhead', errMsg, result, methodList);

   @libRandomizeLayout         := loadSingleMethod ('gf_randomizeLayout', errMsg, result, methodList);
   @libLockNode                := loadSingleMethod ('gf_node_lock', errMsg, result, methodList);
   @libUnLockNode              := loadSingleMethod ('gf_node_unlock', errMsg, result, methodList);
   @libIsLocked                := loadSingleMethod ('gf_node_isLocked', errMsg, result, methodList);

   @libDoLayoutAlgorithm       := loadSingleMethod ('gf_doLayoutAlgorithm', errMsg, result, methodList);
   @libGetLayoutOptDefaults    := loadSingleMethod ('gf_getLayoutOptDefaults', errMsg, result, methodList);
   @libSetCompartmentMinCorner := loadSingleMethod ('gf_compartment_setMinCorner', errMsg, result, methodList);
   @libSetCompartmentMaxCorner := loadSingleMethod ('gf_compartment_setMaxCorner', errMsg, result, methodList);
   @libFitToWindow             := loadSingleMethod ('gf_fit_to_window', errMsg, result, methodList);
   @libIsLayoutSpecified       := loadSingleMethod ('gf_nw_isLayoutSpecified', errMsg, result, methodList);
   @libMoveNetworkToFirstQuad  := loadSingleMethod ('gf_moveNetworkToFirstQuad', errMsg, result, methodList);

   @libMakeAliasNode           := loadSingleMethod ('gf_node_make_alias', errMsg, result, methodList);
   @libNodeIsAliased           := loadSingleMethod ('gf_node_isAliased', errMsg, result, methodList);
   @libAliasNodeWithDegree     := loadSingleMethod ('gf_aliasNodebyDegree', errMsg, result, methodList);
   @libGetNumAliasInstances    := loadSingleMethod ('gf_nw_getNumAliasInstances', errMsg, result, methodList);
   @libGetAliasNodep           := loadSingleMethod ('gf_nw_getAliasInstancep', errMsg, result, methodList);

   @libCreateSBMLModel         := loadSingleMethod ('gf_SBMLModel_newp',  errMsg, result, methodList);
   @libCreateLayout            := loadSingleMethod ('gf_layoutInfo_newp',  errMsg, result, methodList);
   @libCreateCompartment       := loadSingleMethod ('gf_nw_newCompartmentp',  errMsg, result, methodList);
   @libCreateNode              := loadSingleMethod ('gf_nw_newNodep',  errMsg, result, methodList);
   @libCreateAliasNode         := loadSingleMethod ('gf_nw_newAliasNodep',  errMsg, result, methodList);
   @libCreateReaction          := loadSingleMethod ('gf_nw_newReactionp',  errMsg, result, methodList);
   @libConnectNode             := loadSingleMethod ('gf_nw_connectNode', errMsg, result, methodList);
   @libFreeModelAndLayout      := loadSingleMethod ('gf_freeModelAndLayout', errMsg, result, methodList);

   @libGetLastError            := loadSingleMethod ('gf_getLastError', errMsg, result, methodList);
   //@libHaveError               := loadSingleMethod ('gf_haveError', errMsg, result, methodList);
   @libFree                    := loadSingleMethod ('gf_free', errMsg, result, methodList);
   @libStrFree                 := loadSingleMethod ('gf_strfree', errMsg, result, methodList);
 except
    on E: Exception do
       begin
       errMsg := e.message;
       result := false;
       exit;
      end;
  end;
end;



function loadlibSBNW (var errMsg : string; methodList : TStringList) : boolean;
var tempString: WideString;
    aString: PChar;
    dir : WideString;
    path : AnsiString;
    a : boolean;
begin
  grapgfabDLLLoaded := false;
  dir := sysutils.GetCurrentDir;
  path := ExtractFilePath (GetModuleName(HInstance)) + libName;
  TDirectory.SetCurrentDirectory (dir);

  if FileExists (path) then
     begin
     //path := ExtractFilePath (GetModuleName(HInstance)) + 'libSBML.dll';
     tempString := WideString (path);
     DllHandle := LoadLibrary (PWideChar(tempString));

     if DllHandle <> 0 then
         begin
         if loadMethods (errMsg, methodList) then
            begin
            grapgfabDLLLoaded := True;
            result := true;
            end
         else
            begin
            //errMsg := errMsg + sLineBreak + sLineBreak + 'You have an out of date layout library. Current Version: ' + gf_getVersion;
            grapgfabDLLLoaded := False;
            result := false;
            end;
         end
     else
         begin
         errMsg := SysErrorMessage(Windows.GetLastError);
         grapgfabDLLLoaded := False;
         errMsg := 'Failed to load autolayout library at: [' + ExtractFilePath (path) + ']: ' + errMsg;
         end;
     end
  else
     begin
     grapgfabDLLLoaded := False;
     errMsg := 'Unable to locate autolayout library [' + libName + '] at: [' + ExtractFilePath (path) + ']';
     end;
end;


procedure releaseSBNWLibrary;
begin
  if grapgfabDLLLoaded then
     begin
     grapgfabDLLLoaded := false;
     freeLibrary (DllHandle);
     end;
end;

end.
