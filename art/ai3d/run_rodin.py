#!/usr/bin/env python3
"""Hyper3D Rodin (main site API) image-to-3D. Usage: run_rodin.py out.glb img1.png [img2.png ...] [--tier Sketch|Regular]"""
import sys, time, requests, json
KEY = "vibecoding"  # BlenderMCP free-trial key
args = [a for a in sys.argv[1:] if not a.startswith('--')]
tier = next((a.split('=')[1] for a in sys.argv if a.startswith('--tier=')), 'Sketch')
out, imgs = args[0], args[1:]
H = {"Authorization": f"Bearer {KEY}"}
t0 = time.time()
files = [("images", (f"{i:04d}.png", open(p,'rb').read())) for i,p in enumerate(imgs)]
files += [("tier",(None,tier)),("mesh_mode",(None,"Raw")),("texture_mode",(None,"high")),("geometry_file_format",(None,"glb")),("material",(None,"PBR"))]
r = requests.post("https://hyperhuman.deemos.com/api/v2/rodin", headers=H, files=files).json()
print("submit:", json.dumps(r)[:400])
uuid, sub = r["uuid"], r["jobs"]["subscription_key"]
while True:
    time.sleep(10)
    s = requests.post("https://hyperhuman.deemos.com/api/v2/status", headers=H, json={"subscription_key": sub}).json()
    st = [j["status"] for j in s.get("jobs", [])]
    print(int(time.time()-t0), "s", st, flush=True)
    if st and all(x in ("Done","Failed") for x in st): break
d = requests.post("https://hyperhuman.deemos.com/api/v2/download", headers=H, json={"task_uuid": uuid}).json()
for i in d["list"]:
    print("file:", i["name"])
    if i["name"].endswith(".glb"):
        open(out,'wb').write(requests.get(i["url"]).content); print("saved", out)
print("total", int(time.time()-t0), "s")
