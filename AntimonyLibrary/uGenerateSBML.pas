unit uGenerateSBML;

interface

Uses SysUtils,
     uAntimonyModelType,
     uLibSBMLHelpers;

function GenerateSBML (Model : TAntimonyModel) : string;

implementation

function GenerateSBML (Model : TAntimonyModel) : string;
var Manager: TSBMLModelManager;
    i, j, Index : integer;
    Compartment : TSBMLCompartment;
    Species: TSBMLSpecies;
    Reaction : TSBMLReaction;
    Parameter : TSBMLParameter;
    InitialValue : double;
begin
  Manager := TSBMLModelManager.Create(3, 1);
  try
    Manager.SetModelId(Model.Name);

    if Model.Compartments.Count = 0 then
        Compartment := Manager.CreateCompartment('defaultCompartment', '', 1.0)
    else
      for i := 0 to Model.Compartments.Count - 1 do
          Compartment := Manager.CreateCompartment(Model.Compartments[i].Id, '', Model.Compartments[i].Size);

    for i := 0 to Model.Species.Count - 1 do
        begin
        Species := Manager.CreateSpecies(Model.Species[i].Id, '', Model.Species[i].Compartment, Model.Species[i].InitialValue);
        Species.BoundaryCondition := Model.Species[i].IsBoundary;
        if Model.Compartments.Count = 0 then
           Species.CompartmentId := Compartment.Id;
        if Model.Species[i].Compartment = '' then
           Species.CompartmentId := Compartment.Id;
        end;

    for i := 0 to Model.Assignments.Count - 1 do
        begin
        // Check if the assignment is a species or not, if its not (-1) then treat as a parameter
        if Model.FindSpecies(Model.Assignments[i].Variable) = -1 then
           Parameter := Manager.CreateParameter(Model.Assignments[i].Variable, '', strtofloat (Model.Assignments[i].Expression));
        end;

    for i := 0 to Model.Reactions.Count - 1 do
        begin
        Reaction := Manager.CreateReaction(Model.Reactions[i].Id, '');
        for j := 0 to Model.Reactions[i].Reactants.Count - 1 do
            Reaction.AddReactant(Model.Reactions[i].Reactants[j].SpeciesName, Model.Reactions[i].Reactants[j].Stoichiometry);
        for j := 0 to Model.Reactions[i].Products.Count - 1 do
            Reaction.AddProduct(Model.Reactions[i].Products[j].SpeciesName, Model.Reactions[i].Products[j].Stoichiometry);
        Reaction.SetKineticLaw(Model.Reactions[i].KineticLaw);
        end;

    result := Manager.GetSBML;
  finally
    Manager.Free;
  end;

end;


end.
