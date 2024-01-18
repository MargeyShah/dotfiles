#!/bin/bash

# GitHub API endpoint and your personal access token
API_ENDPOINT="https://github.twdcgrid.net/api/v3"
TOKEN="TOKEN"

# Webhook URL to search for
WEBHOOK_URL="https://yellowpages.staging.hulu.com/api/sox_pr_webhook/"

# Get a list of all organizations
orgs=$(curl -s -H "Authorization: token $TOKEN" "$API_ENDPOINT/organizations?per_page=100")

# Loop through each organization
for org in $(echo "$orgs" | jq -r '.[].login'); do
#     # Get a list of webhooks for the organization
    webhooks=$(curl -H "Accept: application/vnd.github+json" -H "Authorization: token $TOKEN" $API_ENDPOINT/orgs/$org/hooks)
#     # Loop through each webhook
    for hook_id in $(echo "$webhooks" | jq -r '.[].id'); do
#         # Get details of the webhook
        webhook=$(curl -s -H "Authorization: token $TOKEN" $API_ENDPOINT/orgs/$org/hooks/$hook_id)
#         # Check if the webhook URL matches
        if [[ $(echo "$webhook" | jq -r '.config.url') == "$WEBHOOK_URL" ]]; then
            # Update webhook events to ['pull_request', 'pull_request_review']
            echo "$WEBHOOK_URL"
            updated_events=$(echo "$webhook" | jq -c '.events=["pull_request", "pull_request_review"]')

            # Perform the update
            curl -X PATCH -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" \
                $API_ENDPOINT/orgs/$org/hooks/$hook_id -d "$updated_events"

            echo "Webhook events updated for organization $org."
        fi
        # echo $(echo "$webhook" | jq -r '.config.url')
    done
done

