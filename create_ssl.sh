#!/bin/bash
set -e

# create certs, auth, and data directories
rm -rf auth certs data
mkdir auth certs data
# generate private rsa key
openssl genrsa -out ca-privkey.pem 2048
# create the certificate from the key
openssl req -config ./ca.conf -new -x509 -key ca-privkey.pem \
     -out cacert.pem -days 365
# generate public keys
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

# add testuser for basic auth
echo "INFO: adding testuser"
docker run --entrypoint htpasswd registry:2 -Bbn testuser testpassword > auth/htpasswd