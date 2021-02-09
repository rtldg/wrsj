/* Header files */
#include <sourcemod>
#include <convar_class>
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#include <adt_trie> // StringMap

/* Preprocessor directives */
#pragma semicolon 1
#pragma newdecls required

/* Global defines */
// Map of JSON objects with the mapname as the key.
//--- Question: Wouldn't it be better and easier with an enum struct instead? ---//
StringMap gS_Maps;

#define STRINGIFY_XD(%1) "%1"
#define PLUGIN_VERSION_X 1.0
#define PLUGIN_VERSION STRINGIFY_XD(PLUGIN_VERSION_X)
#define USERAGENT(%1) "wrsj-steamworks - version %1 (https://github.com/rtldg/wrsj)"

/* Global CVARs */
Convar gCV_SourceJumpAPIKey;
Convar gCV_SourceJumpAPIUrl;
Convar gCV_SourceJumpDelay;
Convar gCV_SourceJumpCacheSize;
Convar gCV_SourceJumpCacheTime;

/* Plugin information */
public Plugin myinfo = {
	name = "Sourcejump World Record",
	author = "rtldg / Nairda",
	description = "Grabs WRs from SourceJump's API",
	version = "1.0",
	url = "https://github.com/rtldg/wrsj"
}

public void OnPluginStart()
{
	gCV_SourceJumpAPIKey = new Convar("sj_api_key", "", "Replace with your unique api key.");
	gCV_SourceJumpAPIUrl = new Convar("sj_api_url", "", "Can be changed for testing.");
	gCV_SourceJumpDelay = new Convar("sj_api_delay", "1.0", "Minimum delay between requests to Sourcejump API.", 0, true, 0.5);
	gCV_SourceJumpCacheSize = new Convar("sj_api_cache_size", "12", "Number of maps to cache from Sourcejump API.");
	gCV_SourceJumpCacheTime = new Convar("sj_api_cache_time", "666.0", "How many seconds to cache a map from Sourcejump API.", 0, true, 5.0);

	RegConsoleCmd("sm_wrsj", Command_WRSJ, "View global world records from Sourcejump's API.");
	RegConsoleCmd("sm_sjwr", Command_WRSJ, "View global world records from Sourcejump's API.");

	gS_Maps = new StringMap();

	AutoExecConfig();
}

void BuildWRSJMenu(int client, char[] mapname)
{
	Menu menu = new Menu(Handler_WRSJMenu, MENU_ACTIONS_ALL);
	menu.SetTitle("SJWR: (Showing %i best):\nTime - Player", gCV_SourceJumpCacheSize.IntValue);

	// TODO: I'm guessing some for loop. I suck with menus.

	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_WRSJMenu(Menu menu, MenuAction action, int client, int choice)
{
	if(action == MenuAction_Select)
	{
		// TODO: Open menu with the stats of selected time (stats are inside of the array, eg. strafes, sync, date and all the other shit.
	}

	return 0;
}

public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid, DataPack map_packed)
{
	int client = GetClientOfUserId(userid);
	char mapname[160];

	map_packed.ReadString(mapname, sizeof(mapname));
	CloseHandle(map_packed);

	// TODO: Get API documentation so we can see if status code should be 200 even when no results.
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		if (client != 0)
		{
			ReplyToCommand(client, "WRSJ: Sourcejump API request failed");
		}

		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	// Cache results now...
	int size;
	if (!SteamWorks_GetHTTPResponseBodySize(request, size))
	{
		return;
	}

	char[] buf = new char[size+1];
	if (!SteamWorks_GetHTTPResponseBodyData(request, buf, size+1))
	{
		return;
	}

	JSON_Object map = json_decode(buf);
	if (map == null)
	{
		return;
	}

	JSON_Object cached_map;
	if (gS_Maps.GetValue(mapname, cached_map))
	{
		CloseHandle(cached_map);
		gS_Maps.SetValue(mapname, map);
		map.SetFloat("cached_time", GetEngineTime());
	}

	if (!IsValidClientIndex(client))
	{
		BuildWRSJMenu(client, mapname);
	}
}

void RetrieveWRSJ(int client, char[] mapname)
{
	int userid = GetClientUserId(client);
	char apikey[40];
	char apiurl[169];

	gCV_SourceJumpAPIKey.GetString(apikey, sizeof(apikey));
	gCV_SourceJumpAPIUrl.GetString(apiurl, sizeof(apiurl));

	if (apikey[0] == 0 || apiurl[0] == 0)
	{
		ReplyToCommand(client, "WRSJ: Sourcejump API key or URL is not set.");
		LogError("WRSJ: Sourcejump API key or URL is not set.");

		return;
	}

	DataPack pack = new DataPack();
	pack.WriteString(mapname);
	Handle request;

	if(!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl)) ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "apikey", apikey) ||
	    !SteamWorks_SetHTTPRequestGetOrPostParameter(request, "mapname", mapname) ||
	    !SteamWorks_SetHTTPRequestUserAgentInfo(request, USERAGENT(PLUGIN_VERSION_X)) ||
	    !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000) ||
	    !SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true) ||
	    !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback) ||
	    !SteamWorks_SetHTTPRequestContextValue(request, userid, pack) ||
	    !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(pack);
		CloseHandle(request);
		ReplyToCommand(client, "WRSJ: failed to setup & send HTTP request");
		LogError("WRSJ: failed to setup & send HTTP request");

		return;
	}
}

Action Command_WRSJ(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: !wrsj <mapname>");
		return Plugin_Handled;
	}

	if (!IsValidClientIndex(client))
	{
		return Plugin_Handled;
	}

	char mapname[160];
	GetCmdArg(1, mapname, sizeof(mapname));

	JSON_Object cached_map;
	if (gS_Maps.GetValue(mapname, cached_map))
	{
		float cached_time;
		cached_map.GetValue("cached_time", cached_time);

		// TODO: Double check the cache check isn't fucked.
		if (cached_time > (GetEngineTime() - gCV_SourceJumpCacheTime.FloatValue))
		{
			BuildWRSJMenu(client, mapname);
			return Plugin_Handled;
		}
	}

	RetrieveWRSJ(client, mapname);

	return Plugin_Handled;
}

// We don't want the -1 client id bug. Thank Volvo™ for this
stock bool IsValidClientIndex(int client)
{
	return (0 < client <= MaxClients);
}
