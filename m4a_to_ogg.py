"""
m4a_to_ogg.py

Converts .m4a (AAC) audio files to .ogg (Vorbis) using PyAV.

Why this exists: Godot has no built-in AAC/M4A decoder, so files
extracted from a hyperPad .tap project as .m4a can't be played directly.
Godot DOES support Ogg Vorbis natively (AudioStreamOggVorbis), so
converting once at extraction/build time makes every sound playable
without touching Godot's C++ side at all.

Why PyAV instead of shelling out to ffmpeg.exe: PyAV (the `av` package)
ships its own compiled FFmpeg libraries INSIDE the Python wheel - there
is no separate ffmpeg.exe to place in a user folder, no OS.execute()
child-process spawning to go wrong, no antivirus/SmartScreen blocking an
unsigned downloaded binary. `pip install av` is the entire dependency.

Usage as a script:
    python m4a_to_ogg.py input.m4a output.ogg
    python m4a_to_ogg.py input.m4a                 # writes input.ogg next to it

Usage as a module:
    from m4a_to_ogg import convert_m4a_to_ogg
    convert_m4a_to_ogg("input.m4a", "output.ogg")
"""

import sys
from pathlib import Path

import av


def convert_m4a_to_ogg(input_path: str, output_path: str | None = None) -> str:
    """
    Convert a single .m4a file to .ogg (Vorbis).

    Args:
        input_path: path to the source .m4a file.
        output_path: path to write the .ogg to. If omitted, uses the
            same directory/basename as input_path with a .ogg extension.

    Returns:
        The output path actually written, as a string.

    Raises:
        FileNotFoundError: if input_path doesn't exist.
        av.AVError / RuntimeError: if decoding or encoding fails.
    """
    in_path = Path(input_path)
    if not in_path.exists():
        raise FileNotFoundError(f"Input file not found: {in_path}")

    out_path = Path(output_path) if output_path else in_path.with_suffix(".ogg")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    input_container = av.open(str(in_path))
    output_container = av.open(str(out_path), mode="w")

    try:
        input_stream = next(
            (s for s in input_container.streams if s.type == "audio"), None
        )
        if input_stream is None:
            raise RuntimeError(f"No audio stream found in '{in_path}'")

        # FFmpeg's built-in "vorbis" encoder (as opposed to the libvorbis
        # wrapper, which isn't always compiled into PyAV's bundled
        # ffmpeg) is marked experimental and refuses to open without this
        # explicit opt-in - equivalent to ffmpeg's `-strict experimental`.
        output_stream = output_container.add_stream(
            "vorbis", options={"strict": "experimental"}
        )

        for frame in input_container.decode(input_stream):
            for packet in output_stream.encode(frame):
                output_container.mux(packet)

        # Flush the encoder - some buffered frames only come out once
        # encode() is called with no more input.
        for packet in output_stream.encode(None):
            output_container.mux(packet)
    finally:
        output_container.close()
        input_container.close()

    return str(out_path)


def convert_directory(root_dir: str, remove_originals: bool = False) -> list[str]:
    """
    Recursively find every .m4a under root_dir and convert each to .ogg
    alongside it (same folder, same base name).

    Args:
        root_dir: directory to search.
        remove_originals: if True, deletes the source .m4a after a
            successful conversion. Defaults to False - leaves the
            original in place, matching the "add .ogg alongside it"
            behaviour the Godot-side extractor originally used.

    Returns:
        List of output .ogg paths that were successfully written.
    """
    converted = []
    for m4a_path in Path(root_dir).rglob("*.m4a"):
        try:
            ogg_path = convert_m4a_to_ogg(str(m4a_path))
            converted.append(ogg_path)
            print(f"Converted: {m4a_path} -> {ogg_path}")
            if remove_originals:
                m4a_path.unlink()
        except Exception as exc:
            print(f"FAILED to convert '{m4a_path}': {exc}", file=sys.stderr)
    return converted


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python m4a_to_ogg.py <input.m4a> [output.ogg]", file=sys.stderr)
        print("       python m4a_to_ogg.py --dir <folder>  (convert every .m4a under folder)", file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--dir":
        if len(sys.argv) < 3:
            print("Usage: python m4a_to_ogg.py --dir <folder>", file=sys.stderr)
            sys.exit(1)
        results = convert_directory(sys.argv[2])
        print(f"\nDone. Converted {len(results)} file(s).")
    else:
        src = sys.argv[1]
        dst = sys.argv[2] if len(sys.argv) > 2 else None
        result_path = convert_m4a_to_ogg(src, dst)
        print(f"Converted: {src} -> {result_path}")
