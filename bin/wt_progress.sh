#!/usr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Mon 11 May 2026 23:34:13 BST
DOCXX

{
    for ((i = 0 ; i <= 100 ; i+=5)); do
        sleep 0.1
        echo $i
    done
} | whiptail --gauge "Please wait while we are sleeping..." 6 50 0
