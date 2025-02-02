[Why sign your commits ??](https://withblue.ink/2020/05/17/how-and-why-to-sign-git-commits.html)

# How to :

``` sudo apt install -y gnupg2 ```

``` gpg2 --full-generate-key ```

``` 
Input :

         9 - ECC (sign and encrypt) (default) 

         1 - Curve 25519 (default) 

         0 = key does not expire (default)

         You name that you use in git (gitlab|github ...), the one you used when you set git config user.name

         You email that you use in git (gitlab|github ...), the one you used when you set git config user.email

         You can add a comment to distinguish keys (optional) 
         
         For security reason you probably shoud set a passphrase on you gpg key so nobody can use it without the password
```

``` gpg2 --list-secret-keys --keyid-format LONG ```

Copy you gpg signature short code for example : 

<dl>
  <dt>Short code in red</dt>
  <dd>sec   rsa3072/<span style={{color:'red'}}>1a62BECsDE903888</span> 2020-12-07 [SC]</dd>
  <dd>XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX</dd>
  <dd>uid                 [ultimate] FirstName LastName (Comment) Email</dd>
  <dd>ssb   rsa3072/XXXXXXXXXXXXXXXXX 2020-12-07 [E]</dd>
</dl>

## Now save that short code, and go to your local git repo

```
Either go to your .git/config and past these
[gpg]
	program = /usr/bin/gpg2
[user]
	name = Takieddine Messaoudi
	email = takieddine.messaoudi.official@gmail.com
	signingKey = 1a62BECsDE903888
[commit]
	gpgSign = true

Or add them by command line
git config gpg.program /usr/bin/gpg2
git config user.signingKey 1a62BECsDE903888
... and continue with the others :)
```

## Now generate you public key : 

``` 
gpg2 --armor --export 1a62BECsDE903888 
copy the output and go to git provider/server (gitlab|github ...)
and add your public key in settings/gpg keys (it's usually where you add you ssh keys)
```

## Debugging
```
When you are having problems with gpg
try echo "test" | gpg2 --clearsign
if you have a problem this will tell you exactly what it is

In some cases you need to set ~/.gnupg/gpg.conf : 
use-agent 
pinentry-mode loopback

and set ~/.gnupg/gpg-agent.conf : 
allow-loopback-pinentry
```

## Optionnaly

If you want to upload your public key to keys.opengpg.org

```
gpg --send-keys 1a62BECsDE903888
```