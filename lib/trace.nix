{}:

let
  enabled = builtins.getEnv "S88_NFM_TRACE" == "1";
in
{
  emit = label: value:
    if enabled then
      builtins.trace "s88-nfm-trace ${label}" value
    else
      value;
}
