"""Procedural geometry kit for the hero (numpy). Used by gen_hero.py."""
import numpy as np

def rot_mat(rx=0, ry=0, rz=0):
    rx, ry, rz = np.radians([rx, ry, rz])
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    Rx = np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])
    Ry = np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])
    Rz = np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
    return Rz @ Ry @ Rx

def xf(pos=(0,0,0), rot=(0,0,0), scale=(1,1,1)):
    M = np.eye(4)
    M[:3,:3] = rot_mat(*rot) @ np.diag(scale)
    M[:3,3] = pos
    return M

def _norm(v):
    l = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(l, 1e-9)

def grid_faces(nu, nv, wrap_u=False):
    """faces for a (nv rows) x (nu cols) vertex grid; rows*cols index = r*nu + c (nu includes seam dup)."""
    F = []
    for r in range(nv - 1):
        for c in range(nu - 1):
            a = r*nu + c; b = a + 1; d = a + nu; e = d + 1
            F.append((a, d, b)); F.append((b, d, e))
    return np.array(F, dtype=np.int64)

def lathe(profile, seg=14):
    """profile: list of (r, y) or (r, y, nr, ny). Revolved about Y. uv native = (u around, v along profile)."""
    prof = [tuple(p) for p in profile]
    n = len(prof)
    R = np.array([p[0] for p in prof]); Y = np.array([p[1] for p in prof])
    NR = np.zeros(n); NY = np.zeros(n)
    for i, p in enumerate(prof):
        if len(p) == 4:
            NR[i], NY[i] = p[2], p[3]
        else:
            a = max(i-1, 0); b = min(i+1, n-1)
            tr, ty = R[b]-R[a], Y[b]-Y[a]
            NR[i], NY[i] = ty, -tr
            l = np.hypot(NR[i], NY[i]) or 1
            NR[i] /= l; NY[i] /= l
    th = np.linspace(0, 2*np.pi, seg+1)
    P = np.zeros((n, seg+1, 3)); N = np.zeros((n, seg+1, 3)); UV = np.zeros((n, seg+1, 2))
    for i in range(n):
        P[i,:,0] = R[i]*np.cos(th); P[i,:,2] = R[i]*np.sin(th); P[i,:,1] = Y[i]
        N[i,:,0] = NR[i]*np.cos(th); N[i,:,2] = NR[i]*np.sin(th); N[i,:,1] = NY[i]
        UV[i,:,0] = th/(2*np.pi); UV[i,:,1] = i/(n-1)
    return dict(P=P.reshape(-1,3), N=N.reshape(-1,3), UV=UV.reshape(-1,2), F=grid_faces(seg+1, n))

def sgnpow(x, p):
    return np.sign(x)*np.abs(x)**p

def superell(q=2.0, seg=16, rings=10, eps_pole=1e-3):
    """unit superellipsoid (implicit |x|^q+|y|^q+|z|^q=1). Y is the pole axis. uv = (u, v)."""
    e = 2.0/q
    v = np.linspace(-np.pi/2+eps_pole, np.pi/2-eps_pole, rings)
    u = np.linspace(0, 2*np.pi, seg+1)
    U, V = np.meshgrid(u, v)
    x = sgnpow(np.cos(V), e)*sgnpow(np.cos(U), e)
    z = sgnpow(np.cos(V), e)*sgnpow(np.sin(U), e)
    y = sgnpow(np.sin(V), e)
    P = np.stack([x,y,z], -1).reshape(-1,3)
    N = _norm(np.sign(P)*np.abs(P)**(q-1))
    UV = np.stack([U/(2*np.pi), (V+np.pi/2)/np.pi], -1).reshape(-1,2)
    return dict(P=P, N=N, UV=UV, F=grid_faces(seg+1, rings))

def box(sx=1, sy=1, sz=1):
    P=[];N=[];UV=[];F=[]
    faces = [((1,0,0),(0,0,-1),(0,1,0)), ((-1,0,0),(0,0,1),(0,1,0)),
             ((0,1,0),(1,0,0),(0,0,-1)), ((0,-1,0),(1,0,0),(0,0,1)),
             ((0,0,1),(1,0,0),(0,1,0)), ((0,0,-1),(-1,0,0),(0,1,0))]
    for n,a,b in faces:
        n=np.array(n,float);a=np.array(a,float);b=np.array(b,float)
        base=len(P)
        for (ua,ub) in [(-1,-1),(1,-1),(-1,1),(1,1)]:
            P.append((n+ua*a+ub*b)*0.5*np.array([sx,sy,sz]))
            N.append(n); UV.append(((ua+1)/2,(ub+1)/2))
        F += [(base,base+1,base+2),(base+1,base+3,base+2)]
    return dict(P=np.array(P),N=np.array(N),UV=np.array(UV),F=np.array(F))

def torus(R=1.0, r=0.2, seg=16, sides=8):
    """ring around Y axis (axis of hole = Y)."""
    u = np.linspace(0, 2*np.pi, seg+1); v = np.linspace(0, 2*np.pi, sides+1)
    U, V = np.meshgrid(u, v)
    x = (R + r*np.cos(V))*np.cos(U); z = (R + r*np.cos(V))*np.sin(U); y = r*np.sin(V)
    nx = np.cos(V)*np.cos(U); nz = np.cos(V)*np.sin(U); ny = np.sin(V)
    return dict(P=np.stack([x,y,z],-1).reshape(-1,3), N=np.stack([nx,ny,nz],-1).reshape(-1,3),
                UV=np.stack([U/(2*np.pi),V/(2*np.pi)],-1).reshape(-1,2), F=grid_faces(seg+1, sides+1))

def catmull(pts, per=8):
    pts = np.array(pts, float)
    p = np.vstack([2*pts[0]-pts[1], pts, 2*pts[-1]-pts[-2]])
    out = []
    for i in range(1, len(p)-2):
        p0,p1,p2,p3 = p[i-1],p[i],p[i+1],p[i+2]
        for t in np.linspace(0,1,per,endpoint=False):
            out.append(0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t**3))
    out.append(p[-2])
    return np.array(out)

def tube(pts, radius, sides=8, pitch=0.0, amp=0.0, per=8, end_taper=False):
    C = catmull(pts, per)
    n = len(C)
    T = np.zeros_like(C)
    T[1:-1] = C[2:]-C[:-2]; T[0] = C[1]-C[0]; T[-1] = C[-1]-C[-2]
    T = _norm(T)
    seglen = np.linalg.norm(np.diff(C,axis=0),axis=1)
    s = np.concatenate([[0], np.cumsum(seglen)])
    ref = np.array([0,1,0.0]) if abs(T[0][1])<0.9 else np.array([1,0,0.0])
    nrm = _norm(np.cross(T[0], ref)); nrm = _norm(np.cross(nrm, T[0])*0 + np.cross(T[0], np.cross(ref, T[0])))
    Ns = []
    for i in range(n):
        nrm = nrm - np.dot(nrm, T[i])*T[i]; nrm = nrm/np.linalg.norm(nrm); Ns.append(nrm.copy())
    Ns = np.array(Ns); Bs = np.cross(T, Ns)
    th = np.linspace(0, 2*np.pi, sides+1)
    rad = radius*(1 + (amp*np.cos(2*np.pi*s/pitch) if pitch > 0 else 0))
    if np.isscalar(rad): rad = np.full(n, rad)
    drds = np.gradient(rad, s) if n > 2 else np.zeros(n)
    P = np.zeros((n, sides+1, 3)); N = np.zeros_like(P); UV = np.zeros((n, sides+1, 2)); aux = np.zeros((n, sides+1))
    for i in range(n):
        rd = np.cos(th)[:,None]*Ns[i] + np.sin(th)[:,None]*Bs[i]
        P[i] = C[i] + rd*rad[i]
        N[i] = _norm(rd - drds[i]*T[i])
        UV[i,:,0] = th/(2*np.pi); UV[i,:,1] = s[i]
        aux[i,:] = i/(n-1)
    return dict(P=P.reshape(-1,3), N=N.reshape(-1,3), UV=UV.reshape(-1,2), F=grid_faces(sides+1, n), aux=aux.reshape(-1))
