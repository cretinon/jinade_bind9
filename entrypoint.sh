#!/bin/bash

_start_debug () {
    if [ $VERBOSE = "true" ]; then echo "start" $* ; fi
}

_end_debug () {
    if [ $VERBOSE = "true" ]; then echo "end" $* ; fi
}

_usage () {
    case $1 in
	_db_domain | _named_conf_local | _dnssec_create_key)
	    echo "./`basename $0`" "-c -d domain.net -m/-s (master/slave) --ns1 ns1_hostname --ipns1 a.b.c.d"
	;;
	*)
	    echo "create new bind config files : ./`basename $0`" "-c -d domain.net -m/-s (master/slave) --ns1 ns1_hostname --ipns1 a.b.c.d"
	    echo "run                          : ./`basename $0`" "-r"
	    ;;
    esac
}

_test () {
    _start_debug ${FUNCNAME[0]} $*
    
    echo "this is a test"
    
    _end_debug ${FUNCNAME[0]} $*
}

_startswith() {
    _str="$1"
    _sub="$2"
    echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}

_isdefined () {
    if [ -z ${1+x} ]; then return 1; else return 0; fi
}

_isnotdefined () {
    if [ -z ${1+x} ]; then return 0; else return 1; fi
}

_isbothdefined () {
    if _isdefined $1 && _isdefined $2 ; then return 0; else return 1; fi
}

_arenotbothdefined () {
    if _isdefined $1 && _isdefined $2 ; then return 1; else return 0; fi
}

_notatleastonedefined () {
    if _isdefined $1 || _isdefined $2 ; then return 1; else return 0; fi
}

_fileexist () {
    if [ -e $1 ]; then return 0; else return 1; fi
}

_filenotexist () {
    if [ -e $1 ]; then return 1; else return 0; fi
}

_init_jinade () {
    WORKDIR="/mnt/gluster/bind"
    echo "10.2.0.10 gluster-1" >> /etc/hosts
    echo "10.2.0.11 gluster-2" >> /etc/hosts

    mkdir -p /mnt/gluster/
    mount -t glusterfs 10.2.0.10:/datastore /mnt/gluster/
    mkdir -p $WORKDIR
}

_db_domain () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage ${FUNCNAME[0]} ; return 1; fi
    if _arenotbothdefined $NS1 $IPNS1 ; then _usage ${FUNCNAME[0]} ; return 1; fi

    DST_db_domain="/etc/bind/db."$DOMAIN

    if _filenotexist $DST_db_domain ; then
	cat << EOF > $DST_db_domain
\$TTL    3600
@       IN      SOA     $NS1.$DOMAIN. admin.$DOMAIN. (
                1                    ; Serial
                3600                 ; Refresh [1h]
                600                  ; Retry   [10m]
                86400                ; Expire  [1d]
                3600 )               ; Negative Cache TTL [1h]
;

@       IN      NS         $NS1.$DOMAIN.
$NS1    IN      A          $IPNS1
EOF

	chown root:bind /etc/bind
	chmod 775 /etc/bind
	chown root:bind $DST_db_domain
    fi
    
    _end_debug ${FUNCNAME[0]} $*
}

_dnssec_create_key () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage ${FUNCNAME[0]} ; return 1; fi

    ls $WORKDIR/Kadmin*.key 2> /dev/null
    RETURN=$?

    if [ $RETURN -eq 0 ]; then
	cd $WORKDIR
	KEY_NAME=$(ls Kadmin*.key)
	KEY_NAME=$(echo $KEY_NAME | sed -e 's/.key//g')
	cd -
	echo "WARNING Key already exist $KEY_NAME"
    else
	cd $WORKDIR/
	KEY_NAME=$(dnssec-keygen -a HMAC-SHA512 -b 512 -n USER admin.$DOMAIN)
	echo $KEY_NAME
	cd -
    fi

    SECRET=$(cat $WORKDIR/$KEY_NAME.private | grep Key | awk '{print $2}')
    NAMED_CONF_KEY="key admin.$DOMAIN {
    algorithm HMAC-SHA512;
    secret \"$SECRET\";
};"
    _end_debug ${FUNCNAME[0]} $*
}

_named_conf_local () {
    _start_debug ${FUNCNAME[0]} $*
    
    # Todo Allow transfert
    if _notatleastonedefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi
    if _isbothdefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi

    if _isdefined $MASTER ; then
	cat <<EOF > $DST_named_conf_local
include "/etc/bind/zones.rfc1918";
include "/etc/bind/named.conf.log";
zone "$DOMAIN" {
        type master;
        file "/etc/bind/db.$DOMAIN";
        $ALLOW_TRANSFERT
        update-policy  { grant admin.$DOMAIN zonesub TXT; };
};
$NAMED_CONF_KEY
EOF
    fi

    if _isdefined $SLAVE ; then
	# Todo case slave
	echo toto
    fi
    
    chown root:bind $DST_named_conf_local
    
    _end_debug ${FUNCNAME[0]} $*
}

_named_conf_log () {
    _start_debug ${FUNCNAME[0]} $*
    
    mkdir -p /var/log/bind/
    touch /var/log/bind/update_debug.log
    touch /var/log/bind/security_info.log
    touch /var/log/bind/bind.log
    chown bind:bind /var/log/bind/
    chown bind:bind /var/log/bind/*
    
    cat <<EOF > $DST_named_conf_log
logging {
        channel update_debug {
                file "/var/log/bind/update_debug.log" versions 3 size 100k;
                severity debug;
                print-severity  yes;
                print-time      yes;
        };
        channel security_info {
                file "/var/log/bind/security_info.log" versions 1 size 100k;
                severity info;
                print-severity  yes;
                print-time      yes;
        };
        channel bind_log {
                file "/var/log/bind/bind.log" versions 3 size 1m;
                severity info;
                print-category  yes;
                print-severity  yes;
                print-time      yes;
        };

        category default { bind_log; };
        category lame-servers { null; };
        category update { update_debug; };
        category update-security { update_debug; };
        category security { security_info; };
};
EOF
    
    _end_debug ${FUNCNAME[0]} $*
}

_nsupdate () {
    _start_debug ${FUNCNAME[0]} $*
    
    KEY_NAME=$(ls $WORKDIR/Kadmin*.key)
    if _fileexist $KEY_NAME ; then
	nsupdate -k $KEY_NAME $WORKDIR/nsupdate.txt
	#rm -rf /data/nsupdate.txt
    else
	echo "ERROR not KEY"
	exit 1
    fi
    
    _end_debug ${FUNCNAME[0]} $*
}


_nsupdate_add_a () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage; return 1; fi
    if _arenotbothdefined $HOST $ADDR ; then _usage; return 1; fi

    cat << EOF > $WORKDIR/nsupdate.txt
server 127.0.0.1
zone $DOMAIN
update delete $HOST A
update add $HOST IN A $ADDR"
send
quit 
EOF

    _nsupdate

    _end_debug ${FUNCNAME[0]} $*
}

_nsupdate_add_ns () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage; return 1; fi
    if _arenotbothdefined $HOST $ADDR ; then _usage; return 1; fi

    cat << EOF > $WORKDIR/nsupdate.txt
server 127.0.0.1
zone $DOMAIN
update delete $HOST A
update add $HOST IN A $ADDR"
send
quit 
EOF

    _nsupdate

    _end_debug ${FUNCNAME[0]} $*
}

_nsupdate_add_cname () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage; return 1; fi
    if _arenotbothdefined $CNAME $HOST ; then _usage; return 1; fi
    
    cat << EOF > $WORKDIR/nsupdate.txt
server 127.0.0.1
zone $DOMAIN
update delete $CNAME
update add $CNAME 600 IN      CNAME   $HOST"
send
quit 
EOF

    _nsupdate
    
    _end_debug ${FUNCNAME[0]} $*
}

_nsupdate_add_txt () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage; return 1; fi
    if _arenotbothdefined $CNAME $TXT ; then _usage; return 1; fi
    
    cat << EOF > $WORKDIR/nsupdate.txt
server 127.0.0.1
zone $DOMAIN
update delete $CNAME.
update add $CNAME. 60 IN TXT "$TXT"
send
quit 
EOF

    _nsupdate

    _end_debug ${FUNCNAME[0]} $*
}



_process () {
    _start_debug ${FUNCNAME[0]} $*
    
    # Option strings
    SHORT=vcd:msrj
    LONG=ns1:,ns2:,ipns1:,ipns2:,mx1:,mx2:,run,update,verbose,test

    # read the options
    OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")

    if [ $? != 0 ] ; then _usage >&2 ; exit 1 ; fi

    eval set -- "$OPTS"

    # extract options and their arguments into variables.
    while true ; do
	case "$1" in
	    -r | --run)
		RUN="yes"
		ACTION="RUN"
		shift
		;;
	    -c | --create)
		CREATE="yes"
		ACTION="CREATE"
		shift
		;;
	    -u | --update)
		UPDATE="yes"
		ACTION="UPDATE"
		TARGET=$2
		shift 2
		;;
	    
            -d)
		DOMAIN="$2"
		shift 2
		;;
	    -m)
		MASTER="yes"
		shift
		;;
	    -s)
		SLAVE="yes"
		shift
		;;
	    --ns1)
		NS1="$2"
		shift 2
		;;
	    --ipns1)
		IPNS1="$2"
		shift 2
		;;
	    -j)
		_init_jinade
		shift
		;;

	    -v | --verbose )
		VERBOSE=true
		shift
		;;
	    -t | --test )
		shift
		;;
	    -- )
		shift
		break
		;;
	    *)
		_usage
		exit 1
		;;
	esac
    done
    
    _end_debug ${FUNCNAME[0]} $*
}

main() {
    _start_debug ${FUNCNAME[0]} $*
    
    [ -z "$1" ] && _usage && return
    if _startswith "$1" '-'; then
	_process "$@"

	if _isdefined $CREATE ; then
	    _db_domain \
		&& _dnssec_create_key \
		&& _named_conf_local \
		&& _named_conf_log
	fi

	if _isdefined $UPDATE ; then
	    case $TARGET in
		A)
		    _nsupdate_add_a
		    ;;
		NS)
		    _nsupdate_add_ns
		    ;;
		TXT)
		    _nsupdate_add_txt
		    ;;
		CNAME)
		    _nsupdate_add_cname
		    ;;
		*)
		    _usage
		    exit 1
		    ;;
	    esac
	fi

	if _isdefined $RUN ; then
	    /usr/sbin/named -u bind
	    tail -f /var/log/bind/*.log
	fi
	
    else
	"$@"
    fi

    _end_debug ${FUNCNAME[0]} $*
}

# set initial values
VERBOSE=false
WORKDIR="/data"
DST_named_conf_local="/etc/bind/named.conf.local"
DST_named_conf_log="/etc/bind/named.conf.log"

main "$@"

exit 0
