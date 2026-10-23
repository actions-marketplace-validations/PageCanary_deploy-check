#!/usr/bin/env bash
# PageCanary deploy check: start a walk of the deployment, wait for it, report it, and fail on a broken flow.
# Needs curl and jq (both on GitHub's hosted runners). A problem on PageCanary's side never fails your deploy.
set -uo pipefail

api="${PC_API_BASE:-https://www.pagecanary.com}"; api="${api%/}"
url="${PC_URL:-}"
out="${GITHUB_OUTPUT:-/dev/null}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
[ -n "${PC_BYPASS:-}" ] && echo "::add-mask::$PC_BYPASS"

finish() { # result headline recording id
  { echo "result=$1"; echo "headline=$2"; echo "recording-url=$3"; echo "walk-id=$4"; } >> "$out"
}
soft_fail() { # PageCanary couldn't run the check: say so, don't block the deploy
  echo "::warning title=PageCanary deploy check::$1"
  echo "### PageCanary deploy check: not run" >> "$summary"
  echo "$1" >> "$summary"
  finish error "$1" "" ""
  exit 0
}

if [ -z "${PC_API_KEY:-}" ]; then echo "::error::api-key is required (store your PageCanary API key as a secret)."; exit 1; fi
if [ -z "$url" ]; then echo "::error::No URL to walk. Set the url input, or run the workflow on deployment_status."; exit 1; fi

body=$(jq -n --arg url "$url" --arg secret "${PC_BYPASS:-}" --arg plan "${PC_PLAN:-}" \
  '{url: $url} + (if $secret == "" then {} else {vercelBypassSecret: $secret} end) + (if ($plan | test("\\S")) then {plan: $plan} else {} end)')
started=$(curl -sS --max-time 30 -X POST "$api/api/v1/walks" -H "Authorization: Bearer $PC_API_KEY" -H "Content-Type: application/json" -d "$body" -w '\n%{http_code}') \
  || soft_fail "Couldn't reach PageCanary to start the walk."
code=$(tail -n1 <<<"$started"); json=$(sed '$d' <<<"$started")
if [ "$code" = "401" ]; then echo "::error::PageCanary didn't accept the API key. Make a new one at https://www.pagecanary.com/dashboard/api."; exit 1; fi
if [ "$code" != "202" ]; then soft_fail "PageCanary couldn't start the walk: $(jq -r '.error // "HTTP '"$code"'"' <<<"$json" 2>/dev/null)"; fi
id=$(jq -r '.walk.id' <<<"$json")
echo "Walking $url (walk $id)…"

deadline=$(( $(date +%s) + ${PC_TIMEOUT_MINUTES:-6} * 60 ))
while :; do
  sleep "${PC_POLL_SECONDS:-5}"
  walk=$(curl -sS --max-time 30 "$api/api/v1/walks/$id" -H "Authorization: Bearer $PC_API_KEY") || walk=""
  status=$(jq -r '.walk.status // empty' <<<"$walk" 2>/dev/null)
  [ "$status" = "done" ] || [ "$status" = "error" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then soft_fail "The walk didn't finish within ${PC_TIMEOUT_MINUTES:-6} minutes (walk $id)."; fi
done

if [ "$status" = "error" ]; then soft_fail "$(jq -r '.walk.error // "The walk couldn'"'"'t finish."' <<<"$walk")"; fi
result=$(jq -r '.walk.result' <<<"$walk")
headline=$(jq -r '.walk.headline // ""' <<<"$walk")
detail=$(jq -r '.walk.detail // ""' <<<"$walk")
video=$(jq -r '.walk.videoUrl // ""' <<<"$walk")
finish "$result" "$headline" "$video" "$id"

case "$result" in
  passed) label="Passed" ;;
  failed) label="Broken" ;;
  planned) label="Mapped (forms are filled in, never sent)" ;;
  *) label="Couldn't test" ;;
esac
{
  echo "### PageCanary deploy check: $label"
  echo ""
  echo "**$headline**"
  [ -n "$detail" ] && echo "" && echo "$detail"
  echo ""
  echo "Walked $url"
  if [ "$(jq -r '.walk.planSteps | length' <<<"$walk" 2>/dev/null)" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "| Step | Result | What we saw |"
    echo "|---|---|---|"
    jq -r '.walk.planSteps | to_entries[] | "| \(.key + 1). \(.value.step | gsub("\\|"; "/")) | \({passed: "Passed", failed: "Failed", blocked: "Couldn'"'"'t do", "not-run": "Not run"}[.value.status] // .value.status) | \(.value.detail | gsub("\\|"; "/")) |"' <<<"$walk"
  else
    jq -r '.walk.steps | to_entries[] | "\(.key + 1). \(.value.text)"' <<<"$walk"
  fi
  [ -n "$video" ] && echo "" && echo "[Watch the recording]($video)"
} >> "$summary"
echo "$headline"
[ -n "$video" ] && echo "Recording: $video"

if [ "$result" = "failed" ] && [ "${PC_FAIL_ON:-failed}" = "failed" ]; then
  echo "::error title=PageCanary deploy check::$headline"
  exit 1
fi
[ "$result" = "cant-test" ] && echo "::warning title=PageCanary deploy check::$headline"
exit 0
