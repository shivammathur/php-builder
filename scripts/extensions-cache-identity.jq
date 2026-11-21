# Only checkout-root prefix maps are location independent. Other paths, map
# destinations and option order can change the installed extension's behavior.
def checkout_root:
  (capture("^(?<workspace>/__w|/home/runner/work|/home/runner/work/_temp/managed-runner-[A-Za-z0-9_-]+/_work)/(?<repo>[A-Za-z0-9_.-]+)/(?<checkout>[A-Za-z0-9_.-]+)$")
   | .repo == .checkout) // false;

def prefix_map:
  . as $original
  | (capture("^(?<assignment>(?:(?:CFLAGS|CPPFLAGS|CXXFLAGS|LDFLAGS|EXTRA_CFLAGS|ICU_CXXFLAGS)=)?)(?<option>-f(?:file|debug|macro)-prefix-map)=(?<source>[^=]+)=(?<destination>.*)$")
     | if (.source | checkout_root) then
         .assignment + .option + "=<github-checkout>=" + .destination
       else $original end) // $original;

def build_options:
  if type != "string" then .
  # Preserve quoted/escaped values verbatim, including significant whitespace.
  # A conservative cache miss is preferable to conflating different arguments.
  elif contains("'") or contains("\"") or contains("\\") then .
  else [splits("[ \t\r\n]+") | select(length > 0) | prefix_map] | join(" ")
  end;

del(.context.development_commit, .context.development_headers,
    .context.libraries, .context.scripts, .context.php_patches)
| .context.configure |= build_options
| .context.flags |= with_entries(
    if (.key | IN("CFLAGS", "CPPFLAGS", "CXXFLAGS", "LDFLAGS", "EXTRA_CFLAGS", "ICU_CXXFLAGS"))
    then .value |= build_options else . end)
