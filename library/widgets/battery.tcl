# The battery — the showcase the params machinery was built for (the
# owner's ask, 2026-08-11): one type, several instances, each naming
# its own SOURCE of charge — this laptop's ACPI, or a phone over ssh —
# and a LETTER to tell them apart on the strip. Three visual pieces:
# an SVG icon whose fill and colour are the state, the percent, and
# the letter. Row or stack by -band/-across, the clock's own
# reasoning.
#
# THE SOURCE is two words:
#   sys ?NAME|path?     /sys/class/power_supply — NAME names a supply,
#                       a full path IS the supply's directory (which is
#                       also how the suite fakes one), and neither
#                       means the first Battery-typed supply found.
#                       Read synchronously: sysfs answers from memory.
#   command {argv…}     any command whose stdout is a bare percent or
#                       termux-battery-status JSON (.percentage,
#                       .status, .plugged) — `ssh phone
#                       termux-battery-status` is the case in hand.
#                       Run through pipe-run with a timeout, never
#                       blocking the desk; while an answer is out no
#                       second one is asked for.
#
# STATE IS KEYED BY THE SOURCE, not by the widget: two widgets naming
# one source show one battery, and a rebuild (cheap, constant — see
# widget.tcl) never forgets the last reading. A source that failed —
# command died, timed out, spoke gibberish — is STALE: grey icon, a
# dash for the percent, standing until the first good answer takes it
# back. That is the «нет связи» the phone case needs.
#
# AC ONLINE is its own fact (the owner, 2026-08-11): plugged and
# charging is the bolt, plugged and NOT charging (full, or holding) is
# the plug — power present is worth a glyph even when nothing flows.
# sysfs says it through a Mains-typed sibling's `online`; termux
# through .plugged ne UNPLUGGED.
package require json

wm-widget-type battery {
    build battery-widget-build
    tick  battery-widget-tick
    every 30000
    prefers panel
    fonts {
        BatteryFont       {default {}
                           doc {the percent's face — the desk font as it stands}}
        BatteryLetterFont {default {-size 0.7x -weight bold}
                           doc {the letter that names a battery among several}}
    }
    params {
        -source {kind list default sys
                 doc {where the charge comes from: sys ?NAME|path?, or command {argv…}}
                 examples {
                     sys {the first battery under /sys/class/power_supply}
                     {sys BAT1} {a supply by name}
                     {command {ssh phone termux-battery-status}}
                         {a phone over ssh — JSON, or a bare percent}}}
        -letter {kind text default {}
                 doc {a letter naming this battery when there are several}}
        -low    {kind {int 0 100} default 15
                 doc {at or below this percent the fill turns red}}
    }
}

keep battery_gap 5
array set battery_state {}      ;# SOURCE -> {stale B pct N status S ac B}
array set battery_inflight {}   ;# SOURCE -> 1 while a command is out

proc battery-widget-build {w opts} {
    set fg [dict get $opts -foreground]
    set bg [dict get $opts -background]
    label $w.icon -background $bg
    label $w.pct -font BatteryFont -foreground $fg -background $bg
    label $w.letter -font BatteryLetterFont -foreground $fg -background $bg
    # the photo dies with its label, or every rebuild would leave one
    bind $w.icon <Destroy> {catch {image delete battery-icon:%W}}
    set letter [dict get $opts -letter]
    if {[battery-widget-shape $opts] eq "row"} {
        pack $w.icon -side left
        pack $w.pct -side left -padx [list $::battery_gap 0]
        if {$letter ne ""} {
            pack $w.letter -side left -padx [list $::battery_gap 0]
        }
    } else {
        pack $w.icon -side top
        pack $w.pct -side top
        if {$letter ne ""} { pack $w.letter -side top }
    }
    battery-widget-tick $w $opts
}

# The clock's reasoning over this widget's own measurements: on a
# horizontal strip the row is the cheap shape; on a vertical one the
# stack is — and paid thickness is spent, not admired. On the desk
# nothing is scarce and a battery reads best in a line.
proc battery-widget-shape {opts} {
    set edges [expr {2 * [dict get $opts -padding] + 2}]
    set ih [font metrics BatteryFont -linespace]
    switch -- [dict get $opts -band] {
        horizontal {
            set stack [expr {$ih + [font metrics BatteryFont -linespace] + $edges}]
            return [expr {[dict get $opts -across] >= $stack ? "stack" : "row"}]
        }
        vertical {
            set row [expr {$ih * 36 / 20 + $::battery_gap \
                           + [font measure BatteryFont "100%"] + $edges}]
            if {[dict get $opts -letter] ne ""} {
                incr row [expr {$::battery_gap \
                    + [font measure BatteryLetterFont [dict get $opts -letter]]}]
            }
            return [expr {[dict get $opts -across] >= $row ? "row" : "stack"}]
        }
    }
    return row
}

proc battery-widget-tick {w opts} {
    # ask first — sysfs answers in the same breath, a command answers
    # later through battery-redraw — then draw what is known now
    battery-poke [dict get $opts -source]
    battery-draw $w $opts
}

# ---- reading the source ----
proc battery-slurp {path} {
    set ch [open $path r]
    try { string trim [read $ch 256] } finally { close $ch }
}
proc battery-poke {src} {
    switch -- [lindex $src 0] {
        sys {
            set ::battery_state($src) [battery-read-sys [lindex $src 1]]
        }
        command {
            if {[info exists ::battery_inflight($src)]} return
            set ::battery_inflight($src) 1
            wm-errand "battery [lindex $src 1]" [list battery-fetch $src]
        }
        default {
            # said once, not per beat: the kind admits any list, so a
            # wrong first word is only caught here
            if {![info exists ::battery_state($src)]} {
                puts "WM: battery: a source speaks sys or command,\
 not «[lindex $src 0]»"
            }
            set ::battery_state($src) {stale 1}
        }
    }
}
proc battery-sys-dir {arg} {
    set base /sys/class/power_supply
    if {$arg ne ""} {
        return [expr {[string match /* $arg] ? $arg : "$base/$arg"}]
    }
    foreach d [lsort [glob -nocomplain $base/*]] {
        if {![catch {battery-slurp $d/type} t] && $t eq "Battery"} {
            return $d
        }
    }
    return ""
}
proc battery-read-sys {arg} {
    set dir [battery-sys-dir $arg]
    if {$dir eq "" || [catch {battery-slurp $dir/capacity} pct]
            || ![string is integer -strict $pct]} {
        return {stale 1}
    }
    set status unknown
    catch { set status [string tolower [battery-slurp $dir/status]] }
    # AC is a SIBLING supply of type Mains, not the battery's own file
    set ac 0
    foreach d [glob -nocomplain [file dirname $dir]/*] {
        if {![catch {battery-slurp $d/type} t] && $t eq "Mains"
                && ![catch {battery-slurp $d/online} on] && $on eq "1"} {
            set ac 1
        }
    }
    dict create stale 0 pct $pct status $status ac $ac
}
# The command's errand: one out per source, a timeout counts as a bad
# answer, and whatever comes back lands in the state and repaints
# every widget watching this source.
proc battery-fetch {src} {
    set st {stale 1}
    try {
        set r [fut::await [pipe-run [lindex $src 1] -stderr drop \
                               -timeout 10000]]
        if {[dict get $r status] == 0} {
            set st [battery-parse [dict get $r out]]
        }
    } on error {e} {
    } finally {
        unset -nocomplain ::battery_inflight($src)
    }
    set ::battery_state($src) $st
    battery-redraw $src
}
# A bare percent, or termux-battery-status JSON — .percentage,
# .status (CAPS there, sysfs capitalizes; lowered here so one reader
# serves both), .plugged (UNPLUGGED / PLUGGED_AC / PLUGGED_USB).
proc battery-parse {out} {
    set out [string trim $out]
    if {[string is integer -strict $out]} {
        return [dict create stale 0 pct $out status unknown ac 0]
    }
    if {[catch {json::json2dict $out} j] || [catch {dict size $j}]} {
        return {stale 1}
    }
    if {![dict exists $j percentage]
            || ![string is integer -strict [dict get $j percentage]]} {
        return {stale 1}
    }
    set st [dict create stale 0 pct [dict get $j percentage] \
                status unknown ac 0]
    if {[dict exists $j status]} {
        dict set st status [string tolower [dict get $j status]]
    }
    if {[dict exists $j plugged]} {
        dict set st ac [expr {[dict get $j plugged] ne "UNPLUGGED"}]
    }
    return $st
}
proc battery-redraw {src} {
    foreach name [array names ::widget_win] {
        if {![dict exists $::widgets $name]} continue
        set opts [widget-opts $name]
        if {[dict get $opts -type] ne "battery"} continue
        if {[dict get $opts -source] ne $src} continue
        set c $::widget_win($name)
        if {[winfo exists $c]} { catch {battery-draw $c $opts} }
    }
}

# ---- drawing ----
proc battery-draw {w opts} {
    set src [dict get $opts -source]
    set st [expr {[info exists ::battery_state($src)] \
                      ? $::battery_state($src) : {stale 1}}]
    set fg [dict get $opts -foreground]
    if {[dict get $st stale]} {
        set text "—"
        set svg [battery-svg 0 {} [themed dim] {} {} 1]
    } else {
        set pct [dict get $st pct]
        set text "$pct%"
        set fill [expr {$pct <= [dict get $opts -low] \
                            ? [themed alert] : [themed found]}]
        set glyph ""
        if {[dict get $st status] eq "charging"} {
            set glyph bolt
        } elseif {[dict get $st ac]} {
            set glyph plug
        }
        set svg [battery-svg [expr {$pct / 100.0}] $fill $fg \
                     $glyph [themed modal] 0]
    }
    set ih [font metrics BatteryFont -linespace]
    image create photo battery-icon:$w.icon \
        -format [list svg -scaletoheight $ih] -data $svg
    $w.icon configure -image battery-icon:$w.icon
    $w.pct configure -text $text
    $w.letter configure -text [dict get $opts -letter]
}
# The icon: a 36x20 body-and-nub, the fill a rectangle scaled by the
# charge, the glyph over the middle. No <text> anywhere — the tiny-svg
# renderer draws shapes, not type — which is why the stale face is a
# drawn dash and the percent stays a real label outside the picture.
proc battery-svg {frac fill outline glyph glyphcolor stale} {
    set svg "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 36 20\">"
    append svg "<rect x=\"1\" y=\"3\" width=\"28\" height=\"14\" rx=\"3\"\
 stroke=\"$outline\" stroke-width=\"2\" fill=\"none\"/>"
    append svg "<rect x=\"31\" y=\"7\" width=\"3\" height=\"6\" rx=\"1\"\
 fill=\"$outline\"/>"
    if {$stale} {
        append svg "<rect x=\"11\" y=\"9\" width=\"8\" height=\"2\"\
 fill=\"$outline\"/>"
    } elseif {$frac > 0} {
        set iw [format %.1f [expr {24 * min(1.0, $frac)}]]
        append svg "<rect x=\"3\" y=\"5\" width=\"$iw\" height=\"10\"\
 rx=\"1\" fill=\"$fill\"/>"
    }
    switch -- $glyph {
        bolt {
            append svg "<polygon points=\"17,1 11,11 15,11 13,19 20,9 16,9\"\
 fill=\"$glyphcolor\"/>"
        }
        plug {
            append svg "<path d=\"M13 3 v4 M19 3 v4\" stroke=\"$glyphcolor\"\
 stroke-width=\"2\"/><rect x=\"11\" y=\"7\" width=\"10\" height=\"6\"\
 rx=\"2\" fill=\"$glyphcolor\"/><path d=\"M16 13 v4\"\
 stroke=\"$glyphcolor\" stroke-width=\"2\"/>"
        }
    }
    append svg "</svg>"
    return $svg
}
