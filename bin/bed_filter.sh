#!/bin/bash

infile=$1
outfile=$2

paste -d '\t' - - < $infile | sed 's/-/_/g' | awk 'BEGIN {FS="\t"; OFS="\t"} {if ($1 > $7) {print substr($4,1,length($4)-2),$12,$7,$8,"16",$6,$1,$2,"8",$11,$5} else { print substr($4,1,length($4)-2),$6,$1,$2,"8",$12,$7,$8,"16",$5,$11} }' | tr '_+' '01' | awk 'NF==11' > $outfile
