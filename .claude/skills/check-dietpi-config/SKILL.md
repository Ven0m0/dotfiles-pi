---
name: check-dietpi-config
description: Validate dietpi.txt and dietpi-wifi.txt in this repo (dotfiles-pi) against the build-image.yml CI gate, this repo's secret-handling rules, and DietPi's real software-ID catalog. Use before committing changes to dietpi.txt/dietpi-wifi.txt, before triggering an image build, or whenever asked to check/validate/review DietPi config in this repo.
allowed-tools: Read, Bash, Grep, WebFetch
---

# Check DietPi Config

`dietpi.txt` and `dietpi-wifi.txt` at the repo root are injected into built images by
`.github/workflows/build-image.yml`. This skill runs the checks that catch the mistakes that
class of file is prone to: a CI build that silently refuses to run, a real secret committed to
git, or a software ID that doesn't do what the comment above it claims.

## 1. CI password gate

The workflow refuses to build while the password is still the placeholder:
```bash
grep -Eq '^AUTO_SETUP_GLOBAL_PASSWORD=MUST_SET_PASSWORD_BEFORE_BUILD[[:space:]]*$' dietpi.txt
```
If this matches, tell the user the build will fail at the "Validate DietPi automation template"
step until a real value is set — don't just report it as an abstract fact, state the concrete
consequence.

## 2. Secret hygiene

- `AUTO_SETUP_GLOBAL_PASSWORD` in `dietpi.txt`: this field is *expected* to hold a real value
  (that's the point of the CI gate above) — this is the one intentional exception to this repo's
  "no secrets" rule, since `dietpi.txt` is a personal automation template the user fills in, not
  shared application code. Don't flag a non-placeholder password here as a violation. Do flag it
  if it looks like it was copy-pasted from somewhere unexpected (e.g. matches a value seen in
  another unrelated file in the repo, suggesting accidental reuse of a real credential).
- `dietpi-wifi.txt`, if present: every `aWIFI_SSID[N]` / `aWIFI_KEY[N]` / `aWIFI_PASSWORD[N]`
  field must be empty (`''`) in the git-tracked copy. Check with:
  ```bash
  grep -E "a(WIFI_SSID|WIFI_KEY|WIFI_PASSWORD)\[[0-9]+\]='[^']+'" dietpi-wifi.txt
  ```
  Any match is a real credential that shouldn't be committed. (A `PreToolUse` hook already blocks
  `git commit`/`git add` when this is non-empty — this check is for reviewing the file directly,
  e.g. mid-edit, before that gate would even run.)

## 3. Software ID validation

`AUTO_SETUP_INSTALL_SOFTWARE_ID` in `dietpi.txt` lists numeric DietPi software IDs. These are easy
to get wrong (transposed digits, IDs from memory that have since been reassigned) and DietPi
doesn't validate them at parse time — an unknown ID is just silently skipped at provisioning time,
which is a hard-to-diagnose failure after the fact.

To verify, fetch the authoritative source and cross-reference each ID:
```bash
curl -fsSL https://raw.githubusercontent.com/MichaIng/DietPi/master/dietpi/dietpi-software \
  -o /tmp/dietpi-software.sh
grep -n -A2 "software_id=<ID>$" /tmp/dietpi-software.sh
```
Report each configured ID's resolved name (e.g. `17 → Git`, `87 → SQLite`) so the user can
sanity-check the list matches intent — don't just confirm "valid/invalid", the actual mapping is
the useful part (this caught a case in this repo's history where confirming IDs 17/87/89/132
resolved to Git/SQLite/PHP/Aria2, not what the surrounding comment implied). Also check
`AUTO_SETUP_APT_INSTALLS` package names look like real Debian package names if any look unusual —
this repo previously caught a `lsb-release` → `lsp-release` typo this way; when in doubt, search
`packages.debian.org` rather than guessing.

## 4. Cross-check web server / dependency implications

If `AUTO_SETUP_INSTALL_SOFTWARE_ID` includes something with a `webserver` dependency (check the
fetched `dietpi-software` source's `aSOFTWARE_DEPS[$software_id]` for the ID in question), confirm
`AUTO_SETUP_WEB_SERVER_INDEX` in `dietpi.txt` is set to a sane preference — DietPi silently picks
one based on that preference when a generic `webserver` dependency is needed, so an unset/default
value may not be what the user expects.

## Output

Summarize as a short checklist (gate: pass/fail, secrets: clean/found, software IDs: resolved
list, apt packages: any suspicious names) rather than a wall of raw command output.
