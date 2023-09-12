# Set PATH, MANPATH, etc., for Homebrew.
eval "$(/opt/homebrew/bin/brew shellenv)"
export VAULT_ADDR="https://secrets.staging.hulu.com"
export DOOZER_HOME=/Users/margey.shah/Documents/test/doozer

# Java configuration
export JAVA_HOME="/opt/homebrew/opt/openjdk@11"
export PATH="/Library/Frameworks/Python.framework/Versions/3.10/bin:/opt/homebrew/opt/openjdk@11/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk@11/bin:$PATH"

#Below is for compilers to be able to use maven"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk@11/include"

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

