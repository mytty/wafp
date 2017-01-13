#!/bin/bash
###
# this script extracts the products/fingerprints from the db
# to a bunch of files - each file containing the fps for one
# version of a product.
###

if [ "X$1" != "X" ] ; then
  filter="WHERE name LIKE \"$1\""
else
  filter=""
fi

wafp_fp_db="../fprints_wafp.db"

rm -rf /tmp/wafp_computed_fps/
mkdir /tmp/wafp_computed_fps/

sqlite3 $wafp_fp_db "SELECT DISTINCT * FROM tbl_product $filter" |
while read i ; do
  product_id=`echo $i | awk -F'|' '{ print $1 }'`
  product=`echo $i | awk -F'|' '{ print $2 }'`
  versionstring=`echo $i | awk -F'|' '{ print $3 }'`
  timestamp=`echo $i | awk -F'|' '{ print $4 }'`
  info=`echo $i | awk -F'|' '{ print $5 }'`
  echo "-- NEW_PRODUCT - START" > /tmp/wafp_computed_fps/${timestamp}___${product}___${versionstring}.fp
  echo "INSERT INTO tbl_product VALUES(NULL, \"$product\", \"$versionstring\", \"$timestamp\", \"$info\")" >> /tmp/wafp_computed_fps/${timestamp}___${product}___${versionstring}.fp
  sqlite3 $wafp_fp_db "SELECT * FROM tbl_fprint WHERE product_id = $product_id" |
  while read n ; do
    csum=`echo $n | awk -F'|' '{ print $3 }'`
    path=`echo $n | awk -F'|' '{ print $4 }'`
    echo "INSERT INTO tbl_fprint VALUES(NULL, PRODUCT_ID, \"$csum\", \"$path\")" >> /tmp/wafp_computed_fps/${timestamp}___${product}___${versionstring}.fp
  done
  bzip2 /tmp/wafp_computed_fps/${timestamp}___${product}___${versionstring}.fp
done
