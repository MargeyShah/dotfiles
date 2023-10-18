#!/bin/bash
# Used with a directory structure where you have a top level folder named anything, and subdirectories in it
# named after the original jenkins instance the jobs were from, and in each of these instance folders
# you would have a folder for each job with a config.xml file in it.
# Will need to create root level folder "migrated_jobs" in the new jenkins instance with nested folders named after 
# the old instance folder names
# Replace these variables with your Jenkins URL, username, and password
JENKINS_URL="https://jenkins-url.global.twdcgrid.net/"
JENKINS_USER=""
# Ideally an API key
JENKINS_PASS=""

# Path to the jenkins-cli.jar
JENKINS_CLI_JAR="/jenkins-cli.jar"

# Root directory where the directory structure starts 
ROOT_DIR="~/jobs_to_migrate"

# Find all config.xml files in the lowest level directories
find "$ROOT_DIR" -type f -name "config.xml" | while read config_xml; do
    # Extract the directory containing config.xml
    dir_path=$(dirname "$config_xml")
    
    # Extract instance name from the path
    instance_name=$(basename "$(dirname "$dir_path")")
    
    # Extract job name from the path
    job_name=$(basename "$dir_path")
    
    # Generate the Jenkins job name by concatenating instance and job name
    jenkins_job_name="migrated_jobs/${instance_name}/${job_name}"
    
    # Create the Jenkins job using jenkins-cli.jar
    java -jar "$JENKINS_CLI_JAR" -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" -webSocket create-job "$jenkins_job_name" < "$config_xml"
    
    echo "Created job: $jenkins_job_name"
done
