{ lib, self ? { outPath = ./.; }, ... }:

{
  assertAny =
    { discoveredCoreNames
    , expectedInputs
    ,
    }:
    if discoveredCoreNames != [ ] then
      true
    else
      throw ''
        network-forwarding-model: no uplinks discovered for any core

        expected one of:
        ${lib.concatMapStringsSep "\n" (line: "- ${line}") expectedInputs}
      '';
}
