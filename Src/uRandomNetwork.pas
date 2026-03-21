unit uRandomNetwork;

{
  uRandomNetwork.pas
  ==================
  Generates random biochemical networks for testing and demonstration.

  The generator produces a connected network by first building a backbone
  linear chain (ensuring every species is reachable), then adding extra
  reactions that connect randomly chosen species pairs.  This avoids the
  degenerate case of isolated species that no layout algorithm can place
  sensibly.

  Usage
  -----
    TRandomNetwork.Generate(FModel, 6, 8);   // 6 species, 8 reactions
    FView.SyncSpeciesNameCounter;            // keep name counter in sync
}

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  uBioModel;

type
  TRandomNetwork = class
  public
    // Generate a random network with ASpeciesCount species and
    // AReactionCount reactions into AModel (clears it first).
    //
    // Constraints
    //   ASpeciesCount  >= 2
    //   AReactionCount >= ASpeciesCount - 1   (to guarantee connectivity)
    //
    // Layout
    //   Species are placed on a rough grid; reactions are centred between
    //   their participants.  Run auto-layout afterwards for a better result.
    //
    // Kinetics
    //   Each reaction gets a mass-action rate law kN * S1 * S2 ...
    //   and a matching parameter kN = 0.1.
    class procedure Generate(AModel         : TBioModel;
                             ASpeciesCount  : Integer;
                             AReactionCount : Integer);
  end;

implementation

class procedure TRandomNetwork.Generate(AModel         : TBioModel;
                                        ASpeciesCount  : Integer;
                                        AReactionCount : Integer);
const
  NODE_W      = 80;
  NODE_H      = 36;
  GRID_COLS   = 5;       // species placed in a grid of this width
  GRID_CELL_W = 160;
  GRID_CELL_H = 620;
  MARGIN      = 80;

var
  Species      : TList<TSpeciesNode>;
  i            : Integer;
  Col, Row     : Integer;
  X, Y         : Single;
  S            : TSpeciesNode;
  R            : TReaction;
  ReactIdx     : Integer;
  ProdIdx      : Integer;
  JX, JY       : Single;
  KName        : string;
  RateLaw      : string;
  NumReactants : Integer;
  NumProducts  : Integer;
  ParamNum     : Integer;

  function PickDifferent(AExclude: Integer): Integer;
  // Return a random species index different from AExclude.
  var
    Idx : Integer;
  begin
    repeat
      Idx := Random(ASpeciesCount);
    until Idx <> AExclude;
    Result := Idx;
  end;

  procedure AddReaction(ARIdx, APIdx: Integer; AParamNum: Integer);
  // Wire up a single reaction between species at ARIdx and APIdx.
  var
    Reactant : TSpeciesNode;
    Product  : TSpeciesNode;
  begin
    Reactant := Species[ARIdx];
    Product  := Species[APIdx];
    JX := (Reactant.Center.X + Product.Center.X) * 0.5;
    JY := (Reactant.Center.Y + Product.Center.Y) * 0.5;

    R := AModel.AddReaction(JX, JY);
    R.Reactants.Add(TParticipant.Create(Reactant, 1.0));
    R.Products.Add (TParticipant.Create(Product,  1.0));
    R.IsLinear := True;

    KName   := 'k' + IntToStr(AParamNum);
    RateLaw := KName + '*' + Reactant.Id;
    R.KineticLaw := RateLaw;

    if not Assigned(AModel.FindParameterByVar(KName)) then
      AModel.AddParameter(KName, '0.1');
  end;

begin
  // Clamp inputs to valid ranges
  ASpeciesCount  := Max(2, ASpeciesCount);
  AReactionCount := Max(ASpeciesCount - 1, AReactionCount);

  AModel.Clear;
  Randomize;

  Species := TList<TSpeciesNode>.Create;
  try
    // -----------------------------------------------------------------
    //  1. Create species on a grid
    // -----------------------------------------------------------------
    for i := 0 to ASpeciesCount - 1 do
    begin
      Col := i mod GRID_COLS;
      Row := i div GRID_COLS;
      X   := MARGIN + Col * GRID_CELL_W;
      Y   := MARGIN + Row * GRID_CELL_H;

      S := AModel.AddSpecies('S' + IntToStr(i + 1), X, Y, NODE_W, NODE_H);
      S.InitialValue := 1.0 + Random * 4.0;   // random value in [1, 5]
      Species.Add(S);
    end;

    ParamNum := 1;

    // -----------------------------------------------------------------
    //  2. Backbone: linear chain S1→S2→S3→...→SN
    //     Guarantees the network is connected.
    // -----------------------------------------------------------------
    for i := 0 to ASpeciesCount - 2 do
    begin
      AddReaction(i, i + 1, ParamNum);
      Inc(ParamNum);
    end;

    // -----------------------------------------------------------------
    //  3. Extra reactions chosen randomly
    //     Each picks a random reactant and a different random product.
    //     Occasionally uses BiUni or UniBi topology (30% chance each).
    // -----------------------------------------------------------------
    var ExtraCount := AReactionCount - (ASpeciesCount - 1);

    for i := 1 to ExtraCount do
    begin
      ReactIdx := Random(ASpeciesCount);
      ProdIdx  := PickDifferent(ReactIdx);

      // Random chance of multi-participant reaction
      NumReactants := 1;
      NumProducts  := 1;
      var Roll := Random(10);
      if Roll < 2 then      // 20% chance BiUni
        NumReactants := 2
      else if Roll < 4 then // 20% chance UniBi
        NumProducts := 2;

      JX := (Species[ReactIdx].Center.X + Species[ProdIdx].Center.X) * 0.5;
      JY := (Species[ReactIdx].Center.Y + Species[ProdIdx].Center.Y) * 0.5;

      R := AModel.AddReaction(JX, JY);
      KName   := 'k' + IntToStr(ParamNum);
      RateLaw := KName;

      // Add reactants
      R.Reactants.Add(TParticipant.Create(Species[ReactIdx], 1.0));
      RateLaw := RateLaw + '*' + Species[ReactIdx].Id;

      if NumReactants > 1 then
      begin
        var SecondReact := PickDifferent(ReactIdx);
        R.Reactants.Add(TParticipant.Create(Species[SecondReact], 1.0));
        RateLaw := RateLaw + '*' + Species[SecondReact].Id;
      end;

      // Add products
      R.Products.Add(TParticipant.Create(Species[ProdIdx], 1.0));

      if NumProducts > 1 then
      begin
        var SecondProd := PickDifferent(ProdIdx);
        R.Products.Add(TParticipant.Create(Species[SecondProd], 1.0));
      end;

      R.KineticLaw := RateLaw;

      if not Assigned(AModel.FindParameterByVar(KName)) then
        AModel.AddParameter(KName, '0.1');

      Inc(ParamNum);
    end;

  finally
    Species.Free;
  end;
end;

end.
