{ lib, ... }:

{
  coreNames =
    { normalizedRouteSite
    , wanResult
    ,
    }:
    let
      routedNames =
        if normalizedRouteSite ? uplinkCoreNames && builtins.isList normalizedRouteSite.uplinkCoreNames then
          normalizedRouteSite.uplinkCoreNames
        else
          [ ];

      wanNames =
        if wanResult ? declaredUplinkCores && builtins.isList wanResult.declaredUplinkCores then
          wanResult.declaredUplinkCores
        else if wanResult ? uplinkCores && builtins.isList wanResult.uplinkCores then
          wanResult.uplinkCores
        else
          [ ];

      egressNames =
        if normalizedRouteSite ? egressIntent && builtins.isAttrs normalizedRouteSite.egressIntent then
          normalizedRouteSite.egressIntent.uplinkCoreNodeNames or [ ]
        else
          [ ];
    in
    lib.sort (a: b: a < b) (
      lib.unique (if wanNames != [ ] then wanNames else if routedNames != [ ] then routedNames else egressNames)
    );

  uplinkNames =
    { normalizedRouteSite
    , wanResult
    ,
    }:
    let
      routedNames =
        if normalizedRouteSite ? uplinkNames && builtins.isList normalizedRouteSite.uplinkNames then
          normalizedRouteSite.uplinkNames
        else
          [ ];

      wanNames =
        if wanResult ? declaredUplinkNames && builtins.isList wanResult.declaredUplinkNames then
          wanResult.declaredUplinkNames
        else if wanResult ? uplinkNames && builtins.isList wanResult.uplinkNames then
          wanResult.uplinkNames
        else
          [ ];

      egressNames =
        if normalizedRouteSite ? egressIntent && builtins.isAttrs normalizedRouteSite.egressIntent then
          normalizedRouteSite.egressIntent.externalDomains or [ ]
        else
          [ ];
    in
    lib.sort (a: b: a < b) (
      lib.unique (if routedNames != [ ] then routedNames else if wanNames != [ ] then wanNames else egressNames)
    );
}
