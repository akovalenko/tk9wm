/*
 * tkwmx — X11 window-manager primitives for a Tcl/Tk window manager
 * (tk9wm), working on TK'S OWN display connection.
 *
 * Why this exists: a WM written as a script needs three things no
 * script can reach — Tk's Display*, SubstructureRedirect selected on
 * it, and native dispatch of the redirect events. Doing it through a
 * generic FFI binding instead costs a second X connection (two request
 * streams, hence ordering bugs), a worker thread to watch its fd, and
 * hand-decoded structs; it also drags libffi and dlopen into the kit,
 * which rules out a fully static build.
 *
 * House rules for this package, so the seam stays thin and stable:
 *   - no pointer ever crosses into Tcl; results are values;
 *   - the display is addressed the Tk way, `-displayof WINDOW`
 *     (default: the main window), never as a handle;
 *   - a window argument is either a Tk path (.f1.slot) or a raw X id
 *     (0x600016) — a WM deals in foreign windows;
 *   - errors are Tcl errors, not status codes to forget to check;
 *   - commands live in ::tkwmx as subcommand-dispatching ensembles;
 *     the global namespace stays clean.
 */

#include <string.h>
#include <unistd.h>

#include <tcl.h>
#include <tk.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/XKBlib.h>

/* ------------------------------------------------------------------ */
/* the per-request error trap                                          */

/*
 * A WM asks about windows that may die between the request and the
 * reply — that race is ordinary life here, not an error worth raising.
 * Tk's per-request trap turns it into a flag: the call goes out, the
 * server's complaint lands HERE instead of blowing through the global
 * handler, and the caller answers {}.
 *
 * The trap matches by SERIAL, not by error/request code. A wildcard
 * handler would also swallow errors belonging to whatever Tk had in
 * flight when our XSync flushed the queue — which is exactly how this
 * first went wrong: every call reported failure because someone else's
 * error arrived inside our window. Anything not ours is passed on.
 */
typedef struct {
    unsigned long serial;	/* the request we are covering */
    int caught;
} Trap;

static int
TrapProc(void *clientData, XErrorEvent *errEventPtr)
{
    Trap *trap = (Trap *)clientData;

    if (errEventPtr->serial == trap->serial) {
	trap->caught = 1;
	return 0;		/* ours, and handled */
    }
    return 1;			/* someone else's — let it travel on */
}

static Tk_ErrorHandler
TrapBegin(Display *dpy, Trap *trap)
{
    trap->caught = 0;
    trap->serial = NextRequest(dpy);
    return Tk_CreateErrorHandler(dpy, -1, -1, -1, TrapProc, trap);
}

/* Round-trip the connection so a complaint about our request is in
 * hand, then close the trap. Non-zero = the request failed. */
static int
TrapEnd(Display *dpy, Tk_ErrorHandler handler, Trap *trap)
{
    XSync(dpy, False);
    Tk_DeleteErrorHandler(handler);
    return trap->caught;
}

/* ------------------------------------------------------------------ */
/* argument plumbing                                                   */
/* Event masks are named, not numeric, everywhere in this package; the
 * window command needs both converters that the event section defines. */
static int MaskFromObj(Tcl_Interp *interp, Tcl_Obj *obj, long *maskPtr);
static Tcl_Obj *MaskNamesObj(long mask);


/*
 * Peel a leading "-displayof WINDOW" off the argument list and answer
 * with the display it names; without it, Tk's main window's display.
 * The objcPtr/objvPtr out-parameters are advanced past the pair, so
 * every subcommand body sees only its own arguments.
 */
static Display *
DisplayOf(Tcl_Interp *interp, Tk_Window tkMain, int *objcPtr,
	  Tcl_Obj *const **objvPtr, Tk_Window *tkwinPtr)
{
    Tk_Window tkwin = tkMain;

    if (*objcPtr >= 2) {
	const char *opt = Tcl_GetString((*objvPtr)[0]);
	if (opt[0] == '-' && strcmp(opt, "-displayof") == 0) {
	    tkwin = Tk_NameToWindow(interp, Tcl_GetString((*objvPtr)[1]), tkMain);
	    if (tkwin == NULL) {
		return NULL;
	    }
	    *objcPtr -= 2;
	    *objvPtr += 2;
	}
    }
    if (tkwinPtr != NULL) {
	*tkwinPtr = tkwin;
    }
    return Tk_Display(tkwin);
}

/*
 * A window argument: a Tk pathname (made to exist, so its id is real)
 * or a raw X window id. Foreign ids are the common case here — the
 * whole point of a WM — so anything that is not a pathname is read as
 * a number and handed to the server as-is.
 */
static int
WindowFromObj(Tcl_Interp *interp, Tk_Window tkMain, Tcl_Obj *obj, Window *winPtr)
{
    const char *s = Tcl_GetString(obj);
    Tcl_WideInt id;

    if (s[0] == '.') {
	Tk_Window tkwin = Tk_NameToWindow(interp, s, tkMain);
	if (tkwin == NULL) {
	    return TCL_ERROR;
	}
	Tk_MakeWindowExist(tkwin);
	*winPtr = Tk_WindowId(tkwin);
	return TCL_OK;
    }
    if (Tcl_GetWideIntFromObj(interp, obj, &id) != TCL_OK) {
	Tcl_SetErrorCode(interp, "TKWMX", "WINDOW", (char *)NULL);
	return TCL_ERROR;
    }
    *winPtr = (Window)id;
    return TCL_OK;
}

/* A cursor NAMED the way Tk names them — "fleur", "left_ptr", or any
 * full Tk cursor spec — as an X Cursor id. An empty name is None.
 *
 * Tk's own cursor table is the right place to ask: it knows every
 * cursorfont name (no hand-copied shape numbers to get subtly wrong),
 * it caches by name, and it owns the lifetime. The alternative,
 * XCreateFontCursor per call, hands out a NEW server-side id every
 * time — a leak of one cursor per drag for the life of a WM. Nothing
 * is freed here on purpose: a handful of names lives as long as the
 * process, which is exactly the caching wanted.
 *
 * On Unix a Tk_Cursor IS the X id, cast into an opaque pointer
 * (tkUnixCursor.c: `cursorPtr->info.cursor = (Tk_Cursor) cursor`).
 * This is the one place that leans on that. */
static int
CursorFromObj(Tcl_Interp *interp, Tk_Window tkwin, Tcl_Obj *obj, Cursor *out)
{
    const char *name = Tcl_GetString(obj);
    Tk_Cursor cursor;

    if (name[0] == '\0') {
	*out = None;
	return TCL_OK;
    }
    cursor = Tk_GetCursor(interp, tkwin, name);
    if (cursor == NULL) {
	return TCL_ERROR;
    }
    *out = (Cursor)(intptr_t)cursor;
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::window                                                     */

static int
WindowObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	     Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"map", "unmap", "reparent", "move", "resize", "geometry",
	"saveset", "tree", "configure", "restack", "create", "attrs",
	"kill", "clear", NULL
    };
    enum { W_MAP, W_UNMAP, W_REPARENT, W_MOVE, W_RESIZE, W_GEOMETRY, W_SAVESET,
	   W_TREE, W_CONFIGURE, W_RESTACK, W_CREATE, W_ATTRS, W_KILL,
	   W_CLEAR };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n;
    Tcl_Obj *const *av;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }

    switch (index) {
    case W_MAP:
    case W_UNMAP:
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (index == W_MAP) {
	    XMapWindow(dpy, win);
	} else {
	    XUnmapWindow(dpy, win);
	}
	return TCL_OK;

    case W_REPARENT: {
	Window parent;
	int x, y;
	if (n != 4) {
	    Tcl_WrongNumArgs(interp, 2, objv,
			     "?-displayof window? window parent x y");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| WindowFromObj(interp, tkMain, av[1], &parent) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[2], &x) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[3], &y) != TCL_OK) {
	    return TCL_ERROR;
	}
	XReparentWindow(dpy, win, parent, x, y);
	return TCL_OK;
    }

    case W_MOVE:
    case W_RESIZE: {
	int a, b;
	if (n != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv,
			     index == W_MOVE
			     ? "?-displayof window? window x y"
			     : "?-displayof window? window width height");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[1], &a) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[2], &b) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (index == W_MOVE) {
	    XMoveWindow(dpy, win, a, b);
	} else {
	    if (a <= 0 || b <= 0) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "width and height must be positive", -1));
		Tcl_SetErrorCode(interp, "TKWMX", "VALUE", (char *)NULL);
		return TCL_ERROR;
	    }
	    XResizeWindow(dpy, win, (unsigned)a, (unsigned)b);
	}
	return TCL_OK;
    }

    case W_GEOMETRY: {
	/* {x y width height border-width depth}, or {} when the server
	 * will not say — a window that died under us is ordinary life
	 * for a WM, not an error to raise. */
	Window root;
	int x, y;
	unsigned width, height, bw, depth;
	Tcl_Obj *res;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	{
	    /* A round trip on a window that may have died between the
	     * request and the reply — the same trap the property side
	     * uses (see GetProperty), so a WM asking about a window that
	     * just went away gets {} instead of an X error killing the
	     * process. */
	    Trap trap;
	    Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	    int ok = XGetGeometry(dpy, win, &root, &x, &y, &width, &height,
				  &bw, &depth);
	    if (TrapEnd(dpy, handler, &trap) || !ok) {
		return TCL_OK;
	    }
	}
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(x));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(y));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj((int)width));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj((int)height));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj((int)bw));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj((int)depth));
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case W_SAVESET: {
	/* The save-set is what makes a WM crash-only: clients reparented
	 * into our frames are handed back to the root if we die. */
	static const char *const modes[] = { "add", "remove", NULL };
	int mode;
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv,
			     "?-displayof window? add|remove window");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(interp, av[0], modes, "mode", 0,
				&mode) != TCL_OK
		|| WindowFromObj(interp, tkMain, av[1], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	XChangeSaveSet(dpy, win, mode == 0 ? SetModeInsert : SetModeDelete);
	return TCL_OK;
    }

    case W_TREE: {
	/* {root parent {children...}} — adoption walks this at startup,
	 * and it is also how a script finds the window a Tk toplevel
	 * really shows to a WM: Tk keeps the WM properties on a WRAPPER,
	 * which is the PARENT of `winfo id`, not that id itself. {} when
	 * the window is gone. */
	Window root, parent, *kids = NULL;
	unsigned int nkids = 0, i;
	Trap trap;
	Tk_ErrorHandler handler;
	Tcl_Obj *res, *lst;
	int ok;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	handler = TrapBegin(dpy, &trap);
	ok = XQueryTree(dpy, win, &root, &parent, &kids, &nkids);
	if (TrapEnd(dpy, handler, &trap) || !ok) {
	    if (kids != NULL) {
		XFree(kids);
	    }
	    return TCL_OK;
	}
	lst = Tcl_NewListObj(0, NULL);
	for (i = 0; i < nkids; i++) {
	    Tcl_ListObjAppendElement(interp, lst,
		Tcl_NewWideIntObj((Tcl_WideInt)kids[i]));
	}
	if (kids != NULL) {
	    XFree(kids);
	}
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res, Tcl_NewWideIntObj((Tcl_WideInt)root));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewWideIntObj((Tcl_WideInt)parent));
	Tcl_ListObjAppendElement(interp, res, lst);
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case W_CONFIGURE: {
	/* window dict — the answer to a ConfigureRequest, and the one
	 * call that has to speak in the request's own terms: only the
	 * keys present are applied, exactly as the client's value_mask
	 * asked. Keys: x y width height border-width sibling stack-mode
	 * (above|below|top-if|bottom-if|opposite). */
	static const char *const keys[] = {
	    "x", "y", "width", "height", "border-width", "sibling",
	    "stack-mode", NULL
	};
	static const char *const stacks[] = {
	    "above", "below", "top-if", "bottom-if", "opposite", NULL
	};
	static const int stackCodes[] = { Above, Below, TopIf, BottomIf, Opposite };
	XWindowChanges ch;
	unsigned int mask = 0;
	Tcl_Obj *dict, *val;
	int k, v;
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window dict");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	memset(&ch, 0, sizeof(ch));
	dict = av[1];
	for (k = 0; keys[k] != NULL; k++) {
	    if (Tcl_DictObjGet(interp, dict, Tcl_NewStringObj(keys[k], -1),
			       &val) != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (val == NULL) {
		continue;
	    }
	    switch (k) {
	    case 0: if (Tcl_GetIntFromObj(interp, val, &v) != TCL_OK) return TCL_ERROR;
		    ch.x = v; mask |= CWX; break;
	    case 1: if (Tcl_GetIntFromObj(interp, val, &v) != TCL_OK) return TCL_ERROR;
		    ch.y = v; mask |= CWY; break;
	    case 2: if (Tcl_GetIntFromObj(interp, val, &v) != TCL_OK) return TCL_ERROR;
		    ch.width = v; mask |= CWWidth; break;
	    case 3: if (Tcl_GetIntFromObj(interp, val, &v) != TCL_OK) return TCL_ERROR;
		    ch.height = v; mask |= CWHeight; break;
	    case 4: if (Tcl_GetIntFromObj(interp, val, &v) != TCL_OK) return TCL_ERROR;
		    ch.border_width = v; mask |= CWBorderWidth; break;
	    case 5: {
		    Window sib;
		    if (WindowFromObj(interp, tkMain, val, &sib) != TCL_OK) {
			return TCL_ERROR;
		    }
		    ch.sibling = sib; mask |= CWSibling; break;
		}
	    case 6: if (Tcl_GetIndexFromObj(interp, val, stacks, "stackMode", 0,
					    &v) != TCL_OK) return TCL_ERROR;
		    ch.stack_mode = stackCodes[v]; mask |= CWStackMode; break;
	    }
	}
	if (mask != 0) {
	    XConfigureWindow(dpy, win, mask, &ch);
	}
	return TCL_OK;
    }

    case W_RESTACK: {
	/* A whole stacking order in one request — top of the list ends up
	 * on top. Doing it window by window makes the desk flicker. */
	Tcl_Size count, i;
	Tcl_Obj **elems;
	Window *wins;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? windowList");
	    return TCL_ERROR;
	}
	if (Tcl_ListObjGetElements(interp, av[0], &count, &elems) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (count == 0) {
	    return TCL_OK;
	}
	wins = (Window *)ckalloc(sizeof(Window) * count);
	for (i = 0; i < count; i++) {
	    if (WindowFromObj(interp, tkMain, elems[i], &wins[i]) != TCL_OK) {
		ckfree(wins);
		return TCL_ERROR;
	    }
	}
	XRestackWindows(dpy, wins, (int)count);
	ckfree(wins);
	return TCL_OK;
    }

    case W_CREATE: {
	/* parent x y width height ?-override? — the WM's own bare
	 * windows: the EWMH check window, the focus holder. Nothing to
	 * draw in them, so a bare InputOutput child is the whole story;
	 * -override keeps it out of any manager's way, including ours. */
	Window parent, made;
	int x, y, width, height, i, override = 0;
	if (n < 5 || n > 6) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? parent x y width height ?-override?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &parent) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[1], &x) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[2], &y) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[3], &width) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[4], &height) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 6) {
	    if (strcmp(Tcl_GetString(av[5]), "-override") != 0) {
		Tcl_SetObjResult(interp,
		    Tcl_NewStringObj("expected -override", -1));
		return TCL_ERROR;
	    }
	    override = 1;
	}
	if (width <= 0) { width = 1; }
	if (height <= 0) { height = 1; }
	i = DefaultScreen(dpy);
	made = XCreateSimpleWindow(dpy, parent, x, y, (unsigned)width,
				   (unsigned)height, 0, BlackPixel(dpy, i),
				   BlackPixel(dpy, i));
	if (override) {
	    XSetWindowAttributes attr;
	    attr.override_redirect = True;
	    XChangeWindowAttributes(dpy, made, CWOverrideRedirect, &attr);
	}
	XSync(dpy, False);	/* it exists before anyone is told its id */
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)made));
	return TCL_OK;
    }

    case W_ATTRS: {
	/* window ?dict? — with a dict, the attributes a WM sets on windows
	 * it did not create (override-redirect, event-mask by name, cursor
	 * as a font-cursor number, 0 = none); without one, the attributes it
	 * READS off such a window. */
	static const char *const keys[] = {
	    "override-redirect", "event-mask", "cursor", "background", NULL
	};
	XSetWindowAttributes attr;
	unsigned long mask = 0;
	Tcl_Obj *val;
	int k, v;
	long emask;
	int bgpixmap = 0;	/* the background wants a PIXMAP, not a pixel */
	if (n < 1 || n > 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window ?dict?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 1) {
	    /* The read side, and adoption is what it exists for: a WM
	     * starting on a live screen walks the root's children and has
	     * to tell a window it must manage from one it must not touch —
	     * viewable or not, override-redirect or not. Geometry is in
	     * here too, so the walk is one round trip per window instead of
	     * two. {} when the window is gone: ordinary life for a WM. */
	    XWindowAttributes wa;
	    Tcl_Obj *d;
	    Trap trap;
	    Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	    int ok = XGetWindowAttributes(dpy, win, &wa);
	    if (TrapEnd(dpy, handler, &trap) || !ok) {
		return TCL_OK;
	    }
	    d = Tcl_NewDictObj();
#define PUT_(k, v) Tcl_DictObjPut(NULL, d, Tcl_NewStringObj((k), -1), (v))
	    PUT_("x", Tcl_NewIntObj(wa.x));
	    PUT_("y", Tcl_NewIntObj(wa.y));
	    PUT_("width", Tcl_NewIntObj(wa.width));
	    PUT_("height", Tcl_NewIntObj(wa.height));
	    PUT_("border-width", Tcl_NewIntObj(wa.border_width));
	    PUT_("depth", Tcl_NewIntObj(wa.depth));
	    PUT_("class", Tcl_NewStringObj(
		wa.class == InputOnly ? "input-only" : "input-output", -1));
	    PUT_("map-state", Tcl_NewStringObj(
		wa.map_state == IsUnmapped ? "unmapped" :
		wa.map_state == IsUnviewable ? "unviewable" : "viewable", -1));
	    PUT_("override-redirect", Tcl_NewIntObj(wa.override_redirect != 0));
	    PUT_("save-under", Tcl_NewIntObj(wa.save_under != 0));
	    PUT_("root", Tcl_NewWideIntObj((Tcl_WideInt)wa.root));
	    PUT_("your-event-mask", MaskNamesObj(wa.your_event_mask));
	    PUT_("all-event-masks", MaskNamesObj(wa.all_event_masks));
#undef PUT_
	    Tcl_SetObjResult(interp, d);
	    return TCL_OK;
	}
	memset(&attr, 0, sizeof(attr));
	for (k = 0; keys[k] != NULL; k++) {
	    if (Tcl_DictObjGet(interp, av[1], Tcl_NewStringObj(keys[k], -1),
			       &val) != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (val == NULL) {
		continue;
	    }
	    switch (k) {
	    case 0:
		if (Tcl_GetBooleanFromObj(interp, val, &v) != TCL_OK) {
		    return TCL_ERROR;
		}
		attr.override_redirect = v ? True : False;
		mask |= CWOverrideRedirect;
		break;
	    case 1:
		if (MaskFromObj(interp, val, &emask) != TCL_OK) {
		    return TCL_ERROR;
		}
		attr.event_mask = emask;
		mask |= CWEventMask;
		break;
	    case 2:
		/* A Tk cursor NAME ("left_ptr"), or empty for None —
		 * which is how a WM stops the root window from wearing
		 * the server's default X_cursor without shelling out to
		 * xsetroot. */
		if (CursorFromObj(interp, tkMain, val, &attr.cursor)
			!= TCL_OK) {
		    return TCL_ERROR;
		}
		mask |= CWCursor;
		break;
	    case 3: {
		/* The background of a window we did not create, and the
		 * two things a tray needs of it.
		 *
		 * "parent-relative" is the classic cure for an icon
		 * drawn with transparency: its see-through parts then
		 * show the CELL's background instead of black. The
		 * server refuses it across depths (BadMatch), which is
		 * exactly why the ARGB question is a question at all.
		 *
		 * A NUMBER is a raw pixel, and raw is the point: in a
		 * 32-bit visual the alpha lives in the bits no
		 * TrueColor mask covers, so a toolkit that computes
		 * colors from the masks — Tk does — can only ever ask
		 * for alpha ZERO, i.e. a window a compositor draws as
		 * not there at all. Handing the pixel in whole
		 * (0xff000000 | rgb) is how a script paints an opaque
		 * ARGB window without teaching Tk about alpha.
		 *
		 * Neither takes effect on what is already on screen —
		 * `window clear` is the repaint. */
		const char *s = Tcl_GetString(val);
		if (strcmp(s, "parent-relative") == 0) {
		    attr.background_pixmap = ParentRelative;
		    bgpixmap = 1;
		} else if (strcmp(s, "none") == 0) {
		    attr.background_pixmap = None;
		    bgpixmap = 1;
		} else {
		    Tcl_WideInt px;
		    if (Tcl_GetWideIntFromObj(interp, val, &px) != TCL_OK) {
			Tcl_SetObjResult(interp, Tcl_NewStringObj(
			    "background: a pixel value, parent-relative or none",
			    -1));
			Tcl_SetErrorCode(interp, "TKWMX", "BACKGROUND",
					 (char *)NULL);
			return TCL_ERROR;
		    }
		    attr.background_pixel = (unsigned long)px;
		}
		mask |= bgpixmap ? CWBackPixmap : CWBackPixel;
		break;
	    }
	    }
	}
	if (mask != 0) {
	    /* Under a trap: ParentRelative across depths is a BadMatch,
	     * and a WM that dies of one deserves what it gets. */
	    Trap trap;
	    Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	    XChangeWindowAttributes(dpy, win, mask, &attr);
	    if (TrapEnd(dpy, handler, &trap)) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "the server refused the attributes (a background"
		    " across depths?)", -1));
		Tcl_SetErrorCode(interp, "TKWMX", "ATTRS", (char *)NULL);
		return TCL_ERROR;
	    }
	}
	return TCL_OK;
    }

    case W_CLEAR: {
	/* Repaint a window from its background — the other half of
	 * setting one. With -exposures the client is told to redraw
	 * too, which is what a foreign window needs: its own drawing
	 * is not ours to reproduce. */
	int expose = 0;
	if (n < 1 || n > 2) {
	    Tcl_WrongNumArgs(interp, 2, objv,
			     "?-displayof window? window ?-exposures?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 2) {
	    if (strcmp(Tcl_GetString(av[1]), "-exposures") != 0) {
		Tcl_SetObjResult(interp,
		    Tcl_NewStringObj("expected -exposures", -1));
		return TCL_ERROR;
	    }
	    expose = 1;
	}
	XClearArea(dpy, win, 0, 0, 0, 0, expose ? True : False);
	return TCL_OK;
    }

    case W_KILL: {
	/* The impolite close: kill the CLIENT owning the window. The
	 * polite one is a WM_DELETE_WINDOW ClientMessage — event client. */
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	XKillClient(dpy, win);
	return TCL_OK;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::prop                                                       */

/*
 * Valid UTF-8? WM_NAME's STRING type is latin1 by the letter of ICCCM,
 * but a client started in the C locale writes raw UTF-8 into it (xterm
 * does exactly that), so the bytes are offered to UTF-8 first and only
 * genuinely invalid ones fall back to latin1. Pure ASCII passes either
 * way.
 */
static int
IsUtf8(const unsigned char *p, int len)
{
    int i = 0;
    while (i < len) {
	unsigned char c = p[i];
	int extra;
	if (c < 0x80) { i++; continue; }
	else if ((c & 0xE0) == 0xC0) { extra = 1; if (c < 0xC2) return 0; }
	else if ((c & 0xF0) == 0xE0) { extra = 2; }
	else if ((c & 0xF8) == 0xF0) { extra = 3; if (c > 0xF4) return 0; }
	else return 0;
	if (i + extra >= len) return 0;
	while (extra-- > 0) {
	    if ((p[++i] & 0xC0) != 0x80) return 0;
	}
	i++;
    }
    return 1;
}

/* The raw property, with the trap on. Returns 0 when there is nothing
 * to report (absent, or the window went away); otherwise the caller
 * owns *dataPtr and must XFree it. */
static int
GetProperty(Display *dpy, Window win, Atom prop, Atom reqType, long words,
	    Atom *typePtr, int *formatPtr, unsigned long *nitemsPtr,
	    unsigned char **dataPtr)
{
    Trap trap;
    Tk_ErrorHandler handler;
    unsigned long after;
    int status;

    handler = TrapBegin(dpy, &trap);
    status = XGetWindowProperty(dpy, win, prop, 0, words, False, reqType,
				typePtr, formatPtr, nitemsPtr, &after, dataPtr);
    if (TrapEnd(dpy, handler, &trap) || status != Success) {
	return 0;
    }
    if (*typePtr == None || *dataPtr == NULL) {
	if (*dataPtr != NULL) {
	    XFree(*dataPtr);
	    *dataPtr = NULL;
	}
	return 0;
    }
    return 1;
}

/* format 8 -> a byte array; 16/32 -> a list of integers (32-bit
 * property data arrives as C longs, which is why this is not a memcpy) */
static Tcl_Obj *
PropValueObj(int format, unsigned long nitems, unsigned char *data)
{
    Tcl_Obj *res;
    unsigned long i;

    if (format == 8) {
	return Tcl_NewByteArrayObj(data, (Tcl_Size)nitems);
    }
    res = Tcl_NewListObj(0, NULL);
    for (i = 0; i < nitems; i++) {
	Tcl_WideInt v;
	if (format == 16) {
	    v = (Tcl_WideInt)((unsigned short *)data)[i];
	} else {
	    v = (Tcl_WideInt)((unsigned long *)data)[i];
	}
	Tcl_ListObjAppendElement(NULL, res, Tcl_NewWideIntObj(v));
    }
    return res;
}

/* The decode ladder for a text property — the one piece of Xlib
 * knowledge a script cannot cheaply have. UTF8_STRING is plain UTF-8;
 * STRING is latin1 by ICCCM but carries UTF-8 in practice (see IsUtf8);
 * anything else is COMPOUND_TEXT — ISO 2022 with charset designations,
 * a standard in its own right — and Xlib already carries the whole
 * conversion table, locale setup or no locale setup. */
static Tcl_Obj *
TextPropertyObj(Tcl_Interp *interp, Display *dpy, Atom type, int format,
		unsigned long nitems, unsigned char *data)
{
    Tcl_Obj *res;
    Tcl_DString ds;
    XTextProperty tp;
    char **list = NULL;
    int count = 0, i;

    if (format != 8 || nitems == 0) {
	return Tcl_NewStringObj("", -1);
    }
    if (type == Tk_InternAtom(Tk_MainWindow(interp), "UTF8_STRING")) {
	Tcl_ExternalToUtfDString(Tcl_GetEncoding(interp, "utf-8"),
				 (char *)data, (Tcl_Size)nitems, &ds);
	res = Tcl_NewStringObj(Tcl_DStringValue(&ds), Tcl_DStringLength(&ds));
	Tcl_DStringFree(&ds);
	return res;
    }
    if (type == XA_STRING) {
	Tcl_ExternalToUtfDString(
	    Tcl_GetEncoding(interp, IsUtf8(data, (int)nitems)
			    ? "utf-8" : "iso8859-1"),
	    (char *)data, (Tcl_Size)nitems, &ds);
	res = Tcl_NewStringObj(Tcl_DStringValue(&ds), Tcl_DStringLength(&ds));
	Tcl_DStringFree(&ds);
	return res;
    }
    tp.value = data;
    tp.encoding = type;
    tp.format = format;
    tp.nitems = nitems;
    if (Xutf8TextPropertyToTextList(dpy, &tp, &list, &count) < 0 || count == 0) {
	if (list != NULL) {
	    XFreeStringList(list);
	}
	return Tcl_NewStringObj("", -1);
    }
    res = Tcl_NewStringObj("", 0);
    for (i = 0; i < count; i++) {
	Tcl_Obj *part;
	Tcl_ExternalToUtfDString(Tcl_GetEncoding(interp, "utf-8"),
				 list[i], -1, &ds);
	part = Tcl_NewStringObj(Tcl_DStringValue(&ds), Tcl_DStringLength(&ds));
	Tcl_DStringFree(&ds);
	if (i > 0) {
	    Tcl_AppendToObj(res, " ", 1);
	}
	Tcl_AppendObjToObj(res, part);
    }
    XFreeStringList(list);
    return res;
}

static int
PropObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	   Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"get", "set", "delete", "text", "class", "hints", "normal-hints",
	"protocols", "transient", NULL
    };
    enum { P_GET, P_SET, P_DELETE, P_TEXT, P_CLASS, P_HINTS, P_NORMAL,
	   P_PROTOCOLS, P_TRANSIENT };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    Atom prop, type;
    int index, n, format;
    unsigned long nitems;
    unsigned char *data;
    Tcl_Obj *const *av;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    if (n < 1) {
	Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window ...");
	return TCL_ERROR;
    }
    if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	return TCL_ERROR;
    }

    switch (index) {
    case P_GET: {
	/* {type FORMAT value} — or {} when the property is absent or the
	 * window is gone. Length: whatever it takes; _NET_WM_ICON is the
	 * big one, and a WM would rather read it whole. */
	Tcl_Obj *res;
	long words = 1L << 20;
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window atom");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (!GetProperty(dpy, win, (Atom)w, AnyPropertyType, words,
			 &type, &format, &nitems, &data)) {
	    return TCL_OK;
	}
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res, Tcl_NewWideIntObj((Tcl_WideInt)type));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(format));
	Tcl_ListObjAppendElement(interp, res, PropValueObj(format, nitems, data));
	XFree(data);
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case P_SET: {
	/* window atom type format value ?append? — value is a byte array
	 * for format 8, a list of integers otherwise. */
	Atom vtype;
	int vformat, mode = PropModeReplace, append = 0;
	if (n < 5 || n > 6) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? window atom type format value ?append?");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	prop = (Atom)w;
	if (Tcl_GetWideIntFromObj(interp, av[2], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	vtype = (Atom)w;
	if (Tcl_GetIntFromObj(interp, av[3], &vformat) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 6 && Tcl_GetBooleanFromObj(interp, av[5], &append) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (append) {
	    mode = PropModeAppend;
	}
	if (vformat == 8) {
	    Tcl_Size len;
	    unsigned char *bytes = Tcl_GetByteArrayFromObj(av[4], &len);
	    XChangeProperty(dpy, win, prop, vtype, 8, mode, bytes, (int)len);
	} else if (vformat == 16 || vformat == 32) {
	    Tcl_Size count, i;
	    Tcl_Obj **elems;
	    if (Tcl_ListObjGetElements(interp, av[4], &count, &elems) != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (vformat == 32) {
		long *vals = (long *)ckalloc(sizeof(long) * (count ? count : 1));
		for (i = 0; i < count; i++) {
		    if (Tcl_GetWideIntFromObj(interp, elems[i], &w) != TCL_OK) {
			ckfree(vals);
			return TCL_ERROR;
		    }
		    vals[i] = (long)w;
		}
		XChangeProperty(dpy, win, prop, vtype, 32, mode,
				(unsigned char *)vals, (int)count);
		ckfree(vals);
	    } else {
		unsigned short *vals = (unsigned short *)
		    ckalloc(sizeof(short) * (count ? count : 1));
		for (i = 0; i < count; i++) {
		    if (Tcl_GetWideIntFromObj(interp, elems[i], &w) != TCL_OK) {
			ckfree(vals);
			return TCL_ERROR;
		    }
		    vals[i] = (unsigned short)w;
		}
		XChangeProperty(dpy, win, prop, vtype, 16, mode,
				(unsigned char *)vals, (int)count);
		ckfree(vals);
	    }
	} else {
	    Tcl_SetObjResult(interp,
		Tcl_NewStringObj("format must be 8, 16 or 32", -1));
	    Tcl_SetErrorCode(interp, "TKWMX", "VALUE", (char *)NULL);
	    return TCL_ERROR;
	}
	return TCL_OK;
    }

    case P_DELETE:
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window atom");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	XDeleteProperty(dpy, win, (Atom)w);
	return TCL_OK;

    case P_TEXT: {
	/* A text property, decoded whatever its encoding — see
	 * TextPropertyObj. "" when absent. */
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window atom");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (!GetProperty(dpy, win, (Atom)w, AnyPropertyType, 1L << 16,
			 &type, &format, &nitems, &data)) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj("", -1));
	    return TCL_OK;
	}
	Tcl_SetObjResult(interp,
	    TextPropertyObj(interp, dpy, type, format, nitems, data));
	XFree(data);
	return TCL_OK;
    }

    case P_CLASS: {
	/* WM_CLASS as {instance class}; {} when unset. */
	Tcl_Obj *res;
	char *inst;
	if (!GetProperty(dpy, win, XA_WM_CLASS, AnyPropertyType, 1024,
			 &type, &format, &nitems, &data) || format != 8) {
	    if (nitems > 0 && data != NULL) {
		XFree(data);
	    }
	    return TCL_OK;
	}
	inst = (char *)data;
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res, Tcl_NewStringObj(inst, -1));
	{
	    unsigned long off = strlen(inst) + 1;
	    Tcl_ListObjAppendElement(interp, res, Tcl_NewStringObj(
		off < nitems ? (char *)(data + off) : "", -1));
	}
	XFree(data);
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case P_HINTS: {
	/* WM_HINTS, the fields a WM actually acts on. {} when unset. */
	Trap trap;
	Tk_ErrorHandler handler;
	XWMHints *h;
	Tcl_Obj *res;
	handler = TrapBegin(dpy, &trap);
	h = XGetWMHints(dpy, win);
	if (TrapEnd(dpy, handler, &trap) || h == NULL) {
	    if (h != NULL) {
		XFree(h);
	    }
	    return TCL_OK;
	}
	res = Tcl_NewDictObj();
	Tcl_DictObjPut(interp, res, Tcl_NewStringObj("flags", -1),
		       Tcl_NewWideIntObj((Tcl_WideInt)h->flags));
	if (h->flags & InputHint) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("input", -1),
			   Tcl_NewIntObj(h->input != 0));
	}
	if (h->flags & StateHint) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("initial-state", -1),
			   Tcl_NewIntObj(h->initial_state));
	}
	if (h->flags & WindowGroupHint) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("group", -1),
			   Tcl_NewWideIntObj((Tcl_WideInt)h->window_group));
	}
	XFree(h);
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case P_NORMAL: {
	/* WM_NORMAL_HINTS: the size contract — minimum, maximum,
	 * increments, base, gravity. {} when unset. */
	XSizeHints hints;
	long supplied = 0;
	Trap trap;
	Tk_ErrorHandler handler;
	Tcl_Obj *res;
	int ok;
	handler = TrapBegin(dpy, &trap);
	ok = XGetWMNormalHints(dpy, win, &hints, &supplied);
	if (TrapEnd(dpy, handler, &trap) || !ok) {
	    return TCL_OK;
	}
	res = Tcl_NewDictObj();
	Tcl_DictObjPut(interp, res, Tcl_NewStringObj("flags", -1),
		       Tcl_NewWideIntObj((Tcl_WideInt)hints.flags));
	if (hints.flags & PMinSize) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("min", -1),
		Tcl_NewListObj(2, (Tcl_Obj *[]){
		    Tcl_NewIntObj(hints.min_width),
		    Tcl_NewIntObj(hints.min_height)}));
	}
	if (hints.flags & PMaxSize) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("max", -1),
		Tcl_NewListObj(2, (Tcl_Obj *[]){
		    Tcl_NewIntObj(hints.max_width),
		    Tcl_NewIntObj(hints.max_height)}));
	}
	if (hints.flags & PResizeInc) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("inc", -1),
		Tcl_NewListObj(2, (Tcl_Obj *[]){
		    Tcl_NewIntObj(hints.width_inc),
		    Tcl_NewIntObj(hints.height_inc)}));
	}
	if (hints.flags & PBaseSize) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("base", -1),
		Tcl_NewListObj(2, (Tcl_Obj *[]){
		    Tcl_NewIntObj(hints.base_width),
		    Tcl_NewIntObj(hints.base_height)}));
	}
	if (hints.flags & PWinGravity) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("gravity", -1),
			   Tcl_NewIntObj(hints.win_gravity));
	}
	if (hints.flags & (USPosition | PPosition)) {
	    Tcl_DictObjPut(interp, res, Tcl_NewStringObj("position", -1),
		Tcl_NewStringObj((hints.flags & USPosition) ? "user" : "program", -1));
	}
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case P_PROTOCOLS: {
	/* WM_PROTOCOLS as a list of atoms; {} when the client advertises
	 * none — the difference between "does not answer WM_DELETE_WINDOW"
	 * and "was never asked". */
	Atom *protos = NULL;
	int count = 0, i;
	Trap trap;
	Tk_ErrorHandler handler;
	Tcl_Obj *res;
	handler = TrapBegin(dpy, &trap);
	i = XGetWMProtocols(dpy, win, &protos, &count);
	if (TrapEnd(dpy, handler, &trap) || !i) {
	    if (protos != NULL) {
		XFree(protos);
	    }
	    return TCL_OK;
	}
	res = Tcl_NewListObj(0, NULL);
	for (i = 0; i < count; i++) {
	    Tcl_ListObjAppendElement(interp, res,
		Tcl_NewWideIntObj((Tcl_WideInt)protos[i]));
	}
	XFree(protos);
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case P_TRANSIENT: {
	/* WM_TRANSIENT_FOR: the leader this dialog belongs to, 0 for none. */
	Window leader = None;
	Trap trap;
	Tk_ErrorHandler handler;
	int ok, failed;
	handler = TrapBegin(dpy, &trap);
	ok = XGetTransientForHint(dpy, win, &leader);
	failed = TrapEnd(dpy, handler, &trap);
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
	    (ok && !failed) ? (Tcl_WideInt)leader : 0));
	return TCL_OK;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::event                                                      */

/*
 * Event masks by NAME. A window manager's selections are the one place
 * where a magic number is guaranteed to be wrong eventually, and the
 * script has no business spelling `1 << 20`.
 */
static const struct { const char *name; long mask; } EventMasks[] = {
    {"key-press",            KeyPressMask},
    {"key-release",          KeyReleaseMask},
    {"button-press",         ButtonPressMask},
    {"button-release",       ButtonReleaseMask},
    {"enter-window",         EnterWindowMask},
    {"leave-window",         LeaveWindowMask},
    {"pointer-motion",       PointerMotionMask},
    {"button-motion",        ButtonMotionMask},
    {"exposure",             ExposureMask},
    {"visibility-change",    VisibilityChangeMask},
    {"structure-notify",     StructureNotifyMask},
    {"resize-redirect",      ResizeRedirectMask},
    {"substructure-notify",  SubstructureNotifyMask},
    {"substructure-redirect",SubstructureRedirectMask},
    {"focus-change",         FocusChangeMask},
    {"property-change",      PropertyChangeMask},
    {"colormap-change",      ColormapChangeMask},
    {"owner-grab-button",    OwnerGrabButtonMask},
    {NULL, 0}
};

static int
MaskFromObj(Tcl_Interp *interp, Tcl_Obj *obj, long *maskPtr)
{
    Tcl_Size count, i;
    Tcl_Obj **elems;
    long mask = 0;

    if (Tcl_ListObjGetElements(interp, obj, &count, &elems) != TCL_OK) {
	return TCL_ERROR;
    }
    for (i = 0; i < count; i++) {
	const char *name = Tcl_GetString(elems[i]);
	int j, found = 0;
	for (j = 0; EventMasks[j].name != NULL; j++) {
	    if (strcmp(name, EventMasks[j].name) == 0) {
		mask |= EventMasks[j].mask;
		found = 1;
		break;
	    }
	}
	if (!found) {
	    Tcl_Obj *msg = Tcl_ObjPrintf("unknown event mask \"%s\": should be one of",
					 name);
	    for (j = 0; EventMasks[j].name != NULL; j++) {
		Tcl_AppendPrintfToObj(msg, "%s %s",
				      j == 0 ? "" : ",", EventMasks[j].name);
	    }
	    Tcl_SetObjResult(interp, msg);
	    Tcl_SetErrorCode(interp, "TKWMX", "MASK", (char *)NULL);
	    return TCL_ERROR;
	}
    }
    *maskPtr = mask;
    return TCL_OK;
}

/* The way back: a mask read off the server, spelled in the same
 * vocabulary the script selects with. */
static Tcl_Obj *
MaskNamesObj(long mask)
{
    Tcl_Obj *res = Tcl_NewListObj(0, NULL);
    int j;

    for (j = 0; EventMasks[j].name != NULL; j++) {
	if (mask & EventMasks[j].mask) {
	    Tcl_ListObjAppendElement(NULL, res,
		Tcl_NewStringObj(EventMasks[j].name, -1));
	}
    }
    return res;
}

/* The names a script sees for event types — same spelling as the mask
 * names, so a dispatcher reads as one vocabulary. */
static const char *
EventTypeName(int type)
{
    switch (type) {
    case KeyPress:		return "key-press";
    case KeyRelease:		return "key-release";
    case ButtonPress:		return "button-press";
    case ButtonRelease:		return "button-release";
    case MotionNotify:		return "motion-notify";
    case EnterNotify:		return "enter-notify";
    case LeaveNotify:		return "leave-notify";
    case FocusIn:		return "focus-in";
    case FocusOut:		return "focus-out";
    case KeymapNotify:		return "keymap-notify";
    case Expose:		return "expose";
    case VisibilityNotify:	return "visibility-notify";
    case CreateNotify:		return "create-notify";
    case DestroyNotify:		return "destroy-notify";
    case UnmapNotify:		return "unmap-notify";
    case MapNotify:		return "map-notify";
    case MapRequest:		return "map-request";
    case ReparentNotify:	return "reparent-notify";
    case ConfigureNotify:	return "configure-notify";
    case ConfigureRequest:	return "configure-request";
    case GravityNotify:		return "gravity-notify";
    case ResizeRequest:		return "resize-request";
    case CirculateNotify:	return "circulate-notify";
    case CirculateRequest:	return "circulate-request";
    case PropertyNotify:	return "property-notify";
    case SelectionClear:	return "selection-clear";
    case SelectionRequest:	return "selection-request";
    case SelectionNotify:	return "selection-notify";
    case ColormapNotify:	return "colormap-notify";
    case ClientMessage:		return "client-message";
    case MappingNotify:		return "mapping-notify";
    /*
     * Tk's own event types. MouseWheelEvent is not a type the server
     * ever sends: Tk REWRITES a press of buttons 4-7 into it, in
     * Tk_HandleEvent and BEFORE the generic handlers run, and drops the
     * matching release outright (tkEvent.c). A script riding this
     * connection therefore never sees a wheel press as a button press,
     * and a window manager that grabs AnyButton has to know it — an
     * unanswered sync grab freezes the pointer for the whole display,
     * with the keyboard still working to disguise it. Naming the event
     * is what keeps that from being invisible.
     */
    case MouseWheelEvent:	return "mouse-wheel";
    case VirtualEvent:		return "virtual-event";
    case ActivateNotify:	return "activate-notify";
    case DeactivateNotify:	return "deactivate-notify";
    default:			return "unknown";
    }
}

#define PUT(k, v) Tcl_DictObjPut(NULL, d, Tcl_NewStringObj((k), -1), (v))
#define PUTW(k, v) PUT((k), Tcl_NewWideIntObj((Tcl_WideInt)(v)))
#define PUTI(k, v) PUT((k), Tcl_NewIntObj((int)(v)))

/*
 * An event as a dict, with EVERY field of the types a window manager
 * acts on — no filtering, no "simplifying". The whole point is that
 * new logic in the script never needs a change down here.
 */
static Tcl_Obj *
EventDict(XEvent *ev)
{
    Tcl_Obj *d = Tcl_NewDictObj();

    PUT("type", Tcl_NewStringObj(EventTypeName(ev->type), -1));
    PUTW("serial", ev->xany.serial);
    PUTI("send-event", ev->xany.send_event != 0);
    PUTW("event-window", ev->xany.window);

    switch (ev->type) {
    case MapRequest:
	PUTW("parent", ev->xmaprequest.parent);
	PUTW("window", ev->xmaprequest.window);
	break;
    case ConfigureRequest:
	PUTW("parent", ev->xconfigurerequest.parent);
	PUTW("window", ev->xconfigurerequest.window);
	PUTI("x", ev->xconfigurerequest.x);
	PUTI("y", ev->xconfigurerequest.y);
	PUTI("width", ev->xconfigurerequest.width);
	PUTI("height", ev->xconfigurerequest.height);
	PUTI("border-width", ev->xconfigurerequest.border_width);
	PUTW("above", ev->xconfigurerequest.above);
	PUTI("detail", ev->xconfigurerequest.detail);
	PUTW("value-mask", ev->xconfigurerequest.value_mask);
	break;
    case ResizeRequest:
	PUTW("window", ev->xresizerequest.window);
	PUTI("width", ev->xresizerequest.width);
	PUTI("height", ev->xresizerequest.height);
	break;
    case CirculateRequest:
	PUTW("parent", ev->xcirculaterequest.parent);
	PUTW("window", ev->xcirculaterequest.window);
	PUTI("place", ev->xcirculaterequest.place);
	break;
    case CreateNotify:
	PUTW("parent", ev->xcreatewindow.parent);
	PUTW("window", ev->xcreatewindow.window);
	PUTI("x", ev->xcreatewindow.x);
	PUTI("y", ev->xcreatewindow.y);
	PUTI("width", ev->xcreatewindow.width);
	PUTI("height", ev->xcreatewindow.height);
	PUTI("border-width", ev->xcreatewindow.border_width);
	PUTI("override-redirect", ev->xcreatewindow.override_redirect != 0);
	break;
    case DestroyNotify:
	PUTW("window", ev->xdestroywindow.window);
	break;
    case UnmapNotify:
	PUTW("window", ev->xunmap.window);
	PUTI("from-configure", ev->xunmap.from_configure != 0);
	break;
    case MapNotify:
	PUTW("window", ev->xmap.window);
	PUTI("override-redirect", ev->xmap.override_redirect != 0);
	break;
    case ReparentNotify:
	PUTW("window", ev->xreparent.window);
	PUTW("parent", ev->xreparent.parent);
	PUTI("x", ev->xreparent.x);
	PUTI("y", ev->xreparent.y);
	PUTI("override-redirect", ev->xreparent.override_redirect != 0);
	break;
    case ConfigureNotify:
	PUTW("window", ev->xconfigure.window);
	PUTI("x", ev->xconfigure.x);
	PUTI("y", ev->xconfigure.y);
	PUTI("width", ev->xconfigure.width);
	PUTI("height", ev->xconfigure.height);
	PUTI("border-width", ev->xconfigure.border_width);
	PUTW("above", ev->xconfigure.above);
	PUTI("override-redirect", ev->xconfigure.override_redirect != 0);
	break;
    case GravityNotify:
	PUTW("window", ev->xgravity.window);
	PUTI("x", ev->xgravity.x);
	PUTI("y", ev->xgravity.y);
	break;
    case PropertyNotify:
	PUTW("window", ev->xproperty.window);
	PUTW("atom", ev->xproperty.atom);
	PUTW("time", ev->xproperty.time);
	PUT("state", Tcl_NewStringObj(
	    ev->xproperty.state == PropertyDelete ? "delete" : "new", -1));
	break;
    case ClientMessage: {
	Tcl_Obj *data = Tcl_NewListObj(0, NULL);
	int i;
	PUTW("window", ev->xclient.window);
	PUTW("message-type", ev->xclient.message_type);
	PUTI("format", ev->xclient.format);
	if (ev->xclient.format == 32) {
	    for (i = 0; i < 5; i++) {
		Tcl_ListObjAppendElement(NULL, data,
		    Tcl_NewWideIntObj((Tcl_WideInt)ev->xclient.data.l[i]));
	    }
	} else if (ev->xclient.format == 16) {
	    for (i = 0; i < 10; i++) {
		Tcl_ListObjAppendElement(NULL, data,
		    Tcl_NewIntObj(ev->xclient.data.s[i]));
	    }
	} else {
	    data = Tcl_NewByteArrayObj((unsigned char *)ev->xclient.data.b, 20);
	}
	PUT("data", data);
	break;
    }
    case FocusIn:
    case FocusOut:
	PUTW("window", ev->xfocus.window);
	PUTI("mode", ev->xfocus.mode);
	PUTI("detail", ev->xfocus.detail);
	break;
    case KeyPress:
    case KeyRelease:
	PUTW("window", ev->xkey.window);
	PUTW("root", ev->xkey.root);
	PUTW("subwindow", ev->xkey.subwindow);
	PUTW("time", ev->xkey.time);
	PUTI("x", ev->xkey.x);
	PUTI("y", ev->xkey.y);
	PUTI("x-root", ev->xkey.x_root);
	PUTI("y-root", ev->xkey.y_root);
	PUTI("state", ev->xkey.state);
	PUTI("keycode", ev->xkey.keycode);
	break;
    case ButtonPress:
    case ButtonRelease:
	PUTW("window", ev->xbutton.window);
	PUTW("root", ev->xbutton.root);
	PUTW("subwindow", ev->xbutton.subwindow);
	PUTW("time", ev->xbutton.time);
	PUTI("x", ev->xbutton.x);
	PUTI("y", ev->xbutton.y);
	PUTI("x-root", ev->xbutton.x_root);
	PUTI("y-root", ev->xbutton.y_root);
	PUTI("state", ev->xbutton.state);
	PUTI("button", ev->xbutton.button);
	break;
    case MouseWheelEvent:
	/* The button press Tk turned into a wheel event: same struct,
	 * read through xkey (the layouts agree up to button/keycode).
	 * `delta` is Tk's own +-120 per notch — which button it was is
	 * NOT recoverable (4 and 6 both become +120, and Tk adds Shift to
	 * the state for 6 and 7), but the window and the time are, and
	 * those are what answering a grab takes. */
	PUTW("window", ev->xkey.window);
	PUTW("root", ev->xkey.root);
	PUTW("subwindow", ev->xkey.subwindow);
	PUTW("time", ev->xkey.time);
	PUTI("x", ev->xkey.x);
	PUTI("y", ev->xkey.y);
	PUTI("x-root", ev->xkey.x_root);
	PUTI("y-root", ev->xkey.y_root);
	PUTI("state", ev->xkey.state);
	PUTI("delta", (int)ev->xkey.keycode);
	break;
    case MotionNotify:
	PUTW("window", ev->xmotion.window);
	PUTI("x", ev->xmotion.x);
	PUTI("y", ev->xmotion.y);
	PUTI("x-root", ev->xmotion.x_root);
	PUTI("y-root", ev->xmotion.y_root);
	PUTI("state", ev->xmotion.state);
	PUTW("time", ev->xmotion.time);
	break;
    case EnterNotify:
    case LeaveNotify:
	PUTW("window", ev->xcrossing.window);
	PUTW("subwindow", ev->xcrossing.subwindow);
	PUTI("mode", ev->xcrossing.mode);
	PUTI("detail", ev->xcrossing.detail);
	PUTI("x", ev->xcrossing.x);
	PUTI("y", ev->xcrossing.y);
	PUTI("focus", ev->xcrossing.focus != 0);
	break;
    case MappingNotify:
	PUTI("request", ev->xmapping.request);
	PUTI("first-keycode", ev->xmapping.first_keycode);
	PUTI("count", ev->xmapping.count);
	break;
    case SelectionClear:
	PUTW("selection", ev->xselectionclear.selection);
	PUTW("time", ev->xselectionclear.time);
	break;
    }
    return d;
}
#undef PUT
#undef PUTW
#undef PUTI

/* The script side of the generic handler: one command prefix, the
 * event dict appended. Errors go to the background handler — an event
 * pump that dies on one bad dispatch is a desktop that stops. */
typedef struct {
    Tcl_Interp *interp;
    Tcl_Obj *prefix;
} EventSink;

static EventSink *TheSink = NULL;

static int
GenericHandler(void *clientData, XEvent *ev)
{
    EventSink *sink = (EventSink *)clientData;
    Tcl_Obj *cmd;

    if (sink->prefix == NULL) {
	return 0;
    }
    cmd = Tcl_DuplicateObj(sink->prefix);
    Tcl_IncrRefCount(cmd);
    Tcl_ListObjAppendElement(NULL, cmd, EventDict(ev));
    if (Tcl_EvalObjEx(sink->interp, cmd, TCL_EVAL_GLOBAL) != TCL_OK) {
	Tcl_BackgroundException(sink->interp, TCL_ERROR);
    }
    Tcl_DecrRefCount(cmd);
    return 0;			/* never claim the event: Tk gets its own */
}

static int
EventObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	    Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"select", "on", "client", "configure-notify", "masks", NULL
    };
    enum { E_SELECT, E_ON, E_CLIENT, E_CONFIGURE, E_MASKS };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n;
    Tcl_Obj *const *av;
    long mask;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }

    switch (index) {
    case E_MASKS: {
	/* The vocabulary, so a config or a test can check itself. */
	Tcl_Obj *res = Tcl_NewListObj(0, NULL);
	int j;
	for (j = 0; EventMasks[j].name != NULL; j++) {
	    Tcl_ListObjAppendElement(interp, res,
		Tcl_NewStringObj(EventMasks[j].name, -1));
	}
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }

    case E_SELECT: {
	/* Selecting substructure-redirect on the root IS becoming the
	 * window manager; the BadAccess when someone else already is
	 * arrives as an ordinary Tcl error. */
	Tk_Window own;
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv,
			     "?-displayof window? window maskList");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| MaskFromObj(interp, av[1], &mask) != TCL_OK) {
	    return TCL_ERROR;
	}
	own = Tk_IdToWindow(dpy, win);
	if (own != NULL) {
	    /* A window TK OWNS — a frame, a slot. On a foreign window a
	     * selection is per-client and replacing it costs nothing; on
	     * one of ours it would REPLACE the mask Tk selected when it
	     * created the window, and Tk never selects again ("No need to
	     * call XSelectInput: Tk always selects on all events for all
	     * windows", tkEvent.c) — the widget would go blind for good:
	     * no expose, no clicks, no motion, and no way to notice but
	     * the desk misbehaving.
	     *
	     * This is a trap that did not exist while the WM ran on a
	     * second connection, and it is the reason this command knows
	     * about Tk at all: our bits are ADDED to what Tk has, through
	     * Tk's own bookkeeping (so the input-method path, which ORs
	     * into the same field, cannot drop them either). */
	    XSetWindowAttributes atts;
	    atts.event_mask = Tk_Attributes(own)->event_mask | mask;
	    Tk_ChangeWindowAttributes(own, CWEventMask, &atts);
	    return TCL_OK;
	}
	{
	    Trap trap;
	    Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	    XSelectInput(dpy, win, mask);
	    if (TrapEnd(dpy, handler, &trap)) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "the server refused the selection (another window"
		    " manager holds it?)", -1));
		Tcl_SetErrorCode(interp, "TKWMX", "SELECT", (char *)NULL);
		return TCL_ERROR;
	    }
	}
	return TCL_OK;
    }

    case E_ON: {
	/* Install (or, with an empty prefix, remove) the dispatcher.
	 * Events arrive in TK'S OWN event loop — no second connection,
	 * no worker thread, no hand-decoded structs. */
	Tcl_Size len;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? cmdPrefix");
	    return TCL_ERROR;
	}
	if (Tcl_ListObjLength(interp, av[0], &len) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (TheSink == NULL) {
	    TheSink = (EventSink *)ckalloc(sizeof(EventSink));
	    TheSink->interp = interp;
	    TheSink->prefix = NULL;
	    Tk_CreateGenericHandler(GenericHandler, TheSink);
	}
	if (TheSink->prefix != NULL) {
	    Tcl_DecrRefCount(TheSink->prefix);
	    TheSink->prefix = NULL;
	}
	if (len > 0) {
	    TheSink->prefix = Tcl_DuplicateObj(av[0]);
	    Tcl_IncrRefCount(TheSink->prefix);
	}
	return TCL_OK;
    }

    case E_CLIENT: {
	/* A ClientMessage, payload verbatim: WM_TAKE_FOCUS,
	 * WM_DELETE_WINDOW, _NET_* — every protocol built on it, with no
	 * C to write per protocol. */
	XEvent ev;
	Tcl_Size count, i;
	Tcl_Obj **elems;
	int format = 32, propagate = 0;
	long sendMask = NoEventMask;
	Window dest;
	if (n < 3 || n > 6) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? window messageType data ?format?"
		" ?maskList? ?destination?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK
		|| Tcl_ListObjGetElements(interp, av[2], &count, &elems) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n >= 4 && Tcl_GetIntFromObj(interp, av[3], &format) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n >= 5 && MaskFromObj(interp, av[4], &sendMask) != TCL_OK) {
	    return TCL_ERROR;
	}
	/* The message is ABOUT `window`; `destination` is who gets it.
	 * They differ all over EWMH — _NET_ACTIVE_WINDOW,
	 * _NET_CLOSE_WINDOW, _NET_REQUEST_FRAME_EXTENTS and ICCCM's
	 * WM_CHANGE_STATE all name a client window and are SENT TO THE
	 * ROOT, where the manager is listening. Default: the two are
	 * the same window, which is every protocol addressed at the
	 * window's own client. */
	dest = win;
	if (n == 6 && WindowFromObj(interp, tkMain, av[5], &dest) != TCL_OK) {
	    return TCL_ERROR;
	}
	memset(&ev, 0, sizeof(ev));
	ev.xclient.type = ClientMessage;
	ev.xclient.window = win;
	ev.xclient.message_type = (Atom)w;
	ev.xclient.format = format;
	if (format == 32) {
	    for (i = 0; i < count && i < 5; i++) {
		if (Tcl_GetWideIntFromObj(interp, elems[i], &w) != TCL_OK) {
		    return TCL_ERROR;
		}
		ev.xclient.data.l[i] = (long)w;
	    }
	} else if (format == 8) {
	    Tcl_Size blen;
	    unsigned char *bytes = Tcl_GetByteArrayFromObj(av[2], &blen);
	    memcpy(ev.xclient.data.b, bytes, blen > 20 ? 20 : (size_t)blen);
	} else {
	    for (i = 0; i < count && i < 10; i++) {
		int v;
		if (Tcl_GetIntFromObj(interp, elems[i], &v) != TCL_OK) {
		    return TCL_ERROR;
		}
		ev.xclient.data.s[i] = (short)v;
	    }
	}
	XSendEvent(dpy, dest, propagate, sendMask, &ev);
	return TCL_OK;
    }

    case E_CONFIGURE: {
	/* The synthetic ConfigureNotify of ICCCM 4.1.5 — what tells a
	 * reparented client where it really is. Its own class of bug if
	 * left out (menus and clicks land offset), so it is a first-class
	 * command and not something to hand-assemble in a script. */
	XEvent ev;
	int x, y, width, height, bw = 0;
	Window target;
	if (n < 6 || n > 7) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? window eventWindow x y width height ?borderWidth?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| WindowFromObj(interp, tkMain, av[1], &target) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[2], &x) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[3], &y) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[4], &width) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[5], &height) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 7 && Tcl_GetIntFromObj(interp, av[6], &bw) != TCL_OK) {
	    return TCL_ERROR;
	}
	memset(&ev, 0, sizeof(ev));
	ev.xconfigure.type = ConfigureNotify;
	ev.xconfigure.event = target;
	ev.xconfigure.window = win;
	ev.xconfigure.x = x;
	ev.xconfigure.y = y;
	ev.xconfigure.width = width;
	ev.xconfigure.height = height;
	ev.xconfigure.border_width = bw;
	ev.xconfigure.above = None;
	ev.xconfigure.override_redirect = False;
	XSendEvent(dpy, target, False, StructureNotifyMask, &ev);
	return TCL_OK;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* the global error sink                                               */

/*
 * A window manager cannot afford Xlib's default error handler: BadWindow
 * against a client that died mid-request is routine, and the default
 * would exit the process. Tk's own machinery already owns the handler
 * chain, so the sink is a Tk_ErrorHandler that is never deleted — it
 * covers every request from here on, while the per-request traps
 * (TrapBegin) sit closer to their calls and are consulted first.
 */
typedef struct {
    Tcl_Interp *interp;
    Tcl_Obj *prefix;
} ErrorSink;

static ErrorSink *TheErrorSink = NULL;

static int
ErrorSinkProc(void *clientData, XErrorEvent *ev)
{
    ErrorSink *sink = (ErrorSink *)clientData;
    Tcl_Obj *cmd, *d;

    if (sink->prefix == NULL) {
	return 0;
    }
    d = Tcl_NewDictObj();
    Tcl_DictObjPut(NULL, d, Tcl_NewStringObj("serial", -1),
		   Tcl_NewWideIntObj((Tcl_WideInt)ev->serial));
    Tcl_DictObjPut(NULL, d, Tcl_NewStringObj("error", -1),
		   Tcl_NewIntObj(ev->error_code));
    Tcl_DictObjPut(NULL, d, Tcl_NewStringObj("request", -1),
		   Tcl_NewIntObj(ev->request_code));
    Tcl_DictObjPut(NULL, d, Tcl_NewStringObj("minor", -1),
		   Tcl_NewIntObj(ev->minor_code));
    Tcl_DictObjPut(NULL, d, Tcl_NewStringObj("resource", -1),
		   Tcl_NewWideIntObj((Tcl_WideInt)ev->resourceid));
    cmd = Tcl_DuplicateObj(sink->prefix);
    Tcl_IncrRefCount(cmd);
    Tcl_ListObjAppendElement(NULL, cmd, d);
    if (Tcl_EvalObjEx(sink->interp, cmd, TCL_EVAL_GLOBAL) != TCL_OK) {
	Tcl_BackgroundException(sink->interp, TCL_ERROR);
    }
    Tcl_DecrRefCount(cmd);
    return 0;			/* swallowed: surviving beats silence */
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::focus                                                      */

static int
FocusObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	    Tcl_Obj *const objv[])
{
    static const char *const subs[] = { "set", "get", NULL };
    static const char *const reverts[] = { "none", "pointer-root", "parent", NULL };
    static const int revertCodes[] = { RevertToNone, RevertToPointerRoot,
				       RevertToParent };
    enum { F_SET, F_GET };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n, revert = 2;
    Tcl_Obj *const *av;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "set|get ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    if (index == F_GET) {
	/* {window revert-to} — a WM believes the SERVER about the focus,
	 * never its own hopes. */
	Window focus = None;
	int rev = 0;
	Tcl_Obj *res;
	Trap trap;
	Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	XGetInputFocus(dpy, &focus, &rev);
	if (TrapEnd(dpy, handler, &trap)) {
	    return TCL_OK;
	}
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res,
	    Tcl_NewWideIntObj((Tcl_WideInt)focus));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewStringObj(
	    rev == RevertToNone ? "none" :
	    rev == RevertToPointerRoot ? "pointer-root" : "parent", -1));
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }
    /* set WINDOW ?revert? ?time? — the window may also be the literals
     * "pointer-root" or "none", which is how a focus is parked. */
    if (n < 1 || n > 3) {
	Tcl_WrongNumArgs(interp, 2, objv,
			 "?-displayof window? window ?revertTo? ?time?");
	return TCL_ERROR;
    }
    {
	const char *s = Tcl_GetString(av[0]);
	if (strcmp(s, "pointer-root") == 0) {
	    win = PointerRoot;
	} else if (strcmp(s, "none") == 0) {
	    win = None;
	} else if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
    }
    if (n >= 2) {
	if (Tcl_GetIndexFromObj(interp, av[1], reverts, "revertTo", 0,
				&revert) != TCL_OK) {
	    return TCL_ERROR;
	}
	revert = revertCodes[revert];
    } else {
	revert = RevertToParent;
    }
    w = CurrentTime;
    if (n == 3 && Tcl_GetWideIntFromObj(interp, av[2], &w) != TCL_OK) {
	return TCL_ERROR;
    }
    {
	Trap trap;
	Tk_ErrorHandler handler = TrapBegin(dpy, &trap);
	XSetInputFocus(dpy, win, revert, (Time)w);
	Tcl_SetObjResult(interp, Tcl_NewIntObj(!TrapEnd(dpy, handler, &trap)));
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::grab                                                       */

static int
GrabObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	   Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"key", "ungrab-key", "keyboard", "ungrab-keyboard",
	"button", "ungrab-button", "pointer", "ungrab-pointer",
	"allow", NULL
    };
    enum { G_KEY, G_UNKEY, G_KBD, G_UNKBD, G_BUTTON, G_UNBUTTON,
	   G_POINTER, G_UNPOINTER, G_ALLOW };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n, code, mods;
    Tcl_Obj *const *av;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }

    switch (index) {
    case G_KEY:
    case G_UNKEY:
	/* keycode modifiers window — the passive grab a global chord is
	 * made of. Async both ways: there is nothing to freeze. */
	if (n != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? keycode modifiers window");
	    return TCL_ERROR;
	}
	if (Tcl_GetIntFromObj(interp, av[0], &code) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[1], &mods) != TCL_OK
		|| WindowFromObj(interp, tkMain, av[2], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (index == G_KEY) {
	    XGrabKey(dpy, code, (unsigned)mods, win, False,
		     GrabModeAsync, GrabModeAsync);
	} else {
	    XUngrabKey(dpy, code, (unsigned)mods, win);
	}
	return TCL_OK;

    case G_KBD: {
	/* window ?time? -> 1 when the server gave it, 0 when it refused
	 * (someone else holds it) — a refusal is an answer, not an error. */
	int status;
	if (n < 1 || n > 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window ?time?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	w = CurrentTime;
	if (n == 2 && Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	status = XGrabKeyboard(dpy, win, False, GrabModeAsync, GrabModeAsync,
			       (Time)w);
	Tcl_SetObjResult(interp, Tcl_NewIntObj(status == GrabSuccess));
	return TCL_OK;
    }

    case G_UNKBD:
	w = CurrentTime;
	if (n == 1 && Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	XUngrabKeyboard(dpy, (Time)w);
	return TCL_OK;

    case G_BUTTON:
    case G_UNBUTTON: {
	/* button modifiers window ?maskList? — the SYNC grab click-to-focus
	 * is built on: the pointer freezes until the WM decides, then
	 * `grab allow replay-pointer` hands the click to the client. */
	long mask = ButtonPressMask;
	if (n < 3 || n > 4) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? button modifiers window ?maskList?");
	    return TCL_ERROR;
	}
	if (Tcl_GetIntFromObj(interp, av[0], &code) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[1], &mods) != TCL_OK
		|| WindowFromObj(interp, tkMain, av[2], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 4 && MaskFromObj(interp, av[3], &mask) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (index == G_BUTTON) {
	    XGrabButton(dpy, (unsigned)code, (unsigned)mods, win, False,
			(unsigned)mask, GrabModeSync, GrabModeAsync, None, None);
	} else {
	    XUngrabButton(dpy, (unsigned)code, (unsigned)mods, win);
	}
	return TCL_OK;
    }

    case G_POINTER: {
	/* window ?maskList? ?time? ?cursorName? — the cursor is the
	 * GRAB's own, and that is the only way to show one over a
	 * window that is not ours: for the duration of an active grab
	 * the pointer wears what the grab says, and with None it wears
	 * whatever the client under it chose. A WM dragging a foreign
	 * window has nowhere else to put a drag cursor. Empty (the
	 * default) means None — leave the cursor alone. */
	int status;
	Cursor cursor = None;
	long mask = ButtonPressMask | ButtonReleaseMask | PointerMotionMask;
	if (n < 1 || n > 4) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? window ?maskList? ?time? ?cursorName?");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n >= 2 && MaskFromObj(interp, av[1], &mask) != TCL_OK) {
	    return TCL_ERROR;
	}
	w = CurrentTime;
	if (n >= 3 && Tcl_GetWideIntFromObj(interp, av[2], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (n == 4 && CursorFromObj(interp, tkMain, av[3], &cursor) != TCL_OK) {
	    return TCL_ERROR;
	}
	status = XGrabPointer(dpy, win, False, (unsigned)mask,
			      GrabModeAsync, GrabModeAsync, None, cursor,
			      (Time)w);
	Tcl_SetObjResult(interp, Tcl_NewIntObj(status == GrabSuccess));
	return TCL_OK;
    }

    case G_UNPOINTER:
	w = CurrentTime;
	if (n == 1 && Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	XUngrabPointer(dpy, (Time)w);
	return TCL_OK;

    case G_ALLOW: {
	/* NEVER skip this after a sync grab: an unanswered one leaves the
	 * pointer frozen for the whole display. */
	static const char *const modes[] = {
	    "async-pointer", "sync-pointer", "replay-pointer",
	    "async-keyboard", "sync-keyboard", "replay-keyboard", NULL
	};
	static const int codes[] = {
	    AsyncPointer, SyncPointer, ReplayPointer,
	    AsyncKeyboard, SyncKeyboard, ReplayKeyboard
	};
	int mode;
	if (n < 1 || n > 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? mode ?time?");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(interp, av[0], modes, "mode", 0, &mode) != TCL_OK) {
	    return TCL_ERROR;
	}
	w = CurrentTime;
	if (n == 2 && Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	XAllowEvents(dpy, codes[mode], (Time)w);
	return TCL_OK;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::keyboard                                                   */

static int
KeyboardObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	       Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"keysym", "name", "keycode", "at", "state", "autorepeat", NULL
    };
    enum { K_KEYSYM, K_NAME, K_KEYCODE, K_AT, K_STATE, K_AUTOREPEAT };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    int index, n;
    Tcl_Obj *const *av;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }

    switch (index) {
    case K_KEYSYM: {			/* name -> keysym, 0 when unknown */
	KeySym ks;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? name");
	    return TCL_ERROR;
	}
	ks = XStringToKeysym(Tcl_GetString(av[0]));
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
	    ks == NoSymbol ? 0 : (Tcl_WideInt)ks));
	return TCL_OK;
    }
    case K_NAME: {			/* keysym -> name, "" when unknown */
	char *name;
	if (n != 1 || Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? keysym");
	    return TCL_ERROR;
	}
	name = XKeysymToString((KeySym)w);
	Tcl_SetObjResult(interp, Tcl_NewStringObj(name ? name : "", -1));
	return TCL_OK;
    }
    case K_KEYCODE: {			/* keysym -> keycode, 0 when unmapped */
	if (n != 1 || Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? keysym");
	    return TCL_ERROR;
	}
	Tcl_SetObjResult(interp,
	    Tcl_NewIntObj(XKeysymToKeycode(dpy, (KeySym)w)));
	return TCL_OK;
    }
    case K_AT: {			/* keycode ?group? ?level? -> keysym */
	int group = 0, level = 0;
	KeySym ks;
	if (n < 1 || n > 3) {
	    Tcl_WrongNumArgs(interp, 2, objv,
		"?-displayof window? keycode ?group? ?level?");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK
		|| (n >= 2 && Tcl_GetIntFromObj(interp, av[1], &group) != TCL_OK)
		|| (n == 3 && Tcl_GetIntFromObj(interp, av[2], &level) != TCL_OK)) {
	    return TCL_ERROR;
	}
	ks = XkbKeycodeToKeysym(dpy, (KeyCode)w, group, level);
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
	    ks == NoSymbol ? 0 : (Tcl_WideInt)ks));
	return TCL_OK;
    }
    case K_STATE: {
	/* Which keys are physically down, as a 32-byte bit vector — the
	 * honest answer to "is the modifier still held?", which is what
	 * an alt-tab cycle rides on. */
	char keys[32];
	XQueryKeymap(dpy, keys);
	Tcl_SetObjResult(interp,
	    Tcl_NewByteArrayObj((unsigned char *)keys, 32));
	return TCL_OK;
    }
    case K_AUTOREPEAT: {
	/* Detectable autorepeat: without it a held key delivers
	 * release/press pairs and "is it still down" lies. */
	int onoff = 1;
	Bool supported = False;
	if (n == 1 && Tcl_GetBooleanFromObj(interp, av[0], &onoff) != TCL_OK) {
	    return TCL_ERROR;
	}
	XkbSetDetectableAutoRepeat(dpy, onoff ? True : False, &supported);
	Tcl_SetObjResult(interp, Tcl_NewIntObj(supported != False));
	return TCL_OK;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::pointer                                                    */

static int
PointerObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	      Tcl_Obj *const objv[])
{
    static const char *const subs[] = { "query", "warp", NULL };
    enum { P_QUERY, P_WARP };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n;
    Tcl_Obj *const *av;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "query|warp ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    if (n < 1 || WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK) {
	Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window ...");
	return TCL_ERROR;
    }
    if (index == P_QUERY) {
	/* {root-x root-y win-x win-y child state same-screen} — the
	 * pointer as seen from ANY window, ours or a client's. */
	Window root, child;
	int rx, ry, wx, wy;
	unsigned int state;
	Bool same;
	Trap trap;
	Tk_ErrorHandler handler;
	Tcl_Obj *res;
	handler = TrapBegin(dpy, &trap);
	same = XQueryPointer(dpy, win, &root, &child, &rx, &ry, &wx, &wy, &state);
	if (TrapEnd(dpy, handler, &trap)) {
	    return TCL_OK;
	}
	res = Tcl_NewListObj(0, NULL);
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(rx));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(ry));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(wx));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(wy));
	Tcl_ListObjAppendElement(interp, res,
	    Tcl_NewWideIntObj((Tcl_WideInt)child));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj((int)state));
	Tcl_ListObjAppendElement(interp, res, Tcl_NewIntObj(same != False));
	Tcl_SetObjResult(interp, res);
	return TCL_OK;
    }
    {					/* warp: window x y (window may be None) */
	int x, y;
	if (n != 3 || Tcl_GetIntFromObj(interp, av[1], &x) != TCL_OK
		|| Tcl_GetIntFromObj(interp, av[2], &y) != TCL_OK) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window x y");
	    return TCL_ERROR;
	}
	XWarpPointer(dpy, None, win, 0, 0, 0, 0, x, y);
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::selection — the WM_Sn manager selection (ICCCM 4.3)         */

static int
SelectionObjCmd(void *clientData, Tcl_Interp *interp, int objc,
		Tcl_Obj *const objv[])
{
    static const char *const subs[] = { "own", "get", NULL };
    enum { S_OWN, S_GET };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    Window win;
    int index, n;
    Tcl_Obj *const *av;
    Tcl_WideInt w;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "own|get ?-displayof window? ...");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    if (index == S_GET) {
	if (n != 1 || Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? selectionAtom");
	    return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
	    (Tcl_WideInt)XGetSelectionOwner(dpy, (Atom)w)));
	return TCL_OK;
    }
    /* own SELECTION WINDOW ?time? — how a modern WM says "I am the one
     * here", and the hook --replace hangs on. */
    if (n < 2 || n > 3) {
	Tcl_WrongNumArgs(interp, 2, objv,
	    "?-displayof window? selectionAtom window ?time?");
	return TCL_ERROR;
    }
    if (Tcl_GetWideIntFromObj(interp, av[0], &w) != TCL_OK) {
	return TCL_ERROR;
    }
    {
	Atom sel = (Atom)w;
	Tcl_WideInt t = CurrentTime;
	if (WindowFromObj(interp, tkMain, av[1], &win) != TCL_OK
		|| (n == 3 && Tcl_GetWideIntFromObj(interp, av[2], &t) != TCL_OK)) {
	    return TCL_ERROR;
	}
	XSetSelectionOwner(dpy, sel, win, (Time)t);
	Tcl_SetObjResult(interp, Tcl_NewIntObj(
	    XGetSelectionOwner(dpy, sel) == win));
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::atom                                                       */

static int
AtomObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	   Tcl_Obj *const objv[])
{
    static const char *const subs[] = { "intern", "name", NULL };
    enum { A_INTERN, A_NAME };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    int index, n;
    Tcl_Obj *const *av;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "intern|name ?-displayof window? arg");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    if (n != 1) {
	Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? arg");
	return TCL_ERROR;
    }
    if (index == A_INTERN) {
	Atom a = XInternAtom(dpy, Tcl_GetString(av[0]), False);
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)a));
    } else {
	Tcl_WideInt id;
	char *name;
	if (Tcl_GetWideIntFromObj(interp, av[0], &id) != TCL_OK) {
	    return TCL_ERROR;
	}
	name = XGetAtomName(dpy, (Atom)id);
	Tcl_SetObjResult(interp,
			 Tcl_NewStringObj(name == NULL ? "" : name, -1));
	if (name != NULL) {
	    XFree(name);
	}
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::server                                                     */

static int
ServerObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	     Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"sync", "flush", "display", "close-down-mode", "error-text",
	"error-handler", "time", NULL
    };
    enum { S_SYNC, S_FLUSH, S_DISPLAY, S_CLOSEDOWN, S_ERRTEXT, S_ERRHANDLER,
	   S_TIME };
    Tk_Window tkMain = (Tk_Window)clientData;
    Display *dpy;
    int index, n, discard = 0;
    Tcl_Obj *const *av;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "sync|flush|display ?-displayof window?");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0,
			    &index) != TCL_OK) {
	return TCL_ERROR;
    }
    n = objc - 2;
    av = objv + 2;
    dpy = DisplayOf(interp, tkMain, &n, &av, NULL);
    if (dpy == NULL) {
	return TCL_ERROR;
    }
    switch (index) {
    case S_SYNC:
	if (n == 1 && Tcl_GetBooleanFromObj(interp, av[0], &discard) != TCL_OK) {
	    return TCL_ERROR;
	}
	XSync(dpy, discard ? True : False);
	break;
    case S_FLUSH:
	XFlush(dpy);
	break;
    case S_DISPLAY:
	/* The display's name and its connection number: enough for a
	 * script to prove it is riding TK'S connection and not one of
	 * its own. */
	{
	    Tcl_Obj *res = Tcl_NewListObj(0, NULL);
	    Tcl_ListObjAppendElement(interp, res,
		Tcl_NewStringObj(DisplayString(dpy), -1));
	    Tcl_ListObjAppendElement(interp, res,
		Tcl_NewIntObj(ConnectionNumber(dpy)));
	    Tcl_SetObjResult(interp, res);
	}
	break;
    case S_CLOSEDOWN: {
	/* RetainTemporary is how a window manager survives its own death
	 * honestly: resources it created stay alive for the clients that
	 * depend on them until someone claims them back. */
	static const char *const modes[] = {
	    "destroy-all", "retain-permanent", "retain-temporary", NULL
	};
	static const int codes[] = {
	    DestroyAll, RetainPermanent, RetainTemporary
	};
	int mode;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? mode");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(interp, av[0], modes, "mode", 0, &mode) != TCL_OK) {
	    return TCL_ERROR;
	}
	XSetCloseDownMode(dpy, codes[mode]);
	break;
    }
    case S_ERRTEXT: {
	/* The server's own words for an error code — better in a log than
	 * a table of names maintained by hand in the script. */
	char buf[256];
	int code;
	if (n != 1 || Tcl_GetIntFromObj(interp, av[0], &code) != TCL_OK) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? errorCode");
	    return TCL_ERROR;
	}
	XGetErrorText(dpy, code, buf, sizeof(buf));
	Tcl_SetObjResult(interp, Tcl_NewStringObj(buf, -1));
	break;
    }
    case S_ERRHANDLER: {
	/* The sink for everything the per-request traps did not claim:
	 * a WM must outlive BadWindow against a client that died a
	 * moment ago, and it must SAY so rather than vanish quietly. An
	 * empty prefix removes it. */
	Tcl_Size len;
	if (n != 1) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? cmdPrefix");
	    return TCL_ERROR;
	}
	if (Tcl_ListObjLength(interp, av[0], &len) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (TheErrorSink == NULL) {
	    TheErrorSink = (ErrorSink *)ckalloc(sizeof(ErrorSink));
	    TheErrorSink->interp = interp;
	    TheErrorSink->prefix = NULL;
	    /* never deleted: it must cover every request from now on */
	    Tk_CreateErrorHandler(dpy, -1, -1, -1, ErrorSinkProc, TheErrorSink);
	}
	if (TheErrorSink->prefix != NULL) {
	    Tcl_DecrRefCount(TheErrorSink->prefix);
	    TheErrorSink->prefix = NULL;
	}
	if (len > 0) {
	    TheErrorSink->prefix = Tcl_DuplicateObj(av[0]);
	    Tcl_IncrRefCount(TheErrorSink->prefix);
	}
	break;
    }
    case S_TIME: {
	/* window atom -> a FRESH server timestamp, fetched and not guessed.
	 * Every WM_TAKE_FOCUS invitation must carry a time newer than the
	 * server's last focus change or the client's answer is dropped as
	 * stale, and an accumulated clock fed by whatever events happened
	 * to arrive goes stale exactly when it matters (typing INTO a
	 * window is invisible to a WM).
	 *
	 * The standard recipe, gdk_x11_get_server_time's own: a ZERO-LENGTH
	 * append to a property on a window of ours changes nothing, and the
	 * server answers with a PropertyNotify carrying its current time.
	 * The window must have property-change selected, or this waits
	 * forever — it is meant for the WM's own check window.
	 *
	 * Why in C: the wait is a synchronous pull out of Xlib's queue.
	 * Events that do not match stay queued and reach Tk afterwards, and
	 * nothing re-enters the event loop in between — which a script
	 * doing the same with vwait could not promise. The SERIAL guard is
	 * what makes the answer ours: a notification already in the queue
	 * when we asked carries an older time, and an older time is the one
	 * thing this command exists to avoid. */
	XEvent ev;
	Window win;
	Atom prop;
	unsigned long serial;
	Tcl_WideInt w;
	if (n != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, "?-displayof window? window atom");
	    return TCL_ERROR;
	}
	if (WindowFromObj(interp, tkMain, av[0], &win) != TCL_OK
		|| Tcl_GetWideIntFromObj(interp, av[1], &w) != TCL_OK) {
	    return TCL_ERROR;
	}
	prop = (Atom)w;
	serial = NextRequest(dpy);
	XChangeProperty(dpy, win, prop, XA_STRING, 8, PropModeAppend,
			(const unsigned char *)"", 0);
	for (;;) {
	    XWindowEvent(dpy, win, PropertyChangeMask, &ev);
	    if (ev.type == PropertyNotify && ev.xproperty.atom == prop
		    && ev.xproperty.serial >= serial) {
		break;
	    }
	}
	Tcl_SetObjResult(interp,
			 Tcl_NewWideIntObj((Tcl_WideInt)ev.xproperty.time));
	break;
    }
    }
    return TCL_OK;
}

/* ------------------------------------------------------------------ */
/* ::tkwmx::exec-self                                                  */

/*
 * Restart in place: replace this process with a fresh copy of itself.
 * Same pid, same stdout, code re-read from disk — and, for a window
 * manager, no gap in which a second instance could race for the
 * redirect (the reason a fork/exec-then-exit dance will not do). The X
 * sockets are close-on-exec, so the server reaps the old frames itself
 * and the fresh instance adopts the clients that were released.
 *
 * Returns only on failure; on success there is nobody left to return to.
 */
static int
ExecSelfObjCmd(void *clientData, Tcl_Interp *interp, int objc,
	       Tcl_Obj *const objv[])
{
    Tcl_Obj **elems = NULL;
    Tcl_Size count = 0, i;
    char **argv;
    const char *path;
    Tcl_Channel ch;
    (void)clientData;

    if (objc < 2 || objc > 3) {
	Tcl_WrongNumArgs(interp, 1, objv, "path ?argList?");
	return TCL_ERROR;
    }
    path = Tcl_GetString(objv[1]);
    if (objc == 3
	    && Tcl_ListObjGetElements(interp, objv[2], &count, &elems) != TCL_OK) {
	return TCL_ERROR;
    }
    /* argv[0] is the path itself, then the list — the shape execv wants */
    argv = (char **)ckalloc(sizeof(char *) * (size_t)(count + 2));
    argv[0] = (char *)path;
    for (i = 0; i < count; i++) {
	argv[i + 1] = Tcl_GetString(elems[i]);
    }
    argv[count + 1] = NULL;
    /* Whatever the log still holds must be on its way out before the
     * process it belongs to stops existing. */
    if ((ch = Tcl_GetStdChannel(TCL_STDOUT)) != NULL) {
	Tcl_Flush(ch);
    }
    if ((ch = Tcl_GetStdChannel(TCL_STDERR)) != NULL) {
	Tcl_Flush(ch);
    }
    execv(path, argv);
    ckfree(argv);
    Tcl_SetObjResult(interp, Tcl_ObjPrintf("cannot exec \"%s\": %s", path,
					   Tcl_PosixError(interp)));
    return TCL_ERROR;
}

/* ------------------------------------------------------------------ */

int
Tkwmx_Init(Tcl_Interp *interp)
{
    Tk_Window tkMain;

    if (Tcl_InitStubs(interp, "8.6-", 0) == NULL) {
	return TCL_ERROR;
    }
    if (Tk_InitStubs(interp, "8.6-", 0) == NULL) {
	return TCL_ERROR;
    }
    tkMain = Tk_MainWindow(interp);
    if (tkMain == NULL) {
	Tcl_SetObjResult(interp, Tcl_NewStringObj(
	    "tkwmx needs Tk: package require Tk first", -1));
	return TCL_ERROR;
    }
    Tcl_CreateNamespace(interp, "::tkwmx", NULL, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::window", WindowObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::prop", PropObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::focus", FocusObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::grab", GrabObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::keyboard", KeyboardObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::pointer", PointerObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::selection", SelectionObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::event", EventObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::atom", AtomObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::server", ServerObjCmd, tkMain, NULL);
    Tcl_CreateObjCommand(interp, "::tkwmx::exec-self", ExecSelfObjCmd, tkMain, NULL);
    return Tcl_PkgProvide(interp, "tkwmx", "0.1");
}
