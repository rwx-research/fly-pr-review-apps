#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

REPO_OWNER=$(jq -r .event.base.repo.owner /github/workflow/event.json)
REPO_NAME=$(jq -r .event.base.repo.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="$INPUT_CONFIG"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

exit_code=0
flyctl status --app "$app" || exit_code=1
is_new_app=$(if [ $exit_code -ne 0 ] ; then echo "true" ; else echo "false" ; fi)

# Deploy the Fly app, creating it first if needed.
if $is_new_app; then
  flyctl apps create --name "$app" --org "$org"
  flyctl regions set "$region" --app "$app"

  # Attach postgres cluster to the app if specified.
  if [ -n "$INPUT_POSTGRES" ]; then
    flyctl postgres attach --postgres-app "$INPUT_POSTGRES" --app "$app"
  fi

  # Attach volume to the app if specified.
  if [ -n "$INPUT_VOLUME" ]; then
    flyctl volumes create review_app_volume --app "$app" --size "$INPUT_VOLUME" --region "$region"
  fi
fi

if [ $is_new_app ] || [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --config "$config" --app "$app" --image "$image" --remote-only
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
