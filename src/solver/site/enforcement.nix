{ lib }:

{
  build =
    { site, ... }:
    let
      normalizeCommunicationContract =
        contract:
        if !(builtins.isAttrs contract) then
          contract
        else
          let
            allowedRelations0 =
              if contract ? allowedRelations then
                contract.allowedRelations
              else if contract ? relations then
                contract.relations
              else
                [ ];
          in
          (builtins.removeAttrs contract [ "relations" ])
          // {
            allowedRelations = allowedRelations0;
          }
          // {
            interfaceTags = if contract ? interfaceTags then contract.interfaceTags else { };
          };
    in
    {
      communicationContract = normalizeCommunicationContract (site.communicationContract or { });
    };
}
