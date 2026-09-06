#!/usr/bin/env python3
"""Deterministic Effy atlas exporter.

Uses only the locked atlas pixels. Pillow is intentionally required for the
pixel-preserving crop, alpha normalization, GIF/APNG previews, and contact
sheet output. Install Pillow in the local project environment, then run this
file from the repository root.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is required: python3 -m pip install pillow", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "PetAssets/Source/effy-production-atlas-v1.png"
SOURCE_META = ROOT / "PetAssets/Source/effy-production-atlas-v1.json"
OUT = ROOT / "PetAssets/Production"
PREVIEWS = ROOT / "PetAssets/Previews"
CANVAS = (512, 512)

# Explicit atlas rectangles (x, y, width, height), measured against the
# locked 1401x1123 atlas. These are intentionally data, not grid inference.
ROWS = {
    "idle": ([(55,0,126,155),(230,0,126,155),(404,0,130,155),(585,0,128,155),(760,0,129,155),(931,0,125,155),(1109,0,126,155)], 140),
    "blink": ([(54,145,126,155),(221,145,125,155),(382,145,127,155),(545,145,126,155),(707,145,123,155)], 140),
    "click": ([(51,270,126,155),(217,270,126,155),(381,270,130,155),(550,270,125,155),(706,270,125,155),(868,270,127,155),(1040,270,125,155),(1207,270,138,155)], 140),
    "thinking": ([(48,405,121,155),(185,405,120,155),(325,405,120,155),(465,405,120,155),(600,405,113,155),(733,405,120,155),(868,405,128,155),(1003,405,115,155),(1128,405,120,155),(1260,405,116,155)], 140),
    "replying": ([(52,545,124,135),(222,545,122,135),(399,545,122,135),(563,545,132,135),(740,545,132,135),(912,545,123,135),(1081,545,122,135)], 140),
    "answerStart": ([(51,630,123,190),(223,630,123,190),(386,630,120,190),(549,630,121,190),(711,630,124,190),(877,630,122,190)], 140),
    "answerComplete": ([(50,765,125,190),(220,765,128,190),(387,765,124,190),(551,765,127,190),(715,765,124,190),(874,765,148,190)], 140),
    "error": ([(45,900,132,205),(207,900,124,205),(369,900,130,205),(532,900,142,205),(696,900,137,205),(862,900,160,205),(1056,900,152,205),(1234,900,127,205)], 140),
}

def metadata():
    return {"atlas": str(ATLAS.relative_to(ROOT)), "canvas": list(CANVAS), "anchor": [256, 432], "states": {k: [{"x":x,"y":y,"width":w,"height":h} for x,y,w,h in v[0]] for k,v in ROWS.items()}}

def save_json():
    SOURCE_META.write_text(json.dumps(metadata(), indent=2) + "\n")

def export_frame(atlas, rect, state, index):
    x,y,w,h = rect
    crop = atlas.crop((x,y,x+w,y+h)).convert("RGBA")
    alpha = crop.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise ValueError(f"empty frame: {state} {index}")
    crop = crop.crop((max(0,bbox[0]-4), max(0,bbox[1]-4), min(crop.width,bbox[2]+4), min(crop.height,bbox[3]+4)))
    # Remove isolated neighboring-frame fragments introduced by the atlas
    # overlap. Keep the main character plus nearby sparkles/question marks.
    mask = crop.getchannel("A")
    seen = set(); components = []
    for yy in range(mask.height):
        for xx in range(mask.width):
            if mask.getpixel((xx,yy)) <= 20 or (xx,yy) in seen: continue
            stack=[(xx,yy)]; seen.add((xx,yy)); pts=[]
            while stack:
                qx,qy=stack.pop(); pts.append((qx,qy))
                for nx,ny in ((qx+1,qy),(qx-1,qy),(qx,qy+1),(qx,qy-1)):
                    if 0<=nx<mask.width and 0<=ny<mask.height and (nx,ny) not in seen and mask.getpixel((nx,ny))>20:
                        seen.add((nx,ny)); stack.append((nx,ny))
            components.append(pts)
    if components:
        main = max(components, key=len); mx0=min(p[0] for p in main); mx1=max(p[0] for p in main); my0=min(p[1] for p in main); my1=max(p[1] for p in main)
        keep=set(main)
        for pts in components:
            if pts is main: continue
            x0=min(p[0] for p in pts); x1=max(p[0] for p in pts); y0=min(p[1] for p in pts); y1=max(p[1] for p in pts)
            near = not (x1 < mx0-45 or x0 > mx1+45 or y1 < my0-45 or y0 > my1+45)
            # No frame has a baked floor shadow. Anything entirely below the
            # character's main component is therefore an atlas neighbor and
            # must be discarded, regardless of its component size.
            top_neighbor = y1 < my0 and (x1 - x0 > 35) and (y1 - y0 < 60)
            if near and y0 <= my1 and not top_neighbor and not (state == "click" and y1 < my0 and len(pts) < 200): keep.update(pts)
        cleaned=Image.new("RGBA", crop.size, (0,0,0,0)); src=crop.load(); dst=cleaned.load()
        for qx,qy in keep: dst[qx,qy]=src[qx,qy]
        crop=cleaned
    scale = min(430 / crop.width, 430 / crop.height)
    crop = crop.resize((round(crop.width*scale), round(crop.height*scale)), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", CANVAS, (0,0,0,0))
    frame.alpha_composite(crop, ((CANVAS[0]-crop.width)//2, CANVAS[1]-crop.height-42))
    folder = OUT / (state[0].upper() + state[1:])
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{state.lower()}_{index:03d}.png"
    frame.save(path)
    return frame

def durations(state, count):
    presets = {"idle": [360,360,360,440,360,360,440], "blink":[90,90,130,90,160], "click":[110]*8, "thinking":[280]*10, "replying":[240]*7, "answerStart":[130]*6, "answerComplete":[200]*6, "error":[260]*8}
    return presets[state][:count]

def smooth_sequence(frames, state, loop):
    """Return crisp approved keyframes; never cross-fade raster poses.

    Cross-fading produces a visible double-image because the source atlas is
    raster art with no landmark correspondence. Until a vector/mesh source is
    available, crisp holds are preferable to invented blurry in-betweens.
    """
    return list(frames)

def main():
    if not ATLAS.exists(): raise SystemExit(f"missing atlas: {ATLAS}")
    atlas = Image.open(ATLAS).convert("RGBA")
    # The approved atlas preview contains a baked checkerboard. Remove only
    # neutral, high-value checkerboard pixels; pink artwork/highlights remain.
    px = atlas.load()
    for y in range(atlas.height):
        for x in range(atlas.width):
            r,g,b,a = px[x,y]
            if max(r,g,b) - min(r,g,b) < 16 and min(r,g,b) > 180:
                px[x,y] = (r,g,b,0)
    save_json()
    report = []
    for state, (rects, _) in ROWS.items():
        frames = [export_frame(atlas, r, state, i) for i,r in enumerate(rects)]
        state_dir = OUT / (state[0].upper() + state[1:])
        state_dir.mkdir(parents=True, exist_ok=True)
        looping = state in {"idle","thinking","replying"}
        preview_frames = smooth_sequence(frames, state, looping)
        smooth_duration = max(70, round(sum(durations(state,len(frames))) / len(preview_frames)))
        preview_frames[0].save(PREVIEWS / f"effy-{state.lower()}-v1.gif", save_all=True, append_images=preview_frames[1:], duration=smooth_duration, loop=0 if looping else 1, disposal=2, transparency=0)
        preview_frames[0].save(PREVIEWS / f"effy-{state.lower()}-v1.apng", save_all=True, append_images=preview_frames[1:], duration=smooth_duration, loop=0 if looping else 1, disposal=2)
        small = [f.resize((64,64), Image.Resampling.LANCZOS) for f in preview_frames]
        small[0].save(PREVIEWS / f"effy-{state.lower()}-64px-v1.gif", save_all=True, append_images=small[1:], duration=smooth_duration, loop=0 if looping else 1, disposal=2, transparency=0)
        report.append({"state":state,"frames":len(frames),"durationsMs":durations(state,len(frames)),"loop":state in {"idle","thinking","replying"}})
    # Technical contact sheet from the exact exported PNGs.
    sheet = Image.new("RGBA", (1500, 8 * 155), (250, 247, 249, 255))
    draw = ImageDraw.Draw(sheet)
    for row, item in enumerate(report):
        state = item["state"]; folder = OUT / (state[0].upper() + state[1:])
        files = sorted(folder.glob("*.png")); y = row * 155
        draw.text((12, y + 8), f"{state.upper()}  ({len(files)} frames, {'LOOP' if item['loop'] else 'ONE-SHOT'})", fill=(92, 20, 55, 255))
        for i, path in enumerate(files):
            im = Image.open(path).convert("RGBA").resize((112,112), Image.Resampling.LANCZOS)
            x = 250 + i * 118
            if x + 112 > sheet.width: break
            sheet.alpha_composite(im, (x, y + 28)); draw.text((x + 48, y + 141), f"{i:03d}", fill=(92,20,55,255))
    sheet.save(PREVIEWS / "effy-production-contact-sheet-v1.png")
    (OUT / "animations.json").write_text(json.dumps({"canvas":list(CANVAS),"anchor":[256,432],"animations":report}, indent=2)+"\n")
    print("Effy asset build complete")
    for item in report: print(f"{item['state']}: {item['frames']} frames")
    print("Canvas: 512x512")
    print("Alpha: OK")

if __name__ == "__main__": main()
