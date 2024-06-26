#! /bin/sh
# the next line restarts using tclsh8.6 on unix \
if type tclsh8.6 > /dev/null 2>&1 ; then exec tclsh8.6 "$0" ${1+"$@"} ; fi
# the next line restarts using tclsh \
if type tclsh > /dev/null 2>&1 ; then exec tclsh "$0" ${1+"$@"} ; fi
# the next line complains about a missing wish \
echo "This software requires Tcl/Tk 8.6 to run." ; \
exit 1

# settings
set dhcpTemplateFileIn  dhcpd.conf.tmpl.in

proc usage {} {
    global argv0
    puts stderr "$argv0 \\"
    puts stderr "--ipv4networkaddr=IPv4 Network Address \\"
    puts stderr "--netmask=Netmask \\"
    puts stderr "--broadcast=Broadcast Address \\"
    puts stderr "--defaultrouter=Default outer Address \\"
    puts stderr "--domain=Domain Name \\"
    puts stderr "--dnsservers=DNS Servers \\"

}

proc getIPv6Netaddr {ipv6addr} {
    set ipv6addr [split $ipv6addr {:}]
    set buf {}
    if {[llength $ipv6addr] != 8} {
        foreach i $ipv6addr {
            if {[string equal {} $i]} {
                for {set j} {$j < [expr 8 - [llength $ipv6addr]]} {incr j} {
                    lappend buf "0000"
                }
            } else {
                lappend buf $i
            }
        }
        set ipv6addr $buf
    }
    return "[join [lrange $ipv6addr 0 3] {:}]:"
}

proc findIPv4NetworkAddresses {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr $err
                exit 1
            }
            if {![regexp {\s+inet ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])) netmask 0x([f0]{8}) broadcast} $err _ ipv4netaddr _ _ _ netmask]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $netmask {
                ff000000 {
                    set ipv4netaddr "[lindex [split $ipv4netaddr {.}] 0].0.0.0"
                }
                ffff0000 {
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 1] {.}].0.0"
                }
                ffffff00 {
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 2] {.}].0"
                }
                default {
                    puts stderr "Does not support CIDR Address"
                    exit
                }
            }
        }
        Linux {
            if {[catch [list exec ip a | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))/(8|16|24) brd ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))\s} $err _ ipv4netaddr _ _ _ prefix _]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $prefix {
                8 {
                    set ipv4netaddr "[lindex [split $ipv4netaddr {.}] 0].0.0.0"
                }
                16 {
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 1] {.}].0.0"
                }
                24 {
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 2] {.}].0"
                }
                default {
                    puts stderr "Does not support CIDR Address"
                    exit 1
                }
            }
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
        }
    }
    return $ipv4netaddr
}

proc findIPv4Netmask {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr $err
                exit 1
            }
            if {![regexp {\s+inet .+ netmask 0x([f0]{8}) broadcast} $err _ netmask]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $netmask {
                ff000000 {
                    set netmask 255.0.0.0
                }
                ffff0000 {
                    set netmask 255.255.0.0
                }
                ffffff00 {
                    set netmask 255.255.255.0
                }
                default {
                    puts stderr "Does not support CIDR Address."
                    exit 1
                }
            }
        }
        Linux {
            if {[catch [list exec ip a | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet .+/(8|16|24) brd\s} $err _ prefix]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $prefix {
                8 {
                    set netmask 255.0.0.0
                }
                16 {
                    set netmask 255.255.0.0
                }
                24 {
                    set netmask 255.255.255.0
                }
                default {
                    puts stderr "Does not support CIDR Address."
                    exit 1
                }
            }
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
        }
    }
    return $netmask
}

proc findIPv4Broadcast {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr $err
                exit 1
            }
            if {![regexp {\s+inet .+ broadcast ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))} $err _  broadcast]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
        }
        Linux {
            if {[catch [list exec ip a | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet .+ brd ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))\s} $err _ broadcast]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
        }
    }
    return $broadcast
}

proc findIPv6NetworkAddresses {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet6 } | grep -v {inet6 fe80:} | grep -v {inet6 ::1}] err]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![regexp {\s+inet6 ([0-9A-Fa-f]{1,4}([:]{1,2}[0-9A-Fa-f]{1,4}){1,7}) prefixlen ([0-9]+)\s} $err _ ipv6netaddr _ prefixlen]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![string equal {64} $prefixlen]} {
                puts stderr "Does not support prefixlen: $prefixlen"
                exit 1
            }
            set ipv6netaddr [getIPv6Netaddr $ipv6netaddr]
        }
        Linux {
            if {[catch [list exec ip a | grep {inet6 } | grep -v {inet6 fe80:} | grep -v {inet6 ::1}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet6 ([0-9A-Fa-f]{1,4}([:]{1,2}[0-9A-Fa-f]{1,4}){1,7})/([0-9]+)\s} $err _ ipv6netaddr _ prefixlen]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![string equal {64} $prefixlen]} {
                puts stderr "Does not support prefixlen: $prefixlen"
                exit 1
            }
            set ipv6netaddr [getIPv6Netaddr $ipv6netaddr]
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
            exit 1
        }
    }
    return $ipv6netaddr
}

proc lreverse {l} {
    set ret {}
    for {set i [expr [llength $l] - 1]} {$i >= 0} {incr i -1} {
        lappend ret [lindex $l $i]
    }
    return $ret
}

proc determinIPv6RevZoneName {ipv6netaddr} {
    set ipv6netaddr [split [regsub {:$} $ipv6netaddr {}] {:}]
    set ret {}
    for {set i 3} {$i >= 0} {incr i -1} {
        set ret [concat $ret [lreverse [split [format {%04x} 0x[lindex $ipv6netaddr $i]] {}]]]
    }
    return "[join $ret {.}].ip6.arpa"
}

proc findDomainname {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            # find domain name from /etc/resolv.conf
            if {[catch [list exec egrep {^domain } /etc/resolv.conf] domain] && \
                [catch [list exec egrep {^search } /etc/resolv.conf] domain]} {
                    puts stderr "Can not find domain and search line in /etc/resolv.conf: $domain"
                    exit 1
            } else {
                set domain [lindex [split $domain] 1]
            }
            if {[string equal {} $domain]} {
                puts stderr "Can not find domain name from /etc/resolv.conf"
                exit 1
            }
        }
        Linux {
            if {[catch [list exec resolvectl status | grep {DNS Domain:}] domain]} {
                puts stderr " Can not get DNS Domain from resolvectl status: $domain"
            } else {
                set domain [lindex [split [regsub -all -line -- {^\s+} $domain {}]] 2]
            }
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
        }
    }
    return $domain
}


proc findDNSServers {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            # find DNS servers from /etc/resolv.conf
            if {[catch [list exec egrep {^nameserver } /etc/resolv.conf] dnsservers]} {
                puts stderr "Cab not find nameserver line in /etc/resolv.conf: $dnsservers"
                exit 1
            } else {
                set buf {}
                foreach i [split [regsub -all -line -- {^nameserver } $dnsservers {}]] {
                    if {[regexp {^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$} $i]} {
                        lappend buf $i
                    }
                }
                set dnsservers $buf
            }
            if {[string equal {} $dnsservers]} {
                puts stderr "Can not find DNS servers from /etc/resolv.conf"
                exit 1
            }
        }
        Linux {
            if {[catch [list exec resolvectl status | grep {DNS Servers:}] dnsservers]} {
                puts stderr "Can not find DNS servers from resolvectl status: $dnsservers"
            } else {
                set buf {}
                foreach i [split [regsub -all -line -- {^\s+DNS Servers: } $dnsservers {}]] {
                    if {[regexp {^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$} $i]} {
                        lappend buf $i
                    }
                }
                if {[string equal {} $buf]} {
                    puts stderr "Can not find DNS servers from resolvectl status"
                    exit 1
                }
                set dnsservers $buf
            }
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
            exit 1
        }
    }
    return [join $dnsservers {, }]
}

proc findIPv4Defaultroute {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec netstat -rn | egrep {^default} | grep -v {fe80::}] ipv4defaultroute]} {
                puts stderr "Can not find default route from netstat -rn: $ipv4defaultroute"
                exit 1
            }
            set buf {}
            foreach i [split [regsub -all -line -- {^default\s+} $ipv4defaultroute {}] "\n"] {
                lappend buf [lindex $i 0]
            }
            set ipv4defaultroute [lindex [lsort -unique $buf] 0]
        }
        Linux {
            if {[catch [list exec ip route | egrep {^default}] ipv4defaultroute] || \
                ![regexp {^default via ((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))} $ipv4defaultroute _ ipv4defaultroute _]} {
                puts stderr "Can not find default route from ip route: $ipv4defaultroute"
                exit 1
            }
            set buf {}
            foreach i [split [regsub -all -line -- {^default\s+} $ipv4defaultroute {}] "\n"] {
                lappend buf [lindex $i 0]
            }
            set ipv4defaultroute [lindex [lsort -unique $buf] 0]
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
        }
    }
    if {[string equal {} $ipv4defaultroute]} {
        puts stderr "an not find IPv4 default route"
        exit 1
    }
    return $ipv4defaultroute
}

proc determinIPv4RevZoneName {ipv4NetAddr} {
    switch -regexp -- $ipv4NetAddr {
        10\..+ {
            set revZone {10.in-addr.arpa}
        }
        172\.(1[6-9]|2[0-9]|3[0-1])\..+ {
            set addr [split $ipv4NetAddr {.}]
            set revZone "[lindex $addr 1].[lindex $addr 0].in-addr.arpa"
        }
        192\.168\..+ {
            set revZone {168.192.in-addr.arpa}
        }
        default {
            puts stderr "Does not support global address: $ipv4NetAddr"
            exit 1
        }
    }
    return $revZone
}

proc findMName {zone} {
    if {[catch [list exec dig $zone soa | egrep -v {^;|^$}] soa]} {
        puts stderr "Can not get soa record: $soa"
        exit 1
    }
    set soa [split [regsub -all -- {\s+} $soa { }]]
    return [lindex $soa 4]
}

proc findRName {zone} {
    if {[catch [list exec dig $zone soa | egrep -v {^;|^$}] soa]} {
        puts stderr "Can not get soa record: $soa"
        exit 1
    }
    set soa [split [regsub -all -- {\s+} $soa { }]]
    return [lindex $soa 5]
}

proc findNSRecords {zone} {
    if {[catch [list exec dig $zone ns | egrep -v {^;|^$} | egrep {IN\s+NS\s}] ns]} {
        puts stderr "Can not get ns record: $ns"
        exit 1
    }
    set buf {}
    foreach i [split $ns "\n"] {
        lappend buf [concat {@} [lrange [split [regsub -all -- {\s+} $i { }]] 2 end]]
    }
    return [join $buf "\n"]
}

proc findIPv6NetworkAddress {} {
    global tcl_platform
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet6 } | grep -v {inet6 fe80:} | grep -v {inet6 ::1}] err]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![regexp {\s+inet6 ([0-9A-Fa-f]{1,4}([:]{1,2}[0-9A-Fa-f]{1,4}){1,7}) prefixlen ([0-9]+)\s} $err _ ipv6netaddr _ prefixlen]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![string equal {64} $prefixlen]} {
                puts stderr "Does not support prefixlen: $prefixlen"
                exit 1
            }
            set ipv6netaddr [getIPv6Netaddr $ipv6netaddr]
        }
        Linux {
            if {[catch [list exec ip a | grep {inet6 } | grep -v {inet6 fe80:} | grep -v {inet6 ::1}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet6 ([0-9A-Fa-f]{1,4}([:]{1,2}[0-9A-Fa-f]{1,4}){1,7})/([0-9]+)\s} $err _ ipv6netaddr _ prefixlen]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            if {![string equal {64} $prefixlen]} {
                puts stderr "Does not support prefixlen: $prefixlen"
                exit 1
            }
            set ipv6netaddr [getIPv6Netaddr $ipv6netaddr]
        }
        default {
            puts stderr "Unsupported OS: $tcl_platform(os)"
            exit 1
        }
    }
    return $ipv6netaddr
}

set domainName {}
set dnsServers {}
set ipv4NetAddr {}
set netMask {}
set ipv4RangeStart {}
set ipv4RangeEnd {}
set ipv4BroadCast {}
set ipv4DefaultRouter {}
set ipv4RevZoneName {}
set mName {}
set rName {}
set nsRecords {}
set ipv6NetAddr {}
set ipv6RevZoneName {}

# parse options
foreach i $argv {
    switch -glob -- %i {
        --domain=* {
            if {![regexp {^--domain=([A-Za-z0-9\.\\]+)$} $i _ domainName]} {
                puts stderr "Invalid domain name: $i"
                exit 1
            }
        }
        --dnsservers=* {
            if {![regexp {^--dnsservers=(.+)$} $i _ dnsServers]} {
                puts stderr "No DNS servers: %i"
                exit 1
            }
            set buf {}
            foreach j [split $dnsServers {,}] {
                set ip {}
                if {![regexp {^((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))$} $j _ ip]} {
                    puts stderr "No IPv4 address: $j"
                    exit 1
                }
                lappend buf $ip
            }
            set dnsServers $buf
        }
        --ipv4netaddress=* {
            if {![regexp {^--ipv4netaddress=((([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))$} $j _ ipv4NetAddr]} {
                puts stderr "Invalid IPv4 Network Address: $i"
                exit 1
            }
        }
        --ipv4netmask=* {
            if {![regexp {^--ipv4netmask=(255\.255\.255\.0|255\.255\.0\.0|255\.0\.0\.0)$} $i _ netMask]} {
                puts stderr "Invalid or unsupported netmask: %i"
                exit 1
            }
        }
        --ipv4broadcast=* {
            if {![regexp {^--ipv4broadcast=(.+)$} $i _ ipv4BroadCast]} {
                puts stderr "No IPv4 Broadcast address: $i"
                exit 1
            }
        }
        --ipv4rangestart=* {
            if {![regxp {^--ipv4rangestart=(.+)$} $i _ ipv4RangeStart]} {
                puts stderr "No IPv4 DHCP Range Start: %i"
                exit 1
            }
        }
        --ipv4rangeend=* {
            if {![regxp {^--ipv4rangeend=(.+)$} $i _ ipv4RangeEnd]} {
                puts stderr "No IPv4 DHCP Range End: %i"
                exit 1
            }
        }
        --dnsMName=* {
            if {![regexp {^--dnsMName=(.+)$} $i _ mName]} {
                puts stderr "No DNS MName: $i"
                exit 1
            }
        }
        --dnsRName=* {
            if {![regexp {^--dnsRName=(.+)$} $i _ rName]} {
                puts stderr "No DNS RName: $i"
                exit 1
            }
        }
        --nsResords=* {
            if {![regexp {^--nsRecords=(.+)$} $i _ nsRecords]} {
                puts stderr "No NS Records: $i"
                exit 1
            }
        }
        --ipv6NetAddr=* {
            if {![regexp {^--ipv6NetAddr=(.+)$} $i _ ipv6NetAddr]} {
                puts stderr "No IPv6 Network Address: $i"
                exit 1
            }
        }
        default {
            puts stderr "Unknown option: %i"
            exit $i
        }
    }
}

# correct options
if {[string equal {} $domainName]} {
    set domainName [findDomainname]
}
if {[string equal {} $dnsServers]} {
    set dnsServers [findDNSServers]
}
if {[string equal {} $ipv4NetAddr]} {
    set ipv4NetAddr [findIPv4NetworkAddresses]
}
if {[string equal {} $netMask]} {
    set netMask [findIPv4Netmask]
}
if {[string equal {} $ipv4RangeStart]} {
    set ipv4RangeStart [regsub {\.0$} $ipv4NetAddr {.100}]
}
if {[string equal {} $ipv4RangeEnd]} {
    set ipv4RangeEnd [regsub {\.0$} $ipv4NetAddr {.200}]
}
if {[string equal {} $ipv4BroadCast]} {
    set ipv4BroadCast [findIPv4Broadcast]
}
if {[string equal {} $ipv4DefaultRouter]} {
    set ipv4DefaultRouter [findIPv4Defaultroute ]
}
if {[string equal {} $ipv4RevZoneName]} {
    set ipv4RevZoneName [determinIPv4RevZoneName $ipv4NetAddr]
}
if {[string equal {} $mName]} {
    set mName [findMName $domainName]
}
if {[string equal {} $rName]} {
    set rName [findRName $domainName]
}
if {[string equal {} $nsRecords]} {
    set nsRecords [findNSRecords $domainName]
}
if {[string equal {} $ipv6NetAddr]} {
    set ipv6NetAddr [findIPv6NetworkAddress]
}
if {[string equal {} $ipv6RevZoneName]} {
    set ipv6RevZoneName [determinIPv6RevZoneName $ipv6NetAddr]
}
# make dictionary
set dict {}
lappend dict [list {%DOMAINNAME%} $domainName]
lappend dict [list {%DNSSERVERS%} $dnsServers]
lappend dict [list {%IPV4NETWORKADDR%} $ipv4NetAddr]
lappend dict [list {%NETMASK%} $netMask]
lappend dict [list {%IPV4RANGESTART%} $ipv4RangeStart]
lappend dict [list {%IPV4RANGEEND%} $ipv4RangeEnd]
lappend dict [list {%IPV4BRDCAST%} $ipv4BroadCast]
lappend dict [list {%IPV4DEFAULTROUTER%} $ipv4DefaultRouter]
lappend dict [list {%IPV4REVZONENAME%} $ipv4RevZoneName]
lappend dict [list {%MNAME%} $mName]
lappend dict [list {%RNAME%} $rName]
lappend dict [list {%NSRECORDS%} $nsRecords]
lappend dict [list {%IPV6NADDR%} $ipv6NetAddr]
lappend dict [list {%IPV6REVZONENAME%} $ipv6RevZoneName]

# generate Template Files
foreach inFile [glob -nocomplain -- {*.in}] {
    set outFile [file rootname $inFile]
    if {[catch [list open $inFile r] in]} {
        puts stderr $in
        exit 1
    }
    if {[catch [list open $outFile w] out]} {
        puts stderr $out
        exit 1
    }
    while {![eof $in]} {
        set line [gets $in]
        foreach i $dict {
            set line [regsub [lindex $i 0] $line [lindex $i 1]]
        }
        puts $out $line
    }
    if {[catch [list close $out] err]} {
        puts stderr $err
        exit 1
    }
    if {[catch [list close $in] err]} {
        puts stderr $err
        exit 1
    }
}
