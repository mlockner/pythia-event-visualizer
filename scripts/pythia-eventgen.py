#!/usr/bin/env python3

import json
import math
import sys
import os

import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

try:
    import pythia8
except ImportError:
    print("ERROR: could not import pythia8.")
    print("Check PYTHONPATH and LD_LIBRARY_PATH.")
    sys.exit(1)


def particle_color(pid: int) -> str:
    apid = abs(pid)

    if pid == 22:
        return "yellow"
    elif apid == 11:
        return "lime"
    elif apid == 13:
        return "cyan"
    elif apid == 15:
        return "turquoise"
    elif apid in (12, 14, 16):
        return "navy"
    elif apid in (211, 321):
        return "red"
    elif apid in (111, 130, 310):
        return "orange"
    elif apid in (2212, 2112, 3122):
        return "magenta"
    else:
        return "gray"


def particle_color_hex(pid: int) -> str:
    apid = abs(pid)
    if pid == 22:
        return "#ffff00"   # photon
    elif apid == 11:
        return "#00ff00"   # electron
    elif apid == 13:
        return "#00ffff"   # muon
    elif apid == 15:
        return "#40e0d0"   # tau
    elif apid in (12, 14, 16):
        return "#000080"   # neutrino
    elif apid in (211, 321):
        return "#ff0000"   # charged meson
    elif apid in (111, 130, 310):
        return "#ffa500"   # neutral meson
    elif apid in (2212, 2112, 3122):
        return "#ff00ff"   # baryon
    else:
        return "#808080"


def particle_label(pid: int) -> str:
    apid = abs(pid)
    if pid == 22:
        return "photon"
    elif apid == 11:
        return "electron"
    elif apid == 13:
        return "muon"
    elif apid == 15:
        return "tau"
    elif apid in (12, 14, 16):
        return "neutrino"
    elif apid in (211, 111, 321, 130, 310):
        return "meson"
    elif apid in (2212, 2112, 3122):
        return "baryon"
    return "other"


def export_event(evt, output_path, event_id=1, default_speed_mps=10.0):
    particles = []

    for i in range(evt.size()):
        p = evt[i]
        if not p.isFinal():
            continue

        px, py, pz = p.px(), p.py(), p.pz()
        pmag = math.sqrt(px*px + py*py + pz*pz)
        if pmag <= 0:
            continue

        pid = p.id()
        particles.append({
            "index": i,
            "pid": pid,
            "label": particle_label(pid),
            "charge": p.charge(),
            "energy_GeV": p.e(),
            "mass_GeV": p.m(),
            "p_GeV": pmag,
            "direction": {
                "x": px / pmag,
                "y": py / pmag,
                "z": pz / pmag
            },
            "color": particle_color_hex(pid),
            "visible": abs(pid) not in (12, 14, 16)
        })

    payload = {
        "event_id": event_id,
        "units": {
            "direction": "unitless",
            "display_speed": "m/s",
            "position": "m"
        },
        "display": {
            "default_speed_mps": default_speed_mps
        },
        "camera_hint": {
            "beam_axis": "z",
            "up_axis": "y",
            "suggested_half_extent_m": 3.0
        },
        "particles": particles
    }

    with open(output_path, "w") as f:
        json.dump(payload, f, indent=2)

    print(f"Wrote {len(particles)} particles to {output_path}")


def main():
    pythia = pythia8.Pythia()

    pythia.readString("Beams:idA = 2212")
    pythia.readString("Beams:idB = 2212")
    pythia.readString("Beams:eCM = 13000.")
    pythia.readString("HardQCD:all = on")
    pythia.readString("PhaseSpace:pTHatMin = 20.")

    if not pythia.init():
        raise RuntimeError("PYTHIA failed to initialize.")

    success = False
    for _ in range(20):
        if pythia.next():
            success = True
            break

    if not success:
        raise RuntimeError("Failed to generate an event.")

    evt = pythia.event
    particles = []

    for i in range(evt.size()):
        p = evt[i]
        if not p.isFinal():
            continue

        px, py, pz = p.px(), p.py(), p.pz()
        pmag = math.sqrt(px * px + py * py + pz * pz)
        if pmag <= 0:
            continue

        particles.append({
            "i": i,
            "id": p.id(),
            "ux": px / pmag,
            "uy": py / pmag,
            "uz": pz / pmag,
            "p": pmag,
            "E": p.e(),
            "m": p.m(),
            "color": particle_color(p.id()),
        })

    if not particles:
        raise RuntimeError("No final-state particles found.")

    print(f"Animating {len(particles)} particles")

    # Optional: cap particle count for speed
    # particles.sort(key=lambda part: part["p"], reverse=True)
    # particles = particles[:80]

    display_speed = 10.0
    lim = 3.0
    duration = lim / display_speed
    fps = 60
    nframes = max(2, int(duration * fps) + 1)

    elev = 5
    azim = -65

    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection="3d")

    fig.patch.set_facecolor("black")
    ax.set_facecolor("black")

    ax.xaxis.pane.set_facecolor((0, 0, 0, 1))
    ax.yaxis.pane.set_facecolor((0, 0, 0, 1))
    ax.zaxis.pane.set_facecolor((0, 0, 0, 1))

    ax.xaxis._axinfo["grid"]["color"] = (0.3, 0.3, 0.3, 0.4)
    ax.yaxis._axinfo["grid"]["color"] = (0.3, 0.3, 0.3, 0.4)
    ax.zaxis._axinfo["grid"]["color"] = (0.3, 0.3, 0.3, 0.4)

    ax.xaxis.label.set_color("white")
    ax.yaxis.label.set_color("white")
    ax.zaxis.label.set_color("white")
    ax.tick_params(colors="white")
    ax.xaxis.line.set_color("white")
    ax.yaxis.line.set_color("white")
    ax.zaxis.line.set_color("white")
    ax.title.set_color("white")

    trail_lines = []
    for part in particles:
        c = part["color"]
        line, = ax.plot([0, 0], [0, 0], [0, 0], color=c, alpha=0.75, linewidth=1.2)
        trail_lines.append(line)

    ax.plot([0, 0], [0, 0], [-lim, lim], color="white", linewidth=1.2, alpha=0.35)

    ax.set_xlim(-lim, lim)
    ax.set_ylim(-lim, lim)
    ax.set_zlim(-lim, lim)

    ax.set_xlabel("x [m]")
    ax.set_ylabel("y [m]")
    ax.set_zlabel("z [m]")
    ax.set_title("PYTHIA Event Slow-Motion Expansion")

    try:
        ax.set_box_aspect((1, 1, 1))
    except Exception:
        pass

    ax.view_init(elev=elev, azim=azim)

    time_text = ax.text2D(0.03, 0.95, "", transform=ax.transAxes, color="white")

    def update(frame):
        t = min(frame / fps, duration)
        r = display_speed * t

        for j, part in enumerate(particles):
            x = part["ux"] * r
            y = part["uy"] * r
            z = part["uz"] * r
            trail_lines[j].set_data_3d([0, x], [0, y], [0, z])

        time_text.set_text(f"t = {t:0.3f} s   display speed ≈ {display_speed:.1f} m/s")
        return trail_lines + [time_text]

    anim = FuncAnimation(
        fig,
        update,
        frames=nframes,
        interval=1000 / fps,
        blit=False,
        repeat=True
    )

    plt.tight_layout()
    plt.show()

    print("\nFinal-state particle summary:")
    counts = {}
    for part in particles:
        label = particle_label(part["id"])
        counts[label] = counts.get(label, 0) + 1

    for k in sorted(counts):
        print(f"  {k:16s}: {counts[k]}")

    print(f"\nTotal final-state particles animated: {len(particles)}")
    export_event(evt, "/mnt/c/Users/smlock/Documents/pythia-event-visualizer/event_data/pythia_event.json")

if __name__ == "__main__":
    main()
