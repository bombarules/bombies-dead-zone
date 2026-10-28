"""Procedural texture atlas for the hero: albedo, metal/rough, emission (all share one layout)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ATLAS = 2048
def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1); return t*t*(3-2*t)

def fnoise(n, beta, seed, aniso=(1.0, 1.0)):
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.normal(size=(n, n)))
    fy = np.fft.fftfreq(n)[:, None]*n; fx = np.fft.fftfreq(n)[None, :]*n
    f = np.sqrt((fx*aniso[0])**2 + (fy*aniso[1])**2); f[0, 0] = 1
    img = np.real(np.fft.ifft2(F / f**beta))
    img = (img - img.min())/(img.max()-img.min())
    # contrast-normalise around the mean using std
    m, s = img.mean(), img.std()
    return np.clip(0.5 + (img-m)/(s*6), 0, 1)

def mix(base, col, amt):
    return base*(1-amt[..., None]) + np.array(col, float)*amt[..., None]

def scratches(img, n, seed, col, alpha, length=(10, 60), width=1):
    """img: float array (T,T,3); draws wrapped light scratches"""
    T = img.shape[0]; rng = np.random.default_rng(seed)
    layer = Image.new("L", (T, T), 0); d = ImageDraw.Draw(layer)
    for _ in range(n):
        x, y = rng.uniform(0, T, 2); a = rng.uniform(0, np.pi*2); L = rng.uniform(*length)
        dx, dy = np.cos(a)*L, np.sin(a)*L
        for ox in (-T, 0, T):
            for oy in (-T, 0, T):
                d.line([(x+ox, y+oy), (x+dx+ox, y+dy+oy)], fill=int(255*rng.uniform(.4, 1)), width=width)
    m = np.asarray(layer, float)/255*alpha
    return mix(img, col, m)

def specks(img, n, seed, col, rmax=2.5, alpha=0.9):
    T = img.shape[0]; rng = np.random.default_rng(seed)
    layer = Image.new("L", (T, T), 0); d = ImageDraw.Draw(layer)
    for _ in range(n):
        x, y = rng.uniform(0, T, 2); r = rng.uniform(0.6, rmax)
        for ox in (-T, 0, T):
            for oy in (-T, 0, T):
                d.ellipse([x-r+ox, y-r+oy, x+r+ox, y+r+oy], fill=255)
    m = np.asarray(layer, float)/255*alpha
    return mix(img, col, m)

def finish(img):
    return np.clip(img, 0, 255)

# ---- tileable regions ------------------------------------------------------
def tex_suit(T):
    base = np.array([186, 142, 22], float)
    low = fnoise(T, 2.0, 1); mid = fnoise(T, 1.4, 2); hi = fnoise(T, 0.6, 3)
    img = np.ones((T, T, 3))*base*(0.80 + 0.35*low)[..., None]
    img *= (0.94 + 0.12*hi)[..., None]
    # sun-bleached / lighter worn areas
    img = mix(img, (228, 190, 60), smooth(0.66, 0.8, fnoise(T, 2.3, 4))*0.5)
    # dark brownish stains
    img = mix(img, (96, 68, 18), smooth(0.58, 0.72, fnoise(T, 1.7, 5))*0.8)
    img = mix(img, (70, 50, 18), smooth(0.62, 0.74, fnoise(T, 1.3, 15))*0.55)
    img = mix(img, (40, 32, 20), smooth(0.68, 0.78, fnoise(T, 1.9, 6))*0.88)
    # dripping streaks
    st = fnoise(T, 1.6, 7, aniso=(1.0, 5.0))
    img = mix(img, (120, 70, 22), smooth(0.64, 0.80, st)*0.55)
    st2 = fnoise(T, 1.4, 8, aniso=(1.0, 7.0))
    img = mix(img, (60, 44, 20), smooth(0.70, 0.84, st2)*0.5)
    # fabric creases
    cr = np.abs(fnoise(T, 1.8, 9) - 0.5)
    img *= (1 - 0.28*smooth(0.03, 0.0, cr))[..., None]
    cr2 = np.abs(fnoise(T, 1.5, 10, aniso=(3, 1)) - 0.5)
    img *= (1 - 0.22*smooth(0.025, 0.0, cr2))[..., None]
    img = specks(img, int(T*0.45), 11, (34, 28, 18), 1.8, 0.8)
    img = specks(img, int(T*0.6), 12, (240, 205, 90), 1.6, 0.5)
    img = scratches(img, int(T*0.25), 13, (236, 205, 105), 0.55, (8, 50))
    img = scratches(img, int(T*0.08), 14, (30, 26, 18), 0.6, (20, 90))
    return finish(img)

def tex_boot(T):
    low = fnoise(T, 2.0, 21); hi = fnoise(T, 0.7, 22)
    img = np.ones((T, T, 3))*np.array([66, 45, 28])*(0.7 + 0.6*low)[..., None]
    img *= (0.9 + 0.2*hi)[..., None]
    img = mix(img, (108, 86, 58), smooth(0.58, 0.75, fnoise(T, 2.3, 23))*0.65)
    img = mix(img, (22, 18, 14), smooth(0.62, 0.78, fnoise(T, 2.1, 24))*0.8)
    cr = np.abs(fnoise(T, 1.6, 25, aniso=(1, 2.5)) - 0.5)
    img *= (1 - 0.35*smooth(0.03, 0.0, cr))[..., None]
    img = scratches(img, int(T*0.3), 26, (150, 110, 70), 0.6, (6, 40))
    return finish(img)

def tex_glove(T):
    low = fnoise(T, 2.0, 31); hi = fnoise(T, 0.6, 32)
    img = np.ones((T, T, 3))*np.array([62, 62, 58])*(0.75 + 0.5*low)[..., None]
    img *= (0.9 + 0.2*hi)[..., None]
    img = mix(img, (112, 110, 100), smooth(0.62, 0.78, fnoise(T, 2.3, 33))*0.6)
    img = mix(img, (20, 20, 18), smooth(0.62, 0.78, fnoise(T, 2.1, 34))*0.7)
    cr = np.abs(fnoise(T, 1.6, 35) - 0.5)
    img *= (1 - 0.3*smooth(0.03, 0.0, cr))[..., None]
    img = scratches(img, int(T*0.25), 36, (150, 148, 138), 0.55, (6, 36))
    return finish(img)

def tex_rubber(T):
    low = fnoise(T, 2.0, 41); hi = fnoise(T, 0.5, 42)
    img = np.ones((T, T, 3))*np.array([30, 30, 29])*(0.7 + 0.7*low)[..., None]
    img *= (0.85 + 0.3*hi)[..., None]
    img = mix(img, (70, 70, 66), smooth(0.66, 0.8, fnoise(T, 2.3, 43))*0.5)
    img = specks(img, int(T*0.5), 44, (90, 90, 84), 1.5, 0.5)
    return finish(img)

def tex_metal(T):
    low = fnoise(T, 2.0, 51); hi = fnoise(T, 0.5, 52)
    img = np.ones((T, T, 3))*np.array([70, 73, 74])*(0.75 + 0.5*low)[..., None]
    img *= (0.88 + 0.24*hi)[..., None]
    img = mix(img, (104, 66, 40), smooth(0.64, 0.76, fnoise(T, 2.4, 53))*0.4)  # rust
    img = mix(img, (24, 24, 24), smooth(0.64, 0.78, fnoise(T, 2.2, 54))*0.6)
    img = scratches(img, int(T*0.35), 55, (178, 180, 178), 0.65, (6, 45))
    return finish(img)

def tex_silver(T):
    low = fnoise(T, 2.0, 61); hi = fnoise(T, 0.5, 62)
    img = np.ones((T, T, 3))*np.array([158, 160, 156])*(0.7 + 0.5*low)[..., None]
    img *= (0.9 + 0.2*hi)[..., None]
    img = mix(img, (70, 60, 44), smooth(0.58, 0.72, fnoise(T, 2.3, 63))*0.7)
    img = mix(img, (125, 70, 36), smooth(0.70, 0.8, fnoise(T, 2.5, 64))*0.6)
    img = scratches(img, int(T*0.3), 65, (225, 225, 220), 0.6, (6, 40))
    return finish(img)

def tex_webbing(T):
    low = fnoise(T, 2.0, 71)
    yy, xx = np.mgrid[0:T, 0:T]
    weave = 0.5 + 0.25*np.sin(xx*2*np.pi/6) + 0.25*np.sin(yy*2*np.pi/6)
    img = np.ones((T, T, 3))*np.array([94, 86, 58])*(0.7 + 0.5*low)[..., None]
    img *= (0.88 + 0.2*weave)[..., None]
    img = mix(img, (40, 34, 24), smooth(0.58, 0.74, fnoise(T, 2.2, 72))*0.7)
    img = mix(img, (122, 108, 74), smooth(0.66, 0.8, fnoise(T, 2.3, 73))*0.4)
    img = scratches(img, int(T*0.12), 74, (140, 130, 100), 0.4, (6, 30))
    return finish(img)

def tex_tape(T):
    low = fnoise(T, 2.0, 81)
    yy, xx = np.mgrid[0:T, 0:T]
    img = np.ones((T, T, 3))*np.array([156, 158, 154])*(0.72 + 0.4*low)[..., None]
    img *= (0.94 + 0.06*np.sin(xx*2*np.pi/9))[..., None]
    img = mix(img, (70, 64, 52), smooth(0.58, 0.72, fnoise(T, 2.3, 82))*0.65)
    cr = np.abs(fnoise(T, 1.5, 83, aniso=(1, 4)) - 0.5)
    img *= (1 - 0.3*smooth(0.04, 0.0, cr))[..., None]
    img = scratches(img, int(T*0.15), 84, (60, 56, 48), 0.5, (6, 36))
    return finish(img)

def tex_brass(T):
    low = fnoise(T, 2.0, 91)
    img = np.ones((T, T, 3))*np.array([158, 112, 42])*(0.7 + 0.55*low)[..., None]
    img = mix(img, (50, 40, 24), smooth(0.58, 0.74, fnoise(T, 2.2, 92))*0.7)
    img = scratches(img, int(T*0.2), 93, (220, 180, 100), 0.5, (6, 36))
    return finish(img)

# ---- native-UV regions (drawn once, not tiled) ------------------------------
def tex_pad(T):
    low = fnoise(T, 2.0, 101); hi = fnoise(T, 0.5, 102)
    img = np.ones((T, T, 3))*np.array([112, 116, 106])*(0.68 + 0.55*low)[..., None]
    img *= (0.9 + 0.2*hi)[..., None]
    img = mix(img, (50, 46, 38), smooth(0.58, 0.72, fnoise(T, 2.3, 103))*0.7)
    img = mix(img, (150, 152, 140), smooth(0.68, 0.8, fnoise(T, 2.3, 104))*0.4)
    cr = np.abs(fnoise(T, 1.6, 105) - 0.5)
    img *= (1 - 0.25*smooth(0.03, 0.0, cr))[..., None]
    img = scratches(img, int(T*0.25), 106, (188, 190, 180), 0.5, (6, 40))
    im = Image.fromarray(finish(img).astype(np.uint8)); d = ImageDraw.Draw(im)
    m = int(T*0.07)
    for x in range(m, T-m, 14):
        d.line([(x, m), (x+7, m)], fill=(36, 33, 26), width=2)
        d.line([(x, T-m), (x+7, T-m)], fill=(36, 33, 26), width=2)
    for y in range(m, T-m, 14):
        d.line([(m, y), (m, y+7)], fill=(36, 33, 26), width=2)
        d.line([(T-m, y), (T-m, y+7)], fill=(36, 33, 26), width=2)
    d.rectangle([0, 0, T-1, T-1], outline=(40, 38, 30), width=3)
    return np.asarray(im, float)

def tex_greenpatch(T):
    low = fnoise(T, 2.0, 111)
    yy, xx = np.mgrid[0:T, 0:T]
    img = np.ones((T, T, 3))*np.array([78, 96, 54])*(0.72 + 0.5*low)[..., None]
    img *= (0.9 + 0.1*np.sin(xx*2*np.pi/7)*np.sin(yy*2*np.pi/7))[..., None]
    img = mix(img, (34, 30, 20), smooth(0.58, 0.72, fnoise(T, 2.3, 112))*0.65)
    img = scratches(img, int(T*0.12), 113, (150, 160, 110), 0.4, (6, 30))
    im = Image.fromarray(finish(img).astype(np.uint8)); d = ImageDraw.Draw(im)
    for k in (0.3, 0.5, 0.7):
        d.line([(int(T*0.1), int(T*k)), (int(T*0.9), int(T*k))], fill=(40, 52, 30), width=3)
    m = int(T*0.06)
    d.rectangle([m, m, T-m, T-m], outline=(30, 34, 22), width=3)
    d.rectangle([0, 0, T-1, T-1], outline=(36, 34, 24), width=3)
    return np.asarray(im, float)

def tex_visor(T):
    yy, xx = np.mgrid[0:T, 0:T]
    u = (xx/T - 0.5)*2; v = (yy/T - 0.5)*2
    r = np.sqrt(u*u + v*v)
    glow = np.clip(1 - r*0.9, 0, 1)
    img = np.zeros((T, T, 3))
    img[..., 0] = 10 + 70*glow**1.5; img[..., 1] = 70 + 150*glow; img[..., 2] = 30 + 70*glow**1.6
    # face silhouette
    face = smooth(1.0, 0.85, np.sqrt((u/0.55)**2 + ((v+0.02)/0.78)**2))
    img = mix(img, (30, 120, 48), face*0.55)
    for ex in (-0.22, 0.22):
        eye = smooth(1.0, 0.5, np.sqrt(((u-ex)/0.16)**2 + ((v+0.16)/0.07)**2))
        img = mix(img, (8, 50, 18), eye*0.85)
    nose = smooth(1.0, 0.4, np.sqrt((u/0.07)**2 + ((v-0.05)/0.2)**2))
    img = mix(img, (20, 85, 34), nose*0.6)
    mouth = smooth(1.0, 0.4, np.sqrt((u/0.22)**2 + ((v-0.36)/0.04)**2))
    img = mix(img, (10, 55, 20), mouth*0.7)
    # reflection streak + dirt rim
    refl = smooth(0.12, 0.0, np.abs((u*0.7 + v) + 0.35))*smooth(1.0, 0.6, r)
    img = mix(img, (210, 255, 215), refl*0.45)
    img = mix(img, (6, 36, 14), smooth(0.78, 1.0, r)*0.8)
    img = scratches(img, 30, 121, (190, 255, 190), 0.4, (10, 50))
    return finish(img)

def tex_misc(T):
    img = np.zeros((T, T, 3)); h = T//2
    img[:h, :h] = (176, 30, 24); img[:h, h:] = (70, 255, 110)
    img[h:, :h] = (255, 150, 30); img[h:, h:] = (22, 22, 24)
    return img

def paste(atlas, tile, rect, g, tiled):
    x0, y0, w, h = rect
    if tiled:
        t = np.pad(tile, ((g, g), (g, g), (0, 0)), mode="wrap")
    else:
        t = np.pad(tile, ((g, g), (g, g), (0, 0)), mode="edge")
    atlas[y0:y0+h, x0:x0+w] = t[:h, :w]

# name -> (cell rect px, tile px, gutter px, tiled?, tile_meters, builder, rough, metal)
def layout():
    L = {}
    L["suit"] = dict(rect=(0, 0, 1120, 1120), T=960, g=80, tiled=True, meters=1.2, fn=tex_suit, rough=0.86, metal=0.0)
    cells = [(1120, 0), (1568, 0), (1120, 448), (1568, 448), (1120, 896), (1568, 896), (1120, 1344), (1568, 1344),
             (0, 1120), (448, 1120), (0, 1568), (448, 1568)]
    spec = [("boot", tex_boot, True, 0.6, .82, 0.0), ("glove", tex_glove, True, 0.45, .72, 0.0),
            ("rubber", tex_rubber, True, 0.45, .55, 0.0), ("metal", tex_metal, True, 0.5, .45, 0.7),
            ("silver", tex_silver, True, 0.5, .32, 0.85), ("webbing", tex_webbing, True, 0.4, .95, 0.0),
            ("tape", tex_tape, True, 0.4, .5, 0.2), ("brass", tex_brass, True, 0.4, .4, 0.8),
            ("pad", tex_pad, False, 1, .85, 0.0), ("greenpatch", tex_greenpatch, False, 1, .9, 0.0),
            ("visor", tex_visor, False, 1, .06, 0.0), ("misc", tex_misc, False, 1, .5, 0.1)]
    for (x, y), (name, fn, tiled, meters, ro, me) in zip(cells, spec):
        g = 48 if tiled else 8
        L[name] = dict(rect=(x, y, 448, 448), T=448-2*g, g=g, tiled=tiled, meters=meters, fn=fn, rough=ro, metal=me)
    return L

def build_atlas(L):
    alb = np.zeros((ATLAS, ATLAS, 3)); mr = np.zeros((ATLAS, ATLAS, 3)); em = np.zeros((ATLAS, ATLAS, 3))
    alb[:] = (60, 60, 58); mr[:] = (255, 200, 0)
    for name, s in L.items():
        tile = s["fn"](s["T"])
        paste(alb, tile, s["rect"], s["g"], s["tiled"])
        x0, y0, w, h = s["rect"]
        mr[y0:y0+h, x0:x0+w] = (255, s["rough"]*255, s["metal"]*255)
        if name == "visor":
            em[y0:y0+h, x0:x0+w] = alb[y0:y0+h, x0:x0+w]*0.95
        if name == "misc":
            hh = 224
            em[y0:y0+hh, x0+hh:x0+w] = alb[y0:y0+hh, x0+hh:x0+w]*0.9          # green LED
            em[y0+hh:y0+h, x0:x0+hh] = alb[y0+hh:y0+h, x0:x0+hh]*0.9           # orange LED
    # bake some roughness variation from albedo luminance for wear (brighter = shinier scuff)
    lum = alb.mean(-1)/255
    mr[..., 1] = np.clip(mr[..., 1]*(1.1 - 0.35*lum), 0, 255)
    f = lambda a: Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return f(alb), f(mr), f(em)
