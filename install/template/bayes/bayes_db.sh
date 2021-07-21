#!/bin/bash
fileid="1Sw0n6UxgE6hKXfdxB_vN8S22_4FY44xt"
filename="bayes.txt"
curl -c ./cookie -s -L "https://drive.google.com/uc?export=download&id=${fileid}" > /dev/null
curl -Lb ./cookie "https://drive.google.com/uc?export=download&confirm=`awk '/download/ {print $NF}' ./cookie`&id=${fileid}" -o /opt/template/bayes/${filename}
