using Godot;
using System;
using System.Text.Json;
using System.IO;
using System.Collections.Generic;

public partial class EmulatorManager : Node
{
    [Export]
    public string PROJECT_JSON = "JARRoutput.json";
    private string MAIN_SCENE_NAME;

    public override void _Ready()
    {

        string path = ProjectSettings.GlobalizePath($"user://{PROJECT_JSON}");
        string jsonText = File.ReadAllText(path);

        using JsonDocument doc = JsonDocument.Parse(jsonText);
        JsonElement root = doc.RootElement;

        JsonElement sceneMapElement = root.GetProperty("SceneMap");

        var sceneMap = JsonSerializer.Deserialize<Dictionary<string, string>>(sceneMapElement.GetRawText());

        if (sceneMap.TryGetValue("3", out string sceneName))
        {
            GD.Print($"Scene with ID 3: {sceneName}");
        }

        string mainScene = null;
        foreach (var kvp in sceneMap)
        {
            if (kvp.Value != "Global" && kvp.Value != "Pause Menu" && kvp.Value != "Game Over")
            {
                mainScene = kvp.Value;
                break;
            }
        }
        if (mainScene != null)
        {
            MAIN_SCENE_NAME = mainScene;
            GD.Print(mainScene);
        }
        else
        {
            GD.PrintErr("No main scene found");
        }
    }

    public override void _Process(double delta)
    {
        if (Input.IsActionJustPressed("open_user_folder"))
        {
            string userPath = ProjectSettings.GlobalizePath("user://");
            OS.ShellOpen(userPath);
        }
    }
}