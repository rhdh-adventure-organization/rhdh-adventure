#!/bin/bash

# Check for required arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <OCP_API_URL> <ADMIN_USERNAME>"
  exit 1
fi

# Read arguments
OCP_API_URL=$1
ADMIN_USERNAME=$2
NUMBER_OF_USERS=20 # Specify the number of users to create namespaces for
OC_BINARY="oc" # Path to the `oc` binary if not in PATH

# Prompt for admin password
echo "Please enter the password for $ADMIN_USERNAME:"
read -s ADMIN_PASSWORD

# Login to OpenShift cluster
echo "Logging in to OpenShift cluster..."
$OC_BINARY login --username=$ADMIN_USERNAME --password=$ADMIN_PASSWORD --server=$OCP_API_URL &> /dev/null
if [ $? -ne 0 ]; then
  echo "Error: Failed to log in to OpenShift cluster."
  exit 1
fi
echo "Login successful."

# Loop to create projects and assign permissions
for i in $(seq 1 $NUMBER_OF_USERS); do
  USER="user$i"
  PROJECT_NAME="rhdh-by-team-$i"

  echo "Creating project: $PROJECT_NAME"
  $OC_BINARY new-project $PROJECT_NAME &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create project $PROJECT_NAME. Skipping..."
    continue
  fi

  echo "Assigning user $USER as administrator of project $PROJECT_NAME"
  $OC_BINARY adm policy add-role-to-user admin $USER -n $PROJECT_NAME &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Error: Failed to assign admin role to user $USER in project $PROJECT_NAME. Skipping..."
    continue
  fi

  echo "Assigning user $USER to monitoring the project $PROJECT_NAME"
  $OC_BINARY adm policy add-cluster-role-to-user monitoring-rules-view $USER -n $PROJECT_NAME &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Error: Failed to assign monitoring role to user $USER in project $PROJECT_NAME. Skipping..."
    continue
  fi

  echo "Project $PROJECT_NAME successfully created and assigned to $USER."
done

echo "Script completed successfully."
