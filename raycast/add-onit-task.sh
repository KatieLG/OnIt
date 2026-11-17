#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add OnIt Task
# @raycast.mode silent
# @raycast.packageName OnIt
# @raycast.icon 📌

# Optional parameters:
# @raycast.argument1 { "type": "text", "placeholder": "Task @board !size #tag" }

encoded=$(printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9_.~-])/sprintf("%%%02X", ord($1))/ge')
open -g "onit://add?text=${encoded}"
