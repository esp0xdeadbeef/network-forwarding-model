{ lib }:

{
  build =
    { site, ... }:
    let
      normalizeCommunicationContract =
        contract:
        if !(builtins.isAttrs contract) then
          {
            allowedRelations = [ ];
            services = [ ];
            trafficTypes = [ ];
          }
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
          (builtins.removeAttrs contract [
            "relations"
            "interfaceTags"
          ])
          // {
            allowedRelations = allowedRelations0;
          };

      normalizePolicy =
        policy:
        if !(builtins.isAttrs policy) then
          {
            interfaceTags = { };
          }
        else
          policy
          // {
            interfaceTags =
              if policy ? interfaceTags && builtins.isAttrs policy.interfaceTags then
                policy.interfaceTags
              else
                { };
          };
    in
    {
      communicationContract = normalizeCommunicationContract (site.communicationContract or { });
      policy = normalizePolicy (site.policy or { });
    };
}
