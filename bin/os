#!/bin/bash 
: <<DOCXX
Determine OS name/type
Author: morgan.sziraki@gmail.com
DATE: Tue 10 Mar 2020 09:25:02 GMT
DOCXX
osName="$(uname -s)"
m="UNKNOWN"
case "${osName}" in
    CYGWIN*)    m=Cygwin;;
    Darwin*)    m=Mac;;
    Linux*)     m=Linux;;
    MINGW*)     m=MinGw;;
    *)          echo "${osName} returned from 'uname -s'" 2>&1
esac
echo ${m}
