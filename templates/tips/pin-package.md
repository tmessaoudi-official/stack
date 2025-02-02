sudo nano /etc/apt/preferences.d/focal-security.pref

Package: <package-name>
Pin: release n=focal-security
Pin-Priority: 990

sudo apt install -t focal-security <package-name>