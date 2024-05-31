proc genEUI64 {macaddr} {
    if {![regexp -nocase -- {^[0-9a-f]{2}([:-][0-9a-f]{2}){5}} $macaddr]} {
        puts stderr "Invalid macaddr format: $macaddr"
        return $ret
    }
    set macaddr [split $macaddr ":"]
    set buf {}
    lappend buf [format {%2x} [expr "0x[lindex $macaddr 0]" ^ 2]]
    foreach i [lrange $macaddr 1 2] {
        lappend buf $i
    }
    lappend buf {ff} {fe}
    foreach i [lrange $macaddr 3 end] {
        lappend buf $i
    }
    set ret {}
    foreach {i j} $buf {
        lappend ret [regsub {^0{1,}} "$i$j" {}]
    }
    return [join $ret ":"]
}
