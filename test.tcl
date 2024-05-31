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