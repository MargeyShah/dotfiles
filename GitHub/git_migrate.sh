#!/bin/sh
# This script takes two github orgs, 1st is source github org, 2nd is dest github org.
# It will clone all repos in source org and migrate it into the test org.
if [ "$#" -ne 2 ]; then 
    echo "Error: two arguments required (source org and dest org)"
    exit 1
fi

export GH_HOST=github.bamtech.co


SOURCE_ORG=$1
DEST_ORG=$2 

SOURCE_GH=github.bamtech.co
DEST_GH=github.disneystreaming.com

# Can add a grep in here to only migrate repos with a keyword
repo_list=$(gh repo list $SOURCE_ORG --no-archived -L 250 | awk NF=1 | cut -d"/"  -f2)
prefix="$SOURCE_ORG/"

for i in $repo_list
do
    git clone --bare git@$SOURCE_GH:$SOURCE_ORG/${i#"$prefix"}.git
    cd ${i#"$prefix"}.git
    export GH_HOST=$DEST_GH
    gh repo create $DEST_ORG/${i#"$prefix"} --public
    git push --mirror git@$DEST_GH:$DEST_ORG/${i#"$prefix"}.git
    export GH_HOST=$SOURCE_GH
    gh repo archive $SOURCE_ORG/${i#"$prefix"}
    cd ~/scripts/GitHub
     
done
