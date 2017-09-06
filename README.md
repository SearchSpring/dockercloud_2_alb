# Dockercloud 2 ALB

## Description
  For a given service, this container will find all of the host nodes that run containers for that service and update a AWS ALB target group with the AWS ids of those host nodes.  It will also remove any ids of host nodes that are not currently running containers for that service.

## Instructions
  For use on Dockercloud, make sure to specify the role global in your stack file
```yaml
  roles:
    - global
```

  Also ensure that this container runs on a node that has access via an AWS role to update the target group you want to use with this container

  Define the SERVICE, STACK and PORT used by your service.  Additionally define the ARN of the target group you want to update.