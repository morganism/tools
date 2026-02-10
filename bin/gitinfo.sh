#!/USr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Fri 30 Jan 2026 05:51:41 GMT
DOCXX

source ~/.include.function

source version.sh

__GIT_COMMIT() { git rev-parse --short HEAD 2>/dev/null || echo "unknown"; }
__GIT_TAG()    { git describe --tags --dirty --always 2>/dev/null || echo "unreleased"; }
__GIT_DATE()   { git show -s --format=%cs HEAD 2>/dev/null || echo "unknown"; }
__GIT_AUTHOR() { git show -s --format='%an <%ae>' HEAD 2>/dev/null || echo "unknown"; }
__GIT_AUTHOR_NAME() { git show -s --format='%an' HEAD 2>/dev/null || echo "unknown"; } # just the name
__GIT_FILE_AUTHOR() { git log -1 --format='%an <%ae>' -- "$0" 2>/dev/null || echo "unknown"; } # who last touched 


AUTHOR="$(__GIT_AUTHOR)"
VERSION="$(__GIT_TAG)"
COMMIT="$(__GIT_COMMIT)"
BUILD_DATE="$(__GIT_DATE)"

echo "$VERSION $COMMIT $AUTHOR"
