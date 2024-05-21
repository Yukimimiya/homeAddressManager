#! /bin/sh
# the next line restarts using tclsh8.6 on unix \
if type tclsh8.6 > /dev/null 2>&1 ; then exec tclsh8.6 "$0" ${1+"$@"} ; fi
# the next line restarts using tclsh \
if type tclsh > /dev/null 2>&1 ; then exec tclsh "$0" ${1+"$@"} ; fi
# the next line complains about a missing wish \
echo "This software requires Tcl/Tk 8.6 to run." ; \
exit 1

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

proc findNetworkAddresses {} {
    global tcl_platform
    global ipv4netaddr netmask broadcast ipv6netaddr
    switch $tcl_platform(os) {
        Darwin -
        FreeBSD {
            if {[catch [list exec ifconfig | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr $err
                exit 1
            }
            if {![regexp {\s+inet ([0-9]{1,3}(\.[0-9]{1,3}){3}) netmask 0x([f0]{8}) broadcast ([0-9]{1,3}(\.[0-9]{1,3}){3})} $err _ ipv4netaddr _ netmask broadcast]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $netmask {
                ff000000 {
                    set netmask 255.0.0.0
                    set class A
                    set ipv4netaddr "[lindex [split $ipv4netaddr {.}] 0].0.0.0"
                }
                ffff0000 {
                    set netmask 255.255.0.0
                    set class B
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 1] {.}].0.0"
                }
                ffffff00 {
                    set netmask 255.255.255.0
                    set class C
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 2] {.}].0"
                }
            }
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
            puts "DEBUG: $ipv6netaddr"
            set ipv6netaddr [getIPv6Netaddr $ipv6netaddr]
        }
        Linux {
            if {[catch [list exec ip a | grep {inet } | grep -v {inet 127.}] err]} {
                puts stderr "Can not parse ip a output: $err"
                exit 1
            }
            if {![regexp {\s+inet ([0-9]{1,3}(\.[0-9]{1,3}){3})/([12][0-9]) brd ([0-9]{1,3}(\.[0-9]{1,3}){3})\s} $err _ ipv4netaddr _ prefix broadcast]} {
                puts stderr "Can not parse ifconfig output: $err"
                exit 1
            }
            switch $prefix {
                8 {
                    set netmask 255.0.0.0
                    set class A
                    set ipv4netaddr "[lindex [split $ipv4netaddr {.}] 0].0.0.0"
                }
                16 {
                    set netmask 255.255.0.0
                    set class B
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 1] {.}].0.0"
                }
                24 {
                    set netmask 255.255.255.0
                    set class C
                    set ipv4netaddr "[join [lrange [split $ipv4netaddr {.}] 0 2] {.}].0"
                }
                default {
                    puts stderr "Unsupported prefix length: $prefix"
                    exit 1
                }
            }
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
    }
}

findNetworkAddresses

puts "ipv4netaddr=$ipv4netaddr"
puts "netmask=$netmask"
puts "broadcast=$broadcast"
puts "ipv6netaddr=$ipv6netaddr"