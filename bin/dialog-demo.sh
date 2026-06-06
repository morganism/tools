#!/usr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Mon 11 May 2026 23:19:44 BST
DOCXX

set -e

DIALOG=dialog
TMP=$(mktemp -d)
LOG="$TMP/tail.log"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

pause_between() {
  $DIALOG --pause "Press OK to continue to the next dialog…" 8 50 2
}

# ------------------------------------------------------------
$DIALOG --msgbox "dialog DEMO\n\nThis script demonstrates most dialog types." 10 50
pause_between

# yesno
$DIALOG --yesno "Do you want to continue?" 8 40
pause_between

# msgbox
$DIALOG --msgbox "This is a message box." 8 40
pause_between

# infobox
$DIALOG --infobox "This is an infobox.\n(Disappears after 3s)" 6 40
sleep 3
pause_between

# inputbox
$DIALOG --inputbox "Enter some text:" 8 40
pause_between

# passwordbox
$DIALOG --passwordbox "Enter a password:" 8 40
pause_between

# menu
$DIALOG --menu "Choose an option:" 12 50 4 \
  1 "Option one" \
  2 "Option two" \
  3 "Option three"
pause_between

# radiolist
$DIALOG --radiolist "Choose ONE item:" 12 50 4 \
  A "Alpha" ON \
  B "Beta" OFF \
  C "Gamma" OFF
pause_between

# checklist
$DIALOG --checklist "Choose MULTIPLE items:" 12 50 4 \
  A "Alpha" OFF \
  B "Beta" ON \
  C "Gamma" OFF
pause_between

# inputmenu
$DIALOG --inputmenu "Edit values:" 12 60 4 \
  1 "Hostname" "localhost" \
  2 "Port" "8080"
pause_between

# form
$DIALOG --form "Enter form values:" 12 60 4 \
  "Name:"     1 1 "" 1 15 20 0 \
  "Email:"    2 1 "" 2 15 30 0
pause_between

# mixedform
$DIALOG --mixedform "Mixed form:" 12 60 4 \
  "Username:" 1 1 "" 1 15 20 0 0 \
  "Password:" 2 1 "" 2 15 20 0 1
pause_between

# passwordform
$DIALOG --passwordform "Password form:" 12 60 2 \
  "User:" 1 1 "" 1 15 20 0 \
  "Pass:" 2 1 "" 2 15 20 0
pause_between

# calendar
$DIALOG --calendar "Select a date:" 0 0
pause_between

# timebox
$DIALOG --timebox "Select a time:" 0 0
pause_between

# dselect
$DIALOG --dselect "$HOME/" 12 60
pause_between

# fselect
$DIALOG --fselect "$HOME/" 12 60
pause_between

# textbox
echo -e "This is a textbox.\n\nScrollable text.\nLine 4\nLine 5\nLine 6" > "$TMP/text.txt"
$DIALOG --textbox "$TMP/text.txt" 12 60
pause_between

# editbox
$DIALOG --editbox "$TMP/text.txt" 12 60
pause_between

# gauge
(
  for i in $(seq 0 10 100); do
    echo $i
    sleep 0.2
  done
) | $DIALOG --gauge "Gauge progress…" 8 40 0
pause_between

# mixedgauge
(
  echo "XXX"
  echo "30"
  echo "Downloading..."
  echo "XXX"
  sleep 1
  echo "XXX"
  echo "60"
  echo "Processing..."
  echo "XXX"
  sleep 1
  echo "XXX"
  echo "100"
  echo "Done"
  echo "XXX"
) | $DIALOG --mixedgauge "Mixed gauge" 10 50 0
pause_between

# progressbox
(
  for i in {1..5}; do
    echo "Processing step $i"
    sleep 0.5
  done
) | $DIALOG --progressbox "Progress output…" 12 60
pause_between

# tailbox / tailboxbg
touch "$LOG"
(
  for i in {1..5}; do
    echo "Log line $i" >> "$LOG"
    sleep 0.5
  done
) &

$DIALOG --tailbox "$LOG" 12 60
pause_between

(
  for i in {6..10}; do
    echo "BG log line $i" >> "$LOG"
    sleep 0.5
  done
) &

$DIALOG --tailboxbg "$LOG" 12 60
sleep 3
pause_between

# pause
$DIALOG --pause "Final pause dialog…" 10 50 5

# done
$DIALOG --msgbox "Demo complete.\n\nAll dialog types shown." 10 50
clear
