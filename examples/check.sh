#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

cd "$parent_path"

for d in ./*/ ; do (echo "checking $d" && odin check $d -vet-unused && echo ""); done
