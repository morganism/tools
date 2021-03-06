#!/bin/bash

ts=`date +%Y%m%d%H%M%S`

FILE=$1
if [ -f $FILE ]; then
  echo "cp $FILE ${FILE}.bak.$ts"
  cp $FILE ${FILE}.bak.$ts
  exit 0
fi

echo "FILE  $FILE does not exists."
exit 1
