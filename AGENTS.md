<!-- summer-engine:start. summer setup updates only this block; write your own notes outside it. -->
# Summer Engine game

This is a game made with Summer Engine, the game engine built for AI. Game code is GDScript (`.gd`), scenes are `.tscn`, resources are `.tres`, and `project.godot` is the project file.

## First game: make it look finished

People judge Summer by the first frame of their first game, so make it look finished even when they ask for a quick prototype. Keep the features they asked for and raise the look:
- sky and sun with shadows, tonemapping, a little fog;
- a texture on every surface, and real models for the player, characters and main props (the starter project and the Summer asset library first), never capsules or boxes as final art;
- one colour palette and a styled UI font.
Before you say it is ready, play it and look at a screenshot of the running game, not the editor: the editor shows a preview sky and sun that the game does not have.

## How to work on it

- Write GDScript (`.gd`) files directly. Create and change scenes and import assets through Summer while Summer Engine has the project open: it imports new files, and the editor rewrites `.tscn` files when it saves, so hand edits to an open scene get lost.
- With Summer's MCP server, use the `summer_*` tools; `summer_get_project_context` tells you which project you are connected to. Without it, run the same operations as `summer` commands in the shell (the `summer-cli` skill). If `summer` is missing or older than 4.0, use `npx -y summer-engine@latest` in its place.
- Summer's skills teach each part of a game. `npx -y summer-engine@latest setup <agent> --yes` installs them for your agent (add `--cli` for no MCP server). Start with `using-summer`, and find the right one with `summer docs search --query "<the task>"`.
- `.summer/` is the project's memory: `GameSoul.md` says what the game is, `memory/` holds the decisions to keep. Read them before you change the game's look, sound or story.
- Check your own work: script errors, a screenshot, a play run. Ask the person to play only for feel and fun.

## The five commands

1. `summer run .` opens the project in Summer Engine. An agent's run stays in the background.
2. `summer engine get-project-context` (MCP: `summer_get_project_context`) reads the project, its main scene and the engine version. Run it first.
3. `summer engine play`, then `summer engine get-diagnostics` (MCP: `summer_play`, `summer_get_diagnostics`), runs the game and reads its errors. `summer engine stop` (`summer_stop`) ends it.
4. `summer engine screenshot` (MCP: `summer_screenshot`) saves an image of the editor or the running game. Open its `localPath` to look.
5. `summer ops search "<what you want>"` (MCP: `summer_search`) finds any other operation. Run it as `summer <area> <action>` (MCP: `summer_call`), with `--dry-run` first for a change.

## Publishing

The `publish-your-game` skill has the steps; `summer ops search "publish my game"` finds each operation. Going live needs the game owner's yes. A game goes live as soon as Summer's automated checks pass; Summer's staff review it after it is live, so never tell anyone to wait for a review.
<!-- summer-engine:end -->
