#!/bin/bash

declare -a MANDATORY
MANDITORY=("DOCKERCLOUD_AUTH" "SERVICE" "PORT" "ARN" )
for V in ${MANDATORY[@]}; do
  if [ -z "${!V}" ]; then
    echo -e "Failed to define $V"
    exit 1
  fi
done

URI="https://cloud.docker.com/api/app/v1/$NAMESPACE"

# Get the STACKURI
STACKURI=`curl -s -H "Authorization: $DOCKERCLOUD_AUTH" -XGET "$URI/stack/" -G --data-urlencode "name=$STACK" | jq  --raw-output '.objects[] | .resource_uri '`
echo -e "\nStack URI\n $STACKURI"

# Get the SERVICE URI matching SERVICE and STACKURI
SERVICEURI=`curl -s -H "Authorization: $DOCKERCLOUD_AUTH" -XGET "$URI/service/" -G --data-urlencode "name=$SERVICE" --data-urlencode "stack=$STACKURI" | jq --raw-output '.objects[] | .resource_uri'`
echo -e "\nService URI\n $SERVICEURI"

# Get Nodes URIs for containers associated with the SERVICEURI
declare -a NODEURIS
NODEURIS=`curl -s -H "Authorization: $DOCKERCLOUD_AUTH" -XGET "$URI/container/" -G --data-urlencode "service=$SERVICEURI" | jq --raw-output '.objects[] | .node' | sort | uniq`
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
EXISTINGIDS=`aws elbv2 describe-target-health --target-group-arn $ARN --region $REGION| jq --raw-output '.TargetHealthDescriptions[] | .Target.Id'`
echo -e "\nExisting IDs"
printf '%s\n' "${EXISTINGIDS[@]}"

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
echo -e "Comparing IDs\n"
for ID in ${!COMPARE[@]}; do
  echo "$ID : ${COMAPARE[$ID]}"
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
