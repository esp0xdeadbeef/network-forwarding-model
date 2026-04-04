{ lib }:

{
  build =
    { site, ... }:
    let
      normalizeCommunicationContract =
        contract:
        let
          value = if builtins.isAttrs contract then contract else { };
        in
        {
          allowedRelations =
            if value ? allowedRelations && builtins.isList value.allowedRelations then
              value.allowedRelations
            else
              [ ];
          services = if value ? services && builtins.isList value.services then value.services else [ ];
          trafficTypes =
            if value ? trafficTypes && builtins.isList value.trafficTypes then value.trafficTypes else [ ];
        };

      mkTenantTag = tenant: {
        name = tenant.name;
        value = {
          attachments = [ ];
          domains = [
            (tenant // { kind = "tenant"; })
          ];
        };
      };

      mkExternalTag = external: {
        name = "external-${external.name}";
        value = {
          attachments = [ ];
          domains = [
            external
          ];
        };
      };

      mkAttachmentTag = attachment: {
        name = attachment.name;
        value = {
          attachments = [ attachment ];
          domains = [ ];
        };
      };

      mergeTag = left: right: {
        attachments = (left.attachments or [ ]) ++ (right.attachments or [ ]);
        domains = (left.domains or [ ]) ++ (right.domains or [ ]);
      };

      mergeTagSets =
        left: right:
        left
        // builtins.mapAttrs (
          name: value:
          mergeTag (left.${name} or {
            attachments = [ ];
            domains = [ ];
          }
          ) value
        ) right;

      tagsFromList =
        items: builtins.foldl' (acc: item: mergeTagSets acc { "${item.name}" = item.value; }) { } items;

      normalizePolicy =
        policy:
        let
          value = if builtins.isAttrs policy then builtins.removeAttrs policy [ "interfaceTags" ] else { };
        in
        value
        // {
          interfaceTags =
            mergeTagSets
              (mergeTagSets (tagsFromList (builtins.map mkTenantTag (site.domains.tenants or [ ]))) (
                tagsFromList (builtins.map mkExternalTag (site.domains.externals or [ ]))
              ))
              (tagsFromList (builtins.map mkAttachmentTag (site.attachments or [ ])));
        };
    in
    {
      communicationContract = normalizeCommunicationContract (site.communicationContract or { });
      policy = normalizePolicy (site.policy or { });
    };
}
