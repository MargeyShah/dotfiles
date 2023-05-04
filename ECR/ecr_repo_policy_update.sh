#!/bin/bash

REGION=us-west-2
repos=$(aws --profile HULU_SSO ecr describe-repositories --query 'repositories[*].{name:repositoryName}' --region $REGION --output text)

for repo in $repos
do
    aws --profile HULU_SSO --no-cli-pager ecr set-repository-policy --region $REGION --repository-name $repo --policy-text file://policy.json 
   # echo $repo
done
