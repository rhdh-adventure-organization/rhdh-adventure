#!/bin/bash

# Configuration variables
TOTAL_USERS=20 # Change this to the desired number of users

# Running from same folder
cd $(dirname $0)

# Set default values
ssl_certs_self_signed="n"

# Iterate over command-line arguments
for arg in "$@"; do
    case $arg in
        --ssl_certs_self_signed=*)
            ssl_certs_self_signed="${arg#*=}"
            ;;
        *)
            # Other arguments are ignored
            ;;
    esac
done

# Check if insecure flag is set to 'y'
if [ "$ssl_certs_self_signed" = "y" ]; then
    # Declare local variables
    echo "SSL Certificates self signed enabled."
    CURL_DISABLE_SSL_VERIFICATION="-k"
    GIT_DISABLE_SSL_VERIFICATION="-c http.sslVerify=false"
fi

# Check required CLI's
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed.  Aborting."; exit 1; }
command -v oc >/dev/null 2>&1 || { echo >&2 "OpenShift CLI is required but not installed.  Aborting."; exit 1; }

#GitLab token must be 20 characters
DEFAULT_GITLAB_TOKEN="KbfdXFhoX407c0v5ZP2Y"

GITLAB_TOKEN=${GITLAB_TOKEN:=$DEFAULT_GITLAB_TOKEN}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:=gitlab-system}

GITLAB_URL=https://$(oc get ingress -n $GITLAB_NAMESPACE -l app=webservice -o jsonpath='{ .items[*].spec.rules[*].host }')

# Check if Token has been registered
if [ "401" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s -I "${GITLAB_URL}/api/v4/user" -w "%{http_code}" -o /dev/null) ]; then
    echo "Registering Token"
    # Create root token
    oc exec -it -n $GITLAB_NAMESPACE -c toolbox $(oc get pods -n $GITLAB_NAMESPACE -l=app=toolbox -o jsonpath='{ .items[0].metadata.name }') -- sh -c "$(cat << EOF
    gitlab-rails runner "User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token', expires_at: 365.days.from_now, token_digest: Gitlab::CryptoHelper.sha256('${GITLAB_TOKEN}'))"
EOF
    )"
fi

# Create Groups
if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-a", "name": "team-a", "visibility": "public" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq length) ]; then
    curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"path": "team-b", "name": "team-b", "visibility": "public" }' \
    "${GITLAB_URL}/api/v4/groups" &> /dev/null
fi

TEAM_A_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-a" | jq -r '(.|first).id')
TEAM_B_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups?search=team-b" | jq -r '(.|first).id')

# Create Users
for i in $(seq 1 $TOTAL_USERS); do
    USERNAME="user$i"
    EMAIL="$USERNAME@redhat.com"
    PASSWORD="@abc1cde2"

    if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=$USERNAME" | jq length) ]; then
        echo "Creating user $USERNAME..."
        curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --header "Content-Type: application/json" \
            --data "{\"email\": \"$EMAIL\", \"password\": \"$PASSWORD\", \"name\": \"$USERNAME\", \"username\": \"$USERNAME\", \"skip_confirmation\": \"true\" }" \
            "${GITLAB_URL}/api/v4/users" &> /dev/null
    fi

    # Get the user ID
    USER_ID=$(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/users?search=$USERNAME" | jq -r '(.|first).id')

    # Check and add the user to the appropriate group
    if (( i % 2 == 1 )); then
        # Odd users -> Team A
        echo "Assigning $USERNAME to Team A..."
        GROUP_ID=$TEAM_A_ID
    else
        # Even users -> Team B
        echo "Assigning $USERNAME to Team B..."
        GROUP_ID=$TEAM_B_ID
    fi

    # Add users to groups
    if [ "0" == $(curl $CURL_DISABLE_SSL_VERIFICATION --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -s "${GITLAB_URL}/api/v4/groups/$GROUP_ID/members?user_ids=$USER_ID" | jq length) ]; then
        curl $CURL_DISABLE_SSL_VERIFICATION --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --header "Content-Type: application/json" \
            --data "{\"user_id\": \"$USER_ID\", \"access_level\": 50 }" \
            "${GITLAB_URL}/api/v4/groups/$GROUP_ID/members" &> /dev/null
    fi
done

echo "GitLab setup completed successfully."

