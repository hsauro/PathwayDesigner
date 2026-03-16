unit uSBMLLayout;

interface

Uses SysUtils, Classes, uLibSBNW, System.Types;

type
   TBezierPoints = record
      startPt : TPointF;
      h1, h2 : TPointF;
      endPt : TPointF;
   end;

   TSBMLLayout = class (TObject)
     private
        sbmlStr : string;
        methodList: TStringList;

        currentModel : PGF_SBMLModel;
        layoutInfo : PGF_layoutInfo;
        network : PGF_Network;
        FnCompartments, FnNodes, FnReactions : integer;

        function getMasterNodePtr (nodeId : string) : PGF_Node;
     public
       options : TGF_Options;
       loaded : boolean;

      function    loadSBML (sbmlStr : string) : string;
      function    loadSBMLFromFile (fileName : string) : string;
      function    getSBMLId : string;
      procedure   layoutNetwork;
      procedure   updateLayout;
      procedure   randomizeNetwork;
      function    getNumberOfCompartments : integer;
      function    getNumberOfMasterNodes : integer; // Master nodes only
      function    getTotalNumberOfNodes : integer;      // Master and alias nodes
      function    getNumberOfReactions : integer;
      function    getNumberOfCurves (iReaction : integer) : integer;

      function    getCompartmentId (index : integer) : string;
      function    getCompartmentWidth (index : integer) : double;
      function    getCompartmentHeight (index : integer) : double;
      function    getCompartmentTopLeftCorner (index : Integer) : TPointF;
      function    getCompartmentBottonRightCorner (index : Integer) : TPointF;
      function    getDefaultCompartmentId : AnsiString;
      function    setDefaultCompartmentId (id : AnsiString) : Boolean;
      function    getCompartmentIdOfNode (nodeIndex : integer) : AnsiString;
      function    getCompartmentVolume (compartmentIndex : integer) : double;

      function    getMasterNodeCentroid (index : integer) : TPointF; overload;
      procedure   setMasterNodeCentroid (index : integer; pt : TPointF);
      function    getMasterNodeCentroid (nodeId : string) : TPointF;  overload;
      function    getMasterNodeWidth (index : integer) : double;
      function    getMasterNodeHeight (index : integer) : double;
      function    getNodeRectangle (index : integer) : TRectF; overload;
      function    getNodeRectangle (nodeId : string) : TRectF; overload;
      procedure   setNodeWidth (nodeIndex : integer; width : double);
      procedure   setNodeHeight (nodeIndex : integer; height : double);

      function    getNodeId (index : integer) : string;
      function    getNodeIndex (nodeId : string) : integer;
      function    getNodeDisplayName (index : integer) : string;

      function    getBezierCoords (iReaction, iCurve : integer) : TBezierPoints;
      function    getRoleOfCurve (iReaction, iCurve : integer) : TGFSpeciesRole;
      function    getReactionCentroid (iReaction : integer) : TPointF;
      function    getArrowHeadVertices (iReaction, iCurve : integer) : TArrayGFPoint;
      function    hasArrowHead (iReaction, iCurve : integer) : Boolean;
      function    getNumberOfReactants (iReaction : integer) : integer;
      function    getNumberOfProducts (iReaction : integer) : integer;
      function    getReactionSpecGetI (iReaction, index : Integer) : Integer;
      function    getReactionGetNumSpec (iReaction : integer) : Integer;

      procedure   lockNode (index : integer);
      procedure   unLockNode (index : integer);
      function    IsNodeLocked (index : integer) : boolean;
      function    makeAliasNode (index : Integer) : boolean;
      function    isNodeAnAlias (index : integer) : boolean;
      procedure   createAliasNodesWithDegree (minDegree : integer);
      function    getAliasCentroid (nodeIndex, aliasIndex : integer) : TPointF;

      procedure   fitToWindow (rect : TRectF);
      function    IsThereALayout : boolean;
      function    getSBMLLayoutString : string;
      function    getTiKZFormat : string;
      function    saveTikZToFile (fileName : string) : string;

      procedure   setStiffness (stiffness : double);
      procedure   setGravity (gravity : double);
      procedure   useMagnetism (magnatism : boolean);
      procedure   setDefaultOptions;
      function    getVersion : AnsiString;
      procedure   moveToFirstQuadrant (x, y : Double);

      function    createSBMLMModel (level, version, width, height : UInt64) : Boolean;
      function    createCompartment (id : AnsiString) : boolean;
      function    createNode (id : AnsiString; compartmentId : AnsiString) : boolean;
      function    createAliasNode (id : AnsiString) : boolean;
      function    createReaction (id : AnsiString; reactantIds, productIds : array of AnsiString) : boolean;


//function  gf_createCompartment (network : PGF_Network; id, name : PAnsiChar) : PGF_Compartment;
//function  gf_createNode (network : PGF_Network; id, name : PAnsiChar; compartment : PGF_Compartment) : PGF_Node;
//function  gf_createAliasNode (network : PGF_Network; id, name : PAnsiChar; sourceNode : PGF_Node) : PGF_Node;
//function  gf_createReaction (network : PGF_Network; id, name : PAnsiChar) : PGF_Reaction;
//function  gf_connectNodeToReaction (network : PGF_Network; reaction : PGF_Reaction; role : TGFSpeciesRole) : Integer;


      constructor Create (sbmlStr : string); overload;
      constructor Create; overload;

      property    nNodes : integer read FnNodes;
      property    nReactions : integer read FnReactions;
      property    nCompartments : integer read FnCompartments;
   end;

implementation

Uses IOUtils;

constructor TSBMLLayout.Create (sbmlStr : string);
var errMsg : string;
begin
  loaded := false;
  self.sbmlStr := sbmlStr;
  methodList := TStringList.Create;
  if not loadlibSBNW (errMsg, methodList) then
     raise Exception.Create (errMsg);
end;


constructor TSBMLLayout.Create;
var errMsg : string;
begin
  loaded := false;
  methodList := TStringList.Create;
  if not loadlibSBNW (errMsg, methodList) then
     raise Exception.Create (errMsg);
  gf_getLayoutOptDefaults(@options);
  options.prerandomize := 0;
  options.stiffness := uLibSBNW.DEFAULT_STIFFNESS;
  currentModel := nil;
end;


function TSBMLLayout.loadSBML (sbmlStr : string) : string;
begin
  loaded := true;
  self.sbmlStr := sbmlStr;
  currentModel := gf_loadSBMLString (sbmlStr, result);
  if currentModel = nil then
     begin
     loaded := false;
     result := gf_getLastError;
     exit;
     end;
  layoutInfo := gf_processLayout (currentModel);
  network := gf_getNetwork (layoutInfo);
  FnCompartments := getNumberOfCompartments;
  FnNodes := getNumberOfMasterNodes;
  FnReactions := getNumberOfReactions;
  FnCompartments := getNumberOfCompartments;
end;

function TSBMLLayout.loadSBMLFromFile (fileName : string) : string;
var str : string;
begin
  if FileExists (fileName) then
     begin
     str := TFile.ReadAllText(fileName);
     result := loadSBML (str);
     end
  else
     result := 'Unable to locate file: ' + fileName;
end;

function TSBMLLayout.getSBMLId : string;
begin
  result := gf_getId (network);
end;



procedure TSBMLLayout.updateLayout;
begin
  gf_computeLayout (options, layoutInfo);
 //network := gf_getNetwork (layoutInfo);
end;


procedure TSBMLLayout.randomizeNetwork;
begin
  if layoutInfo <> nil then
     gf_randomizeLayout(layoutInfo);
end;


procedure TSBMLLayout.setDefaultOptions;
begin
  options.stiffness := 25;
  options.gravity := 15;
  options.useMagnetism := integer (False);
  options.useBoundary := integer (False);
end;


procedure TSBMLLayout.layoutNetwork;
begin
  //gf_randomizeLayout(layoutInfo);
  gf_computeLayout (options, layoutInfo);
end;


function TSBMLLayout.getNumberOfCompartments : integer;
begin
  FnCompartments := gf_getNumberOfCompartments (network);
  result := FnCompartments;
end;


function TSBMLLayout.getTotalNumberOfNodes : integer;
begin
  FnNodes := gf_getNumberOfNodes(network);
  result := FnNodes;
end;

function TSBMLLayout.getNumberOfMasterNodes : integer;
begin
  FnNodes := gf_getNumberOfMasterNodes(network);
  result := FnNodes;
end;


function TSBMLLayout.getNumberOfReactions : integer;
begin
  FnReactions := gf_getNumberOfReactions(network);
  result := FnReactions;
end;


function TSBMLLayout.getNumberOfCurves (iReaction : integer) : integer;
var reaction : PGF_Reaction;
begin
  reaction := gf_getReaction(network, iReaction);
  result := gf_getNumberOfCurves (reaction);
end;


function TSBMLLayout.getCompartmentId (index : Integer) : string;
begin
  result := gf_getCompartmentId (network, index);
end;


function TSBMLLayout.getCompartmentWidth (index : integer) : double;
begin
  result := gf_getCompartmentWidth (network, index);
end;


function TSBMLLayout.getCompartmentHeight (index : integer) : double;
begin
  result := gf_getCompartmentHeight (network, index);
end;


function TSBMLLayout.getCompartmentTopLeftCorner (index : Integer) : TPointF;
begin
  result := gf_getCompartmentMinCorner(network, index);
end;

function TSBMLLayout.getCompartmentBottonRightCorner (index : Integer) : TPointF;
begin
  result := gf_getCompartmentMaxCorner(network, index);
end;


function TSBMLLayout.getDefaultCompartmentId : AnsiString;
begin
  result := gf_getDefaultCompartmentId;
end;


function TSBMLLayout.setDefaultCompartmentId (id: AnsiString) : Boolean;
begin
  result := gf_setDefaultCompartmentId (id);
end;


function TSBMLLayout.getCompartmentIdOfNode (nodeIndex : integer) : AnsiString;
var c : PGF_Compartment;
    node : PGF_Node;
begin
  node := gf_getMasterNode (network, nodeIndex);
  c := gf_getNodeGetCompartment (network, node);
  result := gf_getCompartmentIdFromCompartment (c);
end;


function TSBMLLayout.getCompartmentVolume (compartmentIndex : integer) : double;
var c : PGF_Compartment;
begin
  c := gf_getCompartment (network, compartmentIndex);
  // No method to currently get volume
  // result := gf_CompartmentVolume (c);
  result := 1.0;
end;

function TSBMLLayout.getMasterNodeCentroid (index : integer) : TPointF;
var node : PGF_Node;
begin
  node := gf_getMasterNode (network, index);
  result := gf_getNodeCentroid (node);
end;


function TSBMLLayout.getMasterNodeCentroid(nodeId : string) : TPointF;
var node : PGF_Node;
begin
  node := getMasterNodePtr(nodeId);
  if node <> nil then
     result := gf_getNodeCentroid (node)
  else
     raise Exception.Create ('Unable to locate node: ' + nodeId);
end;


procedure TSBMLLayout.setMasterNodeCentroid (index : integer; pt : TPointF);
var node : PGF_Node;
begin
  node := gf_getMasterNode (network, index);
  gf_setNodeCentroid (node, pt);
end;


function TSBMLLayout.getBezierCoords (iReaction, iCurve : integer) : TBezierPoints;
var reaction : PGF_Reaction;
    curve : PGF_Curve;
    tmp : TGFBezier;
begin
  reaction := gf_getReaction(network, iReaction);
  curve := gf_getReactionCurve (reaction, iCurve);
  tmp := gf_getCurveControlPoints (curve);
  result.startPt.x  := tmp.s.x;  result.startPt.y  := tmp.s.y;
  result.h1.x := tmp.c1.x;       result.h1.y := tmp.c1.y;
  result.h2.x := tmp.c2.x;       result.h2.y := tmp.c2.y;
  result.endPt.x  := tmp.e.x;    result.endPt.y  := tmp.e.y;
end;


function TSBMLLayout.getRoleOfCurve (iReaction, iCurve : integer) : TGFSpeciesRole;
var reaction : PGF_Reaction;
    curve : PGF_Curve;
begin
  reaction := gf_getReaction(network, iReaction);
  curve := gf_getReactionCurve (reaction, iCurve);
  result := gf_getCurveRole(curve, reaction);
end;


function  TSBMLLayout.getReactionCentroid (iReaction : Integer) : TPointF;
var reaction : PGF_Reaction;
begin
  reaction := gf_getReaction(network, iReaction);
  result := gf_getReactionCentroid (reaction);
end;


function TSBMLLayout.getNumberOfReactants (iReaction : integer) : integer;
var nCurves, i : integer;
begin
  result := 0;
  nCurves := getNumberOfCurves (iReaction);
  for i := 0 to nCurves - 1 do
      if (getRoleOfCurve (iReaction, i) = TGFSpeciesRole.rSubstrate) or
         (getRoleOfCurve (iReaction, i) = TGFSpeciesRole.rSideSubstrate) then
         inc (Result);
end;


function TSBMLLayout.getNumberOfProducts (iReaction : integer) : integer;
var nCurves, i : integer;
begin
  result := 0;
  nCurves := getNumberOfCurves (iReaction);
  for i := 0 to nCurves - 1 do
      if (getRoleOfCurve (iReaction, i) = TGFSpeciesRole.rProduct) or
         (getRoleOfCurve (iReaction, i) = TGFSpeciesRole.rSideProduct) then
         inc (Result);
end;


function TSBMLLayout.getReactionSpecGetI (iReaction, index : Integer) : Integer;
var reaction : PGF_Reaction;
begin
  result := -1;
  reaction := gf_getReaction(network, iReaction);
  result := gf_getReactionSpecGeti(reaction, index);
end;

function TSBMLLayout.getReactionGetNumSpec (iReaction : integer) : Integer;
var reaction : PGF_Reaction;
begin
  result := -1;
  reaction := gf_getReaction(network, iReaction);
  result := gf_reaction_getNumSpec(reaction);
end;


function TSBMLLayout.getArrowHeadVertices (iReaction, iCurve : integer) : TArrayGFPoint;
var reaction : PGF_Reaction;
    i : integer;
    curve : PGF_Curve;
    nCurves : integer;
    pts : TArrayGFPoint;
begin
  reaction := gf_getReaction(network, iReaction);
  curve := gf_getReactionCurve (reaction, iCurve);
  gf_getArrowVertices (curve, nCurves, pts);
  setLength (result, nCurves);
  for i := 0 to nCurves - 1 do
      result[i] := pts[i];
end;

function TSBMLLayout.hasArrowHead (iReaction, iCurve : integer) : Boolean;
var curve : PGF_Curve;
    reaction : PGF_Reaction;
begin
  reaction := gf_getReaction(network, iReaction);
  curve := gf_getReactionCurve (reaction, iCurve);
  result := boolean (gf_hasArrowHead(curve));
end;


function TSBMLLayout.getMasterNodeWidth (index : integer) : double;
var node : PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  result := gf_getNodeWidth(node);
end;


function TSBMLLayout.getMasterNodeHeight (index : integer) : double;
var node : PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  result := gf_getNodeHeight(node);
end;

function TSBMLLayout.getNodeRectangle (nodeId : string) : TRectF;
var pt : TPointF;
    w, h : single;
    aStr : AnsiString;
    index : integer;
    nodePtr : PGF_Node;
begin
  aStr := AnsiString (nodeId);
  nodePtr := getMasterNodePtr(aStr);

  pt := gf_getNodeCentroid (nodePtr);

  index := getNodeIndex (nodeId);
  w := getMasterNodeWidth (index);
  h := getMasterNodeHeight (index);
  result.Left := pt.X - w/2;
  result.Top := pt.Y - h/2;
  result.Right := pt.X + w/2;
  result.Bottom := pt.Y + h/2;
end;

function TSBMLLayout.getNodeRectangle (index : integer) : TRectF;
var pt : TPointF;
    w, h : single;
    aStr : AnsiString;
begin
  aStr := getNodeId (index);
  pt := gf_getNodeCentroid (layoutInfo, PAnsiChar (aStr));

  w := getMasterNodeWidth (index);
  h := getMasterNodeHeight (index);
  result.Left := pt.X - w/2;
  result.Top := pt.Y - h/2;
  result.Right := pt.X + w/2;
  result.Bottom := pt.Y + h/2;
end;


procedure TSBMLLayout.setNodeWidth (nodeIndex : integer; width : double);
begin
  gf_setNodeWidth (gf_getMasterNode (network, nodeIndex), width);
end;

procedure TSBMLLayout.setNodeHeight (nodeIndex : integer; height : double);
begin
  gf_setNodeHeight (gf_getMasterNode (network, nodeIndex), height);
end;


function TSBMLLayout.getNodeId (index : integer) : string;
begin
  result := gf_getNodeId(gf_getMasterNode (network, index));
end;


function TSBMLLayout.getNodeIndex (nodeId : string) : integer;
var i : integer; n : integer;
    aStr : AnsiString;
begin
  n := getNumberOfMasterNodes;
  for i := 0 to n - 1 do
      begin
      aStr := getNodeId (i);
      if aStr = nodeId then
         begin
         exit (i);
         end;
      end;
  raise Exception.Create ('Unable to locate node: ' + nodeId + ' in network');
end;


function TSBMLLayout.getMasterNodePtr (nodeId : string) : PGF_Node;
var i : integer; n : integer;
    aStr : AnsiString;
begin
  n := getNumberOfMasterNodes;
  for i := 0 to n - 1 do
      begin
      aStr := getNodeId (i);
      if aStr = nodeId then
         begin
         exit (gf_getMasterNode (network, i));
         end;
      end;
  raise Exception.Create ('Unable to locate node: ' + nodeId + ' in network');
end;

function TSBMLLayout.getNodeDisplayName (index : integer) : string;
begin
  result := gf_getNodeDisplayName(gf_getMasterNode (network, index));
end;


procedure TSBMLLayout.lockNode (index : integer);
var node :PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  gf_lockNode (node);
end;


procedure TSBMLLayout.unLockNode (index : integer);
var node :PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  gf_unLockNode(node);
end;


function TSBMLLayout.IsNodeLocked (index : integer) : boolean;
var node :PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  result := gf_isNodeLocked(node);
end;


function TSBMLLayout.makeAliasNode (index : Integer) : boolean;
var node :PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  result := not boolean (gf_createAliasNode (network, node));
end;


function TSBMLLayout.isNodeAnAlias (index : integer) : boolean;
var node :PGF_Node;
begin
  node := gf_getMasterNode(network, index);
  result := boolean (gf_node_isAliased(node));
end;


procedure TSBMLLayout.createAliasNodesWithDegree (minDegree : integer);
begin
  gf_aliasNodeWithDegree (layoutInfo, minDegree);
end;


function TSBMLLayout.getAliasCentroid (nodeIndex, aliasIndex : integer) : TPointF;
var masterNode, aliasNode : PGF_Node;
begin
  masterNode := gf_getMasterNode(network, nodeIndex);
  aliasNode := gf_getAliasNodep(network, masterNode, aliasIndex);
  result := gf_getNodeCentroid (aliasNode);
end;

procedure TSBMLLayout.fitToWindow (rect : TRectF);
begin
  gf_fitToWindow(layoutInfo, rect.Left, rect.Top, rect.Right, rect.Bottom);
  network := gf_getNetwork (layoutInfo);
end;


function TSBMLLayout.getSBMLLayoutString : string;
begin
  if (currentModel <> nil) and (layoutInfo <> nil) then
     result := gf_getSBMLWithLayout (currentModel, layoutInfo);
end;

function TSBMLLayout.getTiKZFormat : string;
begin
  result := gf_renderTikZ (layoutInfo);
end;

function TSBMLLayout.saveTikZToFile (fileName : string) : string;
begin
  try
    TFile.WriteAllText (fileName, getTiKZFormat);
  except
    on e:Exception do
       result := e.message;
  end;
end;


procedure TSBMLLayout.setstiffness (stiffness : double);
begin
  options.stiffness := stiffness;
  //gf_computeLayout (options, layoutInfo);
  //network := gf_getNetwork (layoutInfo);
end;


procedure TSBMLLayout.setGravity (gravity : double);
begin
  options.gravity := gravity;
  gf_computeLayout (options, layoutInfo);
  network := gf_getNetwork (layoutInfo);
end;


procedure TSBMLLayout.useMagnetism (magnatism : boolean);
begin
  options.useMagnetism := integer (magnatism);
  gf_computeLayout (options, layoutInfo);
  network := gf_getNetwork (layoutInfo);
end;

function TSBMLLayout.IsThereALayout : boolean;
begin
  result := gf_IsThereALayout(network);
end;


function TSBMLLayout.getVersion : AnsiString;
begin
  result := gf_getVersion;
end;


procedure TSBMLLayout.moveToFirstQuadrant (x, y : Double);
begin
  gf_moveNetworkToFirstQuad (layoutInfo, x, y);
end;


function TSBMLLayout.createSBMLMModel (level, version, width, height : UInt64) : Boolean;
begin
  result := true;
  if currentModel <> nil then
     gf_freeModelAndLayout (currentModel, layoutInfo);
  currentModel :=  gf_createNewSBMLModel;
  if currentModel = nil then
     exit (false);

  layoutInfo := gf_createLayout (level, version, width, height);
  network := gf_getNetwork (layoutInfo);
end;


function TSBMLLayout.createCompartment (id : AnsiString) : Boolean;
begin
  result := true;
  if gf_createCompartment(network, PAnsiChar (id), PAnsiChar (id)) = nil then
     exit (false);
end;


function TSBMLLayout.createNode (id : AnsiString; compartmentId : AnsiString) : Boolean;
var compartmentPtr : PGF_Compartment;
    index : integer;
    node : PGF_Node;
begin
  result := true;
  if compartmentId = '' then
     begin
     node := gf_createNode (network, PAnsiChar (id), PAnsiChar (id), nil);
     end
  else
     begin
     compartmentPtr := gf_getCompartmentById (network, PAnsiChar (compartmentId));
     gf_createNode (network, PAnsiChar (id), PAnsiChar (id), compartmentPtr);
     end;
end;


function TSBMLLayout.createAliasNode (id : AnsiString) : Boolean;
var sourceNode : PGF_Node;
begin
  result := true;
  sourceNode := getMasterNodePtr (id);
  if gf_createAliasNode (network , sourceNode) = nil then
     exit (false);
end;


function TSBMLLayout.createReaction (id : AnsiString; reactantIds, productIds : array of AnsiString) : Boolean;
var nr, np, i : integer;
    reaction : PGF_Reaction;
    node : PGF_Node;
    n : integer;
begin
  result := true;
  reaction := gf_createReaction (network, PAnsiChar (id), PAnsiChar (id));
  if reaction = nil then
     exit (false);

  nr := length (reactantIds);
  np := length (productIds);
  for i := 0 to nr - 1 do
      begin
      node := getMasterNodePtr(reactantIds[i]);
      gf_connectNodeToReaction (network, node, reaction, TGFSpeciesRole.rSubstrate);
      end;

  for i := 0 to np - 1 do
      begin
      node := getMasterNodePtr(productIds[i]);
      gf_connectNodeToReaction (network, node, reaction, TGFSpeciesRole.rProduct);
      end;
end;


end.
