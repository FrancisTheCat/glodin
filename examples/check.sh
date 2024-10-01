#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

cd "$parent_path"

echo "Checking shadows"
odin check shadows --show-timings
echo ""

echo "Checking instancing"
odin check instancing --show-timings
echo ""

echo "Checkingbloom "
odin check bloom --show-timings
echo ""

echo "Checking compute"
odin check compute --show-timings
echo ""

echo "Checking textured_cube"
odin check textured_cube --show-timings
echo ""

echo "Checking conway"
odin check conway --show-timings
echo ""

echo "Checking canvas"
odin check canvas --show-timings
echo ""

