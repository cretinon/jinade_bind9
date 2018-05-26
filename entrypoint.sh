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
	domain)
	    echo "domain not defined"
	    ;;
	master_or_slave)
	    echo "need master -m or slave -s"
	    ;;
	master_and_slave)
	    echo "cant have both master -m and slave -s "
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

_set_env () {
    if _isnotdefined $DOMAIN ; then _usage "domain" ; return 1; fi
    if _notatleastonedefined $MASTER $SLAVE ; then _usage "master_or_slave" ; return 1; fi
    if _isbothdefined $MASTER $SLAVE ; then _usage "master_and_slave" ; return 1; fi

    GLUSTER_HOST1="gluster-1"
    GLUSTER_IP1="10.2.0.10"
    GLUSTER_HOST2="gluster-2"
    GLUSTER_IP2="10.2.0.11"
    
    GLUSTER_MOUNT="/mnt/gluster/"
    GLUSTER_SRC="$GLUSTER_IP1:/datastore"

    if _isdefined $MASTER ; then BIND_DIR="$ROOTFS/etc/bind/master" ; fi
    if _isdefined $SLAVE ; then BIND_DIR="$ROOTFS/etc/bind/slave" ; fi

    if _isdefined $MASTER ; then LOG_DIR="$ROOTFS/var/log/bind/master" ; fi
    if _isdefined $SLAVE ; then LOG_DIR="$ROOTFS/var/log/bind/slave" ; fi

    DATA_DIR="$ROOTFS/data"
    
    BIND_MASTER_IP="10.2.1.10"
    BIND_SLAVE_IP="10.2.1.11"

    DST_db_domain="$BIND_DIR/db."$DOMAIN
    
    DST_named_conf="$BIND_DIR/named.conf"
    DST_named_conf_local="$BIND_DIR/named.conf.local"
    DST_named_conf_log="$BIND_DIR/named.conf.log"
}

_init_jinade () {
    if _isnotdefined $GLUSTER_IP1 ; then _usage ${FUNCNAME[0]} ; exit 1; fi

    echo "$GLUSTER_IP1 $GLUSTER_HOST1" >> /etc/hosts
    echo "$GLUSTER_IP2 $GLUSTER_HOST2" >> /etc/hosts

    mkdir -p $GLUSTER_MOUNT
    mount -t glusterfs $GLUSTER_SRC $GLUSTER_MOUNT

    mkdir -p $BIND_DIR
    mkdir -p $DATA_DIR
}

_db_domain () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage ${FUNCNAME[0]} ; return 1; fi

    if _isdefined $MASTER ; then
	if _arenotbothdefined $NS1 $IPNS1 ; then _usage ${FUNCNAME[0]} ; return 1; fi
	
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

	fi
    fi

    chown bind:bind $BIND_DIR
    chmod 775 $BIND_DIR
    chown bind:bind $DST_db_domain
    
    _end_debug ${FUNCNAME[0]} $*
}

_dnssec_create_key () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _isnotdefined $DOMAIN ; then _usage ${FUNCNAME[0]} ; return 1; fi

    if _isdefined $MASTER ; then
	ls $DATA_DIR/Kadmin*.key 2> /dev/null
	RETURN=$?
	
	if [ $RETURN -eq 0 ]; then
	    cd $DATA_DIR
	    KEY_NAME=$(ls Kadmin*.key)
	    KEY_NAME=$(echo $KEY_NAME | sed -e 's/.key//g')
	    cd -
	    echo "WARNING Key already exist $KEY_NAME"
	else
	    cd $DATA_DIR
	    KEY_NAME=$(dnssec-keygen -a HMAC-SHA512 -b 512 -n USER admin.$DOMAIN)
	    echo $KEY_NAME
	    cd -
	fi
	
	SECRET=$(cat $DATA_DIR/$KEY_NAME.private | grep Key | awk '{print $2}')
	NAMED_CONF_KEY="key admin.$DOMAIN {
    algorithm HMAC-SHA512;
    secret \"$SECRET\";
};"
    fi
    
    _end_debug ${FUNCNAME[0]} $*
}

_named_conf () {
    _start_debug ${FUNCNAME[0]} $*

    if _notatleastonedefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi
    if _isbothdefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi

    cat <<EOF > $DST_named_conf
include "/etc/bind/named.conf.options";
include "$BIND_DIR/named.conf.local";
include "/etc/bind/named.conf.default-zones";
EOF
    
    chown root:bind $DST_named_conf
    
    _end_debug ${FUNCNAME[0]} $*
}

_named_conf_local () {
    _start_debug ${FUNCNAME[0]} $*
    
    if _notatleastonedefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi
    if _isbothdefined $MASTER $SLAVE ; then _usage ${FUNCNAME[0]} ; return 1; fi

    if _isdefined $MASTER ; then
	cat <<EOF > $DST_named_conf_local
include "/etc/bind/zones.rfc1918";
include "$BIND_DIR/named.conf.log";
zone "$DOMAIN" {
        type master;
        file "$BIND_DIR/db.$DOMAIN";
        allow-transfer {$BIND_SLAVE_IP;};
        update-policy  { grant admin.$DOMAIN zonesub TXT; };
};
$NAMED_CONF_KEY
EOF
    fi

    if _isdefined $SLAVE ; then
	cat <<EOF > $DST_named_conf_local
include "/etc/bind/zones.rfc1918";
include "$BIND_DIR/named.conf.log";
zone "$DOMAIN" {
        type slave;
        file "/$BIND_DIR/db.$DOMAIN";
        masters {$BIND_MASTER_IP;};
};
EOF
    fi
    
    chown root:bind $DST_named_conf_local
    
    _end_debug ${FUNCNAME[0]} $*
}

_named_conf_log () {
    _start_debug ${FUNCNAME[0]} $*

    mkdir -p $LOG_DIR
    touch $LOG_DIR/update_debug.log
    touch $LOG_DIR/security_info.log
    touch $LOG_DIR/bind.log
    chown bind:bind $LOG_DIR
    chown bind:bind $LOG_DIR/*

    cat <<EOF > $DST_named_conf_log
logging {
        channel update_debug {
                file "$LOG_DIR/update_debug.log" versions 3 size 100k;
                severity debug;
                print-severity  yes;
                print-time      yes;
        };
        channel security_info {
                file "$LOG_DIR/security_info.log" versions 1 size 100k;
                severity info;
                print-severity  yes;
                print-time      yes;
        };
        channel bind_log {
                file "$LOG_DIR/bind.log" versions 3 size 1m;
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
    
    KEY_NAME=$(ls $DATA_DIR/Kadmin*.key)
    if _fileexist $KEY_NAME ; then
	nsupdate -k $KEY_NAME $DATA_DIR/nsupdate.txt
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

    cat << EOF > $DATA_DIR/nsupdate.txt
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

    cat << EOF > $DATA_DIR/nsupdate.txt
server 127.0.0.1
zone $DOMAIN
update delete $HOST NS
update add $HOST IN NS $ADDR"
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
    
    cat << EOF > $DATA_DIR/nsupdate.txt
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
    SHORT=vcd:msu:rjh:a:
    LONG=ns1:,ns2:,ipns1:,ipns2:,mx1:,mx2:,run,update,verbose,test,host:,addr:,update:

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
	    -h | --host)
		HOST="$2"
		shift 2
		;;
	    -a | --addr)
		ADDR="$2"
		shift 2
		;;
	    -j)
		JINADE="yes"
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
    #have to wait gluster-net attached to this container before anything else
    sleep 5
    _start_debug ${FUNCNAME[0]} $*
    
    [ -z "$1" ] && _usage && return
    if _startswith "$1" '-'; then
	_process "$@"

	if _isdefined $JINADE ; then
	    ROOTFS="/mnt/gluster/bind"
	    _set_env
	    _init_jinade
	fi
		
	if _isdefined $CREATE ; then
	    _set_env
	    _db_domain \
		&& _dnssec_create_key \
		&& _named_conf \
		&& _named_conf_local \
		&& _named_conf_log
	fi

	if _isdefined $UPDATE ; then
	    _set_env
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
	    /usr/sbin/named -u bind -c $BIND_DIR/named.conf
	    tail -f $LOG_DIR/*.log
	fi
	
    else
	"$@"
    fi

    _end_debug ${FUNCNAME[0]} $*
}

# set initial values / do not edit, use args !
VERBOSE=false
ROOTFS=""


# go !
main "$@"

# of course everything is fine
exit 0
