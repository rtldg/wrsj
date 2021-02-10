#include <sourcemod>
#include <convar_class>
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#include <adt_trie> // StringMap

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION 1.0
#define USERAGENT "wrsj 1.0 (https://github.com/rtldg/wrsj)"

public Plugin myinfo = {
	name = "Sourcejump World Record",
	author = "rtldg / Nairda",
	description = "Grabs WRs from Sourcejump's API",
	version = "1.0",
	url = "https://github.com/rtldg/wrsj"
}

Convar gCV_SourceJumpAPIKey;
Convar gCV_SourceJumpAPIUrl;
Convar gCV_SourceJumpDelay;
Convar gCV_SourceJumpCacheSize;
Convar gCV_SourceJumpCacheTime;
Convar gCV_SourceJumpWRCount;

// Map of JSON objects with the mapname as the key.
StringMap gS_Maps;

public void OnPluginStart()
{
	gCV_SourceJumpAPIKey = new Convar("sj_api_key", "", "Replace with your unique api key.");
	gCV_SourceJumpAPIUrl = new Convar("sj_api_url", "https://sourcejump.net/api/records/", "Can be changed for testing.");
	gCV_SourceJumpDelay = new Convar("sj_api_delay", "1.0", "Minimum delay between requests to Sourcejump API.", 0, true, 0.5);
	gCV_SourceJumpCacheSize = new Convar("sj_api_cache_size", "12", "Number of maps to cache from Sourcejump API.");
	gCV_SourceJumpCacheTime = new Convar("sj_api_cache_time", "666.0", "How many seconds to cache a map from Sourcejump API.", 0, true, 5.0);
	gCV_SourceJumpWRCount = new Convar("sj_api_wr_count", "10", "How many top times should be shown in the !wrsj menu.");

	RegConsoleCmd("sm_wrsj", Command_WRSJ, "View global world records from Sourcejump's API.");
	RegConsoleCmd("sm_sjwr", Command_WRSJ, "View global world records from Sourcejump's API.");

	gS_Maps = new StringMap();

	AutoExecConfig();
}

void BuildWRSJMenu(int client, char[] mapname)
{
	int maxrecords = gCV_SourceJumpWRCount.IntValue;

	JSON_Array wrs;
	if (!gS_Maps.GetValue(mapname, wrs))
	{
		PrintToChat(client, "WRSJ: Somehow failed to retrieve map records for menu...");
		LogError("WRSJ: Somehow failed to retrieve map records for menu...");
		return;
	}

	int wrs_length = wrs.Length;
	maxrecords = (maxrecords < wrs_length) ? maxrecords : wrs_length;

	Menu menu = new Menu(Handler_WRSJMenu, MENU_ACTIONS_ALL);
	menu.SetTitle("WRSJ: (Showing %i best):", maxrecords);

	for (int i = 0; i < maxrecords; i++)
	{
		JSON_Object record;
		char name[MAX_NAME_LENGTH];
		char time[16];

		if (!wrs.GetValue(i, record)
		 || !record.GetString("name", name, sizeof(name))
		 || !record.GetString("time", time, sizeof(time))
		)
		{
			CloseHandle(menu);
			PrintToChat(client, "WRSJ: asaaadfasdf");
			LogError("WRSJ: asaaadfasdf");
			return;
		}

		int id = record.GetInt("id");
		int jumps = record.GetInt("jumps");

		char line[128];
		FormatEx(line, sizeof(line), "#%d - %s - %s (%d Jumps)", i+1, name, time, jumps);

		char info[192];
		FormatEx(info, sizeof(info), "%d;%s", id, mapname);
		menu.AddItem(info, line);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		//FormatEx(sMenuItem, 64, "%T", "WRMapNoRecords", client);
		FormatEx(sMenuItem, 64, "No records");
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_WRSJMenu(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		// TODO: Open menu with the stats of selected time (stats are inside of the array, eg. strafes, sync, date and all the other shit.
		char display[192];
		//FormatEx
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void ResponseBodyCallback(const char[] data, DataPack pack, int datalen)
{
	pack.Reset();

	char mapname[160];
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	pack.ReadString(mapname, sizeof(mapname));
	CloseHandle(pack);

	JSON_Object map = json_decode(data);
	if (map == null)
	{
		if (client != 0)
			ReplyToCommand(client, "WRSJ: bbb");
		LogError("WRSJ: bbb");
		return;
	}

	JSON_Object cached_map;
	if (!gS_Maps.GetValue(mapname, cached_map))
	{
		CloseHandle(cached_map);
		map.SetFloat("cached_time", GetEngineTime());
		gS_Maps.SetValue(mapname, map);
	}

	if (client != 0)
		BuildWRSJMenu(client, mapname);
}

public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);

	ReplyToCommand(client, "bFailure = %d, bRequestSuccessful = %d, eStatusCode = %d", bFailure, bRequestSuccessful, eStatusCode);

	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		if (client != 0)
			ReplyToCommand(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, ResponseBodyCallback, pack);
}

void RetrieveWRSJ(int client, char[] mapname)
{
	int userid = GetClientUserId(client);
	char apikey[40];
	char apiurl[230];

	gCV_SourceJumpAPIKey.GetString(apikey, sizeof(apikey));
	gCV_SourceJumpAPIUrl.GetString(apiurl, sizeof(apiurl));

	if (apikey[0] == 0 || apiurl[0] == 0)
	{
		ReplyToCommand(client, "WRSJ: Sourcejump API key or URL is not set.");
		LogError("WRSJ: Sourcejump API key or URL is not set.");
		return;
	}

	StrCat(apiurl, sizeof(apiurl), mapname);

	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	pack.WriteString(mapname);
	Handle request;

	ReplyToCommand(client, "url = %s, key = %s", apiurl, apikey);
	//if (true) return;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl)) ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey) ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json") ||
	    !SteamWorks_SetHTTPRequestContextValue(request, pack) ||
	    !SteamWorks_SetHTTPRequestUserAgentInfo(request, USERAGENT) ||
	    !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000) ||
	//    !SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true) ||
	    !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback) ||
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

	if (client == 0 || IsFakeClient(client))// || !IsClientAuthorized(client))
		return Plugin_Handled;

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
