#! /bin/sh
# the next line restarts using tclsh8.6 on unix \
if type tclsh8.6 > /dev/null 2>&1 ; then exec tclsh8.6 "$0" ${1+"$@"} ; fi
# the next line restarts using tclsh \
if type tclsh > /dev/null 2>&1 ; then exec tclsh "$0" ${1+"$@"} ; fi
# the next line complains about a missing wish \
echo "This software requires Tcl/Tk 8.6 to run." ; \
exit 1
# homeAddressManager.tcl [Options] CSVファイ
# 概要: 定められた書式のCSVファイルを入力として、テンプレートを元に、ISC DHCPd用の
#   DHCP固定アドレス払い出し設定を含めた設定ファイル、BIND用の正引き/逆引きゾーンファ
#   イルを生成出力、必要に応じて、dhcpd/namedの再起動を行う。
# 引数:
#  --dhcp-tmplate=DHCP設定テンプレート
#   DHCP設定テンプレートファイル
#  --dhcp-configfile=DHCP設定ファイル
#   出力設定ファイルパス。指定された場合、生成を行う。
#  --forward-zone-template=正引きテンプレート
#   正引きテンプレートファイル
#  --reverse-ipv4-zone-template=IPv4逆引きテンプレート
#   IPv4逆引きテンプレートファイル
#  --reverse-ipv6-template-file=IPv6逆引きテンプレート
#   IPv6逆引きテンプレートファイル
#  --forward-zone-file=正引きゾーンファイル
#   出力正引きゾーンファイルパス。指定された場合、生成を行う。
#  --reverse-ipv4-zone-file=IPv4逆引きゾーンファイル
#   出力IPv4逆引きゾーンファイルパス。指定された場合、生成を行う。
#  --reverse-ipv6-zone-file=IPv6逆引きゾーンファイル
#   出力IPv6逆引きゾーンファイルパス。指定された場合、生成を行う。
#  --domain-name=ドメイン名
#  --ipv6-network-address=IPv6ネットワークアドレス
#  --class=A|B|C
#   IPv4アドレスのクラス。A(/8)、B(/16)、C(/24)。デフォルトC

# genEUI64 macaddr -
# 概要: eui64形式でIPv6のインタフェースID部分64bitを生成する
# 引数:
#  macaddr - インタフェースのMACアドレス。XX:XX:XX:XX:XX:XX の形式
# 戻り値:
#  eui64形式のIPv6 IntrfaceID
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

# proc parseLine line -
# 概要： CSVファイルの1行をパースして、各項目をリストにして返す。
#    MACアドレス、IPアドレス、管理者、ホスト名情報が書式として正しいか否かを検査する。
#    書式として正しくない場合は標準エラー出力にエラーメッセージを出力する。
# 引数:
#   line - CVSファイルの1行
# 戻り値: 書式が正しい場合は、以下の情報のリスト
#          {MACアドレス IPアドレス 管理者 ホスト名 eui64フラグ}
#           ※eui64フラグはEUI64方式のIPv6アドレスでAAAAレコードを生成するか否かのbool値。他はすべて文字列
#       諸記事が不正の場合は空文字列を返す
proc parseLine {line} {
    set buf [split $line {,}]
    set macaddr [lindex $buf 0]
    if {![regexp -nocase -- {^[0-9a-f]{2}([:-][0-9a-f]{2}){5}} $macaddr]} {
        puts stderr "Invalid macaddr format: $line"
        return
    }
    set ipaddr [lindex $buf 1]
    if {![validIPv4addr $ipaddr]} {
        puts stderr "Invalid IPAddr format: $line"
        return
    }
    set eui64 0
    set adminHost [lindex $buf 2]
    if {[string equal "eui64" $adminHost]} {
        set eui64 1
        set adminHost [lindex $buf 3]
    } elseif  {[string equal "eui64" [lindex $buf 3]]} {
        set eui64 1
    }
    set admin [lindex [split $adminHost "@"] 0]
    set host [lindex [split $adminHost "@"] 1]
    if {[string equal "" $admin] || [string equal "" $host]} {
        puts stderr "Invalid Admin@Hostname: $line"
        return
    }
    return [list $macaddr $ipaddr $admin $host $eui64]
}

# proc validIPv4addr -
# 概要: 引数がIPv4アドレスとして解釈できる文字列であるならば真を、それ以外の場合は偽を返す
# 引数: IPv4アドレス文字列
# 戻り値: 判定結果真偽値
proc validIPv4addr {addr} {
    set ret 1
    set addr [split $addr "."]
    if {[llength $addr] != 4} {
        return 0
    }
    foreach a $addr {
        set a [scan $a "%d"]
        if {[string equal {} $a] || $a < 0 || $a > 255} {
            set ret 0
            break
        }
    }
    return $ret
}

# proc genDHCPConf -
# 概要: ISC DHCP用のIPv4固定払い出し設定ファイルを生成する。CVSファイル行のフォーマットが正しく
#      ない場合は無視する。
# 引数:
#  fp - 設定ファイル書き出し用に書き込みモードで開かれたファイルストリーム
#  line - 入力CSVファイルの1行
# 戻り値: なし
proc genDHCPConf {fp line} {
    set parsed [parsedLine $line]
    puts $fp "Host [lindex $parsed 3] \{"
    puts $fp "\thardware ethernet [lindex $parsed 0];"
    outs $fp "\tfixed-address[lindex $parsed 1];"
    puts $fp "\}"
}

# proc genForwardZoneFile -
# 概要: ISC Bind用の正引きゾーンファイルを生成する
proc genForwardZoneFile {fpTMPL fpZONE line domain} {
    set parsed [parseLine $line]
    set ipaddr [lindex $parsed 1]

    set host [lindex $parsed 3]
    set eui64 [lindex $parsed 4]
    set macaddr [lindex $parsed 0]
    puts $fp1 "$host\tIN A\t$ipaddr"
    if {$eui64} {
        puts $fp1 "$host\tIN AAAA\t$ipv6network:[genEUI64 $macaddr]"
    }
}

proc genNamedConf {fp1 fp2 line class domain ipv6network]} {
    set parsed [parseLine $line]
    set ipaddr [lindex $parsed 1]

    set host [lindex $parsed 3]
    set eui64 [lindex $parsed 4]
    set macaddr [lindex $parsed 0]
    puts $fp1 "$host\tIN A\t$ipaddr"
    if {$eui64} {
        puts $fp1 "$host\tIN AAAA\t$ipv6network:[genEUI64 $macaddr]"
    }

    set revip {}
    switch $class {
        a {set rc 2}
        b {set rc 1}
        default {set rc 0}
    }
    for {set i $rc} {$i >= 0} {incr i -1} {
        lappend revip [lindex [split $ipaddr "."] $i]
    }
    puts $fp2 "[join $revip .]\tIN PTR\t$host.$domain"
}

# prov usage -
# 概要: 簡単なヘルプメッセージを表示する
proc usage {} {
    global argv0
    puts stderr "$argv0 \\"
    puts stderr "  --dhcp-tmplate=DHCP Template \\"
    puts stderr "  --dhcp-configfile=Output DHCP Configuration File \\"
    puts stderr "  --forward-zone-template=DNS Forward Template \\"
    puts stderr "  --reverse-ipv4-zone-template=DNS IPv4 reverse Template \\"
    puts stderr "  --reverse-ipv6-template-file=DNS IPv6 reverse Template \\"
    puts stderr "  --forward-zone-file=Output DNS forward Zone File \\
    puts stderr "  --reverse-ipv4-zone-file=Output DNS IPv4 reverse Zone File \\"
    puts stderr "  --reverse-ipv6-zone-file=Output DNS IPv6 reverse Zone File \\"
    puts stderr "  --domain-name=domain name \\"
    puts stderr "  --ipv6-network-address=IPv6 network address \\"
    puts stderr "  --class=A|B|C"
}

# global variables:
set dhcpTemplate {}
set dhcpConfigFile {}
set forwardZoneTemplate {}
set reverseIPv4Template {}
set reverseIPv6Template {}
set forwardZoneFile {}
set reverseIPv4ZoneFile {}
set reverseIPv6ZoneFile {}
set domainName {}
set ipv6NetworkAddress {}
set class {C}

# auto Configuration
switch -- $tcl_platform(os) {
    Linux {
        set dhcpRestartCmd {systemctl restart isc-dhcp-server}
        set bindRestartCmd {systemctl restart named}
    }
    Darwin {
        # for using "sudo brew ...", edit /etc/sudoers as following:
        # %admin          ALL = (ALL) ALL
        # ->
        # %admin          ALL = (ALL) NOPASSWD: ALL
        set dhcpRestartCmd {sudo brew services restart isc-dhcp}
        set bindRestartCmd {sudo brew services restart named}
    }
    FreeBSD {
        set dhcpRestartCmd {service isc-dhcpd restart}
        set bindRestartCmd {service named restart}
    }
    default {
        puts stderr "Unknown OS: $tcl_platform(os)"
        exit 1
    }
}

# parse options
set csvFile [lindex $argv [expr [llength $argv] - 1]]
if {[string equal "" $csvFile]} {
    puts stderr "No Input CSV File."
    usage
    exit 1
}
foreach i [lrange $argv 0 [expr [llength $argv] - 1]] {
    switch -glob -- $i {
        --dhcp-tmplate=* {
            regexp -- {^--dhcp-tmplate=(.+)$} $i _ dhcpTemplate
        }
        --dhcp-configfile=* {
            regexp -- {^--dhcp-configfile=(.+)$} $i _ dhcpConfigFile
        }
        --forward-zone-template=* {
            regexp -- (^--forward-zone-template=(.+)$) $i _ forwardZoneTemplate
        }
        --reverse-ipv4-zone-template=* {
            regexp -- (^--reverse-ipv4-zone-template=(.+)$) $i _ reverseIPv4Template
        }
        --reverse-ipv6-template-file=* {
            regexp -- (^--reverse-ipv6-template-file=(.+)$) $i _ reverseIPv6Template
        }
        --forward-zone-file=* {
            regexp -- {^--forward-zone-file=(.+)$} $i _ forwardZoneFile
        }
        --reverse-ipv4-zone-file=* {
            regexp -- {^--reverse-ipv4-zone-file=(.+)$} $i _ reverseIPv4ZoneFile
        }
        --reverse-ipv6-zone-file=* {
            regexp -- {^--reverse-ipv6-zone-file=(.*)$} $i _ reverseIPv6ZoneFile
        }
        --domain-name=* {
            regexp -- (^--domain-name=(.+)$) $i _ domainName
        }
        --ipv6-network-address=* {
            regexp -- (^--ipv6-network-address=(.+)$) $i _ ipv6NeyworkAddr
        }
        --class=* {
            regexp -- (^--class=([A-Ca-c])$) $i _ class
        }
    }
}

# check Options
if {![string equal {} $dhcpConfigFile] && [string equal {} $dhcpTemplate]} {
    puts stderr "No DHCP Template. Use option --dhcp-tmplate=DHCP Template"
    exit 1
}
if {![string equal {} $forwardZoneFile] && [string equal {} $forwardZoneTemplate]} {
    puts stderr "No DNS Forward Template. Use option --forward-zone-template=DNS Forward Template"
    exit 1
}
if {![string equal {} $reverseIPv4ZoneFile] && [string equal {} $reverseIPv4Template]} {
    puts stderr "No DNS IPv4 reverse Template. Use option --reverse-ipv4-zone-template=DNS IPv4 reverse Template"
    exit 1
}
if {![string equal {} $reverseIPv6ZoneFile] && [string equal {} $reverseIPv4Template]} {
    puts stderr "No DNS IPv6 reverse Template. Use option --reverse-ipv6-zone-template=DNS IPv6 reverse Template"
    exit 1
}
if {![string equal {} $reverseIPv4ZoneFile] && [string equal {} $domain]} {
    puts stderr "No dmain name. Use option --domain=domain name"
    exit 1
}
if {![string equal {} $reverseIPv6ZoneFile] && [string equal {} $ipv6NetworkAddr]} {
    puts stderr "No IPv6 network address. Use option --ipv6-network-address=IPv6 network address"
    exit 1
}

# main loop
if {[catch [list open $csvFile r] fpCSV]} {
    puts stderr $fpCSV
    exit 1
}
if {![string equal {} $dhcpConfigFile]} {
    if {[catch [list open $dhcpTemplate r] fpDHCPTMPL]} {
        puts stderr $fpDHCPTMPL
        exit 1
    }
    if {[catch [list open $dhcpConfigFile w] fpDHCPCONFG]} {
        puts stderr $fpDHCPCONFG
        exit 1
    }
}
if {![string equal {} $forwardZoneFile]} {
    if {[catch [list open $forwardZoneTemplate r] fpFWDZONETMPL]} {
        puts stderr $fpFWDZONETMPL
        exit 1
    }
    if {[catch [list open $forwardZoneFile w] fpFWDZONEFILE]} {
        puts stderr $fpFWDZONEFILE
        exit 1
    }
}
if {![string equal {} $reverseIPv4ZoneFile]} {
    if {[catch [list open $reverseIPv4Template r] fpREVIPV4TMPL]} {
        puts stderr $fpREVIPV4TMPL
        exit 1
    }
    if {[catch [list open $reverseIPv4ZoneFile w] fpREVIPV4FILE]} {
        puts stderr $fpREVIPV4FILE
        exit 1
    }
}
if {![string equal {} $reverseIPv6ZoneFile]} {
    if {[catch [list open $reverseIPv6Template r] fpREVIPV6TMPL]} {
        puts stderr $fpREVIPV6TMPL
        exit 1
    }
    if {[catch [list open $reverseIPv6ZoneFile w] fpREVIPV6FILE]} {
        puts stderr $fpREVIPV6FILE
        exit 1
    }
}
while {![eof $fpCSV]} {

}