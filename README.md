# Create your own Custom Signed Certificates

> ### With this script you can create the SSL certificates and configure a development machine to think it has a trusted CA signed certificate, but actually you are the CA.  

**NOTE: This is intended for development machines and/or training purposes only! For UAT and Production purposes it is strongly recommended to use certificates from a proper trusted public Certificate Authority or Domain certificates generated by the administrators of the relevant organization domain. Any other machine that does not have your custom CA root certificate in its certificate store will not trust your certificates.**  

Acknowledgement: the script was based on the following blog post, and their script was enhanced to make it easier to use.

https://deliciousbrains.com/ssl-certificate-authority-for-local-https-development/

## Create the certificates  

Before you run the script the first time, open up custom.cnf and set any defaults you want for the custom CA certificate. The values don't really matter too much as the only person seeing the values will be you the developer. Probably the key one is the Common Name as that will help identify the root certificate as yours, so maybe use a name like "MY NAME Developer CA".

The script uses openssl to create the certs, so you need to either run in on Linux or using Git Bash in Windows. The easiest way to install Git Bash on Windows is to install [Git for Windows](https://gitforwindows.org/).

### Script arguments  

To run the script, the only required argument is a domain and you can optionally specify an output directory. If you omit the output location, the script will create a sub-directory in the folder the script is run from, using the domain name and the date as the folder name.

Use the -h or --help argument to see the parameters and examples.

Typical example usage:
./create_ssl.sh --domain maps.example.com --san test.example.local,test.local

### Your own custom CA certificates

When you first run the script, it looks for existing CA files called "myCA.key" and "myCA.pem" which of course won't exist. So it will create them.

You will be prompted to create the private key file first and you will need to give it a password. Remember this password as you will need it in the subsequent steps.

It will then create a public key (the PEM file) and to do that it will ask you for the password of the private key created in the previous step.

These two files will be created in the same directory as the script. (And a myCA.srl file). Keep those files, as the next time you run the script it will just reuse them as the CA root certificate files to generate new certificates for your custom domains. You will also need the PEM file later on to import into the certificate store of your developer machine. If you were a real Certificate Authority then you would guard the myCA.key file carefully - if someone else stole that they could generate their own PEM file and pretend to be you. Which is bad. Very bad.  

You do want to re-use these custom CA certificates if you can, because it saves you having to reimport the PEM file into your developer machine(s) again. The script defaults the expiry date of your CA and domain certs to 20 years in the future so you shouldn't have to redo it for the same machine again.

Do remember the password to your myCA.key file, as if you use them to generate a different domain cert it will ask you for that password.

### Create your own custom domain certificate

Once it has created the CA certicates, it will proceed to generate and sign a certificate for you for the domain you requested. You can use any domain you want, but avoid any domain that your development machine will actually need to use such as google.com or microsoft.com etc. You can generate a wildcard certificate, but be aware that some use cases require the certificate to have the Subject Alternative Names for the machine it is running on. In that case, use the -s or --san command line argument to add one or more alternatives which typically will be the computer machine name. Tip: if the machine is not domain joined, add both the machine name and also the machine name with .local at the end. e.g. -s mypc,mypc.local

The script exports a pfx file that can be imported into IIS on Windows. The script will ask you to enter a password to protect the pfx file. This password has nothing to do with the CA key file password, and you will need to enter it when importing the pfx file on your developer machine.

That's it. Once the script finishes, grab the pfx file and the myCA.pem file. Copy them to your development machine somewhere.

## On your developer machine  

Open up the certificates utility for your local computer.  
Import the PEM into the Trusted Root Certification Authorities > Certificates folder.  
Import the pfx cert into the Personal > Certificates folder (you will require the pfx password).

Open up IIS, go to the Default Web Site and set the binding on port 443 to this newly imported certificate.

## Hosts file  

Finally, you can route requests to your domain URL to your local machine too. 

Edit the hosts file on that developer machine. Add an entry for your custom domain that resolves to either the static IP address if set or 127.0.0.1 which always resolves to the local machine.

**Example**  
```
127.0.0.1   maps.example.com
```

## Good to go!  
