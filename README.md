
# Introduction  
This blog is on how to standup a public docker registry on Digital Ocean using docker-machine.  Steps and examples are given below.  Everything can also be cloned from github.com/justsomedevnotes/docker-machine-digital-ocean-registry.

## Pre Requisits  
- Linux host (I used a vagrant box; vagrantfile included in the repository)
- DigitalOcean account
- docker-machine, docker-compose, and docker (All are setup with the vagrantfile from the repository

## Step 1: Setting the Environment  
Once you have a linux box setup and a digitalocean account, you need to retrieve your api token if you don't have it.  Login to your digitalocean account and select your Dashboard.  Select API and generate your token.  Copy this value and set it to an environment variable.  


$ export TOKEN=[token value]  
## Step 2: Create a Droplet  
There are various drivers you can use with docker-machine to provision a VM.  For this blog we are using the digitalocean driver.  It will provision a relatively small droplet.  Use the create docker-machine command giving it the driver, token, and a name for the instance.  

$ docker-machine create --driver digitalocean --digitalocean-access-token $TOKEN registry-01  

After the machine is created run the below command to set the machine environment.  

$ eval $(docker-machine env registry-01)

## Step 3: Update your /etc/hosts  
Since we are not registering our registry instance with a DNS server we need to just update the /etc/hosts file.  Get the IP of your droplet instance and add it to /etc/hosts.  

$ docker-machine ip [instance name]  

Add a line like the following to the /etc/hosts file replacing the ip with the one you received from above.  
107.123.104.184 registry.corp.local

## Step 4: Create Certificates  
In order to have a secure docker registry you need ssl certificates.  Since this blog is really over standing up a docker registry and not how to create ssl certificates I have provided a script that will create ssl certificates.  Place the ca.conf, server.conf, and create_ssl.sh below in a working directory.  Once you have them execute ./create_ssl.sh.  These can also be cloned from the github page.  Note: if you want to use a different domain you will need to modify the *.conf files DNS entry.  

ca.conf  
[req]
distinguished_name = req_distinguished_name
req_extensions  = v3_req
x509_extensions = v3_ca
prompt = no
[req_distinguished_name]
C = US
ST = SomeState
L = SomeCity
O = corp.local
OU = CA
CN =registry.corp.local
[v3_req]
keyUsage = keyEncipherment, dataEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = CA:true
[alt_names]
DNS.1 = registry.corp.local  

server.conf  
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = US
ST = SomeState
L = SomeCity
O = corp.local
OU = Docker
CN = registry.corp.local
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
basicConstraints = CA:FALSE
[alt_names]
DNS.1 = registry.corp.local  

create_ssl.sh  
#!/bin/bash
set -e

#create certs, auth, and data directories
rm -rf auth certs data
mkdir auth certs data
#generate private rsa key
openssl genrsa -out ca-privkey.pem 2048
#create the certificate from the key
openssl req -config ./ca.conf -new -x509 -key ca-privkey.pem \
     -out cacert.pem -days 365
#generate public keys
openssl req -config ./server.conf -newkey rsa:2048 -days 365 \
     -nodes -keyout server-key.pem -out server-req.pem
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 365 \
      -CA cacert.pem -CAkey ca-privkey.pem \
      -set_serial 01 -out server-cert.pem  \
      -extensions v3_req \
      -extfile server.conf

echo "INFO: print cacert.pem..."
openssl x509 -text -in cacert.pem -noout
echo "INFO: print server-req.pem..."
openssl req -text -in server-req.pem -noout
echo "INFO: print server-cert.pem..."
openssl x509 -text -in server-cert.pem -noout
openssl verify -verbose -CAfile ./cacert.pem server-cert.pem

echo "Info: copying keys to certs"
cp server-cert.pem certs/server.crt
cp server-key.pem certs/server.key

echo "INFO: resetting/updating local CA..."
sudo rm -f /usr/local/share/ca-certificates/cacert.crt
sudo update-ca-certificates --fresh

sudo cp cacert.pem /usr/local/share/ca-certificates/cacert.crt
sudo update-ca-certificates
echo "INFO: restarting docker"
sudo service docker restart

#add testuser for basic auth
echo "INFO: adding testuser"
docker run --entrypoint htpasswd registry:2 -Bbn testuser testpassword > auth/htpasswd  

$ ./create_ssl.sh  


## Step 5: Update files on the Droplet  
I use a docker-compose file to launch the registry which has some bind mounts to access the certificates.  We need to execute the following commands to copy over the auth, certs, and data directories to the droplet instance.  

$ docker-machine scp -r ./auth registry-01:/root/auth  
$ docker-machine scp -r ./certs registry-01:/root/certs  
$ docker-machine scp -r ./data registry-01:/root/data  

## Step 6: Start the Registry  
Copy the below contents to a docker-compose.yml file in your working directory and then execute the below command.  This file is also found in the github repo.  

docker-compose.yml  
version: '3'  
services:  
  registry:  
    restart: always  
    image: registry:2  
    ports:  
      - 443:443  
    environment:  
      REGISTRY_HTTP_ADDR: 0.0.0.0:443  
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/server.crt  
      REGISTRY_HTTP_TLS_KEY: /certs/server.key  
      REGISTRY_AUTH: htpasswd  
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd  
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm  
    volumes:  
      - "/root/data:/var/lib/registry"  
      - "/root/certs:/certs"  
      - "/root/auth:/auth"  

$ docker-compose up -d  

## Step 7: Test the Registry  
If everything is working you should be able to login and push an image to the registry.  A simple way to test this is to unset your local docker environment from the registry-01 droplet instance and use the local docker.  

$ eval $(docker-machine env -u)  
$ docker login registry.corp.local  
User: testuser  
password: testpassword  

$ docker pull busybox:latest  
$ docker tag busybox:latest registry.corp.local/busybox:0.9  
$ docker push registry.corp.local/busybox:0.9  


## Resources  

