#!/bin/bash

for f in `find . -regex ".*\.sh"`; do
  sed -i -e '1s/^\.\.\.//' $f
  fsync $f
done
sed -i -e '1s/^\.\.\.//' common/common.env
sed -i -e '1s/^\.\.\.//' common/functions
fsync common/common.env
fsync common/functions