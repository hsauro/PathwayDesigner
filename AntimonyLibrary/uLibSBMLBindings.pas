unit uLibSBMLBindings;

{
  Basic Delphi Object Pascal bindings for libSBML
  Covers core functionality for creating SBML documents, compartments, species, reactions, and parameters
  
  Requirements:
  - libsbml.dll (or libsbml.so on Linux, libsbml.dylib on macOS)
  - Appropriate XML parser library (libxml2, expat, or xerces)
  
  Usage:
  1. Ensure libsbml library is in your system PATH or application directory
  2. Include this unit in your uses clause
  3. Call SBMLDocument_create to start working with SBML
}

interface

uses
  Windows, SysUtils;

const
  // Change to appropriate library name for your platform
  // This path will be relative to the executable!
  // You MUST have bin in the executable directory.
  LIBSBML_DLL = '.\bin\libsbml.dll';

type
  // Opaque pointer types for libSBML objects
  PSBMLDocument = Pointer;
  PModel = Pointer;
  PCompartment = Pointer;
  PSpecies = Pointer;
  PReaction = Pointer;
  PSpeciesReference = Pointer;
  PListOfCompartments = Pointer;
  PListOfSpecies = Pointer;
  PListOfReactions = Pointer;
  PListOfSpeciesReferences = Pointer;
  PKineticLaw = Pointer;
  PParameter = Pointer;
  PListOfParameters = Pointer;

// ============================================================================
// Basic Information about libsbml
// ============================================================================

function getLibSBMLDottedVersion : PAnsiChar; cdecl; external LIBSBML_DLL;

// ============================================================================
// Document and Model Management
// ============================================================================

                // Create and destroy SBML documents
function SBMLDocument_create(level, version: Integer): PSBMLDocument; cdecl; external LIBSBML_DLL;
procedure SBMLDocument_free(document: PSBMLDocument); cdecl; external LIBSBML_DLL;

// Model access
function SBMLDocument_getModel(document: PSBMLDocument): PModel; cdecl; external LIBSBML_DLL;
function SBMLDocument_createModel(document: PSBMLDocument): PModel; cdecl; external LIBSBML_DLL;
function Model_setId(model: PModel; const id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Model_getId(model: PModel): PAnsiChar; cdecl; external LIBSBML_DLL;
function Model_setName(model: PModel; name: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Model_getName(model: PModel): PAnsiChar; cdecl; external LIBSBML_DLL;
function SBMLDocument_getVersion : LongWord; cdecl; external LIBSBML_DLL;

// Document I/O
function writeSBMLToFile(document: PSBMLDocument; filename: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function readSBMLFromFile(filename: PAnsiChar): PSBMLDocument; cdecl; external LIBSBML_DLL;
function writeSBMLToString(document: PSBMLDocument): PAnsiChar; cdecl; external LIBSBML_DLL;
function readSBMLFromString(xml: PAnsiChar): PSBMLDocument; cdecl; external LIBSBML_DLL;

// ============================================================================
// Compartment Management
// ============================================================================

// Get compartment list
function Model_getListOfCompartments(model: PModel): PListOfCompartments; cdecl; external LIBSBML_DLL;
function Model_getNumCompartments(model: PModel): Cardinal; cdecl; external LIBSBML_DLL;
function Model_getCompartment(model: PModel; index: Cardinal): PCompartment; cdecl; external LIBSBML_DLL;
function Model_getCompartmentById(model: PModel; id: PAnsiChar): PCompartment; cdecl; external LIBSBML_DLL;

// Create compartments
function Model_createCompartment(model: PModel): PCompartment; cdecl; external LIBSBML_DLL;
function Model_removeCompartment(model: PModel; index: Cardinal): PCompartment; cdecl; external LIBSBML_DLL;

// Compartment properties
function Compartment_setId(compartment: PCompartment; id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Compartment_getId(compartment: PCompartment): PAnsiChar; cdecl; external LIBSBML_DLL;
function Compartment_setName(compartment: PCompartment; name: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Compartment_getName(compartment: PCompartment): PAnsiChar; cdecl; external LIBSBML_DLL;
function Compartment_setSpatialDimensions(compartment: PCompartment; dimensions: Cardinal): Integer; cdecl; external LIBSBML_DLL;
function Compartment_getSpatialDimensions(compartment: PCompartment): Cardinal; cdecl; external LIBSBML_DLL;
function Compartment_setSize(compartment: PCompartment; size: Double): Integer; cdecl; external LIBSBML_DLL;
function Compartment_getSize(compartment: PCompartment): Double; cdecl; external LIBSBML_DLL;
function Compartment_setConstant(compartment: PCompartment; constant: Integer): Integer; cdecl; external LIBSBML_DLL;
function Compartment_getConstant(compartment: PCompartment): Integer; cdecl; external LIBSBML_DLL;

// ============================================================================
// Species Management
// ============================================================================

// Get species list
function Model_getListOfSpecies(model: PModel): PListOfSpecies; cdecl; external LIBSBML_DLL;
function Model_getNumSpecies(model: PModel): Cardinal; cdecl; external LIBSBML_DLL;
function Model_getSpecies(model: PModel; index: Cardinal): PSpecies; cdecl; external LIBSBML_DLL;
function Model_getSpeciesById(model: PModel; id: PAnsiChar): PSpecies; cdecl; external LIBSBML_DLL;

// Create species
function Model_createSpecies(model: PModel): PSpecies; cdecl; external LIBSBML_DLL;
function Model_removeSpecies(model: PModel; index: Cardinal): PSpecies; cdecl; external LIBSBML_DLL;

// Species properties
function Species_setId(species: PSpecies; id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Species_getId(species: PSpecies): PAnsiChar; cdecl; external LIBSBML_DLL;
function Species_setName(species: PSpecies; name: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Species_getName(species: PSpecies): PAnsiChar; cdecl; external LIBSBML_DLL;
function Species_setCompartment(species: PSpecies; compartment_id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Species_getCompartment(species: PSpecies): PAnsiChar; cdecl; external LIBSBML_DLL;
function Species_setInitialAmount(species: PSpecies; amount: Double): Integer; cdecl; external LIBSBML_DLL;
function Species_getInitialAmount(species: PSpecies): Double; cdecl; external LIBSBML_DLL;
function Species_setInitialConcentration(species: PSpecies; concentration: Double): Integer; cdecl; external LIBSBML_DLL;
function Species_getInitialConcentration(species: PSpecies): Double; cdecl; external LIBSBML_DLL;
function Species_setHasOnlySubstanceUnits(species: PSpecies; hasOnly: Integer): Integer; cdecl; external LIBSBML_DLL;
function Species_getHasOnlySubstanceUnits(species: PSpecies): Integer; cdecl; external LIBSBML_DLL;
function Species_setBoundaryCondition(species: PSpecies; boundary: Integer): Integer; cdecl; external LIBSBML_DLL;
function Species_getBoundaryCondition(species: PSpecies): Integer; cdecl; external LIBSBML_DLL;
function Species_setConstant(species: PSpecies; constant: Integer): Integer; cdecl; external LIBSBML_DLL;
function Species_getConstant(species: PSpecies): Integer; cdecl; external LIBSBML_DLL;

// ============================================================================
// Parameter Management
// ============================================================================

// Get parameter list
function Model_getListOfParameters(model: PModel): PListOfParameters; cdecl; external LIBSBML_DLL;
function Model_getNumParameters(model: PModel): Cardinal; cdecl; external LIBSBML_DLL;
function Model_getParameter(model: PModel; index: Cardinal): PParameter; cdecl; external LIBSBML_DLL;
function Model_getParameterById(model: PModel; id: PAnsiChar): PParameter; cdecl; external LIBSBML_DLL;

// Create parameters
function Model_createParameter(model: PModel): PParameter; cdecl; external LIBSBML_DLL;
function Model_removeParameter(model: PModel; index: Cardinal): PParameter; cdecl; external LIBSBML_DLL;

// Parameter properties
function Parameter_setId(parameter: PParameter; id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Parameter_getId(parameter: PParameter): PAnsiChar; cdecl; external LIBSBML_DLL;
function Parameter_setName(parameter: PParameter; name: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Parameter_getName(parameter: PParameter): PAnsiChar; cdecl; external LIBSBML_DLL;
function Parameter_setValue(parameter: PParameter; value: Double): Integer; cdecl; external LIBSBML_DLL;
function Parameter_getValue(parameter: PParameter): Double; cdecl; external LIBSBML_DLL;
function Parameter_setUnits(parameter: PParameter; units: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Parameter_getUnits(parameter: PParameter): PAnsiChar; cdecl; external LIBSBML_DLL;
function Parameter_setConstant(parameter: PParameter; constant: Integer): Integer; cdecl; external LIBSBML_DLL;
function Parameter_getConstant(parameter: PParameter): Integer; cdecl; external LIBSBML_DLL;

// Kinetic Law Parameters
function KineticLaw_getListOfParameters(kineticLaw: PKineticLaw): PListOfParameters; cdecl; external LIBSBML_DLL;
function KineticLaw_getNumParameters(kineticLaw: PKineticLaw): Cardinal; cdecl; external LIBSBML_DLL;
function KineticLaw_getParameter(kineticLaw: PKineticLaw; index: Cardinal): PParameter; cdecl; external LIBSBML_DLL;
function KineticLaw_getParameterById(kineticLaw: PKineticLaw; id: PAnsiChar): PParameter; cdecl; external LIBSBML_DLL;
function KineticLaw_createParameter(kineticLaw: PKineticLaw): PParameter; cdecl; external LIBSBML_DLL;
function KineticLaw_removeParameter(kineticLaw: PKineticLaw; index: Cardinal): PParameter; cdecl; external LIBSBML_DLL;

// ============================================================================
// Reaction Management
// ============================================================================

// Get reaction list
function Model_getListOfReactions(model: PModel): PListOfReactions; cdecl; external LIBSBML_DLL;
function Model_getNumReactions(model: PModel): Cardinal; cdecl; external LIBSBML_DLL;
function Model_getReaction(model: PModel; index: Cardinal): PReaction; cdecl; external LIBSBML_DLL;
function Model_getReactionById(model: PModel; id: PAnsiChar): PReaction; cdecl; external LIBSBML_DLL;

// Create reactions
function Model_createReaction(model: PModel): PReaction; cdecl; external LIBSBML_DLL;
function Model_removeReaction(model: PModel; index: Cardinal): PReaction; cdecl; external LIBSBML_DLL;

// Reaction properties
function Reaction_setId(reaction: PReaction; id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Reaction_getId(reaction: PReaction): PAnsiChar; cdecl; external LIBSBML_DLL;
function Reaction_setName(reaction: PReaction; name: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function Reaction_getName(reaction: PReaction): PAnsiChar; cdecl; external LIBSBML_DLL;
function Reaction_setReversible(reaction: PReaction; reversible: Integer): Integer; cdecl; external LIBSBML_DLL;
function Reaction_getReversible(reaction: PReaction): Integer; cdecl; external LIBSBML_DLL;
function Reaction_setFast(reaction: PReaction; fast: Integer): Integer; cdecl; external LIBSBML_DLL;
function Reaction_getFast(reaction: PReaction): Integer; cdecl; external LIBSBML_DLL;

// Reactants and Products
function Reaction_getNumReactants(reaction: PReaction): Cardinal; cdecl; external LIBSBML_DLL;
function Reaction_getNumProducts(reaction: PReaction): Cardinal; cdecl; external LIBSBML_DLL;
function Reaction_getNumModifiers(reaction: PReaction): Cardinal; cdecl; external LIBSBML_DLL;

function Reaction_getReactant(reaction: PReaction; index: Cardinal): PSpeciesReference; cdecl; external LIBSBML_DLL;
function Reaction_getProduct(reaction: PReaction; index: Cardinal): PSpeciesReference; cdecl; external LIBSBML_DLL;
function Reaction_getModifier(reaction: PReaction; index: Cardinal): PSpeciesReference; cdecl; external LIBSBML_DLL;

function Reaction_createReactant(reaction: PReaction): PSpeciesReference; cdecl; external LIBSBML_DLL;
function Reaction_createProduct(reaction: PReaction): PSpeciesReference; cdecl; external LIBSBML_DLL;
function Reaction_createModifier(reaction: PReaction): PSpeciesReference; cdecl; external LIBSBML_DLL;

// Species Reference properties
function SpeciesReference_setSpecies(ref: PSpeciesReference; species_id: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function SpeciesReference_getSpecies(ref: PSpeciesReference): PAnsiChar; cdecl; external LIBSBML_DLL;
function SpeciesReference_setStoichiometry(ref: PSpeciesReference; stoichiometry: Double): Integer; cdecl; external LIBSBML_DLL;
function SpeciesReference_getStoichiometry(ref: PSpeciesReference): Double; cdecl; external LIBSBML_DLL;
function SpeciesReference_setConstant(ref: PSpeciesReference; constant: Integer): Integer; cdecl; external LIBSBML_DLL;
function SpeciesReference_getConstant(ref: PSpeciesReference): Integer; cdecl; external LIBSBML_DLL;

// Kinetic Law
function Reaction_getKineticLaw(reaction: PReaction): PKineticLaw; cdecl; external LIBSBML_DLL;
function Reaction_createKineticLaw(reaction: PReaction): PKineticLaw; cdecl; external LIBSBML_DLL;
function KineticLaw_setFormula(kineticLaw: PKineticLaw; formula: PAnsiChar): Integer; cdecl; external LIBSBML_DLL;
function KineticLaw_getFormula(kineticLaw: PKineticLaw): PAnsiChar; cdecl; external LIBSBML_DLL;

// ============================================================================
// Utility Functions
// ============================================================================

// Error and validation
function SBMLDocument_getNumErrors(document: PSBMLDocument): Cardinal; cdecl; external LIBSBML_DLL;
function SBMLDocument_checkConsistency(document: PSBMLDocument): Cardinal; cdecl; external LIBSBML_DLL;

// Helper functions for string conversion
function StringToPAnsiChar(const S: string): PAnsiChar;
function PAnsiCharToString(P: PAnsiChar): string;

// Wrapper classes for easier object-oriented usage
type
  TSBMLDocument = class
  private
    FDocument: PSBMLDocument;
    FModel: PModel;
  public
    constructor Create(Level, Version: Integer);
    destructor Destroy; override;
    
    function GetModel: PModel;
    function CreateModel: PModel;
    procedure SetModelId(const Id: string);
    function GetModelId: string;
    procedure SetModelName(const Name: string);
    function GetModelName: string;
    
    function SaveToFile(const Filename: string): Boolean;
    function LoadFromFile(const Filename: string): Boolean;
    function SaveToString: string;
    function LoadFromString(const XMLString: string): Boolean;
    
    function CheckConsistency: Cardinal;
    function GetNumErrors: Cardinal;
    
    property Document: PSBMLDocument read FDocument;
    property Model: PModel read FModel;
  end;

implementation

// ============================================================================
// Utility Functions Implementation
// ============================================================================

function StringToPAnsiChar(const S: string): PAnsiChar;
begin
  Result := PAnsiChar(AnsiString(S));
end;

function PAnsiCharToString(P: PAnsiChar): string;
begin
  if P <> nil then
    Result := string(AnsiString(P))
  else
    Result := '';
end;

// ============================================================================
// TSBMLDocument Implementation
// ============================================================================

constructor TSBMLDocument.Create(Level, Version: Integer);
begin
  inherited Create;
  FDocument := SBMLDocument_create(Level, Version);
  if FDocument = nil then
    raise Exception.Create('Failed to create SBML document');
  FModel := nil;
end;

destructor TSBMLDocument.Destroy;
begin
  if FDocument <> nil then
    SBMLDocument_free(FDocument);
  inherited Destroy;
end;

function TSBMLDocument.GetModel: PModel;
begin
  if FModel = nil then
    FModel := SBMLDocument_getModel(FDocument);
  Result := FModel;
end;

function TSBMLDocument.CreateModel: PModel;
begin
  FModel := SBMLDocument_createModel(FDocument);
  Result := FModel;
end;

procedure TSBMLDocument.SetModelId(const Id: string);
begin
  if GetModel <> nil then
    Model_setId(FModel, PAnsiChar(AnsiString(Id)));
end;

function TSBMLDocument.GetModelId: string;
var
  P: PAnsiChar;
  a : AnsiString;
begin
  if GetModel <> nil then
  begin
    P := Model_getId(FModel);
    a := AnsiString (P);
    Result := string(a);
  end
  else
    Result := '';
end;

procedure TSBMLDocument.SetModelName(const Name: string);
begin
  if GetModel <> nil then
    Model_setName(FModel, StringToPAnsiChar(Name));
end;

function TSBMLDocument.GetModelName: string;
var
  P: PAnsiChar;
begin
  if GetModel <> nil then
  begin
    P := Model_getName(FModel);
    Result := PAnsiCharToString(P);
  end
  else
    Result := '';
end;

function TSBMLDocument.SaveToFile(const Filename: string): Boolean;
begin
  Result := writeSBMLToFile(FDocument, StringToPAnsiChar(Filename)) = 1;
end;

function TSBMLDocument.LoadFromFile(const Filename: string): Boolean;
var
  NewDoc: PSBMLDocument;
begin
  NewDoc := readSBMLFromFile(StringToPAnsiChar(Filename));
  Result := NewDoc <> nil;
  if Result then
  begin
    if FDocument <> nil then
      SBMLDocument_free(FDocument);
    FDocument := NewDoc;
    FModel := nil; // Reset model pointer
  end;
end;

function TSBMLDocument.SaveToString: string;
var
  P: PAnsiChar;
begin
  P := writeSBMLToString(FDocument);
  Result := PAnsiCharToString(P);
end;

function TSBMLDocument.LoadFromString(const XMLString: string): Boolean;
var
  NewDoc: PSBMLDocument;
begin
  NewDoc := readSBMLFromString(StringToPAnsiChar(XMLString));
  Result := NewDoc <> nil;
  if Result then
  begin
    if FDocument <> nil then
      SBMLDocument_free(FDocument);
    FDocument := NewDoc;
    FModel := nil; // Reset model pointer
  end;
end;

function TSBMLDocument.CheckConsistency: Cardinal;
begin
  Result := SBMLDocument_checkConsistency(FDocument);
end;

function TSBMLDocument.GetNumErrors: Cardinal;
begin
  Result := SBMLDocument_getNumErrors(FDocument);
end;

end.