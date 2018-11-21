#!/usr/bin/env bash


find ../roles/ -name vars -type d | while read dir; do
  cd ${dir}
  ln -sf ../../../vars/global.yml main.yml
  cd - &>/dev/null
done

