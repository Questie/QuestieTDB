# Recon 08 — TOC files, interface versions, packaging & CI

Read-only recon. Source of truth = `Questie/`. Prototypes (`Getters/`, `toc-database/`) are STALE
for interface numbers and MUST NOT be copied.

Workspace root: `/home/logon/projects/Questie-clones/Questie-toc`

---

## 1. Questie TOC headers — quoted in FULL (all six)

There are exactly six `.toc` files at `Questie/` root:

| File | Bytes | Interface |
| --- | ---: | --- |
| `Questie/Questie.toc` | 378 | `00000` |
| `Questie/Questie-Classic.toc` | 9514 | `11508, 11509` |
| `Questie/Questie-BCC.toc` | 9065 | `20506` |
| `Questie/Questie-WOTLKC.toc` | 9484 | `38000, 38001` |
| `Questie/Questie-Cata.toc` | 9631 | `40402` |
| `Questie/Questie-Mists.toc` | 10208 | `50503, 50504` |

### 1.1 `Questie/Questie.toc` — FULL FILE (fallback / unsupported client)

```
# This file is used to show unsupported game client message.
# Supported client flavors load their own TOC file and unsupported ones fall back to this one.
# Check expansion specific TOC files for the correct data.
## Interface: 00000
## Title: Questie|cFFFF0000 game client not supported|r
## Notes: Questie only supports Classic official servers.

Modules\GameVersionError.lua
```

That is the entire file (8 lines). Note it has NO `## Version`, NO `## Author`, NO deps — it is a
deliberately minimal "wrong client" stub. It is unconditionally shipped (`filesToInclude` in
`build.py` always contains `"Questie.toc"`).

**QuestieTDB analogue:** the base `QuestieTDB.toc` is *not* a stub — per `QuestieTDB/DESIGN.md:248`
it is the committed **source mode** TOC. Different semantics, same "un-suffixed file is the
fallback when no suffixed TOC matches" mechanic.

### 1.2 `Questie/Questie-Classic.toc` — header lines 1–30 verbatim

```
## Interface: 11508, 11509
## Title: Questie|cFF00FF00 v11.33.2|r
## Author: Aero/Logon/Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Everyone else
## Notes: A standalone Classic QuestHelper
## Notes-esES: Un asistente de misiones
## Notes-esMX: Un asistente de misiones
## Notes-frFR: Un assistant de quêtes
## Notes-ptBR: Um assistente de missões
## Notes-ruRU: Помощник по заданиям в WoW Classic
## Notes-zhCN: 独立的怀旧服任务助手
## Notes-zhTW: 獨立的經典版任務助手
## Category: Quests
## Category-deDE: Quests
## Category-esES: Misiones
## Category-esMX: Misiones
## Category-frFR: Quêtes
## Category-itIT: Missioni
## Category-koKR: 퀘스트
## Category-ptBR: Missões
## Category-ruRU: Задания
## Category-zhCN: 任务
## Category-zhTW: 任務
## Version: 11.33.2
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
## SavedVariables: QuestieConfig
## SavedVariablesPerCharacter: QuestieConfigCharacter
## IconTexture: Interface\AddOns\Questie\Icons\questie.png
## X-Curse-Project-ID: 334372
## X-Wago-ID: qv634BKb
```

### 1.3 `Questie/Questie-BCC.toc` — header lines 1–30 verbatim

```
## Interface: 20506
## Title: Questie|cFF00FF00 v11.33.2|r
## Author: Aero/Logon/Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Everyone else
## Notes: A standalone Classic QuestHelper
## Notes-esES: Un asistente de misiones
## Notes-esMX: Un asistente de misiones
## Notes-frFR: Un assistant de quêtes
## Notes-ptBR: Um assistente de missões
## Notes-ruRU: Помощник по заданиям в WoW Classic
## Notes-zhCN: 独立的怀旧服任务助手
## Notes-zhTW: 獨立的經典版任務助手
## Category: Quests
## Category-deDE: Quests
## Category-esES: Misiones
## Category-esMX: Misiones
## Category-frFR: Quêtes
## Category-itIT: Missioni
## Category-koKR: 퀘스트
## Category-ptBR: Missões
## Category-ruRU: Задания
## Category-zhCN: 任务
## Category-zhTW: 任務
## Version: 11.33.2
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
## SavedVariables: QuestieConfig
## SavedVariablesPerCharacter: QuestieConfigCharacter
## IconTexture: Interface\AddOns\Questie\Icons\questie.png
## X-Curse-Project-ID: 334372
## X-Wago-ID: qv634BKb
```

### 1.4 `Questie/Questie-WOTLKC.toc` — header lines 1–30 verbatim

```
## Interface: 38000, 38001
## Title: Questie|cFF00FF00 v11.33.2|r
## Author: Aero/Logon/Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Everyone else
## Notes: A standalone Classic QuestHelper
## Notes-esES: Un asistente de misiones
## Notes-esMX: Un asistente de misiones
## Notes-frFR: Un assistant de quêtes
## Notes-ptBR: Um assistente de missões
## Notes-ruRU: Помощник по заданиям в WoW Classic
## Notes-zhCN: 独立的怀旧服任务助手
## Notes-zhTW: 獨立的經典版任務助手
## Category: Quests
## Category-deDE: Quests
## Category-esES: Misiones
## Category-esMX: Misiones
## Category-frFR: Quêtes
## Category-itIT: Missioni
## Category-koKR: 퀘스트
## Category-ptBR: Missões
## Category-ruRU: Задания
## Category-zhCN: 任务
## Category-zhTW: 任務
## Version: 11.33.2
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
## SavedVariables: QuestieConfig
## SavedVariablesPerCharacter: QuestieConfigCharacter
## IconTexture: Interface\AddOns\Questie\Icons\questie.png
## X-Curse-Project-ID: 334372
## X-Wago-ID: qv634BKb
```

### 1.5 `Questie/Questie-Cata.toc` — header lines 1–30 verbatim

```
## Interface: 40402
## Title: Questie|cFF00FF00 v11.33.2|r
## Author: Aero/Logon/Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Everyone else
## Notes: A standalone Classic QuestHelper
## Notes-esES: Un asistente de misiones
## Notes-esMX: Un asistente de misiones
## Notes-frFR: Un assistant de quêtes
## Notes-ptBR: Um assistente de missões
## Notes-ruRU: Помощник по заданиям в WoW Classic
## Notes-zhCN: 独立的怀旧服任务助手
## Notes-zhTW: 獨立的經典版任務助手
## Category: Quests
## Category-deDE: Quests
## Category-esES: Misiones
## Category-esMX: Misiones
## Category-frFR: Quêtes
## Category-itIT: Missioni
## Category-koKR: 퀘스트
## Category-ptBR: Missões
## Category-ruRU: Задания
## Category-zhCN: 任务
## Category-zhTW: 任務
## Version: 11.33.2
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
## SavedVariables: QuestieConfig
## SavedVariablesPerCharacter: QuestieConfigCharacter
## IconTexture: Interface\AddOns\Questie\Icons\questie.png
## X-Curse-Project-ID: 334372
## X-Wago-ID: qv634BKb
```

### 1.6 `Questie/Questie-Mists.toc` — header lines 1–30 verbatim

```
## Interface: 50503, 50504
## Title: Questie|cFF00FF00 v11.33.2|r
## Author: Aero/Logon/Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Everyone else
## Notes: A standalone Classic QuestHelper
## Notes-esES: Un asistente de misiones
## Notes-esMX: Un asistente de misiones
## Notes-frFR: Un assistant de quêtes
## Notes-ptBR: Um assistente de missões
## Notes-ruRU: Помощник по заданиям в WoW Classic
## Notes-zhCN: 独立的怀旧服任务助手
## Notes-zhTW: 獨立的經典版任務助手
## Category: Quests
## Category-deDE: Quests
## Category-esES: Misiones
## Category-esMX: Misiones
## Category-frFR: Quêtes
## Category-itIT: Missioni
## Category-koKR: 퀘스트
## Category-ptBR: Missões
## Category-ruRU: Задания
## Category-zhCN: 任务
## Category-zhTW: 任務
## Version: 11.33.2
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
## SavedVariables: QuestieConfig
## SavedVariablesPerCharacter: QuestieConfigCharacter
## IconTexture: Interface\AddOns\Questie\Icons\questie.png
## X-Curse-Project-ID: 334372
## X-Wago-ID: qv634BKb
```

**Key observation:** the five real headers are byte-identical EXCEPT line 1 (`## Interface:`).
Every other directive — Title, Author, Notes-*, Category-*, Version, RequiredDeps, OptionalDeps,
SavedVariables*, IconTexture, X-Curse-Project-ID, X-Wago-ID — is shared verbatim across all five.
That is the discipline QuestieTDB should mirror: **one canonical header template, one substituted
line per flavor.**

### 1.7 Body-section deltas per flavor (for completeness)

The body (file list) after the header is largely shared. Per-flavor differences that matter:

| Concern | Classic | BCC | WOTLKC | Cata | Mists |
| --- | --- | --- | --- | --- | --- |
| XP DB | `Database\QuestXP\DB\xpDB-classic.lua` | `xpDB-tbc.lua` | `xpDB-wotlk.lua` | `xpDB-cata.lua` | `xpDB-mop.lua` |
| Entity DB dir | `Database\Classic\classic{Item,Npc,Object,Quest}DB.lua` | `Database\TBC\tbc*DB.lua` | `Database\Wotlk\wotlk*DB.lua` | `Database\Cata\cata*DB.lua` | `Database\MoP\mop*DB.lua` |
| Faction template | `factionTemplateClassic.lua` | `factionTemplateTBC.lua` | `factionTemplateWotlk.lua` | `factionTemplateCata.lua` | `factionTemplateMoP.lua` |
| Lookup dir | `Localization\lookups\Classic\...` | `...\TBC\...` | `...\Wotlk\...` | `...\Cata\...` | `...\MoP\...` |
| Item drops | `classicItemDrops.lua` | `tbcItemDrops.lua` | `wotlkItemDrops.lua` | `cataItemDrops.lua` | `mopItemDrops.lua` **+ `cataItemDrops.lua`** (deliberate, commented) |
| Zones data | shared `Database\Zones\data\{areaIdToUiMapId,uiMapIdToAreaId}.lua` | same | same | same | `Database\Zones\data\MoP\areaIdToUiMapId.lua` and `MoP\uiMapIdToAreaId.lua` |
| Corrections stack | classic + SoD only | classic + tbc | classic + tbc + wotlk | classic + tbc + wotlk + cata | classic + tbc + wotlk + cata + mop |
| SoD-specific | `SeasonOfDiscovery.lua`, `sodBase*.lua`, `sod*Fixes.lua`, `HardcoreBlacklist.lua`, `AutoTableUpdates.lua` | `AutoTableUpdates.lua` | `AutoTableUpdates.lua` | — | — |

`Database\compiler.lua` is listed in ALL five (this is the file QuestieTDB replaces; see
`Questie/docs/adr/0001-questie-as-database-consumer.md:15`).

Mists-only note quoted verbatim from `Questie-Mists.toc:141-143`:

```
# this is not a mistake - we load cata pserver data for mop because mop pserver data is so spotty;
# if we implement mop pserver itemdrop data, we can remove this entry from mop toc
Database\DropTables\data\cataItemDrops.lua
```

---

## 2. Flavor mapping: Questie suffix → QuestieTDB modern underscore suffix

`QuestieTDB/DESIGN.md:229-244` fixes the target naming. Combined with the interface numbers found
in `Questie/*.toc`:

| Questie TOC (legacy hyphen suffix) | build.py flavor string | WOW_PROJECT_ID | QuestieTDB TOC (modern underscore suffix) | Interface (copy verbatim) |
| --- | --- | ---: | --- | --- |
| `Questie-Classic.toc` | `classic` | 2 | `QuestieTDB_Vanilla.toc` | `11508, 11509` |
| `Questie-BCC.toc` | `bcc` | 5 | `QuestieTDB_TBC.toc` | `20506` |
| `Questie-WOTLKC.toc` | `wrath` | 11 | `QuestieTDB_Wrath.toc` | `38000, 38001` |
| `Questie-Cata.toc` | `cata` | 14 | `QuestieTDB_Cata.toc` | `40402` |
| `Questie-Mists.toc` | `mists` | 19 | `QuestieTDB_Mists.toc` | `50503, 50504` |
| `Questie.toc` (fallback stub) | — | — | `QuestieTDB.toc` (**source mode**, committed) | source-mode value TBD; NOT `00000` |

`WOW_PROJECT_ID` values are from `Questie/Modules/Expansions.lua:6-20` and the CLI validators:

```lua
-- Questie/Modules/Expansions.lua:6-20
local expansionOrderLookup = {
    [2] = 1,
    [5] = 2,
    [11] = 3,
    [14] = 4,
    [19] = 5,
    -- [1] = 100000000, -- Retail is in the far future
}
Expansions.Current = expansionOrderLookup[WOW_PROJECT_ID or 2] -- If not found, default to classic(era)
-- Expansions.Retail = expansionOrderLookup[WOW_PROJECT_MAINLINE or 1]
Expansions.Era = expansionOrderLookup[WOW_PROJECT_CLASSIC or 2]
Expansions.Tbc = expansionOrderLookup[WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5]
Expansions.Wotlk = expansionOrderLookup[WOW_PROJECT_WRATH_CLASSIC or 11]
Expansions.Cata = expansionOrderLookup[WOW_PROJECT_CATACLYSM_CLASSIC or 14]
Expansions.MoP = expansionOrderLookup[WOW_PROJECT_MISTS_CLASSIC or 19]
```

Per `QuestieTDB/DESIGN.md:231-235` the flavor→TOC mapping including special clients:

```
| WoW Classic                                  | `QuestieTDB_Vanilla.toc` |
| Burning Crusade Classic, Classic Anniversary | `QuestieTDB_TBC.toc`     |
| Wrath Classic, **Titan Reforged**            | `QuestieTDB_Wrath.toc`   |
| Cataclysm Classic                            | `QuestieTDB_Cata.toc`    |
| Mists of Pandaria Classic                    | `QuestieTDB_Mists.toc`   |
| none of the above present                    | `QuestieTDB.toc` → source mode |
```

And `DESIGN.md:238-244`:

> Use these modern underscore suffixes. `-WOTLKC` and `-BCC` are recognised legacy forms and
> are what the prototypes emit, but there is no reason to start on deprecated names.
> `_Classic` and `_Mainline` are lower-priority catch-alls and are deliberately unused — a
> `_Classic` TOC would lose to `_Vanilla` anyway.
>
> Note `_Wrath` serves Titan Reforged as well as Wrath Classic, which Questie distinguishes at
> runtime through its own flag rather than through separate data.

---

## 3. `Questie/build.py` — per-flavor packaging

Full path: `/home/logon/projects/Questie-clones/Questie-toc/Questie/build.py` (8352 bytes, 244 lines).

### 3.1 CLI contract (docstring, build.py:10-41 verbatim)

```
"""
This program accepts optional command line options:

    -r
    --release
        Do not include commit hash in directory/zip/version names
    -a
    --all
        Included files for all expansions
    -c
    --classic
        Include Classic/Era files
    -t
    --tbc
        Include TBC files
    -w
    --wotlk
        Include WotLK files

    -ca
    --cata
        Include Cata files
        
    -m
    --mop
        Include MoP files

    -v <versionString>
    --version <versionString>
        Disregard git and toc versions, and use <versionString> instead

"""
```

### 3.2 Expansion index table (build.py:42-44)

```python
addonDir = "Questie"
includedExpansions = []
tocs = ["", "Questie-Classic.toc", "Questie-BCC.toc", "Questie-WOTLKC.toc", "Questie-Cata.toc", "Questie-Mists.toc"]
```

Index 0 is the empty string sentinel; expansion numbers are **1-based**: 1=Classic, 2=TBC/BCC,
3=WotLK, 4=Cata, 5=MoP/Mists.

### 3.3 Default expansion set (build.py:82-87) — **Cata is excluded by default**

```python
    if len(includedExpansions) == 0:
        # If expansions go online/offline their major version needs to be added/removed here
        includedExpansions.append(1)
        includedExpansions.append(2)
        includedExpansions.append(3)
        includedExpansions.append(5)
```

`4` (Cata) is deliberately absent. `python build.py` with no args ships Classic+TBC+Wrath+Mists
only. `--all` (build.py:61-71) appends 1,2,3,4,5.

### 3.4 ignorePatterns / expansionStrings / copy logic — build.py:177-197 VERBATIM

```python
directoriesToInclude = ["Database", "Icons", "Libs", "Localization", "Modules", "Public"]
filesToInclude = ["Bindings.xml", "embeds.xml", "Questie.lua", "Questie.toc", "README.md", "README_ES.md", "README_CN.md"]
expansionStrings = ["", "Classic", "TBC", "Wotlk", "Cata", "MoP"]
ignorePatterns = ["*.test.lua"]


def copy_content_to(release_folder_path):
    for i in [1, 2, 3, 4, 5]:
        if i in includedExpansions:
            filesToInclude.append(tocs[i])
        else:
            ignorePatterns.append(f"{expansionStrings[i]}")

    for _, directories, files in os.walk("."):
        for directory in directories:
            if directory in directoriesToInclude:
                shutil.copytree(directory, "%s/%s" % (release_folder_path, directory), ignore=shutil.ignore_patterns(*ignorePatterns))
        for file in files:
            if file in filesToInclude:
                shutil.copy2(file, "%s/%s" % (release_folder_path, file))
        break
```

How this actually works:

- `shutil.ignore_patterns(*ignorePatterns)` fnmatches **basenames**. `"Classic"` therefore matches
  ONLY entries named exactly `Classic` — i.e. the directories `Database/Classic` and
  `Localization/lookups/Classic`. Verified those exist:
  - `Questie/Database/` contains: `Cata Classic Corrections DropTables FactionTemplates MoP QuestXP TBC Wotlk Zones` (+ loose .lua)
  - `Questie/Localization/lookups/` contains: `Cata Classic MoP TBC Wotlk` (+ loose .lua)
- It does **not** strip `Database/QuestXP/DB/xpDB-classic.lua`, `Database/Corrections/classic*Fixes.lua`,
  or `Database/DropTables/data/classicItemDrops.lua` — those are dead weight in a non-Classic build.
  Deliberate/accepted: the excluded TOC never references them.
- `*.test.lua` is always excluded (unit tests never ship).
- `os.walk(".")` + `break` = **single top-level pass only** (no recursion); only the six whitelisted
  top-level dirs are copied wholesale, and only the whitelisted top-level files.
- Consequence: `cli/`, `.github/`, `.types/`, `WoW-API/`, `ExternalScripts(DONOTINCLUDEINRELEASE)/`,
  `docs/`, `build.py`, `changelog.py`, `release.py`, `.luacheckrc`, `setupTests.lua`,
  `Questie.test.lua`, `Questie logo.png` are all excluded by omission, not by pattern.
- `Questie.toc` (the unsupported-client stub) is in `filesToInclude` unconditionally.

### 3.5 Interface extraction — build.py:231-234 VERBATIM

```python
def get_interface_versions(expansion="Classic"):
    with open("Questie-%s.toc" % expansion, "r") as toc:
        match = re.match("## Interface: (.*?)\n", toc.read(), re.DOTALL)
        return [v.strip() for v in match.group(1).split(",")]
```

- Reads relative to CWD → **build.py must be run from the repo root.**
- Requires `## Interface:` to be **line 1** (`re.match`, anchored at position 0).
- Splits on comma and strips → `"11508, 11509"` → `["11508", "11509"]`.
- Called at build.py:114-118 as:
  ```python
    interface_classic = get_interface_versions()
    interface_bcc = get_interface_versions("BCC")
    interface_wotlk = get_interface_versions("WOTLKC")
    interface_cata = get_interface_versions("Cata")
    interface_mop = get_interface_versions("Mists")
  ```
  Note **all five are read unconditionally**, even when the expansion is not in `includedExpansions`
  — so every TOC must exist and be parseable regardless of the selected flavors.

### 3.6 `release.json` generation — build.py:120-152 VERBATIM (includes `"nolib"`)

```python
    def flavor_entries(flavor, versions):
        result = ""
        for v in versions:
            result += """
                {
                    "flavor": "%s",
                    "interface": %s
                },""" % (flavor, v)
        return result

    flavorString = ""
    if 1 in includedExpansions:
        flavorString += flavor_entries("classic", interface_classic)
    if 2 in includedExpansions:
        flavorString += flavor_entries("bcc", interface_bcc)
    if 3 in includedExpansions:
        flavorString += flavor_entries("wrath", interface_wotlk)
    if 4 in includedExpansions:
        flavorString += flavor_entries("cata", interface_cata)
    if 5 in includedExpansions:
        flavorString += flavor_entries("mists", interface_mop)

    with open(release_folder_path + "/release.json", "w") as rf:
        rf.write("""{
    "releases": [
        {
            "filename": "%s.zip",
            "nolib": false,
            "metadata": [%s
            ]
        }
    ]
}""" % (zip_name, flavorString[:-1]))
```

Facts:
- Flavor strings are exactly `"classic"`, `"bcc"`, `"wrath"`, `"cata"`, `"mists"` (CurseForge/Wago
  `release.json` vocabulary).
- **One metadata entry per interface number**, not per flavor — `11508, 11509` yields two `classic`
  entries.
- `"nolib": false` is hard-coded, sibling of `"filename"`. `DESIGN.md:498` calls this out as the
  CurseForge mechanism that lets a standalone QuestieTDB installer avoid a folder collision with
  the copy bundled inside Questie's zip.
- `flavorString[:-1]` strips the trailing comma — the JSON is assembled by string concatenation, so
  an empty `includedExpansions` would produce `"metadata": []`-with-mangled-brace. Not reachable in
  practice (the default set is non-empty).

Example of the emitted shape for a default (`1,2,3,5`) build with today's interface numbers:

```json
{
    "releases": [
        {
            "filename": "Questie-v11.33.2.zip",
            "nolib": false,
            "metadata": [
                {
                    "flavor": "classic",
                    "interface": 11508
                },
                {
                    "flavor": "classic",
                    "interface": 11509
                },
                {
                    "flavor": "bcc",
                    "interface": 20506
                },
                {
                    "flavor": "wrath",
                    "interface": 38000
                },
                {
                    "flavor": "wrath",
                    "interface": 38001
                },
                {
                    "flavor": "mists",
                    "interface": 50503
                },
                {
                    "flavor": "mists",
                    "interface": 50504
                }
            ]
        }
    ]
}
```

### 3.7 Version-dir naming — build.py:157-174 VERBATIM

```python
def get_version_dir(is_release_build, versionOverride):
    version, nr_of_commits, recent_commit = get_git_information()
    if versionOverride != "":
        version = versionOverride
    print("Tag: " + version)
    if is_release_build:
        release_dir = "%s" % version
    else:
        release_dir = "%s-%s" % (version, recent_commit)

    print("Number of commits since tag: " + nr_of_commits)
    print("Most Recent commit: " + recent_commit)
    branch = get_branch()
    if branch != "master" and branch != "HEAD":
        release_dir += "-%s" % branch
    print("Current branch: " + branch)

    return release_dir
```

- Output layout: `releases/<release_dir>/Questie/...` plus `releases/<release_dir>/release.json`
  and `releases/<release_dir>/Questie-<release_dir>.zip`.
- `get_git_information()` (build.py:208-219) runs `git describe --tags --long` and rsplits on `-`
  twice: `v11.33.2-14-gabc1234` → tag `v11.33.2`, 14 commits, `abc1234` (leading `g` stripped).
- Zip: `shutil.make_archive(zip_name, "zip", ".", addon_dir)` from inside `releases/<dir>`
  (build.py:200-205) — so the zip root contains a single `Questie/` folder.
- `releases/` is gitignored (`Questie/.gitignore`).

### 3.8 `Questie/release.py` — version bump helper (full file, 49 lines)

```python
#!/usr/bin/env python3

import changelog  # Our own changelog.py
import fileinput
import subprocess
import sys

if not len(sys.argv) > 1:
    print('Needs new version number provided as argument')
    exit()

version = sys.argv[1]

if version[0] == "v":
    print('Please omit the "v" prefix. The script will add it')
    exit()

tocs = ['Questie-Classic.toc', 'Questie-BCC.toc', 'Questie-WOTLKC.toc', 'Questie-Cata.toc', 'Questie-Mists.toc']

for toc in tocs:
    with fileinput.FileInput(toc, inplace=True) as file:
        for line in file:
            if line[:10] == '## Version':
                print('## Version: ' + version)
            elif line[:8] == '## Title':
                print('## Title: Questie|cFF00FF00 v' + version + '|r')
            else:
                print(line, end='')

readmes = ['README.md', 'README_CN.md', 'README_ES.md']
for readme in readmes:
    with fileinput.FileInput(readme, inplace=True) as file:
        for line in file:
            if line[:20] == '[![Downloads Latest]':
                print('[![Downloads Latest](https://img.shields.io/github/downloads/Questie/Questie/v' + version + '/total.svg)](https://github.com/Questie/Questie/releases/latest)')
            else:
                print(line, end='')

changelogString = changelog.get_commit_changelog(True)

print('######### START CHANGELOG')
print('# Questie v' + version + '\n\n' + changelogString)
print('######### END CHANGELOG')

subprocess.run(['git', 'add', 'README.md', 'README_CN.md', 'README_ES.md'])
subprocess.run(['git', 'add', '*.toc'])
subprocess.run(['git', 'commit', '-mBump version to v' + version])
subprocess.run(['git', 'tag', 'v' + version])
```

So: `python release.py 11.33.3` rewrites `## Version` **and** `## Title` in all five real TOCs,
bumps README badges, commits, and tags `v11.33.3`. The tag push then triggers `publish.yml`.

### 3.9 `Questie/changelog.py` — changelog from commit prefixes

Key table (changelog.py:7-13):

```python
commit_keys_and_header = (
    ('feature', '## New Features\n\n'),
    ('fix', '## General Fixes\n\n'),
    ('quest', '## Quest Fixes\n\n'),
    ('db', '## Database Fixes\n\n'),
    ('locale', '## Localization Fixes\n\n'),
)
```

- Commit prefixes `[feature] [fix] [quest] [db] [locale]` (also capitalized forms, changelog.py:80).
- Beta detection: a tag containing `-b` is treated as a beta; the diff base then walks back one tag
  (`{latest_tag}^`), else `git describe --tags --abbrev=0 --exclude "*-b*" HEAD^` (changelog.py:42-53).
- `transform_lines_into_past_tense` maps Add→Added, Fix→Fixed, Mark→Marked, Improve→Improved,
  Change→Changed, Update→Updated, Blacklist→Blacklisted, Remove→Removed (changelog.py:118-127).
- Contributors section is suppressed inside GitHub Actions (`is_running_in_github_actions()`,
  changelog.py:20-22, 152).

---

## 4. `Questie/.github/workflows/` — every file

Exactly three workflow files:

| File | Bytes | Trigger |
| --- | ---: | --- |
| `ci.yml` | 3055 | `workflow_call`, `push` on `**`, `pull_request` (opened/synchronize/reopened) |
| `publish.yml` | 1825 | `push` tags `v*` |
| `issue_labeler.yml` | 533 | `issues` (opened, edited) |

Plus non-workflow `.github` files: `dependabot.yml`, `labeler.yml`, `pull_request_template.md`,
`ISSUE_TEMPLATE/{bug_report,config,feature_request,quest_issue,question}.yml`.

### 4.1 `publish.yml` — QUOTED IN FULL (this is the release/packaging workflow)

```yaml
name: Publish

on:
  push:
    tags:
      - 'v*'

jobs:
  tests:
    uses: './.github/workflows/ci.yml'
    with:
      event_name: ${{ github.event_name }}
      repo_full_name: ${{ github.repository }}
  publish:
    runs-on: ubuntu-latest
    needs: [ tests ]

    env:
      GH_TOKEN: ${{ github.token }}
      CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}

    steps:
      - name: Clone project
        uses: actions/checkout@v7.0.0
        with:
          fetch-depth: 100

      - name: Fetch tags
        run: git fetch --prune --unshallow --tags

      - name: Generate Changelog
        id: changelog
        run: python changelog.py >> CHANGELOG.md

      - name: Build ZIP
        run: python build.py -r

      - name: Create GitHub release
        run: |
          if [[ "${{github.ref_name}}" == *"-b"* ]]; then
            gh release create ${{github.ref_name}} \
              --verify-tag \
              --prerelease \
              -F CHANGELOG.md \
              releases/${{github.ref_name}}/Questie-${{github.ref_name}}.zip \
              releases/${{github.ref_name}}/release.json
          else
            gh release create ${{github.ref_name}} \
              --verify-tag \
              -F CHANGELOG.md \
              releases/${{github.ref_name}}/Questie-${{github.ref_name}}.zip \
              releases/${{github.ref_name}}/release.json
          fi

      - name: Upload CurseForge
        run: sh upload-cf.sh ${{github.ref_name}}

      - name: Upload WAGO
        run: sh upload-wago.sh ${{github.ref_name}}

      - name: Send CI failure to Discord
        uses: nebularg/actions-discord-webhook@v1.0.0
        with:
          webhook_url: ${{ secrets.DISCORD_WEBHOOK }}
          status: ${{ job.status }}
        if: ${{ failure() }}
```

Summary of `publish`:
- **Trigger:** push of any tag matching `v*`.
- **Job `tests`:** reuses `ci.yml` via `uses:` (workflow_call). `publish` `needs: [tests]`.
- **Job `publish` steps:** checkout (depth 100) → `git fetch --prune --unshallow --tags` →
  `python changelog.py >> CHANGELOG.md` → `python build.py -r` (release build: no commit hash in
  names; default flavors 1,2,3,5) → `gh release create` with `--prerelease` iff the tag contains
  `-b` → uploads `Questie-<tag>.zip` **and** `release.json` as GitHub release assets →
  `sh upload-cf.sh <tag>` → `sh upload-wago.sh <tag>` → Discord webhook on failure.
- **Artifacts uploaded:** `releases/<tag>/Questie-<tag>.zip`, `releases/<tag>/release.json`
  (GitHub Release); the same zip to CurseForge project 334372 and Wago project `qv634BKb`.

### 4.2 `ci.yml` — QUOTED IN FULL

```yaml
name: CI

on:
  workflow_call:
    inputs:
      event_name:
        required: true
        type: string
      repo_full_name:
        required: true
        type: string
  push:
    branches:
      - '**'
  pull_request:
    types:
      - opened
      - synchronize
      - reopened

jobs:
  luacheck:
    runs-on: ubuntu-latest
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name != github.event.pull_request.base.repo.full_name

    steps:
      - name: Checkout project
        uses: actions/checkout@v7.0.0

      - name: Run Luacheck
        uses: nebularg/actions-luacheck@v1.1.2
        with:
          files: Database Localization Modules Public Questie.lua
          args: -q

  unit-tests:
    runs-on: ubuntu-latest
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name != github.event.pull_request.base.repo.full_name
    env:
      TZ: Europe/Berlin

    steps:
      - name: Checkout project
        uses: actions/checkout@v7.0.0

      - name: Install Lua
        uses: leafo/gh-actions-lua@v13.0.0
        with:
          luaVersion: "5.1"

      - name: Install luarocks packages
        uses: leafo/gh-actions-luarocks@v6.1.0
        with:
          luaRocksVersion: "3.13.0"

      - name: Install test dependencies
        run: |
          luarocks install bit32 5.3.5.1-1
          luarocks install busted 2.2.0-1
          luarocks install luafilesystem 1.8.0-1

      - name: Run busted Unit Tests
        run: busted -p ".test.lua" .

  db-validation:
    runs-on: ubuntu-latest
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name != github.event.pull_request.base.repo.full_name
    env:
      TZ: Europe/Berlin
    strategy:
      matrix:
        expansion: [era, sod, tbc, wotlk, mop, localization]
      fail-fast: false

    steps:
      - name: Checkout project
        uses: actions/checkout@v7.0.0

      - name: Install Lua
        uses: leafo/gh-actions-lua@v13.0.0
        with:
          luaVersion: "5.1"

      - name: Install luarocks packages
        uses: leafo/gh-actions-luarocks@v6.1.0
        with:
          luaRocksVersion: "3.13.0"

      - name: Install dependencies
        run: |
          luarocks install bit32 5.3.5.1-1
          luarocks install luafilesystem 1.8.0-1

      - name: Validate ${{ matrix.expansion }} database
        run: lua cli/validate-${{ matrix.expansion }}.lua

      - name: Upload correction files
        uses: actions/upload-artifact@v7.0.1
        with:
          name: correction-files-${{ matrix.expansion }}
          path: cli/output/
        if: success() || failure()

  notify:
    runs-on: ubuntu-latest
    needs: [luacheck, unit-tests, db-validation]
    if: failure()

    steps:
      - name: Checkout project
        uses: actions/checkout@v7.0.0

      - name: Send CI failure to Discord
        uses: nebularg/actions-discord-webhook@v1.0.0
        with:
          webhook_url: ${{ secrets.DISCORD_WEBHOOK }}
          status: failure
```

Job-by-job:

| Job | Runs | Uploads |
| --- | --- | --- |
| `luacheck` | `nebularg/actions-luacheck@v1.1.2`, `files: Database Localization Modules Public Questie.lua`, `args: -q` | — |
| `unit-tests` | Lua 5.1 + luarocks 3.13.0; installs `bit32 5.3.5.1-1`, `busted 2.2.0-1`, `luafilesystem 1.8.0-1`; runs `busted -p ".test.lua" .` with `TZ: Europe/Berlin` | — |
| `db-validation` | matrix `[era, sod, tbc, wotlk, mop, localization]`, `fail-fast: false`; `lua cli/validate-${{ matrix.expansion }}.lua` | `actions/upload-artifact@v7.0.1`, name `correction-files-<expansion>`, path `cli/output/`, `if: success() || failure()` |
| `notify` | `needs: [luacheck, unit-tests, db-validation]`, `if: failure()` → Discord webhook | — |

Notes:
- **`cata` is NOT in the db-validation matrix** even though `cli/validate-cata.lua` exists —
  consistent with Cata being excluded from build.py's default expansion set.
- The `if:` guard on the three real jobs skips them for PRs originating from **the same repo**
  (they already ran via the `push` trigger) — the condition is
  `github.event_name != 'pull_request' || head.repo.full_name != base.repo.full_name`.
- The `workflow_call` inputs `event_name` / `repo_full_name` are declared but **never referenced**
  in the job bodies (the `if:` expressions use `github.*` directly). Harmless but dead.

### 4.3 `issue_labeler.yml` — QUOTED IN FULL

```yaml
name: "Issue Labeler"
on:
  issues:
    types: [opened, edited]

permissions:
  issues: write
  contents: read

jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7.0.0
        with:
          sparse-checkout: .github/labeler.yml
          sparse-checkout-cone-mode: false

      - uses: github/issue-labeler@v3.4
        with:
          configuration-path: .github/labeler.yml
          not-before: 2024-10-01T00:00:00Z
          enable-versioned-regex: 0
          repo-token: ${{ github.token }}
```

`.github/labeler.yml` (regex → label) maps the issue-form "Game flavor" dropdown to labels:
`era/hc`, `anniversary`, `Season of Discovery`, `tbc`, `wotlk`, `cata`, `mop`.
The dropdown options in `ISSUE_TEMPLATE/bug_report.yml` are: `Era/HC`, `Season of Discovery`,
`TBC`, `WotLK`, `Cata`, `MoP`.

### 4.4 Upload scripts referenced by publish.yml

`Questie/upload-cf.sh` (full):

```sh
#!/bin/sh

LATEST_GIT_TAG="$1"
CHANGELOG=$(jq --slurp --raw-input '.' < "CHANGELOG.md")

if echo "$LATEST_GIT_TAG" | grep -q "^.*-b.*$"; then
  RELEASE_TYPE="beta"
else
  RELEASE_TYPE="release"
fi

echo "Uploading $RELEASE_TYPE $LATEST_GIT_TAG to CurseForge"

#### CurseForge Upload
# Docs: https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api

# We get the "gameVersions" by doing an authenticated GET to https://wow.curseforge.com/api/game/versions
# You can do so by opening the API in your browser and manually add the X-API-TOKEN Header with an API-Token to the request (https://authors-old.curseforge.com/account/api-tokens).
# Check the answer for the required version (e.g. name = "1.14.4") and take the "id" field for the gameVersions.

# The order of the "gameVersions" below is: WotLK (3.80.1), Era/SoD, TBC, MoP
CF_METADATA=$(cat <<-EOF
{
    "displayName": "$LATEST_GIT_TAG",
    "releaseType": "$RELEASE_TYPE",
    "changelog": $CHANGELOG,
    "changelogType": "markdown",
    "gameVersions": [16081, 16630, 16533, 16168],
    "relations": {
        "projects": [
            {slug: "Ace3", type: "embeddedLibrary"},
            {slug: "CallbackHandler", type: "embeddedLibrary"},
            {slug: "HereBeDragons", type: "embeddedLibrary"},
            {slug: "LibCompress", type: "embeddedLibrary"},
            {slug: "LibDataBroker-1-1", type: "embeddedLibrary"},
            {slug: "LibDBIcon-1-0", type: "embeddedLibrary"},
            {slug: "LibSharedMedia-3-0", type: "embeddedLibrary"},
            {slug: "LibStub", type: "embeddedLibrary"},
            {slug: "LibUIDropDownMenu", type: "embeddedLibrary"}
        ]
    }
}
EOF
)

response=$(curl -sS \
    -o response.txt \
    -w "%{http_code}" \
    -H "X-API-TOKEN: $CF_API_TOKEN" \
    -F "metadata=$CF_METADATA" \
    -F "file=@releases/$LATEST_GIT_TAG/Questie-$LATEST_GIT_TAG.zip" \
    "https://wow.curseforge.com/api/projects/334372/upload-file")

http_status=$(echo "$response" | tail -n1)

if [ "$http_status" -eq 200 ]; then
  echo "CurseForge upload successful"
else
  echo "CurseForge upload failed, HTTP-code: $http_status"
  cat response.txt
  exit 1
fi
```

`Questie/upload-wago.sh` (full):

```sh
#!/bin/sh

LATEST_GIT_TAG="$1"
CHANGELOG=$(jq --slurp --raw-input '.' < "CHANGELOG.md")

if echo "$LATEST_GIT_TAG" | grep -q "^.*-b.*$"; then
  RELEASE_TYPE="beta"
else
  RELEASE_TYPE="stable"
fi

echo "Uploading $RELEASE_TYPE $LATEST_GIT_TAG to Wago"

### WAGO Upload
# Docs: https://docs.wago.io/#introduction

WAGO_METADATA=$(cat <<-EOF
{
   "label": "$LATEST_GIT_TAG",
   "stability": "$RELEASE_TYPE",
   "changelog": $CHANGELOG,
   "supported_classic_patch": "1.15.9",
   "supported_bc_patch": "2.5.6",
   "supported_wotlk_patch": "3.80.1",
   "supported_mop_patch": "5.5.4"
}
EOF
)

response=$(curl -sS \
    -o response.txt \
    -w "%{http_code}" \
    -H "authorization: Bearer $WAGO_API_TOKEN" \
    -H "accept: application/json" \
    -F "metadata=$WAGO_METADATA" \
    -F "file=@releases/$LATEST_GIT_TAG/Questie-$LATEST_GIT_TAG.zip" \
    "https://addons.wago.io/api/projects/qv634BKb/version")

http_status=$(echo "$response" | tail -n1)

if [ "$http_status" -eq 201 ]; then
  echo "Wago upload successful"
else
  echo "Wago upload failed, HTTP-code: $http_status"
  cat response.txt
  exit 1
fi
```

Note the release-type vocabulary differs: CurseForge uses `beta`/`release`; Wago uses
`beta`/`stable`. Both key off `-b` in the tag. Neither script mentions Cata.

### 4.5 Docker fallback for local validation

`Questie/.dockerfiles/Dockerfile`:
```
FROM nickblah/lua:5.1-luarocks

RUN apt-get update && apt-get install -y git gcc && luarocks install bit32
```
`Questie/.dockerfiles/docker-compose.yml` mounts `../` at `/code` and runs `setup.sh`, which is:
```bash
cd code
lua ./cli/validate-era.lua
lua ./cli/validate-sod.lua
lua ./cli/validate-tbc.lua
lua ./cli/validate-wotlk.lua
```
(stale: missing mop/cata/localization).

`Questie/.vscode/tasks.json` defines a default build task running `python.exe build.py`.

---

## 5. Dependency declarations in TOC

### 5.1 What Questie actually uses TODAY

Two directives, both present in all five real TOCs at **lines 24 and 25**:

```
## RequiredDeps:
## OptionalDeps: Ace3, CallbackHandler-1.0, HereBeDragons, Krowi_WorldMapButtons, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibStub, LibUIDropDownMenu
```

- `## RequiredDeps:` is present but **empty** — a placeholder. Questie currently declares NO hard
  dependency on any addon.
- `## OptionalDeps:` is a **comma+space separated** list, 9 entries, alphabetically ordered.
  Exact entries (verbatim, in order):
  1. `Ace3`
  2. `CallbackHandler-1.0`
  3. `HereBeDragons`
  4. `Krowi_WorldMapButtons`
  5. `LibDataBroker-1.1`
  6. `LibDBIcon-1.0`
  7. `LibSharedMedia-3.0`
  8. `LibStub`
  9. `LibUIDropDownMenu`
- **`## Dependencies:` does NOT appear anywhere in any `.toc` in this workspace.** Verified by grep
  across `Questie/`, `Getters/`, `toc-database/`, `QuestieTDB/`. The only hits for the literal token
  are prose in docs and the Blizzard API annotation `C_AddOns.GetAddOnDependencies`.
- `## Dependencies:` and `## RequiredDeps:` are synonyms in the WoW TOC parser. Questie picked
  `RequiredDeps`; the ADR and DESIGN prose say `Dependencies`. **Pick one and be consistent.**

### 5.2 What is PLANNED

`Questie/docs/adr/0001-questie-as-database-consumer.md:12-13`:

> - Questie declares a hard `## Dependencies` on QuestieTDB. The client covers absence; a
>   contract-version check in Questie covers "present but incompatible".

`QuestieTDB/DESIGN.md:22`:

> | Dependency | Hard `## Dependencies: QuestieTDB`. The client's red warning covers absence; the contract version covers mismatch. |

`QuestieTDB/DESIGN.md:332` (third-party correction addons):

> `## Dependencies: Questie` and therefore register *after* Questie has already applied.

`QuestieTDB/DESIGN.md:418`:

> Independent release cycles make skew inevitable. The hard `## Dependencies` covers *absence*;

**Concrete syntax to write into Questie's five TOCs when the cut happens:**

```
## Dependencies: QuestieTDB
```
or, keeping Questie's existing directive name:
```
## RequiredDeps: QuestieTDB
```
Multiple deps use the same `, `-separated form as `OptionalDeps`.

### 5.3 What the prototypes emit

`toc-database/generate.lua:25-33` — `writeHeader` (VERBATIM):

```lua
local function writeHeader(out, version, addonName, notes, optionalDeps)
  out:write("## Interface: ", version.interface, "\n")
  out:write("## Title: ", addonName, "\n")
  out:write("## Author: Logon (Data: VibeQuest exporter)\n")
  out:write("## Notes: ", notes, "\n")
  out:write("## Version: 0.0.0\n")
  if optionalDeps then out:write("## OptionalDeps: ", optionalDeps, "\n") end
  out:write("## X-BUILD-COMMIT: ", BUILD.commit, "\n")
  out:write("## X-BUILD-TIME: ", BUILD.time, "\n\n")
end
```

`Getters/generate.lua:31-42` is the same shape (Author string differs, `optionalDeps` guarded by
`if optionalDeps then`). Only `OptionalDeps` is ever emitted; no `Dependencies`/`RequiredDeps`.

Generated example — `toc-database/{ItemDB}/{ItemDB}-Vanilla.toc` header:

```
## Interface: 11508
## Title: {ItemDB}
## Author: Logon (Data: VibeQuest exporter)
## Notes: A standalone VibeQuest database
## Version: 0.0.0
## OptionalDeps: {l10n}
## X-BUILD-COMMIT: baae6f467c035ddc7ca95ab5d2845c92ff24fdc8
## X-BUILD-TIME: 2026-05-16T18:45:15Z

Get.lua

## X-Manifest-1: {["contractVersion"]=1,["entityCounts"]={...},["files"]={...},["majorVersion"]=1,["producer"]="exporters.vibequest"}
## X-25-1: Worn Shortsword
## X-25-9: 2
...
```

`toc-database/{SupportDB}/{SupportDB}-Vanilla.toc` (no metadata rows; loads versioned Lua files):

```
## Interface: 11508
## Title: {SupportDB}
## Author: Logon (Data: VibeQuest exporter)
## Notes: VibeQuest support databases
## Version: 0.0.0
## X-BUILD-COMMIT: 1912ab257977ba54505724524166a84f9872e8b3
## X-BUILD-TIME: 2026-05-16T19:26:17Z

areaToUiMapDB-Vanilla.lua
zoneOrSortDB-Vanilla.lua
eventQuestDB-Vanilla.lua
dungeonLookupDB-Vanilla.lua
mapIdToUiMapDB-Vanilla.lua
professionMetaDB-Vanilla.lua
```

`Getters/{Database}/{Database}-Vanilla.toc` (the richer prototype's combined addon):

```
## Interface: 11508
## Title: {Database}
## Author: Logon (Data: TheCrux/Drejjmit/Muehe/Yttrium/TechnoHunter/Everyone else)
## Notes: Combined standalone databases
## Version: 0.0.0
## X-BUILD-COMMIT: a4bf4f1452471063dbee95fdaf50fd79f4e42302
## X-BUILD-TIME: 2026-07-27T17:31:03Z

l10n.lua
Item.lua
Npc.lua
Object.lua
Quest.lua

## X-Item-25-1: Worn Shortsword
## X-Item-25-7: 0;0;2;1;0;2;7
...
```

Structural facts worth mirroring:
- `X-BUILD-COMMIT` (40-hex, or 40 zeros when git is unavailable) and `X-BUILD-TIME`
  (`os.date("!%Y-%m-%dT%H:%M:%SZ")`, UTC ISO-8601) are emitted by both prototypes.
- Metadata rows appear **after** the file list; WoW's parser tolerates `##` lines interleaved after
  file entries.
- The combined addon prefixes keys (`X-Item-25-1`) vs the split addon's bare `X-25-1`.
- `toc-database` also writes an `X-Manifest-1` row carrying `contractVersion`, `entityCounts`,
  `files`, `majorVersion`, `producer`.

---

## 6. `toc-database` prototype: LOCAL.bat, entry points, and `test.lua`

### 6.1 `toc-database/LOCAL.bat` — QUOTED IN FULL (19 lines)

```bat
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{ItemDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ItemDB}"
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{NpcDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{NpcDB}"
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{ObjectDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ObjectDB}"
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{QuestDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{QuestDB}"
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{l10n}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{l10n}"
@REM mklink /J "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\{Database}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{Database}"
@REM mklink /J "D:\Projekt\Questwo\AddOns\{ItemDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ItemDB}"
@REM mklink /J "D:\Projekt\Questwo\AddOns\{NpcDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{NpcDB}"
@REM mklink /J "D:\Projekt\Questwo\AddOns\{ObjectDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ObjectDB}"
@REM mklink /J "D:\Projekt\Questwo\AddOns\{QuestDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{QuestDB}"
@REM mklink /J "D:\Projekt\Questwo\AddOns\{l10n}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{l10n}"



@REM mklink /J "D:\Projekt\Questwo-gemini\AddOns\{ItemDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ItemDB}"
@REM mklink /J "D:\Projekt\Questwo-gemini\AddOns\{NpcDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{NpcDB}"
@REM mklink /J "D:\Projekt\Questwo-gemini\AddOns\{ObjectDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{ObjectDB}"
@REM mklink /J "D:\Projekt\Questwo-gemini\AddOns\{QuestDB}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{QuestDB}"
@REM mklink /J "D:\Projekt\Questwo-gemini\AddOns\{l10n}" "C:\Games\World of Warcraft\_classic_era_\Interface\AddOns\Getters\{l10n}"
```

Line layout: lines 1-11 are the first block (6 `_classic_era_` junctions + 5 `D:\Projekt\Questwo`
junctions), lines 12-14 are blank, lines 15-19 are the `Questwo-gemini` block
(`{ItemDB} {NpcDB} {ObjectDB} {QuestDB} {l10n}`). 19 lines total, no trailing newline.

**IMPORTANT — every line is commented out with `@REM`. The file executes nothing.** It is a
copy-paste crib sheet of Windows `mklink /J` (directory junction) commands for wiring the generated
addon folders into a live WoW `Interface\AddOns` tree. It is byte-identical to `Getters/LOCAL.bat`
(`diff` returns no differences).

For QuestieTDB the equivalent is a single junction:
`mklink /J "<WoW>\Interface\AddOns\QuestieTDB" "<repo>\QuestieTDB"` — and per `DESIGN.md:253-256`,
"A fresh clone junctioned into `AddOns` is a working development environment with **no download and
no Lua toolchain**."

### 6.2 Generation entry points

`toc-database/` (5 Lua entry points at repo root):

| File | Bytes | Role |
| --- | ---: | --- |
| `main.lua` | 1997 | one-command runner: refresh → generate → verify → test |
| `git.lua` | 3662 | sparse-clones `VibesQuest/Exporter` into `data/` |
| `generate.lua` | 14242 | data → generated addon folders + `.toc` |
| `verify.lua` | 8958 | round-trip verification against generated metadata |
| `test.lua` | 11233 | end-to-end decoder test with mocked WoW API |

`Getters/` has `generate.lua` (15372), `verify.lua` (12043), `test.lua` (15601), `LOCAL.bat`,
`README.md` — **no `main.lua`, no `git.lua`.** The one-command runner exists only in `toc-database`.

#### `toc-database/main.lua` — QUOTED IN FULL (71 lines)

```lua
-- main.lua
-- One-command runner: refresh exporter output, generate addons, verify, then run runtime tests.

local git = require("git")
local config = dofile("src/config.lua")

local lua = os.getenv("LUA") or "lua"
local target = "all"
local verify = true
local test = true

for _, value in ipairs(arg or {}) do
  if value == "--no-verify" then
    verify = false
  elseif value == "--no-test" then
    test = false
  elseif value == "--verify" then
    verify = true -- kept for compatibility; verify is on by default
  elseif value == "--test" then
    test = true -- kept for explicitness; test is on by default
  elseif value:match("^%-%-lua=") then
    lua = value:match("^%-%-lua=(.+)$")
  elseif value ~= "" then
    target = value
  end
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(cmd)
  print("+ " .. cmd)
  local ok, _, code = os.execute(cmd)
  if ok == true or ok == 0 then return end
  if type(ok) == "number" then code = ok end
  error("Command failed" .. (code and (" with code " .. tostring(code)) or "") .. ": " .. cmd)
end

local function runVerify()
  if not verify then return end
  run(shellQuote(lua) .. " verify.lua " .. shellQuote(target))
end

local function runTestsForMode(mode)
  for _, version in ipairs(config.versions) do
    run(shellQuote(lua) .. " test.lua " .. shellQuote(version.suffix) .. " " .. shellQuote(mode))
  end
end

local function runTests()
  if not test then return end

  if target == "all" then
    runTestsForMode("split")
    runTestsForMode("combined")
    runTestsForMode("support")
  elseif target == "combined" then
    runTestsForMode("combined")
  elseif target == "SupportDB" then
    runTestsForMode("support")
  else
    print("Skipping runtime tests for target " .. target .. ": test.lua currently requires all split entity addons.")
  end
end

git.refreshExporterOutput()
run(shellQuote(lua) .. " generate.lua " .. shellQuote(target))
runVerify()
runTests()
```

Documented invocations (from `toc-database/README.md`):

```sh
lua main.lua               # refresh data/ + generate all + verify all + test split/combined/support
lua main.lua Item          # refresh data/ + generate one split entity DB for v1/v2/v3 + verify it
lua main.lua l10n          # refresh data/ + generate l10n addon + verify it
lua main.lua SupportDB     # refresh data/ + generate SupportDB + verify it + test support mode
lua main.lua combined      # refresh data/ + generate combined + verify it + test combined mode
lua main.lua --no-test     # refresh data/ + generate all + verify all, but skip runtime tests
lua main.lua --no-verify   # refresh data/ + generate all + test, but skip round-trip verification

lua git.lua                # refresh data/ only
lua generate.lua all       # generate only; assumes data/ exists
lua generate.lua Item|Npc|Object|Quest|l10n|SupportDB|combined
```

`git.lua` refresh (`git.refreshExporterOutput`, git.lua:95-117) does:
```
rm -rf data
git clone --filter=blob:none --sparse --no-checkout --no-tags --depth=1 --single-branch -b main <exporterUrl> data
cd data && git sparse-checkout set --no-cone output
cd data && git checkout
rm -rf data/.git
```
`exporterUrl` is derived from this repo's `origin` URL by substituting the repo name with `Exporter`
(SSH-scp, ssh://, https:// with and without `.git` all handled), defaulting to
`https://github.com/VibesQuest/Exporter.git` (git.lua:8-9, 59-93).

`toc-database/.gitignore` — generated output is not committed:
```
~*
{*}

*.log

v1

QuestieDB
GetterDB

data/
```

#### `toc-database/src/config.lua` — versions block (STALE interface numbers)

```lua
config.versions = {
  { suffix = "Vanilla", interface = "11508", major = 1 },
  { suffix = "BCC",     interface = "20504", major = 2 },
  { suffix = "WOTLKC",  interface = "30404", major = 3 },
}
```

`Getters/src/config.lua`:

```lua
config.versions = {
  { suffix = "Vanilla", interface = "11508", dir = "Era" },
  { suffix = "BCC",     interface = "20504", dir = "Tbc" },
  { suffix = "WOTLKC",  interface = "30404", dir = "Wotlk" },
  { suffix = "Cata",    interface = "40402", dir = "Cata" },
  { suffix = "Mists",   interface = "50500", dir = "Mop" },
}
```

**Both are wrong for TBC, Wrath, and Mists.** See §7.

### 6.3 `toc-database/test.lua` — QUOTED IN FULL (279 lines, the file being ported)

```lua
-- test.lua
-- End-to-end decoder test with mocked WoW API against VibeQuest exporter output.
-- Usage: lua test.lua [Vanilla|BCC|WOTLKC] [split|combined|support]

if not loadstring then loadstring = load end

local lib = dofile("src/lib.lua")
local config = dofile("src/config.lua")

local versions = {}
for _, version in ipairs(config.versions) do versions[version.suffix] = version end

local types = {
  {
    name = "Item", addonName = "{ItemDB}", tableFile = "itemDB.lua", global = "ItemDB",
    getters = { "name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags", "foodType", "itemLevel", "requiredLevel", "ammoType", "class", "subClass", "vendors", "relatedQuests", "teachesSpell" },
  },
  {
    name = "Npc", addonName = "{NpcDB}", tableFile = "npcDB.lua", global = "NpcDB",
    getters = { "name", "minLevel", "maxLevel", "rank", "spawns", "waypoints", "questStarts", "questEnds", "react", "subName", "npcFlags" },
  },
  {
    name = "Object", addonName = "{ObjectDB}", tableFile = "objectDB.lua", global = "ObjectDB",
    getters = { "name", "questStarts", "questEnds", "spawns", "react", "waypoints" },
  },
  {
    name = "Quest", addonName = "{QuestDB}", tableFile = "questDB.lua", global = "QuestDB",
    getters = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "objectivesText", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "reputationReward", "breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredEvents" },
  },
}

local versionName = arg[1] or "Vanilla"
local packageMode = arg[2] or "split"
local ver = versions[versionName]
if not ver or (packageMode ~= "split" and packageMode ~= "combined" and packageMode ~= "support") then
  print("Usage: lua test.lua [Vanilla|BCC|WOTLKC] [split|combined|support]")
  os.exit(1)
end

local function sourcePath(fileName)
  return string.format("%s/v%d/vibequest/%s", config.sourceRoot, ver.major, fileName)
end

local function loadSource(fileName)
  local data = dofile(sourcePath(fileName))
  if type(data) ~= "table" then error(fileName .. " did not return table") end
  return data
end

local function l10nConfig(typeName)
  for _, cfg in ipairs(config.l10n.types) do
    if cfg.prefix == typeName then return cfg end
  end
end

local function extractLocale(raw, locale)
  local meta = loadSource(config.l10n.metaFile)
  local localeIndex
  for i, loc in ipairs(meta.locales or {}) do
    if loc == locale then localeIndex = i; break end
  end
  if not localeIndex then return nil end

  local separator = meta.separator or "‡"
  local pattern = "^"
  for i = 1, localeIndex do
    pattern = pattern .. (i == localeIndex and "(.-)" or ".-")
    pattern = pattern .. (i == #(meta.locales or {}) and "$" or separator)
  end

  local value = raw:match(pattern)
  if value and value ~= "" then return value end
end

local function versionedSupportFileName(fileName, version)
  return fileName:gsub("%.lua$", "") .. "-" .. version.suffix .. ".lua"
end

local function clearSupportGlobals()
  AreaToUiMapDB = nil
  ZoneOrSortDB = nil
  EventQuestDB = nil
  DungeonLookupDB = nil
  MapIdToUiMapDB = nil
  ProfessionMetaDB = nil
end

local function loadSupportFiles(baseDir, versioned)
  clearSupportGlobals()
  for _, supportFile in ipairs(config.supportDb.files) do
    local loadName = versioned and versionedSupportFileName(supportFile.luaFile, ver) or supportFile.luaFile
    assert(loadfile(baseDir .. "/" .. loadName))(config.supportDb.addonName)
  end
end

local function snapshotSupport()
  local questSortNames = ZoneOrSortDB.GetQuestSortNames()
  local questSortId = next(questSortNames)
  local eventAll = EventQuestDB.GetAll()
  local eventId = next(eventAll)
  local dungeonAll = DungeonLookupDB.GetAll()
  local dungeonId = next(dungeonAll)
  local mapAll = MapIdToUiMapDB.GetAll()
  local mapId = next(mapAll)
  local professionAll = ProfessionMetaDB.GetAll()
  local professionId = next(professionAll.professions)

  return {
    areaAll = AreaToUiMapDB.GetAll(),
    areaSample = AreaToUiMapDB.Get(12),
    zoneOrSortNames = questSortNames,
    zoneOrSortNegativeName = ZoneOrSortDB.GetName(-questSortId, "deDE"),
    zoneOrSortPositiveName = ZoneOrSortDB.GetName(12),
    zoneOrSortZeroName = ZoneOrSortDB.GetName(0),
    eventAll = eventAll,
    eventSample = EventQuestDB.Get(eventId),
    eventRelation = EventQuestDB.EventRelation,
    eventVisible = EventQuestDB.IsEventPointVisible({1}, function(id) return id == 1 end),
    dungeonAll = dungeonAll,
    dungeonSample = DungeonLookupDB.Get(dungeonId),
    mapAll = mapAll,
    mapSample = MapIdToUiMapDB.Get(mapId),
    professionAll = professionAll,
    professionSample = ProfessionMetaDB.GetProfession(professionId),
  }
end

print("Testing: " .. versionName .. " (" .. packageMode .. ")")
print("")

local allMeta = {}
if packageMode == "combined" then
  allMeta[config.combined.addonName] = lib.loadTOC(config.combined.addonName .. "/" .. config.combined.addonName .. "-" .. ver.suffix .. ".toc")
elseif packageMode == "split" then
  allMeta[config.l10n.addonName] = lib.loadTOC(config.l10n.addonName .. "/" .. config.l10n.addonName .. "-" .. ver.suffix .. ".toc")
  for _, t in ipairs(types) do
    allMeta[t.addonName] = lib.loadTOC(t.addonName .. "/" .. t.addonName .. "-" .. ver.suffix .. ".toc")
  end
end

C_AddOns = {
  GetAddOnMetadata = function(addon, key)
    local meta = allMeta[addon]
    return meta and meta[key]
  end
}
GetLocale = function() return "enUS" end
GetTimePreciseSec = function() return os.clock() end
C_Map = {
  GetAreaInfo = function(areaId) return "Area " .. tostring(areaId) end,
}

if packageMode == "combined" then
  assert(loadfile(config.combined.addonName .. "/l10n.lua"))(config.combined.addonName)
  for _, t in ipairs(types) do assert(loadfile(config.combined.addonName .. "/" .. t.name .. ".lua"))(config.combined.addonName) end
  loadSupportFiles(config.combined.addonName, true)
elseif packageMode == "split" then
  assert(loadfile(config.l10n.addonName .. "/Get.lua"))(config.l10n.addonName)
  for _, t in ipairs(types) do assert(loadfile(t.addonName .. "/Get.lua"))(t.addonName) end
end
print("")

local totalErrors = 0
local function report(label, errors, detail)
  local status = errors == 0 and "PASS" or "FAIL"
  print(string.format("[%s] %s: %s", status, label, detail))
  totalErrors = totalErrors + errors
end

local function compare(label, expected, got, errors)
  if not lib.deepEqual(expected, got) then
    errors.count = errors.count + 1
    if errors.count <= 5 then
      io.write("  MISMATCH ", label, ":\n")
      io.write("    expected: ", lib.show(expected):sub(1, 120), "\n")
      io.write("    got:      ", lib.show(got):sub(1, 120), "\n")
    end
  end
end

local function testSupportGlobals(label, addonDir)
  loadSupportFiles(config.sourceRoot .. "/v" .. ver.major .. "/vibequest", false)
  local expected = snapshotSupport()
  loadSupportFiles(addonDir, true)
  local got = snapshotSupport()
  local errors = { count = 0 }
  compare(label, expected, got, errors)
  report(label .. " globals", errors.count, string.format("%d errors", errors.count))
end

if packageMode == "support" then
  testSupportGlobals("SupportDB", config.supportDb.addonName)
else
  for _, t in ipairs(types) do
    local source = loadSource(t.tableFile)
    local db = _G[t.global]
    local errors = { count = 0 }
    local entries, fields, named = 0, 0, 0

    for id, row in pairs(source) do
      entries = entries + 1
      for fieldIdx, original in pairs(row) do
        if type(fieldIdx) == "number" and original ~= nil and original ~= "" then
          fields = fields + 1
          compare(t.name .. ".Get(" .. id .. "," .. fieldIdx .. ")", original, db.Get(id, fieldIdx), errors)
          local getterName = t.getters[fieldIdx]
          if getterName then
            named = named + 1
            compare(t.name .. "." .. getterName .. "(" .. id .. ")", original, db[getterName](id), errors)
          end
        end
      end
    end

    report(t.name .. ".Get + named getters", errors.count,
      string.format("%d entries, %d fields, %d named checks, %d errors", entries, fields, named, errors.count))

    local ids = {}
    for id in pairs(source) do ids[#ids + 1] = id end
    table.sort(ids)
    local idErrors = { count = 0 }
    compare(t.name .. ".GetAllIds()", ids, db.GetAllIds(), idErrors)
    local idMap = db.GetAllIds(true)
    for _, id in ipairs(ids) do
      if idMap[id] ~= true then idErrors.count = idErrors.count + 1; break end
    end
    report(t.name .. ".GetAllIds", idErrors.count, string.format("%d ids, %d errors", #ids, idErrors.count))
  end

  local l10nErrors = { count = 0 }
  local l10nCases = {
    { label = "ItemDB.name", typeName = "Item", db = ItemDB, dbGetter = "name", l10nGetter = "itemName", fieldName = "name" },
    { label = "NpcDB.name", typeName = "Npc", db = NpcDB, dbGetter = "name", l10nGetter = "npcName", fieldName = "name" },
    { label = "NpcDB.subName", typeName = "Npc", db = NpcDB, dbGetter = "subName", l10nGetter = "npcSubName", fieldName = "subName" },
    { label = "ObjectDB.name", typeName = "Object", db = ObjectDB, dbGetter = "name", l10nGetter = "objectName", fieldName = "name" },
    { label = "QuestDB.name", typeName = "Quest", db = QuestDB, dbGetter = "name", l10nGetter = "questName", fieldName = "title" },
    { label = "QuestDB.objectivesText", typeName = "Quest", db = QuestDB, dbGetter = "objectivesText", l10nGetter = "questObjectivesText", fieldName = "objectives", wrap = function(value) return { value } end },
  }

  for _, case in ipairs(l10nCases) do
    l10nDB.SetLocale("enUS")
    local sampleId, localized, base
    local cfg = l10nConfig(case.typeName)
    local source = loadSource(cfg.tableFile)
    local sourceField
    for _, field in ipairs(cfg.fields) do
      if field.name == case.fieldName then sourceField = field.sourceField; break end
    end

    for _, id in ipairs(l10nDB.GetAllIds(case.typeName)) do
      local row = source[id]
      local raw = cfg.scalar and row or (row and row[sourceField])
      localized = raw and extractLocale(raw, "deDE")
      if localized then
        sampleId = id
        l10nDB.SetLocale("enUS")
        base = case.db[case.dbGetter](id)
        break
      end
    end

    if not sampleId then
      l10nErrors.count = l10nErrors.count + 1
      io.write("  MISSING l10n sample for ", case.label, "\n")
    else
      l10nDB.SetLocale("deDE")
      compare(case.label .. " localized", case.wrap and case.wrap(localized) or localized, case.db[case.dbGetter](sampleId), l10nErrors)
      l10nDB.SetLocale("enUS")
      compare(case.label .. " enUS fallback", base, case.db[case.dbGetter](sampleId), l10nErrors)
    end
  end
  report("l10n overlays", l10nErrors.count, string.format("%d errors", l10nErrors.count))

  if packageMode == "combined" then
    testSupportGlobals("combined SupportDB", config.combined.addonName)
  end
end

os.exit(totalErrors == 0 and 0 or 1)
```

**What the port must carry over (test.lua contract):**
- `if not loadstring then loadstring = load end` — Lua 5.1/5.2+ shim at the very top.
- Argv: `arg[1]` = version suffix (defaults `"Vanilla"`), `arg[2]` = package mode (defaults
  `"split"`; one of `split|combined|support`). Bad input → usage + `os.exit(1)`.
- Mocked WoW globals, exactly four:
  ```lua
  C_AddOns = { GetAddOnMetadata = function(addon, key) ... end }
  GetLocale = function() return "enUS" end
  GetTimePreciseSec = function() return os.clock() end
  C_Map = { GetAreaInfo = function(areaId) return "Area " .. tostring(areaId) end }
  ```
  `GetAddOnMetadata` is backed by `lib.loadTOC()` which parses only `## X-...:` lines
  (`toc-database/src/lib.lua:117-129`).
- Addon files are loaded as `assert(loadfile(path))(addonName)` — the addon name is passed as the
  first vararg, mirroring WoW's `...` convention.
- The oracle is the raw exporter table at `data/output/v<major>/vibequest/<tableFile>.lua`; the
  test asserts `db.Get(id, fieldIdx)` and every named getter round-trip via `lib.deepEqual`.
- Skips `nil` and `""` fields: `if type(fieldIdx) == "number" and original ~= nil and original ~= ""`.
- Only the first 5 mismatches per bucket are printed (`if errors.count <= 5`), truncated to 120 chars.
- `GetAllIds()` must return a **sorted array**; `GetAllIds(true)` must return a set (`[id] = true`).
- l10n: locale strings are `‡`-separated per locale; locale order comes from
  `l10nMetaDB.lua`'s `meta.locales`, separator from `meta.separator` (default `"‡"`).
  `l10nDB.SetLocale(locale)` switches; enUS is the fallback baseline.
  `QuestDB.objectivesText` is wrapped in a table (`wrap = function(value) return { value } end`).
- Support DBs are validated by loading the raw exporter files and the generated versioned files and
  deep-comparing a snapshot of six globals: `AreaToUiMapDB`, `ZoneOrSortDB`, `EventQuestDB`,
  `DungeonLookupDB`, `MapIdToUiMapDB`, `ProfessionMetaDB`. Globals are nil'd between loads
  (`clearSupportGlobals`).
- Exit code: `os.exit(totalErrors == 0 and 0 or 1)`.

Prototype getter-name lists in `test.lua` are **prototype schema, not Questie schema** — do not
adopt the field orders above without checking against Questie's real DB layouts (recon 01/02).

### 6.4 `toc-database/src/lib.lua` helpers `test.lua` depends on

- `lib.loadTOC(tocPath)` — parses `^## (X%-[^:]+): (.+)$` into a table. **Only `X-`-prefixed keys.**
- `lib.deepEqual(a, b)` — recursive, both directions.
- `lib.show(v)` — Lua-literal-ish serializer for mismatch output.
- `lib.MAX_VALUE_LEN = 1000` + `lib.writeMetadata` — UTF-8-safe value splitting; long values are
  written as `## KEY: ~N~` followed by `## KEY-1:` … `## KEY-N:`.
- `lib.getRaw(meta, id, fieldIdx, prefix)` + `lib.N` — the offline `~N~` reassembly used by
  `verify.lua` (test.lua goes through the generated `Get.lua` instead).

---

## 7. Authoritative interface version strings (and provenance)

**Rule: take the numbers from `Questie/*.toc`. They are the only current values in this workspace.**

| Flavor | Interface string (use verbatim) | Where it came from | Patch it corresponds to |
| --- | --- | --- | --- |
| Classic Era (+ SoD, Hardcore, Anniversary Era) | `11508, 11509` | `Questie/Questie-Classic.toc:1` | 1.15.8 / 1.15.9 — `upload-wago.sh:22` says `"supported_classic_patch": "1.15.9"` |
| TBC Classic / Anniversary | `20506` | `Questie/Questie-BCC.toc:1` | 2.5.6 — `upload-wago.sh:23` `"supported_bc_patch": "2.5.6"` |
| Wrath Classic (incl. Titan Reforged) | `38000, 38001` | `Questie/Questie-WOTLKC.toc:1` | 3.80.0 / 3.80.1 — `upload-wago.sh:24` `"supported_wotlk_patch": "3.80.1"`, and `upload-cf.sh:21` comment "WotLK (3.80.1)" |
| Cataclysm Classic | `40402` | `Questie/Questie-Cata.toc:1` | 4.4.2 |
| Mists Classic | `50503, 50504` | `Questie/Questie-Mists.toc:1` | 5.5.3 / 5.5.4 — `upload-wago.sh:25` `"supported_mop_patch": "5.5.4"` |
| Unsupported-client fallback | `00000` | `Questie/Questie.toc:4` | n/a |

Corroborating / conflicting numbers found elsewhere in the workspace (**all stale or unrelated —
do not use**):

| Value | Location | Status |
| --- | --- | --- |
| `20504` | `Getters/src/config.lua:8`, `toc-database/src/config.lua:8` | STALE (2.5.4); real is `20506` |
| `30404` | `Getters/src/config.lua:9`, `toc-database/src/config.lua:9` | STALE — Wrath moved to the 38xxx numbering (`38000, 38001`) |
| `50500` | `Getters/src/config.lua:11` | STALE (5.5.0); real is `50503, 50504` |
| `11508` | `Getters`/`toc-database` config | correct but incomplete — missing `11509` |
| `40402` | `Getters/src/config.lua:10` | matches Questie |
| `11506,40402,110100,110105` | `Questie/Libs/HereBeDragons/HereBeDragons.toc:1` | third-party lib, includes Retail; ignore |
| `11403`, `11500`, `20501`, `30400`, `40400`, `50500` | `Questie/cli/validate-{era,localization,sod,tbc,wotlk,cata,mop}.lua` `GetBuildInfo()` mocks | test fixtures, intentionally old; NOT release targets |

CurseForge numeric `gameVersions` (opaque CF IDs, NOT interface numbers) —
`Questie/upload-cf.sh:21-28`:
```
# The order of the "gameVersions" below is: WotLK (3.80.1), Era/SoD, TBC, MoP
    "gameVersions": [16081, 16630, 16533, 16168],
```

**Recommended QuestieTDB `config.versions` table (correct values):**

```lua
config.versions = {
  { suffix = "Vanilla", interface = "11508, 11509", questieToc = "Questie-Classic.toc", flavor = "classic", projectId = 2  },
  { suffix = "TBC",     interface = "20506",        questieToc = "Questie-BCC.toc",     flavor = "bcc",     projectId = 5  },
  { suffix = "Wrath",   interface = "38000, 38001", questieToc = "Questie-WOTLKC.toc",  flavor = "wrath",   projectId = 11 },
  { suffix = "Cata",    interface = "40402",        questieToc = "Questie-Cata.toc",    flavor = "cata",    projectId = 14 },
  { suffix = "Mists",   interface = "50503, 50504", questieToc = "Questie-Mists.toc",   flavor = "mists",   projectId = 19 },
}
```

Better still: **derive** these at build time by reading `Questie/*.toc` line 1 with the same regex
`build.py` uses, so the two projects cannot drift.

---

## 8. Gotchas / traps for the implementer

1. **`build.py:103` has a missing path separator bug.**
   ```python
   questie_toc_path = release_addon_folder_path + toc
   ```
   `release_addon_folder_path` is `"releases/<dir>" + "/Questie"` (no trailing slash) and `toc` is
   `"Questie-Classic.toc"` → `"releases/<dir>/QuestieQuestie-Classic.toc"`. Only reached when
   `-v/--version` is passed; the CI path (`build.py -r`) never hits it. **Do not copy this line.**

2. **Cata is excluded from the default build set** (`build.py:82-87` appends 1,2,3,5) and from the
   `db-validation` matrix in `ci.yml` (`[era, sod, tbc, wotlk, mop, localization]`), and from both
   upload scripts. But `Questie-Cata.toc` exists and `get_interface_versions("Cata")` is called
   unconditionally at `build.py:117`. QuestieTDB must decide Cata's status explicitly.

3. **`get_interface_versions` requires `## Interface:` on line 1 and CWD = repo root.**
   `re.match` is anchored; a leading comment line (as in `Questie.toc`, where `## Interface:` is on
   line 4) would break it. `Questie.toc` is never passed to it, but a generated QuestieTDB TOC that
   opens with a `# generated by ...` comment WOULD break an equivalent parser.

4. **`ignorePatterns` matches basenames only.** `"Cata"` strips `Database/Cata` and
   `Localization/lookups/Cata`, but NOT `xpDB-cata.lua`, `cataQuestFixes.lua`,
   `cataItemDrops.lua`, `factionTemplateCata.lua`. Excluded-expansion data files still ship.

5. **`os.walk(".")` + `break` = no recursion.** Only the six whitelisted top-level directories and
   seven whitelisted top-level files are copied. Anything new at the repo root is silently omitted
   from releases unless added to `filesToInclude`/`directoriesToInclude`.

6. **`release.json` emits one entry per interface number, not per flavor.** A flavor with two
   interface numbers produces two `metadata` entries with the same `"flavor"` value.

7. **`flavorString[:-1]`** chops the last character to remove the trailing comma. Any change to the
   `flavor_entries` template's trailing character breaks the JSON.

8. **`"nolib": false` is hard-coded** in `build.py:146`. If QuestieTDB ever ships a `-nolib` variant
   it must emit a second release entry, not flip this flag.

9. **Beta detection is `*"-b"*` substring matching**, in three independent places with three
   different vocabularies: `publish.yml:41` (`--prerelease`), `upload-cf.sh:6-10`
   (`beta`/`release`), `upload-wago.sh:6-10` (`beta`/`stable`), plus `changelog.py:42`
   (previous-tag selection). A tag like `v1.2.3-bugfix` would be misclassified as a beta.

10. **`## RequiredDeps:` vs `## Dependencies:`** — Questie's TOCs use `RequiredDeps` (currently
    empty); the ADR and DESIGN prose say `Dependencies`. They are synonyms to WoW, but pick one
    spelling and use it everywhere so grep stays reliable.

11. **`## Interface: 00000`** in `Questie.toc` is a "never load" sentinel for the fallback stub.
    QuestieTDB's base `QuestieTDB.toc` is a *working* source-mode TOC and must NOT use `00000`.

12. **Prototype interface numbers are stale** (`20504`, `30404`, `50500`) — see §7. Copying
    `Getters/src/config.lua` or `toc-database/src/config.lua` wholesale ships out-of-date TOCs.

13. **Prototype suffixes are legacy** (`-BCC`, `-WOTLKC`, hyphen-separated). QuestieTDB uses
    underscore + modern names: `_Vanilla`, `_TBC`, `_Wrath`, `_Cata`, `_Mists`
    (`QuestieTDB/DESIGN.md:229-244`).

14. **`toc-database/LOCAL.bat` is 100% `@REM`-commented** — it is documentation, not a script, and
    is byte-identical to `Getters/LOCAL.bat`.

15. **`lib.loadTOC` only reads `X-`-prefixed keys** (`^## (X%-[^:]+): (.+)$`). Any non-`X-` metadata
    (a contract-version directive, for instance) is invisible to the test harness unless the regex
    is widened. WoW's real `GetAddOnMetadata` returns any `X-*` key; non-`X-` keys are only
    available through dedicated APIs.

16. **`ci.yml`'s `workflow_call` inputs are declared but never used** in the job bodies. Copying the
    file will carry dead inputs.

17. **`Getters/` has no `main.lua` and no `git.lua`** — the one-command runner and the exporter
    refresh live only in `toc-database/`. If porting "the richer prototype", these two files must
    come from `toc-database/`.

18. **`busted -p ".test.lua" .`** is Questie's unit-test invocation; test files are named
    `<name>.test.lua` and `build.py` strips them via `ignorePatterns = ["*.test.lua"]`. Keep that
    naming convention so the same one-line exclusion works.

19. **Action versions are pinned and dependabot-managed** (`actions/checkout@v7.0.0`,
    `actions/upload-artifact@v7.0.1`, `leafo/gh-actions-lua@v13.0.0`,
    `leafo/gh-actions-luarocks@v6.1.0`, `nebularg/actions-luacheck@v1.1.2`,
    `nebularg/actions-discord-webhook@v1.0.0`, `github/issue-labeler@v3.4`). `.github/dependabot.yml`
    watches `github-actions` in `/` weekly.

20. **Secrets consumed:** `CF_API_TOKEN`, `WAGO_API_TOKEN`, `DISCORD_WEBHOOK` (plus `github.token`
    as `GH_TOKEN`). CurseForge project id `334372`; Wago project id `qv634BKb`. Both also appear as
    `## X-Curse-Project-ID: 334372` / `## X-Wago-ID: qv634BKb` in every real Questie TOC — QuestieTDB
    will need its own pair.

21. **`Questie/.gitignore` ignores `releases/`, `CHANGELOG.md`, `response.txt`, `*.log`, `*.zip`.**
    CHANGELOG.md is generated per-release and never committed. QuestieTDB additionally must gitignore
    the generated suffixed TOCs (`DESIGN.md:248`: "`QuestieTDB_Vanilla.toc` etc. (gitignored,
    generated)").

22. **`.gitattributes` forces LF** (`* text=lf`, plus explicit `*.lua *.toc *.xml *.py *.json text`;
    `*.png *.jpg *.exe *.tga *.blp binary`). Generated TOCs written with `\n` are consistent; a
    Windows generator emitting `\r\n` would fight this.

---

## 9. File index (absolute paths)

```
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie-Classic.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie-BCC.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie-WOTLKC.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie-Cata.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/Questie-Mists.toc
/home/logon/projects/Questie-clones/Questie-toc/Questie/build.py
/home/logon/projects/Questie-clones/Questie-toc/Questie/release.py
/home/logon/projects/Questie-clones/Questie-toc/Questie/changelog.py
/home/logon/projects/Questie-clones/Questie-toc/Questie/upload-cf.sh
/home/logon/projects/Questie-clones/Questie-toc/Questie/upload-wago.sh
/home/logon/projects/Questie-clones/Questie-toc/Questie/.github/workflows/ci.yml
/home/logon/projects/Questie-clones/Questie-toc/Questie/.github/workflows/publish.yml
/home/logon/projects/Questie-clones/Questie-toc/Questie/.github/workflows/issue_labeler.yml
/home/logon/projects/Questie-clones/Questie-toc/Questie/.github/labeler.yml
/home/logon/projects/Questie-clones/Questie-toc/Questie/.github/dependabot.yml
/home/logon/projects/Questie-clones/Questie-toc/Questie/.gitignore
/home/logon/projects/Questie-clones/Questie-toc/Questie/.gitattributes
/home/logon/projects/Questie-clones/Questie-toc/Questie/.vscode/tasks.json
/home/logon/projects/Questie-clones/Questie-toc/Questie/.dockerfiles/{Dockerfile,docker-compose.yml,setup.sh}
/home/logon/projects/Questie-clones/Questie-toc/Questie/Modules/Expansions.lua
/home/logon/projects/Questie-clones/Questie-toc/Questie/cli/loadTOC.lua
/home/logon/projects/Questie-clones/Questie-toc/Questie/cli/validate-{era,sod,tbc,wotlk,cata,mop,localization}.lua
/home/logon/projects/Questie-clones/Questie-toc/Questie/docs/adr/0001-questie-as-database-consumer.md
/home/logon/projects/Questie-clones/Questie-toc/Questie/AGENTS.md   (build/lint/test commands, lines 25-46)
/home/logon/projects/Questie-clones/Questie-toc/toc-database/LOCAL.bat
/home/logon/projects/Questie-clones/Questie-toc/toc-database/main.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/git.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/generate.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/verify.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/test.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/src/config.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/src/lib.lua
/home/logon/projects/Questie-clones/Questie-toc/toc-database/.gitignore
/home/logon/projects/Questie-clones/Questie-toc/toc-database/README.md
/home/logon/projects/Questie-clones/Questie-toc/Getters/src/config.lua
/home/logon/projects/Questie-clones/Questie-toc/Getters/generate.lua
/home/logon/projects/Questie-clones/Questie-toc/Getters/LOCAL.bat   (identical to toc-database's)
/home/logon/projects/Questie-clones/Questie-toc/QuestieTDB/DESIGN.md  (§"Two runtime modes" L229-256, §"Packaging and release" L491-520)
```
