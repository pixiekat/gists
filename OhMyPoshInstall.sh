echo "Installing 'Oh My Posh'..."
sudo wget https://www.github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
sudo chmod +x /usr/local/bin/oh-my-posh
echo "Oh My Posh installation complete. Version:"
oh-my-posh --version
