# app/

Entry points: the main scene (`main.tscn`, `main.gd`) and the headless dedicated server: `godot --headless --path . -- --server --bind ADDR [--port N]`. `server_main.gd` lists every flag; `main.gd` builds the `NetServer` node (net/) and adds it to the tree. The client comes in #7.
