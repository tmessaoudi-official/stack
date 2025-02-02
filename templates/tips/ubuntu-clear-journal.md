show journal disc usage : journalctl --disk-usage

sudo journalctl --rotate
sudo journalctl --vacuum-time=2days
sudo journalctl --vacuum-size=100M
sudo journalctl --vacuum-files=5