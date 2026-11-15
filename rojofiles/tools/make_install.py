"""
Builds install/MarsBase7_Scripts.rbxmx from src/ (same layout as default.project.json),
so the scripts can be put into a place WITHOUT Rojo.  Run:  python3 tools/make_install.py

In Studio: right-click Workspace > Insert from File... > MarsBase7_Scripts.rbxmx,
then paste install/InstallScripts.lua into the Command Bar.
Scripts/LocalScripts inside the file are disabled until the installer turns them on,
so nothing runs while the pack sits in Workspace.
"""
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "install", "MarsBase7_Scripts.rbxmx")
ref = 0


def next_ref():
    global ref
    ref += 1
    return f"RBX{ref}"


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def kind(filename):
    if filename.endswith(".server.lua"):
        return "Script", filename[:-len(".server.lua")]
    if filename.endswith(".client.lua"):
        return "LocalScript", filename[:-len(".client.lua")]
    if filename.endswith(".lua"):
        return "ModuleScript", filename[:-len(".lua")]
    return None, None


def script_item(cls, name, source, children=""):
    disabled = '<bool name="Disabled">true</bool>' if cls in ("Script", "LocalScript") else ""
    return (f'<Item class="{cls}" referent="{next_ref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>{disabled}'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties>{children}</Item>')


def folder_item(name, children):
    return (f'<Item class="Folder" referent="{next_ref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string></Properties>{children}</Item>')


def dir_children(path):
    """Items for every file / init-folder inside path (Rojo rules)."""
    out = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            init = [f for f in os.listdir(full) if f.startswith("init.") and f.endswith(".lua")]
            if init:
                cls, _ = kind(init[0])
                src = open(os.path.join(full, init[0]), encoding="utf-8").read()
                kids = "".join(
                    script_item(*kind(f), open(os.path.join(full, f), encoding="utf-8").read())
                    for f in sorted(os.listdir(full)) if f != init[0] and kind(f)[0])
                out.append(script_item(cls, entry, src, kids))
            else:
                out.append(folder_item(entry, "".join(dir_children(full))))
        else:
            cls, name = kind(entry)
            if cls:
                out.append(script_item(cls, name, open(full, encoding="utf-8").read()))
    return out


body = folder_item("MarsBase7_Scripts",
    folder_item("ReplicatedStorage", folder_item("BaseShared", "".join(dir_children(os.path.join(SRC, "shared", "BaseShared")))))
    + folder_item("ServerScriptService", folder_item("BaseServer", "".join(dir_children(os.path.join(SRC, "server", "BaseServer")))))
    + folder_item("StarterPlayerScripts", "".join(dir_children(os.path.join(SRC, "client")))))
xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">' + body + '</roblox>')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(xml)
print("wrote", OUT, len(xml) // 1024, "KB,", ref, "items")
