#!/bin/bash
#
# Setup Bind (Named) 'hidden' Master (no DNSec), with public secondaries.
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2012
#

## Configuration
SLAVES='8.8.8.8; 8.8.8.8;'
SOA_HOSTNAME='ns1.example.com'

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start

# Install base packages
yum -y install bind-chroot
yum -y install bind-utils

# turn on services
chkconfig named on

# Configure Named
rmdir /var/named/data/ /var/named/slaves/
mkdir -p /var/named/chroot/var/named/dynamic
chown named:named /var/named/chroot/var/named/dynamic

cp -arn /usr/share/doc/bind-*/sample/var/named/* /var/named/chroot/var/named/

# Our configuration loosely based on /usr/share/doc/bind-*/sample/etc/named.conf 
cat > /var/named/chroot/etc/named.conf << EOF
options
{
        // Put files that named is allowed to write in the data/ directory:
        directory               "/var/named";           // "Working" directory
        dump-file               "data/cache_dump.db";
        statistics-file         "data/named_stats.txt";
        memstatistics-file      "data/named_mem_stats.txt";

        /*
          Specify listenning interfaces. You can use list of addresses (';' is
          delimiter) or keywords "any"/"none"
        */
        listen-on port 53     { any; };
        listen-on-v6 port 53  { any; };

        /*
          Access restrictions

          There are two important options:
            allow-query { argument; };
              - allow queries for authoritative data

            allow-query-cache { argument; };
              - allow queries for non-authoritative data (mostly cached data)

          You can use address, network address or keywords "any"/"localhost"/"none" as argument
          Examples:
            allow-query { localhost; 10.0.0.1; 192.168.1.0/8; };
            allow-query-cache { ::1; fe80::5c63:a8ff:fe2f:4526; 10.0.0.1; };
        */

        allow-query             { any; };
        allow-query-cache       { localhost; };

        // Enable/disable recursion - recursion yes/no;
        recursion no;

        // Our secondaries (public masters)
        allow-transfer { ${SLAVES} };
        also-notify { ${SLAVES} };

        /* DNSSEC related options. See information about keys ("Trusted keys", bellow) */

        /* Enable serving of DNSSEC related data - enable on both authoritative
           and recursive servers DNSSEC aware servers */
        dnssec-enable no;

        /* Enable DNSSEC validation on recursive servers */
        dnssec-validation yes;

        /* Enable DLV by default, use built-in ISC DLV key. */
        dnssec-lookaside auto;
};

logging
{
/*      If you want to enable debugging, eg. using the 'rndc trace' command,
 *      named will try to write the 'named.run' file in the $directory (/var/named).
 *      By default, SELinux policy does not allow named to modify the /var/named directory,
 *      so put the default debug log file in data/ :
 */
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

/*
 Views let a name server answer a DNS query differently depending on who is asking.

 By default, if named.conf contains no "view" clauses, all zones are in the
 "default" view, which matches all clients.

 Views are processed sequentially. The first match is used so the last view should
 match "any" - it's fallback and the most restricted view.

 If named.conf contains any "view" clause, then all zones MUST be in a view.
*/
view "external"
{
/* This view will contain zones you want to serve only to "external" clients
 * that have addresses that are not match any above view:
 */
        match-clients           { any; };

        zone "." IN {
                type hint;
                file "/var/named/named.ca";
        };

        recursion no;
        // you'd probably want to deny recursion to external clients, so you don't
        // end up providing free DNS service to all takers

        // These are your "authoritative" external zones, and would probably
        // contain entries for just your web and mail servers:

        include "/etc/named-zones.conf";
};
EOF

# Example of how to include a zone
if [ ! -f /var/named/chroot/etc/named-zones.conf ]; then
cat > /var/named/chroot/etc/named-zones.conf << EOF
// zone "example.com" { type master; file "/var/named/data/example.com.zone";  };
EOF
fi

# Example zone config
cat > /var/named/chroot/var/named/data/example.com.zone << EOF
$TTL 38400      ; 10 hours 40 minutes
example.com.    IN SOA  ${SOA_HOSTNAME}. hostmaster.example.com. (
                                2012020101 ; serial
                                10800      ; refresh (3 hours)
                                3600       ; retry (1 hour)
                                604800     ; expire (1 week)
                                38400      ; minimum (10 hours 40 minutes)
                                )

example.com.                            IN      NS      ${SOA_HOSTNAME}.
example.com.                            IN      NS      ns2.example.com.

example.com.                            IN      A       8.8.8.8
www.example.com.                        IN      A       8.8.8.8

mail.example.com.                       IN      A       8.8.8.8
example.com.                            IN      MX      10 mail.example.com.

EOF

# Start / Restart
service named restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
