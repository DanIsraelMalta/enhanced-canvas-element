package require Tk
package require snit

# a zoomable canvas with automatic conversion from "world" coordinate to "screen" and "view" coordinate systems
# based on snit widget
::snit::widgetadaptor zoom-canvas {
    # variable "my" is an array collecting all object's variables
    variable my -array {}  ; # initialized in constructor
    
    # NOTE that default values can be externally changed by setting
    # the "Tk options database" as follows:
    #    option add *Canvas.framerate     25
    #    ...
    # NOTE that a zoom-canvas-widget's class is still "Canvas".
    # In the same way, you can set the "Canvas" options for
    #   background, cursor, ....
    
    option -userdata -default {}  ; # can contain anything ...
    option -zoomratio -type {snit::double -min 1.0} -default 1.4142135623730950488016887242097
    option -pointbmp ;# WARNING  prefix "@" required if it's a file ..
    # zoom-canvas is a widget based on the canvas widget.
    # We choose to propagate all *options* of the underlying widget,
    # and all *commands*.
    # The only removed options/commands  are those related vith scrollbars
    # (they are useless)
    delegate option * to hull \
            except {-scrollregion -confine
                -xscrollcommand -yscrollcommand
                -xscrollincrement -yscrollincrement
            }
    delegate method * to hull \
            except {xview yview canvasx canvasy}
    
    # Handling MouseWheel event is rather complex, given the differences between
    #  various platforms.
    # TIP#171 (implemented in 8.6) removes some differences between "win32" and
    #  other platforms.
    # Note that MacOs implementation has a bug "MouseWheel on Mac : wrong x y"
    # (see http://sourceforge.net/tracker/?func=detail&aid=3609839&group_id=12997&atid=112997)
    # and this implementation provides a patch workaround.
    proc SetMouseWheelBindings {} {
        # WARNING: on tcltk 8.6 behavior should be different (see TIP #171)
        set tkwinsys [tk windowingsystem]
        switch -- $tkwinsys {
            "win32" -
            "x11" {
                if { $tkwinsys == "win32"} {
                    set tkVer [package present Tk]
                    if { [package vcompare $tkVer 8.6b2] < 0 } {
                        # On win32 MouseWheel on a widget requires focus
                        bind ZoomCanvas <Enter>         [myproc SetFocus %W]
                        bind ZoomCanvas <Leave>         [myproc RestoreFocus]
                    }
                } else {
                    # x11
                    bind ZoomCanvas <Button-4> {
                        event generate <MouseWheel> -x %x -y %y -delta +128
                    }
                    bind ZoomCanvas <Button-5> {
                        event generate <MouseWheel> -x %x -y %y -delta -128
                    }
                }
                bind ZoomCanvas <MouseWheel>    { %W rzoom %D {*}[%W V2W %x %y] }
            }
            "aqua" {
                bind ZoomCanvas <MouseWheel>    {
                    %W rzoom %D {*}[%W V2W [zoom-canvas::MW_correction %W %x %y]]
                }
            }
        }
    }

    
    typevariable prevFocus ;# widget with focus before zoom-canvas is entered
    
    proc SetFocus {w} {
        set prevFocus [focus -displayof $w]
        focus $w
    }
    proc RestoreFocus {} {
        focus $prevFocus
    }
    
    # WARNING: just for "MouseWheel on Mac" bug ...  remove when fixed
    proc MW_correction { w x y } {
        set top [winfo toplevel $w]
        set topx [winfo rootx $top]
        set topy [winfo rooty $top]
        
        set wx [winfo rootx $w]
        set wy [winfo rooty $w]
        
        set x [expr {$x-($wx-$topx)}]
        set y [expr {$y-($wy-$topy)}]
        list $x $y
    }
    
    
    typeconstructor {
        # define a 'pseudo' Class binding
        bind ZoomCanvas <ButtonPress-1> { %W _scan_mark %x %y }
        bind ZoomCanvas <B1-Motion>     { %W _scan_dragto %x %y }
        SetMouseWheelBindings
    }
    
    # Note: tag "draggable" has a special meaning ...
    method _scan_mark { x y } {
        if { [$hull find withtag current&&draggable] == {} } {
            set my(panning) true
            $hull scan mark $x $y
        } else {
            set my(panning) false
        }
    }
    method _scan_dragto { x y } {
        if { $my(panning) } {
            $hull scan dragto $x $y 1
        }
    }
    
    constructor {args} {
        installhull using canvas
        bindtags $win [linsert [bindtags $win] 1 ZoomCanvas]
        set my(zoom) 1.0
        $win configurelist $args
    }
    
    destructor {
    }
    
    # redefine "create" method for new type "point"
    method create { itemtype args } {
        if { $itemtype == "point" } {
            set bmp  $options(-pointbmp)
            # remove -bitmap xxx from $args
            set idx [lsearch -exact $args -bitmap]
            if { $idx != -1 } {
                set bmp [lindex $args ${idx}+1]
                set args [lreplace $args $idx ${idx}+1]
            }
            $hull create bitmap {*}$args -bitmap $bmp
        } else {
            uplevel $hull create $itemtype $args
        }
    }
    
    # return the World-Coords of the viewport's center
    method _World_CenterOfViewport {} {
        set dVx [winfo width  $win]
        set dVy [winfo height $win]
        
        return [$win V2W [expr {$dVx/2.0}] [expr {$dVy/2.0}]]
    }
    
    # Absolute zoom
    #   f : (0 ...)
    #   (Wx Wy)   is the pivot of zooming  (in World coords)
    #   (if not specified, is point related to center of viewport)
    method zoom {{f {}} {Wx {}} {Wy {}}} {
        if { $f == {} } {
            return $my(zoom)
        }
        if { $Wx == {} || $Wy == {} } {
            lassign [$win _World_CenterOfViewport]  Wx Wy
        }
        
        # (px,px) is the screen-point related to (Wx,Wy) before zooming
        lassign [$win W2V $Wx $Wy] px py
        
        set f [expr double($f)]
        set A [expr $f/$my(zoom)]
        set my(zoom) $f
        
        $hull scale all 0 0 $A $A
        
        # collimate points ...
        $self overlap $Wx $Wy  $px $py
        event generate $win <<Zoom>> -data $my(zoom)
    }
    
    
    # relative Zoom
    #  df : currently meaningful its sign only
    # ---
    # relative zoom
    #  df : currently meaningful its sign only
    #   (Wx Wy)   is the pivot of zooming  (in World coords)
    #   (if not specified, is point related to center of viewport)
    method rzoom { df {Wx {}} {Wy {}} } {
        # do nothing if $df it's zero
        if { abs($df) < 0.001 } return
        
        set z $my(zoom)
        if { $df > 0 } {
            set f [expr {$z*$options(-zoomratio)}]
        } else {
            set f [expr {$z/double($options(-zoomratio))}]
        }
        $win zoom $f $Wx $Wy
    }
    
    
    # collimate World-Point (Wx,Wy) with Viewport-Point (Vx,Vy)
    method overlap {Wx Wy Vx Vy} {
        set Vx [expr {round($Vx)}]
        set Vy [expr {round($Vy)}]
        
        lassign [$win W2V $Wx $Wy] Vox Voy
        set Vox [expr {round($Vox)}]
        set Voy [expr {round($Voy)}]
        $hull scan mark $Vox $Voy
        $hull scan dragto $Vx $Vy 1
    }
    
    # move the whole canvas (panning) by program
    # Note that dWx,dWy are expressed in World-Coords
    method scrollviewport { dWx dWy } {
        lassign [$win W2C $dWx $dWy] dVx dVy
        set dVx [expr {round(-$dVx)}]
        set dVy [expr {round(-$dVy)}]
        $hull scan mark 0 0
        $hull scan dragto $dVx $dVy 1
    }
    
    
    # -- helpers --------------------------------------------------------------
    
    proc flatten {args} {
        if { [llength $args] == 1 } {
            set args {*}$args
        }
        return $args
    }
    
    # Viewport to World coords conversion
    method V2W {args} {
        if { [catch { $win _V2W [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    
    method _V2W {L} {
        set R {}
        foreach {Vx Vy} $L {
            set x1 [expr {[$hull canvasx $Vx]/(+$my(zoom))}]
            set y1 [expr {[$hull canvasy $Vy]/(-$my(zoom))}]
            lappend R $x1 $y1
        }
        return $R
    }
    
    # World to Viewport coords conversion
    method W2V {args} {
        if { [catch { $win _W2V [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    
    method _W2V {L} {
        set R {}
        foreach {Wx Wy} $L {
            set x1 [expr { $Wx*$my(zoom) - [$hull canvasx 0]}]
            set y1 [expr {-$Wy*$my(zoom) - [$hull canvasy 0]}]
            lappend R $x1 $y1
        }
        return $R
    }
    
    # World to Canvas coords conversion
    method W2C {args} {
        if { [catch { _W2C $my(zoom) [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    # Canvas to World coords conversion
    method C2W {args} {
        if { [catch { _W2C [expr {1.0/$my(zoom)}] [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    
    proc _W2C { zoom L } {
        set R {}
        foreach {x y} $L {
            set x1 [expr {$x*$zoom}]
            set y1 [expr {-$y*$zoom}]  ;# NOTE: inverted Y !
            lappend R $x1 $y1
        }
        return $R
    }
    
    # Viewport to Canvas coords conversion
    method V2C {args} {
        if { [catch { $win _V2C [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    
    method _V2C { L } {
        set R {}
        foreach {x y} $L {
            set x1 [$hull canvasx $x]
            set y1 [$hull canvasy $y]
            lappend R $x1 $y1
        }
        return $R
    }
    
    # Canvas to Viewport coords conversion
    method C2V {args} {
        if { [catch { $win _C2V [flatten {*}$args] } res] } {
            error "malformed coordList: must be a sequence of x y ... or a list of x y .."
        }
        return $res
    }
    
    method _C2V { L } {
        set R {}
        foreach {x y} $L {
            set x1 [expr {$x - [$hull canvasx 0]}]
            set y1 [expr {$y - [$hull canvasy 0]}]
            lappend R $x1 $y1
        }
        return $R
    }
    
    # Set the best zoom and center the worldArea in the viewport.
    # what:
    #   x - best width
    #   y - best height
    #  xy - best fit (default)
    # worldArea:
    #  list of 4 World-Coords
    #  (default is the the bounding-box of all items)
    method zoomfit  {{what xy} {worldArea {}}} {
        set dVX [winfo width $win]
        set dVY [winfo height $win]
        set b [expr {2*([$hull cget -border]+[$hull cget -highlightthickness])}]
        incr dVX -$b
        incr dVY -$b
        
        # compute bbox (in World-Coords). Warning: Wy0 *may be* greater than Wy1
        if { $worldArea == {} } {
            # if bbox is empty,then set a dummy -1 -1 1 1 bbox,
            # so that origin will appear at the viewport center
            set bbox [$hull bbox all]
            if { $bbox == {} } {
                lassign {-1.0 -1.0 1.0 1.0} Wx0 Wy0 Wx1 Wy1
            } else {
                # note that bbox "may be overestimated by a few pixel",
                # therefore .. subtract 1 pixel by each side
                lassign $bbox bx0 by0 bx1 by1
                incr bx0 ; incr by0
                incr bx1 -1 ; incr by1 -1
                lassign [$win C2W $bx0 $by0 $bx1 $by1] Wx0 Wy0 Wx1 Wy1
            }
        } else {
            lassign $worldArea Wx0 Wy0 Wx1 Wy1
        }
        set dWX [expr {double(abs($Wx1-$Wx0))}]
        set dWY [expr {double(abs($Wy1-$Wy0))}]
        
        set rX [expr {$dVX/$dWX}]
        set rY [expr {$dVY/$dWY}]
        
        switch -- $what {
            x {
                set ratio $rX
            }
            y {
                set ratio $rY
            }
            xy {
                set ratio [expr min($rX,$rY)]
            }
        }
        set Vx [expr {($dVX+$b-$ratio*$dWX)/2.0}]
        set Vy [expr {($dVY+$b-$ratio*$dWY)/2.0}]
        $win zoom $ratio
        $win overlap [expr min($Wx0,$Wx1)] [expr max($Wy0,$Wy1)] $Vx $Vy
    }
}
