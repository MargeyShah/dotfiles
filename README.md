# Scripts

Various scripts to automate tasks, simplify repetiive configuration, etc.

If running locally ensure `export AWS_DEFAULT_PROFILE=HULU_SSO` is set.

Handy links

* [Homebrew](https://brew.sh/)
* [sdkman](https://sdkman.io/sdks)
* [oh-my-zsh](https://ohmyz.sh/)
* [fzf](https://github.com/junegunn/fzf)
* [pyenv](https://github.com/pyenv/pyenv)
* [pipenv](https://pipenv.pypa.io/en/latest/)
* [Jfrog CLI](https://jfrog.com/getcli/)
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/#install-with-homebrew-on-macos)
* [devx-cli](https://dev.prod.hulu.com/mariner/devxcli?url=/docs/getting_started)
* [frogger](https://github.bamtech.co/JFrog/frogger)




<br/>

## Python handy .env
Place in the root of a python project with structure similar to below.
```
PYTHONPATH=${PYTHONPATH}:src/main/python:src/test/python
PYTHONDONTWRITEBYTECODE=1
```

## PyTest handy filtering
```
#Store in root of python project
[pytest]
junit_family = xunit2

filterwarnings =
    ignore:"@coroutine" decorator is deprecated since Python 3.8, use "async def" instead:DeprecationWarning
```