#!/bin/bash

#goal: check if everything needed by project exists.
# edge goal: set env variable for different tools, so scripts can then
#   use the env variable locations, versus each tool having to hunt.
#   also detect if interactive, so it can be sourced.

if [[ $- != *i* ]] ; then
	#insert non-interactive steps here
else
	#insert interactive steps here
fi
