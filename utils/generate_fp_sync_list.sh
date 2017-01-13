#!/bin/bash
###
# this script generates the sync list which is to be placed on
# a wafp update server.
###

sql=`which sqlite3 2>/dev/null`
bz2=`which bzip2 2>/dev/null`

if [ "X$sql" = "X" ] ; then
  echo "ERROR: SQLite3 binary not found in PATH!"
  exit 0
fi
if [ "X$bz2" = "X" ] ; then
  echo "ERROR: BZip2 binary not found in PATH!"
  exit 0
fi

wafp_fp_db="../fprints_wafp.db"

$sql $wafp_fp_db "SELECT DISTINCT timestamp, name, versionstring FROM tbl_product ASC" > wafp_fp.lst
$bz2 -v wafp_fp.lst
