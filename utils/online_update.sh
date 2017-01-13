#!/bin/bash
###
# this script performs an online update of the wafp fp db.
###

if [ -e /tmp/wafp_`basename ${0} .sh`.pid ] ; then
  echo "ERROR: The PID file (/tmp/wafp_`basename ${0} .sh`.pid) is already present!"
  echo "ERROR: You should not run multiple instances of this script on the same DB at the same time!"
  echo "ERROR: If this is wrong you can just delete the PID file by hand and retry execution..."
  exit 0
fi

echo $$ > /tmp/wafp_`basename ${0} .sh`.pid

wafp_fp_db="../fprints_wafp.db"
update_site="http://208.111.34.127/wafp_update"
update_list="wafp_fp.lst.bz2"
update_source="$update_site/wafp_fps"

function rmpid() {
  rm -f /tmp/wafp_`basename ${0} .sh`.pid
}

function usage() {
  echo "USAGE: $0 --update|--show"
  echo "--"
  echo " --update  updates your local database from the online repository."
  echo " --show    shows which fingerprints would be updated."
  rmpid
  exit 0
}

if [ "X$1" = "X" ] ; then
  usage
fi

sql=`which sqlite3 2>/dev/null`
fnd=`which find 2>/dev/null`
ak=`which awk 2>/dev/null`
sd=`which sed 2>/dev/null`
bz2=`which bunzip2 2>/dev/null`
wg=`which wget 2>/dev/null`

if [ "X$sql" = "X" ] ; then
  echo "ERROR: SQLite3 binary not found in PATH!"
  rmpid
  exit 0
fi
if [ "X$bz2" = "X" ] ; then
  echo "ERROR: BunZip2 binary not found in PATH!"
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
if [ "X$wg" = "X" ] ; then
  echo "ERROR: WGet binary not found in PATH!"
  rmpid
  exit 0
fi

if [ "X$1" != "X--show" ] && [ "X$1" != "X--update" ] ; then
  usage
fi

# collecting the local db fprints...
rm -f /tmp/wafp_fp_local.lst
for i in `$sql $wafp_fp_db "SELECT DISTINCT timestamp, name, versionstring FROM tbl_product ASC"` ; do
  echo $i >> /tmp/wafp_fp_local.lst
done

# fetching the latest fprint repository
rm -f /tmp/wafp_fp.lst
rm -f /tmp/wafp_fp.lst.bz2
$wg -O /tmp/wafp_fp.lst.bz2 $update_site/$update_list
$bz2 -v /tmp/wafp_fp.lst.bz2

cnt=`diff /tmp/wafp_fp.lst /tmp/wafp_fp_local.lst | grep -E '^<' | awk '{ print $2 }' | wc -l`
if [ $cnt -eq 0 ] ; then
  echo ""
  echo -e "\033[4mNothing to be done, you are up-to-date! ;)\033[0m"
  rmpid
  exit 0
fi

if [ "X$1" = "X--show" ] ; then
  echo ""
  echo -e "\033[1mThe following FingerPrints would be installed:\033[0m"
  sleep 1;
  diff /tmp/wafp_fp.lst /tmp/wafp_fp_local.lst | grep -E '^<' | awk '{ print $2 }'
  rmpid
  exit 0
fi

# fetching new fps...
echo ""
echo -e "\033[1mDownloading latest FingerPrints:\033[0m"
sleep 1;
rm -rf /tmp/wafp_fps
mkdir /tmp/wafp_fps
for i in `diff /tmp/wafp_fp.lst /tmp/wafp_fp_local.lst | grep -E '^<' | awk '{ print $2 }'` ; do
  $wg -O /tmp/wafp_fps/`echo $i | $sd s/\|/___/g`.fp.bz2 $update_source/`echo $i | $sd s/\|/___/g`.fp.bz2
done

echo ""
echo -e "\033[1mUnpacking downloaded FingerPrints:\033[0m"
for i in `ls /tmp/wafp_fps/*.bz2` ; do 
  $bz2 -v $i
done

echo ""
echo -e "\033[1mAdding FingerPrints to your local database:\033[0m"
# adding the newly downloaded fps to the db
for i in `ls /tmp/wafp_fps/*.fp` ; do
  echo "adding: `basename $i .fp`"
  ./generate_wafp_fingerprint.sh $i IMPORT
done

rmpid
