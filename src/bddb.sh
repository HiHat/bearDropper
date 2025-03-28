#!/bin/sh
# shellcheck disable=SC2046,SC2006,SC2086,SC2162,SC3043,SC2155,SC1090,SC2166,SC1101,SC2034
#
# bearDropper DB - storage routines for ultralight IP/status/epoch storage
# GNU AFFERO GENERAL PUBLIC LICENSE Version 3 # https://www.gnu.org/licenses/agpl-3.0.html
#
# A BDDB record format is: bddb_$IPADDR=$STATE,$TIME[,$TIME...]
#
# Where: IPADDR has periods replaced with underscores
#        TIME is in epoch-seconds
#
# A BDDB record has one of three STATES:
#   bddb_1_2_3_4=-1                            (whitelisted IP or network)
#   bddb_1_2_3_4=0,1452332535[,1452332536...]  (tracked, but not banned)
#   bddb_1_2_3_4=1,1452332535                  (banned, time=effective ban start)
#
# BDDB records exist in RAM usually, but using bddbSave & bddbLoad, they are 
# written on (ram)disk with optional compression 
#
# Partially implemented is IPADDR being in CIDR format, with a fifth octet
# at the end, being the mask.  Ex: bddb_192_168_1_0_24=....
#
# TBD: finish CIDR support, add lookup/match routines
#
# _BEGIN_MEAT_
ip2raw () { echo "$1" | sed 's|/|m|;s/\./_/g;s/:/i/g'; }

raw2ip () { echo "$1" | sed 's/=.*//;s/^bddb_//;s|m|/|;s/_/./g;s/i/:/g'; }

# Clear bddb entries from environment
bddbClear () { 
  local bddbVar
  for bddbVar in `set | grep -E '^bddb_[0-9a-f_im]*=' | cut -f1 -d= | xargs echo -n` ; do eval unset $bddbVar ; done
  bddbStateChange=1
}

# Returns count of unique IP entries in environment
bddbCount () { set | grep -c '^bddb_[0-9a-f_im]*=' ; }

# Loads existing bddb file into environment
# Arg: $1 = file, $2 = type (bddb/bddbz), $3 = 
bddbLoad () { 
  local loadFile="$1.$2"
  if [ "$2" = bddb -a -f "$loadFile" ] ; then
    . "$loadFile"
  elif [ "$2" = bddbz -a -f "$loadFile" ] ; then
    local tmpFile="`mktemp`"
    zcat $loadFile > "$tmpFile"
    . "$tmpFile"
    rm -f "$tmpFile"
  fi
  bddbStateChange=0
}

# Saves environment bddb entries to file, Arg: $1 = file to save in
bddbSave () { 
  local saveFile="$1.$2"
  if [ "$2" = bddb ] ; then
    set | grep '^bddb_[0-9a-f_im]*=' | sed s/\'//g > "$saveFile"
  elif [ "$2" = bddbz ] ; then
    set | grep -E '^bddb_[0-9a-f_im]*=' | sed s/\'//g | gzip -c > "$saveFile"
  fi
  bddbStateChange=0 
}

# Set bddb record status=1, update ban time flag with newest
# Args: $1=IP Address $2=timeFlag
bddbEnableStatus () {
  local record=bddb_`ip2raw $1`
  local newestTime=`bddbGetTimes $1 | sed 's/.*,//' | xargs echo $2 | tr \  '\n' | sort -n | tail -1 `
  eval $record="1,$newestTime"
  bddbStateChange=1
}

# Args: $1=IP Address
bddbGetStatus () {
  bddbGetRecord $1 | cut -d, -f1
}

# Args: $1=IP Address
bddbGetTimes () {
  bddbGetRecord $1 | cut -d, -f2-
}

# Args: $1 = IP address, $2 [$3 ...] = timestamp (seconds since epoch)
bddbAddRecord () {
  local ip="`ip2raw $1`" status=''
  shift
  [ "$1" -lt 2 ] && { status="$1"; shift; }
  [ -z "$status" ] && status="`eval echo \\\$bddb_$ip | cut -f1 -d,`"
  local newEpochList="$*"
  local oldEpochList="`eval echo \\\$bddb_$ip | cut -f2- -d,  | tr , \ `" 
  local epochList=`echo $oldEpochList $newEpochList | xargs -n 1 echo | sort -un | xargs echo -n | tr \  ,`
  [ -z "$status" ] && status=0
  eval "bddb_$ip"=\"$status,$epochList\"
  bddbStateChange=1
}

# Args: $1 = IP address
bddbRemoveRecord () {
  eval unset bddb_`ip2raw $1`
  bddbStateChange=1
}

# Returns all IPs (not CIDR) present in records
bddbGetAllIPs () { 
  local ipRaw record
  set | grep '^bddb_[0-9a-f_im]*=' | tr \' \  | while read record ; do
    raw2ip "$record"
  done
}

# retrieve single IP record, Args: $1=IP
bddbGetRecord () {
  local record=bddb_`ip2raw $1`
  eval echo \$$record
}
# _END_MEAT_
#
# Test routines
#

# Dump bddb from environment for debugging 
bddbDump () { 
  local ip ipRaw status times time record
  set | grep '^bddb_[0-9a-f_im]*='  | tr -d \' | while read record ; do
    ip=`raw2ip $record`
    status=`echo $record | cut -f2 -d= | cut -f1 -d,`
    echo $record | cut -f2 -d= | cut -f2- -d, | while read time; do
      printf 'IP (%s) (%s): %s\n' "$ip" "$status" "$time" ;
    done
    # times=`echo $record | cut -f2 -d= | cut -f2- -d,`
    # for time in `echo $times | tr , \ ` ; do printf 'IP (%s) (%s): %s\n' "$ip" "$status" "$time" ; done
  done
} 

bddbFilePrefix=/tmp/bddbtest
#bddbFileType=bddbz
bddbFileType=bddb

echo seeding
bddbAddRecord 2.3.4.5 1442000000
bddbAddRecord 10.0.1.0/24 -1
bddbAddRecord 64.242.113.77 0 1442000000 1442001000 1442002000
bddbAddRecord 2001:470:27:48d::2 1 1442000000 1442001000 1442002000

echo saving
bddbSave "$bddbFilePrefix" "$bddbFileType"

echo environment has `bddbCount` entries, clearing and dumping
bddbClear ; bddbDump

echo environment has `bddbCount` entries

echo loading
bddbClear 
bddbLoad "$bddbFilePrefix" "$bddbFileType"

echo loaded `bddbCount` entries, dumping
bddbDump

echo creating a new record \(1.2.3.4\)
bddbAddRecord 1.2.3.4 1440001234

echo adding to an existing record \(2.3.4.5\)
bddbAddRecord 2.3.4.5 1442000001 1441999999 

echo adding to an existing record \(64.242.113.77\)
bddbAddRecord 64.242.113.77 1441999999 1442999999 1442001050

echo saving and dumping
bddbSave "$bddbFilePrefix" "$bddbFileType"
bddbDump

echo clearing and dumping
bddbClear ; bddbDump

echo loading and dumping
bddbClear 
bddbLoad "$bddbFilePrefix" "$bddbFileType"
echo bddbEnableStatus 64.242.113.77
bddbEnableStatus 64.242.113.77
bddbDump
echo bddbRemoveRecord 2.3.4.5
bddbRemoveRecord 2.3.4.5
bddbDump

echo removing file
echo rm "$bddbFilePrefix.$bddbFileType"
