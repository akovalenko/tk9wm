# fut.tcl — future/await over Tcl coroutines and the event loop.
#
# VENDORED, not linked: this file comes from the owner's tools/tcl
# collection (its own design notes live there), and tk9wm carries a
# copy because a window manager may not depend on a checkout that
# happens to sit next to it. Keep the copy honest — fixes belong
# upstream first.
#
# Why a WM wants it: everything this desk asks of the world outside
# itself must not block the event loop, because the loop IS the desk
# — a stalled handler freezes every window on the screen (the XIM
# post-mortem). Hand-rolled, each such errand grows the same three
# pieces: a channel callback, a state variable and a guard timer.
# With futures the errand reads top to bottom and the guard is
# `fut::timeout`.
#
# fut.tcl — future/await core for the coroutine substrate: BASE LAYER
# ONLY.  Pure Tcl 8.6+/9: needs nothing but the event loop and
# coroutines.  No I/O, no Thread, no http here — bindings that turn
# sockets, exec pipelines, thread pools etc. into futures belong in a
# separate optional layer (fut-*.tcl) so this core stays dependency-free
# and small enough to audit in one sitting.
#
# The model is deliberately NOT ES6 promises (cancellation cannot be
# retrofitted onto that model; here it is first-class) and await-first
# rather than then-first:
#
#   set f [fut::new]              ;# -> token
#   fut::fulfill $f $value        ;# producer: settle ok (first settle wins)
#   fut::fail $f $msg ?$options?  ;# producer: settle err; $options is a
#                                  # return-options dict (e.g. from catch);
#                                  # default {-code error -errorcode {FUT FAILED}}
#   fut::cancel $f ?$msg?         ;# anyone: settle err with -errorcode
#                                  # {FUT CANCELLED}, then run the producer's
#                                  # oncancel handlers so the underlying
#                                  # operation gets aborted; 0 if too late
#   fut::oncancel $f cmdprefix    ;# producer: register the aborter ($f
#                                  # appended); fires (once) even when
#                                  # registered after the cancellation
#   fut::onsettle $f cmdprefix    ;# callback API ($f appended), runs via the
#                                  # event loop; await is built on it
#   fut::await $f                 ;# coroutine only: park until settled,
#                                  # return the value or rethrow the error
#                                  # (options preserved, so callers can
#                                  # `trap {FUT CANCELLED}`)
#   fut::state $f                 ;# pending | ok | err
#   fut::peek $f                  ;# dict {state value opts}: inspect without
#                                  # consuming or throwing
#   fut::forget $f                ;# drop a settled future's storage
#   fut::discard $f               ;# dispose in any state: cancel if still
#                                  # pending, then drop the storage; an
#                                  # already-forgotten token is fine
#   fut::take $f                  ;# await + discard on every path: consume
#                                  # the future, its storage does not
#                                  # outlive the await
#
# Injection (what the task/scope layer builds cancellation on):
#   fut::interrupt $co ?$msg? ?$options?
#                                 ;# inject an error into a coroutine's await.
#                                  # Parked in fut::await -> it wakes up
#                                  # rethrowing (default {FUT CANCELLED}) and
#                                  # the future it was parked on will NOT wake
#                                  # it again.  Running -> the injection is
#                                  # sticky and fires at its next await entry:
#                                  # awaits are the cancellation points.
#   fut::forget-coro $co          ;# drop await bookkeeping of a coroutine
#                                  # that died while parked (the task layer's
#                                  # reaper calls this on the kill path)
#
# Combinators (still base layer — they need only the core and timers):
#   fut::all $flist               ;# -> future of the value list (input
#                                  # order); fail-fast: the first error
#                                  # settles the aggregate and CANCELS the
#                                  # still-pending inputs
#   fut::race $flist              ;# first settlement wins; the losers are
#                                  # CANCELLED (deliberate difference from
#                                  # ES6 race)
#   fut::after $ms ?$value?       ;# timer future; cancelling it stops the
#                                  # timer
#   fut::timeout $f $ms           ;# $f's own result, or — after $ms —
#                                  # cancel $f and fail with {FUT TIMEOUT}
#
# Discipline:
# - settlement callbacks and coroutine wakeups are ALWAYS trampolined
#   through the event loop (after 0): a waiter is never resumed from
#   inside the producer's stack, so there is no callback reentrancy.
# - a future is one-shot; a second settle is a silent no-op (first wins).
# - on cancel the aborters are queued before the waiters' wakeups, but
#   both run from the event loop: don't rely on ordering beyond that.
# - storage lives until fut::forget; the task/scope layer will own
#   lifecycles later, long-running code forgets what it awaited for now.

namespace eval fut {
    variable seq 0
    variable F
    array set F {}
    # Awaiting($co) = the future $co is parked on right now (inside await)
    # Interrupt($co) = {msg options} pending injection for $co
    variable Awaiting
    array set Awaiting {}
    variable Interrupt
    array set Interrupt {}
}

proc fut::new {} {
    variable seq
    variable F
    set f "fut#[incr seq]"
    set F($f) [dict create state pending cancelled 0 value {} opts {} \
                   waiters {} oncancel {}]
    return $f
}

proc fut::Get {f} {
    variable F
    if {![info exists F($f)]} {
        error "fut: unknown future \"$f\""
    }
    return $F($f)
}

proc fut::state {f} {
    dict get [Get $f] state
}

# The single state transition; 1 if this call settled the future,
# 0 if it was already settled.
proc fut::Settle {f state value opts} {
    variable F
    Get $f
    if {[dict get $F($f) state] ne "pending"} { return 0 }
    dict set F($f) state $state
    dict set F($f) value $value
    dict set F($f) opts $opts
    foreach w [dict get $F($f) waiters] {
        ::after 0 [list {*}$w $f]
    }
    dict set F($f) waiters {}
    return 1
}

proc fut::fulfill {f value} {
    Settle $f ok $value {}
}

proc fut::fail {f msg {options {}}} {
    if {$options eq {}} {
        set options [list -code error -errorcode {FUT FAILED}]
    }
    Settle $f err $msg $options
}

proc fut::cancel {f {msg cancelled}} {
    variable F
    Get $f
    if {[dict get $F($f) state] ne "pending"} { return 0 }
    foreach c [dict get $F($f) oncancel] {
        ::after 0 [list {*}$c $f]
    }
    dict set F($f) oncancel {}
    dict set F($f) cancelled 1
    Settle $f err $msg [list -code error -errorcode {FUT CANCELLED}]
}

proc fut::oncancel {f cmdprefix} {
    variable F
    Get $f
    if {[dict get $F($f) state] eq "pending"} {
        dict lappend F($f) oncancel $cmdprefix
    } elseif {[dict get $F($f) cancelled]} {
        ::after 0 [list {*}$cmdprefix $f]
    }
    # settled without cancellation: nothing will ever need aborting
    return
}

proc fut::onsettle {f cmdprefix} {
    variable F
    Get $f
    if {[dict get $F($f) state] eq "pending"} {
        dict lappend F($f) waiters $cmdprefix
    } else {
        ::after 0 [list {*}$cmdprefix $f]
    }
    return
}

proc fut::await {f} {
    variable Awaiting
    set co [info coroutine]
    if {$co eq ""} {
        error "fut::await must be called from inside a coroutine"
    }
    CheckInterrupt $co
    if {[dict get [Get $f] state] eq "pending"} {
        set Awaiting($co) $f
        onsettle $f [list [namespace current]::Wake $co]
        yield
        unset -nocomplain Awaiting($co)
        CheckInterrupt $co
    }
    set d [Get $f]
    if {[dict get $d state] eq "ok"} {
        return [dict get $d value]
    }
    return -options [dict get $d opts] [dict get $d value]
}

# Wake drops resumes for coroutines that died while parked (killed by
# rename): that bookkeeping belongs to the task layer, not the core.
proc fut::Wake {co f} {
    if {[llength [info commands $co]]} { $co }
}

# Throws the pending injection (if any) in the caller's caller — i.e.
# out of fut::await into the awaiting code.
proc fut::CheckInterrupt {co} {
    variable Interrupt
    if {[info exists Interrupt($co)]} {
        lassign $Interrupt($co) msg opts
        unset Interrupt($co)
        return -options $opts $msg
    }
}

proc fut::interrupt {co {msg cancelled} {options {}}} {
    variable Interrupt
    variable Awaiting
    if {![llength [info commands $co]]} { return 0 }
    if {$options eq {}} {
        set options [list -code error -errorcode {FUT CANCELLED}]
    }
    set Interrupt($co) [list $msg $options]
    if {[info exists Awaiting($co)]} {
        # steal the park: the future must not wake this coroutine later
        Unwait $Awaiting($co) [list [namespace current]::Wake $co]
        unset Awaiting($co)
        ::after 0 [list [namespace current]::Kick $co]
    }
    return 1
}

# Deliver a queued interrupt resume; skip if it was consumed meanwhile
# (e.g. a settle raced us) or the target is gone.
proc fut::Kick {co} {
    variable Interrupt
    if {[info exists Interrupt($co)] && [llength [info commands $co]]} { $co }
}

proc fut::Unwait {f cmd} {
    variable F
    if {![info exists F($f)]} return
    set ws [dict get $F($f) waiters]
    set i [lsearch -exact $ws $cmd]
    if {$i >= 0} {
        dict set F($f) waiters [lreplace $ws $i $i]
    }
}

proc fut::forget-coro {co} {
    variable Awaiting
    variable Interrupt
    if {[info exists Awaiting($co)]} {
        Unwait $Awaiting($co) [list [namespace current]::Wake $co]
        unset Awaiting($co)
    }
    unset -nocomplain Interrupt($co)
}

proc fut::peek {f} {
    set d [Get $f]
    return [dict create state [dict get $d state] \
                value [dict get $d value] opts [dict get $d opts]]
}

proc fut::forget {f} {
    variable F
    if {[info exists F($f)] && [dict get $F($f) state] ne "pending"} {
        unset F($f)
    }
}

# Dispose regardless of state.  A pending future is cancelled first (so
# producers get their oncancel aborters); the cancel queues callbacks
# through the event loop, so the storage is dropped right behind them,
# not under their feet.
proc fut::discard {f} {
    variable F
    if {![info exists F($f)]} return
    if {[dict get $F($f) state] eq "pending"} {
        cancel $f
        ::after 0 [list [namespace current]::forget $f]
        return
    }
    unset F($f)
}

# Consume: the value (or rethrown error, cancellation included) comes
# through, and the future is disposed of on every path — the awaited
# storage never outlives the await.
proc fut::take {f} {
    try {
        await $f
    } finally {
        discard $f
    }
}

# --- combinators -----------------------------------------------------

proc fut::all {flist} {
    variable F
    set agg [new]
    if {![llength $flist]} {
        fulfill $agg {}
        return $agg
    }
    dict set F($agg) all_left [llength $flist]
    dict set F($agg) all_vals [lrepeat [llength $flist] {}]
    set i -1
    foreach f $flist {
        onsettle $f [list [namespace current]::AllOne $agg [incr i] $flist]
    }
    return $agg
}

proc fut::AllOne {agg i flist f} {
    variable F
    if {![info exists F($agg)] || [dict get $F($agg) state] ne "pending"} return
    set d [Get $f]
    if {[dict get $d state] eq "ok"} {
        set vals [dict get $F($agg) all_vals]
        lset vals $i [dict get $d value]
        dict set F($agg) all_vals $vals
        dict incr F($agg) all_left -1
        if {[dict get $F($agg) all_left] == 0} {
            fulfill $agg $vals
        }
    } else {
        Settle $agg err [dict get $d value] [dict get $d opts]
        foreach g $flist {
            if {[dict get [Get $g] state] eq "pending"} { cancel $g }
        }
    }
}

proc fut::race {flist} {
    if {![llength $flist]} {
        error "fut::race: empty future list"
    }
    set agg [new]
    foreach f $flist {
        onsettle $f [list [namespace current]::RaceOne $agg $flist]
    }
    return $agg
}

proc fut::RaceOne {agg flist f} {
    variable F
    if {![info exists F($agg)] || [dict get $F($agg) state] ne "pending"} return
    set d [Get $f]
    Settle $agg [dict get $d state] [dict get $d value] [dict get $d opts]
    foreach g $flist {
        if {[dict get [Get $g] state] eq "pending"} { cancel $g }
    }
}

proc fut::after {ms {value {}}} {
    set f [new]
    set id [::after $ms [list [namespace current]::fulfill $f $value]]
    oncancel $f [list [namespace current]::AfterAbort $id]
    return $f
}

proc fut::AfterAbort {id f} {
    ::after cancel $id
}

proc fut::timeout {f ms} {
    set agg [new]
    set t [::fut::after $ms]
    onsettle $f [list [namespace current]::TimeoutMain $agg $t]
    onsettle $t [list [namespace current]::TimeoutTimer $agg $f]
    return $agg
}

proc fut::TimeoutMain {agg t f} {
    variable F
    if {![info exists F($agg)] || [dict get $F($agg) state] ne "pending"} return
    set d [Get $f]
    Settle $agg [dict get $d state] [dict get $d value] [dict get $d opts]
    cancel $t
}

proc fut::TimeoutTimer {agg f t} {
    variable F
    if {![info exists F($agg)] || [dict get $F($agg) state] ne "pending"} return
    if {[dict get [Get $t] state] ne "ok"} return   ;# the timer was cancelled
    Settle $agg err "operation timed out" \
        [list -code error -errorcode {FUT TIMEOUT}]
    cancel $f
}
