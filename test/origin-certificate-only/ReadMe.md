# Origin Certificate

This test is to test **only** the install of an origin certificate from Cloudflare.

* From : https://dash.cloudflare.com/ece0cae4e0feaf4b159db224b17773fd/screenshot.gd/ssl-tls/origin/certificate-form

Instructions on how to use them : https://developers.cloudflare.com/ssl/origin-configuration/origin-ca

## Create a Private Key for Age

```
$ age-keygen | age --passphrase --encrypt --armor > key.age

Public key: age1th2pmg67c0fpjdqgcjykjldyr8y0aq65u8djp3fz55mfz4n6jccs3vc356
Enter passphrase (leave empty to autogenerate a secure one): correct horse battery staple
Confirm passphrase: correct horse battery staple
```

Now you have a key to encrypt your certificates:

```
$ git add key.age
```

## PEM

First, generate and save to a plain text file the ASCII keys from the above Cloudflare page:

* apex.pem
* apex.key

Then, you'll need to encrypt the `private-key.txt`:

```
$ age --encrypt --recipient=age1th2pmg67c0fpjdqgcjykjldyr8y0aq65u8djp3fz55mfz4n6jccs3vc356 --armor --output=apex.key.age apex.key
```

You can now remove `apex.key` if you like, or back it up somewhere else. Also, check that you can decrypt `apex.key.age` properly.

```
$ age --decrypt --identity=key.age apex.key.age
```

(Remember to type "correct horse battery staple".)

```
$ git add apex.pem apex.key.age
$ git status

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	new file:   apex.key.age
	new file:   apex.pem
	new file:   key.age

```

Once checked in to git and deployed, `deployer.pl` will look for

(Ends)
