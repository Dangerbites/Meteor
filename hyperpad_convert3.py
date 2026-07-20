"""
hyperpad_convert.py

Converts a hyperPad (.hyperpad / .tap) project bundle into a single JSON
document describing its scenes, objects, behavior graphs, colours, asset
index, and every other piece of metadata available.

This is a merge of the original hyperpad_convert.py and the former
tap_extract_extra.py into one file. Nothing about the merge changes any
existing key's shape - Behaviours / Objects / Scenes / Overlays /
GameDetails / LevelDetails / Layers / SceneMap all come out the same as
before, just with additions noted below. Everything that used to live only
in ExtendedHyperPadProject (SceneSettings, RawTables, EditorFiles) is
included too, since that's what get_project() always returned in practice.

Extended version:
  - Reads colors.plist    -> "Colors" in output
  - Reads assets.plist     -> "AssetInfo" in output
  - Extracts scene background colours (ZCOLOR, ZBGCOLOR, ZGRIDCOLOR) from SQLite
  - Each object now includes "secondary_asset_path", resolved from
    ZOBJECTDATA.ZPATHSECONDARY the same way "asset_path" is resolved from
    ZPATH.
  - "Layers" entries now include "hidden": bool, read from ZLAYERDATA.ZVISIBLE
    (0 = hidden, everything else = visible). Previously this only showed up
    buried in RawTables -> "Level 1" -> ZLAYERDATA -> ZVISIBLE per row; it's
    now surfaced directly on the same Layers dict every consumer already
    reads, keyed by the same layer number used in each object's "layer"
    field.
  - "Layers" entries also include "z_order", read from ZLAYERDATA.ZINDEX -
    the layer's stacking order relative to OTHER layers in the same scene
    (not global). Separate from each object's own "z_index"
    (ZOBJECTDATA.ZZ_INDEX), which orders objects within a layer.
  - "SceneSettings": background color/image/fill-mode + camera transform +
    width/height/level_mode/world_collisions, per scene name (from
    ZLEVELDATA + ZCAMERADATA, which nothing else reads).
  - "RawTables": every table, every column, from every levels/*/Level.sqlite,
    with any NSKeyedArchiver blob fully resolved. The safety net - whatever
    field turns out to be missing next, it's already in here.
  - "EditorFiles": colourPickerMemory.plist / objectDock.plist. Editor-only
    UI state (recently used colors, dock favorites), not runtime game data.

Usage:
    py hyperpad_convert.py "Jarr.tap"
    (writes Jarr.json next to it; pass a second argument to name it yourself)
"""

import base64
import json
import os
import plistlib
import re
import sqlite3
import tempfile
import zipfile
from plistlib import UID


# --------------------------------------------------------------------------
# NSKeyedArchiver resolution
# --------------------------------------------------------------------------
_PRIMITIVE_UNWRAP = {
    "NSString": "NS.string",
    "NSMutableString": "NS.string",
    "NSData": "NS.data",
    "NSMutableData": "NS.data",
}


def _resolve(node, objects, memo):
    if isinstance(node, UID):
        idx = node.data
        if idx in memo:
            return memo[idx]
        memo[idx] = None
        result = _resolve(objects[idx], objects, memo)
        memo[idx] = result
        return result

    if isinstance(node, dict):
        if "$class" not in node:
            return {k: _resolve(v, objects, memo) for k, v in node.items()}

        cls = _resolve(node["$class"], objects, memo)
        classname = cls.get("$classname", "Unknown") if isinstance(cls, dict) else "Unknown"

        if "NS.keys" in node and "NS.objects" in node:
            keys = [_resolve(k, objects, memo) for k in node["NS.keys"]]
            vals = [_resolve(v, objects, memo) for v in node["NS.objects"]]
            return dict(zip(keys, vals))

        if "NS.objects" in node:
            return [_resolve(v, objects, memo) for v in node["NS.objects"]]

        body = {k: _resolve(v, objects, memo) for k, v in node.items() if k != "$class"}

        if classname in _PRIMITIVE_UNWRAP:
            return body.get(_PRIMITIVE_UNWRAP[classname], body)

        body["__class__"] = classname
        return body

    if isinstance(node, list):
        return [_resolve(v, objects, memo) for v in node]

    return node


def _unwrap_nested_bplists(value):
    if isinstance(value, bytes) and value.startswith(b"bplist00"):
        return unarchive_bplist_bytes(value)
    if isinstance(value, dict):
        return {k: _unwrap_nested_bplists(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_unwrap_nested_bplists(v) for v in value]
    return value


def unarchive_bplist_bytes(data: bytes):
    plist = plistlib.loads(data)
    objects = plist["$objects"]
    top = plist.get("$top", {})
    root_ref = top.get("root", next(iter(top.values()), None))
    result = _resolve(root_ref, objects, {})
    return _unwrap_nested_bplists(result)


class BinaryJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, bytes):
            try:
                return obj.decode("utf-8")
            except UnicodeDecodeError:
                return base64.b64encode(obj).decode("ascii")
        return super().default(obj)


# --------------------------------------------------------------------------
# Hardened NSKeyedArchiver resolver
# --------------------------------------------------------------------------
# The plain _resolve() above crashes with "unhashable type: 'dict'" on a
# real subset of this kind of project's data: some "Set Graphic v1.26"
# behaviours contain a stray legacy-migration artifact -- a dictionary entry
# whose *key* resolves to NSNull (`{'__class__': 'NSNull'}`) instead of a
# string. dict(zip(keys, vals)) can't use a dict as a key, so it raises, the
# caller's try/except swallows it, and that behaviour's actions come back as
# {} -- silently, with only a printed warning.
#
# This only affects RawTables below -- Behaviours/Objects still go through
# the plain _resolve()/_decode_blob() path above and come out exactly as
# they always have, empty actions dict and all, so nothing about the
# existing hand-mapped fields changes.
#
# The fix: when a resolved key isn't hashable, use a stable JSON string of
# it as the key instead of raising. Ordinary string/number keys (the
# overwhelming majority) are completely unaffected.
def _safe_key(key):
    if isinstance(key, (dict, list)):
        return json.dumps(key, sort_keys=True, default=str)
    return key


def _resolve_safe(node, objects, memo):
    if isinstance(node, UID):
        idx = node.data
        if idx in memo:
            return memo[idx]
        memo[idx] = None
        result = _resolve_safe(objects[idx], objects, memo)
        memo[idx] = result
        return result

    if isinstance(node, dict):
        if "$class" not in node:
            return {k: _resolve_safe(v, objects, memo) for k, v in node.items()}

        cls = _resolve_safe(node["$class"], objects, memo)
        classname = cls.get("$classname", "Unknown") if isinstance(cls, dict) else "Unknown"

        if "NS.keys" in node and "NS.objects" in node:
            keys = [_resolve_safe(k, objects, memo) for k in node["NS.keys"]]
            vals = [_resolve_safe(v, objects, memo) for v in node["NS.objects"]]
            return dict(zip((_safe_key(k) for k in keys), vals))

        if "NS.objects" in node:
            return [_resolve_safe(v, objects, memo) for v in node["NS.objects"]]

        body = {k: _resolve_safe(v, objects, memo) for k, v in node.items() if k != "$class"}

        if classname in _PRIMITIVE_UNWRAP:
            return body.get(_PRIMITIVE_UNWRAP[classname], body)

        body["__class__"] = classname
        return body

    if isinstance(node, list):
        return [_resolve_safe(v, objects, memo) for v in node]

    return node


def _unwrap_nested_bplists_safe(value):
    if isinstance(value, bytes) and value.startswith(b"bplist00"):
        return unarchive_bplist_bytes_safe(value)
    if isinstance(value, dict):
        return {k: _unwrap_nested_bplists_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_unwrap_nested_bplists_safe(v) for v in value]
    return value


def unarchive_bplist_bytes_safe(data: bytes):
    """Same as unarchive_bplist_bytes, but never raises on a non-hashable
    dictionary key -- see _safe_key above."""
    plist = plistlib.loads(data)

    # Not every bplist00-prefixed blob is an NSKeyedArchiver archive -- e.g.
    # Z_METADATA.Z_PLIST is a plain Core Data metadata plist that just
    # happens to also be binary-plist-encoded. Only run the keyed-archiver
    # resolver when the archive actually says that's what it is; otherwise
    # hand back the plain parsed plist untouched.
    if not (isinstance(plist, dict) and plist.get("$archiver") == "NSKeyedArchiver" and "$objects" in plist):
        return plist

    objects = plist["$objects"]
    top = plist.get("$top", {})
    root_ref = top.get("root", next(iter(top.values()), None))
    result = _resolve_safe(root_ref, objects, {})
    return _unwrap_nested_bplists_safe(result)


# --------------------------------------------------------------------------
# SQLite -> plain Python tables
# --------------------------------------------------------------------------
def sqlite_to_tables(db_bytes: bytes) -> dict:
    fd, tmp_path = tempfile.mkstemp(suffix=".sqlite")
    os.close(fd)
    try:
        with open(tmp_path, "wb") as f:
            f.write(db_bytes)

        conn = sqlite3.connect(tmp_path)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        table_names = [r[0] for r in cur.fetchall()]

        tables = {}
        for name in table_names:
            cur.execute(f"PRAGMA table_info({name})")
            cols = [c[1] for c in cur.fetchall()]
            cur.execute(f"SELECT * FROM {name}")
            tables[name] = [dict(zip(cols, row)) for row in cur.fetchall()]

        conn.close()
        return tables
    finally:
        os.unlink(tmp_path)


# --------------------------------------------------------------------------
# hyperPad project (extended)
# --------------------------------------------------------------------------
class HyperPadProject:
    """Loads a .hyperpad/.tap bundle and exposes every piece of metadata."""

    def __init__(self, path):
        self.zip = zipfile.ZipFile(path, "r")
        self.level_dirs = self._find_level_dirs()
        if not self.level_dirs:
            raise ValueError("No levels/*/Level.sqlite found in this archive")
        self.level_tables = {d: self._load_level_sqlite(d) for d in self.level_dirs}
        self._blob_cache = {}
        self.warnings = []

    # ---- file discovery ---------------------------------------------------
    def _find_level_dirs(self):
        dirs = set()
        for name in self.zip.namelist():
            m = re.match(r"^levels/([^/]+)/Level\.sqlite$", name)
            if m:
                dirs.add(m.group(1))
        return sorted(dirs)

    def _load_level_sqlite(self, level_dir):
        return sqlite_to_tables(self.zip.read(f"levels/{level_dir}/Level.sqlite"))

    def _decode_blob(self, blob):
        if not blob:
            return {}
        cached = self._blob_cache.get(blob)
        if cached is not None:
            return cached
        try:
            result = unarchive_bplist_bytes(blob)
        except Exception as exc:
            self.warnings.append(f"failed to decode blob ({len(blob)} bytes): {exc}")
            result = {}
        self._blob_cache[blob] = result
        return result

    # ---- top-level plists ---------------------------------------------
    def get_game_details(self):
        return plistlib.loads(self.zip.read("gameDetails.plist"))

    def get_level_details(self):
        # uses first level as canonical
        d = self.level_dirs[0]
        return plistlib.loads(self.zip.read(f"levels/{d}/levelDetails.plist"))

    def get_colors(self):
        """Return the project colour palette (colors.plist) if it exists."""
        try:
            return plistlib.loads(self.zip.read("colors.plist"))
        except KeyError:
            self.warnings.append("colors.plist not found in archive")
            return {}

    def get_asset_info(self):
        """Return the asset index (assets.plist) if it exists."""
        try:
            return plistlib.loads(self.zip.read("assets.plist"))
        except KeyError:
            self.warnings.append("assets.plist not found in archive")
            return {}

    # ---- scenes / layers (extended with background colours + visibility) -
    def get_scenes(self):
        tables = self.level_tables[self.level_dirs[0]]
        scenes, overlays = [], []
        for s in tables.get("ZLEVELDATA", []):
            # ---- decode colour blobs ---------------------------------
            def _safe_color(key):
                blob = s.get(key)
                return self._decode_blob(blob) if blob else None

            entry = {
                "name": s["ZLEVELNAME"],
                "position": (s["ZX_POS"], s["ZY_POS"]),
                "zoom": s["ZSCALE"],
                "preload": s["ZPRELOAD"],
                # colour fields (keep them null if missing)
                "color": _safe_color("ZCOLOR"),
                "background_color": _safe_color("ZBGCOLOR"),
                "grid_color": _safe_color("ZGRIDCOLOR"),
            }
            (scenes if s["ZSCENETYPE"] == 0 else overlays).append(entry)
        return {"Scenes": scenes, "Overlays": overlays}

    def get_layers(self):
        tables = self.level_tables[self.level_dirs[0]]
        layers = {}
        for l in tables.get("ZLAYERDATA", []):
            layers[l["Z_PK"]] = {
                "scene": l["ZLEVEL"] or 0,
                "ui_layer": not l["ZNAME"],
                # ZVISIBLE is the editor's per-layer show/hide toggle,
                # independent of any individual object's own
                # gameobjectdata.hidden flag. 0 = hidden, anything else
                # (normally 1) = visible. An object can be individually
                # visible but still suppressed because its layer is hidden.
                "hidden": l["ZVISIBLE"] == 0,
                # ZINDEX is the layer's stacking order relative to OTHER
                # layers in the same scene (not global - two layers in
                # different scenes can share the same z_order with no
                # relationship to each other). This is separate from each
                # object's own z_index (ZOBJECTDATA.ZZ_INDEX), which orders
                # objects within a layer; z_order here orders the layers
                # themselves. Confirmed empirically: higher z_order means
                # further BACK (opposite of Godot's own z_index, where
                # higher = further front) - negate this value when
                # assigning it to a Godot node's z_index.
                "z_order": l["ZINDEX"],
            }
        return layers

    # ---- objects ----------------------------------------------
    def get_objects(self):
        merged = {}
        global_ui = {}
        for level_dir in self.level_dirs:
            organised, ui = self._get_objects_for_level(level_dir)
            for scene_name, objs in organised.items():
                merged.setdefault(scene_name, {}).update(objs)
            global_ui.update(ui)
        for scene_name in merged:
            merged[scene_name].update(global_ui)
        return merged

    def _get_objects_for_level(self, level_dir):
        tables = self.level_tables[level_dir]
        levels = [s["ZLEVELNAME"] for s in tables.get("ZLEVELDATA", [])]

        asset_paths = {p["ZUNIQUEID"]: p["ZPATH"] for p in tables.get("ZPATHDATA", [])}
        layer_scenes = {l["Z_PK"]: (l["ZLEVEL"] or 0) for l in tables.get("ZLAYERDATA", [])}
        positions = {p["ZOBJECTS"]: p for p in tables.get("ZOBJECTPOSITION", [])}

        collisions_by_object = {}
        for c in tables.get("ZCOLLISIONDATA", []):
            collisions_by_object.setdefault(c["ZOBJECT"], {})[c["ZINDEX"]] = (
                c["ZX_POS"],
                -c["ZY_POS"],
            )

        organised, ui_objects = {}, {}
        last_scene = None

        for od in tables.get("ZOBJECTDATA", []):
            pk = od["Z_PK"]
            pos = positions.get(pk)
            if pos is None:
                continue

            layer = pos["ZLAYERS"] or 1
            ui_element = pos["ZUNITX"] == 2
            path = asset_paths.get(od["ZPATH"]) if od["ZPATH"] else None
            second_path = asset_paths.get(od["ZPATHSECONDARY"]) if od["ZPATHSECONDARY"] else None
            gdata = self._decode_blob(od["ZGAMEOBJECTDATA"])

            points_by_index = collisions_by_object.get(pk, {})
            collision_points = [points_by_index.get(i, (0, 0)) for i in range(len(points_by_index))]

            scene_idx = int(layer_scenes.get(layer, 0))

            entry = {
                "name": od["ZNAME"],
                "ui_element": ui_element,
                "position": (pos["ZX"], pos["ZY"]),
                "scale": (od["ZX_SCALE"], od["ZY_SCALE"]),
                "rotation": od["ZROTATION"],
                "anchor": (pos["ZANCHORX"], pos["ZANCHORY"]),
                "gravity": (od["ZGRAVITY_X"], od["ZGRAVITY_Y"]),
                "friction": od["ZFRICTION"],
                "mass": od["ZMASS"],
                "density": od["ZDENSITY"],
                "restitution": od["ZRESTITUTION"],
                "physics_mode": od["ZPHYSICS_MODE"],
                "object_type": od["ZOBJECTTYPE"],
                "collidable": od["ZCOLLIDABLE"],
                "id": od["ZUNIQUEID"],
                "asset_path": path,
                "secondary_asset_path": second_path,
                "gameobjectdata": gdata,
                "collision_points": collision_points,
                "collision_shape": gdata.get("shape") if isinstance(gdata, dict) else None,
                "z_index": od["ZZ_INDEX"],
                "flip": (od["ZFLIPX"], od["ZFLIPY"]),
                "layer": int(layer),
                "scene": scene_idx,
            }

            if scene_idx == 0:
                ui_objects[entry["id"]] = entry
                continue

            if 0 < scene_idx <= len(levels):
                last_scene = levels[scene_idx - 1]
            scene_name = last_scene

            organised.setdefault(scene_name, {})[entry["id"]] = entry

        return organised, ui_objects

    # ---- behaviours -------------------------------------------
    def get_behaviours(self):
        merged = {}
        for level_dir in self.level_dirs:
            for obj_id, behaviours in self._get_behaviours_for_level(level_dir).items():
                merged.setdefault(obj_id, []).extend(behaviours)
        return merged

    def _get_behaviours_for_level(self, level_dir):
        tables = self.level_tables[level_dir]
        objects_by_pk = {o["Z_PK"]: o for o in tables.get("ZOBJECTDATA", [])}

        organised = {}
        for b in tables.get("ZBEHAVIOURDATA", []):
            owner = objects_by_pk.get(b["ZOBJECT"])
            if owner is None:
                continue

            actions = self._decode_blob(b["ZACTIONS"])

            entry = {
                "actions": actions,
                "root": b["ZISROOT"],
                "name": b["ZNAME"],
                "tag": b["ZTAG"],
                "position": (b["ZX_POS"], b["ZY_POS"]),
            }
            organised.setdefault(owner["ZUNIQUEID"], []).append(entry)

        return organised

    # ---- assets -----------------------------------------------
    def _find_asset_file(self, path_prefix, extension, hd=False):
        for info in self.zip.filelist:
            name = info.filename
            if not (name.startswith(path_prefix) and name.endswith(extension)):
                continue
            is_hd = name.endswith("-hd.png")
            is_thumb = name.endswith(".thumbnail.png")
            if hd and is_hd:
                return info
            if not hd and not is_hd and not is_thumb:
                return info
        return None

    def get_asset_path(self, path_prefix, extension, hd=False):
        info = self._find_asset_file(path_prefix, extension, hd)
        return info.filename if info else None

    def get_asset_size(self, path_prefix, extension, hd=False):
        info = self._find_asset_file(path_prefix, extension, hd)
        return info.file_size if info else None

    def get_image_dimensions(self, path_prefix, extension, hd=False):
        info = self._find_asset_file(path_prefix, extension, hd)
        if info is None:
            return None
        from PIL import Image
        with self.zip.open(info.filename) as fh:
            return Image.open(fh).size

    def extract_assets(self, to_dir, extension, compress=0):
        extracted = []
        for info in self.zip.filelist:
            if not info.filename.endswith(extension):
                continue
            try:
                self.zip.extract(info.filename, to_dir)
                out_path = os.path.join(to_dir, info.filename)
                if compress:
                    from PIL import Image
                    image = Image.open(out_path)
                    w, h = image.size
                    image.resize((int(w / compress), int(h / compress))).save(
                        out_path, optimize=True, quality=50
                    )
                extracted.append(out_path)
            except Exception as exc:
                self.warnings.append(f"failed to extract {info.filename}: {exc}")
        return extracted

    # ---- project assembly (base set of keys) ----------------------------
    def get_project(self):
        scenes = self.get_scenes()
        tables = self.level_tables[self.level_dirs[0]]
        scene_map = {0: "Global"}
        for s in tables.get("ZLEVELDATA", []):
            scene_map[s["Z_PK"]] = s["ZLEVELNAME"]

        project_data = {
            "Behaviours": self.get_behaviours(),
            "Objects": self.get_objects(),
            "Scenes": scenes["Scenes"],
            "Overlays": scenes["Overlays"],
            "GameDetails": self.get_game_details(),
            "LevelDetails": self.get_level_details(),
            "Layers": self.get_layers(),
            "SceneMap": scene_map,
            "Colors": self.get_colors(),
            "AssetInfo": self.get_asset_info(),
        }
        return project_data

    def to_json(self, indent=4):
        return json.dumps(self.get_project(), indent=indent, cls=BinaryJSONEncoder)


class ExtendedHyperPadProject(HyperPadProject):
    """Adds SceneSettings / RawTables / EditorFiles on top of the base
    get_project() output. Nothing here overrides a parent method - it only
    adds new top-level keys, so whatever reads the base keys keeps working
    unchanged."""

    # ---- per-scene background/camera settings (ZCAMERADATA) --------------
    def get_scene_settings(self):
        """Everything ZLEVELDATA + ZCAMERADATA know about a scene that
        get_scenes() doesn't surface: background color/image/fill mode,
        camera transform, pixel dimensions, level mode, world collisions."""
        tables = self.level_tables[self.level_dirs[0]]
        asset_paths = {p["ZUNIQUEID"]: p["ZPATH"] for p in tables.get("ZPATHDATA", [])}
        cameras_by_pk = {c["Z_PK"]: c for c in tables.get("ZCAMERADATA", [])}

        settings = {}
        for lvl in tables.get("ZLEVELDATA", []):
            cam = cameras_by_pk.get(lvl.get("ZCAMERA"))

            background = None
            camera = None
            if cam is not None:
                bg_image_id = cam.get("ZBACKGROUNDIMAGE")
                background = {
                    "color_rgb": (
                        cam.get("ZBACKGROUNDCOLORR"),
                        cam.get("ZBACKGROUNDCOLORG"),
                        cam.get("ZBACKGROUNDCOLORB"),
                    ),
                    "opacity": cam.get("ZOPACITY"),
                    "fill_mode": cam.get("ZBACKGROUNDFILLMODE"),
                    "image_path": asset_paths.get(bg_image_id) if bg_image_id else None,
                    "image_frame": cam.get("ZBACKGROUNDIMAGEFRAME"),
                }
                camera = {
                    "selected": bool(cam.get("ZCAMERASELECTED")),
                    "position": (cam.get("ZX_POS"), cam.get("ZY_POS")),
                    "anchor": (cam.get("ZX_ANCHOR"), cam.get("ZY_ANCHOR")),
                    "scale": cam.get("ZSCALE"),
                }

            settings[lvl["ZLEVELNAME"]] = {
                "background": background,
                "camera": camera,
                "width": lvl.get("ZWIDTH"),
                "height": lvl.get("ZHEIGHT"),
                "level_mode": lvl.get("ZLEVELMODE"),
                "game_name": lvl.get("ZGAMENAME"),
                "world_collisions": lvl.get("ZWORLDCOLLISIONS"),
            }

        return settings

    # ---- generic full dump of every table/column, blobs resolved ---------
    def get_raw_tables(self):
        """Every table from every levels/*/Level.sqlite, every column,
        verbatim -- with any NSKeyedArchiver bplist bytes column fully
        resolved via the same generic resolver get_behaviours()/get_objects()
        already use for ZACTIONS/ZGAMEOBJECTDATA. The catch-all: any column
        nobody has hand-mapped into get_project() yet still shows up here."""
        raw = {}
        for level_dir, tables in self.level_tables.items():
            raw[level_dir] = {
                table_name: [
                    {col: self._decode_raw_value(val) for col, val in row.items()}
                    for row in rows
                ]
                for table_name, rows in tables.items()
            }
        return raw

    def _decode_raw_value(self, value):
        if isinstance(value, bytes):
            if value.startswith(b"bplist00"):
                cache_key = ("raw", value)
                cached = self._blob_cache.get(cache_key)
                if cached is not None:
                    return cached
                try:
                    result = unarchive_bplist_bytes_safe(value)
                except Exception as exc:
                    self.warnings.append(
                        f"raw dump: failed to decode blob ({len(value)} bytes): {exc}"
                    )
                    result = base64.b64encode(value).decode("ascii")
                self._blob_cache[cache_key] = result
                return result
            try:
                return value.decode("utf-8")
            except UnicodeDecodeError:
                return base64.b64encode(value).decode("ascii")
        return value

    # ---- editor-only top-level plists (not game/runtime data) ------------
    def get_editor_files(self):
        files = {}
        for name in ("colourPickerMemory.plist", "objectDock.plist"):
            if name in self.zip.namelist():
                try:
                    files[name] = plistlib.loads(self.zip.read(name))
                except Exception as exc:
                    self.warnings.append(f"failed to parse {name}: {exc}")
        return files

    # ---- extend get_project() by ADDING keys, parent keys untouched -------
    def get_project(self):
        project = super().get_project()
        project["SceneSettings"] = self.get_scene_settings()
        project["RawTables"] = self.get_raw_tables()
        project["EditorFiles"] = self.get_editor_files()
        return project


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
if __name__ == "__main__":
    import sys

    if len(sys.argv) not in (2, 3):
        print('Usage: py hyperpad_convert.py "Jarr.tap" [output.json]')
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) == 3 else os.path.splitext(input_path)[0] + ".json"

    project = ExtendedHyperPadProject(input_path)
    with open(output_path, "w") as f:
        json.dump(project.get_project(), f, indent=4, cls=BinaryJSONEncoder)

    if project.warnings:
        print(f"Completed with {len(project.warnings)} warning(s):")
        for w in project.warnings:
            print(f"  - {w}")
    print(f"Wrote {output_path}")