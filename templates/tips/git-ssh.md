ssh-keygen -t ed25519 -C "your_email@local.io"

To work with multiple ssh keys in multiple local repository 

you should set this in every local repository you have

``` 
git config core.sshCommand = ssh -i ~/.ssh/your_key
```