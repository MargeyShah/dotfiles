#!/bin/bash

# Function to update remote URLs in a Git repository
update_remote_urls() {
    repo_path="$1"
    old_domain="$2"
    new_domain="$3"
    dry_run="$4"
    
    cd "$repo_path" || return
    
    # Check if the current directory is a Git repository
    if [ -d ".git" ]; then
        remotes=$(git remote)
        
        for remote in $remotes; do
            url=$(git remote get-url "$remote")
            if [[ $url == *"$old_domain"* ]]; then
                new_remote_url="${url//$old_domain/$new_domain}"
                if [ "$dry_run" = true ]; then
                    echo "Would update remote URL for '$repo_path' from '$url' to '$new_remote_url'"
                else
                    git remote set-url "$remote" "$new_remote_url"
                    echo "Updated remote URL for '$repo_path' from '$url' to '$new_remote_url'"
                fi
            fi
        done
    fi
    
    cd - > /dev/null || return
}

# Function to recursively update remote URLs in a folder and its subfolders
update_remote_urls_recursive() {
    folder_path="$1"
    old_domain="$2"
    new_domain="$3"
    dry_run="$4"
    
    for item in "$folder_path"/*; do
        if [ -d "$item" ]; then
            update_remote_urls "$item" "$old_domain" "$new_domain" "$dry_run"
            update_remote_urls_recursive "$item" "$old_domain" "$new_domain" "$dry_run"
        fi
    done
}

# Main script
if [ $# -lt 3 ]; then
    echo "Usage: $0 folder_path old_domain new_domain [--dry-run]"
    exit 1
fi

folder_path="$1"
old_domain="$2"
new_domain="$3"
dry_run=false

if [ $# -eq 4 ] && [ "$4" = "--dry-run" ]; then
    dry_run=true
fi

update_remote_urls_recursive "$folder_path" "$old_domain" "$new_domain" "$dry_run"
