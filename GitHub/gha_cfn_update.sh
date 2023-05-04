#!/bin/bash
if [ "$1" == "" ]; then
   echo "usage: pass in a cfn name query such as a prefix as the only argument"
   exit
fi

stacks="$(aws cloudformation describe-stacks --region us-east-1 --query "Stacks[?contains(StackName, '$1')].StackName" --output text)"

for s in $stacks; do
  echo $s
done
