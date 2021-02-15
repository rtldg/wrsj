#include <sourcemod>
#include <convar_class>
#include <adt_trie> // StringMap

#define USE_RIPEXT 1
#if USE_RIPEXT
#include <ripext> // https://github.com/ErikMinekus/sm-ripext
#else
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#endif

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION 1.0
#define USERAGENT "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.47 Safari/537.36 wrsj/1.0 (https://github.com/rtldg/wrsj)"

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

enum struct RecordInfo {
	int id;
	char name[MAX_NAME_LENGTH];
	//char country[];
	//char mapname[90]; // longest map name I've seen is bhop_pneumonoultramicroscopicsilicovolcanoconiosis_v3_001.bsp
	char hostname[111];
	char time[13];
	char wrDif[13];
	char steamid[20];
	//int tier;
	char date[11]; // eventually increase?
	float sync;
	int strafes;
	int jumps;
}

StringMap gS_Maps;
StringMap gS_MapsCachedTime;

char gS_MapName[MAXPLAYERS + 1][128];

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
	gS_MapsCachedTime = new StringMap();

	AutoExecConfig();
}

void BuildWRSJMenu(int client, char[] mapname)
{
	ArrayList records;
	gS_Maps.GetValue(mapname, records);

	int maxrecords = gCV_SourceJumpWRCount.IntValue;
	maxrecords = (maxrecords < records.Length) ? maxrecords : records.Length;

	Menu menu = new Menu(Handler_WRSJMenu, MENU_ACTIONS_ALL);
	menu.SetTitle("SourceJump WR\n%s - Showing %i best", mapname, maxrecords);

	for (int i = 0; i < maxrecords; i++)
	{
		RecordInfo record;
		records.GetArray(i, record, sizeof(record));

		char line[128];
		FormatEx(line, sizeof(line), "#%d - %s - %s (%d Jumps)", i+1, record.name, record.time, record.jumps);

		char info[192];
		FormatEx(info, sizeof(info), "%d;%s", record.id, mapname);
		menu.AddItem(info, line);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];

		FormatEx(sMenuItem, 64, "No records");
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_WRSJMenu(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		int id;
		char mapname[128];
		char info[128];
		menu.GetItem(choice, info, 128);

		if (StringToInt(info) == -1)
		{
			delete menu;
			return 0;
		}

		char exploded[2][128];
		ExplodeString(info, ";", exploded, 2, 128, true);

		id = StringToInt(exploded[0]);
		mapname = exploded[1];
		gS_MapName[client] = mapname;


		RecordInfo record;
		ArrayList records;
		gS_Maps.GetValue(mapname, records);

		for (int i = 0; i < records.Length; i++)
		{
			records.GetArray(i, record, sizeof(record));
			if (record.id == id)
				break;
		}

		if (record.id != id)
		{
			delete menu;
			return 0;
		}

		Menu submenu = new Menu(SubMenu_Handler);

		char display[160];

		FormatEx(display, sizeof(display), "%s %s", record.name, record.steamid);
		submenu.SetTitle(display);

		FormatEx(display, sizeof(display), "Time: %s (%s)", record.time, record.wrDif);
		submenu.AddItem("-1", display);
		FormatEx(display, sizeof(display), "Jumps: %d", record.jumps);
		submenu.AddItem("-1", display);
		FormatEx(display, sizeof(display), "Strafes: %d (%.2f%%)", record.strafes, record.sync);
		submenu.AddItem("-1", display);
		FormatEx(display, sizeof(display), "Server: %s", record.hostname);
		submenu.AddItem("-1", display);

		submenu.ExitBackButton = true;
		submenu.ExitButton = true;
		submenu.Display(client, MENU_TIME_FOREVER);
	}

	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

int SubMenu_Handler(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Cancel && choice == MenuCancel_ExitBack)
	{
		BuildWRSJMenu(client, gS_MapName[client]);
		delete menu;
	}
}

#if USE_RIPEXT
void CacheMap(char[] mapname, JSONArray json)
#else
void CacheMap(char[] mapname, JSON_Array json)
#endif
{
	ArrayList records;

	if (gS_Maps.GetValue(mapname, records))
		records.Clear();
	else
		records = new ArrayList(sizeof(RecordInfo));

	gS_MapsCachedTime.SetValue(mapname, GetEngineTime(), true);
	gS_Maps.SetValue(mapname, records, true);

	for (int i = 0; i < json.Length; i++)
	{
#if USE_RIPEXT
		JSONObject record = view_as<JSONObject>(json.Get(i));
#else
		JSON_Object record = json.GetObject(i);
#endif

		RecordInfo info;
		info.id = record.GetInt("id");
		record.GetString("name", info.name, sizeof(info.name));
		record.GetString("hostname", info.hostname, sizeof(info.hostname));
		record.GetString("time", info.time, sizeof(info.time));
		record.GetString("steamid", info.steamid, sizeof(info.steamid));
		record.GetString("date", info.date, sizeof(info.date));
		record.GetString("wrDif", info.wrDif, sizeof(info.wrDif));
		info.sync = record.GetFloat("sync");
		info.strafes = record.GetInt("strafes");
		info.jumps = record.GetInt("jumps");

		records.PushArray(info, sizeof(info));

#if USE_RIPEXT
		delete record;
#else
		// ???
#endif
	}
}

#if USE_RIPEXT
void RequestCallback(HTTPResponse response, DataPack pack, const char[] error)
#else
void ResponseBodyCallback(const char[] data, DataPack pack, int datalen)
#endif
{
	pack.Reset();

	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	char mapname[160];
	pack.ReadString(mapname, sizeof(mapname));

	CloseHandle(pack);

#if USE_RIPEXT
	//PrintToChat(client, "status = %d, error = '%s'", response.Status, error);
	if (response.Status != HTTPStatus_OK)
	{
		if (client != 0)
			PrintToChat(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	JSONArray records = view_as<JSONArray>(response.Data);
#else
	JSON_Array records = view_as<JSON_Array>(json_decode(data));
	if (records == null)
	{
		if (client != 0)
			ReplyToCommand(client, "WRSJ: bbb");
		LogError("WRSJ: bbb");
		return;
	}
#endif

	CacheMap(mapname, records);
	if (client != 0)
		BuildWRSJMenu(client, mapname);
}

#if !USE_RIPEXT
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
#endif

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

	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	pack.WriteString(mapname);

	StrCat(apiurl, sizeof(apiurl), mapname);
	//ReplyToCommand(client, "url = %s", apiurl);

#if USE_RIPEXT
	HTTPClient http = new HTTPClient(apiurl);
	http.SetHeader("api-key", apikey);
	//http.SetHeader("user-agent", USERAGENT); // doesn't work :(
	http.Get("", RequestCallback, pack);
#else
	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl)) ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey) ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json") ||
	    !SteamWorks_SetHTTPRequestHeaderValue(request, "user-agent", USERAGENT) ||
	    !SteamWorks_SetHTTPRequestContextValue(request, pack) ||
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
#endif
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

	float cached_time;
	if (gS_MapsCachedTime.GetValue(mapname, cached_time))
	{
		if (cached_time > (GetEngineTime() - gCV_SourceJumpCacheTime.FloatValue))
		{
			BuildWRSJMenu(client, mapname);
			return Plugin_Handled;
		}
	}

	RetrieveWRSJ(client, mapname);
	return Plugin_Handled;
}
