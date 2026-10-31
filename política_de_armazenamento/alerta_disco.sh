#!/bin/bash
USO=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [ "$USO" -ge 80 ]; then
  echo "$(date): disco em ${USO}%" 
