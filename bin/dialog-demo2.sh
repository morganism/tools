#!/usr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Mon 11 May 2026 23:23:28 BST
DOCXX

set -e

DIALOG=dialog
TMP=$(mktemp -d)
LOG="$TMP/tail.log"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

run_dialog() {
  local title="$1"
  shift

  exec 3>&1
  RESULT=$("$@" 2>&1 1>&3)
  RC=$?
  exec 3>&-

  $DIALOG --msgbox \
"RESULT DISPLAY

Dialog: $title
Exit code: $RC
Output:
${RESULT:-<no output>}" \
  12 70
}

# ------------------------------------------------------------
$DIALOG --msgbox "dialog DEMO\n\nEach dialog shows its returned value." 10 60

# yesno
run_dialog "yesno" \
  $DIALOG --yesno "Do you want to continue?" 8 40

# msgbox
run_dialog "msgbox" \
  $DIALOG --msgbox "This is a message box." 8 40

# infobox
$DIALOG --infobox "This is an infobox (3s)" 6 40
sleep 3
$DIALOG --msgbox "infobox\n(no return value)" 8 40

# inputbox
run_dialog "inputbox" \
  $DIALOG --inputbox "Enter some text:" 8 40

# passwordbox
run_dialog "passwordbox" \
  $DIALOG --passwordbox "Enter a password:" 8 40

# menu
run_dialog "menu" \
  $DIALOG --menu "Choose an option:" 12 50 4 \
    1 "Option one" \
    2 "Option two" \
    3 "Option three"

# radiolist
run_dialog "radiolist" \
  $DIALOG --radiolist "Choose ONE item:" 12 50 4 \
    A "Alpha" ON \
    B "Beta" OFF \
    C "Gamma" OFF

# checklist
run_dialog "checklist" \
  $DIALOG --checklist "Choose MULTIPLE items:" 12 50 4 \
    A "Alpha" OFF \
    B "Beta" ON \
    C "Gamma" OFF

# inputmenu
run_dialog "inputmenu" \
  $DIALOG --inputmenu "Edit values:" 12 60 4 \
    1 "Hostname" "localhost" \
    2 "Port" "8080"

# form
run_dialog "form" \
  $DIALOG --form "Enter form values:" 12 60 4 \
    "Name:"  1 1 "" 1 15 20 0 \
    "Email:" 2 1 "" 2 15 30 0

# mixedform
run_dialog "mixedform" \
  $DIALOG --mixedform "Mixed form:" 12 60 4 \
    "Username:" 1 1 "" 1 15 20 0 0 \
    "Password:" 2 1 "" 2 15 20 0 1

# passwordform
run_dialog "passwordform" \
  $DIALOG --passwordform "Password form:" 12 60 2 \
    "User:" 1 1 "" 1 15 20 0 \
    "Pass:" 2 1 "" 2 15 20 0

# calendar
run_dialog "calendar" \
  $DIALOG --calendar "Select a date:" 0 0

# timebox
run_dialog "timebox" \
  $DIALOG --timebox "Select a time:" 0 0

# dselect
run_dialog "dselect" \
  $DIALOG --dselect "$HOME/" 12 60

# fselect
run_dialog "fselect" \
  $DIALOG --fselect "$HOME/" 12 60

# textbox
echo -e "Textbox demo\n\nScrollable content\nLine 4\nLine 5" > "$TMP/text.txt"
run_dialog "textbox" \
  $DIALOG --textbox "$TMP/text.txt" 12 60

# editbox
run_dialog "editbox" \
  $DIALOG --editbox "$TMP/text.txt" 12 60

# gauge (no return value)
(
  for i in $(seq 0 10 100); do
    echo "$i"
    sleep 0.2
  done
) | $DIALOG --gauge "Gauge running…" 8 40 0
$DIALOG --msgbox "gauge\n(no return value)" 8 40

# mixedgauge (no return value)
(
  echo "XXX"
  echo "40"
  echo "Working..."
  echo "XXX"
  sleep 1
  echo "XXX"
  echo "100"
  echo "Done"
  echo "XXX"
) | $DIALOG --mixedgauge "Mixed gauge" 10 50 0
$DIALOG --msgbox "mixedgauge\n(no return value)" 8 40

# progressbox
(
  for i in {1..5}; do
    echo "Processing step $i"
    sleep 0.4
  done
) | $DIALOG --progressbox "Progress output…" 12 60
$DIALOG --msgbox "progressbox\n(output streamed only)" 8 50

# tailbox
touch "$LOG"
(
  for i in {1..5}; do
    echo "Log line $i" >> "$LOG"
    sleep 0.4
  done
) &
run_dialog "tailbox" \
  $DIALOG --tailbox "$LOG" 12 60

# tailboxbg
(
  for i in {6..10}; do
    echo "BG log line $i" >> "$LOG"
    sleep 0.4
  done
) &
$DIALOG --tailboxbg "$LOG" 12 60
sleep 3
$DIALOG --msgbox "tailboxbg\n(background only)" 8 50

# pause
run_dialog "pause" \
  $DIALOG --pause "Final pause dialog…" 10 50 5

$DIALOG --msgbox "Demo complete.\n\nAll selections displayed." 10 60
clear
