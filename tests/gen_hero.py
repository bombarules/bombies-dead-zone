"""Builds the one-piece hero: assets/hero/hero.glb (single skinned mesh, ONE material/atlas)
and assets/hero/hero_fps.glb (first-person weapon + gloved hands, same atlas).
Run:  python3 tests/gen_hero.py
"""
import json, struct, io, sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from gen_hero_geo import *
import gen_hero_tex as TX

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "hero")
os.makedirs(OUT, exist_ok=True)
LAYOUT = TX.layout()

BONES = ["root", "hips", "chest", "head", "up_l", "fore_l", "hand_l", "up_r", "fore_r", "hand_r",
         "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r", "gun"]
PARENT = {"hips": "root", "chest": "hips", "head": "chest", "up_l": "chest", "fore_l": "up_l", "hand_l": "fore_l",
          "up_r": "chest", "fore_r": "up_r", "hand_r": "fore_r", "thigh_l": "hips", "shin_l": "thigh_l",
          "foot_l": "shin_l", "thigh_r": "hips", "shin_r": "thigh_r", "foot_r": "shin_r", "gun": "root"}
REST = {"root": (0, 0, 0), "hips": (0, .95, 0), "chest": (0, 1.2, 0), "head": (0, 1.5, 0),
        "up_l": (-.31, 1.42, 0), "fore_l": (-.31, 1.13, 0), "hand_l": (-.31, .88, 0),
        "up_r": (.31, 1.42, 0), "fore_r": (.31, 1.13, 0), "hand_r": (.31, .88, 0),
        "thigh_l": (-.115, .95, 0), "shin_l": (-.115, .52, 0), "foot_l": (-.115, .1, 0),
        "thigh_r": (.115, .95, 0), "shin_r": (.115, .52, 0), "foot_r": (.115, .1, 0),
        "gun": (.26, 1.0, -.28)}
BI = {n: i for i, n in enumerate(BONES)}

# ---------------------------------------------------------------- weights
def W_single(b):
    def f(P, aux):
        j = np.zeros((len(P), 4), int); w = np.zeros((len(P), 4)); j[:, 0] = BI[b]; w[:, 0] = 1; return j, w
    return f

def W_blend_y(top, bot, y0, y1):
    def f(P, aux):
        t = TX.smooth(y0, y1, P[:, 1]); j = np.zeros((len(P), 4), int); w = np.zeros((len(P), 4))
        j[:, 0] = BI[top]; w[:, 0] = t; j[:, 1] = BI[bot]; w[:, 1] = 1-t; return j, w
    return f

def W_chain(*stops):
    """stops: [(bone, y_center), ...] descending y; smooth blending between consecutive bones near boundary."""
    def f(P, aux):
        n = len(P); j = np.zeros((n, 4), int); w = np.zeros((n, 4))
        y = P[:, 1]
        # piecewise: bones listed top->bottom with boundaries (y_hi, y_lo)
        raw = []
        for k, (b, yc) in enumerate(stops):
            raw.append(np.zeros(n))
        out_j = []; out_w = []
        # linear partition of unity by hat functions on joint heights
        ys = np.array([s[1] for s in stops])  # descending
        for k, (b, yc) in enumerate(stops):
            hat = np.zeros(n)
            if k > 0:
                up = ys[k-1]; m = (y <= up) & (y >= yc)
                hat = np.where(m, (y-yc)/(up-yc), hat)
            if k < len(stops)-1:
                dn = ys[k+1]; m = (y <= yc) & (y >= dn)
                hat = np.where(m, (y-dn)/(yc-dn), hat)
            else:
                hat = np.where(y <= yc, 1, hat)
            if k == 0:
                hat = np.where(y >= yc, 1, hat)
            out_j.append(np.full(n, BI[b])); out_w.append(hat)
        # keep top 4
        J = np.stack(out_j, 1); Wt = np.stack(out_w, 1)
        order = np.argsort(-Wt, 1)[:, :4]
        j = np.take_along_axis(J, order, 1); w = np.take_along_axis(Wt, order, 1)
        w = w/np.maximum(w.sum(1, keepdims=True), 1e-9)
        if j.shape[1] < 4:
            pad = 4-j.shape[1]; j = np.pad(j, ((0, 0), (0, pad))); w = np.pad(w, ((0, 0), (0, pad)))
        return j, w
    return f

def W_aux(a, b):
    def f(P, aux):
        j = np.zeros((len(P), 4), int); w = np.zeros((len(P), 4))
        j[:, 0] = BI[a]; w[:, 0] = 1-aux; j[:, 1] = BI[b]; w[:, 1] = aux; return j, w
    return f

# ---------------------------------------------------------------- mesh accumulator
class MeshBuilder:
    def __init__(self, skinned=True):
        self.P = []; self.N = []; self.UV = []; self.J = []; self.W = []; self.C = []
        self.skinned = skinned

    def add(self, prim, M, region, wfn=None, mode="planar", uvrect=None, color=None):
        L = LAYOUT[region]
        P = prim["P"]@M[:3, :3].T + M[:3, 3]
        Nm = prim["N"]@np.linalg.inv(M[:3, :3])
        Nm = Nm/np.maximum(np.linalg.norm(Nm, axis=1, keepdims=True), 1e-9)
        F = prim["F"].copy()
        # fix winding vs vertex normals
        a, b, c = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
        gn = np.cross(b-a, c-a)
        vn = Nm[F[:, 0]] + Nm[F[:, 1]] + Nm[F[:, 2]]
        flip = (gn*vn).sum(1) < 0
        F[flip] = F[flip][:, [0, 2, 1]]
        a, b, c = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
        area = np.linalg.norm(np.cross(b-a, c-a), axis=1)
        keep = area > 1e-9
        F = F[keep]
        # per-vertex weights
        aux = prim.get("aux", np.zeros(len(P)))
        if self.skinned:
            J, Wt = wfn(P, aux)
        else:
            J = np.zeros((len(P), 4), int); Wt = np.zeros((len(P), 4))
        # triangle soup
        Pt = P[F].reshape(-1, 3); Nt = Nm[F].reshape(-1, 3); Jt = J[F].reshape(-1, 4); Wtt = Wt[F].reshape(-1, 4)
        nt = len(F)
        x0, y0, w, h = L["rect"]; g = L["g"]; T = L["T"]
        if mode == "planar":
            tn = Nm[F].mean(1); ax = np.argmax(np.abs(tn), 1)
            Pf = P[F]  # (nt,3,3)
            uu = np.zeros((nt, 3)); vv = np.zeros((nt, 3))
            for k, (cu, cv) in enumerate([(2, 1), (0, 2), (0, 1)]):
                m = ax == k
                uu[m] = Pf[m][:, :, cu]; vv[m] = Pf[m][:, :, cv]
            uu = uu/L["meters"]; vv = vv/L["meters"]
            uu = uu - np.floor(uu.min(1, keepdims=True)); vv = vv - np.floor(vv.min(1, keepdims=True))
            px = x0 + g + uu*T; py = y0 + g + vv*T
            UVt = np.stack([px, py], -1).reshape(-1, 2)/TX.ATLAS
        else:
            uv = prim["UV"] if mode == "native" else None
            if mode == "xyproj":
                uv = np.stack([prim["P"][:, 0]*0.5+0.5, 0.5-prim["P"][:, 1]*0.5], -1)
            if uvrect is not None:
                rx, ry, rw, rh = uvrect  # fraction within region
            else:
                rx, ry, rw, rh = 0, 0, 1, 1
            ux = x0 + g + (rx + np.clip(uv[:, 0], 0, 1)*rw)*(w-2*g)
            uy = y0 + g + (ry + np.clip(uv[:, 1], 0, 1)*rh)*(h-2*g)
            UVt = (np.stack([ux, uy], -1)[F].reshape(-1, 2))/TX.ATLAS
        # vertex colour: dirt near floor + mild noise
        y = Pt[:, 1]
        dirt = TX.smooth(0.75, 0.0, y)*0.5
        col = np.stack([1-dirt*0.35, 1-dirt*0.5, 1-dirt*0.7, np.ones_like(y)], 1)
        if color is not None:
            col[:, :3] *= np.array(color)
        self.P.append(Pt); self.N.append(Nt); self.UV.append(UVt); self.J.append(Jt); self.W.append(Wtt); self.C.append(col)

    def arrays(self):
        c = lambda l: np.concatenate(l, 0)
        return c(self.P), c(self.N), c(self.UV), c(self.J), c(self.W), c(self.C)

# ---------------------------------------------------------------- helpers
def ell(mb, r, pos, region, wfn, scale=(1, 1, 1), rot=(0, 0, 0), q=2.0, seg=14, rings=9, **kw):
    mb.add(superell(q, seg, rings), xf(pos, rot, (r[0]*scale[0], r[1]*scale[1], r[2]*scale[2])), region, wfn, **kw)

def cyl(mb, rt, rb, h, pos, region, wfn, rot=(0, 0, 0), scale=(1, 1, 1), seg=12, **kw):
    prof = [(0, h/2, 0, 1), (rt, h/2, 0, 1), (rt, h/2, 1, 0), (rb, -h/2, 1, 0), (rb, -h/2, 0, -1), (0, -h/2, 0, -1)]
    # side normal tilt
    t = np.hypot(h, rb-rt); nr, ny = h/t, (rb-rt)/t
    prof[2] = (rt, h/2, nr, ny); prof[3] = (rb, -h/2, nr, ny)
    mb.add(lathe(prof, seg), xf(pos, rot, scale), region, wfn, **kw)

def lath(mb, prof, pos, region, wfn, rot=(0, 0, 0), scale=(1, 1, 1), seg=16, **kw):
    mb.add(lathe(prof, seg), xf(pos, rot, scale), region, wfn, **kw)

def bx(mb, size, pos, region, wfn, rot=(0, 0, 0), q=None, **kw):
    if q is None:
        mb.add(box(*size), xf(pos, rot), region, wfn, **kw)
    else:
        mb.add(superell(q, 12, 8), xf(pos, rot, tuple(s/2 for s in size)), region, wfn, **kw)

def tub(mb, pts, r, region, wfn, sides=8, pitch=0, amp=0, per=8, **kw):
    mb.add(tube(pts, r, sides, pitch, amp, per), np.eye(4), region, wfn, **kw)

def mirror_x(p):
    return (-p[0], p[1], p[2])

# ---------------------------------------------------------------- the gun (gun-local coords, barrel to -Z, grip at origin)
def build_gun(mb, W, off=(0, 0, 0), hero_space=True):
    """Adds the multi-barrel industrial rifle. W = weight fn for rigid parts; off = placement offset."""
    ox, oy, oz = off
    def p(x, y, z): return (x+ox, y+oy, z+oz)
    # receiver block (dark gunmetal)
    bx(mb, (.085, .12, .34), p(0, .03, -.09), "metal", W, q=6)
    bx(mb, (.06, .06, .16), p(0, .105, -.02), "rubber", W, q=5)          # top housing
    bx(mb, (.032, .028, .30), p(0, .145, -.1), "metal", W, q=6)          # top rail
    cyl(mb, .017, .017, .09, p(0, .165, -.2), "silver", W, rot=(90, 0, 0), seg=10)  # optic tube
    ell(mb, (.02, .02, .02), p(0, .165, -.255), "pad", W, mode="native")  # lens cap
    # stock / rear block
    bx(mb, (.06, .1, .09), p(0, .0, .13), "metal", W, q=5)
    bx(mb, (.05, .06, .05), p(0, .02, .2), "rubber", W, q=4)
    # pistol grip (rubber)
    bx(mb, (.042, .13, .055), p(0, -.075, .025), "rubber", W, rot=(-12, 0, 0), q=5)
    # trigger guard
    bx(mb, (.012, .05, .05), p(0, -.02, -.05), "metal", W, q=4)
    # foregrip + underbarrel clamp
    bx(mb, (.04, .11, .045), p(0, -.085, -.25), "rubber", W, q=5)
    bx(mb, (.07, .03, .06), p(0, -.025, -.25), "metal", W, q=5)
    # triple barrel
    for (bxp, byp, zl, zc) in [(0, .045, .46, -.42), (-.036, -.002, .42, -.40), (.036, -.002, .38, -.38)]:
        cyl(mb, .0185, .0185, zl, p(bxp, byp, zc), "metal", W, rot=(90, 0, 0), seg=10)
        cyl(mb, .025, .025, .025, p(bxp, byp, zc-zl/2+.01), "silver", W, rot=(90, 0, 0), seg=10)  # muzzle ring
        cyl(mb, .012, .012, .01, p(bxp, byp, zc-zl/2-.01), "rubber", W, rot=(90, 0, 0), seg=8)
    for zc in (-.32, -.5):
        cyl(mb, .06, .06, .026, p(0, .014, zc), "silver", W, rot=(90, 0, 0), scale=(1.1, 1, .9), seg=14)
    # side canister (silver, left) with rubber bands
    cyl(mb, .036, .036, .24, p(-.082, .03, -.11), "silver", W, rot=(90, 0, 0), seg=12)
    for zc in (-.03, -.11, -.19):
        cyl(mb, .039, .039, .018, p(-.082, .03, zc), "rubber", W, rot=(90, 0, 0), seg=12)
    ell(mb, (.034, .034, .03), p(-.082, .03, -.24), "silver", W, seg=12)
    # brass valve cylinder right + black tank
    cyl(mb, .028, .028, .2, p(.07, .06, -.1), "brass", W, rot=(90, 0, 0), seg=10)
    cyl(mb, .032, .032, .02, p(.07, .06, -.2), "metal", W, rot=(90, 0, 0), seg=10)
    cyl(mb, .022, .022, .15, p(.074, -.02, -.13), "rubber", W, rot=(90, 0, 0), seg=10)
    cyl(mb, .01, .01, .05, p(.07, .105, -.1), "brass", W, seg=8)       # valve stem
    cyl(mb, .022, .022, .01, p(.07, .135, -.1), "metal", W, seg=10)    # valve wheel
    # pressure gauge on left
    cyl(mb, .026, .026, .014, p(-.125, .07, .02), "silver", W, rot=(0, 0, 90), seg=14)
    cyl(mb, .02, .02, .004, p(-.133, .07, .02), "misc", W, rot=(0, 0, 90), seg=12, mode="native", uvrect=(.5, 0, .5, .5))
    # LEDs
    ell(mb, (.008, .008, .008), p(.045, .095, .03), "misc", W, mode="native", uvrect=(.5, 0, .5, .5), seg=8, rings=5)
    ell(mb, (.008, .008, .008), p(.045, .095, .0), "misc", W, mode="native", uvrect=(0, .5, .5, .5), seg=8, rings=5)
    # red + black cables on the gun
    tub(mb, [p(-.082, .07, -.2), p(-.1, .12, -.05), p(-.07, .13, .08), p(-.03, .08, .13)], .006, "misc", W, sides=6, mode="native", uvrect=(0, 0, .5, .5))
    tub(mb, [p(.07, .09, -.18), p(.1, .14, -.08), p(.08, .16, .05), p(.03, .1, .13)], .007, "rubber", W, sides=6)
    tub(mb, [p(-.03, -.02, -.3), p(-.11, -.1, -.28), p(-.17, -.05, -.15), p(-.15, .04, -.02), p(-.1, .06, .06)], .007, "misc", W, sides=6, mode="native", uvrect=(0, 0, .5, .5))
    # wire loop frame on left side
    tub(mb, [p(-.1, .12, .12), p(-.2, .1, .12), p(-.24, -.02, .08), p(-.2, -.14, .03), p(-.1, -.13, .0)], .008, "rubber", W, sides=6, per=6)
    tub(mb, [p(-.09, .0, .17), p(-.17, -.03, .2), p(-.21, -.12, .16), p(-.16, -.2, .1), p(-.09, -.19, .06)], .006, "rubber", W, sides=6, per=6)

# ---------------------------------------------------------------- the hero
def build_hero():
    mb = MeshBuilder(True)
    S = W_single
    # ---------------- torso, pelvis
    torso = [(.0, .86, 0, -1), (.15, .87, .3, -.9), (.19, .95, 1, -.2), (.205, 1.05, 1, 0), (.205, 1.15, 1, .05),
             (.215, 1.27, 1, .15), (.222, 1.38, .9, .4), (.19, 1.47, .5, .8), (.13, 1.52, .3, .95), (.0, 1.54, 0, 1)]
    lath(mb, torso, (0, 0, 0), "suit", W_chain(("chest", 1.32), ("hips", 1.0)), scale=(1.28, 1, .82), seg=20)
    ell(mb, (.19, .13, .17), (0, .95, 0), "suit", S("hips"), scale=(1.2, 1, 1), seg=16)  # pelvis
    # cowl (hood drape over shoulders)
    cowl = [(.105, 1.58, .3, .9), (.135, 1.545, .6, .8), (.19, 1.5, .5, .8), (.235, 1.45, .6, .7), (.24, 1.41, 1, .2), (.232, 1.375, .8, -.4), (.2, 1.34, 0, -1)]
    lath(mb, cowl, (0, 0, 0), "suit", W_chain(("head", 1.52), ("chest", 1.40)), scale=(1.28, 1, .84), seg=24)
    # ---------------- head / hood
    ell(mb, (.205, .235, .22), (0, 1.67, .0), "suit", S("head"), seg=24, rings=16, q=2.15)
    
    # hood seam ridge on the back/top
    tub(mb, [(0, 1.89, .07), (0, 1.82, .17), (0, 1.7, .22), (0, 1.58, .22)], .012, "suit", S("head"), sides=6)
    # visor frame (grey rubber) + glass dome
    HY, HZ = 1.69, -.2
    mb.add(torus(.118, .013, 28, 8), xf((0, HY, HZ+.0), (90, 0, 0), (1, 1, 1.15)), "metal", S("head"))
    mb.add(torus(.132, .008, 28, 6), xf((0, HY, HZ-.005), (90, 0, 0), (1, 1, 1.15)), "rubber", S("head"))
    mb.add(superell(2.0, 22, 12), xf((0, HY, HZ+.04), (0, 0, 0), (.118, .136, .075)), "visor", S("head"), mode="xyproj")
    # gas mask (lower face)
    ell(mb, (.1, .078, .085), (0, 1.585, -.16), "rubber", S("head"), scale=(1, 1, 1), seg=16, rings=10, q=2.4)
    ell(mb, (.05, .05, .05), (0, 1.55, -.22), "rubber", S("head"), seg=12)   # nose/mouth bulge
    cyl(mb, .03, .03, .026, (0, 1.55, -.262), "silver", S("head"), rot=(90, 0, 0), seg=12)  # speaking port
    for k in range(3):
        cyl(mb, .027, .027, .004, (0, 1.55, -.277), "metal", S("head"), rot=(90, 0, 0), seg=10)
    # tape across mask and cowl
    for (pos, rot, size) in [((0, 1.612, -.205), (0, 0, 22), (.17, .028, .014)), ((0, 1.575, -.21), (0, 0, -18), (.16, .026, .014)),
                             ((-.04, 1.61, -.20), (0, 0, 95), (.07, .024, .012))]:
        bx(mb, size, pos, "tape", S("head"), rot=rot, q=6)
    # filter canisters (cheeks)
    for sx in (-1, 1):
        rotz = 90
        cyl(mb, .042, .042, .075, (sx*.118, 1.56, -.16), "silver", S("head"), rot=(90, 0, 0), seg=14)  # body (axis z)
        cyl(mb, .046, .046, .016, (sx*.118, 1.56, -.205), "rubber", S("head"), rot=(90, 0, 0), seg=14)  # front cap band
        cyl(mb, .044, .044, .01, (sx*.118, 1.56, -.12), "rubber", S("head"), rot=(90, 0, 0), seg=14)
        cyl(mb, .028, .028, .012, (sx*.118, 1.56, -.218), "metal", S("head"), rot=(90, 0, 0), seg=10)
        cyl(mb, .017, .017, .06, (sx*.165, 1.545, -.115), "metal", S("head"), rot=(0, 0, 90), seg=8)   # hose port
        tube_pts = None
    # patches on hood
    bx(mb, (.1, .044, .014), (0, 1.855, -.1), "pad", S("head"), rot=(-50, 0, 0), q=5, mode="native")
    bx(mb, (.05, .07, .014), (-.168, 1.7, -.06), "pad", S("head"), rot=(0, -78, 0), q=5, mode="native")
    # ---------------- shoulders + arms
    for sx, s in ((-1, "l"), (1, "r")):
        up, fo, ha = "up_"+s, "fore_"+s, "hand_"+s
        X = sx*.31
        ell(mb, (.118, .112, .118), (X, 1.41, 0), "suit", W_blend_y(up, "chest", 1.35, 1.46), seg=14, rings=9)
        sleeve = [(.0, 1.42, 0, 1), (.085, 1.41, .6, .6), (.098, 1.34, 1, .05), (.092, 1.22, 1, 0), (.082, 1.14, 1, -.1),
                  (.074, 1.05, 1, -.05), (.068, .95, 1, 0), (.07, .93, 1, -.1)]
        lath(mb, sleeve, (X, 0, 0), "suit", W_chain((up, 1.3), (fo, 1.13), (fo, .93)), scale=(1, 1, 1), seg=14)
        # glove: gauntlet cuff + fist
        lath(mb, [(.082, .95, 0, 1), (.088, .93, 1, .1), (.088, .83, 1, 0), (.076, .78, .8, -.5)], (X, 0, 0), "glove", S(ha), seg=14)
        ell(mb, (.052, .07, .045), (X, .73, 0), "glove", S(ha), seg=12, rings=8, q=2.8)
        for fi, fz in enumerate((-.04, -.015, .01, .035)):
            ell(mb, (.012, .042, .013), (X+sx*.0, .69, -.045*1.0 + (fi-1.5)*0.0 + 0.0), "glove", S(ha), seg=6, rings=4) if False else None
        # curled fingers across the front
        for fi in range(4):
            fy = .775 - fi*.0
            ell(mb, (.052/4+.004, .018, .016), (X + (fi-1.5)*.021, .69, -.052), "glove", S(ha), seg=8, rings=5, q=2.6)
            ell(mb, (.011, .026, .011), (X + (fi-1.5)*.021, .665, -.05), "glove", S(ha), seg=6, rings=4)
        ell(mb, (.016, .036, .018), (X - sx*.0, .74, -.047), "glove", S(ha), seg=8, rings=5, rot=(0, 0, sx*-25), scale=(1, 1, 1))  # thumb
        # shoulder pad + upper arm patch (grey)
        bx(mb, (.075, .02, .105), (X+sx*.022, 1.512, .0), "pad", W_blend_y(up, "chest", 1.35, 1.46), rot=(0, 0, sx*-20), q=5, mode="native")
        bx(mb, (.016, .12, .09), (X+sx*.095, 1.31, -.0), "pad", S(up), rot=(0, 0, 0), q=5, mode="native")
        bx(mb, (.1, .045, .014), (X+sx*.0, 1.24, -.092), "tape", S(up), rot=(20, 0, 0), q=6)
        # elbow patch
        bx(mb, (.07, .085, .02), (X, 1.13, .085), "pad", S(fo), q=4, mode="native")
    # ---------------- chest patches, tape, details
    bx(mb, (.115, .14, .02), (.115, 1.255, -.187), "greenpatch", S("chest"), rot=(0, -6, 4), q=4, mode="native")
    bx(mb, (.03, .16, .014), (.06, 1.24, -.196), "webbing", S("chest"), rot=(0, 0, -22), q=4)
    bx(mb, (.17, .21, .018), (-.1, 1.235, -.19), "pad", S("chest"), rot=(0, 8, 28), q=4, mode="native")
    for (pos, rot, size) in [((-.07, 1.3, -.2), (0, 0, 28), (.2, .03, .014)), ((-.115, 1.2, -.2), (0, 0, -24), (.12, .026, .014)),
                             ((0, 1.44, -.225), (0, 0, 30), (.16, .03, .014)), ((.03, 1.43, -.228), (0, 0, -30), (.14, .028, .014)),
                             ((-.02, 1.39, -.225), (0, 0, 80), (.1, .026, .014))]:
        bx(mb, size, pos, "tape", S("chest"), rot=rot, q=6)
    bx(mb, (.05, .06, .02), (.0, 1.215, -.188), "metal", S("chest"), q=4)   # zipper pull plate
    tub(mb, [(0, 1.45, -.215), (0, 1.3, -.225), (0, 1.12, -.2)], .006, "suit", S("chest"), sides=6)  # centre seam
    # back filter pack
    bx(mb, (.3, .3, .11), (0, 1.27, .205), "metal", S("chest"), q=5)
    bx(mb, (.26, .24, .02), (0, 1.27, .26), "pad", S("chest"), q=5, mode="native")
    for sx in (-1, 1):
        cyl(mb, .045, .045, .2, (sx*.085, 1.22, .27), "silver", S("chest"), seg=14)
        cyl(mb, .05, .05, .02, (sx*.085, 1.33, .27), "rubber", S("chest"), seg=14)
        cyl(mb, .05, .05, .02, (sx*.085, 1.12, .27), "rubber", S("chest"), seg=14)
    tub(mb, [(-.165, 1.545, .0), (-.2, 1.56, .12), (-.14, 1.5, .22), (-.085, 1.38, .26)], .02, "rubber", W_aux("chest", "head") if False else W_blend_y("head", "chest", 1.4, 1.55), sides=8, pitch=.026, amp=.16)
    tub(mb, [(.165, 1.545, .0), (.2, 1.56, .12), (.14, 1.5, .22), (.085, 1.38, .26)], .02, "rubber", W_blend_y("head", "chest", 1.4, 1.55), sides=8, pitch=.026, amp=.16)
    # ---------------- HOSES at the front
    HW = W_blend_y("head", "chest", 1.4, 1.58)
    # necklace hose from hero-left canister around neck to the right shoulder, then down to belt
    tub(mb, [(-.165, 1.545, -.12), (-.235, 1.5, -.1), (-.24, 1.45, -.2), (-.12, 1.41, -.29), (.0, 1.39, -.3), (.11, 1.37, -.275),
             (.17, 1.32, -.22), (.15, 1.23, -.225), (.12, 1.12, -.215)], .021, "rubber", W_chain(("head", 1.55), ("chest", 1.36), ("hips", 1.12)), sides=8, pitch=.028, amp=.17, per=10)
    # second hose: from hero-right canister, arcs up around hood back? short loop down the chest diagonal to belt valve
    tub(mb, [(.165, 1.545, -.12), (.235, 1.5, -.12), (.25, 1.4, -.17), (.205, 1.28, -.215), (.16, 1.15, -.215), (.15, 1.09, -.2)],
        .019, "rubber", W_chain(("head", 1.55), ("chest", 1.36), ("hips", 1.12)), sides=8, pitch=.026, amp=.17, per=10)
    # diagonal gas hose with valve (centre chest to belt)
    tub(mb, [(-.02, 1.43, -.25), (-.05, 1.36, -.255), (-.1, 1.27, -.235), (-.13, 1.17, -.225), (-.13, 1.1, -.205)], .015, "metal",
        W_chain(("chest", 1.36), ("hips", 1.12)), sides=8, pitch=.02, amp=.15, per=8)
    cyl(mb, .02, .02, .05, (-.13, 1.17, -.23), "brass", S("chest"), rot=(0, 0, 0), seg=10)
    # ---------------- belt, pouches, canisters
    bl = [(.205, 1.0, 1, 0), (.205, 1.1, 1, 0)]
    lath(mb, [(.2, 1.0, 0, -1), (.208, 1.0, 1, 0), (.208, 1.1, 1, 0), (.2, 1.1, 0, 1)], (0, 0, 0), "webbing", S("hips"), scale=(1.32, 1, .93), seg=24)
    bx(mb, (.07, .07, .014), (0, 1.055, -.2), "metal", S("hips"), q=5)                 # buckle
    for sx in (-1, 1):
        ell(mb, (.03, .05, .03), (sx*.255, 1.05, -.0), "metal", S("hips"), seg=8, rings=5)
    # hero-right pouches (olive) + cylinder
    bx(mb, (.085, .115, .06), (.14, 1.02, -.185), "webbing", S("hips"), rot=(0, -12, 0), q=4)
    bx(mb, (.08, .105, .06), (.225, 1.0, -.125), "greenpatch", S("hips"), rot=(0, -60, 0), q=4, mode="native")
    bx(mb, (.1, .03, .066), (.14, 1.075, -.185), "webbing", S("hips"), rot=(0, -12, 0), q=4)
    cyl(mb, .03, .03, .15, (.075, 1.02, -.2), "silver", S("hips"), seg=12)
    cyl(mb, .033, .033, .016, (.075, 1.1, -.2), "brass", S("hips"), seg=12)
    cyl(mb, .012, .012, .04, (.075, 1.13, -.2), "metal", S("hips"), seg=8)
    # hero-left gas canisters
    for k, (cx, cz, h) in enumerate([(-.115, -.2, .17), (-.172, -.185, .19), (-.225, -.15, .17)]):
        cyl(mb, .031, .031, h, (cx, 1.0, cz), "silver" if k != 1 else "metal", S("hips"), rot=(0, 0, 0), seg=12)
        cyl(mb, .034, .034, .018, (cx, 1.0+h/2, cz), "brass" if k != 1 else "rubber", S("hips"), seg=12)
        cyl(mb, .011, .011, .045, (cx, 1.0+h/2+.03, cz), "metal", S("hips"), seg=8)
        cyl(mb, .034, .034, .014, (cx, 1.0-h/2+.012, cz), "rubber", S("hips"), seg=12)
    bx(mb, (.07, .1, .06), (-.265, .98, -.085), "webbing", S("hips"), rot=(0, 75, 0), q=4)
    bx(mb, (.12, .09, .06), (-.08, .99, .19), "webbing", S("hips"), q=4)
    # cables belt -> thigh loops (dark rubber)
    tub(mb, [(-.2, 1.04, -.17), (-.27, .98, -.16), (-.29, .88, -.13), (-.26, .84, -.12)], .008, "rubber", S("hips"), sides=6, per=8)
    tub(mb, [(.2, 1.04, -.17), (.285, .98, -.14), (.3, .9, -.1), (.27, .86, -.08)], .008, "rubber", S("hips"), sides=6, per=8)
    # cable from belt to gun (stretchy)
    tub(mb, [(.14, 1.06, -.19), (.22, 1.0, -.22), (.26, .92, -.24), (.26, .98, -.25)], .008, "rubber", W_aux("hips", "gun"), sides=6, per=8)
    # ---------------- legs + boots
    for sx, s in ((-1, "l"), (1, "r")):
        th, sh, ft = "thigh_"+s, "shin_"+s, "foot_"+s
        X = sx*.115
        leg = [(.0, .98, 0, 1), (.112, .97, .5, .7), (.122, .88, 1, .1), (.112, .72, 1, 0), (.1, .58, 1, -.1), (.092, .5, 1, -.05),
               (.092, .4, 1, 0), (.1, .28, 1, -.05), (.108, .2, 1, -.1)]
        lath(mb, leg, (X, 0, 0), "suit", W_chain(("hips", .96), (th, .86), (sh, .52), (ft, .12)), seg=16, scale=(1, 1, 1.02))
        # knee pad (grey) + thigh pocket patch
        bx(mb, (.105, .13, .028), (X, .53, -.1), "pad", S(sh), rot=(-6, 0, 0), q=3.5, mode="native")
        bx(mb, (.05, .1, .02), (X+sx*.004, .77, -.115), "pad", S(th), rot=(0, 0, 0), q=4, mode="native") if sx > 0 else None
        bx(mb, (.095, .13, .016), (X+sx*.05, .72, -.07), "pad", S(th), rot=(0, 25*sx, 0), q=4, mode="native") if sx < 0 else None
        # boot shaft (tall) + foot
        shaft = [(.098, .3, 0, 1), (.104, .29, 1, .2), (.106, .24, 1, 0), (.1, .12, 1, 0), (.098, .1, 0, -1)]
        lath(mb, shaft, (X, 0, 0), "boot", S(ft) if False else W_blend_y(sh, ft, .14, .3), seg=16, scale=(1, 1, 1.05))
        lath(mb, [(.107, .31, 0, 1), (.114, .305, 1, .5), (.116, .28, 1, -.3), (.106, .275, 0, -1)], (X, 0, 0), "rubber", W_blend_y(sh, ft, .14, .3), seg=16, scale=(1, 1, 1.05))  # boot cuff band
        ell(mb, (.09, .062, .175), (X, .065, -.065), "boot", S(ft), seg=16, rings=10, q=2.6)           # foot
        ell(mb, (.09, .05, .075), (X, .075, -.2), "boot", S(ft), seg=14, rings=8, q=2.4)               # toe cap
        bx(mb, (.178, .034, .35), (X, .017, -.075), "rubber", S(ft), q=3.2)                                      # sole
        bx(mb, (.15, .03, .06), (X, .03, .105), "rubber", S(ft), q=3)                                       # heel
        for k in range(3):
            bx(mb, (.19, .008, .02), (X, .05+k*.0, -.15+k*.07), "rubber", S(ft), q=4) if False else None
        for z in (-.01, .03):
            bx(mb, (.032, .012, .1), (X, .19+z*0, -.1), "webbing", S(sh), rot=(0, 0, 0), q=3) if False else None
        # laces/straps on boots
        bx(mb, (.19, .02, .035), (X, .22, -.02), "webbing", W_blend_y(sh, ft, .14, .3), q=4) if False else None
        lath(mb, [(.108, .205, 0, 1), (.112, .2, 1, 0), (.112, .185, 1, 0), (.108, .18, 0, -1)], (X, 0, 0), "webbing", W_blend_y(sh, ft, .14, .3), seg=16, scale=(1, 1, 1.05))
    # ---------------- gun (rigid on the gun bone)
    build_gun(mb, W_single("gun"), off=(.26, 1.0, -.28))
    return mb

# ---------------------------------------------------------------- first-person weapon + hands
def build_fps():
    mb = MeshBuilder(False)
    G = None
    build_gun(mb, G, off=(0, 0, 0))
    # right gloved fist at the pistol grip + yellow sleeve coming from lower right/back
    def hand(pos, sx):
        ell(mb, (.05, .06, .055), pos, "glove", G, seg=12, rings=8, q=2.8)
        for fi in range(4):
            ell(mb, (.012, .02, .02), (pos[0]-.05*0+ (fi-1.5)*0.0, pos[1]+.032-fi*.017, pos[2]-.055), "glove", G, seg=6, rings=4, rot=(0, 0, 0))
    hand((.0, -.07, .028), 1)
    # right forearm
    cyl(mb, .088, .082, .13, (.0, -.1, .125), "glove", G, rot=(-70, 0, 0), seg=12)
    cyl(mb, .064, .06, .55, (.04, -.255, .42), "suit", G, rot=(-62, 8, 0), seg=14)
    # left glove on the foregrip + forearm
    ell(mb, (.052, .06, .062), (-.002, -.085, -.255), "glove", G, seg=12, rings=8, q=2.8)
    cyl(mb, .085, .08, .14, (-.06, -.11, -.15), "glove", G, rot=(-70, -12, 0), seg=12)
    cyl(mb, .064, .06, .55, (-.17, -.235, .12), "suit", G, rot=(-62, -22, 0), seg=14)
    return mb

# ---------------------------------------------------------------- GLB writer
def write_glb(path, mb, skinned, name, textures=True):
    want_tex = textures
    P, N, UV, J, Wt, C = mb.arrays()
    alb, mr, em = TX.build_atlas(LAYOUT)
    if os.environ.get("HERO_ATLAS_PREVIEW"):
        alb.save("/tmp/hero_atlas.png")
    bin_chunks = []; views = []; accessors = []
    def add_view(data, target=None):
        pad = (-sum(len(b) for b in bin_chunks)) % 4
        if pad: bin_chunks.append(b"\0"*pad)
        off = sum(len(b) for b in bin_chunks)
        bin_chunks.append(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target: v["target"] = target
        views.append(v); return len(views)-1
    def add_acc(arr, ctype, typ, target=34962, minmax=False):
        data = arr.tobytes(); vi = add_view(data, target)
        a = {"bufferView": vi, "componentType": ctype, "count": int(len(arr)), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
        accessors.append(a); return len(accessors)-1
    attrs = {}
    attrs["POSITION"] = add_acc(P.astype(np.float32), 5126, "VEC3", minmax=True)
    attrs["NORMAL"] = add_acc(N.astype(np.float32), 5126, "VEC3")
    attrs["TEXCOORD_0"] = add_acc(UV.astype(np.float32), 5126, "VEC2")
    attrs["COLOR_0"] = add_acc(C.astype(np.float32), 5126, "VEC4")
    if skinned:
        attrs["JOINTS_0"] = add_acc(J.astype(np.uint16), 5123, "VEC4")
        attrs["WEIGHTS_0"] = add_acc(Wt.astype(np.float32), 5126, "VEC4")
    idx = np.arange(len(P), dtype=np.uint32)
    ia = add_acc(idx, 5125, "SCALAR", target=34963)
    images = []; textures = []
    def add_img(im):
        b = io.BytesIO(); im.save(b, "PNG", optimize=True)
        vi = add_view(b.getvalue()); images.append({"bufferView": vi, "mimeType": "image/png"})
        textures.append({"source": len(images)-1}); return len(textures)-1
    t_alb = t_mr = t_em = 0
    if want_tex:
        t_alb, t_mr, t_em = add_img(alb), add_img(mr), add_img(em)
    material = {"name": "HeroAtlas", "pbrMetallicRoughness": {"baseColorTexture": {"index": t_alb}, "metallicFactor": 1.0, "roughnessFactor": 1.0,
                "metallicRoughnessTexture": {"index": t_mr}}, "emissiveTexture": {"index": t_em}, "emissiveFactor": [0.55, 0.55, 0.55]}
    if not want_tex:
        material = {"name": "HeroAtlas", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}}
    nodes = []; gltf = {"asset": {"version": "2.0", "generator": "gen_hero.py"}}
    skins = []
    if skinned:
        # node 0 = scene root; bones follow, then mesh node
        nodes.append({"name": name, "children": []})
        for b in BONES:
            nodes.append({"name": b})
        for b in BONES:
            pos = np.array(REST[b]); par = PARENT.get(b)
            ppos = np.array(REST[par]) if par else np.zeros(3)
            nodes[1+BI[b]]["translation"] = (pos-ppos).tolist()
            if par: nodes[1+BI[par]].setdefault("children", []).append(1+BI[b])
        nodes[0]["children"] = [1+BI["root"]]
        ibm = np.zeros((len(BONES), 4, 4), np.float32)
        for b in BONES:
            m = np.eye(4); m[:3, 3] = -np.array(REST[b]); ibm[BI[b]] = m.T   # column-major
        ibm_acc = add_acc(ibm.reshape(-1, 16), 5126, "MAT4", target=None)
        skins.append({"inverseBindMatrices": ibm_acc, "joints": [1+BI[b] for b in BONES], "skeleton": 1+BI["root"]})
        nodes.append({"name": "HeroMesh", "mesh": 0, "skin": 0})
        nodes[0]["children"].append(len(nodes)-1)
    else:
        nodes.append({"name": name, "mesh": 0})
    gltf.update({"scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
                 "meshes": [{"name": name+"Mesh", "primitives": [{"attributes": attrs, "indices": ia, "material": 0}]}],
                 "materials": [material], **({"textures": textures, "images": images} if want_tex else {}), "accessors": accessors, "bufferViews": views})
    if skins: gltf["skins"] = skins
    bindata = b"".join(bin_chunks)
    bindata += b"\0"*((-len(bindata)) % 4)
    gltf["buffers"] = [{"byteLength": len(bindata)}]
    js = json.dumps(gltf).encode(); js += b" "*((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12+8+len(js)+8+len(bindata)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(bindata), 0x004E4942)); f.write(bindata)
    print(path, "tris:", len(P)//3, "verts:", len(P), "size KB:", os.path.getsize(path)//1024)
    # also store the albedo atlas (for inspection / docs)
    if textures: alb.resize((1024, 1024)).save(os.path.join(os.path.dirname(__file__), "hero_atlas_preview.png"))

if __name__ == "__main__":
    hero = build_hero()
    write_glb(os.path.join(OUT, "hero.glb"), hero, True, "Hero")
    fps = build_fps()
    write_glb(os.path.join(OUT, "hero_fps.glb"), fps, False, "HeroFps", textures=False)
