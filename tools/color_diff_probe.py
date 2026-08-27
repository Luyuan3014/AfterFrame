"""Compare the source frame with the exported Live cover to classify the colour shift."""

import sys

import numpy as np
from PIL import Image

A = sys.argv[1]
B = sys.argv[2]


def load(path):
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(np.float64), img.size


a, sa = load(A)
b, sb = load(B)
print("size", sa, sb)

if sa != sb:
    b = np.asarray(Image.open(B).convert("RGB").resize(sa, Image.LANCZOS)).astype(np.float64)


def content_rows(arr):
    lum = arr.mean(axis=(1, 2))
    rows = np.where(lum > 8)[0]
    return rows.min(), rows.max()


ra = content_rows(a)
rb = content_rows(b)
print("content rows", ra, rb)

top = max(ra[0], rb[0]) + 4
bottom = min(ra[1], rb[1]) - 4
ca = a[top:bottom]
cb = b[top:bottom]
print("compare band rows", top, bottom, ca.shape)

print("\n--- global channel means ---")
for i, ch in enumerate("RGB"):
    print(f"{ch}: src={ca[:,:,i].mean():7.2f}  exp={cb[:,:,i].mean():7.2f}  delta={cb[:,:,i].mean()-ca[:,:,i].mean():+7.2f}")

print("\n--- global channel std ---")
for i, ch in enumerate("RGB"):
    print(f"{ch}: src={ca[:,:,i].std():7.2f}  exp={cb[:,:,i].std():7.2f}")


def to_ycbcr(arr):
    r, g, bl = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    y = 0.299 * r + 0.587 * g + 0.114 * bl
    cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * bl
    cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * bl
    return y, cb, cr


ya, cba, cra = to_ycbcr(ca)
yb, cbb, crb = to_ycbcr(cb)
print("\n--- YCbCr means ---")
print(f"Y : src={ya.mean():7.2f} exp={yb.mean():7.2f} delta={yb.mean()-ya.mean():+7.2f}")
print(f"Cb: src={cba.mean():7.2f} exp={cbb.mean():7.2f} delta={cbb.mean()-cba.mean():+7.2f}")
print(f"Cr: src={cra.mean():7.2f} exp={crb.mean():7.2f} delta={crb.mean()-cra.mean():+7.2f}")

print("\n--- chroma spread (saturation proxy) ---")
sat_a = np.hypot(cba - 128, cra - 128)
sat_b = np.hypot(cbb - 128, crb - 128)
print(f"mean chroma radius: src={sat_a.mean():6.2f} exp={sat_b.mean():6.2f} ratio={sat_b.mean()/max(sat_a.mean(),1e-6):.3f}")
print(f"p99 chroma radius : src={np.percentile(sat_a,99):6.2f} exp={np.percentile(sat_b,99):6.2f}")

print("\n--- luma range (studio vs full swing) ---")
for name, y in (("src", ya), ("exp", yb)):
    print(f"{name}: min={y.min():6.2f} p0.1={np.percentile(y,0.1):6.2f} p99.9={np.percentile(y,99.9):6.2f} max={y.max():6.2f}")

print("\n--- per-luma-bucket channel delta (detects gamma vs gain vs range) ---")
buckets = [(0, 40), (40, 80), (80, 120), (120, 160), (160, 200), (200, 256)]
for lo, hi in buckets:
    m = (ya >= lo) & (ya < hi)
    if m.sum() < 200:
        continue
    dr = cb[:, :, 0][m].mean() - ca[:, :, 0][m].mean()
    dg = cb[:, :, 1][m].mean() - ca[:, :, 1][m].mean()
    db = cb[:, :, 2][m].mean() - ca[:, :, 2][m].mean()
    dy = yb[m].mean() - ya[m].mean()
    print(f"Y[{lo:3d},{hi:3d}) n={m.sum():7d}  dY={dy:+6.2f}  dR={dr:+6.2f} dG={dg:+6.2f} dB={db:+6.2f}")

print("\n--- local chroma noise (high-freq Cb/Cr energy) ---")
def hf(x):
    return np.abs(x[1:-1, 1:-1] - 0.25 * (x[:-2, 1:-1] + x[2:, 1:-1] + x[1:-1, :-2] + x[1:-1, 2:]))


print(f"Cb hf: src={hf(cba).mean():6.3f} exp={hf(cbb).mean():6.3f}")
print(f"Cr hf: src={hf(cra).mean():6.3f} exp={hf(crb).mean():6.3f}")
print(f"Y  hf: src={hf(ya).mean():6.3f} exp={hf(yb).mean():6.3f}")
