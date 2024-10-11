#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

cd "$parent_path"

for d in ./*/ ; do (cd "$d" && echo "checking $d" && odin check . -vet-unused && echo ""); done
