# Source - https://stackoverflow.com/q/6928946
# Posted by hmontoliu, modified by community. See post 'Timeline' for change history
# Retrieved 2026-02-27, License - CC BY-SA 3.0

# Copyright (c): Hilario J. Montoliu <hmontoliu@gmail.com>
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.  See http://www.gnu.org/copyleft/gpl.html for
# the full text of the license.

set -o errtrace
trap 'traperror $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]})'  ERR

traperror () {
    local err=$1 # error status
    local line=$2 # LINENO
    local linecallfunc=$3 
    local command="$4"
    local funcstack="$5"
    echo "<---"
    echo "ERROR: line $line - command '$command' exited with status: $err" 
    if [ "$funcstack" != "::" ]; then
        echo -n "   ... Error at ${funcstack} "
        if [ "$linecallfunc" != "" ]; then
            echo -n "called at line $linecallfunc"
        fi
        else
            echo -n "   ... internal debug info from function ${FUNCNAME} (line $linecallfunc)"
    fi
    echo
    echo "--->" 
    }

somefunction () {
    asdfasdf param1
    }

somefunction

echo foo

