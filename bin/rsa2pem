#!/bin/bash
#
# https://github.com/morganism
# Tue  5 Mar 2019 00:47:12 GMT

RSA_KEY=$1
PEM_KEY=${RSA_KEY}.pem

openssl rsa -in ${RSA_KEY} -outform pem > $PEM_KEY
chmod 600 $PEM_KEY
