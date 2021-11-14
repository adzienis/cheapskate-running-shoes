#!/bin/bash

diff_count=$(git diff index.html | xargs -0 echo | wc -w)

if [[ $diff_count -ne "0" ]]
then
  git add index.html && git commit -m "Automated update" && git push --force
fi

