Old Method : 

sudo apt-key list
sudo apt-key adv --refresh-keys
sudo apt-key adv --keyserver hkps://keyserver.ubuntu.com --refresh-keys

# With fingerprint
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 690951F1A4DE0F905496E8C6C793BFA2FA577F07
sudo apt-key export 690951F1A4DE0F905496E8C6C793BFA2FA577F07 | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/my-package-name.gpg

# With key file
curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_20.04/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/podman-archive.gpg

# /etc/apt/sources.list.d/my-package-name.list
deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/my-package-name.gpg arch=amd64] http://ppa.xxxx.xxxx focal main


New Method : 

sudo mkdir -p /etc/apt/keyrings 
sudo gpg --no-default-keyring --keyring /etc/apt/keyrings/bruno.gpg --keyserver keyserver.ubuntu.com --recv-keys 9FA6017ECABE0266 

echo "deb [trusted=yes signed-by=/etc/apt/keyrings/bruno.gpg] http://debian.usebruno.com/ bruno stable" | sudo tee /etc/apt/sources.list.d/bruno.list 