#!/bin/bash

dir=$(dirname "$scriptpath")
cd "$dir" || exit


git archive --prefix=PlanetsLib_1.10.2/ -o PlanetsLib_1.10.2.zip HEAD
