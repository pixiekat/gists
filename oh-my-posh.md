# Oh My Posh Install/Update

Basic script to install and update oh-my-posh, adopted and forked from [BraINstinct0](https://gist.github.com/BraINstinct0/7624d58eee2917267e6f1ba79571dd90).

## Install

```bash
echo "Installing 'Oh My Posh'..."
sudo wget https://www.github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
sudo chmod +x /usr/local/bin/oh-my-posh
echo "Oh My Posh installation complete. Version:"
oh-my-posh --version
```

## Update

```bash
#!/bin/bash

if [[ ! $(command -v jq) ]]; then
        echo "Jq command not found; install with apt install jq"
        exit 1
fi

remote_repo="https://github.com/JanDeDobbeleer/oh-my-posh.git"
latest_tag=$(curl -sSL https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest | jq -r '.tag_name')
current_version=$(oh-my-posh --version)
echo "Current version of 'Oh My Posh': v$current_version"
echo "Latest version of 'Oh My Posh': $latest_tag"

if [[ "$latest_tag" == "v$current_version" ]]; then
        echo "Nothing to update..."
        exit 1
fi

read -p "Do you want to update? (y/n): " answer

if [[ $answer =~ ^[Yy]$ ]]; then
        echo "Continuing..."
        sudo wget https://www.github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
        sudo chmod +x /usr/local/bin/oh-my-posh
        echo "Oh My Posh updated to following version:"
        oh-my-posh --version
else
        echo "Aborting..."
        exit 1
fi
```
