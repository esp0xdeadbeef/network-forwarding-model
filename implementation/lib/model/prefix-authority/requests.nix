{ lib, self ? { outPath = ./.; }, ... }:

let
  requestId =
    idx: r:
    toString (r.id or r.name or "request-${toString idx}");

  classifyRequest =
    records: idx: request:
    let
      authorityId = request.authorityId or null;
      authority = if authorityId != null && records ? "${authorityId}" then records.${authorityId} else null;
      consumer = toString (request.consumer or "route");
      assigned = authority != null && (authority.reservationState or "assigned") == "assigned";
      consumerAllowed = assigned && ((authority.consumerEligibility.${consumer} or false) == true);
      allowed = consumerAllowed;
      reason =
        if authority == null then
          "unassigned-prefix-authority"
        else if (authority.reservationState or "assigned") != "assigned" then
          "reserved-prefix-authority"
        else if !consumerAllowed then
          "invalid-consumer-for-authority-class"
        else
          "allowed";
    in
    {
      id = requestId idx request;
      inherit
        allowed
        consumer
        reason
        ;
      authorityId = authorityId;
      authorityClass = if authority == null then null else authority.authorityClass;
      reservationState = if authority == null then "unassigned" else authority.reservationState or "assigned";
    }
    // lib.optionalAttrs ((request.family or null) != null) { family = request.family; }
    // lib.optionalAttrs ((request.prefix or null) != null) { prefix = toString request.prefix; }
    // lib.optionalAttrs ((request.sourceFile or null) != null) { sourceFile = toString request.sourceFile; };

in
{
  classify =
    records: requests:
    map (args: classifyRequest records args.fst args.snd) (lib.imap0 (idx: value: {
      fst = idx;
      snd = value;
    }) requests);
}
