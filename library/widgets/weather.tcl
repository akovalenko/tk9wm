# The weather — the sky on the strip, from a free API nobody pays for
# or registers with (the owner's ask, 2026-08-11). Open-Meteo answers
# one request with the current sky AND a week of days, so the click's
# forecast sheet never fetches anything: it draws what is already
# known, and lives offline. Three visual pieces: an SVG glyph of the
# sky (WMO code folded into a dozen faces, sun or moon by is_day),
# the temperature, and a word naming the place when there are
# several. Row or stack by -band/-across, the clock's own reasoning.
#
# THE SOURCE is two words, the battery's grammar:
#   latlon LAT LON      coordinates as they stand
#   name PLACE          geocoded through the API's own gazetteer,
#                       once, and remembered for the session
#   command {argv…}     anything whose stdout is Open-Meteo's own
#                       JSON shape — the suite's door, and anybody's
#                       cache or private station
# Unsaid, the source is {name Tbilisi} — the owner's grin, 2026-08-11.
#
# THE ROAD TO THE SKY is a ladder, probed once and remembered
# (weather-via): tcltls when the runtime carries it (in-process,
# https), curl when it does not (https still), and bare core-http
# last — Open-Meteo genuinely answers plain http (measured,
# 2026-08-11), and a weather report is nobody's secret, so the last
# rung keeps the widget alive on a machine with neither tls nor
# curl. All three rungs are event-loop citizens: the fetch rides an
# errand and the desk never waits.
#
# STATE IS KEYED BY THE SOURCE, the battery's discipline: two widgets
# naming one sky show one sky, and a rebuild never forgets the last
# reading. A fetch that fails leaves the OLD reading standing, marked
# stale — the glyph goes grey while the numbers stand, because
# yesterday's sky is a better guess than a dash — and only a source
# that never answered at all wears the dash. The pace is -every
# (default 15 min), and the freshness guard keeps event-driven ticks
# (a desk switch ticks everybody) from spamming the sky.
package require json

wm-widget-type weather {
    build weather-widget-build
    tick  weather-widget-tick
    every 900000
    prefers panel
    fonts {
        WeatherFont      {default {}
                          doc {the temperature's face — the desk font as it stands}}
        WeatherLabelFont {default {-size 0.7x -weight bold}
                          doc {the word naming a place among several}}
        WeatherSheetFont {default {-size 0.9x}
                          doc {the forecast sheet's face, as a delta from the desk font}}
    }
    params {
        -source {kind list default {name Tbilisi}
                 doc {whose sky: latlon LAT LON, name PLACE, or command {argv…}
                      whose stdout is Open-Meteo's JSON}
                 examples {
                     {name Tbilisi} {a place by name, geocoded once and remembered}
                     {latlon 41.69 44.8} {coordinates as they stand}
                     {command {cat wx.json}} {anything speaking the API's own shape}}}
        -label  {kind text default {}
                 doc {a word naming this place beside the temperature}}
    }
}

keep weather_gap 5
keep weather_api api.open-meteo.com
keep weather_geocoder geocoding-api.open-meteo.com
# A full base URL (scheme and host) overriding both hosts above — the
# suite points this at a localhost httpd and the whole road is walked
# for real, no sky required.
keep weather_sky {}
keep weather_via {}             ;# the rung: tls | curl | http | none
array set weather_state {}      ;# SOURCE -> {stale B ?temp T code C isday B days L?}
array set weather_inflight {}   ;# SOURCE -> 1 while a fetch is out
array set weather_asked {}      ;# SOURCE -> [clock milliseconds] of the last ask
array set weather_geo {}        ;# PLACE -> {lat lon}, for the session

# ---- the road ----
proc weather-via {} {
    if {$::weather_via ne ""} { return $::weather_via }
    if {![catch {package require http}] && ![catch {package require tls}]} {
        ::http::register https 443 [list ::tls::socket -autoservername 1]
        set ::weather_via tls
    } elseif {[llength [auto_execok curl]]} {
        set ::weather_via curl
    } elseif {![catch {package require http}]} {
        set ::weather_via http
    } else {
        set ::weather_via none
    }
    puts "WM: weather goes by [expr {$::weather_via eq "none"
        ? "no road at all — no tls, no curl, no http" : $::weather_via}]"
    return $::weather_via
}
proc weather-url {host path} {
    if {$::weather_sky ne ""} { return "$::weather_sky$path" }
    set scheme [expr {[weather-via] eq "http" ? "http" : "https"}]
    return "$scheme://$host$path"
}
# One page, awaited inside the errand's coroutine — top to bottom,
# whatever the rung. Throws when the sky does not answer.
proc weather-slurp {url} {
    switch -- [weather-via] {
        curl {
            set r [fut::await [pipe-run [list curl -sf --max-time 15 $url] \
                                   -stderr drop -timeout 20000]]
            if {[dict get $r status] != 0} {
                error "curl exited [dict get $r status]"
            }
            return [dict get $r out]
        }
        none { error "no road to the sky" }
    }
    package require http
    set f [fut::new]
    ::http::geturl $url -timeout 15000 -command [list weather-landed $f]
    return [fut::await $f]
}
proc weather-landed {f tok} {
    set status [::http::status $tok]
    set code 0
    catch { set code [::http::ncode $tok] }
    set body [::http::data $tok]
    ::http::cleanup $tok
    if {$status eq "ok" && $code == 200} {
        fut::fulfill $f $body
    } else {
        fut::fail $f "the sky answered $status/$code"
    }
}
# %-encoding by hand, NOT http::formatQuery: the curl rung is chosen
# exactly when the http package may be absent.
proc weather-quote {s} {
    set out ""
    foreach b [split [encoding convertto utf-8 $s] ""] {
        if {[string match {[a-zA-Z0-9._~-]} $b]} {
            append out $b
        } else {
            append out [format %%%02X [scan $b %c]]
        }
    }
    return $out
}

# ---- asking the sky ----
proc weather-poke {src every} {
    if {[info exists ::weather_inflight($src)]} return
    # the freshness guard: a desk switch ticks every widget, and the
    # sky has not changed because the desk did
    set now [clock milliseconds]
    if {[info exists ::weather_asked($src)]
            && $now - $::weather_asked($src) < $every} return
    set ::weather_asked($src) $now
    set ::weather_inflight($src) 1
    wm-errand "weather $src" [list weather-bring $src]
}
proc weather-bring {src} {
    set st {stale 1}
    try {
        set st [weather-parse [weather-body $src]]
    } on error {e} {
        # the old reading stands, marked stale — yesterday's sky
        # beats a dash; said on the way DOWN, not per failed poll
        if {[info exists ::weather_state($src)]} {
            if {![dict get $::weather_state($src) stale]} {
                puts "WM: weather $src: $e"
            }
            set st [dict merge $::weather_state($src) {stale 1}]
        } else {
            puts "WM: weather $src: $e"
        }
    } finally {
        unset -nocomplain ::weather_inflight($src)
    }
    set ::weather_state($src) $st
    weather-redraw $src
}
proc weather-body {src} {
    switch -- [lindex $src 0] {
        latlon {
            lassign $src _ lat lon
        }
        name {
            lassign [weather-locate [lrange $src 1 end]] lat lon
        }
        command {
            set r [fut::await [pipe-run [lindex $src 1] -stderr drop \
                                   -timeout 15000]]
            if {[dict get $r status] != 0} {
                error "command exited [dict get $r status]"
            }
            return [dict get $r out]
        }
        default {
            error "a source speaks latlon, name or command,\
 not «[lindex $src 0]»"
        }
    }
    weather-slurp [weather-url $::weather_api \
        "/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=7"]
}
proc weather-locate {words} {
    set q [join $words " "]
    if {[info exists ::weather_geo($q)]} { return $::weather_geo($q) }
    set j [json::json2dict [weather-slurp [weather-url $::weather_geocoder \
        "/v1/search?count=1&name=[weather-quote $q]"]]]
    if {[catch {dict get $j results} rs] || ![llength $rs]} {
        error "no place called «$q»"
    }
    set r [lindex $rs 0]
    set ::weather_geo($q) [list [dict get $r latitude] [dict get $r longitude]]
    puts "WM: weather: «$q» is [dict get $r name] at [join $::weather_geo($q) ,]"
    return $::weather_geo($q)
}
# Open-Meteo's shape, from the sky or from a command: `current` for
# the strip, `daily` for the sheet — parallel arrays folded into one
# list of days.
proc weather-parse {out} {
    if {[catch {json::json2dict $out} j] || [catch {dict size $j}]
            || ![dict exists $j current] || ![dict exists $j daily]} {
        error "an answer, but not the API's shape"
    }
    set cur [dict get $j current]
    set st [dict create stale 0 \
        temp [dict get $cur temperature_2m] \
        code [dict get $cur weather_code] \
        isday [dict getdef $cur is_day 1]]
    set d [dict get $j daily]
    set days {}
    set rains [dict getdef $d precipitation_probability_max {}]
    set i 0
    foreach date [dict get $d time] code [dict get $d weather_code] \
        hi [dict get $d temperature_2m_max] lo [dict get $d temperature_2m_min] {
        lappend days [dict create date $date code $code hi $hi lo $lo \
            rain [lindex $rains $i]]
        incr i
    }
    dict set st days $days
}
proc weather-redraw {src} {
    foreach name [array names ::widget_win] {
        if {![dict exists $::widgets $name]} continue
        set opts [widget-opts $name]
        if {[dict get $opts -type] ne "weather"} continue
        if {[dict get $opts -source] ne $src} continue
        set c $::widget_win($name)
        if {[winfo exists $c]} { catch {weather-draw $c $opts} }
    }
    # a standing sheet shows this sky: redraw it from the fresh state
    # NOW, not on the next quarter-hour tick — but only when the
    # answer actually MOVED something, or a steady poll would blink
    # the sheet once per beat
    if {[winfo exists .wxsheet]
            && [lindex $::weather_sheet_key 0] eq $src
            && [weather-sheet-signature] ne $::weather_sheet_sig} {
        set k $::weather_sheet_key
        weather-sheet-close
        weather-sheet-open {*}$k
    }
}

# ---- the widget on the strip ----
proc weather-widget-build {w opts} {
    set fg [dict get $opts -foreground]
    set bg [dict get $opts -background]
    label $w.icon -background $bg
    label $w.temp -font WeatherFont -foreground $fg -background $bg
    label $w.label -font WeatherLabelFont -foreground $fg -background $bg
    bind $w.icon <Destroy> {catch {image delete weather-icon:%W}}
    set lbl [dict get $opts -label]
    if {[weather-widget-shape $opts] eq "row"} {
        pack $w.icon -side left
        pack $w.temp -side left -padx [list $::weather_gap 0]
        if {$lbl ne ""} {
            pack $w.label -side left -padx [list $::weather_gap 0]
        }
    } else {
        pack $w.icon -side top
        pack $w.temp -side top
        if {$lbl ne ""} { pack $w.label -side top }
    }
    # the click the forecast sheet answers — bound on the frame and
    # every label, together they tile the face
    set open [list weather-sheet-toggle [dict get $opts -source] \
                  [dict get $opts -on] $lbl]
    foreach t [list $w $w.icon $w.temp $w.label] {
        bind $t <ButtonPress-1> $open
    }
    weather-widget-tick $w $opts
}
# The clock's reasoning over this widget's own measurements: the glyph
# is square at the temperature's linespace.
proc weather-widget-shape {opts} {
    set edges [expr {2 * [dict get $opts -padding] + 2}]
    set ih [font metrics WeatherFont -linespace]
    switch -- [dict get $opts -band] {
        horizontal {
            set stack [expr {2 * $ih + $edges}]
            return [expr {[dict get $opts -across] >= $stack ? "stack" : "row"}]
        }
        vertical {
            set row [expr {$ih + $::weather_gap \
                           + [font measure WeatherFont "+20°"] + $edges}]
            if {[dict get $opts -label] ne ""} {
                incr row [expr {$::weather_gap + [font measure \
                    WeatherLabelFont [dict get $opts -label]]}]
            }
            return [expr {[dict get $opts -across] >= $row ? "row" : "stack"}]
        }
    }
    return row
}
proc weather-widget-tick {w opts} {
    # ask first — the answer lands later through weather-redraw —
    # then draw what is known now
    weather-poke [dict get $opts -source] [dict get $opts -every]
    weather-draw $w $opts
    # the sheet rides this beat for everything but the data itself:
    # midnight, a theme flip, a workarea reshaped
    if {[winfo exists .wxsheet]
            && [weather-sheet-signature] ne $::weather_sheet_sig} {
        set k $::weather_sheet_key
        weather-sheet-close
        weather-sheet-open {*}$k
    }
}
proc weather-draw {w opts} {
    set src [dict get $opts -source]
    set st [expr {[info exists ::weather_state($src)] \
                      ? $::weather_state($src) : {stale 1}}]
    set ink [expr {[dict get $st stale] \
                       ? [themed dim] : [dict get $opts -foreground]}]
    if {[dict exists $st temp]} {
        set text [weather-degrees [dict get $st temp]]
        set group [weather-group [dict get $st code] [dict get $st isday]]
    } else {
        set text "—"
        set group cloud
    }
    set ih [font metrics WeatherFont -linespace]
    image create photo weather-icon:$w.icon \
        -format [list svg -scaletoheight $ih] \
        -data [weather-svg $group $ink [dict get $opts -background]]
    $w.icon configure -image weather-icon:$w.icon
    $w.temp configure -text $text
    $w.label configure -text [dict get $opts -label]
}
# +21° reads as weather where 21° reads as an oven's dial.
proc weather-degrees {t} {
    set n [expr {round($t)}]
    expr {$n > 0 ? "+$n°" : "$n°"}
}

# ---- the sky's faces ----
# WMO folded into a dozen: the codes differ in intensity the strip
# has no room to say, and a glance wants the KIND of sky, not the
# millimetres. Clear and partly get a night face by is_day; the rest
# look the same in the dark.
proc weather-group {code isday} {
    set g [expr {
        $code <= 1 ? "clear" :
        $code == 2 ? "partly" :
        $code == 3 ? "cloud" :
        $code in {45 48} ? "fog" :
        $code >= 51 && $code <= 57 ? "drizzle" :
        $code >= 61 && $code <= 67 ? "rain" :
        $code >= 71 && $code <= 77 || $code in {85 86} ? "snow" :
        $code >= 80 && $code <= 82 ? "shower" :
        $code >= 95 ? "thunder" : "cloud"}]
    if {$g in {clear partly} && !$isday} { return $g-night }
    return $g
}
# One ink, shapes only — the tiny-svg renderer draws no <text>, and a
# monochrome glyph follows the theme for free; stale simply hands a
# dimmer ink in. The moon's bite and nothing else takes the ground
# colour.
proc weather-svg {group ink bg} {
    set svg "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 36 36\">"
    switch -- $group {
        clear {
            append svg [weather-sun 18 18 7 $ink]
        }
        clear-night {
            append svg "<circle cx=\"18\" cy=\"18\" r=\"11\" fill=\"$ink\"/>\
<circle cx=\"24\" cy=\"13\" r=\"9\" fill=\"$bg\"/>"
        }
        partly {
            append svg [weather-sun 11 10 4.5 $ink] [weather-cloud $ink 6]
        }
        partly-night {
            append svg "<circle cx=\"11\" cy=\"9\" r=\"6\" fill=\"$ink\"/>\
<circle cx=\"15\" cy=\"6\" r=\"5\" fill=\"$bg\"/>" [weather-cloud $ink 6]
        }
        cloud {
            append svg [weather-cloud $ink 6]
        }
        fog {
            append svg [weather-cloud $ink 0] \
                "<path d=\"M8 26 H28 M11 31 H31\" stroke=\"$ink\"\
 stroke-width=\"2.5\" fill=\"none\"/>"
        }
        drizzle {
            append svg [weather-cloud $ink 0]
            foreach {x y} {13 27 19 30 25 27} {
                append svg "<circle cx=\"$x\" cy=\"$y\" r=\"1.7\" fill=\"$ink\"/>"
            }
        }
        rain {
            append svg [weather-cloud $ink 0] \
                "<path d=\"M14 25 L12 31 M20 25 L18 31 M26 25 L24 31\"\
 stroke=\"$ink\" stroke-width=\"2.5\" fill=\"none\"/>"
        }
        shower {
            append svg [weather-cloud $ink 0] \
                "<path d=\"M13 24 L10 34 M19 24 L16 34 M25 24 L22 34\"\
 stroke=\"$ink\" stroke-width=\"2.5\" fill=\"none\"/>"
        }
        snow {
            append svg [weather-cloud $ink 0]
            foreach {x y} {13 28 19 31 25 28} {
                append svg "<circle cx=\"$x\" cy=\"$y\" r=\"2\" fill=\"none\"\
 stroke=\"$ink\" stroke-width=\"1.5\"/>"
            }
        }
        thunder {
            append svg [weather-cloud $ink 0] \
                "<polygon points=\"20,21 13,29 17,29 15,36 23,26 19,26\"\
 fill=\"$ink\"/>"
        }
    }
    append svg "</svg>"
    return $svg
}
proc weather-sun {cx cy r ink} {
    set svg "<circle cx=\"$cx\" cy=\"$cy\" r=\"$r\" fill=\"$ink\"/>"
    set near [expr {$r + 2.5}]
    set far [expr {$r + 6.5}]
    foreach {dx dy} {1 0 -1 0 0 1 0 -1 0.707 0.707 -0.707 0.707 0.707 -0.707 -0.707 -0.707} {
        append svg "<path d=\"M[expr {$cx + $near*$dx}] [expr {$cy + $near*$dy}]\
 L[expr {$cx + $far*$dx}] [expr {$cy + $far*$dy}]\" stroke=\"$ink\"\
 stroke-width=\"2.2\" fill=\"none\"/>"
    }
    return $svg
}
# The puff: three circles and a rect make the silhouette; dy slides
# it down when nothing falls underneath.
proc weather-cloud {ink dy} {
    set svg ""
    foreach {cx cy r} [list 11 [expr {15 + $dy}] 5.5 \
                            19 [expr {11 + $dy}] 7 \
                            27 [expr {16 + $dy}] 4.5] {
        append svg "<circle cx=\"$cx\" cy=\"$cy\" r=\"$r\" fill=\"$ink\"/>"
    }
    append svg "<rect x=\"11\" y=\"[expr {14 + $dy}]\" width=\"16\"\
 height=\"7\" fill=\"$ink\"/>"
    return $svg
}

# ---- the forecast sheet: the click the header promised ----
# The calendar's manners exactly: a toggle, the corner the panel's
# side names, no keyboard, no grab, deliberately NOT in popups-close's
# modal set (no router to give back), a click anywhere on the sheet
# dismisses it. It draws the days already standing in the state — a
# glance works offline, in yesterday's ink.
proc weather-sheet-toggle {src on label} {
    popups-close
    if {[winfo exists .wxsheet]} {
        set was $::weather_sheet_key
        weather-sheet-close
        if {$was eq [list $src $on $label]} return
    }
    weather-sheet-open $src $on $label
}
proc weather-sheet-close {} {
    if {![winfo exists .wxsheet]} return
    destroy .wxsheet
    puts "WM: weather sheet closed"
}
proc weather-sheet-open {src on label} {
    set ::weather_sheet_key [list $src $on $label]
    set st [expr {[info exists ::weather_state($src)] \
                      ? $::weather_state($src) : {stale 1}}]
    set ink [expr {[dict get $st stale] ? [themed dim] : [themed ink]}]
    set days [dict getdef $st days {}]
    toplevel .wxsheet -background $::OUTLINE
    wm overrideredirect .wxsheet 1
    wm withdraw .wxsheet
    frame .wxsheet.f -background [themed raised] -borderwidth 5
    set vert [widget-popup-vertical $on]
    # the title: the label's word, or the name the source spoke
    set title $label
    if {$title eq "" && [lindex $src 0] eq "name"} {
        set title [join [lrange $src 1 end] " "]
    }
    set r0 0
    if {$title ne ""} {
        label .wxsheet.f.title -font WeatherSheetFont -foreground $ink \
            -background [themed raised] -text $title
        if {$vert} {
            grid .wxsheet.f.title -row 0 -column 0 -columnspan 5 -pady {0 3}
        } else {
            grid .wxsheet.f.title -row 0 -column 0 \
                -columnspan [expr {max(1, [llength $days])}] -pady {0 3}
        }
        set r0 1
    }
    if {![llength $days]} {
        # a sheet with nothing to say yet says so in one drawn dash
        label .wxsheet.f.none -font WeatherSheetFont -foreground $ink \
            -background [themed raised] -text "—"
        grid .wxsheet.f.none -row $r0 -column 0 -padx 18 -pady 10
    }
    set i 0
    foreach day $days {
        weather-sheet-day .wxsheet.f $i $r0 $day $ink $vert
        incr i
    }
    # a row of days reads as a table when the cells agree on a width
    if {!$vert} {
        for {set c 0} {$c < $i} {incr c} {
            grid columnconfigure .wxsheet.f $c -uniform day
        }
    }
    update idletasks
    set W [expr {[winfo reqwidth .wxsheet.f] + 2}]
    set H [expr {[winfo reqheight .wxsheet.f] + 2}]
    place .wxsheet.f -x 1 -y 1
    lassign [workarea] wx wy ww wh
    lassign [widget-popup-corner $on] halign valign
    set X [place-axis $wx $ww $W $halign]
    set Y [place-axis $wy $wh $H $valign]
    wm geometry .wxsheet ${W}x${H}+${X}+${Y}
    stack-layer .wxsheet $::LAYER_POPUP
    wm deiconify .wxsheet
    update idletasks
    bind .wxsheet <ButtonPress-1> weather-sheet-close
    set ::weather_sheet_sig [weather-sheet-signature]
    puts "WM: weather sheet open ${W}x${H}+${X}+${Y} ([llength $days] days)"
}
# One day, one line of the sheet's ONE grid: the weekday in the
# calendar's manner (locale names, weekend in the dim ink), the sky's
# glyph, the high, the low, and the chance of rain when the API said
# one. A line lies down when the sheet does. One grid and not a pane
# per day, because a pane packed its fields to its own measure and
# the sheet's columns stood ragged — a shared grid is what makes a
# column a column. Lying down, the names take the left edge and the
# numbers the right, so the degree signs stand in file.
proc weather-sheet-day {f i r0 day ink vert} {
    set t [clock scan [dict get $day date] -format %Y-%m-%d]
    set wkend [expr {[clock format $t -format %u] >= 6}]
    set dayink [expr {$wkend ? [themed dim] : $ink}]
    label $f.n$i -font WeatherSheetFont -foreground $dayink \
        -background [themed raised] \
        -text [clock format $t -format %a -locale current]
    set ih [expr {[font metrics WeatherSheetFont -linespace] * 3 / 2}]
    label $f.i$i -background [themed raised]
    bind $f.i$i <Destroy> {catch {image delete weather-day:%W}}
    image create photo weather-day:$f.i$i \
        -format [list svg -scaletoheight $ih] \
        -data [weather-svg [weather-group [dict get $day code] 1] $ink \
                   [themed raised]]
    $f.i$i configure -image weather-day:$f.i$i
    label $f.h$i -font WeatherSheetFont -foreground $ink \
        -background [themed raised] \
        -text [weather-degrees [dict get $day hi]]
    label $f.l$i -font WeatherSheetFont -foreground [themed dim] \
        -background [themed raised] \
        -text [weather-degrees [dict get $day lo]]
    set parts [list $f.n$i $f.i$i $f.h$i $f.l$i]
    set rain [dict get $day rain]
    if {$rain ne ""} {
        label $f.r$i -font WeatherSheetFont -foreground [themed dim] \
            -background [themed raised] -text "$rain%"
        lappend parts $f.r$i
    }
    set j 0
    foreach p $parts s {w {} e e e} {
        if {$p eq ""} break
        if {$vert} {
            grid $p -row [expr {$r0 + $i}] -column $j -sticky $s \
                -padx 3 -pady 2
        } else {
            grid $p -row [expr {$r0 + $j}] -column $i -padx 5 -pady 1
        }
        incr j
    }
}
proc weather-sheet-signature {} {
    set src [lindex $::weather_sheet_key 0]
    list $::weather_sheet_key \
        [expr {[info exists ::weather_state($src)] \
                   ? $::weather_state($src) : {}}] \
        [themed raised] [themed ink] [workarea]
}
