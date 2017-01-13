#!/bin/bash
###
# this is generate_wafp_fingerprint
# it can be used to generate fingerprints
# of webapps, to export them and, oh yeah, to import them.
###
# its meant to be used with WAFP
###
# alpha4 - internal only!
# by richard sammet (e-axe)
###

if [ ! -e i_read_README.generate_wafp_fingerprint ] ; then
  echo "PLEASE READ \"README.generate_wafp_fingerprint\" BEFORE USING THIS SCRIPT!"
  exit 0
fi

if [ -e /tmp/wafp_`basename ${0} .sh`.pid ] ; then
  echo "ERROR: The PID file (/tmp/wafp_`basename ${0} .sh`.pid) is already present!"
  echo "ERROR: You should not run multiple instances of this script on the same DB at the same time!"
  echo "ERROR: If this is wrong you can just delete the PID file by hand and retry execution..."
  exit 0
fi

echo $$ > /tmp/wafp_`basename ${0} .sh`.pid

if [ "X$1" == "X" ] ; then
  echo "USAGE: $0 APPLICATION_PATH|FINGERPRINT_FILE [EXPORT|IMPORT]"
  exit 0
fi

function rmpid() {
  rm -f /tmp/wafp_`basename ${0} .sh`.pid
}

# all the other stuff should always be there...

sql=`which sqlite3 2>/dev/null`
fnd=`which find 2>/dev/null`
ak=`which awk 2>/dev/null`
sd=`which sed 2>/dev/null`

if [ "X$sql" = "X" ] ; then
  echo "ERROR: SQLite3 binary not found in PATH!"
  rmpid
  exit 0
fi
if [ "X$fnd" = "X" ] ; then
  echo "ERROR: Find binary not found in PATH!"
  rmpid
  exit 0
fi
if [ "X$ak" = "X" ] ; then
  echo "ERROR: AWK binary not found in PATH!"
  rmpid
  exit 0
fi
if [ "X$sd" = "X" ] ; then
  echo "ERROR: SED binary not found in PATH!"
  rmpid
  exit 0
fi

cur_pwd=`pwd`
wafp_fp_db="../fprints_wafp.db"

mnext=0
if [ "X$2" == "XIMPORT" ] ; then
  if [ -e $1 ] ; then
    while read LINE ; do
      if `echo $LINE | grep -q -E '^\-\- NEW_PRODUCT \- START'` ; then
        mnext=1
        continue
      fi
      if [ $mnext -eq 1 ] ; then
        mnext=0
        version=`echo -n $LINE | $ak -F'"' '{ print $4 }'`
        product=`echo -n $LINE | $ak -F'"' '{ print $2 }'`
        timestamp=`echo -n $LINE | $ak -F'"' '{ print $6 }'`
        info=`echo -n $LINE | $ak -F'"' '{ print $8 }'`
        $sql $cur_pwd/$wafp_fp_db "INSERT INTO tbl_product VALUES(NULL, \"$product\", \"$version\", \"$timestamp\", \"$info\")"
        product_id=`$sql $cur_pwd/$wafp_fp_db "SELECT id FROM tbl_product WHERE name = \"$product\" AND versionstring = \"$version\" LIMIT 1"`
        continue
      fi
      qryp=`echo -n $LINE | $sd s/PRODUCT_ID/$product_id/`
      $sql $cur_pwd/$wafp_fp_db "$qryp"
    done < $1
    rmpid
    exit 0
  else
    echo "FINGERPRINT_FILE($1) not found."
    rmpid
    exit 0
  fi
fi

if [ -e $1 ] ; then

  product=`basename  $1 | $ak -F'-' '{ print $1 }'`
  version=`basename  $1 | $sd s/"^[^\-]\+\-"/""/g`
  timestamp=`date +%s`
  info="not used, yet."

  if [ "X$2" == "XEXPORT" ] ; then
    echo "-- NEW_PRODUCT - START"
    echo "INSERT INTO tbl_product VALUES(NULL, \"$product\", \"$version\", \"$timestamp\", \"$info\")"
    product_id="PRODUCT_ID"
  else
    $sql $wafp_fp_db "INSERT INTO tbl_product VALUES(NULL, \"$product\", \"$version\", \"$timestamp\", \"$info\")"
    product_id=`$sql $wafp_fp_db "SELECT id FROM tbl_product WHERE name = \"$product\" AND versionstring = \"$version\" LIMIT 1"`
  fi

  if [ "X$2" != "XEXPORT" ] ; then
    echo "switching to $1";
  fi
  cd $1;

  file_list=`find ./ -iname '*\.png' -or -iname '*\.gif' -or -iname '*\.jpg' -or -iname '*\.jpeg' -or -iname '*\.html' -or -iname '*\.js' -or -iname '*\.xml' -or -iname '*\.swf' -or -iname '*\.txt' -or -iname '*\.css' -or -iname '*\.htm' -or -iname '*\.xhtml' -or -iname '*\.pdf' -or -name '*LICENSE*' -or -name '*READ*' -or -name '*INSTALL*' -or -iname '*\.tpl' -or -iname '*\.ico' -or -iname '*\.tmpl'`

  for i in $file_list ; do
    tcsumstr=`md5sum $i | $ak '{ print $1,"|",$2 }' | $sd s/" "/""/g`
    tcsum=`echo $tcsumstr | $ak -F'|' '{ print $1 }'`
    tpath=`echo $tcsumstr | $ak -F'|' '{ print $2 }'`
    if [ "X$2" == "XEXPORT" ] ; then
      echo "INSERT INTO tbl_fprint VALUES(NULL, $product_id, \"$tcsum\", \"$tpath\")"
    else
      $sql $cur_pwd/$wafp_fp_db "INSERT INTO tbl_fprint VALUES(NULL, $product_id, \"$tcsum\", \"$tpath\")"
    fi
  done

  if [ "X$2" != "XEXPORT" ] ; then
    echo "switching back to $cur_pwd";
  fi
  cd $cur_pwd;

  else

  if [ "X$2" != "XEXPORT" ] ; then
    echo "no such directory: $1"
  fi

fi

rmpid
