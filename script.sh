#!/bin/bash

declare -a MANDITORY
MANDITORY=("DOCKERCLOUD_AUTH" "SERVICE" "STACK" "PORT" "ARN" )
for V in ${MANDITORY[@]}; do
  if [ -z "${!V}" ]; then
    echo -e "Failed to define $V"
    exit 1
  fi
done

URI="https://cloud.docker.com/api/app/v1/$NAMESPACE"

# Get the STACKURI
STACKURI=`curl -s -H "Authorization: Basic $DOCKERCLOUD_AUTH" -XGET "$URI/stack/" --data-urlencode "name=$SERVICE" | jq '.objects[] | .resource_uri ' | tr -d '\"'`
echo -e "\nStack URI\n $STACKURI"

# Get the SERVICE URI matching SERVICE and STACKURI
SERVICEURI=`curl -s -H "Authorization: Basic $DOCKERCLOUD_AUTH" -XGET "$URI/service/" --data-urlencode "name=$SERVICE" --data-urlencode "stack=$STACKURI" | jq '.objects[] | .resource_uri'| tr -d '\"'`
echo -e "\nService URI\n $SERVICEURI"

# Get Nodes URIs for containers associated with the SERVICEURI
declare -a NODEURIS
NODEURIS=`curl -s -H "Authorization: Basic $DOCKERCLOUD_AUTH" -XGET "$URI/container/?limit=1" --data-urlencode "service=$SERVICEURI" | jq '.objects[] | .node' | tr -d '\"' | sort | uniq`
echo -e "\nNode URIs"
printf '%s\n' "${NODEURIS[@]}"

# Convert NODEURIS into AWS node names
i=0
declare -a AWSNICKS
for NODE in ${NODEURIS[@]}; do
	AWSNICKS[$i]=`echo $NODE | sed 's/.*\/\(.*\)\/$/\1.node.dockerapp.io/'`
	i=$(( $i + 1))
done
echo -e "\nAWS Node Names"
printf '%s\n' "${AWSNICKS[@]}"

# Get a list of AWS IDs from AWS node names
i=0
declare -a AWSIDS
for ID in ${AWSNICKS[@]}; do
	AWSIDS[$i]=`aws ec2 describe-instances --filters "Name=tag-value,Values=$ID" --query "Reservations[*].Instances[*].InstanceId" --region $REGION --output text`
	i=$(( $i + 1))
done
echo -e "\nAWS Node IDs"
printf '%s\n' "${AWSIDS[@]}"

declare -a EXISTINGIDS
EXISTINGIDS=`aws elbv2 describe-target-health --target-group-arn $ARN --region $REGION| jq '.TargetHealthDescriptions[] | .Target.Id' | tr -d '\"'`

# Compare AWSIDS and EXISTINGIDS, create ADDID array of IDs to add, and REMOVEID of IDs to remove
declare -A COMPARE
for ID in ${EXISTINGIDS[@]}; do
  COMPARE[$ID]=1
done
for ID in ${AWSIDS[@]}; do
  COMPARE[$ID]=$((${COMPARE[$ID]}+2))
done
declare -a ADDID
declare -a REMOVEID
i=0
n=0
for ID in ${!COMPARE[@]}; do
  if [ ${COMPARE[$ID]} = 1 ]; then
    REMOVEID[$i]=$ID
    i=$(($i + 1))
  elif [ ${COMPARE[$ID]} = 2 ]; then
    ADDID[$n]=$ID
    n=$(($i + 1))
  fi
done

# Add AWS IDs to 
echo -e "\nAdding IDs"
printf '%s\n' "${ADDID[@]}"
for ID in ${ADDID[@]}; do
	aws elbv2 register-targets --target-group-arn $ARN --targets Id=$ID,Port=$PORT --region $REGION
done

# Remove AWS IDs to 
echo -e "\nRemoving IDs"
printf '%s\n' "${REMOVE[@]}"
for ID in ${REMOVEID[@]}; do
  aws elbv2 deregister-targets --target-group-arn $ARN --targets Id=$ID,Port=$PORT --region $REGION
done