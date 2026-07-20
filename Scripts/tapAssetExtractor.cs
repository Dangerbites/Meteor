using Godot;
using System;
using System.Collections.Generic;
using System.Threading;

// Autoload: TapAssetExtractor
//
// GameSalad ".tap" project files are just zip archives. Every asset lives
// under "Assets/" as one folder per asset, containing:
//   <name>.png       - the plain image
//   <name>-hd.png    - a retina/high-def variant
//   .thumbnail.png   - hidden editor thumbnail (unused at runtime)
//   .metaData.plist  - hidden editor metadata (unused at runtime)
//
// This walks EVERY entry in the archive structurally (no name/keyword
// filtering), so folders with spaces or unusual names never get silently
// skipped.
//
// Files are written to user:// preserving their original relative path,
// e.g. an entry at "Assets/Foo/Foo.png" becomes
// "user://project/Assets/Foo/Foo.png".
//
// Extraction runs on a background System.Threading.Thread so it doesn't
// block the main thread. All scene-tree/UI/signal work is marshaled back
// to the main thread via Callable.From(...).CallDeferred(), which is the
// only safe way to touch nodes from a worker thread in Godot 4.
//
// Progress is pushed automatically to:
//   get_tree().current_scene.get_node("ProgressUI")
// calling its GDScript contract: set_progress(info: String, value: float)
// where value is 0-100 (the ProgressUI node hides itself once value >= 100).

public partial class tapAssetExtractor : Node
{
	[Signal]
	public delegate void ExtractionProgressEventHandler(int current, int total, string path);

	[Signal]
	public delegate void ExtractionFinishedEventHandler(bool success, int extractedCount, int skippedCount, int errorCount);

	private const string OutputRoot = "user://project";
	private const string AssetsPrefix = "Assets/";
	private const string HdSuffix = "-hd.png";

	// Characters Windows forbids anywhere in a file/folder name.
	private static readonly string[] WindowsReservedChars = { "<", ">", ":", "\"", "\\", "|", "?", "*" };

	// Names Windows forbids outright, regardless of extension.
	private static readonly HashSet<string> WindowsReservedNames = new HashSet<string>
	{
		"CON", "PRN", "AUX", "NUL",
		"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
		"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
	};

	private Thread _extractionThread;
	private volatile bool _isExtracting = false;

	private class ExtractionResult
	{
		public bool Success = false;
		public List<string> Extracted = new List<string>();
		public List<(string Path, string Reason)> Skipped = new List<(string, string)>();
		public List<(string Path, string Reason)> Errors = new List<(string, string)>();
	}

	// Windows silently strips trailing dots/spaces from file and folder names
	// (e.g. "b o x . . ." becomes "b o x" on disk) and rejects reserved
	// characters like ":" outright. Apply this to every path SEGMENT -- not
	// the whole path, since "/" isn't affected -- on both write and read so
	// extraction and lookups always agree on the same filename.
	public static string SanitizePathSegment(string segment)
	{
		string cleaned = segment;
		foreach (var ch in WindowsReservedChars)
			cleaned = cleaned.Replace(ch, "");

		cleaned = cleaned.TrimEnd('.', ' ');

		if (WindowsReservedNames.Contains(cleaned.ToUpperInvariant()))
			cleaned += "_";

		return string.IsNullOrEmpty(cleaned) ? segment : cleaned;
	}

	// Sanitizes every "/"-separated segment of an asset_path (or any relative
	// path) the same way the extractor sanitizes folder/file names on write.
	// Call this on asset_path before building your load path so it matches
	// what actually landed on disk.
	public static string SanitizeAssetPath(string assetPath)
	{
		var parts = assetPath.Split('/');
		for (int i = 0; i < parts.Length; i++)
			parts[i] = SanitizePathSegment(parts[i]);
		return string.Join("/", parts);
	}

	// Like SanitizeAssetPath, but the LAST segment is treated as a filename:
	// its extension is preserved as-is and only the basename before it gets
	// sanitized. Needed because a trailing-dot name like "b o x . . ." only
	// produces a problem for the FOLDER "b o x . . ." -- the file itself is
	// "b o x . . ..png", which doesn't end in a dot, so a plain segment-wise
	// sanitize would leave the folder as "b o x" but the file as
	// "b o x . . ..png", no longer matching. This keeps the folder name and
	// the file's basename identical, since GameSalad always names them the same.
	public static string SanitizeFullPath(string path)
	{
		var parts = path.Split('/');
		for (int i = 0; i < parts.Length; i++)
		{
			if (i == parts.Length - 1)
			{
				string fileName = parts[i];
				string ext = fileName.GetExtension();
				string baseName = SanitizePathSegment(fileName.GetBaseName());
				parts[i] = string.IsNullOrEmpty(ext) ? baseName : $"{baseName}.{ext}";
			}
			else
			{
				parts[i] = SanitizePathSegment(parts[i]);
			}
		}
		return string.Join("/", parts);
	}

	// Convenience helper matching the loader pattern:
	//   var fullPath = "user://project/<asset_path>/<basename>.png"
	// where basename is the last segment of asset_path (GameSalad names the
	// file the same as its containing folder).
	public string GetAssetUserPath(string assetPath)
	{
		string sanitizedDir = SanitizeAssetPath(assetPath);
		string baseName = SanitizePathSegment(assetPath.GetFile());
		return OutputRoot.PathJoin(sanitizedDir).PathJoin(baseName + ".png");
	}

	// Kicks off extraction on a background thread. Safe to call from the
	// main thread. Progress and completion are reported via the
	// ExtractionProgress / ExtractionFinished signals and via ProgressUI,
	// both delivered on the main thread.
	//
	// tapFilePath: path to the .tap file. Can be res://, user://, or an
	//              absolute OS path (e.g. one picked via a native file dialog).
	// preferHd:    if true, whenever both "<name>.png" and "<name>-hd.png"
	//              exist, the -hd image data is used but still written to
	//              the PLAIN filename.
	// verbose:     print a summary + per-file log to the console.
	public void ExtractTapAssetsAsync(string tapFilePath, bool preferHd = true, bool verbose = true)
	{
		if (_isExtracting)
		{
			GD.PushWarning("TapAssetExtractor: extraction already in progress, ignoring new request.");
			return;
		}

		_isExtracting = true;
		_extractionThread = new Thread(() => ExtractTapAssetsThreaded(tapFilePath, preferHd, verbose))
		{
			IsBackground = true
		};
		_extractionThread.Start();
	}

	private void ExtractTapAssetsThreaded(string tapFilePath, bool preferHd, bool verbose)
	{
		var result = new ExtractionResult();

		var reader = new ZipReader();
		Error openErr = reader.Open(tapFilePath);
		if (openErr != Error.Ok)
		{
			string msg = $"Could not open '{tapFilePath}' as a zip archive (error code {(int)openErr})";
			GD.PushError(msg);
			result.Errors.Add((tapFilePath, msg));
			FinishOnMainThread(result);
			_isExtracting = false;
			return;
		}

		var allFiles = new List<string>(reader.GetFiles());
		int total = allFiles.Count;

		// Precompute which plain pngs have an -hd sibling present in the
		// archive, only needed when preferHd is on.
		var plainHasHd = new Dictionary<string, bool>();
		if (preferHd)
		{
			foreach (var path in allFiles)
			{
				if (path.EndsWith(HdSuffix))
				{
					string plainPath = path.Substring(0, path.Length - HdSuffix.Length) + ".png";
					plainHasHd[plainPath] = true;
				}
			}
		}

		int i = 0;
		foreach (var entryPath in allFiles)
		{
			i++;
			ReportProgress(i, total, entryPath);

			// Directory entries in a zip end with "/" and have no content.
			if (entryPath.EndsWith("/"))
				continue;

			if (!entryPath.StartsWith(AssetsPrefix))
			{
				result.Skipped.Add((entryPath, "outside Assets/"));
				continue;
			}

			string fileName = entryPath.GetFile();

			// Hidden GameSalad editor files: ".thumbnail.png", ".metaData.plist"
			if (fileName.StartsWith("."))
			{
				result.Skipped.Add((entryPath, "hidden editor metadata"));
				continue;
			}

			bool isHd = fileName.EndsWith(HdSuffix);
			string targetEntryPath = entryPath;

			if (isHd)
			{
				if (!preferHd)
				{
					result.Skipped.Add((entryPath, "hd variant (prefer_hd is false)"));
					continue;
				}
				// Rename the target so it lands on the plain filename.
				targetEntryPath = entryPath.Substring(0, entryPath.Length - HdSuffix.Length) + ".png";
			}
			else if (preferHd && fileName.EndsWith(".png") && plainHasHd.TryGetValue(entryPath, out bool hasHd) && hasHd)
			{
				// A better -hd version of this exact file exists elsewhere
				// in the loop and will be written to this same target path.
				result.Skipped.Add((entryPath, "superseded by -hd sibling"));
				continue;
			}

			byte[] data = reader.ReadFile(entryPath);
			if (data == null || data.Length == 0)
			{
				result.Errors.Add((entryPath, "archive returned no data for this entry"));
				continue;
			}

			string sanitizedEntryPath = SanitizeFullPath(targetEntryPath);
			string targetPath = OutputRoot.PathJoin(sanitizedEntryPath);
			string targetDir = targetPath.GetBaseDir();

			Error dirErr = DirAccess.MakeDirRecursiveAbsolute(targetDir);
			if (dirErr != Error.Ok && dirErr != Error.AlreadyExists)
			{
				result.Errors.Add((entryPath, $"could not create dir '{targetDir}' (error {(int)dirErr})"));
				continue;
			}

			using var f = FileAccess.Open(targetPath, FileAccess.ModeFlags.Write);
			if (f == null)
			{
				result.Errors.Add((entryPath, $"could not open '{targetPath}' for writing (error {(int)FileAccess.GetOpenError()})"));
				continue;
			}
			f.StoreBuffer(data);
			f.Close();

			result.Extracted.Add(targetPath);
			if (verbose)
				GD.Print("Extracted: ", targetPath);
		}

		reader.Close();

		result.Success = result.Errors.Count == 0;

		if (verbose)
		{
			GD.Print($"--- ExtractTapAssets('{tapFilePath}') ---");
			GD.Print($"Extracted: {result.Extracted.Count}   Skipped: {result.Skipped.Count}   Errors: {result.Errors.Count}");
			foreach (var e in result.Errors)
				GD.PushWarning($"ExtractTapAssets error on {e.Path}: {e.Reason}");
		}

		FinishOnMainThread(result);
		_isExtracting = false;
	}

	// Marshals a progress update to the main thread: emits the
	// ExtractionProgress signal and pushes the same info to ProgressUI.
	private void ReportProgress(int current, int total, string path)
	{
		Callable.From(() =>
		{
			EmitSignal(SignalName.ExtractionProgress, current, total, path);
			PushToProgressUi($"Extracting ({current}/{total}): {path}", total > 0 ? (float)current / total * 100f : 0f);
		}).CallDeferred();
	}

	// Marshals the finished result to the main thread: emits the
	// ExtractionFinished signal and forces ProgressUI to 100 (which makes
	// it hide itself, per its own set_progress logic).
	private void FinishOnMainThread(ExtractionResult result)
	{
		Callable.From(() =>
		{
			EmitSignal(SignalName.ExtractionFinished, result.Success, result.Extracted.Count, result.Skipped.Count, result.Errors.Count);
			string summary = result.Success
				? $"Done: {result.Extracted.Count} extracted"
				: $"Finished with {result.Errors.Count} error(s)";
			PushToProgressUi(summary, 100f);
		}).CallDeferred();
	}

	// Pushes to get_tree().current_scene.get_node("ProgressUI"), matching the
	// GDScript CanvasLayer's set_progress(info: String, value: float) contract
	// (0-100; the node hides itself once value >= 100). Must only be called
	// on the main thread (i.e. from inside a Callable.From(...).CallDeferred()).
	private void PushToProgressUi(string info, float value)
	{
		var progressUi = GetTree()?.CurrentScene?.GetNodeOrNull("ProgressUI");
		if (progressUi == null)
			return;

		progressUi.Call("set_progress", info, value);
	}

	public override void _ExitTree()
	{
		// Don't let the tree close out from under a still-running thread.
		if (_extractionThread != null && _extractionThread.IsAlive)
			_extractionThread.Join();
	}
}