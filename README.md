can use [sm-ripext](https://github.com/ErikMinekus/sm-ripext) or SteamWorks [[1](https://github.com/KyleSanderson/SteamWorks/releases)][[2](https://users.alliedmods.net/~kyles/builds/SteamWorks/)] + [sm-json](https://github.com/clugg/sm-json)

config location is at `cstrike/cfg/sourcemod/plugin.wrsj.cfg`

just change the `#define USE_RIPEXT 1` to `#define USE_RIPEXT 0` if you want to use the SteamWorks+sm-json one.
- ^ you should use `#define USE_RIPEXT 0` on Windows because sm-ripext/curl have an bug that returns partial data
